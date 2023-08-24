import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PiPBuilderCallback = Widget Function(PiPStatus status);

class PiPBuilder extends StatefulWidget {
  const PiPBuilder({
    super.key,
    required this.builder,
  });

  final PiPBuilderCallback builder;

  @override
  State<PiPBuilder> createState() => _PiPBuilderState();
}

class _PiPBuilderState extends State<PiPBuilder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final value = await FlPiP().isAvailable;
      if (!value) return;
      FlPiP().status.addListener(listener);
      await FlPiP().isActive;
    });
  }

  void listener() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(FlPiP().status.value);

  @override
  void dispose() {
    FlPiP().status.removeListener(listener);
    super.dispose();
  }
}

enum PiPStatus {
  /// Show picture in picture
  enabled,

  /// Does not display picture-in-picture
  disabled,

  /// Picture-in-picture is not supported
  unavailable
}

const _channel = MethodChannel('fl_pip');

class FlPiP {
  factory FlPiP() => _singleton ??= FlPiP._();

  static FlPiP? _singleton;

  FlPiP._() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPiPStatus':
          status.value = PiPStatus.values[call.arguments as int];
          break;
      }
    });
  }

  final ValueNotifier<PiPStatus> status = ValueNotifier(PiPStatus.disabled);

  /// 开启画中画
  /// enable picture-in-picture
  Future<bool> enable({
    FlPiPAndroidConfig android = const FlPiPAndroidConfig(),
    FlPiPiOSConfig ios = const FlPiPiOSConfig(),
  }) async {
    if (!(_isAndroid || _isIos)) {
      return false;
    }
    if (_isAndroid && !(android.aspectRatio.fitsInAndroidRequirements)) {
      throw RationalNotMatchingAndroidRequirementsException(
          android.aspectRatio);
    }
    final state = await _channel.invokeMethod<bool>(
        'enable', _isAndroid ? android.toMap() : ios.toMap());
    return state ?? false;
  }

  /// 开启画中画 创建新的 engine
  /// enable picture-in-picture use Engine
  Future<bool> enableWithEngine({
    FlPiPAndroidConfig android = const FlPiPAndroidConfig(),
    FlPiPiOSConfig ios = const FlPiPiOSConfig(),
  }) async {
    if (!(_isAndroid || _isIos)) {
      return false;
    }
    final state = await _channel.invokeMethod<bool>(
        'enableWithEngine', {..._isAndroid ? android.toMap() : ios.toMap()});
    return state ?? false;
  }

  /// 关闭画中画
  /// disable picture-in-picture
  Future<bool> disable() async {
    final state = await _channel.invokeMethod<bool>('disable');
    return state ?? false;
  }

  /// 画中画状态
  /// Picture-in-picture window state
  Future<PiPStatus> get isActive async {
    final int? state = await _channel.invokeMethod<int>('isActive');
    status.value = PiPStatus.values[state ?? 2];
    return status.value;
  }

  /// 是否支持画中画
  /// Whether to support picture in picture
  Future<bool> get isAvailable async {
    final bool? state = await _channel.invokeMethod('available');
    return state ?? false;
  }

  /// 切换前后台
  /// Toggle front and back
  /// ios仅支持切换后台
  /// ios supports background switching only
  Future<void> toggle(AppState state) =>
      _channel.invokeMethod('toggle', state == AppState.foreground);
}

enum AppState {
  /// 前台
  foreground,

  /// 后台
  background,
}

class FlPiPConfig {
  const FlPiPConfig({required this.path, this.packageName, this.rect});

  ///  ios 画中画弹出前视频的初始大小和位置,默认 [left:width/2,top:height/2,width:0.1,height:0.1]
  ///  ios The initial size and position of the video before the picture-in-picture pops up,default [left:width/2,top:height/2,width:0.1,height:0.1]
  ///  android 系统弹窗的大小和位置 ,默认 [left:width/2,top:height/2,width:300,height:300]
  ///  android The size and position of the system popup,default [left:width/2,top:height/2,width:300,height:300]
  final Rect? rect;

  final String path;

  /// 资源地址的 packageName
  /// Set packageName to the asset address
  /// 如果使用你自己项目的资源文件 请设置[packageName]为null
  /// If using your own project's resource files, set [packageName] to null
  final String? packageName;

  Map<String, dynamic> toMap() => {
        'left': rect?.left,
        'top': rect?.top,
        'width': rect?.width,
        'height': rect?.height,
        'packageName': packageName,
        'path': path
      };
}

/// android 画中画配置
/// android picture-in-picture configuration
class FlPiPAndroidConfig extends FlPiPConfig {
  const FlPiPAndroidConfig(
      {
      /// Android 悬浮框右上角的关闭按钮的图片地址
      /// Android The image address of the Close button in the upper right corner of the floating
      super.path = 'assets/close.png',
      super.packageName = 'fl_pip',
      this.aspectRatio = const Rational.square(),
      super.rect});

  /// android 画中画窗口宽高比例
  /// android picture in picture window width-height ratio
  final Rational aspectRatio;

  @override
  Map<String, dynamic> toMap() => {...aspectRatio.toMap(), ...super.toMap()};

  String toHex(Color color) =>
      '#${color.alpha.toRadixString(16).padLeft(2, '0')}'
      '${color.red.toRadixString(16).padLeft(2, '0')}'
      '${color.green.toRadixString(16).padLeft(2, '0')}'
      '${color.blue.toRadixString(16).padLeft(2, '0')}';
}

/// ios 画中画配置
/// ios picture-in-picture configuration
class FlPiPiOSConfig extends FlPiPConfig {
  const FlPiPiOSConfig(
      {
      /// 视频路径 用于修修改画中画尺寸
      /// The video [path] is used to modify the size of the picture in picture
      super.path = 'assets/landscape.mp4',
      super.packageName = 'fl_pip',
      this.enableControls = false,
      this.enablePlayback = false,
      super.rect});

  /// 显示播放控制
  /// Display play control
  final bool enableControls;

  /// 开启播放速度
  /// Turn on playback speed
  final bool enablePlayback;

  @override
  Map<String, dynamic> toMap() => {
        ...super.toMap(),
        'enableControls': enableControls,
        'enablePlayback': enablePlayback,
      };
}

/// android 画中画宽高比
/// android picture in picture aspect ratio
class Rational {
  final int numerator;
  final int denominator;

  double get aspectRatio => numerator / denominator;

  const Rational(this.numerator, this.denominator);

  const Rational.square()
      : numerator = 1,
        denominator = 1;

  const Rational.landscape()
      : numerator = 16,
        denominator = 9;

  const Rational.maxLandscape()
      : numerator = 239,
        denominator = 100;

  const Rational.maxVertical()
      : numerator = 100,
        denominator = 239;

  const Rational.vertical()
      : numerator = 9,
        denominator = 16;

  @override
  String toString() =>
      'Rational(numerator: $numerator, denominator: $denominator)';

  Map<String, dynamic> toMap() =>
      {'numerator': numerator, 'denominator': denominator};
}

extension on Rational {
  bool get fitsInAndroidRequirements {
    final aspectRatio = numerator / denominator;
    const min = 1 / 2.39;
    const max = 2.39;
    return (min <= aspectRatio) && (aspectRatio <= max);
  }
}

class RationalNotMatchingAndroidRequirementsException implements Exception {
  final Rational rational;

  RationalNotMatchingAndroidRequirementsException(this.rational);

  @override
  String toString() => 'RationalNotMatchingAndroidRequirementsException('
      '${rational.numerator}/${rational.denominator} does not fit into '
      'Android-supported aspect ratios. Boundaries: '
      'min: 1/2.39, max: 2.39/1. '
      ')';
}

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
