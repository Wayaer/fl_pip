## 0.0.1

* Initial release.
* Creates, destroys, lists and connects named Flutter engines on Android, iOS, macOS, Windows,
  Linux and HarmonyOS. Engine creation never shows any UI; presentation is left to the host app.
* Engine APIs: `create`, `destroy`, `list`, `status`, `send` and `currentEngineName`, exposed both
  through Dart (`FlMultiEngine`) and through the native API of every platform
  (`FlMultiEngineBridge`, `FlMultiEngineInfo`, `FlMultiEngineDestroyObserver`).
* `send` delivers messages between engines with a `sender`, `method` and `value` payload; native
  implementations notify Flutter through `onEnginesChanged` whenever an engine is created or
  destroyed.
* Unified error codes on every platform (`not_supported`, `invalid_name`, `engine_exists`,
  `create_failed`, `main_engine_not_destroyable`, `not_initialized`, `unknown`) and unified engine
  list ordering (creation time, with the engine name as a stable tie-break).
* Native engine management: `FlutterEngineGroup` on Android, iOS and HarmonyOS,
  `FlutterEngine` + `FlutterDartProject` on macOS, `FlutterDesktopEngineCreate` on Windows and
  `fl_engine_new_headless` on Linux.
* iOS and macOS share the `darwin/` Swift package and one podspec, with both Swift Package Manager
  and CocoaPods support.
