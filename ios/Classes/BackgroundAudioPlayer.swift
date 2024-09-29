import AVFAudio
import AVKit
import Foundation

class BackgroundAudioPlayer: NSObject {
    static let shared = BackgroundAudioPlayer()

    var audioPlayer: AVAudioPlayer?

    func setAudioPath(path: String) {
        do {
            // 设置后台模式和锁屏模式下依旧能够播放
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)

            let audio = Bundle.main.path(forResource: path, ofType: nil)
            if audio != nil {
                if audioPlayer == nil {
                    audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: audio!))
                }
                audioPlayer!.volume = 0
                audioPlayer!.numberOfLoops = -1
//                print("===成功")
            } else {
//                print("====\(path)")
            }
        } catch {
            print(error)
        }
    }

    func startPlay() {
        audioPlayer?.play()
    }

    func stopPlay() {
        audioPlayer?.stop()
    }
}
