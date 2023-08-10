import AVKit
import Flutter
import Foundation
import UIKit

public class FlPiPPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate {
    private var registrar: FlutterPluginRegistrar
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?

    private let engineGroup = FlutterEngineGroup(name: "pip.flutter", project: nil)
    private var flutterController: FlutterViewController?
    private var mainName: String?
    private var whenStopDestroyEngine: Bool = true
    private var withEngine: Bool = false

    private var rootWindow: UIWindow?
    private var rootController: UIViewController?

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
        case "disable":
            dispose()
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
                let targetSelect = #selector(NSXPCConnection.suspend)
                if UIApplication.shared.responds(to: targetSelect) {
                    UIApplication.shared.perform(targetSelect)
                }
            }
            result(nil)
        case "available":
            rootController = rootWindow?.rootViewController
            result(isAvailable())
        default:
            result(nil)
        }
    }

    func enable(_ args: [String: Any?]) -> Int {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("FlPiP error : AVAudioSession.sharedInstance()")
            return 1
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
            return 1
        }
        if isAvailable() {
            rootWindow = windows()?.filter { window in
                window.isKeyWindow
            }.first
            rootController = rootWindow?.rootViewController
            if rootWindow == nil || rootController == nil {
                print("FlPiP error : rootWindow || rootController  is null")
                return 1
            }
            createFlutterEngine(args)
            playerLayer = AVPlayerLayer()
            playerLayer!.frame = .init(x: 0, y: 0, width: 1, height: 1)
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
            rootController?.view?.layer.addSublayer(playerLayer!)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.4) {
                self.pipController!.startPictureInPicture()
            }
            return 0
        }
        return 2
    }

    func createFlutterEngine(_ args: [String: Any?]) {
        let name = args["mainName"] as? String
        withEngine = name != nil
        if mainName != name {
            disposeEngine()
            mainName = name
        }
        whenStopDestroyEngine = args["whenStopDestroyEngine"] as? Bool ?? true
        if mainName != nil, flutterController == nil {
            let engine = engineGroup.makeEngine(withEntrypoint: mainName, libraryURI: nil)
            flutterController = FlutterViewController(
                engine: engine,
                nibName: nil,
                bundle: nil)
            engine.run(withEntrypoint: mainName)
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
        if whenStopDestroyEngine {
            flutterController?.engine?.destroyContext()
            flutterController?.dismiss(animated: true)
            flutterController = nil
            mainName = nil
        }
    }

    public func isAvailable() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if let firstWindow = UIApplication.shared.windows.first, rootWindow != nil {
            if withEngine {
                firstWindow.rootViewController?.present(flutterController!, animated: true)
            } else if rootController != nil {
                rootController!.view.frame = firstWindow.rootViewController?.view.frame ?? CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
                rootController!.view.removeFromSuperview()
                print(firstWindow.rootViewController)
                firstWindow.rootViewController = rootController
                print(rootWindow?.rootViewController)
//                rootWindow?.rootViewController = nil
//                print(rootWindow?.rootViewController)
//                background()
            }
            channel.invokeMethod("onPiPStatus", arguments: 0)
        }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if rootController != nil, !withEngine {
            let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            rootController!.view.frame = rect
            let firstWindow = UIApplication.shared.windows.first
            print(rootWindow!.rootViewController)
            print(firstWindow!.rootViewController)
            let controller = firstWindow?.rootViewController ?? rootController
            controller?.view.frame = rect
            rootWindow!.rootViewController = controller
            firstWindow?.rootViewController = nil
            print(rootWindow!.rootViewController)
            print(firstWindow!.rootViewController)
//            firstWindow?.rootViewController = nil
//            rootController!.view.removeFromSuperview()

//            rootWindow!.rootViewController?.view = rootView!.view
//            rootWindow!.rootViewController?.present(rootController!, animated: true)
//            print(rootWindow!.rootViewController?.view)
//            print(rootWindow!.rootViewController)
            ////            print(rootWindow!.addSubview())
//            rootWindow!.addSubview(rootView!.view)
//            print(rootWindow!.rootViewController?.view)
//            print(rootWindow!.rootViewController)
//            rootWindow!.rootViewController?.view.addSubview()
//            if let firstWindow = UIApplication.shared.windows.first { firstWindow.rootViewController?.dismiss(animated: true)
//            }
        }

        channel.invokeMethod("onPiPStatus", arguments: 1)
        dispose()
        if withEngine {
            disposeEngine()
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
