import AVKit
import Flutter
import Foundation
import UIKit

public class FlPiPPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate {
    private var registrar: FlutterPluginRegistrar
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?

    private var flutterView: UIView?
    private var flutterWindow: UIWindow?

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
            flutterView = flutterWindow?.rootViewController?.view
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
        dispose()
        let path = args["path"] as! String
        let packageName = args["packageName"] as! String
        let assetPath: String
        assetPath = registrar.lookupKey(forAsset: path, fromPackage: packageName)
        let bundlePath = Bundle.main.path(forResource: assetPath, ofType: nil)
        if bundlePath == nil {
            print("FlPiP error : Unable to load video resources, \(path) in \(packageName)")
            return 1
        }
        if isAvailable() {
            flutterWindow = windows()?.filter { window in
                window.isKeyWindow
            }.first
            flutterView = flutterWindow?.rootViewController?.view
            if flutterWindow == nil || flutterView == nil {
                print("FlPiP error : (flutterWindow || flutterView ） is null")
                return 1
            }
            playerLayer = AVPlayerLayer()
            playerLayer!.frame = .init(x: args["left"] as! Double, y: args["top"] as! Double, width: args["width"] as! Double, height: args["height"] as! Double)
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
            flutterView?.layer.addSublayer(playerLayer!)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.4) {
                self.pipController!.startPictureInPicture()
            }
            return pipController!.isPictureInPictureActive ? 0 : 1
        }
        return 2
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

    public func isAvailable() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if let window = UIApplication.shared.windows.first {
            if flutterView != nil {
                flutterView?.frame = window.rootViewController?.view.frame ?? CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
                window.addSubview(flutterView!)
                background()
                channel.invokeMethod("onPiPStatus", arguments: 0)
            }
        }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if flutterView != nil {
            let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            flutterView!.frame = rect
            flutterWindow?.addSubview(flutterView!)
            channel.invokeMethod("onPiPStatus", arguments: 1)
        }
        dispose()
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
