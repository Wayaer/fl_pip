import 'dart:async';

import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 视频示例使用的来源。 / Video sources used by the demo.
enum DemoVideoSource {
  /// 本地横屏视频 h.mp4。
  landscape,

  /// 本地竖屏视频 v.mp4。
  portrait,

  /// 远程 URL 视频。
  url,
}

/// 一条 API 调用记录。 / One API call recorded by the example pages.
@immutable
class DemoLogEntry {
  const DemoLogEntry({required this.api, required this.result});

  /// 展示在结果上方的 API 名。 / The API name shown above the result.
  final String api;

  /// 格式化后的返回值或异常。 / The formatted result or exception.
  final String result;
}

/// 示例程序共享的状态与操作。 / Shared state and actions used by every example page.
class DemoController extends ChangeNotifier {
  static const String landscapeVideoPath = 'assets/h.mp4';
  static const String portraitVideoPath = 'assets/v.mp4';
  static const String urlVideoPath = 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

  static const List<FlPiPAspectRatio> aspectRatios = <FlPiPAspectRatio>[
    FlPiPAspectRatio.square(),
    FlPiPAspectRatio.landscape(),
    FlPiPAspectRatio.vertical(),
    FlPiPAspectRatio.maxLandscape(),
    FlPiPAspectRatio.maxVertical(),
    FlPiPAspectRatio(7, 4),
    FlPiPAspectRatio(3, 1),
  ];

  /// 画中画引擎名称；首次 present 时原生会用 `pipMain` 入口补建。
  ///
  /// The PiP engine name; the native side creates it with the `pipMain` entry point on the first
  /// present call when it does not exist yet.
  static const String pipEngineName = 'pipMain';

  /// 是否在关闭画中画时销毁引擎。 / Whether the engine is destroyed when the window closes.
  bool destroyEngineOnDismiss = true;

  /// 与插件默认值一致：Android 默认悬浮弹窗，HarmonyOS 默认系统画中画。
  ///
  /// Matches the plugin defaults: the overlay on Android and the system PiP on HarmonyOS.
  FlPiPPresentationMode mode = defaultTargetPlatform == TargetPlatform.android
      ? FlPiPPresentationMode.overlay
      : FlPiPPresentationMode.systemPip;
  FlPiPAspectRatio aspectRatio = const FlPiPAspectRatio.square();
  double overlayCornerRadius = 12;

  bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// 鸿蒙版 Flutter SDK 才有 TargetPlatform.ohos，这里用 name 判断以兼容官方 SDK。
  bool get isHarmonyOS => defaultTargetPlatform.name == 'ohos';

  /// 自定义窗口：页面中用逻辑像素调整，传给原生前按 devicePixelRatio 换算成物理像素。
  ///
  /// Custom window: adjusted in logical pixels by the UI and converted to physical pixels before
  /// it is passed to the native side.
  bool useCustomWindow = false;
  double windowLeft = 0;
  double windowTop = 0;
  double windowWidth = 480;
  double windowHeight = 270;

  /// 当前窗口参数（物理像素），未启用时返回 null。
  ///
  /// The current window in physical pixels, or null when it is disabled.
  FlPiPWindow? window(double pixelRatio) => useCustomWindow
      ? FlPiPWindow(
          width: windowWidth * pixelRatio,
          height: windowHeight * pixelRatio,
          top: windowTop * pixelRatio,
          left: windowLeft * pixelRatio,
        )
      : null;

  FlPiPAndroidOptions androidOptions(double pixelRatio) => mode == FlPiPPresentationMode.overlay
      ? FlPiPAndroidOptions.overlay(window: window(pixelRatio), cornerRadius: overlayCornerRadius)
      : FlPiPAndroidOptions.systemPip(aspectRatio: aspectRatio);

  /// iOS 不传视频与音频资源：原生把引擎渲染进画中画，主引擎才按 window 尺寸生成占位媒体。
  ///
  /// iOS needs no media assets: the engine is rendered in PiP; only the main engine falls back to
  /// placeholder media generated from the window.
  FlPiPIOSOptions iosOptions(double pixelRatio) => FlPiPIOSOptions(window: window(pixelRatio));

  FlPiPHarmonyOSOptions harmonyOSOptions(double pixelRatio) => mode == FlPiPPresentationMode.overlay
      ? FlPiPHarmonyOSOptions.overlay(window: window(pixelRatio), cornerRadius: overlayCornerRadius)
      : FlPiPHarmonyOSOptions.systemPip(aspectRatio: aspectRatio);

  final List<FlPiPVideoEvent> videoEvents = <FlPiPVideoEvent>[];
  final List<FlPiPMessage> engineMessages = <FlPiPMessage>[];
  final List<DemoLogEntry> calls = <DemoLogEntry>[];

  StreamSubscription<FlPiPVideoEvent>? videoEventSubscription;
  StreamSubscription<FlPiPMessage>? engineMessageSubscription;

  double playbackSpeed = 1.0;
  double mediaVolume = 1.0;
  double mediaSeekSeconds = 0;

  /// 视频控件自定义宽高与位置：页面中用逻辑像素，传给原生前换算成物理像素。
  ///
  /// The video view size and offsets in logical pixels, converted to physical pixels before use.
  bool useCustomVideoWindow = false;
  double videoWidth = 360;
  double videoHeight = 202;
  double videoTop = 0;
  double videoLeft = 0;

  /// 视频系统画中画是否使用自定义宽高比；关闭时跟随视频原始宽高比。
  ///
  /// Whether the video system PiP uses a custom aspect ratio; follows the video when disabled.
  bool useVideoAspectRatio = false;
  FlPiPAspectRatio videoAspectRatio = const FlPiPAspectRatio.landscape();

  FlPiPWindow? videoWindow(double pixelRatio) => useCustomVideoWindow
      ? FlPiPWindow(
          width: videoWidth * pixelRatio,
          height: videoHeight * pixelRatio,
          top: videoTop * pixelRatio,
          left: videoLeft * pixelRatio,
        )
      : null;

  double mediaCornerRadius = 12;
  bool mediaLoop = true;
  bool mediaMuted = false;
  DemoVideoSource videoSource = DemoVideoSource.landscape;
  final TextEditingController urlController = TextEditingController(text: urlVideoPath);

  bool controlsEnabled = true;
  bool showPlayPause = true;
  bool showProgress = true;
  bool showClose = true;
  bool allowDrag = true;
  bool autoHide = true;

  bool _disposed = false;

  DemoController() {
    videoEventSubscription = FlPiP.instance.videoEvents.listen((FlPiPVideoEvent event) {
      if (_disposed) return;
      videoEvents.insert(0, event);
      if (videoEvents.length > 10) videoEvents.removeLast();
      notifyListeners();
    });
    engineMessageSubscription = FlPiP.instance.messages.listen((FlPiPMessage message) {
      if (_disposed) return;
      engineMessages.insert(0, message);
      if (engineMessages.length > 10) engineMessages.removeLast();
      notifyListeners();
    });
  }

  /// 根据当前来源选择示例视频；URL 模式使用输入框内容。
  ///
  /// Picks the demo video for the current source; URL mode uses the text field.
  FlPiPVideoSource get selectedVideoSource => switch (videoSource) {
    DemoVideoSource.landscape => const FlPiPVideoSource.asset(landscapeVideoPath),
    DemoVideoSource.portrait => const FlPiPVideoSource.asset(portraitVideoPath),
    DemoVideoSource.url => FlPiPVideoSource.network(
      urlController.text.trim().isEmpty ? urlVideoPath : urlController.text.trim(),
    ),
  };

  FlPiPVideoAndroidOptions androidVideoOptions(double pixelRatio) => FlPiPVideoAndroidOptions(
    source: selectedVideoSource,
    loop: mediaLoop,
    muted: mediaMuted,
    window: videoWindow(pixelRatio),
    cornerRadius: mediaCornerRadius,
    showControls: controlsEnabled,
    showPlayPause: showPlayPause,
    showProgress: showProgress,
    showClose: showClose,
    allowDrag: allowDrag,
    autoHide: autoHide,
  );

  /// iOS 画中画窗口比例由视频本身决定；内联视频层在原生侧固定隐藏，window 不影响展示。
  ///
  /// iOS sizes the PiP window from the video; the inline layer is hidden natively, so window has
  /// no visible effect.
  FlPiPVideoIOSOptions iosVideoOptions(double pixelRatio) => FlPiPVideoIOSOptions(
    source: selectedVideoSource,
    loop: mediaLoop,
    muted: mediaMuted,
    window: videoWindow(pixelRatio),
    showControls: controlsEnabled,
  );

  FlPiPVideoHarmonyOSOptions harmonyOSVideoOptions(double pixelRatio) => mode == FlPiPPresentationMode.overlay
      ? FlPiPVideoHarmonyOSOptions.overlay(
          source: selectedVideoSource,
          loop: mediaLoop,
          muted: mediaMuted,
          window: videoWindow(pixelRatio),
          cornerRadius: mediaCornerRadius,
          showControls: controlsEnabled,
          showPlayPause: showPlayPause,
          showProgress: showProgress,
          showClose: showClose,
          allowDrag: allowDrag,
          autoHide: autoHide,
        )
      : FlPiPVideoHarmonyOSOptions.systemPip(
          source: selectedVideoSource,
          loop: mediaLoop,
          muted: mediaMuted,
          aspectRatio: useVideoAspectRatio ? videoAspectRatio : null,
        );

  /// 开启画中画；[pipEngineName] 指定的引擎不存在时由原生补建。
  ///
  /// 窗口中的宽高与位置按 devicePixelRatio 换算成物理像素。
  ///
  /// Enables PiP; the native side creates the engine named [pipEngineName] when it does not exist.
  /// The window size and offsets are converted to physical pixels.
  Future<void> present(BuildContext context) {
    final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return record(
      'present(${mode.name})',
      () => isAndroid
          ? FlPiP.instance.present(
              name: pipEngineName,
              destroyEngineOnDismiss: destroyEngineOnDismiss,
              android: androidOptions(pixelRatio),
            )
          : (isHarmonyOS
                ? FlPiP.instance.present(
                    name: pipEngineName,
                    destroyEngineOnDismiss: destroyEngineOnDismiss,
                    harmonyOS: harmonyOSOptions(pixelRatio),
                  )
                : FlPiP.instance.present(
                    name: pipEngineName,
                    destroyEngineOnDismiss: destroyEngineOnDismiss,
                    ios: iosOptions(pixelRatio),
                  )),
    );
  }

  Future<void> dismiss() => record('dismiss()', () => FlPiP.instance.dismiss());

  /// 播放视频，只传入当前平台的参数。 / Plays a video with only the current platform options.
  Future<void> playVideo(BuildContext context) {
    final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return record(
      'FlPiPVideo.play()',
      () => FlPiPVideo.instance.play(
        android: isAndroid ? androidVideoOptions(pixelRatio) : null,
        ios: isIOS ? iosVideoOptions(pixelRatio) : null,
        harmonyOS: isHarmonyOS ? harmonyOSVideoOptions(pixelRatio) : null,
      ),
    );
  }

  Future<void> stopVideo() => record('FlPiPVideo.stop()', () => FlPiPVideo.instance.stop());

  Future<void> checkAvailable() => record('isAvailable', () => FlPiP.instance.isAvailable);

  Future<void> checkActive() => record('isActive', () => FlPiP.instance.isActive);

  Future<void> checkVideoActive() => record('isVideoActive', () => FlPiPVideo.instance.isActive);

  Future<void> seekAbsolute() =>
      record('seekVideo()', () => FlPiPVideo.instance.seek(Duration(milliseconds: (mediaSeekSeconds * 1000).round())));

  Future<void> setLooping() => record('setVideoLooping($mediaLoop)', () => FlPiPVideo.instance.setLooping(mediaLoop));

  Future<void> sendMessage() =>
      record('send()', () => FlPiP.instance.send('main/message', arguments: <String, Object?>{'from': 'main'}));

  Future<void> toggle(FlPiPAppState state) => record('toggle(FlPiPAppState.${state.name})', () async {
    await FlPiP.instance.toggle(state);
    return 'sent';
  });

  void setPlaybackSpeed(double value) {
    playbackSpeed = value;
    FlPiPVideo.instance.setSpeed(value);
    notifyListeners();
  }

  void setMediaVolume(double value) {
    mediaVolume = value;
    FlPiPVideo.instance.setVolume(value);
    notifyListeners();
  }

  /// 调用一个示例 API，并记录返回值或抛出的异常。
  /// Invokes one demo call and records its return value or thrown exception.
  Future<void> record(String api, Future<Object?> Function() invocation) async {
    String result;
    try {
      result = describe(await invocation());
    } on FlPiPAspectRatioNotSupportedException catch (exception) {
      result = '异常：$exception';
    } catch (error) {
      result = '异常：$error';
    }
    if (_disposed) return;
    calls.insert(0, DemoLogEntry(api: api, result: result));
    if (calls.length > 12) calls.removeLast();
    notifyListeners();
  }

  /// 把 API 返回值格式化成结果列表中的文本。
  /// Formats a value returned by an API for the result list.
  String describe(Object? value) {
    if (value is FlPiPStatusInfo) {
      return 'FlPiPStatusInfo(\n'
          '  status: ${value.status.name},\n'
          '  mode: ${value.mode?.value},\n'
          '  hasEngine: ${value.hasEngine},\n'
          ')';
    }
    if (value is FlMultiEngineInfo) {
      return 'FlMultiEngineInfo(\n'
          '  name: ${value.name},\n'
          '  entrypoint: ${value.entrypoint},\n'
          '  state: ${value.state.name},\n'
          '  isMain: ${value.isMain},\n'
          ')';
    }
    return '$value';
  }

  void clearResults() {
    calls.clear();
    notifyListeners();
  }

  /// 修改页面状态并通知所有页面刷新。
  /// Mutates demo state and rebuilds every listening page.
  void update(VoidCallback action) {
    action();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    videoEventSubscription?.cancel();
    engineMessageSubscription?.cancel();
    urlController.dispose();
    super.dispose();
  }
}
