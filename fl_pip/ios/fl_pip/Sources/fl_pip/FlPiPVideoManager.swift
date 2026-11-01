import AVFoundation
import AVKit
import Flutter
import UIKit

/// iOS 画中画视频播放层。
///
/// 只负责 AVPlayer 的播放、事件与参数控制；窗口的创建、启动、停止与状态由
/// [FlPiPWindowManager] 统一管理。
///
/// 网络视频会先用本地占位媒体启动画中画，等网络视频可播放后再替换当前播放项，
/// 这样首帧加载过程发生在画中画窗口内，而不是停在 App 页面。
///
/// Plays videos in the iOS PiP window. Only owns the AVPlayer and its events; the window itself
/// is managed by [FlPiPWindowManager].
final class FlPiPVideoManager {
    static let shared = FlPiPVideoManager()

    private final class Session {
        let player: AVPlayer
        var timeObserver: Any?
        var endObserver: NSObjectProtocol?
        var failureObserver: NSObjectProtocol?
        var itemStatusObservation: NSKeyValueObservation?
        var realItemObservation: NSKeyValueObservation?
        var playing = true
        var rate: Float = 1.0
        var volume: Float = 1.0
        var loop = false
        var startItem: AVPlayerItem?
        var realItem: AVPlayerItem?

        init(player: AVPlayer) {
            self.player = player
        }
    }

    private var session: Session?
    private var registrar: FlutterPluginRegistrar?
    private var playToken = 0

    private init() {}

    /// 保留第一个注册的 registrar，用于把 Flutter asset 解析成真实路径。
    /// Keeps the first registrar so Flutter assets can be resolved to real paths.
    func setRegistrar(_ registrar: FlutterPluginRegistrar) {
        if self.registrar == nil {
            self.registrar = registrar
        }
    }

    var isActive: Bool { session != nil }

    /// 播放视频并交给窗口层展示。 / Plays a video and hands the window to the window layer.
    func playVideo(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let source = mediaSource(arguments),
              let url = resolveMediaURL(type: source.type, uri: source.uri, packageName: source.packageName) else {
            let message = "Unable to resolve the video source"
            result(FlPiPException(.videoAssetNotFound, message: message).flutterError)
            return
        }
        guard FlPiPWindowManager.shared.isAvailable() else {
            result(FlPiPException(.notSupported, message: "Picture-in-picture is not supported").flutterError)
            return
        }
        FlPiPWindowManager.shared.resetIfNotVisible()
        guard session == nil, FlPiPWindowManager.shared.owner == .none else {
            let message = "Another PiP window is already visible"
            result(FlPiPException(.alreadyEnabled, message: message).flutterError)
            return
        }

        playToken += 1
        let token = playToken
        let muted = arguments["muted"] as? Bool ?? false
        let loop = arguments["loop"] as? Bool ?? false
        let geometry = FlPiPWindowManager.Geometry(
            widthPx: number(arguments["width"]),
            heightPx: number(arguments["height"]),
            leftPx: number(arguments["left"]),
            topPx: number(arguments["top"])
        )
        let showControls = (arguments["controls"] as? [String: Any])?["enabled"] as? Bool ?? true

        let realItem = AVPlayerItem(url: url)
        // 网络视频尽量立刻开始播放，不为凑够缓冲而阻塞首帧。
        // Start network playback as early as possible without waiting for a full buffer.
        realItem.preferredForwardBufferDuration = 0

        if source.type == "network" {
            FlPiPPlaceholderMedia.shared.makeItem(
                widthPx: geometry.widthPx,
                heightPx: geometry.heightPx
            ) { [weak self] placeholderItem in
                guard let self = self, self.playToken == token else {
                    result(FlPiPException(.startFailed, message: "The presentation was cancelled").flutterError)
                    return
                }
                self.startPlayback(
                    startItem: placeholderItem ?? realItem,
                    realItem: placeholderItem == nil ? nil : realItem,
                    muted: muted,
                    loop: loop,
                    geometry: geometry,
                    showControls: showControls,
                    result: result
                )
            }
            return
        }

        startPlayback(
            startItem: realItem,
            realItem: nil,
            muted: muted,
            loop: loop,
            geometry: geometry,
            showControls: showControls,
            result: result
        )
    }

    func setPlaying(_ playing: Bool) -> Bool {
        guard let session = session else { return false }
        session.playing = playing
        if playing {
            // 播放结束后再点播放需要先回到开头，否则 rate 设在末尾不会重新开始。
            // Restart from the beginning when playback already reached the end.
            if let duration = session.player.currentItem?.duration, !duration.isIndefinite,
               CMTimeCompare(session.player.currentTime(), duration) >= 0 {
                session.player.seek(to: .zero)
            }
            session.player.rate = session.rate
        } else {
            session.player.pause()
        }
        notifyEvent("playPause", playing: playing, action: playing ? "play" : "pause")
        return true
    }

    func seek(positionMs: Int) -> Bool {
        guard let session = session else { return false }
        // 与 Android / HarmonyOS 一致：位置限制在 [0, duration]。
        // Match Android / HarmonyOS: clamp the position to [0, duration].
        var targetMs = max(positionMs, 0)
        if let duration = session.player.currentItem?.duration, !duration.isIndefinite {
            targetMs = min(targetMs, milliseconds(duration))
        }
        let time = CMTime(value: CMTimeValue(targetMs), timescale: 1000)
        session.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        notifyPosition(time: time, action: "seek")
        return true
    }

    func seekBy(offsetMs: Int) -> Bool {
        guard let session = session else { return false }
        return seek(positionMs: milliseconds(session.player.currentTime()) + offsetMs)
    }

    func stopPlayback() -> Bool {
        guard let session = session else { return false }
        session.playing = false
        session.player.pause()
        session.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        notifyEvent("stop", playing: false, positionMs: 0, action: "pause")
        return true
    }

    func setRate(_ rate: Float) -> Bool {
        guard let session = session, rate > 0 else { return false }
        session.rate = rate
        if session.player.timeControlStatus == .playing {
            session.player.rate = rate
        }
        notifyEvent("speed", playing: session.playing)
        return true
    }

    func setVolume(_ volume: Float) -> Bool {
        guard let session = session else { return false }
        let clamped = min(max(volume, 0), 1)
        session.volume = clamped
        session.player.volume = clamped
        notifyEvent("volume", playing: session.playing)
        return true
    }

    func setLooping(_ loop: Bool) -> Bool {
        guard let session = session else { return false }
        session.loop = loop
        return true
    }

    func statusMap() -> [String: Any]? {
        guard let session = session else { return nil }
        var durationMs = 0
        if let duration = session.player.currentItem?.duration, !duration.isIndefinite {
            durationMs = milliseconds(duration)
        }
        let positionMs = milliseconds(session.player.currentTime())
        // 缓冲（waitingToPlayAtSpecifiedRate）也视为播放中，只有 paused 才是暂停；
        // 同时回写 session.playing，避免播放意图与上报状态分叉。
        // Waiting to play still counts as playing; keep session.playing in sync.
        let playing = session.player.timeControlStatus != .paused
        session.playing = playing
        return [
            "playing": playing,
            "positionMs": positionMs,
            "durationMs": durationMs,
            "speed": Double(session.rate),
            "volume": Double(session.volume),
        ]
    }

    /// 关闭视频窗口。 / Stops the video window.
    @discardableResult
    func stop() -> Bool {
        // 取消仍在生成占位媒体的网络视频播放请求。
        // Cancel a pending network presentation that is still preparing the placeholder.
        playToken += 1
        guard let session = session else { return false }
        // 先暂停并让窗口层收起画中画，等系统真正关闭后再释放播放项，
        // 避免画中画收起过程中播放项被清空导致窗口残留。
        // Pause first and release the item only after the window is gone.
        session.playing = false
        session.player.pause()
        if FlPiPWindowManager.shared.owner == .video {
            FlPiPWindowManager.shared.dismiss { [weak self] in self?.stopInternal(notifyClose: true) }
        } else {
            stopInternal(notifyClose: true)
        }
        return true
    }

    /// 系统面板快进/快退：跳转并上报 skip 事件。 / Handles system skip actions.
    func handleSkip(interval: CMTime, completion: @escaping () -> Void) {
        let seconds = CMTimeGetSeconds(interval)
        let action = seconds < 0 ? "rewind" : "forward"
        guard let session = session else {
            notifyEvent("skip", action: action)
            completion()
            return
        }
        let currentMs = milliseconds(session.player.currentTime())
        let offsetMs = seconds.isFinite ? Int(seconds * 1000) : 0
        let targetMs = max(0, currentMs + offsetMs)
        let time = CMTime(value: CMTimeValue(targetMs), timescale: 1000)
        session.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        var durationMs = 0
        if let duration = session.player.currentItem?.duration, !duration.isIndefinite {
            durationMs = milliseconds(duration)
        }
        notifyEvent(
            "skip",
            playing: session.playing,
            positionMs: targetMs,
            durationMs: durationMs,
            action: action
        )
        completion()
    }

    /// 建立播放会话；`realItem` 为网络视频的真实播放项，占位媒体就绪后替换。
    ///
    /// Creates the playback session. For network videos [realItem] is swapped in as soon as it is
    /// ready, so the placeholder only serves to start PiP immediately.
    private func startPlayback(
        startItem: AVPlayerItem,
        realItem: AVPlayerItem?,
        muted: Bool,
        loop: Bool,
        geometry: FlPiPWindowManager.Geometry,
        showControls: Bool,
        result: @escaping FlutterResult
    ) {
        guard session == nil, FlPiPWindowManager.shared.owner == .none else {
            let message = "Another PiP window is already visible"
            result(FlPiPException(.alreadyEnabled, message: message).flutterError)
            return
        }

        let player = AVPlayer(playerItem: startItem)
        player.volume = muted ? 0 : 1
        player.isMuted = muted
        // 网络视频卡顿时也要保持播放意图，由画中画展示缓冲画面。
        // Keep the playback intent while buffering so PiP shows the loading state.
        player.automaticallyWaitsToMinimizeStalling = false
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect

        let newSession = Session(player: player)
        newSession.loop = loop
        newSession.volume = player.volume
        newSession.startItem = startItem
        newSession.realItem = realItem
        session = newSession

        if let exception = FlPiPWindowManager.shared.present(
            owner: .video,
            playerLayer: playerLayer,
            geometry: geometry,
            showControls: showControls,
            onStop: { [weak self] in self?.windowDidStop() }
        ) {
            session = nil
            player.replaceCurrentItem(with: nil)
            result(exception.flutterError)
            return
        }

        observeItem(startItem, session: newSession)
        newSession.itemStatusObservation = startItem.observe(\.status, options: [.new]) { [weak self, weak newSession] observed, _ in
            guard observed.status == .failed else { return }
            // KVO 可能在后台线程触发，事件统一回到主线程上报。
            // KVO may fire on a background thread; report the event on the main thread.
            DispatchQueue.main.async { [weak self, weak newSession] in
                guard let self = self, let session = newSession, self.session === session else { return }
                guard session.player.currentItem === observed else { return }
                self.notifyEvent("error", playing: false)
            }
        }

        if let realItem = realItem, realItem !== startItem {
            newSession.realItemObservation = realItem.observe(\.status, options: [.new, .initial]) {
                [weak self, weak newSession] observed, _ in
                DispatchQueue.main.async { [weak self, weak newSession] in
                    guard let self = self, let session = newSession, self.session === session else { return }
                    switch observed.status {
                    case .readyToPlay:
                        self.swapToRealItem(observed, session: session)
                    case .failed:
                        self.notifyEvent("error", playing: false)
                    default:
                        break
                    }
                }
            }
        }

        newSession.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 1000),
            queue: .main
        ) { [weak self] time in
            self?.notifyPosition(time: time)
        }

        player.rate = newSession.rate
        notifyEvent("play", playing: true, action: "play")
        result(true)
    }

    /// 监听当前播放项的结束与失败事件。 / Observes end and failure events of the current item.
    private func observeItem(_ item: AVPlayerItem, session: Session) {
        session.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak session] _ in
            guard let self = self, let session = session, self.session === session else { return }
            if let startItem = session.startItem, item === startItem, session.realItem !== startItem {
                // 网络视频还没准备好：循环占位媒体，避免画中画因播放结束而关闭。
                // The network item is not ready yet; loop the placeholder to keep PiP open.
                session.player.seek(to: .zero)
                session.player.rate = session.playing ? session.rate : 0
                return
            }
            if session.loop {
                session.player.seek(to: .zero)
                session.player.rate = session.rate
            } else {
                session.playing = false
                self.notifyEvent("ended", playing: false, action: "pause")
            }
        }
        session.failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak session] _ in
            guard let self = self, let session = session, self.session === session else { return }
            guard session.player.currentItem === item else { return }
            self.notifyEvent("error", playing: false)
        }
    }

    /// 网络视频可播放后替换占位媒体，画中画保持打开。 / Swaps in the ready network item.
    private func swapToRealItem(_ item: AVPlayerItem, session: Session) {
        guard session.player.currentItem !== item else { return }
        if let observer = session.endObserver {
            NotificationCenter.default.removeObserver(observer)
            session.endObserver = nil
        }
        if let observer = session.failureObserver {
            NotificationCenter.default.removeObserver(observer)
            session.failureObserver = nil
        }
        session.player.replaceCurrentItem(with: item)
        observeItem(item, session: session)
        session.player.rate = session.playing ? session.rate : 0
    }

    /// 窗口被系统关闭时，只清理播放状态并上报 close。
    /// Clears playback when the system closes the window and reports `close`.
    private func windowDidStop() {
        stopInternal(notifyClose: true)
    }

    private func stopInternal(notifyClose: Bool) {
        guard let session = session else { return }
        session.player.pause()
        if let observer = session.timeObserver {
            session.player.removeTimeObserver(observer)
            session.timeObserver = nil
        }
        if let observer = session.endObserver {
            NotificationCenter.default.removeObserver(observer)
            session.endObserver = nil
        }
        if let observer = session.failureObserver {
            NotificationCenter.default.removeObserver(observer)
            session.failureObserver = nil
        }
        session.itemStatusObservation?.invalidate()
        session.itemStatusObservation = nil
        session.realItemObservation?.invalidate()
        session.realItemObservation = nil
        session.player.replaceCurrentItem(with: nil)
        self.session = nil
        if notifyClose {
            notifyEvent("close", action: "close")
        }
    }

    private func milliseconds(_ time: CMTime) -> Int {
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? Int(seconds * 1000) : 0
    }

    private func notifyPosition(time: CMTime, action: String = "progress") {
        guard let session = session else { return }
        let positionSeconds = CMTimeGetSeconds(time)
        let positionMs = positionSeconds.isFinite ? Int(positionSeconds * 1000) : 0
        // 直播/流媒体在时长确定前会返回 indefinite，直接 Int(NaN) 会崩溃。
        // Indefinite durations convert to NaN; Int(NaN) traps, so guard it explicitly.
        var durationMs = 0
        if let duration = session.player.currentItem?.duration, !duration.isIndefinite {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite {
                durationMs = Int(seconds * 1000)
            }
        }
        let playing = session.player.timeControlStatus == .playing
        if playing != session.playing {
            session.playing = playing
            notifyEvent("playPause", playing: playing, action: playing ? "play" : "pause")
        }
        notifyEvent(
            "position",
            playing: playing,
            positionMs: positionMs,
            durationMs: durationMs,
            action: action
        )
    }

    private func notifyEvent(
        _ event: String,
        playing: Bool? = nil,
        positionMs: Int? = nil,
        durationMs: Int? = nil,
        action: String? = nil
    ) {
        var payload: [String: Any] = ["event": event]
        if let playing = playing { payload["playing"] = playing }
        if let positionMs = positionMs { payload["positionMs"] = positionMs }
        if let durationMs = durationMs { payload["durationMs"] = durationMs }
        if let action = action { payload["action"] = action }
        FlPiPChannelRegistry.shared.broadcast(method: "onVideoEvent", arguments: payload)
    }

    /// 从 Dart 参数中读取视频来源：type、uri 与 packageName。
    /// Reads a video source (type, uri and packageName) from the Dart arguments.
    private func mediaSource(_ value: Any?) -> (type: String, uri: String, packageName: String?)? {
        guard let map = value as? [String: Any], let uri = map["uri"] as? String else { return nil }
        return (map["type"] as? String ?? "asset", uri, map["packageName"] as? String)
    }

    /// 按来源类型解析视频来源：network / file / Flutter asset。
    /// Resolves a video source by its type: network / file / Flutter asset.
    private func resolveMediaURL(type: String, uri: String, packageName: String?) -> URL? {
        switch type {
        case "network":
            return URL(string: uri)
        case "file":
            return uri.hasPrefix("file://") ? URL(string: uri) : URL(fileURLWithPath: uri)
        default:
            guard let path = resolveAssetPath(uri, packageName: packageName) else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    /// 把 Flutter asset 解析成 bundle 内的真实路径。
    ///
    /// [packageName] 为 `nil` 表示宿主 App 的资源；
    /// 调用方显式传入，避免意外回退到插件资源。
    ///
    /// Resolves a Flutter asset to its bundle path. A `nil` [packageName] means host app assets.
    private func resolveAssetPath(_ asset: String, packageName: String?) -> String? {
        guard let registrar = registrar else {
            return Bundle.main.path(forResource: asset, ofType: nil)
        }
        let key = packageName.map { registrar.lookupKey(forAsset: asset, fromPackage: $0) }
            ?? registrar.lookupKey(forAsset: asset)
        return Bundle.main.path(forResource: key, ofType: nil)
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

/// 供宿主 App 直接驱动 fl_pip 视频窗口的原生入口。
/// Native entry points for host apps that want to drive the fl_pip video window directly.
public enum FlPiPNative {
    /// 停止原生视频窗口。 / Stops the native video window.
    public static func stopVideo() {
        FlPiPVideoManager.shared.stop()
    }

    /// 是否已有视频窗口。 / Whether a video window is active.
    public static var isVideoActive: Bool { FlPiPVideoManager.shared.isActive }
}
