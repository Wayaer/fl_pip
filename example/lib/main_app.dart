import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_waya/flutter_waya.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: double.infinity, height: context.statusBarHeight),
        CountDown(
            periodic: 1,
            duration: const Duration(seconds: 500),
            builder: (int i) => Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
                child: Text(i.toString()))),
        PiPBuilder(builder: (PiPStatusInfo? statusInfo) {
          switch (statusInfo?.status) {
            case PiPStatus.enabled:
              return Column(children: [
                const Text('PiPStatus enabled'),
                Text('isCreateNewEngine: ${statusInfo!.isCreateNewEngine}',
                    style: const TextStyle(fontSize: 10)),
                Text(
                    'isEnabledWhenBackground: ${statusInfo.isEnabledWhenBackground}',
                    style: const TextStyle(fontSize: 10)),
                ElevatedButton(
                    onPressed: () {
                      FlPiP().disable();
                    },
                    child: const Text('disable')),
              ]);
            case PiPStatus.disabled:
              return builderDisabled;
            case PiPStatus.unavailable:
              return buildUnavailable;
            case null:
              return builderDisabled;
          }
        }),
        ElevatedButton(
            onPressed: () async {
              final state = await FlPiP().isAvailable;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: state
                        ? const Text('PiP available')
                        : const Text('PiP unavailable')));
              }
            },
            child: const Text('PiPStatus isAvailable')),
        ElevatedButton(
            onPressed: () {
              FlPiP().toggle(AppState.background);
            },
            child: const Text('toggle')),
      ])));

  Widget get builderDisabled =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('PiPStatus disabled'),
        const SizedBox(height: 10),
        ElevatedButton(
            onPressed: () async {
              await FlPiP().enable(
                  ios: const FlPiPiOSConfig(
                      path: 'assets/landscape.mp4', packageName: null),
                  android: const FlPiPAndroidConfig(
                      aspectRatio: Rational.maxLandscape()));
              Future.delayed(const Duration(seconds: 10), () {
                FlPiP().disable();
              });
            },
            child: const Text('Enable PiP')),
        ElevatedButton(
            onPressed: () {
              FlPiP().enable(
                  ios: const FlPiPiOSConfig(
                      enabledWhenBackground: true,
                      path: 'assets/landscape.mp4',
                      packageName: null),
                  android: const FlPiPAndroidConfig(
                      enabledWhenBackground: true,
                      aspectRatio: Rational.maxLandscape()));
            },
            child: const Text('Enabled when background',
                textAlign: TextAlign.center)),
        ElevatedButton(
            onPressed: () {
              FlPiP().enable(
                  android: const FlPiPAndroidConfig(createNewEngine: true),
                  ios: const FlPiPiOSConfig(
                      createNewEngine: true,
                      path: 'assets/landscape.mp4',
                      packageName: null));
            },
            child: const Text('Create new engine')),
        ElevatedButton(
            onPressed: () {
              FlPiP().enable(
                  android: const FlPiPAndroidConfig(
                      enabledWhenBackground: true, createNewEngine: true),
                  ios: const FlPiPiOSConfig(
                      enabledWhenBackground: true,
                      createNewEngine: true,
                      path: 'assets/landscape.mp4',
                      packageName: null));
            },
            child: const Text('Create new engine and enabled when background',
                textAlign: TextAlign.center)),
      ]);

  Widget get buildUnavailable => ElevatedButton(
      onPressed: () async {
        final state = await FlPiP().isAvailable;
        if (!mounted) return;
        if (!state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('PiP unavailable')));
        }
      },
      child: const Text('PiP unavailable'));
}

class PiPMainApp extends StatefulWidget {
  const PiPMainApp({super.key});

  @override
  State<PiPMainApp> createState() => _PiPMainAppState();
}

class _PiPMainAppState extends State<PiPMainApp> {
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white70,
      body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        CountDown(
            onChanged: (int i) {},
            periodic: 1,
            duration: const Duration(seconds: 500),
            builder: (int i) => Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(i.toString()))),
        const Text('The current pip is created using a new engine'),
        const SizedBox(
            height: 20,
            width: double.infinity,
            child: FlAnimationWave(
                value: 0.5, color: Colors.red, direction: Axis.vertical)),
      ])));
}
