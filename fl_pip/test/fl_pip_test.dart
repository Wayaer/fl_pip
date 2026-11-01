import 'package:fl_pip/fl_pip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlPiPStatusInfo', () {
    test('parses the native status map', () {
      final FlPiPStatusInfo info = FlPiPStatusInfo.fromMap(<Object?, Object?>{
        'status': 0,
        'mode': 'overlay',
        'hasEngine': true,
      });

      expect(info.status, FlPiPStatus.enabled);
      expect(info.mode, FlPiPPresentationMode.overlay);
      expect(info.hasEngine, isTrue);
    });

    test('maps every status index', () {
      expect(FlPiPStatusInfo.fromMap(<Object?, Object?>{'status': 1}).status, FlPiPStatus.disabled);
      expect(FlPiPStatusInfo.fromMap(<Object?, Object?>{'status': 2}).status, FlPiPStatus.unavailable);
      expect(FlPiPStatusInfo.fromMap(<Object?, Object?>{'status': 9}).status, FlPiPStatus.disabled);
      expect(FlPiPStatusInfo.fromMap(<Object?, Object?>{}).status, FlPiPStatus.disabled);
    });

    test('ignores an unknown presentation mode', () {
      expect(FlPiPStatusInfo.fromMap(<Object?, Object?>{'mode': 'unknown'}).mode, isNull);
    });

    test('compares by value', () {
      expect(
        const FlPiPStatusInfo(status: FlPiPStatus.enabled, mode: FlPiPPresentationMode.systemPip, hasEngine: true),
        const FlPiPStatusInfo(status: FlPiPStatus.enabled, mode: FlPiPPresentationMode.systemPip, hasEngine: true),
      );
    });
  });

  group('FlPiPErrorCode', () {
    test('resolves known codes and falls back to unknown', () {
      expect(FlPiPErrorCode.fromCode('already_enabled'), FlPiPErrorCode.alreadyEnabled);
      expect(FlPiPErrorCode.fromCode('engine_creation_failed'), FlPiPErrorCode.engineCreationFailed);
      expect(FlPiPErrorCode.fromCode('engine_not_found'), FlPiPErrorCode.engineNotFound);
      expect(FlPiPErrorCode.fromCode('something_new'), FlPiPErrorCode.unknown);
      expect(FlPiPErrorCode.fromCode(null), FlPiPErrorCode.unknown);
    });
  });

  group('FlPiPWindow', () {
    test('serialises the pixel geometry', () {
      expect(const FlPiPWindow(width: 720, height: 405, top: 200, left: 40).toMap(), <String, Object?>{
        'width': 720,
        'height': 405,
        'top': 200,
        'left': 40,
      });
    });

    test('defaults the offsets to zero', () {
      expect(const FlPiPWindow(width: 320, height: 180).toMap(), <String, Object?>{
        'width': 320,
        'height': 180,
        'top': 0,
        'left': 0,
      });
    });
  });

  group('options', () {
    test('Android overlay sends the window and the corner radius', () {
      final Map<String, Object?> map = const FlPiPAndroidOptions.overlay(
        window: FlPiPWindow(width: 720, height: 405, top: 100, left: 20),
        cornerRadius: 16,
      ).toMap();

      expect(map['mode'], 'overlay');
      expect(map['width'], 720);
      expect(map['height'], 405);
      expect(map['top'], 100);
      expect(map['cornerRadius'], 16);
    });

    test('Android system PiP only sends the aspect ratio', () {
      final Map<String, Object?> map = const FlPiPAndroidOptions.systemPip(
        aspectRatio: FlPiPAspectRatio.vertical(),
      ).toMap();

      expect(map['mode'], 'systemPip');
      expect(map.containsKey('width'), isFalse);
      expect(map['numerator'], 9);
      expect(map['denominator'], 16);
    });

    test('iOS only sends the requested window and nothing else', () {
      expect(const FlPiPIOSOptions().toMap(), isEmpty);
      expect(const FlPiPIOSOptions(window: FlPiPWindow(width: 360, height: 202, top: 80)).toMap(), <String, Object?>{
        'width': 360,
        'height': 202,
        'top': 80,
        'left': 0,
      });
    });

    test('HarmonyOS overlay sends the window and the corner radius', () {
      final Map<String, Object?> map = const FlPiPHarmonyOSOptions.overlay(
        window: FlPiPWindow(width: 480, height: 270),
        cornerRadius: 12,
      ).toMap();

      expect(map['mode'], 'overlay');
      expect(map['width'], 480);
      expect(map['cornerRadius'], 12);
    });

    test('HarmonyOS system PiP only sends the aspect ratio', () {
      expect(const FlPiPHarmonyOSOptions.systemPip().toMap(), <String, Object?>{'mode': 'systemPip'});
      expect(const FlPiPHarmonyOSOptions.systemPip(aspectRatio: FlPiPAspectRatio.vertical()).toMap(), <String, Object?>{
        'mode': 'systemPip',
        'numerator': 9,
        'denominator': 16,
      });
    });
  });

  group('video', () {
    test('parses a control event', () {
      final FlPiPVideoEvent event = FlPiPVideoEvent.fromMap(<Object?, Object?>{
        'event': 'playPause',
        'action': 'pause',
        'playing': false,
        'positionMs': 12000,
        'durationMs': 60000,
      });

      expect(event.event, 'playPause');
      expect(event.action, FlPiPVideoControlAction.pause);
      expect(event.playing, isFalse);
      expect(event.positionMs, 12000);
      expect(event.durationMs, 60000);
    });

    test('falls back to progress for an unknown action', () {
      expect(FlPiPVideoEvent.fromMap(<Object?, Object?>{'action': 'unknown'}).action, FlPiPVideoControlAction.progress);
      expect(FlPiPVideoEvent.fromMap(<Object?, Object?>{}).action, isNull);
    });

    test('parses the video status map', () {
      final FlPiPVideoStatus status = FlPiPVideoStatus.fromMap(<Object?, Object?>{
        'playing': true,
        'positionMs': 1000,
        'durationMs': 2000,
        'speed': 1.5,
        'volume': 0.4,
      });

      expect(status.playing, isTrue);
      expect(status.positionMs, 1000);
      expect(status.durationMs, 2000);
      expect(status.speed, 1.5);
      expect(status.volume, 0.4);
    });

    test('uses defaults for missing video status fields', () {
      final FlPiPVideoStatus status = FlPiPVideoStatus.fromMap(<Object?, Object?>{});

      expect(status.playing, isFalse);
      expect(status.positionMs, 0);
      expect(status.durationMs, 0);
      expect(status.speed, 1.0);
      expect(status.volume, 1.0);
    });

    test('Android video options carry the window and the control flags', () {
      final Map<String, Object?> map = const FlPiPVideoAndroidOptions(
        source: FlPiPVideoSource.asset('assets/h.mp4'),
        window: FlPiPWindow(width: 720, height: 405, top: 200, left: 40),
      ).toMap();

      expect(map['type'], 'asset');
      expect(map['uri'], 'assets/h.mp4');
      expect(map['width'], 720);
      expect(map['top'], 200);
      expect(map['controls'], isA<Map<String, Object?>>());
    });
  });

  group('FlPiPAspectRatio', () {
    test('accepts the supported range', () {
      expect(const FlPiPAspectRatio.square().isSupported, isTrue);
      expect(const FlPiPAspectRatio.maxLandscape().isSupported, isTrue);
      expect(const FlPiPAspectRatio.maxVertical().isSupported, isTrue);
      expect(const FlPiPAspectRatio(3, 1).isSupported, isFalse);
      expect(const FlPiPAspectRatio(1, 3).isSupported, isFalse);
    });
  });
}
