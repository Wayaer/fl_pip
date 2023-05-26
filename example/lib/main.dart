import 'dart:math';

import 'package:fl_pip/fl_pip.dart';
import 'package:flutter/material.dart';
import 'dart:async';

void main() {
  runApp(MaterialApp(theme: ThemeData.dark(), home: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final floating = Floating();
  ValueNotifier<int> num = ValueNotifier(0);
  late Timer timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      num.value = num.value + 1;
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    floating.dispose();
    timer.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive) {
      floating.enable(aspectRatio: const Rational.square());
    }
  }

  Future<void> enablePip(BuildContext context) async {
    final rational = const Rational.landscape();
    final screenSize =
        MediaQuery.of(context).size * MediaQuery.of(context).devicePixelRatio;
    final status = await floating.enable(
      aspectRatio: rational,
      sourceRectHint: Rectangle<int>(20, 20, screenSize.width.toInt(), 200),
    );
    debugPrint('PiP enabled? $status');
  }

  @override
  Widget build(BuildContext context) => PiPSwitcher(
      childWhenDisabled: scaffold(FutureBuilder<bool>(
          future: floating.isPipAvailable,
          initialData: false,
          builder: (context, snapshot) => snapshot.data ?? false
              ? FloatingActionButton.extended(
                  onPressed: () => enablePip(context),
                  label: const Text('Enable PiP'),
                  icon: const Icon(Icons.picture_in_picture),
                )
              : const Card(
                  child: Text('PiP unavailable'),
                ))),
      childWhenEnabled: scaffold());

  Widget scaffold([Widget? floatingActionButton]) => Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(title: const Text("appBar")),
      body: Container(
          child: ValueListenableBuilder(
              valueListenable: num,
              builder: (_, int num, __) => Text('$num'))));
}
