part of 'package:fl_pip/fl_pip.dart';

/// 视频来源类型。 / The kind of video source.
enum FlPiPVideoSourceType {
  /// Flutter 资源文件。 / A Flutter asset.
  asset('asset'),

  /// 本地文件路径或 `file://` 地址。 / A local file path or `file://` URL.
  file('file'),

  /// 网络地址。 / A remote URL.
  network('network');

  const FlPiPVideoSourceType(this.value);

  /// 平台通道使用的稳定字符串值。 / The stable value sent over the platform channel.
  final String value;
}

/// 视频来源，对齐 `video_player` 的 asset / file / network 三种用法。
///
/// A video source, matching the asset / file / network sources of `video_player`.
@immutable
class FlPiPVideoSource {
  /// Flutter 资源文件。
  ///
  /// [packageName] 为 `null` 时使用宿主 App 的资源；插件自带的资源使用 `fl_pip`。
  const FlPiPVideoSource.asset(this.uri, {this.packageName}) : type = FlPiPVideoSourceType.asset;

  /// 本地文件路径或 `file://` 地址。
  const FlPiPVideoSource.file(this.uri) : type = FlPiPVideoSourceType.file, packageName = null;

  /// 网络地址。
  const FlPiPVideoSource.network(this.uri) : type = FlPiPVideoSourceType.network, packageName = null;

  /// 资源地址或文件/网络路径。 / The asset path, file path or URL.
  final String uri;

  /// 来源类型。 / The source type.
  final FlPiPVideoSourceType type;

  /// 仅 [FlPiPVideoSourceType.asset] 使用：资源所属的 package。
  ///
  /// Asset owner package, only used by [FlPiPVideoSourceType.asset].
  final String? packageName;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{'type': type.value, 'uri': uri, 'packageName': packageName};

  @override
  String toString() => 'FlPiPVideoSource(${type.value}: $uri, packageName: $packageName)';
}

/// 原生视频窗口上报的控制面板操作。 / A control action reported by the native video panel.
enum FlPiPVideoControlAction {
  /// 控制面板显示。 / The control panel became visible.
  show,

  /// 控制面板隐藏。 / The control panel was hidden.
  hide,

  /// 播放。 / Play was pressed.
  play,

  /// 暂停。 / Pause was pressed.
  pause,

  /// 播放/暂停按钮。 / The play/pause button was pressed.
  playPause,

  /// 快退。 / Rewind was pressed.
  rewind,

  /// 快进。 / Fast-forward was pressed.
  forward,

  /// 跳转。 / A seek operation was requested.
  seek,

  /// 关闭。 / The close button was pressed.
  close,

  /// 进度更新。 / A playback progress update.
  progress,
}

/// 原生视频窗口上报的事件。 / An event emitted by the native video window.
@immutable
class FlPiPVideoEvent {
  const FlPiPVideoEvent({required this.event, this.action, this.playing, this.positionMs, this.durationMs});

  /// 从原生参数表创建事件。 / Creates an event from the native argument map.
  factory FlPiPVideoEvent.fromMap(Map<Object?, Object?> map) {
    final Object? action = map['action'];
    return FlPiPVideoEvent(
      event: map['event'] as String? ?? '',
      action: action is String
          ? FlPiPVideoControlAction.values.firstWhere(
              (FlPiPVideoControlAction value) => value.name == action,
              orElse: () => FlPiPVideoControlAction.progress,
            )
          : null,
      playing: map['playing'] as bool?,
      positionMs: map['positionMs'] as int?,
      durationMs: map['durationMs'] as int?,
    );
  }

  /// 事件名：`play`、`playPause`、`skip`、`close`、`ended`、`position`、`stop`、`speed`、
  /// `volume`、`error`，以及自定义控制面板显示/隐藏时上报的 `controls`。
  ///
  /// `controls` 只在绘制自定义面板的平台上报（Android 悬浮窗、HarmonyOS 应用内浮窗）；
  /// iOS 的系统面板由系统绘制，不会上报该事件。
  ///
  /// The event name. `controls` is only emitted where a custom panel is drawn (the Android
  /// overlay and the HarmonyOS in-app overlay); iOS leaves the panel to the system.
  final String event;

  /// 控制面板操作，来自原生面板时非空。 / The control action, when it comes from the native panel.
  final FlPiPVideoControlAction? action;

  /// 是否正在播放。 / Whether playback is running, when known.
  final bool? playing;

  /// 当前播放位置，毫秒。 / The current position in milliseconds.
  final int? positionMs;

  /// 总时长，毫秒。 / The duration in milliseconds.
  final int? durationMs;

  @override
  String toString() => 'FlPiPVideoEvent(event: $event, action: $action, playing: $playing)';
}

/// 原生视频窗口的状态快照。 / The state snapshot of the native video window.
@immutable
class FlPiPVideoStatus {
  const FlPiPVideoStatus({
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.speed,
    required this.volume,
  });

  /// 从原生参数表创建状态。 / Creates a status from the native argument map.
  factory FlPiPVideoStatus.fromMap(Map<Object?, Object?> map) => FlPiPVideoStatus(
    playing: map['playing'] as bool? ?? false,
    positionMs: map['positionMs'] as int? ?? 0,
    durationMs: map['durationMs'] as int? ?? 0,
    speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
    volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
  );

  /// 是否正在播放。 / Whether playback is running.
  final bool playing;

  /// 当前位置，毫秒。 / The current position in milliseconds.
  final int positionMs;

  /// 总时长，毫秒；未知时为 `0`。 / The duration in milliseconds, `0` when unknown.
  final int durationMs;

  /// 播放速度。 / The playback speed multiplier.
  final double speed;

  /// 音量，范围 `0.0 ~ 1.0`。 / The volume in the `0.0 ~ 1.0` range.
  final double volume;

  @override
  String toString() =>
      'FlPiPVideoStatus(playing: $playing, positionMs: $positionMs, '
      'durationMs: $durationMs, speed: $speed, volume: $volume)';
}

/// Android 视频播放参数（`WindowManager` 系统弹窗）。
///
/// Android 视频默认且只能使用系统弹窗（[FlPiPPresentationMode.overlay]）；它是唯一支持自定义
/// 弹窗圆角与逐按钮控制面板的视频平台。[window] 的宽/高/位置全部是**物理像素**；传入后原生把
/// 视频控件设置成该宽高，画面自适应填充。
///
/// Android video options for the `WindowManager` overlay. See [FlPiPWindow] for the pixel unit.
@immutable
class FlPiPVideoAndroidOptions {
  const FlPiPVideoAndroidOptions({
    required this.source,
    this.loop = false,
    this.muted = false,
    this.window,
    this.cornerRadius = 12,
    this.showControls = true,
    this.showPlayPause = true,
    this.showProgress = true,
    this.showClose = true,
    this.allowDrag = true,
    this.autoHide = true,
  });

  /// 视频来源。 / The video source.
  final FlPiPVideoSource source;

  /// 是否循环播放。 / Whether playback restarts automatically at the end.
  final bool loop;

  /// 是否静音。 / Whether the audio is muted.
  final bool muted;

  /// 视频控件宽高与位置，单位物理像素（px）；`null` 时由原生使用默认尺寸。
  ///
  /// The video view size and position in physical pixels; `null` uses the native default.
  final FlPiPWindow? window;

  /// 弹窗圆角，单位 dp。 / The overlay corner radius in dp.
  final double cornerRadius;

  /// 是否显示整个控制面板。 / Whether the control panel is shown.
  final bool showControls;

  /// 是否显示播放/暂停按钮。 / Whether the play/pause button is shown.
  final bool showPlayPause;

  /// 是否显示进度条。 / Whether the progress bar is shown.
  final bool showProgress;

  /// 是否显示关闭按钮。 / Whether the close button is shown.
  final bool showClose;

  /// 是否允许拖动窗口。 / Whether the overlay can be dragged.
  final bool allowDrag;

  /// 控制面板是否自动隐藏。 / Whether the control panel hides automatically.
  final bool autoHide;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{
    ...source.toMap(),
    'loop': loop,
    'muted': muted,
    if (window != null) ...window!.toMap(),
    'cornerRadius': cornerRadius,
    'controls': <String, Object?>{
      'enabled': showControls,
      'showPlayPause': showPlayPause,
      'showProgress': showProgress,
      'showClose': showClose,
      'allowDrag': allowDrag,
      'autoHide': autoHide,
    },
  };
}

/// iOS 视频播放参数（`AVPlayerLayer` 系统画中画）。
///
/// 系统画中画窗口的比例由视频本身决定。iOS 不展示画中画弹出前的内联视频层（原生把它固定为
/// 0.01pt 并放在左上角），[window] 仅为 API 一致而保留。网络视频会先用本地占位媒体启动
/// 画中画，首帧到达后在画中画窗口内完成加载。系统面板只能整体显示或隐藏。
///
/// iOS video options for the `AVPlayerLayer` system PiP. The inline preview is hidden on iOS;
/// [window] is kept for API symmetry. Network videos start PiP with placeholder media so the
/// first frame loads inside the PiP window. See [FlPiPWindow] for the pixel unit.
@immutable
class FlPiPVideoIOSOptions {
  const FlPiPVideoIOSOptions({
    required this.source,
    this.loop = false,
    this.muted = false,
    this.window,
    this.showControls = true,
  });

  /// 视频来源。 / The video source.
  final FlPiPVideoSource source;

  /// 是否循环播放。 / Whether playback restarts automatically at the end.
  final bool loop;

  /// 是否静音。 / Whether the audio is muted.
  final bool muted;

  /// 内联视频层的宽高与位置，单位物理像素（px）。
  ///
  /// iOS 把内联视频层固定为 0.01pt 并放在左上角（等同于隐藏），该参数不影响展示。
  ///
  /// The inline video layer size and position in physical pixels. iOS hides the inline layer,
  /// so the value has no visible effect.
  final FlPiPWindow? window;

  /// 是否显示系统画中画面板。iOS 的面板由系统管理，无法隐藏，该参数在 iOS 上不起作用。
  ///
  /// Whether the system PiP panel is shown. iOS manages the panel itself and cannot hide it, so
  /// the value has no effect on iOS.
  final bool showControls;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{
    ...source.toMap(),
    'loop': loop,
    'muted': muted,
    if (window != null) ...window!.toMap(),
    'controls': <String, Object?>{'enabled': showControls},
  };
}

/// HarmonyOS 视频播放参数。
///
/// 提供两个构造函数，对应鸿蒙的两种承载方式：
/// - [FlPiPVideoHarmonyOSOptions.systemPip]（默认）：系统画中画，只用 [aspectRatio]；不传时按
///   视频原始宽高比，窗口大小与位置由系统管理；面板由系统绘制，**不支持任何自定义控制面板参数**。
/// - [FlPiPVideoHarmonyOSOptions.overlay]：应用内弹窗，[window] 的宽高固定窗口尺寸，视频按原始
///   比例等比缩放并撑满其中一条边，其余方向留黑边，不会拉伸画面；按下面的开关绘制与 Android
///   一致的控制面板。
///
/// HarmonyOS video options with one constructor per presentation mode. See [FlPiPWindow] for the
/// pixel unit.
@immutable
class FlPiPVideoHarmonyOSOptions {
  /// 系统画中画：可跨应用展示，只使用 [aspectRatio]，`null` 时按视频原始宽高比；实际窗口大小
  /// 与位置由系统管理。
  ///
  /// The system PiP window; only [aspectRatio] is used and `null` follows the video's intrinsic
  /// ratio. The system controls the actual size and position.
  const FlPiPVideoHarmonyOSOptions.systemPip({
    required this.source,
    this.loop = false,
    this.muted = false,
    this.aspectRatio,
  }) : mode = FlPiPPresentationMode.systemPip,
       window = null,
       cornerRadius = 12,
       showControls = false,
       showPlayPause = false,
       showProgress = false,
       showClose = false,
       allowDrag = false,
       autoHide = false;

  /// 应用内弹窗：只在 App 前台可见，使用与 Android 一致的自定义控制面板。
  ///
  /// [window] 的宽高固定窗口尺寸，视频按原始比例等比缩放，撑满其中一条边且不拉伸画面。
  ///
  /// The in-app overlay with the same custom control panel as Android. The window keeps the
  /// [window] size while the video aspect-fits inside it without being stretched.
  const FlPiPVideoHarmonyOSOptions.overlay({
    required this.source,
    this.loop = false,
    this.muted = false,
    this.window,
    this.cornerRadius = 12,
    this.showControls = true,
    this.showPlayPause = true,
    this.showProgress = true,
    this.showClose = true,
    this.allowDrag = true,
    this.autoHide = true,
  }) : mode = FlPiPPresentationMode.overlay,
       aspectRatio = null;

  /// 视频来源。 / The video source.
  final FlPiPVideoSource source;

  /// 是否循环播放。 / Whether playback restarts automatically at the end.
  final bool loop;

  /// 是否静音。 / Whether the audio is muted.
  final bool muted;

  /// 视频控件宽高与位置，单位物理像素（px）；仅 [FlPiPPresentationMode.overlay] 生效，用于固定
  /// 浮窗尺寸与位置，视频在其中等比缩放并撑满一条边。
  ///
  /// The video view size and position in physical pixels; only used by
  /// [FlPiPPresentationMode.overlay], which keeps that size and position and aspect-fits the video
  /// inside it.
  final FlPiPWindow? window;

  /// 系统画中画宽高比；仅 [FlPiPPresentationMode.systemPip] 生效，`null` 时按视频原始宽高比。
  ///
  /// The system PiP aspect ratio; only used by [FlPiPPresentationMode.systemPip]. `null` follows
  /// the video's intrinsic ratio.
  final FlPiPAspectRatio? aspectRatio;

  /// 承载方式，默认 [FlPiPPresentationMode.systemPip]。
  ///
  /// How the video is presented, [FlPiPPresentationMode.systemPip] by default.
  final FlPiPPresentationMode mode;

  /// 应用内弹窗圆角，单位 vp；系统画中画忽略。 / Overlay corner radius in vp; ignored by the system PiP.
  final double cornerRadius;

  /// 是否显示整个控制面板，仅应用内弹窗生效。
  ///
  /// Whether the control panel is shown; only used by the application overlay.
  final bool showControls;

  /// 是否显示播放/暂停按钮，仅应用内弹窗生效。
  final bool showPlayPause;

  /// 是否显示进度条，仅应用内弹窗生效。
  final bool showProgress;

  /// 是否显示关闭按钮，仅应用内弹窗生效。
  final bool showClose;

  /// 是否允许拖动，仅应用内弹窗生效。
  final bool allowDrag;

  /// 控制面板是否自动隐藏，仅应用内弹窗生效。
  final bool autoHide;

  /// 转换为原生参数表。 / Converts to the native argument map.
  Map<String, Object?> toMap() => <String, Object?>{
    ...source.toMap(),
    'loop': loop,
    'muted': muted,
    'mode': mode.value,
    if (mode == FlPiPPresentationMode.overlay) ...<String, Object?>{
      if (window != null) ...window!.toMap(),
      'cornerRadius': cornerRadius,
      'controls': <String, Object?>{
        'enabled': showControls,
        'showPlayPause': showPlayPause,
        'showProgress': showProgress,
        'showClose': showClose,
        'allowDrag': allowDrag,
        'autoHide': autoHide,
      },
    },
    if (mode == FlPiPPresentationMode.systemPip && aspectRatio != null) ...aspectRatio!.toMap(),
  };
}

/// 使用原生视频窗口播放视频的统一入口。
///
/// 支持 `asset` / `file` / `network` 三种来源。一次性传入三端参数，原生只使用当前平台对应的
/// 那一份；未传入当前平台的参数时抛出 [FlPiPException]（`invalid_configuration`）。
///
/// 三端承载方式：iOS 使用系统画中画；Android 视频固定使用系统弹窗
/// （[FlPiPPresentationMode.overlay]）；HarmonyOS 支持系统画中画（默认）与应用内弹窗两种。
///
/// The unified entry point for playing videos in the native window.
class FlPiPVideo {
  FlPiPVideo._();

  /// 共享实例。 / The shared instance.
  static final FlPiPVideo instance = FlPiPVideo._();

  /// 返回共享实例。 / Returns the shared instance.
  factory FlPiPVideo() => instance;

  /// 原生视频窗口上报的事件，包含控制面板操作与进度。
  ///
  /// Events emitted by the native video window, including panel actions and progress.
  Stream<FlPiPVideoEvent> get events => FlPiP.instance.videoEvents;

  /// 在原生视频窗口中播放视频。
  ///
  /// 只使用当前平台对应的参数类：[android] 用于 Android、[ios] 用于 iOS、
  /// [harmonyOS] 用于鸿蒙；其余参数可以为 `null`。当前平台的参数为空时抛出
  /// [FlPiPException]（`invalid_configuration`）。鸿蒙系统画中画的宽高比不合法时抛出
  /// [FlPiPAspectRatioNotSupportedException]。
  ///
  /// [FlPiPWindow] 中的宽高与位置全部是物理像素（px）。
  ///
  /// Plays a video in the native window, using only the options of the current platform.
  Future<bool> play({
    FlPiPVideoAndroidOptions? android,
    FlPiPVideoIOSOptions? ios,
    FlPiPVideoHarmonyOSOptions? harmonyOS,
  }) async {
    if (!FlPiP.instance.isSupportedPlatform) return false;
    final FlPiPAspectRatio? harmonyRatio = harmonyOS?.aspectRatio;
    if (FlPiP.instance.isHarmonyOSPlatform &&
        harmonyOS?.mode == FlPiPPresentationMode.systemPip &&
        harmonyRatio != null &&
        !harmonyRatio.isSupported) {
      throw FlPiPAspectRatioNotSupportedException(harmonyRatio);
    }
    final Map<String, Object?>? arguments = FlPiP.instance.isAndroidPlatform
        ? android?.toMap()
        : (FlPiP.instance.isHarmonyOSPlatform ? harmonyOS?.toMap() : ios?.toMap());
    if (arguments == null) {
      throw const FlPiPException(
        FlPiPErrorCode.invalidConfiguration,
        message: 'The video options of the current platform must not be null',
      );
    }
    return _invoke('playVideo', arguments);
  }

  /// 关闭原生视频窗口。 / Stops the native video window.
  Future<bool> stop() => _invoke('stopVideo', const <String, Object?>{});

  /// 暂停或恢复播放。 / Pauses or resumes playback.
  Future<bool> setPlaying(bool playing) => _invoke('setVideoPlaying', <String, Object?>{'playing': playing});

  /// 暂停播放。 / Pauses playback.
  Future<bool> pause() => setPlaying(false);

  /// 恢复播放。 / Resumes playback.
  Future<bool> resume() => setPlaying(true);

  /// 跳转到 [position]。 / Seeks to [position].
  Future<bool> seek(Duration position) =>
      _invoke('seekVideo', <String, Object?>{'positionMs': position.inMilliseconds});

  /// 按 [offset] 跳转，负值快退，正值快进。
  ///
  /// Seeks by [offset]; negative rewinds and positive fast-forwards.
  Future<bool> seekBy(Duration offset) => _invoke('seekVideoBy', <String, Object?>{'offsetMs': offset.inMilliseconds});

  /// 停止播放并回到开头，保持窗口打开。
  ///
  /// Stops playback, rewinds to the beginning and keeps the window open.
  Future<bool> stopPlayback() => _invoke('stopVideoPlayback', const <String, Object?>{});

  /// 设置播放速度，范围 `0.25 ~ 4.0`。 / Sets the playback speed, `0.25 ~ 4.0`.
  Future<bool> setSpeed(double speed) async {
    if (!FlPiP.instance.isSupportedPlatform) return false;
    if (speed < 0.25 || speed > 4.0) {
      throw const FlPiPException(
        FlPiPErrorCode.invalidConfiguration,
        message: 'The playback speed must be between 0.25 and 4.0',
      );
    }
    return _invoke('setVideoSpeed', <String, Object?>{'speed': speed});
  }

  /// 设置音量，范围 `0.0 ~ 1.0`。 / Sets the volume, `0.0 ~ 1.0`.
  Future<bool> setVolume(double volume) async {
    if (!FlPiP.instance.isSupportedPlatform) return false;
    if (volume < 0.0 || volume > 1.0) {
      throw const FlPiPException(
        FlPiPErrorCode.invalidConfiguration,
        message: 'The volume must be between 0.0 and 1.0',
      );
    }
    return _invoke('setVideoVolume', <String, Object?>{'volume': volume});
  }

  /// 开启或关闭循环播放。 / Enables or disables looping.
  Future<bool> setLooping(bool loop) => _invoke('setVideoLooping', <String, Object?>{'loop': loop});

  /// 当前播放状态，没有视频窗口时返回 `null`。
  ///
  /// The current playback status, or `null` when no video window is active.
  Future<FlPiPVideoStatus?> get status async {
    if (!FlPiP.instance.isSupportedPlatform) return null;
    try {
      final Map<Object?, Object?>? map = await _channel.invokeMethod<Map<Object?, Object?>>('getVideoStatus');
      return map == null ? null : FlPiPVideoStatus.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (exception) {
      throw FlPiPException.fromPlatformException(exception);
    }
  }

  /// 是否已有视频窗口。 / Whether a video window is currently active.
  Future<bool> get isActive async {
    if (!FlPiP.instance.isSupportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('isVideoActive') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 统一调用原生方法；不支持的平台直接返回 `false`。
  ///
  /// Invokes a native method; unsupported platforms return `false`.
  Future<bool> _invoke(String method, Map<String, Object?> arguments) async {
    if (!FlPiP.instance.isSupportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      throw const FlPiPException(FlPiPErrorCode.notSupported);
    } on PlatformException catch (exception) {
      throw FlPiPException.fromPlatformException(exception);
    }
  }
}
