// Runs the iOS app's text recognition (ios/Runner/AppDelegate.swift, readText) on a Mac and
// prints the lines as JSON, for test/fixtures/labels:
//   swiftc -O tool/vision_ocr.swift -o /tmp/vision_ocr && /tmp/vision_ocr label.jpg
// (prefix swiftc with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer here).
import Foundation
import ImageIO
import Vision

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fputs("Can't open \(url.path)\n", stderr)
  exit(1)
}
let handler = VNImageRequestHandler(cgImage: image)

func recognize(_ level: VNRequestTextRecognitionLevel) throws -> [VNRecognizedTextObservation] {
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = level
  if level == .accurate { request.automaticallyDetectsLanguage = true }
  try handler.perform([request])
  return request.results ?? []
}

// Accurate mode skips short numbers alone in table cells; fast lines fill in only where
// accurate found nothing.
let accurate = try recognize(.accurate)
let fast = try recognize(.fast).filter { line in
  !accurate.contains {
    let overlap = $0.boundingBox.intersection(line.boundingBox)
    return !overlap.isNull && overlap.width * overlap.height > 0.3 * line.boundingBox.width * line.boundingBox.height
  }
}
let lines: [[String: Any]] = (accurate + fast).compactMap { o in
  guard let text = o.topCandidates(1).first?.string else { return nil }
  let box = o.boundingBox
  let run = o.topRight.x - o.topLeft.x
  return ["text": text, "left": box.minX, "top": 1 - box.maxY, "right": box.maxX, "bottom": 1 - box.minY,
          "slope": run > 0 ? -(o.topRight.y - o.topLeft.y) / run : 0]
}
print(String(data: try JSONSerialization.data(withJSONObject: lines), encoding: .utf8)!)
