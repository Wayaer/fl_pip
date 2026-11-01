import Cocoa
import FlutterMacOS
import fl_multi_engine

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlMultiEnginePlugin.pluginRegistrant = { engine in
      RegisterGeneratedPlugins(registry: engine)
    }

    super.awakeFromNib()
  }
}
