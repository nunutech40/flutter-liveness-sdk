import Flutter
import UIKit

public final class FlutterLivenessSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private weak var captureController: LivenessViewController?
  private var pendingResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterLivenessSdkPlugin()
    let commands = FlutterMethodChannel(
      name: "com.nunutech40.flutter_liveness_sdk/commands", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(
      name: "com.nunutech40.flutter_liveness_sdk/events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: commands)
    events.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      guard pendingResult == nil else {
        result(FlutterError(code: "session_active", message: "A liveness session is already active", details: nil))
        return
      }
      guard let config = call.arguments as? [String: Any],
            let steps = config["steps"] as? [String], !steps.isEmpty,
            steps.count == Set(steps).count,
            steps.allSatisfy({ ["lookLeft", "lookRight", "smile", "blink"].contains($0) }),
            let timeoutMs = config["timeoutMs"] as? Int, (5000...120000).contains(timeoutMs) else {
        result(FlutterError(code: "invalid_config", message: "Invalid steps or timeout", details: nil))
        return
      }
      guard let presenter = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "no_activity", message: "No foreground view controller", details: nil))
        return
      }
      let controller = LivenessViewController(
        steps: steps, auditMode: config["auditMode"] as? Bool ?? false,
        timeout: TimeInterval(timeoutMs) / 1000)
      controller.onEvent = { [weak self] event in self?.eventSink?(event) }
      controller.onComplete = { [weak self] outcome in
        guard let self = self else { return }
        let completion = self.pendingResult
        self.pendingResult = nil
        completion?(outcome)
        self.captureController = nil
      }
      controller.modalPresentationStyle = .fullScreen
      pendingResult = result
      captureController = controller
      var top = presenter
      while let presented = top.presentedViewController { top = presented }
      top.present(controller, animated: true)
    case "cancel":
      captureController?.cancelCapture()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
