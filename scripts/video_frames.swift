import AVFoundation
import AppKit

// Decode sampled frames as a basic integrity check; visual review is still required.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: video_frames.swift recording.mp4 output-directory")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let asset = AVURLAsset(url: source)
let duration = try await asset.load(.duration).seconds
guard duration.isFinite, duration > 0 else { fatalError("Video has no duration") }
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
var frames: [[String: Any]] = []
for (index, fraction) in [0.05, 0.5, 0.9].enumerated() {
    let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
    let (image, actualTime) = try await generator.image(at: time)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
    let name = "frame-\(index).png"
    try png.write(to: output.appendingPathComponent(name))
    frames.append(["file": name, "seconds": actualTime.seconds, "width": image.width, "height": image.height])
}
let data = try JSONSerialization.data(withJSONObject: ["duration_seconds": duration, "frames": frames], options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("video.json"))
print(String(decoding: data, as: UTF8.self))
