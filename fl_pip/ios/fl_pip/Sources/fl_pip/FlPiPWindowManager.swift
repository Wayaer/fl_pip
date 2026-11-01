import AVFoundation
import AVKit
import Flutter
import UIKit

/// 唯一的系统画中画窗口状态与控制器。
///
/// 引擎与视频都向本层申请展示；`owner` 决定当前窗口归谁使用，两套内容共享同一个
/// `AVPictureInPictureController` 与同一份状态通知。
///
/// - 视频使用 `AVPlayerLayer` 承载，App 内的内联预览层固定为 0.01pt 并放在左上角，
///   等同于不展示。
/// - 引擎使用 `AVPictureInPictureVideoCallViewController` 承载 FlutterViewController，
///   引擎画面会实时渲染进画中画窗口；App 内把它放在根视图最底层，因此不会显示。
///
/// The single system picture-in-picture window state and controller shared by the engine and
/// the video player.
final class FlPiPWindowManager: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = FlPiPWindowManager()

    /// 当前占用画中画窗口的一方。 / Who currently owns the PiP window.
    enum Owner {
        case none
        case engine
        case video
    }

    /// Dart 传入的物理像素几何，原生按屏幕缩放换算成 point。
    /// Physical-pixel geometry from Dart, converted to points by the screen scale.
    struct Geometry {
        let widthPx: CGFloat?
        let heightPx: CGFloat?
        let leftPx: CGFloat?
        let topPx: CGFloat?
    }

    private(set) var owner: Owner = .none
    private(set) var geometry: Geometry?

    private var controller: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var container: UIView?
    private var engineViewController: FlutterViewController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var stopHandler: (() -> Void)?
    private var isStopping = false
    /// 等待系统收起画中画期间暂存的状态；收起完成后统一清理。
    /// Kept until the system finishes dismissing the window, then cleaned up at once.
    private var dismissCompletion: (() -> Void)?
    private var dismissWorkItem: DispatchWorkItem?
    /// 系统未回调收起时的重试次数。 / Number of stop retries used when the system does not report.
    private var dismissAttempts = 0

    /// 启动画中画的轮询状态：网络视频在首帧到达前不可启动时继续等待。
    /// Retry state while starting PiP, used while a network video has no first frame yet.
    private var isStarting = false
    private var startAttempts = 0
    private let maxStartAttempts = 40
    private var startWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
    }

    func isAvailable() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// 申请展示视频画中画；返回异常，`nil` 表示成功。
    /// Requests video PiP; returns the error, `nil` meaning success.
    func present(
        owner: Owner,
        playerLayer: AVPlayerLayer,
        geometry: Geometry,
        showControls: Bool,
        onStop: @escaping () -> Void
    ) -> FlPiPException? {
        guard let window = keyWindow() else {
            print("FlPiP error: the host window is unavailable")
            return FlPiPException(.windowUnavailable, message: "The host window is unavailable")
        }
        do {
            try activateAudioSession()
        } catch {
            print("FlPiP error: unable to configure the audio session")
            return FlPiPException(.audioSessionFailed, message: "Unable to configure the audio session")
        }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            print("FlPiP error: unable to create AVPictureInPictureController")
            return FlPiPException(.controllerUnavailable, message: "Unable to create the PiP controller")
        }
        controller.delegate = self
        controller.requiresLinearPlayback = false
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
        }

        // 内联预览固定为 0.01pt 并放在左上角，App 内不会出现视频框。
        // Keep the inline preview at 0.01pt in the top-left corner so no video box shows in-app.
        let hidden = makeHiddenContainer()
        playerLayer.frame = hidden.bounds
        playerLayer.removeFromSuperlayer()
        hidden.layer.addSublayer(playerLayer)
        hostView(for: window).addSubview(hidden)

        self.owner = owner
        self.geometry = geometry
        self.controller = controller
        self.playerLayer = playerLayer
        self.container = hidden
        self.stopHandler = onStop

        beginStart()
        return nil
    }

    /// 申请把 Flutter 引擎渲染进画中画；返回异常，`nil` 表示成功。
    ///
    /// 使用 `AVPictureInPictureVideoCallViewController` 作为画中画内容源，把引擎的
    /// `FlutterViewController` 作为它的子控制器；画中画窗口会实时镜像引擎画面。
    ///
    /// Requests PiP for a Flutter engine. The engine view controller is embedded in an
    /// `AVPictureInPictureVideoCallViewController` content source so the PiP window mirrors the
    /// engine in real time.
    func presentEngine(
        engineViewController: FlutterViewController,
        geometry: Geometry,
        onStop: @escaping () -> Void
    ) -> FlPiPException? {
        guard let window = keyWindow(), let rootViewController = window.rootViewController else {
            print("FlPiP error: the host window is unavailable")
            return FlPiPException(.windowUnavailable, message: "The host window is unavailable")
        }
        do {
            try activateAudioSession()
        } catch {
            print("FlPiP error: unable to configure the audio session")
            return FlPiPException(.audioSessionFailed, message: "Unable to configure the audio session")
        }

        let contentSize = pipContentSize(geometry: geometry)
        let callViewController = FlPiPVideoCallViewController(contentViewController: engineViewController)
        callViewController.preferredContentSize = contentSize

        // 视频通话内容源只把内容控制器放进画中画窗口，不会出现在 App 页面上。
        // The video-call content source only places the content controller in the PiP window, so
        // nothing appears in the app page.
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: rootViewController.view,
            contentViewController: callViewController
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
        }

        self.owner = .engine
        self.geometry = geometry
        self.controller = controller
        self.pipViewController = callViewController
        self.engineViewController = engineViewController
        self.stopHandler = onStop

        beginStart()
        return nil
    }

    /// 主动停止窗口并清理状态；不会回调 owner。
    ///
    /// 停止时保留 controller 与播放层，直到系统真正收起画中画（或超时兜底）再清理。
    /// 这样在画中画正在弹出、尚未回调 `didStart` 时停止，也不会出现无人管理的残留窗口。
    ///
    /// Stops the window and clears the state without notifying the owner. The controller and
    /// player layer stay alive until the system finishes dismissing (or a timeout fires), so
    /// stopping while the window is still animating in cannot leave an orphaned PiP window.
    func dismiss(completion: (() -> Void)? = nil) {
        guard controller != nil || container != nil || pipViewController != nil || owner != .none else {
            completion?()
            return
        }
        // 已经在等待系统收起时只追加回调，避免重复请求并丢掉此前登记的回调。
        // Already waiting for the system: only append the callback.
        if isStopping {
            let pending = dismissCompletion
            dismissCompletion = {
                pending?()
                completion?()
            }
            return
        }
        // 还没真正向系统发起启动时无需等待，立即清理。
        // Nothing was handed to the system yet, so there is nothing to wait for.
        if controller?.isPictureInPictureActive != true, !isStarting {
            finishDismissal(completion: completion)
            return
        }
        isStopping = true
        dismissCompletion = completion
        dismissAttempts = 0
        startWorkItem?.cancel()
        startWorkItem = nil
        isStarting = false
        controller?.stopPictureInPicture()
        scheduleDismissTimeout()
    }

    /// 等待系统收起；超时后若窗口仍存在则重新请求停止，最多重试两次。
    ///
    /// Waits for the system. When it does not report in time and the window is still visible,
    /// requests the stop again, retrying at most twice.
    private func scheduleDismissTimeout() {
        let workItem = DispatchWorkItem { [weak self] in self?.handleDismissTimeout() }
        dismissWorkItem?.cancel()
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func handleDismissTimeout() {
        guard isStopping, let controller = controller, controller.isPictureInPictureActive else {
            finishDismissal(completion: nil)
            return
        }
        dismissAttempts += 1
        guard dismissAttempts <= 2 else {
            finishDismissal(completion: nil)
            return
        }
        controller.stopPictureInPicture()
        scheduleDismissTimeout()
    }

    /// 系统窗口实际不可见时兜底清理，例如用户点了系统面板的 X。
    /// Clears stale state when the system window is no longer visible, e.g. after the user taps X.
    func resetIfNotVisible() {
        // 正在等待系统收起时不能提前清理，否则 controller 被释放后窗口可能残留。
        // Do not clear the state while a dismissal is still in flight.
        guard !isStopping else { return }
        guard owner != .none, controller?.isPictureInPictureActive != true else { return }
        print("FlPiP: cleared stale system picture-in-picture state")
        let handler = stopHandler
        teardown()
        notifyStatusChanged()
        handler?()
    }

    /// 当前状态表，status 与 Dart 的 FlPiPStatus 对齐，`0` 展示、`1` 未展示、`2` 不支持。
    /// Status map aligned with the Dart FlPiPStatus enum.
    func statusMap() -> [String: Any] {
        // hasEngine 只反映 present() 关联的引擎是否仍存在，与窗口是否展示无关。
        // hasEngine only reflects whether the engine from present() still exists, regardless of
        // whether the window is visible.
        let hasEngine = FlPiPEngineManager.shared.hasPresentedEngine
        guard isAvailable() else {
            return ["status": 2, "hasEngine": hasEngine]
        }
        let active = owner != .none
        var map: [String: Any] = ["status": active ? 0 : 1, "hasEngine": hasEngine]
        if active {
            map["mode"] = "systemPip"
        }
        return map
    }

    /// 向所有引擎广播最新画中画状态。 / Broadcasts the latest PiP status to every engine.
    func notifyStatusChanged() {
        FlPiPChannelRegistry.shared.broadcast(method: "onPiPStatus", arguments: statusMap())
    }

    /// 系统面板的快进/快退交给视频层处理。 / Forwards system skip actions to the video layer.
    func skip(by interval: CMTime, completion: @escaping () -> Void) {
        guard owner == .video else {
            completion()
            return
        }
        FlPiPVideoManager.shared.handleSkip(interval: interval, completion: completion)
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isStarting = false
        startAttempts = 0
        // 窗口正在弹出时已经请求停止：立即收起，等 didStop 再清理。
        // A stop was requested while the window was animating in: close it right away.
        if isStopping {
            pictureInPictureController.stopPictureInPicture()
            return
        }
        notifyStatusChanged()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 主动停止时由这里完成清理；系统面板关闭时走下面的常规清理。
        // A manual stop finishes here; a close from the system panel uses the regular path.
        if isStopping {
            finishDismissal(completion: nil)
            return
        }
        guard controller != nil else { return }
        isStarting = false
        let handler = stopHandler
        teardown()
        notifyStatusChanged()
        handler?()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("FlPiP error: unable to start picture-in-picture, \(error.localizedDescription)")
        guard controller === pictureInPictureController else { return }
        if isStopping {
            finishDismissal(completion: nil)
            return
        }
        isStarting = false

        // 视频源本身失败时不再重试，直接结束窗口。
        // A failed video item is not retried; close the window instead.
        if owner == .video, let item = playerLayer?.player?.currentItem, item.status == .failed {
            let handler = stopHandler
            teardown()
            notifyStatusChanged()
            handler?()
            return
        }
        scheduleStartRetry()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // 画中画收起后直接回到 App 界面。
        // Returning from PiP simply restores the app.
        completionHandler(true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        skip(by: skipInterval, completion: completionHandler)
    }

    /// 先等待系统准备完成，再启动画中画。
    /// Waits for the system to become ready and then starts picture-in-picture.
    private func beginStart() {
        isStarting = false
        startAttempts = 0
        scheduleStartWorkItem(delay: 0.4)
    }

    private func scheduleStartRetry() {
        startAttempts += 1
        guard startAttempts <= maxStartAttempts else {
            let handler = stopHandler
            teardown()
            notifyStatusChanged()
            handler?()
            return
        }
        scheduleStartWorkItem(delay: 0.5)
    }

    private func scheduleStartWorkItem(delay: TimeInterval) {
        startWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptStart()
        }
        startWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func attemptStart() {
        guard let controller = controller, !isStopping else { return }
        if controller.isPictureInPictureActive {
            return
        }
        if controller.isPictureInPicturePossible {
            guard !isStarting else { return }
            isStarting = true
            controller.startPictureInPicture()
            scheduleStartWatchdog()
            return
        }
        scheduleStartRetry()
    }

    /// 系统在画中画关闭动画期间可能静默忽略启动请求：超时后复位标记并继续重试。
    /// The system may silently ignore a start request while PiP is still dismissing; reset the
    /// flag and keep retrying when no callback arrives in time.
    private func scheduleStartWatchdog() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isStarting, !self.isStopping, let controller = self.controller else { return }
            if controller.isPictureInPictureActive {
                return
            }
            self.isStarting = false
            self.scheduleStartRetry()
        }
        startWorkItem?.cancel()
        startWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    /// 完成主动停止：清理窗口状态并回调等待方。
    /// Finishes a manual stop: clears the window state and notifies the waiting caller.
    private func finishDismissal(completion: (() -> Void)?) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let pendingCompletion = dismissCompletion
        dismissCompletion = nil
        isStopping = false
        teardown()
        notifyStatusChanged()
        completion?()
        pendingCompletion?()
    }

    private func teardown() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        dismissCompletion = nil
        startWorkItem?.cancel()
        startWorkItem = nil
        controller?.delegate = nil
        controller = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        container?.removeFromSuperview()
        container = nil
        if let engineViewController = engineViewController {
            engineViewController.willMove(toParent: nil)
            engineViewController.view.removeFromSuperview()
            engineViewController.removeFromParent()
            self.engineViewController = nil
        }
        if let pipViewController = pipViewController {
            pipViewController.willMove(toParent: nil)
            pipViewController.view.removeFromSuperview()
            pipViewController.removeFromParent()
            self.pipViewController = nil
        }
        stopHandler = nil
        isStarting = false
        geometry = nil
        owner = .none
    }

    private func activateAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    /// 预览容器：尺寸变化时同步更新内部渲染层的 frame，旋转后画面不会错位。
    /// Preview container that resizes its sublayers together with the container.
    private final class PreviewContainer: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { sublayer in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                sublayer.frame = bounds
                CATransaction.commit()
            }
        }
    }

    /// 内联预览层固定为 0.01pt 并放在左上角，等同于隐藏。
    /// The inline preview is 0.01pt in the top-left corner, effectively hidden.
    private func makeHiddenContainer() -> UIView {
        let container = PreviewContainer(frame: CGRect(x: 0, y: 0, width: 0.01, height: 0.01))
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        return container
    }

    /// 把物理像素宽高换算成画中画内容尺寸；未传宽高时使用 16:9。
    /// Converts the physical-pixel size to the PiP content size, defaulting to 16:9.
    private func pipContentSize(geometry: Geometry) -> CGSize {
        let scale = UIScreen.main.scale
        if let width = geometry.widthPx, let height = geometry.heightPx {
            return CGSize(width: max(width / scale, 1), height: max(height / scale, 1))
        }
        if let width = geometry.widthPx {
            let pointWidth = max(width / scale, 1)
            return CGSize(width: pointWidth, height: pointWidth * 9 / 16)
        }
        return CGSize(width: 640, height: 360)
    }

    /// 把预览层挂到根视图上，跟随屏幕旋转布局；根视图不可用时退回窗口。
    /// Attaches the preview to the root view so it follows rotation.
    private func hostView(for window: UIWindow) -> UIView {
        window.rootViewController?.view ?? window
    }

    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    }
}

/// 画中画内容控制器：把引擎的 `FlutterViewController` 填满自己的视图。
///
/// 内容控制器只在系统画中画窗口中出现，不会占用 App 页面；系统要求内容始终铺满其 bounds。
///
/// Content controller that fills its view with the engine's `FlutterViewController`. It only
/// appears in the system PiP window and never occupies the app page.
private final class FlPiPVideoCallViewController: AVPictureInPictureVideoCallViewController {
    private let contentViewController: UIViewController
    private var isEmbedded = false

    init(contentViewController: UIViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !isEmbedded else { return }
        isEmbedded = true
        view.backgroundColor = .black
        addChild(contentViewController)
        contentViewController.view.frame = view.bounds
        contentViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentViewController.view)
        contentViewController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentViewController.view.frame = view.bounds
    }
}
