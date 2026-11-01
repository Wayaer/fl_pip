#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import Foundation

/// Registers the fl_multi_engine channel on every Flutter engine.
///
/// The plugin is attached to the main engine by the Flutter tool and to every engine created by
/// [FlMultiEngine]. The channel identity is used as the sender of messages.
public final class FlMultiEnginePlugin: NSObject, FlutterPlugin {
    public static let mainName = "main"

    /// Registers the generated app plugins on engines created by [FlMultiEngine].
    ///
    /// Set this from the app delegate:
    ///
    /// ```swift
    /// FlMultiEnginePlugin.pluginRegistrant = { engine in
    ///     GeneratedPluginRegistrant.register(with: engine) // iOS
    ///     // RegisterGeneratedPlugins(registry: engine)   // macOS
    /// }
    /// ```
    public static var pluginRegistrant: ((FlutterEngine) -> Void)?

    private let engineName: String?

    private init(engineName: String?) {
        self.engineName = engineName
        super.init()
    }

    /// 由 Flutter 工具在引擎启动时自动调用；主引擎在这里完成注册，新增引擎则由
    /// `FlMultiEngine.create` 在启动前写入 pendingName。
    /// 不属于 fl_multi_engine 的引擎（例如 fl_pip 的 pipMain）不会登记成命名引擎，
    /// 也不会覆盖 main 的通道。
    ///
    /// Called automatically by the Flutter tool when an engine starts. Engines that are not
    /// managed by fl_multi_engine (for example the fl_pip pipMain engine) never register a named
    /// channel and never take over the main identity.
    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        // 同一个 messenger 只允许注册一次，避免重复添加通道。
        // Only register once per messenger to avoid duplicate channels.
        if FlMultiEngine.shared.hasChannel(for: messenger) {
            return
        }
        let pendingName = FlMultiEngine.shared.takePendingName(for: messenger)
        let name = pendingName ?? (FlMultiEngine.shared.isMainRegistered ? nil : mainName)
        let plugin = FlMultiEnginePlugin(engineName: name)
        let channel = FlutterMethodChannel(name: "fl_multi_engine", binaryMessenger: messenger)
        // addMethodCallDelegate 内部会设置通道的 handler，无需再次调用 setMethodCallHandler。
        // addMethodCallDelegate installs the channel handler, so no second call is needed.
        registrar.addMethodCallDelegate(plugin, channel: channel)
        if let name = name {
            FlMultiEngine.shared.attach(name: name, channel: channel, plugin: plugin, messenger: messenger)
        } else {
            FlMultiEngine.shared.attachExternal(messenger: messenger)
        }
    }

    /// Registers the plugin on an engine created by [FlMultiEngine] when the app has not provided a
    /// [pluginRegistrant].
    internal static func registerOnEngine(_ engine: FlutterEngine, name: String) {
        let messenger = engine.binaryMessenger
        if FlMultiEngine.shared.hasChannel(for: messenger) {
            return
        }
        let plugin = FlMultiEnginePlugin(engineName: name)
        let channel = FlutterMethodChannel(name: "fl_multi_engine", binaryMessenger: messenger)
        channel.setMethodCallHandler(plugin.handle)
        FlMultiEngine.shared.attach(name: name, channel: channel, plugin: plugin, messenger: messenger)
    }

    /// 引擎销毁时清理注册表中的 messenger 记录，避免标识被复用。
    /// Clears the messenger bookkeeping when the engine is destroyed.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        FlMultiEngine.shared.detach(messenger: messenger)
    }

    /// 平台通道方法统一分发：create / destroy / list / status / send。
    /// Dispatches every platform channel method.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "currentEngineName":
                result(engineName)

            case "create":
                let arguments = call.arguments as? [String: Any] ?? [:]
                let name = arguments["name"] as? String ?? ""
                let entrypoint = arguments["entrypoint"] as? String ?? ""
                let entrypointArgs = arguments["arguments"] as? [String] ?? []
                let info = try FlMultiEngine.shared.create(
                    name: name,
                    entrypoint: entrypoint,
                    arguments: entrypointArgs
                )
                // 只返回创建成功的唯一 ID，Dart 侧会重新拉取引擎列表并筛选。
                // Only return the unique ID; Dart re-fetches the engine list afterwards.
                result(info.name)

            case "destroy":
                let arguments = call.arguments as? [String: Any] ?? [:]
                let name = arguments["name"] as? String ?? ""
                result(try FlMultiEngine.shared.destroy(name: name))

            case "list":
                result(FlMultiEngine.shared.engines().map { $0.toMap() })

            case "status":
                let arguments = call.arguments as? [String: Any] ?? [:]
                let name = arguments["name"] as? String ?? ""
                result(FlMultiEngine.shared.status(name: name)?.toMap())

            case "send":
                let arguments = call.arguments as? [String: Any] ?? [:]
                let target = arguments["target"] as? String ?? ""
                let method = arguments["method"] as? String ?? "message"
                let value = arguments["value"] as? [String: Any] ?? [:]
                result(FlMultiEngine.shared.send(from: engineName ?? "", to: target, method: method, value: value))

            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let exception as FlMultiEngineException {
            result(FlutterError(code: exception.code, message: exception.message, details: nil))
        } catch {
            result(FlutterError(
                code: FlMultiEngineErrorCode.unknown,
                message: error.localizedDescription,
                details: nil
            ))
        }
    }
}

/// Sends messages from a native engine to a named engine and listens to messages delivered to that
/// engine.
public final class FlMultiEngineBridge {
    private let engineName: String
    private var listeners: [FlMultiEngine.NativeListener] = []

    public init(engineName: String) {
        self.engineName = engineName
    }

    /// Sends [value] to [target]. Returns `1` when the target exists, otherwise `0`.
    public func send(target: String, method: String = "message", value: [String: Any] = [:]) -> Int {
        FlMultiEngine.shared.send(from: engineName, to: target, method: method, value: value)
    }

    /// Listens to every message delivered to [engineName].
    public func listen(_ callback: @escaping (_ sender: String, _ method: String, _ value: [String: Any]) -> Void) {
        let listener = FlMultiEngine.NativeListener(engineName: engineName, method: nil, callback: callback)
        listeners.append(listener)
        FlMultiEngine.shared.addListener(listener)
    }

    /// Listens to the messages with [method] delivered to [engineName].
    public func listen(method: String, _ callback: @escaping (_ value: [String: Any]) -> Void) {
        listen { _, receivedMethod, value in
            if receivedMethod == method {
                callback(value)
            }
        }
    }

    /// Stops listening to all messages.
    public func dispose() {
        listeners.forEach(FlMultiEngine.shared.removeListener)
        listeners.removeAll()
    }
}
