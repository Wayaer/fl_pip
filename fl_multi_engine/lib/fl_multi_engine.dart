import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 运行 App `main()` 的主引擎名称。
/// The name used by the engine that runs the app's `main()` entry point.
const String kFlMultiEngineMainName = 'main';

/// fl_multi_engine 管理的引擎生命周期状态。 / The lifecycle state of a managed engine.
enum FlMultiEngineState {
  /// The engine is created and running.
  ///
  /// 当前原生实现只会通过 [FlMultiEngine.list] / [FlMultiEngine.status] 返回此状态；
  /// 引擎销毁后会直接从注册表移除，创建失败会抛出 [FlMultiEngineException]。
  running,

  /// The engine has been destroyed.
  ///
  /// 预留给保留销毁记录的实现；当前原生实现销毁后会直接移除引擎。
  disposed,

  /// The engine could not be created.
  ///
  /// 预留给保留失败记录的实现；当前原生实现通过 [FlMultiEngineException] 上报创建失败。
  failed,
}

/// 描述一个由 fl_multi_engine 管理的引擎。 / Describes a managed engine.
@immutable
class FlMultiEngineInfo {
  const FlMultiEngineInfo({
    required this.name,
    required this.entrypoint,
    required this.state,
    required this.createdAt,
    required this.isMain,
  });

  /// Creates an info object from the map sent by the native implementation.
  factory FlMultiEngineInfo.fromMap(Map<Object?, Object?> map) {
    final Object? createdAt = map['createdAt'];
    final Object? state = map['state'];
    return FlMultiEngineInfo(
      name: map['name'] as String? ?? '',
      entrypoint: map['entrypoint'] as String? ?? '',
      state: state is String
          ? FlMultiEngineState.values.firstWhere(
              (FlMultiEngineState value) => value.name == state,
              orElse: () => FlMultiEngineState.failed,
            )
          : FlMultiEngineState.failed,
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : DateTime.fromMillisecondsSinceEpoch(0),
      isMain: map['isMain'] == true,
    );
  }

  /// The unique name of the engine.
  final String name;

  /// The Dart entry point used to start the engine.
  final String entrypoint;

  /// The current lifecycle state.
  final FlMultiEngineState state;

  /// When the engine was created.
  final DateTime createdAt;

  /// Whether this is the engine that runs `main()`.
  final bool isMain;

  /// 销毁该引擎；主引擎不可销毁。 / Destroys this engine. The main engine cannot be destroyed.
  Future<bool> destroy() => FlMultiEngine.instance.destroy(name);

  /// 从当前引擎向这个引擎发送消息，返回投递成功的目标数量（1 或 0）。
  ///
  /// Sends a message from the current engine to this engine and returns the number of engines
  /// that received it: `1` when this engine exists and is running, `0` otherwise.
  Future<int> send({String method = 'message', Map<String, Object?> value = const <String, Object?>{}}) =>
      FlMultiEngine.instance.send(target: name, method: method, value: value);

  @override
  String toString() => 'FlMultiEngineInfo(name: $name, entrypoint: $entrypoint, state: ${state.name}, isMain: $isMain)';
}

/// 从其他引擎转发过来的消息。 / A message relayed from another engine.
@immutable
class FlMultiEngineMessage {
  const FlMultiEngineMessage({required this.sender, required this.method, required this.value});

  /// Creates a message from the map sent by the native implementation.
  factory FlMultiEngineMessage.fromMap(Map<Object?, Object?> map) {
    final Object? value = map['value'];
    return FlMultiEngineMessage(
      sender: map['sender'] as String? ?? '',
      method: map['method'] as String? ?? '',
      value: value is Map<Object?, Object?> ? Map<String, Object?>.from(value) : const <String, Object?>{},
    );
  }

  /// The name of the engine that sent the message.
  final String sender;

  /// The method chosen by the sender.
  final String method;

  /// The payload sent by the sender.
  final Map<String, Object?> value;

  @override
  String toString() => 'FlMultiEngineMessage(sender: $sender, method: $method, value: $value)';
}

/// Called when [FlMultiEngine] receives a message from another engine.
typedef FlMultiEngineMessageCallback = void Function(FlMultiEngineMessage message);

/// Called when a specific method is received from another engine.
typedef FlMultiEngineValueCallback = void Function(Map<String, Object?> value);

/// 各平台原生实现统一使用的稳定错误码。
///
/// 原生侧通过平台通道返回同一个字符串，因此可以直接与 [FlMultiEngineException.code] 比较，
/// 例如 `exception.code == FlMultiEngineErrorCode.engineExists`。
///
/// Stable error codes shared by every native implementation.
class FlMultiEngineErrorCode {
  const FlMultiEngineErrorCode._();

  /// 当前平台不支持该能力。 / The current platform does not support the capability.
  static const String notSupported = 'not_supported';

  /// 引擎名称或入口函数为空。
  static const String invalidName = 'invalid_name';

  /// 同名引擎已存在；`main` 同样不能被重复创建。
  static const String engineExists = 'engine_exists';

  /// 引擎创建或启动失败。
  static const String createFailed = 'create_failed';

  /// 主引擎不允许销毁。
  static const String mainEngineNotDestroyable = 'main_engine_not_destroyable';

  /// 原生实现尚未绑定到主引擎。
  static const String notInitialized = 'not_initialized';

  /// 原生实现未识别的异常。
  static const String unknown = 'unknown';
}

/// 原生引擎管理器返回的错误。 / An error reported by the native engine manager.
class FlMultiEngineException implements Exception {
  const FlMultiEngineException(this.code, {this.message});

  /// The stable error code reported by the native implementation.
  ///
  /// See [FlMultiEngineErrorCode] for every code used by the plugin.
  final String code;

  /// A human readable description.
  final String? message;

  @override
  String toString() => 'FlMultiEngineException(code: $code, message: $message)';
}

/// 创建、销毁和查询 Flutter 引擎的统一入口。
///
/// 主引擎会自动注册为 [kFlMultiEngineMainName]；新增引擎必须使用唯一的 [create] 名称。
/// 支持 Android、iOS、macOS、Windows、Linux 和 HarmonyOS / OpenHarmony；其他平台会抛出带
/// [FlMultiEngineErrorCode.notSupported] 的异常。
///
/// Creates, destroys and inspects Flutter engines.
class FlMultiEngine {
  FlMultiEngine._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// The shared instance. Each Flutter engine has its own isolate and therefore its own instance.
  static final FlMultiEngine instance = FlMultiEngine._();

  /// Returns the shared instance.
  factory FlMultiEngine() => instance;

  static const MethodChannel _channel = MethodChannel('fl_multi_engine');

  final StreamController<FlMultiEngineMessage> _messages = StreamController<FlMultiEngineMessage>.broadcast();
  final StreamController<List<FlMultiEngineInfo>> _engines = StreamController<List<FlMultiEngineInfo>>.broadcast();

  /// All messages sent by the other engines.
  Stream<FlMultiEngineMessage> get messages => _messages.stream;

  /// 引擎列表变化事件。
  ///
  /// 原生实现创建或销毁引擎后会通知 Flutter，Dart 侧收到通知后重新调用 [list] 拉取完整列表，
  /// 再把最新列表推送给订阅者；通知本身不携带引擎数据。
  ///
  /// Emits the latest engine list whenever the native implementation reports that an engine was
  /// created or destroyed. The notification carries no data; the list is re-fetched with [list].
  Stream<List<FlMultiEngineInfo>> get engines => _engines.stream;

  /// Subscribes to the messages sent by the other engines.
  StreamSubscription<FlMultiEngineMessage> listen(FlMultiEngineMessageCallback callback) => messages.listen(callback);

  /// Whether the current platform is supported by the plugin.
  static bool get isSupported {
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        // HarmonyOS / OpenHarmony 只在鸿蒙版 Flutter SDK 中存在 TargetPlatform.ohos，
        // 用 name 比较以兼容官方 SDK。
        // TargetPlatform.ohos only exists on the HarmonyOS Flutter SDK; compare by name to stay
        // compatible with the upstream SDK.
        platform.name == 'ohos') {
      return true;
    }
    return false;
  }

  /// The name of the engine that is running this Dart code.
  ///
  /// The main engine reports [kFlMultiEngineMainName]. Additional engines report the name passed
  /// to [create].
  Future<String?> get currentEngineName async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('currentEngineName');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (exception) {
      throw FlMultiEngineException(exception.code, message: exception.message);
    }
  }

  /// Creates and starts a new engine that runs [entrypoint].
  ///
  /// [entrypoint] must be a top-level function annotated with `@pragma('vm:entry-point')`.
  /// [arguments] are passed to the entry point as command line arguments.
  ///
  /// The engine starts [entrypoint] immediately on creation, while plugins are registered on the
  /// engine right after creation. The entry point must therefore not call plugin channels
  /// synchronously from `main()`; call them after `runApp` or from a post-frame callback, otherwise
  /// an early call can fail with `MissingPluginException`.
  ///
  /// On Linux the Flutter embedder does not expose an entry point name. The implementation passes
  /// the entry point and engine name as arguments, therefore the app's `main(List<String> args)`
  /// must dispatch to the requested entry point on that platform.
  ///
  /// 返回信息中的 [FlMultiEngineInfo.name] 就是引擎的唯一标识，后续的 destroy、status 和
  /// send 都用它定位引擎。创建引擎不会展示任何界面。
  ///
  /// 原生只返回创建成功的唯一 ID，Dart 侧随后重新拉取 [list] 并按 ID 筛选出该引擎的信息。
  /// 创建失败时返回 `null`；原生返回的错误会以 [FlMultiEngineException] 抛出。
  ///
  /// The native implementation only returns the unique ID of the created engine. The plugin then
  /// re-fetches [list] and returns the matching [FlMultiEngineInfo]. Returns `null` when the native
  /// implementation reports no ID; native errors are thrown as [FlMultiEngineException].
  Future<FlMultiEngineInfo?> create({
    required String name,
    required String entrypoint,
    List<String> arguments = const <String>[],
  }) async {
    if (!isSupported) throw const FlMultiEngineException(FlMultiEngineErrorCode.notSupported);
    if (name.isEmpty || entrypoint.isEmpty) {
      throw const FlMultiEngineException(
        FlMultiEngineErrorCode.invalidName,
        message: 'The engine name and entry point must not be empty',
      );
    }
    try {
      final String? id = await _channel.invokeMethod<String>('create', <String, Object?>{
        'name': name,
        'entrypoint': entrypoint,
        'arguments': arguments,
      });
      if (id == null) return null;
      final List<FlMultiEngineInfo> engines = await list();
      for (final FlMultiEngineInfo info in engines) {
        if (info.name == id) return info;
      }
      return null;
    } on PlatformException catch (exception) {
      throw FlMultiEngineException(exception.code, message: exception.message);
    }
  }

  /// Destroys the engine called [name].
  ///
  /// The main engine cannot be destroyed.
  Future<bool> destroy(String name) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('destroy', <String, Object?>{'name': name}) ?? false;
    } on PlatformException catch (exception) {
      throw FlMultiEngineException(exception.code, message: exception.message);
    }
  }

  /// Returns every engine currently registered, including the main engine.
  Future<List<FlMultiEngineInfo>> list() async {
    if (!isSupported) return const <FlMultiEngineInfo>[];
    try {
      final List<Object?>? maps = await _channel.invokeMethod<List<Object?>>('list');
      return maps?.whereType<Map<Object?, Object?>>().map(FlMultiEngineInfo.fromMap).toList(growable: false) ??
          const <FlMultiEngineInfo>[];
    } on PlatformException catch (exception) {
      throw FlMultiEngineException(exception.code, message: exception.message);
    }
  }

  /// Returns the information of the engine called [name], or `null` when it does not exist.
  Future<FlMultiEngineInfo?> status(String name) async {
    if (!isSupported) return null;
    try {
      final Map<Object?, Object?>? map = await _channel.invokeMethod<Map<Object?, Object?>>('status', <String, Object?>{
        'name': name,
      });
      return map == null ? null : FlMultiEngineInfo.fromMap(map);
    } on PlatformException catch (exception) {
      throw FlMultiEngineException(exception.code, message: exception.message);
    }
  }

  /// Sends [value] to the engine called [target].
  ///
  /// Returns the number of engines that received the message: `1` when the target exists and is
  /// running, `0` otherwise.
  Future<int> send({
    required String target,
    String method = 'message',
    Map<String, Object?> value = const <String, Object?>{},
  }) async {
    if (!isSupported) return 0;
    try {
      return await _channel.invokeMethod<int>('send', <String, Object?>{
            'target': target,
            'method': method,
            'value': value,
          }) ??
          0;
    } on MissingPluginException {
      return 0;
    } on PlatformException catch (exception) {
      throw FlMultiEngineException(exception.code, message: exception.message);
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onEnginesChanged') {
      await _refreshEngines();
      return;
    }
    final Object? arguments = call.arguments;
    if (arguments is! Map<Object?, Object?>) return;
    if (call.method == 'onMessage') {
      _messages.add(FlMultiEngineMessage.fromMap(arguments));
    }
  }

  /// 原生通知引擎列表变化后重新拉取完整列表并推送给订阅者。
  ///
  /// Re-fetches the engine list after a native change notification and forwards it to subscribers.
  Future<void> _refreshEngines() async {
    try {
      final List<FlMultiEngineInfo> engines = await list();
      _engines.add(engines);
    } catch (_) {
      // 通知触发的刷新失败时忽略，避免影响平台通道回调。
      // Ignore refresh failures triggered by a notification so the channel callback stays clean.
    }
  }
}

/// 以某个引擎的身份收发消息。
///
/// 构造时传入当前 Dart isolate 所属的引擎名称。原生侧会以通道身份作为 sender，
/// 因此 [engineName] 主要用于日志和校验。
///
/// Sends and receives messages for one specific engine.
class FlMultiEngineBridge {
  const FlMultiEngineBridge(this.engineName);

  /// The name of the engine that owns this bridge.
  final String engineName;

  /// Sends [value] to [target].
  Future<int> send({
    required String target,
    String method = 'message',
    Map<String, Object?> value = const <String, Object?>{},
  }) => FlMultiEngine.instance.send(target: target, method: method, value: value);

  /// Messages sent by the other engines.
  Stream<FlMultiEngineMessage> get messages => FlMultiEngine.instance.messages;

  /// Listens to the messages whose method equals [method].
  StreamSubscription<FlMultiEngineMessage> listen(String method, FlMultiEngineValueCallback callback) => messages
      .where((FlMultiEngineMessage message) => message.method == method)
      .listen((FlMultiEngineMessage message) => callback(message.value));

  @override
  String toString() => 'FlMultiEngineBridge(engineName: $engineName)';
}
