import AVKit
import Flutter
import Foundation
import UIKit

public class FlPiPPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate {
    private var registrar: FlutterPluginRegistrar
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?

    private var engineGroup: FlutterEngineGroup?
    private var flPiPEngine: FlutterEngine?
    private var flutterController: FlutterViewController?

    private var withEngine: Bool = false

    private var rootWindow: UIWindow?

    private var channel: FlutterMethodChannel

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "fl_pip", binaryMessenger: registrar.messenger())
        let instance = FlPiPPlugin(channel, registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(_ channel: FlutterMethodChannel, _ registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.channel = channel
        super.init()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enable":
            result(enable(call.arguments as! [String: Any?]))
        case "enableWithEngine":
            withEngine = true
            result(enable(call.arguments as! [String: Any?]))
        case "disable":
            dispose()
            disposeEngine()
            result(true)
        case "isActive":
            if isAvailable() {
                if pipController?.isPictureInPictureActive ?? false {
                    result(0)
                } else {
                    result(1)
                }
            } else {
                result(2)
            }
        case "toggle":
            let value = call.arguments as! Bool
            if value {
                /// 切换前台
            } else {
                /// 切换后台
                background()
            }
            result(nil)
        case "available":
            result(isAvailable())
        default:
            result(nil)
        }
    }

    func enable(_ args: [String: Any?]) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("FlPiP error : AVAudioSession.sharedInstance()")
            return false
        }
        let path = args["path"] as! String
        dispose()
        let packageName = args["packageName"] as? String
        let assetPath: String
        if packageName != nil {
            assetPath = registrar.lookupKey(forAsset: path, fromPackage: packageName!)
        } else {
            assetPath = registrar.lookupKey(forAsset: path)
        }
        let bundlePath = Bundle.main.path(forResource: assetPath, ofType: nil)
        if bundlePath == nil {
            print("FlPiP error : Unable to load video resources, \(path) in \(packageName ?? "current")")
            return false
        }
        if isAvailable() {
            rootWindow = windows()?.filter { window in
                window.isKeyWindow
            }.first
            if rootWindow == nil {
                print("FlPiP error : rootWindow is null")
                return false
            }
            createFlutterEngine(args)
            playerLayer = AVPlayerLayer()

            let x = args["left"] as? CGFloat ?? UIScreen.main.bounds.size.width/2
            let y = args["top"] as? CGFloat ?? UIScreen.main.bounds.size.height/2
            let width = args["width"] as? CGFloat ?? 1
            let height = args["height"] as? CGFloat ?? 1

            playerLayer!.frame = .init(x: x, y: y, width: width, height: height)
            player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: URL(fileURLWithPath: bundlePath!))))
            playerLayer!.player = player
            player!.isMuted = true
            player!.allowsExternalPlayback = true
            player!.accessibilityElementsHidden = true
            pipController = AVPictureInPictureController(playerLayer: playerLayer!)
            pipController!.delegate = self

            let enableControls = args["enableControls"] as! Bool
            pipController!.setValue(enableControls ? 0 : 1, forKey: "controlsStyle")

            let enablePlayback = args["enablePlayback"] as! Bool
            pipController!.setValue(enablePlayback ? 0 : 1, forKey: "requiresLinearPlayback")

            if #available(iOS 14.2, *) {
                pipController!.canStartPictureInPictureAutomaticallyFromInline = true
            } else {}
            player!.play()
            rootWindow!.rootViewController?.view?.layer.addSublayer(playerLayer!)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.4) {
                self.pipController!.startPictureInPicture()
            }
            return true
        }
        return false
    }

    func createFlutterEngine(_ args: [String: Any?]) {
        disposeEngine()
        if withEngine {
            engineGroup = FlutterEngineGroup(name: "pip.flutter", project: nil)
            let rootController = (rootWindow?.rootViewController as! FlutterViewController)
            flPiPEngine = engineGroup!.makeEngine(withEntrypoint: "pipMain", libraryURI: nil)
            flutterController = FlutterViewController(
                engine: flPiPEngine!,
                nibName: rootController.nibName,
                bundle: rootController.nibBundle)
            flPiPEngine!.run(withEntrypoint: "pipMain")
        }
    }

    public func background() {
        /// 切换后台
        let targetSelect = #selector(NSXPCConnection.suspend)
        if UIApplication.shared.responds(to: targetSelect) {
            UIApplication.shared.perform(targetSelect)
        }
    }

    public func dispose() {
        pipController?.stopPictureInPicture()
        pipController = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    public func disposeEngine() {
        flutterController?.removeFromParent()
        flutterController?.engine?.destroyContext()
        flPiPEngine?.viewController?.dismiss(animated: false)
        flPiPEngine = nil
        engineGroup = nil
        flutterController = nil
    }

    public func isAvailable() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if let firstWindow = UIApplication.shared.windows.first, rootWindow != nil {
            let rect = firstWindow.rootViewController?.view.frame ?? CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            if withEngine, flutterController != nil {
                flutterController!.view.frame = rect
                firstWindow.rootViewController = flutterController
            } else if rootWindow != nil {
                let rootController = rootWindow!.rootViewController
                let flController = (rootController as! FlutterViewController)
                let engine = flController.engine!
                engine.viewController = nil
                let newController = FlutterViewController(engine: engine, nibName: flController.nibName, bundle: flController.nibBundle)
                flController.dismiss(animated: true)
                newController.view.frame = rect
                firstWindow.rootViewController = newController
            }
            channel.invokeMethod("onPiPStatus", arguments: 0)
        }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if withEngine {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                disposeEngine()
            }
        } else if rootWindow != nil {
            let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            let firstWindow = UIApplication.shared.windows.first
            let flController = (firstWindow!.rootViewController as! FlutterViewController)
            let engine = flController.engine!
            engine.viewController = nil
            let newController = FlutterViewController(engine: flController.engine!, nibName: flController.nibName, bundle: flController.nibBundle)
            flController.dismiss(animated: true)
            firstWindow!.rootViewController = nil
            newController.view.frame = rect
            rootWindow?.rootViewController = newController
        }
        dispose()
        channel.invokeMethod("onPiPStatus", arguments: 1)
    }

    public func windows() -> [UIWindow]? {
        return UIApplication.shared.windows
//        if #available(iOS 13.0, *) {
//            let windowScene = (UIApplication.shared.connectedScenes.first as? UIWindowScene)
//            return windowScene?.windows
//        } else {
//            return UIApplication.shared.windows
//        }
    }
}
