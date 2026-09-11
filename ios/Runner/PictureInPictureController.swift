import AVFoundation
import AVKit
import Flutter
import UIKit

/// Provides system Picture in Picture for the media_kit based Flutter player.
/// AVPlayer is used only while the system PiP window is active because iOS only
/// exposes the standard PiP controller for AVPlayerLayer content.
final class PictureInPictureController: NSObject, AVPictureInPictureControllerDelegate {
  static let channelName = "com.piliplus/picture_in_picture"

  private let channel: FlutterMethodChannel
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var hostView: UIView?
  private var controller: AVPictureInPictureController?
  private var pendingStartResult: FlutterResult?
  private var requestGeneration = 0
  private var restorePosition = CMTime.zero
  private var shouldResume = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "start":
      guard let arguments = call.arguments as? [String: Any],
            let videoUrlString = arguments["videoUrl"] as? String,
            let videoUrl = URL(string: videoUrlString),
            AVPictureInPictureController.isPictureInPictureSupported() else {
        result(FlutterError(code: "unavailable", message: "Picture in Picture is unavailable", details: nil))
        return
      }
      let audioUrl = (arguments["audioUrl"] as? String).flatMap(URL.init(string:))
      let position = (arguments["positionMs"] as? NSNumber)?.doubleValue ?? 0
      let playing = (arguments["isPlaying"] as? NSNumber)?.boolValue ?? true
      start(videoUrl: videoUrl, audioUrl: audioUrl, position: position, playing: playing, result: result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(videoUrl: URL, audioUrl: URL?, position: Double, playing: Bool, result: @escaping FlutterResult) {
    stop(notifyFlutter: false)
    let requestID = requestGeneration
    pendingStartResult = result
    restorePosition = CMTime(milliseconds: position)
    shouldResume = playing

    let item: AVPlayerItem
    if let audioUrl {
      // Bilibili DASH sources often carry video and audio separately. Combining
      // their tracks lets the iOS PiP player retain sound instead of playing a
      // silent video stream.
      let composition = AVMutableComposition()
      let videoAsset = asset(url: videoUrl)
      let audioAsset = asset(url: audioUrl)
      let group = DispatchGroup()
      group.enter()
      videoAsset.loadValuesAsynchronously(forKeys: ["tracks"]) { group.leave() }
      group.enter()
      audioAsset.loadValuesAsynchronously(forKeys: ["tracks"]) { group.leave() }
      group.notify(queue: .main) { [weak self] in
        guard let self else { return }
        guard self.requestGeneration == requestID else { return }
        do {
          guard let videoTrack = videoAsset.tracks(withMediaType: .video).first,
                let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            self.finish(requestID: requestID, with: FlutterError(code: "video_track", message: "Unable to load the video track", details: nil), cleanup: true)
            return
          }
          try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: videoTrack, at: .zero)
          if let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
             let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: audioAsset.duration), of: audioTrack, at: .zero)
          }
          self.start(item: AVPlayerItem(asset: composition), videoUrl: videoUrl, position: position, playing: playing, requestID: requestID)
        } catch {
          self.finish(requestID: requestID, with: FlutterError(code: "composition", message: error.localizedDescription, details: nil), cleanup: true)
        }
      }
    } else {
      item = AVPlayerItem(asset: asset(url: videoUrl))
      start(item: item, videoUrl: videoUrl, position: position, playing: playing, requestID: requestID)
    }
  }

  private func start(item: AVPlayerItem, videoUrl: URL, position: Double, playing: Bool, requestID: Int) {
    guard requestGeneration == requestID else { return }
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    let playerLayer = AVPlayerLayer(player: player)
    // AVPictureInPictureController needs a non-zero AVPlayerLayer attached to
    // the window. The tiny layer is not used for the app's visible playback.
    let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
    hostView.isUserInteractionEnabled = false
    playerLayer.frame = hostView.bounds
    hostView.layer.addSublayer(playerLayer)
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    guard let rootView = keyWindow?.rootViewController?.view else {
      finish(requestID: requestID, with: FlutterError(code: "window", message: "Unable to attach the Picture in Picture player", details: nil), cleanup: true)
      return
    }
    rootView.addSubview(hostView)
    guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
      hostView.removeFromSuperview()
      finish(requestID: requestID, with: FlutterError(code: "unsupported", message: "Picture in Picture is not available", details: nil), cleanup: true)
      return
    }
    controller.delegate = self
    self.player = player
    self.playerLayer = playerLayer
    self.hostView = hostView
    self.controller = controller
    let seekTolerance = CMTime(value: 500, timescale: 1000)
    player.seek(to: CMTime(milliseconds: position), toleranceBefore: seekTolerance, toleranceAfter: seekTolerance) { _ in
      guard self.requestGeneration == requestID, self.controller === controller else { return }
      if playing { player.play() }
      self.beginPictureInPicture(controller, videoUrl: videoUrl, requestID: requestID)
    }
  }

  private func beginPictureInPicture(
    _ controller: AVPictureInPictureController,
    videoUrl: URL,
    requestID: Int,
    attemptsRemaining: Int = 15
  ) {
    guard requestGeneration == requestID, self.controller === controller else { return }
    if controller.isPictureInPicturePossible {
      channel.invokeMethod("willStart", arguments: ["videoUrl": videoUrl.absoluteString]) { [weak self] response in
        guard let self,
              self.requestGeneration == requestID,
              self.controller === controller else { return }
        let allowed = (response as? NSNumber)?.boolValue ?? (response as? Bool ?? false)
        guard allowed else {
          self.finish(requestID: requestID, with: FlutterError(code: "cancelled", message: "Picture in Picture request was cancelled", details: nil), cleanup: true)
          return
        }
        self.player?.isMuted = false
        controller.startPictureInPicture()
      }
      return
    }
    guard attemptsRemaining > 0 else {
      finish(requestID: requestID, with: FlutterError(code: "not_ready", message: "Picture in Picture could not be prepared for this video", details: nil), cleanup: true)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.beginPictureInPicture(controller, videoUrl: videoUrl, requestID: requestID, attemptsRemaining: attemptsRemaining - 1)
    }
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard controller === pictureInPictureController else { return }
    let position = player?.currentTime().milliseconds ?? restorePosition.milliseconds
    let resume = shouldResume
    stop(notifyFlutter: false)
    channel.invokeMethod("didStop", arguments: ["positionMs": position, "shouldResume": resume])
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard controller === pictureInPictureController else { return }
    finish(requestID: requestGeneration, with: nil)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    guard controller === pictureInPictureController else { return }
    finish(requestID: requestGeneration, with: FlutterError(code: "start_failed", message: error.localizedDescription, details: nil), cleanup: true)
  }

  private func stop(notifyFlutter: Bool = true) {
    requestGeneration &+= 1
    if let pendingStartResult {
      self.pendingStartResult = nil
      pendingStartResult(FlutterError(code: "cancelled", message: "Picture in Picture request was cancelled", details: nil))
    }
    cleanupPlayer()
  }

  private func finish(requestID: Int, with value: Any?, cleanup: Bool = false) {
    guard requestGeneration == requestID, let pendingStartResult else { return }
    self.pendingStartResult = nil
    pendingStartResult(value)
    if cleanup { cleanupPlayer() }
  }

  private func cleanupPlayer() {
    if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
    player?.pause()
    controller = nil
    playerLayer = nil
    player = nil
    hostView?.removeFromSuperview()
    hostView = nil
  }

  private func asset(url: URL) -> AVURLAsset {
    AVURLAsset(url: url, options: [
      // Bilibili's media CDN rejects DASH segment requests unless both of
      // these headers are present. Use the raw key because Apple exposes a
      // public user-agent option, but no public option for arbitrary headers.
      "AVURLAssetHTTPHeaderFieldsKey": [
        "Referer": "https://www.bilibili.com/",
        "User-Agent": "Mozilla/5.0",
      ],
    ])
  }
}

private extension CMTime {
  init(milliseconds: Double) { self.init(value: CMTimeValue(milliseconds.rounded()), timescale: 1000) }
  var milliseconds: Double { CMTimeGetSeconds(self) * 1000 }
}
