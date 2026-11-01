import 'package:example/src/home_page.dart';
import 'package:example/src/pip_home_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DemoApp(home: HomePage()));

/// Entry point of the dedicated picture-in-picture engine.
///
/// The function must be named `pipMain` and annotated with `@pragma('vm:entry-point')` so that it
/// is kept when the app is compiled ahead-of-time.
@pragma('vm:entry-point')
void pipMain() => runApp(
  const ClipRRect(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    child: DemoApp(home: PiPHomePage()),
  ),
);

/// The app shared by the main engine and the picture-in-picture engine.
class DemoApp extends StatelessWidget {
  const DemoApp({super.key, required this.home});

  /// The page rendered by this engine.
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0EA5E9)),
    darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF0EA5E9), brightness: Brightness.dark),
    home: home,
  );
}
