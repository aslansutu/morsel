import Flutter
import UIKit
import Vision
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var labelVision: LabelVision?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    labelVision = LabelVision(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// The `morsel/vision` channel (lib/vision.dart): VisionKit's document scanner,
/// Vision text recognition and subject cut-out, photos made ready to send, and
/// the Keychain. Everything runs on the device.
class LabelVision: NSObject, VNDocumentCameraViewControllerDelegate {
  private let channel: FlutterMethodChannel
  private var pendingScan: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "morsel/vision", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "appFolder":
      result(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path)
    case "scanDocument":
      scanDocument(result: result)
    case "readText":
      inBackground(result) { try Self.readText(Self.load(call.arguments)) }
    case "cutOut":
      inBackground(result) { try Self.cutOut(Self.load(call.arguments)) }
    case "forUpload":
      inBackground(result) { try Self.save(Self.upright(Self.load(call.arguments), maxSide: 2400)) }
    case "readSecret":
      result(Keychain.read(call.arguments as! String))
    case "writeSecret":
      let args = call.arguments as! [String: String]
      result(Keychain.write(args["name"]!, args["value"]!)
        ? nil : FlutterError(code: "keychain_failed", message: "Couldn't save to the Keychain.", details: nil))
    case "deleteSecret":
      Keychain.delete(call.arguments as! String)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Document scanner

  private func scanDocument(result: @escaping FlutterResult) {
    // No camera on the simulator, so no scanner either.
    guard VNDocumentCameraViewController.isSupported else {
      result(FlutterError(code: "unavailable", message: "This device can't scan documents.", details: nil))
      return
    }
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    guard let presenter = top else {
      result(FlutterError(code: "unavailable", message: "No screen to show the scanner on.", details: nil))
      return
    }
    pendingScan = result
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    presenter.present(scanner, animated: true)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
  ) {
    controller.dismiss(animated: true)
    // A label is one page; extra pages are ignored.
    finishScan(scan.pageCount > 0 ? (try? Self.save(scan.imageOfPage(at: 0))) : nil)
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    finishScan(nil)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    finishScan(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
  }

  private func finishScan(_ value: Any?) {
    pendingScan?(value)
    pendingScan = nil
  }

  // MARK: Text recognition

  /// Lines with their boxes as fractions of the image, from the top left, and
  /// their slope: how far the baseline drops per unit across.
  private static func readText(_ image: UIImage) throws -> [[String: Any]] {
    let handler = handler(for: image)
    func recognize(_ level: VNRequestTextRecognitionLevel) throws -> [VNRecognizedTextObservation] {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = level
      if level == .accurate, #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = true }
      try handler.perform([request])
      return request.results ?? []
    }
    // Accurate mode skips short numbers alone in table cells ("25", "0,2"); fast
    // mode finds them. Fast lines fill in only where accurate found nothing.
    let accurate = try recognize(.accurate)
    let fast = try recognize(.fast).filter { line in
      !accurate.contains {
        let overlap = $0.boundingBox.intersection(line.boundingBox)
        return !overlap.isNull && overlap.width * overlap.height > 0.3 * line.boundingBox.width * line.boundingBox.height
      }
    }
    return (accurate + fast).compactMap { observation in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      // Vision measures from the bottom left.
      let box = observation.boundingBox
      let run = observation.topRight.x - observation.topLeft.x
      return [
        "text": text, "left": box.minX, "top": 1 - box.maxY, "right": box.maxX, "bottom": 1 - box.minY,
        "slope": run > 0 ? -(observation.topRight.y - observation.topLeft.y) / run : 0,
      ]
    }
  }

  // MARK: Subject cut-out

  /// The photo's subjects on white, or nil when Vision finds none (or the OS is older than iOS 17).
  private static func cutOut(_ image: UIImage) throws -> String? {
    guard #available(iOS 17.0, *) else { return nil }
    let requestHandler = handler(for: image)
    let request = VNGenerateForegroundInstanceMaskRequest()
    try requestHandler.perform([request])
    guard let mask = request.results?.first, !mask.allInstances.isEmpty else { return nil }
    let buffer = try mask.generateMaskedImage(
      ofInstances: mask.allInstances, from: requestHandler, croppedToInstancesExtent: true)
    let ciImage = CIImage(cvPixelBuffer: buffer)
    guard let subject = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
    return try save(onWhite(UIImage(cgImage: subject)))
  }

  /// [subject] centred on a white square with a margin, at most 1200 px across.
  private static func onWhite(_ subject: UIImage) -> UIImage {
    let side = max(subject.size.width, subject.size.height) * 1.12
    let scale = min(1, 1200 / side)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let canvas = CGSize(width: side * scale, height: side * scale)
    return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: canvas))
      let size = CGSize(width: subject.size.width * scale, height: subject.size.height * scale)
      subject.draw(in: CGRect(
        x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
        width: size.width, height: size.height))
    }
  }

  // MARK: Photos to send

  /// [image] redrawn upright, at most [maxSide] px across: a new image, so none of
  /// the original's metadata (location, camera) goes with it.
  private static func upright(_ image: UIImage, maxSide: CGFloat) -> UIImage {
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  // MARK: Helpers

  private func inBackground(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      let value: Any?
      do {
        value = try work()
      } catch {
        value = FlutterError(code: "vision_failed", message: error.localizedDescription, details: nil)
      }
      DispatchQueue.main.async { result(value) }
    }
  }

  private static func load(_ argument: Any?) throws -> UIImage {
    guard let path = argument as? String, let image = UIImage(contentsOfFile: path) else {
      throw NSError(domain: "morsel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't open the image."])
    }
    return image
  }

  /// A handler that sees the photo upright, whichever way the camera held it.
  private static func handler(for image: UIImage) -> VNImageRequestHandler {
    let orientation: CGImagePropertyOrientation = switch image.imageOrientation {
    case .up: .up
    case .down: .down
    case .left: .left
    case .right: .right
    case .upMirrored: .upMirrored
    case .downMirrored: .downMirrored
    case .leftMirrored: .leftMirrored
    case .rightMirrored: .rightMirrored
    @unknown default: .up
    }
    if let cgImage = image.cgImage {
      return VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
    }
    return VNImageRequestHandler(ciImage: CIImage(image: image)!, orientation: orientation)
  }

  private static func save(_ image: UIImage) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    guard let data = image.jpegData(compressionQuality: 0.9) else {
      throw NSError(domain: "morsel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Can't save the image."])
    }
    try data.write(to: url)
    return url.path
  }
}

/// Small secrets in the Keychain, readable only on this device while it's unlocked.
enum Keychain {
  private static func query(_ name: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "morsel", kSecAttrAccount as String: name]
  }

  static func read(_ name: String) -> String? {
    var query = query(name)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func write(_ name: String, _ value: String) -> Bool {
    delete(name)
    var query = query(name)
    query[kSecValueData as String] = Data(value.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
  }

  static func delete(_ name: String) {
    SecItemDelete(query(name) as CFDictionary)
  }
}
