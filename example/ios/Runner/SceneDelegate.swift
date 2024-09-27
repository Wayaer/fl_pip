//import UIKit
//
//class SceneDelegate: UIResponder, UIWindowSceneDelegate {
//
//    var window: UIWindow?
//
//
//    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
//        guard let _ = (scene as? UIWindowScene) else { return }
//    }
//
//    func sceneDidDisconnect(_ scene: UIScene) {
//   
//    }
//
//    func sceneDidBecomeActive(_ scene: UIScene) {
//        print("sceneDidBecomeActive")
//        BackgroundTaskManager.shared.stopPlay()
//    }
//
//    func sceneDidEnterBackground(_ scene: UIScene) {
//        print("sceneDidEnterBackground")
//        BackgroundTaskManager.shared.startPlay()
//    }
//
//}
//
