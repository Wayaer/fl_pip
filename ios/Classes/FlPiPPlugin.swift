import AVKit
import Flutter
import Foundation
import UIKit

public class FlPiPPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate {
    private var registrar: FlutterPluginRegistrar
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?

    private var engineGroup = FlutterEngineGroup(name: "pip.flutter", project: nil)
    private var flPiPEngine: FlutterEngine?
    private var flutterController: FlutterViewController?

    private var createNewEngine: Bool = false
    private var isEnable: Bool = false
    private var enabledWhenBackground: Bool = false
    private var rootWindow: UIWindow?

    private var channel: FlutterMethodChannel

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "fl_pip", binaryMessenger: registrar.messenger())
        let instance = FlPiPPlugin(channel, registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }

    init(_ channel: FlutterMethodChannel, _ registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.channel = channel
        super.init()
    }

    private var enableArgs: [String: Any?] = [:]

    private var isCallDisable: Bool = false

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enable":
            if isAvailable(), !isEnable {
                enableArgs = call.arguments as! [String: Any?]
                createNewEngine = enableArgs["createNewEngine"] as! Bool
                enabledWhenBackground = enableArgs["enabledWhenBackground"] as! Bool
                rootWindow = windows()?.filter { window in
                    window.isKeyWindow
                }.first
                isEnable = enable()
                result(isEnable)
                return
            }
            result(false)
        case "disable":
            isCallDisable = true
            dispose()
            enableArgs = [:]
            setPiPStatus(1)
            result(true)
        case "isActive":
            var map = ["createNewEngine": createNewEngine, "enabledWhenBackground": enabledWhenBackground] as [String: Any]
            if isAvailable() {
                map["status"] = (pipController?.isPictureInPictureActive ?? false) ? 0 : 1
            } else {
                map["status"] = 2
            }
            result(map)
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

    func enable() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("FlPiP error : AVAudioSession.sharedInstance()")
            return false
        }
        let path = enableArgs["path"] as! String
        let packageName = enableArgs["packageName"] as? String
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
            if rootWindow == nil {
                print("FlPiP error : rootWindow is null")
                return false
            }
            createFlutterEngine()
            playerLayer = AVPlayerLayer()
            let x = enableArgs["left"] as? CGFloat ?? UIScreen.main.bounds.size.width/2
            let y = enableArgs["top"] as? CGFloat ?? UIScreen.main.bounds.size.height/2
            let width = enableArgs["width"] as? CGFloat ?? 1
            let height = enableArgs["height"] as? CGFloat ?? 1

            playerLayer!.frame = .init(x: x, y: y, width: width, height: height)
            player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: URL(fileURLWithPath: bundlePath!))))
            playerLayer!.player = player
            player!.isMuted = true
            player!.allowsExternalPlayback = true
            player!.accessibilityElementsHidden = true
            pipController = AVPictureInPictureController(playerLayer: playerLayer!)
            pipController!.delegate = self

            let enableControls = enableArgs["enableControls"] as! Bool
            pipController!.setValue(enableControls ? 0 : 1, forKey: "controlsStyle")

            let enablePlayback = enableArgs["enablePlayback"] as! Bool
            pipController!.setValue(enablePlayback ? 0 : 1, forKey: "requiresLinearPlayback")

            if #available(iOS 14.2, *) {
                pipController!.canStartPictureInPictureAutomaticallyFromInline = true
            }
            player!.play()
            rootWindow!.rootViewController?.view?.layer.addSublayer(playerLayer!)
            if !enabledWhenBackground {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.4) {
                    self.pipController!.startPictureInPicture()
                }
            }
            return true
        }
        return false
    }

    func createFlutterEngine() {
        if createNewEngine {
            let rootController = (rootWindow?.rootViewController as! FlutterViewController)
            flPiPEngine = engineGroup.makeEngine(withEntrypoint: "pipMain", libraryURI: nil)
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

    public func isAvailable() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if let firstWindow = UIApplication.shared.windows.first, rootWindow != nil {
            let rect = firstWindow.rootViewController?.view.frame ?? CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            if createNewEngine {
                flutterController?.view.frame = rect
                firstWindow.rootViewController = flutterController
            } else {
                let rootController = rootWindow!.rootViewController
                let flController = (rootController as! FlutterViewController)
                let engine = flController.engine!
                engine.viewController = nil
                let newController = FlutterViewController(engine: engine, nibName: flController.nibName, bundle: flController.nibBundle)
                flController.dismiss(animated: true)
                newController.view.frame = rect
                firstWindow.rootViewController = newController
            }
            setPiPStatus(0)
        }
    }

    func setPiPStatus(_ int: Int) {
        channel.invokeMethod("onPiPStatus", arguments: ["createNewEngine": createNewEngine, "enabledWhenBackground": enabledWhenBackground, "status": int])
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if !isCallDisable {
            dispose()
        }
    }

    public func dispose() {
        pipController?.stopPictureInPicture()
        if createNewEngine {
            flutterController?.removeFromParent()
            flPiPEngine?.viewController?.dismiss(animated: false)
            flutterController = nil
            flPiPEngine = nil
        } else if rootWindow != nil {
            let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            let firstWindow = UIApplication.shared.windows.first
            if firstWindow!.rootViewController is FlutterViewController {
                let flController = (firstWindow!.rootViewController as! FlutterViewController)
                let engine = flController.engine!
                engine.viewController = nil
                let newController = FlutterViewController(engine: flController.engine!, nibName: flController.nibName, bundle: flController.nibBundle)
                flController.dismiss(animated: true)
                firstWindow!.rootViewController = nil
                newController.view.frame = rect
                rootWindow?.rootViewController = newController
            }
        }
        isCallDisable = false
        pipController = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        setPiPStatus(1)
        isEnable = false
        createNewEngine = false
        enabledWhenBackground = false
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        if enabledWhenBackground {
            // print("app will enter foreground")
        }
    }

    public func applicationDidEnterBackground(_ application: UIApplication) {
        if enabledWhenBackground {
            if createNewEngine {
                createFlutterEngine()
            }
            pipController?.startPictureInPicture()
        }
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
