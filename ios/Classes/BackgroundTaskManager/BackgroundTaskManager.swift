import AVFAudio
import AVKit
import Foundation

public class BackgroundTaskManager: NSObject {
    public static let shared = BackgroundTaskManager()
    
    public func startPlay() {
        audioPlayer.play()
    }
    
    public func stopPlay() {
        audioPlayer.stop()
    }
    
    var audioPlayer: AVAudioPlayer!
    
    override private init() {
        super.init()
        
        do {
            // 设置后台模式和锁屏模式下依旧能够播放
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            
            let mp4Video = Bundle.main.url(forResource: "slience", withExtension: "mp3")
            try audioPlayer = AVAudioPlayer(contentsOf: mp4Video!)
            audioPlayer.volume = 0
            audioPlayer.numberOfLoops = -1
            print("成功")
        } catch {
            print(error)
        }
    }
}
