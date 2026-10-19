import Cocoa
import FlutterMacOS
import ImageIO

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    HostChannel.register(with: flutterViewController.registrar(forPlugin: "GeniusTransferHost"))

    super.awakeFromNib()
  }
}

/// The Dart side's door to macOS. See lib/platform/host_platform.dart.
///
/// The app is sandboxed: it may write to ~/Downloads (an entitlement) and to
/// a save folder the user picks, which it keeps as a security-scoped bookmark
/// to get back in on later launches.
final class HostChannel: NSObject, FlutterPlugin {
  /// For the window the folder panel attaches to.
  private let registrar: FlutterPluginRegistrar
  private var picking = false
  /// Deliveries run here, one at a time and off the main thread: a copy to
  /// another volume or a file provider can take a while.
  private let fileQueue = DispatchQueue(label: "geniustransfer.files", qos: .userInitiated)

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "geniustransfer/host", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(HostChannel(registrar: registrar), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "freeBytes":
      guard let path = args["path"] as? String, !path.isEmpty else {
        return result(Self.badArgs(call))
      }
      // Off the main thread: "important usage" can take a moment to compute.
      DispatchQueue.global(qos: .userInitiated).async {
        let bytes = Self.freeBytes(at: path)
        DispatchQueue.main.async { result(bytes) }
      }
    case "pickFolder":
      pickFolder(result: result)
    case "deliverFile":
      guard let source = args["source"] as? String, let name = args["name"] as? String,
        let folder = args["folder"] as? String
      else { return result(Self.badArgs(call)) }
      fileQueue.async {
        let reply = SaveFolder.deliver(source: source, name: name, bookmark: folder)
        DispatchQueue.main.async { result(reply) }
      }
    case "convertToJpeg":
      guard let source = args["source"] as? String, let target = args["target"] as? String
      else { return result(Self.badArgs(call)) }
      // A 12-megapixel photo takes a moment: off the main thread.
      DispatchQueue.global(qos: .userInitiated).async {
        let made = JpegCopy.make(from: source, to: target)
        DispatchQueue.main.async { result(made) }
      }
    case "revealInFinder":
      guard let path = args["path"] as? String else { return result(Self.badArgs(call)) }
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Shows the folder panel, as a sheet on the app's window. Replies nil if
  /// the user cancels.
  private func pickFolder(result: @escaping FlutterResult) {
    guard !picking else {
      return result(
        FlutterError(code: "busy", message: "A folder picker is already open.", details: nil))
    }
    picking = true
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    let done = { [weak self] (response: NSApplication.ModalResponse) in
      self?.picking = false
      result(response == .OK ? panel.url.map(SaveFolder.describe(picked:)) : nil)
    }
    if let window = registrar.view?.window {
      panel.beginSheetModal(for: window, completionHandler: done)
    } else {
      panel.begin(completionHandler: done)
    }
  }

  /// Free bytes on the volume holding `path`. The folder may not exist yet
  /// (nothing received so far), so this asks about its nearest existing parent.
  private static func freeBytes(at path: String) -> Int? {
    var dir = path
    while !FileManager.default.fileExists(atPath: dir) {
      let parent = (dir as NSString).deletingLastPathComponent
      if parent.isEmpty || parent == dir { return nil }
      dir = parent
    }
    let keys: Set<URLResourceKey> = [
      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ]
    guard let values = try? URL(fileURLWithPath: dir).resourceValues(forKeys: keys) else {
      return nil
    }
    // "Important usage" counts space macOS would free up for the user.
    if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
      return Int(important)
    }
    return values.volumeAvailableCapacity
  }

  private static func badArgs(_ call: FlutterMethodCall) -> FlutterError {
    FlutterError(code: "bad_args", message: "Missing arguments for \(call.method).", details: nil)
  }
}

/// A save folder the user picked. The sandbox lets us in only through the
/// security-scoped bookmark made when it was picked, so the Dart side keeps
/// it and hands it back with each file.
private enum SaveFolder {
  /// The pickFolder reply: a bookmark to get back in later, and a name to show.
  static func describe(picked url: URL) -> Any {
    do {
      let id = try makeBookmark(for: url)
      return ["id": id, "name": displayName(of: url)]
    } catch {
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
  }

  /// Moves the staged file into the folder under the first free name.
  /// Replies with what deliverFile in host_platform.dart expects.
  static func deliver(source: String, name: String, bookmark: String) -> Any {
    guard isPlainName(name) else {
      return FlutterError(code: "bad_args", message: "Not a plain file name: \(name)", details: nil)
    }
    guard let data = Data(base64Encoded: bookmark) else {
      return unavailable("The saved folder bookmark is damaged.")
    }
    var stale = false
    let folder: URL
    do {
      // No UI: this runs in the background, with nobody to answer a prompt.
      folder = try URL(
        resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
        bookmarkDataIsStale: &stale)
    } catch {
      return unavailable(error.localizedDescription)
    }
    guard folder.startAccessingSecurityScopedResource() else {
      return unavailable("Access to the folder was refused.")
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    guard isUsableFolder(folder) else {
      return unavailable("The folder no longer exists.")
    }
    do {
      let saved = try moveIntoFolder(URL(fileURLWithPath: source), name: name, folder: folder)
      var reply: [String: Any] = [
        "name": saved.lastPathComponent, "location": displayName(of: folder), "uri": saved.path,
      ]
      if stale, let fresh = try? makeBookmark(for: folder) { reply["folder"] = fresh }
      return reply
    } catch {
      if isAccessDenied(error) { return unavailable(error.localizedDescription) }
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
  }

  private static func makeBookmark(for folder: URL) throws -> String {
    try folder.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
    ).base64EncodedString()
  }

  /// The folder's path with the home folder shown as "~". Not
  /// NSString.abbreviatingWithTildeInPath: in the sandbox, "home" is the
  /// app's container, so it would leave the real home path as it is.
  private static func displayName(of folder: URL) -> String {
    let path = folder.path
    guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return path }
    let home = String(cString: dir)
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
    return path
  }

  /// Writes under the first free name, coordinated so that iCloud Drive and
  /// other file providers notice the new file.
  private static func moveIntoFolder(_ source: URL, name: String, folder: URL) throws -> URL {
    let coordinator = NSFileCoordinator()
    for n in 0..<10_000 {
      let target = folder.appendingPathComponent(numbered(name, n), isDirectory: false)
      if isTaken(target) { continue }
      var coordinationError: NSError?
      var outcome: Result<URL, Error>?
      coordinator.coordinate(
        writingItemAt: target, options: .forReplacing, error: &coordinationError
      ) { url in
        guard !isTaken(url) else { return }
        do {
          try place(source, at: url)
          outcome = .success(url)
        } catch {
          outcome = .failure(error)
        }
      }
      if let coordinationError { throw coordinationError }
      switch outcome {
      case .success(let url)?:
        return url
      case .failure(let error)? where !isFileExists(error):
        throw error
      default:
        continue  // Taken in the meantime: try the next name.
      }
    }
    throw CocoaError(.fileWriteFileExists)
  }

  /// Moves `source` to `target`, or copies it when the move is refused
  /// (another volume, or a file provider). On failure nothing is left at
  /// `target` and `source` stays where it was.
  private static func place(_ source: URL, at target: URL) throws {
    let files = FileManager.default
    do {
      try files.moveItem(at: source, to: target)
      return
    } catch let error where isFileExists(error) {
      throw error
    } catch {
      try? files.removeItem(at: target)  // A move across volumes can stop half-way.
    }
    do {
      try files.copyItem(at: source, to: target)
    } catch {
      if !isFileExists(error) { try? files.removeItem(at: target) }
      throw error
    }
    try? files.removeItem(at: source)
  }

  /// "a.jpg", then "a (1).jpg", "a (2).jpg"…; "a", "a (1)"… The same rule
  /// as uniqueName in the server.
  private static func numbered(_ name: String, _ n: Int) -> String {
    guard n > 0 else { return name }
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
      return "\(name) (\(n))"
    }
    return "\(name[..<dot]) (\(n))\(name[dot...])"
  }

  /// Also true for a dangling link, and for a file iCloud has not
  /// downloaded yet (it sits there as ".a.jpg.icloud").
  private static func isTaken(_ url: URL) -> Bool {
    let files = FileManager.default
    if (try? files.attributesOfItem(atPath: url.path)) != nil { return true }
    let placeholder = url.deletingLastPathComponent()
      .appendingPathComponent(".\(url.lastPathComponent).icloud", isDirectory: false)
    return files.fileExists(atPath: placeholder.path)
  }

  /// False if the folder is gone, or in the Trash: a bookmark follows a
  /// folder the user deleted, into the Trash.
  private static func isUsableFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return false }
    return !url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
  }

  /// One path segment. The Dart side has sanitized it already; this makes
  /// sure the file cannot land outside the folder.
  private static func isPlainName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
  }

  private static func isFileExists(_ error: Error) -> Bool {
    let e = error as NSError
    return (e.domain == NSCocoaErrorDomain && e.code == NSFileWriteFileExistsError)
      || (e.domain == NSPOSIXErrorDomain && e.code == Int(EEXIST))
  }

  /// Errors that mean we may not write into the folder at all.
  private static func isAccessDenied(_ error: Error) -> Bool {
    let e = error as NSError
    if e.domain == NSCocoaErrorDomain {
      return e.code == NSFileWriteNoPermissionError || e.code == NSFileWriteVolumeReadOnlyError
    }
    return e.domain == NSPOSIXErrorDomain
      && [Int(EACCES), Int(EPERM), Int(EROFS)].contains(e.code)
  }

  private static func unavailable(_ message: String) -> FlutterError {
    FlutterError(code: "folder_unavailable", message: message, details: nil)
  }
}

/// JPEG copies of HEIC photos, for guests whose devices may not open HEIC
/// (older Android phones, Windows without the HEIF extension). ImageIO
/// copies the metadata too: date, orientation, location.
private enum JpegCopy {
  static func make(from source: String, to target: String) -> Bool {
    let output = URL(fileURLWithPath: target)
    guard let image = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
      CGImageSourceGetCount(image) > 0,
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL, "public.jpeg" as CFString, 1, nil)
    else { return false }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
    CGImageDestinationAddImageFromSource(destination, image, 0, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: output)
      return false
    }
    return true
  }
}
