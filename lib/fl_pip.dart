import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PiPBuilderCallback = Widget Function(PiPStatus status);

class PiPBuilder extends StatefulWidget {
  const PiPBuilder({
    super.key,
    required this.pip,
    required this.builder,
  });

  final FlPiP pip;
  final PiPBuilderCallback builder;

  @override
  State<PiPBuilder> createState() => _PiPBuilderState();
}

class _PiPBuilderState extends State<PiPBuilder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final value = await widget.pip.isAvailable;
      if (!value) return;
      widget.pip.status.addListener(listener);
      await widget.pip.isActive;
    });
  }

  void listener() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(widget.pip.status.value);

  @override
  void dispose() {
    widget.pip.status.removeListener(listener);
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

class FlPiP {
  factory FlPiP() => _singleton ??= FlPiP._();

  static FlPiP? _singleton;

  FlPiP._() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "onPiPStatus":
          final state = call.arguments as int;
          status.value = PiPStatus.values[state];
      }
    });
  }

  final _channel = const MethodChannel('fl_pip');

  final ValueNotifier<PiPStatus> status = ValueNotifier(PiPStatus.unavailable);

  /// 开启画中画
  /// enable picture-in-picture
  Future<PiPStatus> enable({
    FlPiPAndroidConfig android = const FlPiPAndroidConfig(),
    FlPiPiOSConfig ios = const FlPiPiOSConfig(),
  }) async {
    if (!(_isAndroid || _isIos)) {
      return PiPStatus.unavailable;
    }
    if (_isAndroid && !(android.aspectRatio.fitsInAndroidRequirements)) {
      throw RationalNotMatchingAndroidRequirementsException(
          android.aspectRatio);
    }
    final int? state = await _channel.invokeMethod<int>(
        'enable', _isAndroid ? android.toMap() : ios.toMap());
    status.value = PiPStatus.values[state ?? 2];
    return status.value;
  }

  /// 开启画中画 创建新的 engine
  /// enable picture-in-picture use Engine
  Future<PiPStatus> enableWithEngine({
    FlPiPAndroidConfig android = const FlPiPAndroidConfig(),
    FlPiPiOSConfig ios = const FlPiPiOSConfig(),
  }) async {
    if (!(_isAndroid || _isIos)) {
      return PiPStatus.unavailable;
    }
    final int? state = await _channel.invokeMethod<int>(
        'enableWithEngine', {..._isAndroid ? android.toMap() : ios.toMap()});
    status.value = PiPStatus.values[state ?? 2];
    return status.value;
  }

  /// 关闭画中画
  /// disable picture-in-picture
  Future<PiPStatus> disable() async {
    final int? state = await _channel.invokeMethod<int>('disable');
    status.value = PiPStatus.values[state ?? 1];
    return status.value;
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

/// android 画中画配置
/// android picture-in-picture configuration
class FlPiPAndroidConfig {
  const FlPiPAndroidConfig({
    this.aspectRatio = const Rational.square(),
    this.size = const Size(400, 600),
  });

  /// android 画中画窗口宽高比例
  /// android picture in picture window width-height ratio
  final Rational aspectRatio;

  /// 当使用mainName 的时候窗口的宽高
  /// The width and height of the window when mainName is used
  final Size size;

  Map<String, dynamic> toMap() => {
        ...aspectRatio.toMap(),
        'width': size.width,
        'height': size.height,
      };
}

/// ios 画中画配置
/// ios picture-in-picture configuration
class FlPiPiOSConfig {
  const FlPiPiOSConfig({
    this.path = 'assets/landscape.mp4',
    this.packageName = 'fl_pip',
    this.enableControls = false,
    this.enablePlayback = false,
  });

  /// 视频路径 用于修修改画中画尺寸
  /// The video [path] is used to modify the size of the picture in picture
  final String path;

  /// 配置视频地址的 packageName
  /// Set packageName to the video address
  /// 如果使用你自己项目的资源文件 请设置[packageName]为null
  /// If using your own project's resource files, set [packageName] to null
  final String? packageName;

  /// 显示播放控制
  /// Display play control
  final bool enableControls;

  /// 开启播放速度
  /// Turn on playback speed
  final bool enablePlayback;

  Map<String, dynamic> toMap() => {
        'enableControls': enableControls,
        'enablePlayback': enablePlayback,
        'packageName': packageName,
        'path': path
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
