// Runs the app's screenshot classifier on every png, jpg, jpeg and heic file in a folder, on the Mac.
// Compiled together with ScreenshotClassifier.swift and ScreenshotAnalyzer.swift. Run through scripts/classify-folder.sh.
// Recognised text is only printed with --dump, the screenshots may be private.
import CoreGraphics
import Foundation
import ImageIO

let longestSide = 1024
let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

struct ReadError: Error, CustomStringConvertible {
    let description: String
}

/// The app reads screenshots at this size, so the tool does too.
func loadDownscaled(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let full = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw ReadError(description: "cannot read image") }
    let scale = Double(longestSide) / Double(max(full.width, full.height))
    guard scale < 1 else { return full }
    let width = max(1, Int((Double(full.width) * scale).rounded()))
    let height = max(1, Int((Double(full.height) * scale).rounded()))
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw ReadError(description: "cannot resize image") }
    context.interpolationQuality = .high
    context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let small = context.makeImage() else { throw ReadError(description: "cannot resize image") }
    return small
}

let arguments = Array(CommandLine.arguments.dropFirst())
let dump = arguments.contains("--dump")
guard let folderPath = arguments.first(where: { $0 != "--dump" }) else {
    fail("usage: scripts/classify-folder.sh <folder> [--dump]")
}
var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
    fail("usage: scripts/classify-folder.sh <folder> [--dump] (no such folder: \(folderPath))")
}

let folder = URL(fileURLWithPath: folderPath)
let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
    .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var counts: [ScreenshotKind: Int] = [:]
var failures = 0
var totalMilliseconds = 0.0

for file in files {
    let name = file.lastPathComponent
    let start = Date()
    do {
        let image = try loadDownscaled(file)
        let features = try ScreenshotAnalyzer.features(of: image)
        let kind = ScreenshotClassifier.classify(features)
        let milliseconds = Date().timeIntervalSince(start) * 1000
        totalMilliseconds += milliseconds
        counts[kind, default: 0] += 1
        let topLabels = features.labels.sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key) \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
        print("\(name)  \(kind.rawValue)  lines \(features.lines.count)  barcodes \(features.barcodeCount)  "
            + "\(Int(milliseconds.rounded())) ms  labels: \(topLabels.isEmpty ? "none" : topLabels)")
        if dump {
            for line in features.lines {
                print(String(format: "    x %.2f-%.2f  y %.2f-%.2f  ", line.minX, line.maxX, line.minY, line.maxY) + line.text)
            }
        }
    } catch {
        failures += 1
        totalMilliseconds += Date().timeIntervalSince(start) * 1000
        print("\(name)  ERROR \(error)")
    }
}

print("")
// Mix last, like the review screen.
for kind in ScreenshotKind.allCases.filter({ $0 != .mix }) + [.mix] {
    print("\(kind.rawValue): \(counts[kind, default: 0])")
}
let analysed = files.count - failures
print("files: \(files.count)  errors: \(failures)")
let average = files.isEmpty ? 0 : totalMilliseconds / Double(files.count)
print("total: \(Int(totalMilliseconds.rounded())) ms  average: \(Int(average.rounded())) ms per file (\(analysed) analysed)")
