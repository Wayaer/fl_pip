import AudioToolbox
import AVFoundation
import Foundation
import UIKit

/// 运行时生成的画中画占位媒体：1 秒纯黑视频 + 1 秒静音音轨。
///
/// 有两种用途：网络视频在首帧到达前先用它启动画中画；主引擎没有独立的 `FlutterEngine`
/// 实例，也用它在画中画窗口中兜底展示。文件按尺寸缓存到 `Caches/fl_pip/frames/`，
/// 同一尺寸只生成一次。
///
/// Placeholder media generated at runtime with a 1-second black video and a 1-second silent
/// audio track. It lets a network video start PiP before its first frame arrives, and serves as
/// the fallback for the main engine, which has no standalone engine instance.
final class FlPiPPlaceholderMedia {
    static let shared = FlPiPPlaceholderMedia()

    private let workQueue = DispatchQueue(label: "fl_pip.placeholder", qos: .userInitiated)
    private let cacheDirectory: URL

    private var generation = 0
    private var itemGeneration = 0
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer = AVPlayerLayer()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let base = caches ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = base.appendingPathComponent("fl_pip/frames", isDirectory: true)
    }

    /// 准备占位媒体并返回已循环播放的图层；
    /// 宽高为物理像素，未传时铺满宽度并使用 16:9。
    /// Prepares the placeholder media and returns a looping player layer.
    func makePlayerLayer(
        widthPx: CGFloat?,
        heightPx: CGFloat?,
        muted: Bool,
        completion: @escaping (AVPlayerLayer?) -> Void
    ) {
        generation += 1
        let token = generation
        let size = pixelSize(widthPx: widthPx, heightPx: heightPx)
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.placeholderURL(width: size.width, height: size.height)
            DispatchQueue.main.async {
                guard self.generation == token, let url = url else {
                    completion(nil)
                    return
                }
                completion(self.startPlayer(url: url, muted: muted))
            }
        }
    }

    /// 生成一个可立即播放的本地占位 `AVPlayerItem`。
    ///
    /// 网络视频在首帧到达前无法启动画中画，先用本地占位媒体启动画中画，再替换成网络地址，
    /// 就能把加载过程放进画中画里。
    ///
    /// Builds a local placeholder `AVPlayerItem` that can play immediately. It lets PiP start
    /// before the first frame of a network video arrives, so buffering happens inside PiP.
    func makeItem(
        widthPx: CGFloat?,
        heightPx: CGFloat?,
        completion: @escaping (AVPlayerItem?) -> Void
    ) {
        itemGeneration += 1
        let token = itemGeneration
        let size = pixelSize(widthPx: widthPx, heightPx: heightPx)
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.placeholderURL(width: size.width, height: size.height)
            DispatchQueue.main.async {
                guard self.itemGeneration == token else {
                    completion(nil)
                    return
                }
                completion(url.map { AVPlayerItem(url: $0) })
            }
        }
    }

    /// 停止占位媒体播放。 / Stops placeholder playback.
    func stop() {
        generation += 1
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        playerLayer.player = nil
    }

    private func startPlayer(url: URL, muted: Bool) -> AVPlayerLayer {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = muted
        player.actionAtItemEnd = .none
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.player = player
        self.looper = looper
        self.playerLayer = layer
        player.play()
        return layer
    }

    /// 计算取偶后的物理像素尺寸。 / Resolves the even physical-pixel size.
    private func pixelSize(widthPx: CGFloat?, heightPx: CGFloat?) -> (width: Int, height: Int) {
        let screenWidth = UIScreen.main.bounds.width * UIScreen.main.scale
        let resolvedWidth: CGFloat
        if let width = widthPx {
            resolvedWidth = width
        } else if let height = heightPx {
            resolvedWidth = height * 16 / 9
        } else {
            resolvedWidth = screenWidth
        }
        let resolvedHeight = heightPx ?? resolvedWidth * 9 / 16
        return (Self.even(resolvedWidth), Self.even(resolvedHeight))
    }

    private static func even(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded - (rounded % 2)
    }

    private func placeholderURL(width: Int, height: Int) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("placeholder-\(width)x\(height).mp4")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            print("FlPiP error: unable to create the placeholder cache directory, \(error)")
            return nil
        }
        return writePlaceholder(width: width, height: height, to: fileURL) ? fileURL : nil
    }

    /// 用 AVAssetWriter 写入 1 秒黑帧视频与 1 秒静音 AAC 音轨。
    /// Writes one second of black frames and one second of silent AAC audio.
    private func writePlaceholder(width: Int, height: Int, to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            print("FlPiP error: unable to create the placeholder asset writer")
            return false
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            writer.cancelWriting()
            print("FlPiP error: the placeholder inputs are not supported")
            return false
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else {
            writer.cancelWriting()
            print("FlPiP error: unable to start writing the placeholder")
            return false
        }
        writer.startSession(atSourceTime: .zero)

        let frameRate: Int32 = 30
        var succeeded = true
        for frame in 0..<Int(frameRate) {
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard let buffer = makePixelBuffer(width: width, height: height) else {
                succeeded = false
                break
            }
            let time = CMTime(value: CMTimeValue(frame), timescale: frameRate)
            if !adaptor.append(buffer, withPresentationTime: time) {
                succeeded = false
                break
            }
        }
        videoInput.markAsFinished()

        if succeeded {
            while !audioInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            if let sample = makeSilentAudioSample(frameCount: 44100, sampleRate: 44100) {
                succeeded = audioInput.append(sample)
            } else {
                succeeded = false
            }
        }
        audioInput.markAsFinished()

        guard succeeded else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            print("FlPiP error: unable to write the placeholder media")
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            print("FlPiP error: the placeholder media is incomplete")
            return false
        }
        return true
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            // 纯黑：BGRA 全 0；H.264 不使用 alpha 通道。
            // Pure black: all BGRA bytes zero; H.264 ignores the alpha channel.
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    /// 构造 1 秒 16-bit 单声道全零 PCM，AVAssetWriter 会把它编码成 AAC。
    /// Builds one second of silent 16-bit mono PCM which AVAssetWriter encodes to AAC.
    private func makeSilentAudioSample(frameCount: Int, sampleRate: Double) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let format = formatDescription else { return nil }

        let byteCount = frameCount * Int(asbd.mBytesPerFrame)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let block = blockBuffer else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return sampleBuffer
    }
}
