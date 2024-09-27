import 'package:example/main.dart';
import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_waya/flutter_waya.dart';

class PiPHomePage extends StatelessWidget {
  const PiPHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.white70,
      body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Timer(),
        const Text('The current pip is created using a new engine'),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Filled(text: 'disable', onPressed: FlPiP().disable),
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
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Filled(
              text: 'foreground',
              onPressed: () {
                FlPiP().toggle(AppState.foreground);
              }),
          Filled(
              text: 'background',
              onPressed: () {
                FlPiP().toggle(AppState.background);
              }),
        ]),
        const SizedBox(
            height: 20,
            width: double.infinity,
            child: FlAnimationWave(
                value: 0.5, color: Colors.red, direction: Axis.vertical)),
      ])));
}
