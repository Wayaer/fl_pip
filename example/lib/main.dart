import 'package:example/main_app.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const MainApp()));
}

/// mainName must be the same as the method name
@pragma('vm:entry-point')
void pipMain() {
  runApp(ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        home: const PiPMainApp()),
  ));
}
