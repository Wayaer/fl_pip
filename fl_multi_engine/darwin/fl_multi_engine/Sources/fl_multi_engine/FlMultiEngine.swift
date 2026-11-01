#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import Foundation

/// 命名引擎管理器的原生入口，宿主 App 可以不经过 Flutter 直接管理引擎。
/// 插件与 Flutter 侧共用同一份注册表。
///
/// Native entry point of the engine manager.
///
/// Host apps can create, destroy and inspect engines without going through Flutter. The Flutter
/// plugin uses the same registry.
public final class FlMultiEngine {
    public static let shared = FlMultiEngine()

    internal final class Entry {
        let name: String
        let entrypoint: String
        let engine: FlutterEngine?
        let isMain: Bool
        let createdAt: Int64
        var channel: FlutterMethodChannel?
        var plugin: FlMultiEnginePlugin?
        var state = "running"

        init(name: String, entrypoint: String, engine: FlutterEngine?, isMain: Bool) {
            self.name = name
            self.entrypoint = entrypoint
            self.engine = engine
            self.isMain = isMain
            self.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        }

        func info() -> FlMultiEngineInfo {
            FlMultiEngineInfo(name: name, entrypoint: entrypoint, state: state, createdAt: createdAt, isMain: isMain)
        }
    }

    internal final class NativeListener {
        let engineName: String
        let method: String?
        let callback: (String, String, [String: Any]) -> Void

        init(engineName: String, method: String?, callback: @escaping (String, String, [String: Any]) -> Void) {
            self.engineName = engineName
            self.method = method
            self.callback = callback
        }
    }

    #if os(iOS)
    private let engineGroup = FlutterEngineGroup(name: "fl_multi_engine", project: nil)
    #endif
    private var entries: [String: Entry] = [:]
    private var pendingNames: [ObjectIdentifier: String] = [:]
    private var messengerNames: [ObjectIdentifier: String] = [:]
    private var externalMessengers: Set<ObjectIdentifier> = []
    private var listeners: [NativeListener] = []
    private var destroyObservers: [FlMultiEngineDestroyObserver] = []

    private init() {}

    internal func takePendingName(for messenger: FlutterBinaryMessenger) -> String? {
        pendingNames.removeValue(forKey: ObjectIdentifier(messenger as AnyObject))
    }

    /// main 是否已经注册；用于区分外部引擎，避免它们冒充 main。
    /// Whether main is already registered, used to keep external engines from impersonating it.
    internal var isMainRegistered: Bool { entries[FlMultiEnginePlugin.mainName] != nil }

    /// 插件注册完成后把通道与插件实例关联到注册表。
    /// Links the channel and the plugin instance to the registry after registration.
    internal func attach(
        name: String,
        channel: FlutterMethodChannel,
        plugin: FlMultiEnginePlugin,
        messenger: FlutterBinaryMessenger
    ) {
        messengerNames[ObjectIdentifier(messenger as AnyObject)] = name
        if let entry = entries[name] {
            entry.channel = channel
            entry.plugin = plugin
            return
        }
        let entry = Entry(
            name: name,
            entrypoint: name == FlMultiEnginePlugin.mainName ? "main" : "",
            engine: nil,
            isMain: name == FlMultiEnginePlugin.mainName
        )
        entry.channel = channel
        entry.plugin = plugin
        entries[name] = entry
    }

    /// 记录一个不属于 fl_multi_engine 的引擎（例如 fl_pip 的 pipMain）；它既不会登记成命名
    /// 引擎，也不会覆盖 main 的通道。
    /// Records an engine that fl_multi_engine does not manage. It never registers a named channel
    /// and never takes over the main identity.
    internal func attachExternal(messenger: FlutterBinaryMessenger) {
        externalMessengers.insert(ObjectIdentifier(messenger as AnyObject))
    }

    internal func hasChannel(for messenger: FlutterBinaryMessenger) -> Bool {
        let identifier = ObjectIdentifier(messenger as AnyObject)
        return messengerNames[identifier] != nil || externalMessengers.contains(identifier)
    }

    /// 引擎销毁时清理 messenger 记录，避免 ObjectIdentifier 被新引擎复用时误判为已注册。
    /// Clears the messenger bookkeeping so a reused ObjectIdentifier is not mistaken for a
    /// registered engine.
    internal func detach(messenger: FlutterBinaryMessenger) {
        let identifier = ObjectIdentifier(messenger as AnyObject)
        messengerNames.removeValue(forKey: identifier)
        externalMessengers.remove(identifier)
    }

    /// 注册引擎销毁观察者，供其他插件在引擎消失时释放对应的原生视图。
    /// Adds an observer that is called when a named engine is destroyed.
    public func addDestroyObserver(_ observer: FlMultiEngineDestroyObserver) {
        destroyObservers.append(observer)
    }

    /// 移除引擎销毁观察者。 / Removes a destroy observer.
    public func removeDestroyObserver(_ observer: FlMultiEngineDestroyObserver) {
        destroyObservers.removeAll { $0 === observer }
    }

    /// 创建并启动一个运行 [entrypoint] 的新引擎。
    ///
    /// 创建前必须先把引擎名称写入 pendingNames，插件注册时才能拿到正确的引擎名。
    ///
    /// Creates and starts a new engine that runs [entrypoint]. The engine name is the unique
    /// identifier used by `destroy` and messages. The pending name is stored before the plugins
    /// are registered so that the new engine is not mistaken for the main engine.
    public func create(
        name: String,
        entrypoint: String,
        arguments: [String] = []
    ) throws -> FlMultiEngineInfo {
        guard !name.isEmpty, !entrypoint.isEmpty else {
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.invalidName,
                "The engine name and entry point must not be empty"
            )
        }
        guard name != FlMultiEnginePlugin.mainName, entries[name] == nil else {
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.engineExists,
                "The engine \(name) already exists"
            )
        }

        #if os(iOS)
        let options = FlutterEngineGroupOptions()
        options.entrypoint = entrypoint
        options.entrypointArgs = arguments
        let engine = engineGroup.makeEngine(with: options)
        #else
        let project = FlutterDartProject()
        project.dartEntrypointArguments = arguments
        let engine = FlutterEngine(name: name, project: project, allowHeadlessExecution: true)
        guard engine.run(withEntrypoint: entrypoint.isEmpty ? nil : entrypoint) else {
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.createFailed,
                "Unable to start the engine \(name)"
            )
        }
        #endif

        let entry = Entry(name: name, entrypoint: entrypoint, engine: engine, isMain: false)
        entries[name] = entry
        pendingNames[ObjectIdentifier(engine.binaryMessenger as AnyObject)] = name

        if let registrant = FlMultiEnginePlugin.pluginRegistrant {
            registrant(engine)
        }
        if entry.channel == nil {
            FlMultiEnginePlugin.registerOnEngine(engine, name: name)
        }

        // 插件注册失败时通道仍然为空，此时必须回滚，否则注册表里会留下一个无法收发消息的
        // 引擎，并且会随 create 调用不断累积。
        // When the channel is still missing after registration the engine cannot be reached by
        // `send`; roll the entry back and destroy it instead of leaking a half-registered engine.
        guard entry.channel != nil else {
            let identifier = ObjectIdentifier(engine.binaryMessenger as AnyObject)
            entries.removeValue(forKey: name)
            pendingNames.removeValue(forKey: identifier)
            messengerNames.removeValue(forKey: identifier)
            #if os(iOS)
            engine.destroyContext()
            #else
            engine.shutDownEngine()
            #endif
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.createFailed,
                "Unable to register the fl_multi_engine channel on the engine \(name)"
            )
        }

        notifyEnginesChanged()
        return entry.info()
    }

    /// Destroys the engine called [name].
    public func destroy(name: String) throws -> Bool {
        try destroyNow(name: name)
    }

    private func destroyNow(name: String) throws -> Bool {
        guard let entry = entries[name] else { return false }
        guard !entry.isMain else {
            throw FlMultiEngineException(
                FlMultiEngineErrorCode.mainEngineNotDestroyable,
                "The main engine cannot be destroyed"
            )
        }
        entry.channel?.setMethodCallHandler(nil)
        entry.state = "disposed"
        entries.removeValue(forKey: name)
        // 先通知观察者（例如 fl_pip 会在这里关闭该引擎的画中画），再销毁引擎。
        // Notify observers first so presented views are released before the engine is destroyed.
        let observers = destroyObservers
        observers.forEach { $0.callback(name) }
        if let engine = entry.engine {
            let identifier = ObjectIdentifier(engine.binaryMessenger as AnyObject)
            pendingNames.removeValue(forKey: identifier)
            messengerNames.removeValue(forKey: identifier)
            #if os(iOS)
            engine.destroyContext()
            #else
            engine.shutDownEngine()
            #endif
        }
        notifyEnginesChanged()
        return true
    }

    /// 通知 Flutter 侧引擎列表发生变化；只发通知，不携带引擎数据。
    ///
    /// Notifies Flutter that the engine list changed. The notification carries no engine data.
    internal func notifyEnginesChanged() {
        guard let channel = entries[FlMultiEnginePlugin.mainName]?.channel else { return }
        // 延后到当前调用返回之后再通知，避免通知和 create/destroy 的结果竞争。
        // Post the notification so it arrives after the current create/destroy result.
        DispatchQueue.main.async {
            channel.invokeMethod("onEnginesChanged", arguments: nil)
        }
    }

    /// Returns every registered engine, including the main engine.
    ///
    /// 按创建时间排序，保证跨平台顺序稳定（Android 是插入顺序）。
    /// Sorted by creation time so the order is stable across platforms like Android.
    public func engines() -> [FlMultiEngineInfo] {
        entries.values.map { $0.info() }.sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return left.name < right.name
        }
    }

    /// Returns the information of [name], or `nil`.
    public func status(name: String) -> FlMultiEngineInfo? {
        entries[name]?.info()
    }

    /// Returns the real engine instance of [name], or `nil` when it is the main engine.
    public func engine(named name: String) -> FlutterEngine? {
        entries[name]?.engine
    }

    /// 把消息定向投递给 [target] 的 Dart 侧，同时回调该引擎的原生监听器。
    /// Sends [value] from [sender] to [target]; returns 1 when the target exists.
    public func send(from sender: String, to target: String, method: String, value: [String: Any]) -> Int {
        guard let entry = entries[target], let channel = entry.channel else { return 0 }
        let payload: [String: Any] = ["sender": sender, "method": method, "value": value]
        channel.invokeMethod("onMessage", arguments: payload)
        listeners.filter { $0.engineName == target && ($0.method == nil || $0.method == method) }
            .forEach { $0.callback(sender, method, value) }
        return 1
    }

    internal func addListener(_ listener: NativeListener) {
        listeners.append(listener)
    }

    internal func removeListener(_ listener: NativeListener) {
        listeners.removeAll { $0 === listener }
    }
}

/// 引擎销毁观察者；注册后会在命名引擎被销毁时收到回调。
/// An observer that is called when a named engine is destroyed.
public final class FlMultiEngineDestroyObserver {
    fileprivate let callback: (String) -> Void

    public init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }
}

/// 描述一个由 fl_multi_engine 管理的引擎。 / Describes an engine managed by fl_multi_engine.
@objcMembers
public final class FlMultiEngineInfo: NSObject {
    public let name: String
    public let entrypoint: String
    public let state: String
    public let createdAt: Int64
    public let isMain: Bool

    init(name: String, entrypoint: String, state: String, createdAt: Int64, isMain: Bool) {
        self.name = name
        self.entrypoint = entrypoint
        self.state = state
        self.createdAt = createdAt
        self.isMain = isMain
    }

    func toMap() -> [String: Any] {
        [
            "name": name,
            "entrypoint": entrypoint,
            "state": state,
            "createdAt": createdAt,
            "isMain": isMain,
        ]
    }
}

/// 引擎管理器抛出的错误，code 与 Dart 侧的错误码一一对应。
/// An error reported by the engine manager.
public struct FlMultiEngineException: Error {
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

/// 与 Dart 侧 `FlMultiEngineErrorCode` 一一对应的稳定错误码。
/// Stable error codes shared with the Dart implementation.
public enum FlMultiEngineErrorCode {
    public static let notSupported = "not_supported"
    public static let invalidName = "invalid_name"
    public static let engineExists = "engine_exists"
    public static let createFailed = "create_failed"
    public static let mainEngineNotDestroyable = "main_engine_not_destroyable"
    public static let notInitialized = "not_initialized"
    public static let unknown = "unknown"
}
