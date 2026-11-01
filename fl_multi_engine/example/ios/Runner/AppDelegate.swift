import Flutter
import fl_multi_engine
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 新引擎需要注册 App 的生成插件，这样 fl_multi_engine 之外的其他插件也能工作。
    // New engines need the app plugins, so other plugins keep working there.
    FlMultiEnginePlugin.pluginRegistrant = { engine in
      GeneratedPluginRegistrant.register(with: engine)
    }
  }
}
