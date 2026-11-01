import Flutter
import Foundation
import fl_multi_engine

/// 引擎之间共享的 `fl_pip` 通道注册表。
///
/// 每个引擎注册一个同名通道；状态与视频事件会广播到所有通道，
/// `send` 只投递给 `present(name:)` 指定的画中画引擎，该引擎发送时回到主引擎。
///
/// Registry of the `fl_pip` channels shared by every engine. `send` only reaches the
/// picture-in-picture engine selected by `present(name:)`, whose own `send` goes back to the main
/// engine.
final class FlPiPChannelRegistry {
    static let shared = FlPiPChannelRegistry()

    private var channels: [ObjectIdentifier: FlutterMethodChannel] = [:]

    /// 主引擎的通道标识。主引擎没有独立的 `FlutterEngine` 实例，通道在 App 启动时最先注册。
    /// Identifier of the main engine channel; the main engine registers its plugins first at launch.
    private(set) var mainIdentifier: ObjectIdentifier?

    private init() {}

    @discardableResult
    func add(_ channel: FlutterMethodChannel, messenger: FlutterBinaryMessenger) -> ObjectIdentifier {
        let identifier = ObjectIdentifier(messenger as AnyObject)
        channels[identifier] = channel
        if mainIdentifier == nil {
            mainIdentifier = identifier
        }
        return identifier
    }

    func remove(messenger: FlutterBinaryMessenger) {
        channels.removeValue(forKey: ObjectIdentifier(messenger as AnyObject))
    }

    /// 返回引擎对应通道的标识。 / Returns the channel identifier of the engine.
    func identifier(for messenger: FlutterBinaryMessenger) -> ObjectIdentifier {
        ObjectIdentifier(messenger as AnyObject)
    }

    /// 向所有引擎广播原生事件。 / Broadcasts a native event to every engine.
    func broadcast(method: String, arguments: Any?) {
        channels.values.forEach { $0.invokeMethod(method, arguments: arguments) }
    }

    /// 把 `send` 投递给目标通道，返回送达数量。 / Delivers `send` to the target channel.
    @discardableResult
    func forward(arguments: [String: Any], to target: ObjectIdentifier?, excluding sender: ObjectIdentifier) -> Int {
        guard let target = target, target != sender, let channel = channels[target] else { return 0 }
        channel.invokeMethod("onMessage", arguments: arguments)
        return 1
    }
}

/// fl_pip 的 iOS 平台通道入口，只负责方法分派。
///
/// Platform channel entry point of fl_pip on iOS. It only dispatches method calls.
public class FlPiPPlugin: NSObject, FlutterPlugin {
    /// 在画中画使用的 `pipMain` 引擎上注册 App 生成的插件。
    ///
    /// 设置时同步转发给 fl_multi_engine，
    /// 宿主只设置 fl_pip 的回调即可让新引擎注册生成插件。
    ///
    /// Registers the generated app plugins on the `pipMain` engine. The callback is forwarded to
    /// fl_multi_engine so the host only needs to configure the fl_pip one.
    public static var pluginRegistrant: ((FlutterPluginRegistry) -> Void)? {
        didSet {
            guard let registrant = pluginRegistrant else {
                FlMultiEnginePlugin.pluginRegistrant = nil
                return
            }
            FlMultiEnginePlugin.pluginRegistrant = { engine in registrant(engine) }
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        FlPiPVideoManager.shared.setRegistrar(registrar)
        let messenger = registrar.messenger()
        let channel = FlutterMethodChannel(name: FlPiPChannel.name, binaryMessenger: messenger)
        let senderId = FlPiPChannelRegistry.shared.add(channel, messenger: messenger)
        channel.setMethodCallHandler { call, result in
            handle(call, result: result, senderId: senderId)
        }
    }

    /// 引擎销毁时移除该引擎的 `fl_pip` 通道。
    /// Removes the `fl_pip` channel of a destroyed engine.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        FlPiPChannelRegistry.shared.remove(messenger: registrar.messenger())
    }

    private static func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult,
        senderId: ObjectIdentifier
    ) {
        switch call.method {
        case "present":
            guard let arguments = call.arguments as? [String: Any] else {
                let message = "present arguments are missing"
                result(FlPiPException(.invalidConfiguration, message: message).flutterError)
                return
            }
            FlPiPEngineManager.shared.present(arguments: arguments, result: result)

        case "dismiss":
            FlPiPEngineManager.shared.dismiss()
            result(true)

        case "isActive":
            result(FlPiPWindowManager.shared.statusMap())

        case "available":
            result(FlPiPWindowManager.shared.isAvailable())

        case "toggle":
            // iOS 没有公开 API 让 App 主动进入后台。
            // iOS has no public API to send the app to the background.
            result(nil)

        case "send":
            guard let arguments = call.arguments as? [String: Any] else {
                result(FlPiPException(.invalidConfiguration, message: "send arguments are missing").flutterError)
                return
            }
            result(sendMessage(arguments: arguments, senderId: senderId))

        case "playVideo":
            guard let arguments = call.arguments as? [String: Any] else {
                let message = "playVideo arguments are missing"
                result(FlPiPException(.invalidConfiguration, message: message).flutterError)
                return
            }
            FlPiPVideoManager.shared.playVideo(arguments: arguments, result: result)

        case "stopVideo":
            result(FlPiPVideoManager.shared.stop())

        case "isVideoActive":
            result(FlPiPVideoManager.shared.isActive)

        case "setVideoPlaying":
            let arguments = call.arguments as? [String: Any]
            result(FlPiPVideoManager.shared.setPlaying(arguments?["playing"] as? Bool ?? false))

        case "seekVideo":
            let arguments = call.arguments as? [String: Any]
            result(FlPiPVideoManager.shared.seek(positionMs: arguments?["positionMs"] as? Int ?? 0))

        case "seekVideoBy":
            let arguments = call.arguments as? [String: Any]
            result(FlPiPVideoManager.shared.seekBy(offsetMs: arguments?["offsetMs"] as? Int ?? 0))

        case "stopVideoPlayback":
            result(FlPiPVideoManager.shared.stopPlayback())

        case "setVideoSpeed":
            let arguments = call.arguments as? [String: Any]
            result(FlPiPVideoManager.shared.setRate((arguments?["speed"] as? NSNumber)?.floatValue ?? 1))

        case "setVideoVolume":
            let arguments = call.arguments as? [String: Any]
            result(FlPiPVideoManager.shared.setVolume((arguments?["volume"] as? NSNumber)?.floatValue ?? 0))

        case "setVideoLooping":
            let arguments = call.arguments as? [String: Any]
            result(FlPiPVideoManager.shared.setLooping(arguments?["loop"] as? Bool ?? false))

        case "getVideoStatus":
            result(FlPiPVideoManager.shared.statusMap())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 投递消息：主引擎发往 `present(name:)` 指定的画中画引擎，该引擎发往主引擎。
    ///
    /// Delivers a message to the picture-in-picture engine, or back to the main engine when the
    /// picture-in-picture engine sends. Other engines never receive it.
    private static func sendMessage(arguments: [String: Any], senderId: ObjectIdentifier) -> Int {
        guard let name = FlPiPEngineManager.shared.pipEngineName else { return 0 }
        let registry = FlPiPChannelRegistry.shared
        var target: ObjectIdentifier?
        if let engine = FlMultiEngine.shared.engine(named: name) {
            target = registry.identifier(for: engine.binaryMessenger)
        } else if FlMultiEngine.shared.status(name: name)?.isMain == true {
            target = registry.mainIdentifier
        }
        if target == senderId {
            // 画中画引擎向主引擎发消息。 / The picture-in-picture engine sends back to the main engine.
            target = registry.mainIdentifier
        }
        return registry.forward(arguments: arguments, to: target, excluding: senderId)
    }
}
