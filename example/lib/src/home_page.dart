import 'package:example/main.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

const videoPath = 'assets/landscape.mp4';
const closeIconPath = 'assets/close.png';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: double.infinity, height: 20),
          Timer(),
          Container(
              margin: EdgeInsets.all(20),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).dividerColor)),
              child: PiPBuilder(builder: (PiPStatusInfo? statusInfo) {
                switch (statusInfo?.status) {
                  case PiPStatus.enabled:
                    return builderEnabled(statusInfo);
                  case PiPStatus.disabled:
                    return builderDisabled;
                  case PiPStatus.unavailable:
                    return buildUnavailable(context);
                  case null:
                    return builderDisabled;
                }
              })),
          Filled(
              text: 'PiPStatus isAvailable',
              onPressed: () async {
                final state = await FlPiP().isAvailable;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: state
                          ? const Text('PiP available')
                          : const Text('PiP unavailable')));
                }
              }),
          Filled(
              text: 'toggle',
              onPressed: () {
                FlPiP().toggle(AppState.background);
              }),
        ])),
      ));

  Widget builderEnabled(PiPStatusInfo? statusInfo) => Column(children: [
        const Text('PiPStatus enabled'),
        Text('isCreateNewEngine: ${statusInfo!.isCreateNewEngine}',
            style: const TextStyle(fontSize: 10)),
        Text('isEnabledWhenBackground: ${statusInfo.isEnabledWhenBackground}',
            style: const TextStyle(fontSize: 10)),
        Filled(text: 'disable', onPressed: FlPiP().disable),
      ]);

  Widget get builderDisabled =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Currently using picture in picture mode'),
        Filled(
            onPressed: () async {
              await FlPiP().enable(
                  ios: const FlPiPiOSConfig(
                      videoPath: videoPath, packageName: null),
                  android: const FlPiPAndroidConfig(
                      aspectRatio: Rational.maxLandscape()));
              Future.delayed(const Duration(seconds: 10), () {
                FlPiP().disable();
              });
            },
            text: 'Enable PiP'),
        Text(
            'The picture in picture mode will only be activated when the app enters the background'),
        Filled(
            onPressed: () {
              FlPiP().enable(
                  ios: const FlPiPiOSConfig(
                      enabledWhenBackground: true,
                      videoPath: videoPath,
                      packageName: null),
                  android: const FlPiPAndroidConfig(
                      enabledWhenBackground: true,
                      aspectRatio: Rational.maxLandscape()));
            },
            text: 'Enabled when background'),
        Divider(),
        Text(
            'This still uses picture in picture mode in iOS and has created a new FlutterEngine that cannot be shared with the current main，But in Android, the picture in picture mode is not used, and WindowManager is used, similar to a system pop-up window'),
        Filled(
            onPressed: () {
              FlPiP().enable(
                  android: const FlPiPAndroidConfig(
                      createNewEngine: true, closeIconPath: closeIconPath),
                  ios: const FlPiPiOSConfig(
                      createNewEngine: true,
                      videoPath: videoPath,
                      packageName: null));
            },
            text: 'Create new engine'),
        Text('Start when the app enters the background'),
        Filled(
            onPressed: () {
              FlPiP().enable(
                  android: const FlPiPAndroidConfig(
                      closeIconPath: closeIconPath,
                      enabledWhenBackground: true,
                      createNewEngine: true),
                  ios: const FlPiPiOSConfig(
                      enabledWhenBackground: true,
                      createNewEngine: true,
                      videoPath: videoPath,
                      packageName: null));
            },
            text: 'Create new engine and enabled when background'),
      ]);

  Widget buildUnavailable(BuildContext context) => Filled(
      text: 'PiP unavailable',
      onPressed: () async {
        final state = await FlPiP().isAvailable;
        if (!context.mounted) return;
        if (!state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('PiP unavailable')));
        }
      });
}
