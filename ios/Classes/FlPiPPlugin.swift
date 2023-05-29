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
            result(enablePictureInPicture(call.arguments as! [String: Any?]))
        case "isActive":
            result(pipController?.isPictureInPictureActive ?? false)
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
        case "isSupported":
            flutterWindow = UIApplication.shared.windows.filter { window in
                window.isKeyWindow
            }.first
            flutterView = flutterWindow?.rootViewController?.view
            result(isSupported())
        case "dispose":
            dispose()
            result(pipController == nil)
        default:
            result(nil)
        }
    }

    func enablePictureInPicture(_ args: [String: Any?]) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            return false
        }
        dispose()
        let asset = args["path"] as! String
        let packageName = args["packageName"] as? String
        let assetPath: String
        if packageName != nil {
            assetPath = registrar.lookupKey(forAsset: asset, fromPackage: packageName!)
        } else {
            assetPath = registrar.lookupKey(forAsset: asset)
        }
        let bundlePath = Bundle.main.path(forResource: assetPath, ofType: nil)
        if bundlePath == nil {
            return false
        }
        if isSupported() {
            playerLayer = AVPlayerLayer()
            playerLayer!.frame = .init(x: 0, y: 0, width: 1, height: 1)
            player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: URL(fileURLWithPath: bundlePath!))))
            playerLayer!.player = player
            player!.isMuted = true
            player!.allowsExternalPlayback = true
            player!.accessibilityElementsHidden = true
            pipController = AVPictureInPictureController(playerLayer: playerLayer!)
            pipController!.delegate = self
            pipController!.setValue(1, forKey: "requiresLinearPlayback")
            pipController!.setValue(1, forKey: "controlsStyle")
            if #available(iOS 14.2, *) {
                pipController!.canStartPictureInPictureAutomaticallyFromInline = true
            } else {}
            player!.play()
            flutterWindow?.rootViewController?.view.layer.addSublayer(playerLayer!)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.4) {
                self.pipController!.startPictureInPicture()
            }
            return true
        } else {
            print("当前设备不支持PiP")
        }

        UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier.invalid)
        }
        return false
    }

    public func dispose() {
        pipController?.stopPictureInPicture()
        pipController = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    public func isSupported() -> Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {}

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if let window = UIApplication.shared.windows.first {
            if flutterView != nil {
                window.addSubview(flutterView!)
                channel.invokeMethod("start", arguments: nil)
            }
        }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if flutterView != nil {
            let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
            flutterView!.frame = rect
            flutterWindow?.addSubview(flutterView!)
            channel.invokeMethod("stop", arguments: nil)
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
