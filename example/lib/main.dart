import 'package:example/src/home_page.dart';
import 'package:example/src/pip_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_waya/flutter_waya.dart';

void main() {
  runApp(App(home: HomePage()));
}

/// mainName must be the same as the method name
@pragma('vm:entry-point')
void pipMain() {
  runApp(ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: App(home: PiPHomePage())));
}

class App extends StatelessWidget {
  const App({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: home);
  }
}

class Timer extends StatelessWidget {
  const Timer({super.key});

  @override
  Widget build(BuildContext context) => Counter.down(
      value: const Duration(seconds: 500),
      builder: (Duration duration, bool isRunning, VoidCallback startTiming,
          VoidCallback stopTiming) {
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
            child: Text('timer:${duration.inSeconds.toString()}'));
      });
}

class Filled extends StatelessWidget {
  const Filled({super.key, required this.text, this.onPressed});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
        onPressed: onPressed, child: Text(text, textAlign: TextAlign.center));
  }
}
