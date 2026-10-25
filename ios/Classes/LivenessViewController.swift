import AVFoundation
import MLKitFaceDetection
import MLKitVision
import UIKit

private final class ChallengeEngine {
  let steps: [String]
  private(set) var index = 0
  private var baselineSeen = false
  private var stableFrames = 0
  private var blinkPhase = 0
  private var trackingID: Int?

  init(steps: [String]) { self.steps = steps }
  var currentStep: String? { index < steps.count ? steps[index] : nil }

  func resetTransient() {
    baselineSeen = false
    stableFrames = 0
    blinkPhase = 0
    trackingID = nil
  }

  func update(_ face: Face) -> (passed: String?, finalReady: Bool) {
    let id: Int? = face.hasTrackingID ? face.trackingID : nil
    if let previous = trackingID, let id = id, previous != id { resetTransient() }
    trackingID = id
    guard face.hasHeadEulerAngleY else { resetTransient(); return (nil, false) }
    let yaw = face.headEulerAngleY
    if index == steps.count {
      stableFrames = abs(yaw) < 10 ? stableFrames + 1 : 0
      return (nil, stableFrames >= 2)
    }
    let step = steps[index]
    let frontal = abs(yaw) < 15
    var passed = false
    switch step {
    case "lookLeft": passed = transition(abs(yaw) < 12, yaw > 35)
    case "lookRight": passed = transition(abs(yaw) < 12, yaw < -35)
    case "smile":
      let probability = face.hasSmilingProbability ? face.smilingProbability : -1
      passed = transition(frontal && probability >= 0 && probability < 0.4,
                          frontal && probability > 0.7)
    case "blink":
      if frontal && face.hasLeftEyeOpenProbability && face.hasRightEyeOpenProbability {
        let left = face.leftEyeOpenProbability
        let right = face.rightEyeOpenProbability
        if blinkPhase == 0 && left > 0.7 && right > 0.7 { blinkPhase = 1 }
        else if blinkPhase == 1 && left < 0.4 && right < 0.4 { blinkPhase = 2 }
        else if blinkPhase == 2 && left > 0.7 && right > 0.7 { passed = true }
      }
    default: break
    }
    guard passed else { return (nil, false) }
    index += 1
    baselineSeen = false
    stableFrames = 0
    blinkPhase = 0
    return (step, false)
  }

  private func transition(_ baseline: Bool, _ target: Bool) -> Bool {
    if baseline { baselineSeen = true }
    stableFrames = baselineSeen && target ? stableFrames + 1 : 0
    return stableFrames >= 2
  }
}

final class LivenessViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate,
  AVCapturePhotoCaptureDelegate {
  var onEvent: (([String: Any]) -> Void)?
  var onComplete: (([String: Any]) -> Void)?

  private let engine: ChallengeEngine
  private let auditMode: Bool
  private let timeout: TimeInterval
  private let cameraQueue = DispatchQueue(label: "com.nunutech40.liveness.camera")
  private let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let detector: FaceDetector
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let statusLabel = UILabel()
  private var timer: Timer?
  private var evidence = [String: String]()
  private var terminal = false
  private var capturing = false
  private var lastGuidance: String?

  init(steps: [String], auditMode: Bool, timeout: TimeInterval) {
    self.engine = ChallengeEngine(steps: steps)
    self.auditMode = auditMode
    self.timeout = timeout
    let options = FaceDetectorOptions()
    options.performanceMode = ProcessInfo.processInfo.physicalMemory < 2 * 1024 * 1024 * 1024 ? .fast : .accurate
    options.landmarkMode = .all
    options.classificationMode = .all
    options.isTrackingEnabled = true
    self.detector = FaceDetector.faceDetector(options: options)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)
    let overlay = UIStackView()
    overlay.axis = .vertical
    overlay.distribution = .equalSpacing
    overlay.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.text = "Preparing camera…"
    statusLabel.textColor = .white
    statusLabel.font = .systemFont(ofSize: 23, weight: .semibold)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    overlay.addArrangedSubview(statusLabel)
    let cancelButton = UIButton(type: .system)
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.setTitleColor(.white, for: .normal)
    cancelButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
    overlay.addArrangedSubview(cancelButton)
    view.addSubview(overlay)
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      overlay.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
    ])
    NotificationCenter.default.addObserver(
      self, selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      self?.finish(status: "timedOut", errorCode: "timeout")
    }
    requestCamera()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
  }

  private func requestCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: configureCamera()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
        DispatchQueue.main.async {
          if allowed { self?.configureCamera() }
          else { self?.finish(status: "failed", errorCode: "camera_permission_denied") }
        }
      }
    default: finish(status: "failed", errorCode: "camera_permission_denied")
    }
  }

  private func configureCamera() {
    cameraQueue.async { [weak self] in
      guard let self = self else { return }
      guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera) else {
        DispatchQueue.main.async { self.finish(status: "failed", errorCode: "front_camera_unavailable") }
        return
      }
      self.session.beginConfiguration()
      self.session.sessionPreset = .photo
      let videoOutput = AVCaptureVideoDataOutput()
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.setSampleBufferDelegate(self, queue: self.cameraQueue)
      guard self.session.canAddInput(input), self.session.canAddOutput(videoOutput),
            self.session.canAddOutput(self.photoOutput) else {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.finish(status: "failed", errorCode: "camera_bind_failed") }
        return
      }
      self.session.addInput(input)
      self.session.addOutput(videoOutput)
      self.session.addOutput(self.photoOutput)
      self.session.commitConfiguration()
      self.session.startRunning()
      DispatchQueue.main.async {
        guard !self.terminal else { return }
        self.statusLabel.text = self.instruction(self.engine.currentStep)
        self.onEvent?(["type": "ready", "step": (self.engine.currentStep as Any?) ?? NSNull()])
      }
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    guard !terminal, !capturing else { return }
    let image = VisionImage(buffer: sampleBuffer)
    image.orientation = .leftMirrored
    do {
      let faces = try detector.results(in: image)
      if faces.isEmpty { engine.resetTransient(); guide("no_face"); return }
      if faces.count > 1 { engine.resetTransient(); guide("multiple_faces"); return }
      let update = engine.update(faces[0])
      if let step = update.passed {
        if auditMode {
          guard saveEvidence(step: step, sampleBuffer: sampleBuffer) else {
            DispatchQueue.main.async { self.finish(status: "failed", errorCode: "evidence_capture_failed") }
            return
          }
        }
        DispatchQueue.main.async {
          self.onEvent?(["type": "stepPassed", "step": step])
          self.statusLabel.text = self.instruction(self.engine.currentStep)
        }
      }
      if update.finalReady {
        capturing = true
        DispatchQueue.main.async { self.captureSelfie() }
      }
    } catch {
      DispatchQueue.main.async { self.finish(status: "failed", errorCode: "face_detection_failed") }
    }
  }

  private func saveEvidence(step: String, sampleBuffer: CMSampleBuffer) -> Bool {
    guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
    let context = CIContext()
    let image = CIImage(cvPixelBuffer: buffer).oriented(.leftMirrored)
    guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB()),
          let url = temporaryURL("\(step).jpg") else { return false }
    do {
      try data.write(to: url, options: .atomic)
      evidence[step] = url.path
      return true
    } catch { return false }
  }

  private func captureSelfie() {
    guard !terminal else { return }
    statusLabel.text = "Capturing selfie…"
    photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                   error: Error?) {
    guard !terminal, error == nil, let data = photo.fileDataRepresentation(),
          let url = temporaryURL("selfie.jpg") else {
      DispatchQueue.main.async { self.finish(status: "failed", errorCode: "selfie_capture_failed") }
      return
    }
    do {
      try data.write(to: url, options: .atomic)
      DispatchQueue.main.async { self.finish(status: "success", selfiePath: url.path) }
    } catch {
      DispatchQueue.main.async { self.finish(status: "failed", errorCode: "selfie_capture_failed") }
    }
  }

  private func temporaryURL(_ suffix: String) -> URL? {
    FileManager.default.temporaryDirectory.appendingPathComponent("liveness_\(UUID().uuidString)_\(suffix)")
  }

  private func guide(_ code: String) {
    guard lastGuidance != code else { return }
    lastGuidance = code
    DispatchQueue.main.async {
      guard !self.terminal else { return }
      self.statusLabel.text = code == "no_face" ? "Show your face" : "Only one face in frame"
      self.onEvent?(["type": "guidance", "code": code])
    }
  }

  private func instruction(_ step: String?) -> String {
    switch step {
    case "lookLeft": return "Look left"
    case "lookRight": return "Look right"
    case "smile": return "Start neutral, then smile"
    case "blink": return "Open your eyes, then blink"
    default: return "Face forward for the final photo"
    }
  }

  @objc func cancelCapture() { finish(status: "cancelled") }

  @objc private func appDidEnterBackground() {
    finish(status: "cancelled", errorCode: "interrupted")
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  private func finish(status: String, errorCode: String? = nil, selfiePath: String? = nil) {
    guard !terminal else { return }
    terminal = true
    timer?.invalidate()
    timer = nil
    cameraQueue.async { [session] in session.stopRunning() }
    let outcome: [String: Any] = [
      "status": status, "errorCode": (errorCode as Any?) ?? NSNull(),
      "selfiePath": (selfiePath as Any?) ?? NSNull(), "evidencePaths": evidence,
    ]
    dismiss(animated: true) { [onComplete] in onComplete?(outcome) }
  }
}
