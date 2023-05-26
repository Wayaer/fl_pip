import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget switching utility.
///
/// Depending on current PiP status will render [childWhenEnabled]
/// or [childWhenDisabled] widget.
class PiPSwitcher extends StatefulWidget {
  /// Floating instance that the listener will connect to.
  ///
  /// It may be provided by the instance user. If not, the widget
  /// will create it's own Floating instance.
  final Floating? floating;

  /// Child to render when PiP is enabled
  final Widget childWhenEnabled;

  /// Child to render when PiP is disabled or unavailable.
  final Widget childWhenDisabled;

  const PiPSwitcher({
    Key? key,
    required this.childWhenEnabled,
    required this.childWhenDisabled,
    this.floating,
  }) : super(key: key);

  @override
  State<PiPSwitcher> createState() => _PipAwareState();
}

class _PipAwareState extends State<PiPSwitcher> {
  late final Floating _floating = widget.floating ?? Floating();

  @override
  void dispose() {
    if (widget.floating == null) {
      _floating.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: _floating.pipStatus$,
        initialData: PiPStatus.disabled,
        builder: (context, snapshot) => snapshot.data == PiPStatus.enabled
            ? widget.childWhenEnabled
            : widget.childWhenDisabled,
      );
}

enum PiPStatus { enabled, disabled, unavailable }

class Floating {
  final _channel = const MethodChannel('fl_pip');
  final _controller = StreamController<PiPStatus>();
  final Duration _probeInterval;
  Timer? _timer;
  Stream<PiPStatus>? _stream;

  Floating({
    Duration probeInterval = const Duration(milliseconds: 10),
  }) : _probeInterval = probeInterval;

  Future<bool> get isPipAvailable async {
    final bool? supportsPip = await _channel.invokeMethod('pipAvailable');
    return supportsPip ?? false;
  }

  Future<PiPStatus> get pipStatus async {
    if (!await isPipAvailable) {
      return PiPStatus.unavailable;
    }
    final bool? inPipAlready = await _channel.invokeMethod('inPipAlready');
    return inPipAlready ?? false ? PiPStatus.enabled : PiPStatus.disabled;
  }

  Stream<PiPStatus> get pipStatus$ {
    _timer ??= Timer.periodic(
      _probeInterval,
      (_) async => _controller.add(await pipStatus),
    );
    _stream ??= _controller.stream.asBroadcastStream();
    return _stream!.distinct();
  }

  /// Turns on PiP mode.
  ///
  /// When enabled, PiP mode can be ended by the user via system UI.
  ///
  /// PiP may be unavailable because of system settings managed
  /// by admin or device manufacturer. Also, the device may
  /// have Android version that was released without this feature.
  ///
  /// Provide [aspectRatio] to override default 16/9 aspect ratio.
  /// [aspectRatio] must fit into Android-supported values:
  /// min: 1/2.39, max: 2.39/1, otherwise [RationalNotMatchingAndroidRequirementsException]
  /// will be thrown.
  /// Note: this will not make any effect on Android SDK older than 26.
  Future<PiPStatus> enable({
    Rational aspectRatio = const Rational.landscape(),
    Rectangle<int>? sourceRectHint,
  }) async {
    if (!aspectRatio.fitsInAndroidRequirements) {
      throw RationalNotMatchingAndroidRequirementsException(aspectRatio);
    }

    final bool? enabledSuccessfully = await _channel.invokeMethod(
      'enablePip',
      {
        ...aspectRatio.toMap(),
        if (sourceRectHint != null)
          'sourceRectHintLTRB': [
            sourceRectHint.left,
            sourceRectHint.top,
            sourceRectHint.right,
            sourceRectHint.bottom,
          ]
      },
    );
    return enabledSuccessfully ?? false
        ? PiPStatus.enabled
        : PiPStatus.unavailable;
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

/// Represents rational in [numerator]/[denominator] notation.
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

  const Rational.vertical()
      : numerator = 9,
        denominator = 16;

  @override
  String toString() =>
      'Rational(numerator: $numerator, denominator: $denominator)';

  Map<String, dynamic> toMap() => {
        'numerator': numerator,
        'denominator': denominator,
      };
}

/// Extension for [Rational] to confirm whether Android aspect ration
/// requirements are met or not.
extension on Rational {
  /// Checks whether given [Rational] instance fits into Android requirements
  /// or not.
  ///
  /// Android docs specified boundaries as inclusive.
  bool get fitsInAndroidRequirements {
    final aspectRatio = numerator / denominator;
    const min = 1 / 2.39;
    const max = 2.39;
    return (min <= aspectRatio) && (aspectRatio <= max);
  }
}

/// Provides details about Android requirements and compares current
/// [rational] value to those.
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
