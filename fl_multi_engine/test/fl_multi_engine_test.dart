import 'package:fl_multi_engine/fl_multi_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlMultiEngineInfo', () {
    test('parses every field from the native map', () {
      const int createdAt = 1700000000000;
      final FlMultiEngineInfo info = FlMultiEngineInfo.fromMap(<Object?, Object?>{
        'name': 'engine_a',
        'entrypoint': 'engineAMain',
        'state': 'running',
        'createdAt': createdAt,
        'isMain': false,
      });

      expect(info.name, 'engine_a');
      expect(info.entrypoint, 'engineAMain');
      expect(info.state, FlMultiEngineState.running);
      expect(info.createdAt, DateTime.fromMillisecondsSinceEpoch(createdAt));
      expect(info.isMain, isFalse);
    });

    test('falls back to failed for an unknown state and a missing timestamp', () {
      final FlMultiEngineInfo info = FlMultiEngineInfo.fromMap(<Object?, Object?>{'state': 'booting'});

      expect(info.state, FlMultiEngineState.failed);
      expect(info.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(info.name, '');
    });
  });

  group('FlMultiEngineMessage', () {
    test('parses the sender, method and value', () {
      final FlMultiEngineMessage message = FlMultiEngineMessage.fromMap(<Object?, Object?>{
        'sender': 'main',
        'method': 'command',
        'value': <Object?, Object?>{'text': 'hello'},
      });

      expect(message.sender, 'main');
      expect(message.method, 'command');
      expect(message.value, <String, Object?>{'text': 'hello'});
    });

    test('uses an empty map when the value is not a map', () {
      final FlMultiEngineMessage message = FlMultiEngineMessage.fromMap(<Object?, Object?>{'value': 'text'});

      expect(message.value, isEmpty);
    });
  });

  group('platform capabilities', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('isSupported is true on the five supported platforms only', () {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(FlMultiEngine.isSupported, isTrue);
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      expect(FlMultiEngine.isSupported, isFalse);
    });
  });

  group('FlMultiEngine.create', () {
    const MethodChannel channel = MethodChannel('fl_multi_engine');
    const StandardMethodCodec codec = StandardMethodCodec();
    late List<MethodCall> calls;
    Object? createResult;
    Object? createError;

    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    setUp(() {
      calls = <MethodCall>[];
      createResult = 'engine_a';
      createError = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall call,
      ) async {
        calls.add(call);
        if (call.method == 'create') {
          final Object? error = createError;
          if (error != null) throw error;
          return createResult;
        }
        if (call.method == 'list') {
          return <Object?>[
            <Object?, Object?>{
              'name': 'engine_a',
              'entrypoint': 'engineAMain',
              'state': 'running',
              'createdAt': 1700000000000,
              'isMain': false,
            },
          ];
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('returns the matching engine after re-fetching the list', () async {
      final FlMultiEngineInfo? info = await FlMultiEngine.instance.create(name: 'engine_a', entrypoint: 'engineAMain');

      expect(info?.name, 'engine_a');
      expect(calls.map((MethodCall call) => call.method), <String>['create', 'list']);
    });

    test('returns null when the native implementation reports no ID', () async {
      createResult = null;
      final FlMultiEngineInfo? info = await FlMultiEngine.instance.create(name: 'engine_a', entrypoint: 'engineAMain');

      expect(info, isNull);
      expect(calls.map((MethodCall call) => call.method), <String>['create']);
    });

    test('throws our exception for a native bridge error', () async {
      createError = PlatformException(code: FlMultiEngineErrorCode.engineExists, message: 'exists');
      await expectLater(
        FlMultiEngine.instance.create(name: 'engine_a', entrypoint: 'engineAMain'),
        throwsA(
          isA<FlMultiEngineException>().having(
            (FlMultiEngineException exception) => exception.code,
            'code',
            FlMultiEngineErrorCode.engineExists,
          ),
        ),
      );
    });

    test('re-fetches the list after onEnginesChanged', () async {
      final Future<List<FlMultiEngineInfo>> next = FlMultiEngine.instance.engines.first;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'fl_multi_engine',
        codec.encodeMethodCall(const MethodCall('onEnginesChanged')),
        (ByteData? data) {},
      );

      final List<FlMultiEngineInfo> engines = await next;
      expect(engines.single.name, 'engine_a');
      expect(calls.map((MethodCall call) => call.method), <String>['list']);
    });
  });
}
