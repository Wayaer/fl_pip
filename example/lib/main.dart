import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) => PiPBuilder(
      pip: FlPiP(),
      builder: (PiPStatus status) {
        switch (status) {
          case PiPStatus.enabled:
            return buildEnabled;
          case PiPStatus.disabled:
            return builderDisabled;
          case PiPStatus.unavailable:
            return buildUnavailable;
        }
      });

  Widget get buildEnabled => Scaffold(
      body: Container(
          alignment: Alignment.center, child: const Text('PiPStatus enabled')));

  Widget get builderDisabled => Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            FlPiP().enable(
                iosConfig: FlPiPiOSConfig(),
                androidConfig: FlPiPAndroidConfig(
                    aspectRatio: const Rational.maxLandscape()));
          },
          label: const Text('Enable PiP'),
          icon: const Icon(Icons.picture_in_picture)),
      body: Container(
          alignment: Alignment.center,
          child: const Text('PiPStatus disabled')));

  Widget get buildUnavailable => Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            FlPiP().isAvailable;
          },
          label: const Text('PiP unavailable')),
      appBar: AppBar(title: const Text("PiP unavailable")));
}
