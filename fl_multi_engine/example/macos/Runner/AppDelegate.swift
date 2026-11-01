import Cocoa
import FlutterMacOS
import fl_multi_engine

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // macOS 新引擎同样需要注册 App 生成插件；本示例只用到 fl_multi_engine 本身。
    // Register the generated app plugins on engines created on macOS.
    FlMultiEnginePlugin.pluginRegistrant = { engine in
      RegisterGeneratedPlugins(registry: engine)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
