import Flutter
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GeniusTransferHost") {
      HostChannel.register(with: registrar)
    }
  }
}

/// The Dart side's door to iOS. See lib/platform/host_platform.dart.
///
/// iOS suspends apps shortly after they leave the foreground, and the local
/// server with them. When that happens the Dart side asks for the extra
/// background time iOS grants (about 30 seconds, not guaranteed) so a
/// download already running can finish.
///
/// For received files: free space (for the upload limit), a save folder the
/// user picks in Files, delivery into that folder, and Save to Photos.
final class HostChannel: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  /// Kept until the folder picker closes: UIKit holds its delegate weakly.
  private var folderPicker: FolderPickerDelegate?
  /// Deliveries run here, one at a time and off the main thread: a copy to
  /// another volume or a file provider can take a while.
  private let fileQueue = DispatchQueue(label: "geniustransfer.files", qos: .userInitiated)

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "geniustransfer/host", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HostChannel(channel: channel), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "beginBackgroundTask":
      beginBackgroundTask()
      result(nil)
    case "endBackgroundTask":
      endBackgroundTask()
      result(nil)
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
    case "saveToPhotos":
      guard let path = args["path"] as? String, let video = args["video"] as? Bool else {
        return result(Self.badArgs(call))
      }
      saveToPhotos(path: path, video: video, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish transfers") {
      [weak self] in
      self?.channel.invokeMethod("backgroundTimeExpired", arguments: nil)
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  /// Shows the Files folder picker. Replies nil if the user cancels.
  private func pickFolder(result: @escaping FlutterResult) {
    guard folderPicker == nil else {
      return result(
        FlutterError(code: "busy", message: "A folder picker is already open.", details: nil))
    }
    guard let presenter = Self.topViewController() else {
      return result(
        FlutterError(code: "failed", message: "No window to show the picker in.", details: nil))
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    let delegate = FolderPickerDelegate { [weak self] url in
      self?.folderPicker = nil
      result(url.map(SaveFolder.describe(picked:)))
    }
    picker.delegate = delegate
    // Swiping the sheet away is a cancel too.
    picker.presentationController?.delegate = delegate
    folderPicker = delegate
    presenter.present(picker, animated: true)
  }

  /// Adds the file to the Photos library byte for byte, so HEIC stays HEIC
  /// and nothing is re-encoded. Add-only access is all this needs.
  private func saveToPhotos(path: String, video: Bool, result: @escaping FlutterResult) {
    let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      return result(
        FlutterError(code: "failed", message: "File not found: \(url.lastPathComponent)", details: nil))
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        return reply(
          FlutterError(code: "denied", message: "No permission to add to Photos.", details: nil))
      }
      PHPhotoLibrary.shared().performChanges({
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = url.lastPathComponent
        PHAssetCreationRequest.forAsset().addResource(
          with: video ? .video : .photo, fileURL: url, options: options)
      }) { success, error in
        if success {
          reply(true)
        } else {
          let message = error?.localizedDescription ?? "Photos did not take the file."
          reply(FlutterError(code: "failed", message: message, details: nil))
        }
      }
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
    // "Important usage" counts space iOS would free up for the user.
    if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
      return Int(important)
    }
    return values.volumeAvailableCapacity
  }

  /// The view controller on top in the app's window, to present from.
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private static func badArgs(_ call: FlutterMethodCall) -> FlutterError {
    FlutterError(code: "bad_args", message: "Missing arguments for \(call.method).", details: nil)
  }
}

/// Reports the folder picked, or nil, exactly once however the picker
/// closes: Open, Cancel, or swiped away.
private final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private var completion: ((URL?) -> Void)?

  init(completion: @escaping (URL?) -> Void) {
    self.completion = completion
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(urls.first)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }

  private func finish(_ url: URL?) {
    let completion = self.completion
    self.completion = nil
    completion?(url)
  }
}

/// A save folder the user picked in Files: iCloud Drive, another app's
/// storage, a USB drive. iOS lets us in only while we hold its security
/// scope, so the Dart side keeps a bookmark and hands it back with each file.
private enum SaveFolder {
  /// The pickFolder reply: a bookmark to get back in later, and a name to show.
  static func describe(picked url: URL) -> Any {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
      folder = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    } catch {
      return unavailable(error.localizedDescription)
    }
    // False for folders that need no scope (the app's own); the checks
    // and the write below decide whether we may write there.
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
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

  /// A minimal bookmark is enough on iOS: the scope comes with it.
  private static func makeBookmark(for folder: URL) throws -> String {
    try folder.bookmarkData(
      options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
    ).base64EncodedString()
  }

  /// The name Files shows: "iCloud Drive", not "com~apple~CloudDocs".
  private static func displayName(of folder: URL) -> String {
    if let name = try? folder.resourceValues(forKeys: [.localizedNameKey]).localizedName,
      !name.isEmpty
    {
      return name
    }
    return folder.lastPathComponent
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
