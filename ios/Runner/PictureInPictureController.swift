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
        do {
          guard let videoTrack = videoAsset.tracks(withMediaType: .video).first,
                let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            result(FlutterError(code: "video_track", message: "Unable to load the video track", details: nil))
            return
          }
          try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoAsset.duration), of: videoTrack, at: .zero)
          if let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
             let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: audioAsset.duration), of: audioTrack, at: .zero)
          }
          self.start(item: AVPlayerItem(asset: composition), position: position, playing: playing, result: result)
        } catch {
          result(FlutterError(code: "composition", message: error.localizedDescription, details: nil))
        }
      }
    } else {
      item = AVPlayerItem(asset: asset(url: videoUrl))
      start(item: item, position: position, playing: playing, result: result)
    }
  }

  private func start(item: AVPlayerItem, position: Double, playing: Bool, result: @escaping FlutterResult) {
    let player = AVPlayer(playerItem: item)
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
      result(FlutterError(code: "window", message: "Unable to attach the Picture in Picture player", details: nil))
      return
    }
    rootView.addSubview(hostView)
    guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
      result(FlutterError(code: "unsupported", message: "Picture in Picture is not available", details: nil))
      return
    }
    controller.delegate = self
    self.player = player
    self.playerLayer = playerLayer
    self.hostView = hostView
    self.controller = controller
    player.seek(to: CMTime(milliseconds: position), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
      if playing { player.play() }
      self.beginPictureInPicture(controller, result: result)
    }
  }

  private func beginPictureInPicture(
    _ controller: AVPictureInPictureController,
    result: @escaping FlutterResult,
    attemptsRemaining: Int = 15
  ) {
    guard self.controller === controller else { return }
    if controller.isPictureInPicturePossible {
      pendingStartResult = result
      controller.startPictureInPicture()
      return
    }
    guard attemptsRemaining > 0 else {
      result(FlutterError(code: "not_ready", message: "Picture in Picture could not be prepared for this video", details: nil))
      stop(notifyFlutter: false)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.beginPictureInPicture(controller, result: result, attemptsRemaining: attemptsRemaining - 1)
    }
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let position = player?.currentTime().milliseconds ?? restorePosition.milliseconds
    let resume = shouldResume
    stop(notifyFlutter: false)
    channel.invokeMethod("didStop", arguments: ["positionMs": position, "shouldResume": resume])
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    pendingStartResult?(nil)
    pendingStartResult = nil
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    pendingStartResult?(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
    pendingStartResult = nil
    stop(notifyFlutter: false)
  }

  private func stop(notifyFlutter: Bool = true) {
    if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
    player?.pause()
    controller = nil
    playerLayer = nil
    player = nil
    hostView?.removeFromSuperview()
    hostView = nil
  }

  private func asset(url: URL) -> AVURLAsset {
    AVURLAsset(url: url)
  }
}

private extension CMTime {
  init(milliseconds: Double) { self.init(value: CMTimeValue(milliseconds.rounded()), timescale: 1000) }
  var milliseconds: Double { CMTimeGetSeconds(self) * 1000 }
}
