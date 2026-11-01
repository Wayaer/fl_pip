part of 'package:fl_pip/fl_pip.dart';

/// 根据当前画中画状态构建组件。 / Builds a widget from the current PiP status.
typedef FlPiPBuilderCallback = Widget Function(FlPiPStatusInfo? status);

/// 画中画状态变化时自动刷新的组件。
///
/// [FlPiPBuilder] 监听 [FlPiP.status]；当前平台或设备不支持画中画时回调
/// [FlPiPStatus.unavailable]。
///
/// A widget that rebuilds whenever the picture-in-picture status changes.
class FlPiPBuilder extends StatefulWidget {
  const FlPiPBuilder({super.key, required this.builder});

  /// 使用最新画中画状态的回调。 / Called with the latest picture-in-picture status.
  final FlPiPBuilderCallback builder;

  @override
  State<FlPiPBuilder> createState() => _FlPiPBuilderState();
}

class _FlPiPBuilderState extends State<FlPiPBuilder> {
  @override
  void initState() {
    super.initState();
    FlPiP.instance.status.addListener(listener);
    initialize();
  }

  Future<void> initialize() async {
    try {
      final available = await FlPiP.instance.isAvailable;
      if (!mounted) return;

      if (!available) {
        FlPiP.instance.status.value = const FlPiPStatusInfo(status: FlPiPStatus.unavailable);
        return;
      }
      await FlPiP.instance.isActive;
    } on FlPiPException {
      // isActive 会把原生 PlatformException 转换成 FlPiPException，必须在这里一并处理。
      // isActive converts native PlatformException into FlPiPException.
      if (!mounted) return;
      FlPiP.instance.status.value = const FlPiPStatusInfo(status: FlPiPStatus.unavailable);
    } on MissingPluginException {
      if (!mounted) return;
      FlPiP.instance.status.value = const FlPiPStatusInfo(status: FlPiPStatus.unavailable);
    } on PlatformException {
      if (!mounted) return;
      FlPiP.instance.status.value = const FlPiPStatusInfo(status: FlPiPStatus.unavailable);
    }
  }

  void listener() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(FlPiP.instance.status.value);

  @override
  void dispose() {
    FlPiP.instance.status.removeListener(listener);
    super.dispose();
  }
}

/// 画中画窗口状态。 / The picture-in-picture window status.
enum FlPiPStatus {
  /// 画中画正在展示。 / Picture-in-picture is shown.
  enabled,

  /// 画中画未展示。 / Picture-in-picture is not shown.
  disabled,

  /// 当前平台或设备不支持画中画。 / Picture-in-picture is not supported.
  unavailable,
}

/// 当前画中画窗口的承载方式。 / How the current PiP window is presented.
enum FlPiPPresentationMode {
  /// 系统画中画窗口：Android 缩小宿主 Activity、HarmonyOS 系统画中画、iOS 系统画中画视频。
  ///
  /// The system PiP window.
  systemPip('systemPip'),

  /// 悬浮窗 / 应用内弹窗：Android `WindowManager` 悬浮窗、HarmonyOS 应用内浮窗。
  ///
  /// A floating / in-app overlay.
  overlay('overlay');

  const FlPiPPresentationMode(this.value);

  /// 平台通道使用的稳定字符串值。 / The stable value sent over the platform channel.
  final String value;

  /// 把原生字符串解析成枚举，未知值返回 `null`。
  ///
  /// Resolves the native string, or `null` when it is unknown.
  static FlPiPPresentationMode? fromValue(Object? value) {
    for (final FlPiPPresentationMode mode in values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}

/// 当前画中画状态、承载方式以及是否已创建独立引擎。
///
/// The current PiP status, its presentation mode and whether the dedicated engine exists.
@immutable
class FlPiPStatusInfo {
  const FlPiPStatusInfo({required this.status, this.mode, this.hasEngine = false});

  /// 从原生参数表创建状态。 / Creates a status from the native argument map.
  factory FlPiPStatusInfo.fromMap(Map<Object?, Object?> map) {
    final Object? statusValue = map['status'];
    final FlPiPStatus status = statusValue is int && statusValue >= 0 && statusValue < FlPiPStatus.values.length
        ? FlPiPStatus.values[statusValue]
        : FlPiPStatus.disabled;
    return FlPiPStatusInfo(
      status: status,
      mode: FlPiPPresentationMode.fromValue(map['mode']),
      hasEngine: map['hasEngine'] == true,
    );
  }

  /// 画中画窗口状态。 / The picture-in-picture window status.
  final FlPiPStatus status;

  /// 承载方式；未知或未开启时为 `null`。 / The presentation mode, `null` when unknown or disabled.
  final FlPiPPresentationMode? mode;

  /// [FlPiP.present] 传入的 `name` 对应的引擎是否仍然存在（未被销毁），与窗口是否展示无关。
  ///
  /// 窗口关闭时 `destroyEngineOnDismiss = false` 会保留引擎，此时该值仍为 `true`；
  /// 引擎被销毁后变为 `false`。
  ///
  /// Whether the engine passed to [FlPiP.present] still exists and has not been destroyed,
  /// regardless of whether the window is visible. It stays `true` when the window is closed with
  /// `destroyEngineOnDismiss = false` and turns `false` once the engine is destroyed.
  final bool hasEngine;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlPiPStatusInfo && other.status == status && other.mode == mode && other.hasEngine == hasEngine;

  @override
  int get hashCode => Object.hash(status, mode, hasEngine);

  @override
  String toString() => 'FlPiPStatusInfo(status: $status, mode: $mode, hasEngine: $hasEngine)';
}

/// 原生画中画实现返回的错误码。 / Error codes reported by the native implementation.
enum FlPiPErrorCode {
  /// 用户拒绝了画中画权限（Android 悬浮窗权限）。
  permissionDenied('permission_denied'),

  /// 已有权限申请正在进行中。
  permissionRequestInProgress('permission_request_in_progress'),

  /// 当前设备或平台不支持画中画。
  notSupported('not_supported'),

  /// 画中画已经开启。
  alreadyEnabled('already_enabled'),

  /// 宿主 Activity 未初始化，通常是 `MainActivity` 没有继承 [FlPiPActivity]。
  activityNotInitialized('activity_not_initialized'),

  /// 传入的参数不合法。
  invalidConfiguration('invalid_configuration'),

  /// 原生实现启动画中画失败。
  startFailed('start_failed'),

  /// Android 悬浮窗创建失败。
  overlayCreationFailed('overlay_creation_failed'),

  /// iOS 音频会话配置失败。
  audioSessionFailed('audio_session_failed'),

  /// 视频资源不存在。
  videoAssetNotFound('video_asset_not_found'),

  /// iOS 画中画需要的宿主窗口不可用。
  windowUnavailable('window_unavailable'),

  /// iOS 画中画控制器创建失败。
  controllerUnavailable('controller_unavailable'),

  /// 画中画使用的独立 Flutter engine 创建失败。
  engineCreationFailed('engine_creation_failed'),

  /// `fl_multi_engine` 中不存在指定名称的引擎。
  engineNotFound('engine_not_found'),

  /// 未知的原生错误。
  unknown('unknown');

  const FlPiPErrorCode(this.code);

  /// 平台通道使用的稳定字符串值。 / The stable string value sent over the platform channel.
  final String code;

  /// 把原生错误码转换为 [FlPiPErrorCode]，未知错误返回 [unknown]。
  ///
  /// Resolves the native [code], falling back to [unknown].
  static FlPiPErrorCode fromCode(String? code) =>
      values.firstWhere((FlPiPErrorCode value) => value.code == code, orElse: () => unknown);
}

/// 原生实现返回错误时抛出。 / Thrown when the native implementation reports an error.
class FlPiPException implements Exception {
  const FlPiPException(this.code, {this.message, this.details});

  /// 从 [PlatformException] 创建异常。 / Creates an exception from a [PlatformException].
  factory FlPiPException.fromPlatformException(PlatformException exception) =>
      FlPiPException(FlPiPErrorCode.fromCode(exception.code), message: exception.message, details: exception.details);

  /// 原生实现返回的错误码。 / The error code reported by the native implementation.
  final FlPiPErrorCode code;

  /// 原生实现返回的错误信息。 / The error message reported by the native implementation.
  final String? message;

  /// 原生实现返回的附加信息。 / Additional details reported by the native implementation.
  final Object? details;

  @override
  String toString() => 'FlPiPException(code: ${code.code}, message: $message)';
}

/// 引擎之间传递的消息。 / A message relayed between engines.
@immutable
class FlPiPMessage {
  const FlPiPMessage({required this.method, required this.arguments});

  /// 从原生参数表创建消息。 / Creates a message from the native argument map.
  factory FlPiPMessage.fromMap(Map<Object?, Object?> map) {
    final Object? method = map['method'];
    final Object? arguments = map['arguments'];
    return FlPiPMessage(
      method: method is String ? method : '',
      arguments: arguments is Map<Object?, Object?> ? Map<String, Object?>.from(arguments) : const <String, Object?>{},
    );
  }

  /// 发送方选择的消息类型。 / The message type chosen by the sender.
  final String method;

  /// 发送方携带的可序列化数据。 / The serializable payload sent by the sender.
  final Map<String, Object?> arguments;

  @override
  String toString() => 'FlPiPMessage(method: $method, arguments: $arguments)';
}

/// 前后台切换时使用的应用状态。 / The app state used by [FlPiP.toggle].
enum FlPiPAppState {
  /// App 在前台。 / The app is in the foreground.
  foreground,

  /// App 在后台。 / The app is in the background.
  background,
}

/// 画中画插件的统一入口。
///
/// 插件通过 `fl_multi_engine` 管理画中画引擎：窗口使用哪个引擎由 [present] 的 `name` 指定，
/// 引擎的创建与销毁都交给引擎管理插件。主引擎调用 [send] 时，消息投递给 [present] 指定的
/// 画中画引擎；该引擎调用 [send] 时，消息投递回主引擎，双方通过 [messages] 监听。
///
/// 仅支持 Android、iOS 与 HarmonyOS；在其他平台调用 [present] 会抛出 [FlPiPException]。
///
/// The unified entry point of the plugin. The engine shown in the window is selected by the
/// `name` passed to [present] and is managed through `fl_multi_engine`. [send] from the main engine
/// delivers to the picture-in-picture engine passed to [present]; [send] from that engine goes back
/// to the main engine, and both listen through [messages].
class FlPiP {
  FlPiP._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// 共享实例。 / The shared instance.
  static final FlPiP instance = FlPiP._();

  /// 返回共享实例。 / Returns the shared instance.
  factory FlPiP() => instance;

  /// 原生上报的最新画中画状态；未请求前为 `null`。
  ///
  /// The latest picture-in-picture status reported by the native implementation.
  final ValueNotifier<FlPiPStatusInfo?> status = ValueNotifier<FlPiPStatusInfo?>(null);

  final StreamController<FlPiPVideoEvent> _videoEvents = StreamController<FlPiPVideoEvent>.broadcast();
  final StreamController<FlPiPMessage> _messages = StreamController<FlPiPMessage>.broadcast();

  /// 原生视频窗口上报的事件。 / Events emitted by the native video window.
  Stream<FlPiPVideoEvent> get videoEvents => _videoEvents.stream;

  /// 对方引擎发来的消息。 / Messages sent by the other engine.
  Stream<FlPiPMessage> get messages => _messages.stream;

  /// 当前平台是否被插件支持。 / Whether the current platform is supported.
  bool get isSupportedPlatform => _isSupported;

  /// 当前是否运行在 Android 上。 / Whether the app runs on Android.
  bool get isAndroidPlatform => _isAndroid;

  /// 当前是否运行在 iOS 上。 / Whether the app runs on iOS.
  bool get isIOSPlatform => _isIOS;

  /// 当前是否运行在 HarmonyOS 上。 / Whether the app runs on HarmonyOS.
  bool get isHarmonyOSPlatform => _isHarmonyOS;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  // HarmonyOS / OpenHarmony 只在鸿蒙版 Flutter SDK 中存在 TargetPlatform.ohos，
  // 用 name 比较以兼容官方 SDK。
  bool get _isHarmonyOS => defaultTargetPlatform.name == 'ohos';

  bool get _isSupported => _isAndroid || _isIOS || _isHarmonyOS;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final Object? arguments = call.arguments;
    if (arguments is! Map<Object?, Object?>) return;
    switch (call.method) {
      case 'onVideoEvent':
        _videoEvents.add(FlPiPVideoEvent.fromMap(arguments));
      case 'onPiPStatus':
        status.value = FlPiPStatusInfo.fromMap(arguments);
      case 'onMessage':
        _messages.add(FlPiPMessage.fromMap(arguments));
      default:
        return;
    }
  }

  /// 在当前平台上开启画中画。
  ///
  /// [name] 是 `fl_multi_engine` 中的引擎名称。推荐先用 `FlMultiEngine.create()` 创建该引擎，
  /// 原生会按名称读取引擎注册表；如果引擎尚未创建，原生会用 `pipMain` 入口补建。
  ///
  /// 一次性传入三端参数，原生只使用当前平台对应的那一份。三端承载方式：
  /// - Android：[FlPiPAndroidOptions.overlay]（默认）把引擎放进 `WindowManager` 悬浮窗；
  ///   [FlPiPAndroidOptions.systemPip] 把宿主 Activity 缩成系统画中画，引擎不会被渲染。
  /// - iOS：非主引擎会把 `FlutterViewController` 渲染进系统画中画窗口；主引擎没有独立的
  ///   `FlutterEngine` 实例，改用原生运行时生成的 1 秒纯黑占位视频。宽高取自
  ///   [FlPiPIOSOptions.window]，只决定画中画窗口的比例。
  /// - HarmonyOS：[FlPiPHarmonyOSOptions.systemPip] 或 [FlPiPHarmonyOSOptions.overlay]
  ///   决定承载方式；[FlPiPHarmonyOSOptions.overlay] 支持完整宽高与位置，系统画中画的宽高只
  ///   决定窗口比例，实际大小与位置由系统管理。
  ///
  /// [FlPiPWindow] 中的宽高与位置全部是物理像素（px）。
  ///
  /// 成功时返回 `fl_multi_engine` 的引擎信息。窗口关闭时，[destroyEngineOnDismiss] 为 `true`
  /// 就销毁该引擎，否则保留引擎供 Flutter 继续使用。主引擎只能在
  /// [destroyEngineOnDismiss] 为 `false` 时展示；为 `true` 时原生会返回
  /// [FlPiPErrorCode.invalidConfiguration]。原生返回错误时抛出 [FlPiPException]；
  /// Android / HarmonyOS 系统画中画的宽高比不合法时抛出 [FlPiPAspectRatioNotSupportedException]。
  ///
  /// Enables picture-in-picture for the engine called [name]. Only the options of the current
  /// platform are used. Returns the `fl_multi_engine` info of the presented engine.
  Future<FlMultiEngineInfo> present({
    required String name,
    bool destroyEngineOnDismiss = true,
    FlPiPAndroidOptions android = const FlPiPAndroidOptions.overlay(),
    FlPiPIOSOptions ios = const FlPiPIOSOptions(),
    FlPiPHarmonyOSOptions harmonyOS = const FlPiPHarmonyOSOptions.systemPip(),
  }) async {
    if (!_isSupported) throw const FlPiPException(FlPiPErrorCode.notSupported);
    if (name.isEmpty) {
      throw const FlPiPException(FlPiPErrorCode.invalidConfiguration, message: 'The engine name must not be empty');
    }
    if (_isAndroid && android.mode == FlPiPPresentationMode.systemPip && !android.aspectRatio.isSupported) {
      throw FlPiPAspectRatioNotSupportedException(android.aspectRatio);
    }
    final FlPiPAspectRatio? harmonyRatio = harmonyOS.aspectRatio;
    if (_isHarmonyOS &&
        harmonyOS.mode == FlPiPPresentationMode.systemPip &&
        harmonyRatio != null &&
        !harmonyRatio.isSupported) {
      throw FlPiPAspectRatioNotSupportedException(harmonyRatio);
    }
    final Map<String, Object?> platformOptions = _isAndroid
        ? android.toMap()
        : (_isHarmonyOS ? harmonyOS.toMap() : ios.toMap());
    try {
      final Map<Object?, Object?>? map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'present',
        <String, Object?>{'name': name, 'destroyEngineOnDismiss': destroyEngineOnDismiss, ...platformOptions},
      );
      if (map == null) {
        throw const FlPiPException(
          FlPiPErrorCode.startFailed,
          message: 'The native implementation returned no engine info',
        );
      }
      return FlMultiEngineInfo.fromMap(map);
    } on MissingPluginException {
      throw const FlPiPException(FlPiPErrorCode.notSupported);
    } on PlatformException catch (exception) {
      throw FlPiPException.fromPlatformException(exception);
    }
  }

  /// 关闭画中画窗口；是否销毁引擎由 [present] 的 `destroyEngineOnDismiss` 决定。
  ///
  /// 视频窗口请使用 [FlPiPVideo.stop] 关闭。
  ///
  /// Dismisses the PiP window. Whether the engine is destroyed depends on the
  /// `destroyEngineOnDismiss` passed to [present].
  Future<bool> dismiss() async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('dismiss') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (exception) {
      throw FlPiPException.fromPlatformException(exception);
    }
  }

  /// 获取当前画中画状态；平台不支持时返回 `null`。
  ///
  /// Reads the current PiP status; returns `null` on unsupported platforms.
  Future<FlPiPStatusInfo?> get isActive async {
    if (!_isSupported) return null;
    try {
      final Map<Object?, Object?>? map = await _channel.invokeMethod<Map<Object?, Object?>>('isActive');
      if (map != null) status.value = FlPiPStatusInfo.fromMap(map);
      return status.value;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (exception) {
      throw FlPiPException.fromPlatformException(exception);
    }
  }

  /// 当前设备是否支持系统画中画。
  ///
  /// 悬浮窗 / 应用内弹窗（[FlPiPPresentationMode.overlay]）不依赖该值：Android 需要
  /// `SYSTEM_ALERT_WINDOW` 权限，HarmonyOS 应用内浮窗始终可用。
  ///
  /// Whether the device supports system picture-in-picture. The overlay mode
  /// ([FlPiPPresentationMode.overlay]) does not depend on it.
  Future<bool> get isAvailable async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 切换 App 前后台。
  ///
  /// iOS 没有公开 API，调用会被忽略；HarmonyOS 只能把 App 切到后台，切回前台会被忽略。
  ///
  /// Switches the app between foreground and background. Ignored on iOS; HarmonyOS only supports
  /// moving the app to the background and ignores the foreground request.
  Future<void> toggle(FlPiPAppState state) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('toggle', state == FlPiPAppState.foreground);
    } on MissingPluginException {
      // 原生实现未注册。 / The native implementation is not registered.
    } on PlatformException {
      // 前后台切换是尽力而为。 / Toggling the app state is best effort.
    }
  }

  /// 向画中画引擎发送消息，返回送达数量（`1` 或 `0`）。
  ///
  /// 主引擎调用时，消息投递给 [present] 指定的引擎（例如 `pipMain`，也可以是自定义名称）；
  /// 该引擎调用时，消息投递给主引擎。消息只在主引擎与画中画引擎之间投递，不会广播给其他引擎。
  /// [arguments] 必须能被 `StandardMessageCodec` 编码，例如 `null`、`bool`、`num`、`String`、
  /// `Uint8List`、`List` 和 `Map`。
  ///
  /// Sends [method] with [arguments] to the picture-in-picture engine and returns the delivery
  /// count (`1` or `0`). Messages from the main engine go to the engine passed to [present]
  /// (for example `pipMain`, or a custom name); messages from that engine go to the main engine.
  /// Other engines never receive them.
  Future<int> send(String method, {Map<String, Object?> arguments = const <String, Object?>{}}) async {
    if (!_isSupported) return 0;
    try {
      return await _channel.invokeMethod<int>('send', <String, Object?>{'method': method, 'arguments': arguments}) ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
}

/// Android 画中画参数。
///
/// 提供两个构造函数，对应 Android 的两种承载方式：
/// - [FlPiPAndroidOptions.overlay]：系统弹窗（`WindowManager` 悬浮窗），使用 [window] 与
///   [cornerRadius]。
/// - [FlPiPAndroidOptions.systemPip]：整个 Activity 进入系统画中画，只用 [aspectRatio]。
///
/// [FlPiPWindow] 中的宽高与位置全部是物理像素（px）。
///
/// Android picture-in-picture options with one constructor per presentation mode.
@immutable
class FlPiPAndroidOptions {
  /// 系统弹窗：`WindowManager` 悬浮窗，由 [FlPiP.present] 传入 `name` 对应的引擎渲染。
  ///
  /// The floating overlay rendered by the engine named in [FlPiP.present].
  const FlPiPAndroidOptions.overlay({this.window, this.cornerRadius = 12})
    : mode = FlPiPPresentationMode.overlay,
      aspectRatio = const FlPiPAspectRatio.square();

  /// 系统画中画：把宿主 Activity 缩成系统画中画窗口，只用宽高比。
  ///
  /// The system PiP window showing the host Activity; only the aspect ratio is used.
  const FlPiPAndroidOptions.systemPip({this.aspectRatio = const FlPiPAspectRatio.square()})
    : mode = FlPiPPresentationMode.systemPip,
      window = null,
      cornerRadius = 12;

  /// 承载方式。 / The presentation mode.
  final FlPiPPresentationMode mode;

  /// 悬浮窗宽高与位置，单位物理像素（px）；`null` 使用原生默认尺寸。
  ///
  /// The overlay size and position in physical pixels; `null` uses the native default.
  final FlPiPWindow? window;

  /// 悬浮窗圆角，单位 dp；仅 [FlPiPPresentationMode.overlay] 生效。
  ///
  /// The overlay corner radius in dp; only used by [FlPiPPresentationMode.overlay].
  final double cornerRadius;

  /// 系统画中画宽高比；仅 [FlPiPPresentationMode.systemPip] 生效。
  ///
  /// The system PiP aspect ratio; only used by [FlPiPPresentationMode.systemPip].
  final FlPiPAspectRatio aspectRatio;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{
    'mode': mode.value,
    if (mode == FlPiPPresentationMode.overlay) ...<String, Object?>{
      if (window != null) ...window!.toMap(),
      'cornerRadius': cornerRadius,
    } else
      ...aspectRatio.toMap(),
  };
}

/// iOS 画中画参数。
///
/// iOS 按 [FlPiP.present] 传入的 `name` 获取或补建引擎，并把该引擎的 `FlutterViewController`
/// 渲染进系统画中画窗口。主引擎没有独立的 `FlutterEngine` 实例，无法作为画中画内容源，
/// 此时窗口改用原生运行时生成的 1 秒纯黑视频与 1 秒静音音轨循环播放。
///
/// [FlPiPWindow] 中的宽高只决定画中画窗口的比例（系统管理实际大小与位置），全部为
/// **物理像素（px）**；`null` 时使用 16:9。
///
/// iOS picture-in-picture options. The engine named in [FlPiP.present] renders its
/// `FlutterViewController` into the PiP window. The main engine has no standalone engine
/// instance, so it falls back to placeholder media. The requested size only determines the
/// window's aspect ratio; the system owns the actual size and position.
@immutable
class FlPiPIOSOptions {
  const FlPiPIOSOptions({this.window});

  /// 画中画窗口宽高与位置，单位物理像素（px）；`null` 使用原生默认尺寸。
  ///
  /// The window size and position in physical pixels; `null` uses the native default.
  final FlPiPWindow? window;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{if (window != null) ...window!.toMap()};
}

/// HarmonyOS 画中画参数。
///
/// 提供两个构造函数，对应鸿蒙的两种承载方式：
/// - [FlPiPHarmonyOSOptions.systemPip]（默认）：系统画中画，只用 [aspectRatio]；不传时窗口
///   使用 16:9，窗口大小与位置由系统管理。
/// - [FlPiPHarmonyOSOptions.overlay]：应用内浮窗，使用 [window] 的完整位置与宽高，以及
///   [cornerRadius] 自定义控制面板。
///
/// [FlPiPWindow] 中的所有值都是**物理像素（px）**，[cornerRadius] 单位为 vp。
///
/// HarmonyOS picture-in-picture options with one constructor per presentation mode.
@immutable
class FlPiPHarmonyOSOptions {
  /// 系统画中画：可跨应用展示，系统绘制控制条，不创建自定义控制面板。
  ///
  /// 只使用 [aspectRatio]；`null` 时窗口使用 16:9，实际大小与位置由系统管理。
  ///
  /// The system PiP window; no custom control panel is used. Only [aspectRatio] is used and
  /// `null` falls back to 16:9; the system controls the actual size and position.
  const FlPiPHarmonyOSOptions.systemPip({this.aspectRatio})
    : mode = FlPiPPresentationMode.systemPip,
      window = null,
      cornerRadius = 12;

  /// 应用内浮窗：只在 App 前台展示，内容可拖拽、可点击交互。
  ///
  /// The in-app overlay, fully interactive while the app is in the foreground.
  const FlPiPHarmonyOSOptions.overlay({this.window, this.cornerRadius = 12})
    : mode = FlPiPPresentationMode.overlay,
      aspectRatio = null;

  /// 承载方式，默认 [FlPiPPresentationMode.systemPip]。
  ///
  /// The presentation mode, [FlPiPPresentationMode.systemPip] by default.
  final FlPiPPresentationMode mode;

  /// 悬浮窗宽高与位置，单位物理像素（px）；仅 [FlPiPPresentationMode.overlay] 生效。
  ///
  /// The overlay size and position in physical pixels; only used by
  /// [FlPiPPresentationMode.overlay].
  final FlPiPWindow? window;

  /// 浮窗圆角，单位 vp；仅 [FlPiPPresentationMode.overlay] 生效。
  ///
  /// The overlay corner radius in vp; only used by [FlPiPPresentationMode.overlay].
  final double cornerRadius;

  /// 系统画中画宽高比；仅 [FlPiPPresentationMode.systemPip] 生效，`null` 时使用 16:9。
  ///
  /// The system PiP aspect ratio; only used by [FlPiPPresentationMode.systemPip]. `null` falls
  /// back to 16:9.
  final FlPiPAspectRatio? aspectRatio;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{
    'mode': mode.value,
    if (mode == FlPiPPresentationMode.overlay) ...<String, Object?>{
      if (window != null) ...window!.toMap(),
      'cornerRadius': cornerRadius,
    } else if (aspectRatio != null)
      ...aspectRatio!.toMap(),
  };
}

/// 系统画中画窗口使用的宽高比。 / The aspect ratio used by the system PiP window.
@immutable
class FlPiPAspectRatio {
  const FlPiPAspectRatio(this.numerator, this.denominator)
    : assert(numerator > 0, 'numerator must be greater than zero'),
      assert(denominator > 0, 'denominator must be greater than zero');

  /// 1:1 正方形。 / A 1:1 square ratio.
  const FlPiPAspectRatio.square() : numerator = 1, denominator = 1;

  /// 16:9 横屏。 / A 16:9 landscape ratio.
  const FlPiPAspectRatio.landscape() : numerator = 16, denominator = 9;

  /// Android 支持的最宽比例（2.39:1）。
  const FlPiPAspectRatio.maxLandscape() : numerator = 239, denominator = 100;

  /// Android 支持的最高比例（1:2.39）。
  const FlPiPAspectRatio.maxVertical() : numerator = 100, denominator = 239;

  /// 9:16 竖屏。 / A 9:16 vertical ratio.
  const FlPiPAspectRatio.vertical() : numerator = 9, denominator = 16;

  /// 比例分子。 / The numerator of the ratio.
  final int numerator;

  /// 比例分母。 / The denominator of the ratio.
  final int denominator;

  /// 比例数值。 / The numeric value of the ratio.
  double get ratio => numerator / denominator;

  /// 系统是否接受该画中画比例（Android 与 HarmonyOS 使用同一范围）。
  ///
  /// Whether the system accepts this ratio; Android and HarmonyOS share the same range.
  bool get isSupported {
    if (numerator <= 0 || denominator <= 0) return false;
    final double value = ratio;
    const double min = 1 / 2.39;
    const double max = 2.39;
    return min <= value && value <= max;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlPiPAspectRatio && other.numerator == numerator && other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => 'FlPiPAspectRatio($numerator/$denominator)';

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{'numerator': numerator, 'denominator': denominator};
}

/// Android / HarmonyOS 画中画比例超出系统支持范围时抛出。
///
/// Thrown when a picture-in-picture ratio is outside the range supported by Android or
/// HarmonyOS.
class FlPiPAspectRatioNotSupportedException implements Exception {
  const FlPiPAspectRatioNotSupportedException(this.aspectRatio);

  /// 不被支持的比例。 / The unsupported ratio.
  final FlPiPAspectRatio aspectRatio;

  @override
  String toString() =>
      'FlPiPAspectRatioNotSupportedException('
      '${aspectRatio.numerator}/${aspectRatio.denominator} does not fit into '
      'supported aspect ratios. Boundaries: min: 1/2.39, max: 2.39/1. '
      ')';
}
