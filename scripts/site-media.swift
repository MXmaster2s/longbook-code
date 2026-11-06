// One film for the website: H.264 at a set width and bitrate, AAC audio, the index first so playback
// starts early, no editor metadata, a JPEG poster, and an optional gain on the sound. Called by
// scripts/site-media.mts:
//   swift scripts/site-media.swift <source> <out.mp4> <width> <video bits/s> <poster.jpg> <poster at, s> [gain dB]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 7 || args.count == 8, let width = Int(args[3]), let bitrate = Int(args[4]), let posterAt = Double(args[6]),
      let gainDb = args.count == 8 ? Double(args[7]) : 0 else {
    FileHandle.standardError.write("usage: site-media.swift <source> <out.mp4> <width> <video bits/s> <poster.jpg> <poster at> [gain dB]\n".data(using: .utf8)!)
    exit(2)
}
let source = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let posterOut = URL(fileURLWithPath: args[5])

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(1)
}

let asset = AVURLAsset(url: source)
let semaphore = DispatchSemaphore(value: 0)
var videoTrack: AVAssetTrack?
var audioTrack: AVAssetTrack?
var natural = CGSize.zero
var transform = CGAffineTransform.identity
var duration = CMTime.zero
Task {
    do {
        videoTrack = try await asset.loadTracks(withMediaType: .video).first
        audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        if let v = videoTrack {
            natural = try await v.load(.naturalSize)
            transform = try await v.load(.preferredTransform)
        }
        duration = try await asset.load(.duration)
    } catch {
        fail("cannot read \(source.path): \(error)")
    }
    semaphore.signal()
}
semaphore.wait()
guard let video = videoTrack else { fail("\(source.path) has no video") }

// Even dimensions, the source's shape kept.
let height = Int((Double(width) * Double(natural.height) / Double(natural.width) / 2).rounded()) * 2

try? FileManager.default.removeItem(at: out)
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let reader = try AVAssetReader(asset: asset)
let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true
writer.metadata = []

let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
])
videoOut.alwaysCopiesSampleData = false
reader.add(videoOut)
let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalDurationKey: 2,
        AVVideoAllowFrameReorderingKey: true,
    ],
])
videoIn.transform = transform
videoIn.expectsMediaDataInRealTime = false
writer.add(videoIn)

var audioOut: AVAssetReaderOutput?
var audioIn: AVAssetWriterInput?
if let audio = audioTrack {
    // Read through a mix so the gain lands on the PCM before it is encoded again.
    let o = AVAssetReaderAudioMixOutput(audioTracks: [audio], audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
    let level = AVMutableAudioMixInputParameters(track: audio)
    level.setVolume(Float(pow(10, gainDb / 20)), at: .zero)
    let mix = AVMutableAudioMix(); mix.inputParameters = [level]; o.audioMix = mix
    reader.add(o)
    let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 48_000,
        AVEncoderBitRateKey: 128_000,
    ])
    i.expectsMediaDataInRealTime = false
    writer.add(i)
    audioOut = o
    audioIn = i
}

guard reader.startReading() else { fail("reader: \(String(describing: reader.error))") }
guard writer.startWriting() else { fail("writer: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)

let group = DispatchGroup()
func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, _ label: String) {
    group.enter()
    let queue = DispatchQueue(label: label)
    input.requestMediaDataWhenReady(on: queue) {
        while input.isReadyForMoreMediaData {
            if let sample = output.copyNextSampleBuffer() {
                if !input.append(sample) { fail("\(label): \(String(describing: writer.error))") }
            } else {
                input.markAsFinished()
                group.leave()
                return
            }
        }
    }
}
pump(videoIn, videoOut, "video")
if let i = audioIn, let o = audioOut { pump(i, o, "audio") }
group.wait()
if reader.status == .failed { fail("reader: \(String(describing: reader.error))") }
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { fail("writer: \(String(describing: writer.error))") }

// The poster: one frame, the film's own size, sRGB JPEG with nothing attached.
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: width, height: height)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let at = CMTime(seconds: min(posterAt, max(0, duration.seconds - 0.1)), preferredTimescale: 600)
let posterDone = DispatchSemaphore(value: 0)
var frame: CGImage?
generator.generateCGImageAsynchronously(for: at) { image, _, error in
    if let error { fail("poster: \(error)") }
    frame = image
    posterDone.signal()
}
posterDone.wait()
guard let image = frame else { fail("poster: no frame") }
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("poster: no context") }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let flat = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(posterOut as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { fail("poster: cannot write") }
CGImageDestinationAddImage(dest, flat, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { fail("poster: cannot finalize") }

let bytes = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
print("\(out.lastPathComponent): \(width)×\(height), \(String(format: "%.1f", duration.seconds)) s, \(bytes) bytes; poster \(posterOut.lastPathComponent) at \(posterAt) s")
