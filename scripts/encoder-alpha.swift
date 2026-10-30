import Foundation
import AVFoundation
import CoreVideo

// Use Apple's alpha-capable encoder, not a plain HEVC encode that loses alpha.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let asset = AVURLAsset(url: input)
guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVC1920x1080WithAlpha) else {
    fatalError("HEVC alpha export unavailable")
}
export.outputURL = output
export.outputFileType = .mov
export.shouldOptimizeForNetworkUse = true
let done = DispatchSemaphore(value: 0)
export.exportAsynchronously { done.signal() }
guard done.wait(timeout: .now() + 600) == .success, export.status == .completed else {
    fatalError("Export failed: \(String(describing: export.error))")
}

// Decode every exported frame: metadata alone cannot prove transparency.
let movie = AVURLAsset(url: output)
let track = movie.tracks(withMediaType: .video)[0]
let reader = try AVAssetReader(asset: movie)
let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(decoded)
guard reader.startReading() else { fatalError("Cannot decode exported movie") }
var frames = 0
var partialTotal = 0
while let sample = decoded.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let pixels = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    for (x, y) in [(0,0),(width-1,0),(0,height-1),(width-1,height-1)] {
        precondition(pixels[y * stride + x * 4 + 3] < 8, "Opaque corner in exported frame")
    }
    precondition(pixels[Int(Double(height) * 0.7) * stride + (width/2) * 4 + 3] > 30, "Missing scene content")
    var partial = 0
    for y in 0..<height {
        for x in 0..<width {
            let alpha = pixels[y * stride + x * 4 + 3]
            if alpha > 0 && alpha < 255 { partial += 1 }
        }
    }
    partialTotal += partial
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    frames += 1
}
precondition(reader.status == .completed, "Incomplete decode")
precondition(frames == 192, "Expected all 192 rendered views")
precondition(partialTotal > 192000, "Missing translucent glass")
let bytes = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as! Int
precondition(bytes < 12 * 1024 * 1024, "Mobile media budget exceeded")
let proof: [String: Any] = ["frames":frames,"partialAlphaPixels":partialTotal,"bytes":bytes,"duration":movie.duration.seconds,"width":track.naturalSize.width,"height":track.naturalSize.height,"encoder":"AVAssetExportPresetHEVC1920x1080WithAlpha","decodedAlphaVerified":true]
let json = try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted,.sortedKeys])
try json.write(to: output.deletingLastPathComponent().appendingPathComponent("verification.json"))
print(String(data: json, encoding: .utf8)!)
