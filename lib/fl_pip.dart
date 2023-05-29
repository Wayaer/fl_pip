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
      await widget.pip.isActive();
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

enum PiPStatus { enabled, disabled, unavailable }

class FlPiP {
  factory FlPiP() => _singleton ??= FlPiP._();

  FlPiP._() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "onPiPStatus":
          final state = call.arguments as int;
          status.value = PiPStatus.values[state];
      }
    });
  }

  static FlPiP? _singleton;

  final _channel = const MethodChannel('fl_pip');

  final ValueNotifier<PiPStatus> status = ValueNotifier(PiPStatus.unavailable);

  Future<PiPStatus> enable({
    required FlPiPAndroidConfig androidConfig,
    required FlPiPiOSConfig iosConfig,
  }) async {
    if (_isAndroid && !(androidConfig.aspectRatio.fitsInAndroidRequirements)) {
      throw RationalNotMatchingAndroidRequirementsException(
          androidConfig.aspectRatio);
    }
    final int? state = await _channel.invokeMethod<int>(
        'enable', _isAndroid ? androidConfig.toMap() : iosConfig.toMap());
    status.value = PiPStatus.values[state ?? 2];
    return status.value;
  }

  /// 弹窗是否显示
  Future<PiPStatus> isActive() async {
    final int? state = await _channel.invokeMethod<int>('isActive');
    status.value = PiPStatus.values[state ?? 2];
    return status.value;
  }

  /// 是否支持
  Future<bool> get isAvailable async {
    final bool? state = await _channel.invokeMethod('available');
    return state ?? false;
  }

  /// 切换前后台
  Future<void> toggle(AppLifecycleState state) =>
      _channel.invokeMethod('toggle', state == AppLifecycleState.foreground);
}

enum AppLifecycleState {
  /// 前台
  foreground,

  /// 后台
  background,
}

/// android 配置信息
class FlPiPAndroidConfig {
  FlPiPAndroidConfig({
    this.aspectRatio = const Rational.square(),
  });

  final Rational aspectRatio;

  Map<String, dynamic> toMap() => aspectRatio.toMap();
}

/// ios 配置信息
class FlPiPiOSConfig {
  FlPiPiOSConfig({
    this.path = 'assets/landscape.mp4',
    this.packageName = 'fl_pip',
    this.enableControls = false,
    this.enablePlayback = false,
  });

  ///  ios 需要的视频路径
  ///  用于修改ios悬浮框尺寸的视频地址
  final String path;

  /// ios 配置视频地址的 packageName
  final String? packageName;

  /// 开启播放控制
  final bool enableControls;

  /// 开启播放速度
  final bool enablePlayback;

  Map<String, dynamic> toMap() => {
        'enableControls': enableControls,
        'enablePlayback': enablePlayback,
        'packageName': packageName,
        'path': path
      };
}

/// android pip 宽高比
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

extension ExtensionRect on Rect {
  Map<String, double> toLTWH() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        'right': right,
        'bottom': bottom
      };
}

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
