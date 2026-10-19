import Flutter
import UIKit

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
final class HostChannel: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "geniustransfer/host", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HostChannel(channel: channel), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beginBackgroundTask":
      beginBackgroundTask()
      result(nil)
    case "endBackgroundTask":
      endBackgroundTask()
      result(nil)
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
}
