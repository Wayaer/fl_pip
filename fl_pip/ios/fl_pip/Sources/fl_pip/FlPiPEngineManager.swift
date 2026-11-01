import AVKit
import Flutter
import fl_multi_engine
import UIKit

/// 画中画引擎管理器。
///
/// 引擎的创建与销毁全部交给 fl_multi_engine：`present()` 按传入的 `name` 复用或补建引擎，
/// 并按 `destroyEngineOnDismiss` 决定关闭时是否销毁。非主引擎会把
/// `FlutterViewController` 渲染进系统画中画窗口；主引擎没有独立的 `FlutterEngine` 实例，
/// 改用占位媒体（纯黑画面）。
///
/// The PiP engine manager. Creation and destruction are delegated to fl_multi_engine; `present()`
/// reuses or creates the engine called `name` and decides on dismissal whether to destroy it.
/// Engines other than the main engine render their view controller in the PiP window; the main
/// engine has no standalone engine instance and falls back to placeholder media.
final class FlPiPEngineManager {
    static let shared = FlPiPEngineManager()

    private var presentToken = 0
    private var presentedEngineName: String?
    /// `present()` 关联的引擎名称；窗口关闭后引擎被保留时仍然记录。
    /// Name of the engine associated with `present()`; kept after the window closes when the
    /// engine is retained.
    private(set) var pipEngineName: String?
    private var destroyEngineOnDismiss = true
    private let destroyObserver: FlMultiEngineDestroyObserver

    /// `present()` 关联的引擎是否仍然存在，与窗口是否展示无关。
    /// Whether the engine associated with `present()` still exists, regardless of the window.
    var hasPresentedEngine: Bool {
        guard let name = pipEngineName else { return false }
        return FlMultiEngine.shared.status(name: name) != nil
    }

    private init() {
        destroyObserver = FlMultiEngineDestroyObserver { name in
            guard name == FlPiPEngineManager.shared.presentedEngineName else { return }
            FlPiPEngineManager.shared.engineDidDestroyExternally()
        }
        FlMultiEngine.shared.addDestroyObserver(destroyObserver)
    }

    /// 开启引擎画中画：按 `name` 获取（或补建）引擎、生成占位媒体、交给窗口层展示。
    ///
    /// Enables engine PiP: reuses or creates the engine called `name`, generates the placeholder
    /// media and presents the window.
    func present(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            let exception = FlPiPException(.invalidConfiguration, message: "The engine name must not be empty")
            result(exception.flutterError)
            return
        }
        guard FlPiPWindowManager.shared.isAvailable() else {
            result(FlPiPException(.notSupported, message: "Picture-in-picture is not supported").flutterError)
            return
        }
        FlPiPWindowManager.shared.resetIfNotVisible()
        guard FlPiPWindowManager.shared.owner == .none else {
            result(FlPiPException(.alreadyEnabled, message: "Picture-in-picture is already enabled").flutterError)
            return
        }

        let destroy = arguments["destroyEngineOnDismiss"] as? Bool ?? true
        guard let info = ensureEngine(name: name) else {
            result(FlPiPException(.engineCreationFailed, message: "Unable to create the engine \(name)").flutterError)
            return
        }
        if info.isMain && destroy {
            result(FlPiPException(.invalidConfiguration, message: "The main engine cannot be destroyed").flutterError)
            return
        }

        presentedEngineName = name
        pipEngineName = name
        destroyEngineOnDismiss = destroy

        // top / left 与宽高都是物理像素，由窗口层统一换算成 point。
        // top / left and the size are physical pixels converted to points by the window layer.
        let geometry = FlPiPWindowManager.Geometry(
            widthPx: number(arguments["width"]),
            heightPx: number(arguments["height"]),
            leftPx: number(arguments["left"]),
            topPx: number(arguments["top"])
        )

        // 主引擎没有独立的 FlutterEngine 实例，无法作为内容源渲染，继续使用占位媒体。
        // The main engine has no standalone FlutterEngine instance, so it keeps the placeholder.
        if info.isMain {
            presentPlaceholder(info: info, destroy: destroy, geometry: geometry, result: result)
            return
        }
        guard let engine = FlMultiEngine.shared.engine(named: name) else {
            finishPresentation()
            let message = "Unable to find the engine \(name)"
            result(FlPiPException(.engineNotFound, message: message).flutterError)
            return
        }
        let engineViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        if let exception = FlPiPWindowManager.shared.presentEngine(
            engineViewController: engineViewController,
            geometry: geometry,
            onStop: { [weak self] in self?.windowDidStop() }
        ) {
            finishPresentation()
            result(exception.flutterError)
            return
        }
        result(Self.map(info))
    }

    /// 主引擎兜底：使用占位媒体让系统画中画按请求的宽高比展示。
    ///
    /// Fallback for the main engine: show the system PiP window with the placeholder media.
    private func presentPlaceholder(
        info: FlMultiEngineInfo,
        destroy: Bool,
        geometry: FlPiPWindowManager.Geometry,
        result: @escaping FlutterResult
    ) {
        let name = info.name
        presentToken += 1
        let token = presentToken
        FlPiPPlaceholderMedia.shared.makePlayerLayer(
            widthPx: geometry.widthPx,
            heightPx: geometry.heightPx,
            muted: true
        ) { [weak self] playerLayer in
            guard let self = self else { return }
            guard self.presentToken == token else {
                // 被更新的 present 取消时，按本次的销毁标记清理已经创建的引擎，
                // 否则第一个引擎会在没有窗口的情况下残留。
                // A newer presentation cancelled this one; clean up the engine created here.
                if self.presentedEngineName != name, destroy {
                    self.destroyEngine(name: name)
                }
                result(FlPiPException(.startFailed, message: "The presentation was cancelled").flutterError)
                return
            }
            guard let playerLayer = playerLayer else {
                self.finishPresentation()
                result(
                    FlPiPException(
                        .videoAssetNotFound,
                        message: "Unable to generate the placeholder media"
                    ).flutterError
                )
                return
            }
            if let exception = FlPiPWindowManager.shared.present(
                owner: .engine,
                playerLayer: playerLayer,
                geometry: geometry,
                showControls: true,
                onStop: { [weak self] in self?.windowDidStop() }
            ) {
                FlPiPPlaceholderMedia.shared.stop()
                self.finishPresentation()
                result(exception.flutterError)
                return
            }
            result(Self.map(info))
        }
    }

    /// 关闭引擎画中画；按展示时的 `destroyEngineOnDismiss` 决定是否销毁引擎。
    /// Dismisses engine PiP, destroying the engine when requested at presentation time.
    func dismiss() {
        presentToken += 1
        FlPiPPlaceholderMedia.shared.stop()
        // 先等系统收起窗口并移除引擎的 FlutterViewController，再销毁引擎，
        // 避免在引擎仍挂载视图时销毁它。
        // Wait for the window to go away and the engine view to be removed before destroying it.
        if FlPiPWindowManager.shared.owner == .engine {
            FlPiPWindowManager.shared.dismiss { [weak self] in
                self?.finishPresentation()
                FlPiPWindowManager.shared.notifyStatusChanged()
            }
            return
        }
        finishPresentation()
        FlPiPWindowManager.shared.notifyStatusChanged()
    }

    private func windowDidStop() {
        FlPiPPlaceholderMedia.shared.stop()
        finishPresentation()
        FlPiPWindowManager.shared.notifyStatusChanged()
    }

    /// fl_multi_engine 销毁引擎时的回调：只关闭由引擎占用的画中画。
    /// Called when fl_multi_engine destroys the engine; only closes the engine-owned window.
    private func engineDidDestroyExternally() {
        presentToken += 1
        FlPiPPlaceholderMedia.shared.stop()
        presentedEngineName = nil
        destroyEngineOnDismiss = true
        if FlPiPWindowManager.shared.owner == .engine {
            FlPiPWindowManager.shared.dismiss()
        }
    }

    /// 结束当前展示：记录的名称与销毁标记先清空，再按标记处理引擎。
    ///
    /// Ends the current presentation: clears the recorded name and flag first, then handles the
    /// engine according to the dismissal flag.
    private func finishPresentation() {
        let name = presentedEngineName
        let shouldDestroy = destroyEngineOnDismiss
        presentedEngineName = nil
        destroyEngineOnDismiss = true
        if let name = name, shouldDestroy {
            destroyEngine(name: name)
        }
    }

    /// 返回已创建的引擎；不存在时用 `pipMain` 入口补建。 / Ensures the engine exists.
    private func ensureEngine(name: String) -> FlMultiEngineInfo? {
        if let info = FlMultiEngine.shared.status(name: name) {
            return info
        }
        do {
            return try FlMultiEngine.shared.create(name: name, entrypoint: "pipMain")
        } catch {
            print("FlPiP error: unable to create the engine \(name), \(error)")
            return nil
        }
    }

    private func destroyEngine(name: String) {
        if let engine = FlMultiEngine.shared.engine(named: name) {
            FlPiPChannelRegistry.shared.remove(messenger: engine.binaryMessenger)
        }
        do {
            _ = try FlMultiEngine.shared.destroy(name: name)
        } catch {
            print("FlPiP error: unable to destroy the engine \(name), \(error)")
        }
    }

    /// 把引擎信息转换成平台通道参数表；与 fl_multi_engine 的字段保持一致。
    /// Converts the engine info to the channel map, matching the fl_multi_engine fields.
    private static func map(_ info: FlMultiEngineInfo) -> [String: Any] {
        [
            "name": info.name,
            "entrypoint": info.entrypoint,
            "state": info.state,
            "createdAt": info.createdAt,
            "isMain": info.isMain,
        ]
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        return nil
    }
}
