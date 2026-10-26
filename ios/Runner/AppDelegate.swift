import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var cachedVideoExporter: CachedVideoExporter?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false // Disable shake to undo
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PipPlugin") {
      PipPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CachedVideoExporter") {
      cachedVideoExporter = CachedVideoExporter(messenger: registrar.messenger())
    }
  }
}

private final class CachedVideoExporter: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?
  private var temporaryDirectory: URL?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.piliplus/cached_video_export",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "export" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "已有视频正在导出", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let videoPath = arguments["videoPath"] as? String,
          let fileName = arguments["fileName"] as? String else {
      result(FlutterError(code: "arguments", message: "导出参数不完整", details: nil))
      return
    }

    let videoURL = URL(fileURLWithPath: videoPath)
    let audioURL = (arguments["audioPath"] as? String).map(URL.init(fileURLWithPath:))
    guard FileManager.default.fileExists(atPath: videoURL.path),
          audioURL.map({ FileManager.default.fileExists(atPath: $0.path) }) ?? true else {
      result(FlutterError(code: "missing_file", message: "缓存文件不完整", details: nil))
      return
    }

    pendingResult = result
    Task { [weak self] in
      do {
        let outputURL = try Self.makeTemporaryURL(fileName: fileName)
        do {
          if let audioURL {
            try await Self.mux(videoURL: videoURL, audioURL: audioURL, outputURL: outputURL)
          } else if videoURL.pathExtension.lowercased() == "mp4" {
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
          } else {
            try await Self.mux(videoURL: videoURL, audioURL: nil, outputURL: outputURL)
          }
        } catch {
          try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
          throw error
        }
        await MainActor.run {
          self?.presentPicker(for: outputURL)
        }
      } catch {
        await MainActor.run {
          self?.finish(with: FlutterError(
            code: "export_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private static func makeTemporaryURL(fileName: String) throws -> URL {
    let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
    let safeName = fileName.components(separatedBy: illegal)
      .filter { !$0.isEmpty }
      .joined(separator: "_")
    let baseName = (safeName as NSString).deletingPathExtension
    let finalName = baseName.isEmpty ? "PiliPlus缓存视频.mp4" : "\(baseName.prefix(80)).mp4"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PiliPlusExports", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(finalName)
  }

  private static func mux(videoURL: URL, audioURL: URL?, outputURL: URL) async throws {
    // AVFoundation uses the extension to recognize local media. Hard links
    // expose cached .m4s data as MP4 without copying large source files.
    let inputDirectory = outputURL.deletingLastPathComponent()
      .appendingPathComponent("MuxInputs", isDirectory: true)
    try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: inputDirectory) }

    let stagedVideo = inputDirectory.appendingPathComponent("video.mp4")
    try FileManager.default.linkItem(at: videoURL, to: stagedVideo)
    let stagedAudio: URL?
    if let audioURL {
      let url = inputDirectory.appendingPathComponent("audio.mp4")
      try FileManager.default.linkItem(at: audioURL, to: url)
      stagedAudio = url
    } else {
      stagedAudio = nil
    }

    let videoAsset = AVURLAsset(url: stagedVideo)
    guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
      throw ExportError.missingVideoTrack
    }
    let videoReader = try AVAssetReader(asset: videoAsset)
    let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    videoOutput.alwaysCopiesSampleData = false
    guard videoReader.canAdd(videoOutput) else { throw ExportError.cannotCreateReader }
    videoReader.add(videoOutput)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: nil,
      sourceFormatHint: videoTrack.formatDescriptions.first.map { $0 as! CMFormatDescription }
    )
    videoInput.expectsMediaDataInRealTime = false
    videoInput.transform = videoTrack.preferredTransform
    guard writer.canAdd(videoInput) else { throw ExportError.cannotCreateWriter }
    writer.add(videoInput)

    var audioReader: AVAssetReader?
    var audioOutput: AVAssetReaderTrackOutput?
    var audioInput: AVAssetWriterInput?
    if let stagedAudio {
      let audioAsset = AVURLAsset(url: stagedAudio)
      guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else {
        throw ExportError.missingAudioTrack
      }
      let reader = try AVAssetReader(asset: audioAsset)
      let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      guard reader.canAdd(output) else { throw ExportError.cannotCreateReader }
      reader.add(output)
      let input = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: nil,
        sourceFormatHint: audioTrack.formatDescriptions.first.map { $0 as! CMFormatDescription }
      )
      input.expectsMediaDataInRealTime = false
      guard writer.canAdd(input) else { throw ExportError.cannotCreateWriter }
      writer.add(input)
      audioReader = reader
      audioOutput = output
      audioInput = input
    }

    do {
      guard writer.startWriting(), videoReader.startReading() else {
        throw writer.error ?? videoReader.error ?? ExportError.cannotStartExport
      }
      if let audioReader, !audioReader.startReading() {
        throw audioReader.error ?? ExportError.cannotStartExport
      }
      writer.startSession(atSourceTime: .zero)

      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await pump(videoOutput, from: videoReader, into: videoInput, writer: writer)
        }
        if let audioReader, let audioOutput, let audioInput {
          group.addTask {
            try await pump(audioOutput, from: audioReader, into: audioInput, writer: writer)
          }
        }
        do {
          for try await _ in group {}
        } catch {
          group.cancelAll()
          throw error
        }
      }

      await withCheckedContinuation { continuation in
        writer.finishWriting { continuation.resume() }
      }
      guard writer.status == .completed else {
        throw writer.error ?? ExportError.writeFailed
      }
    } catch {
      videoReader.cancelReading()
      audioReader?.cancelReading()
      writer.cancelWriting()
      throw error
    }
  }

  private static func pump(
    _ output: AVAssetReaderOutput,
    from reader: AVAssetReader,
    into input: AVAssetWriterInput,
    writer: AVAssetWriter
  ) async throws {
    while true {
      try Task.checkCancellation()
      if writer.status == .failed || writer.status == .cancelled {
        throw writer.error ?? ExportError.writeFailed
      }
      if reader.status == .failed || reader.status == .cancelled {
        throw reader.error ?? ExportError.readFailed
      }
      guard input.isReadyForMoreMediaData else {
        try await Task.sleep(nanoseconds: 5_000_000)
        continue
      }
      guard let sample = output.copyNextSampleBuffer() else {
        guard reader.status == .completed else {
          throw reader.error ?? ExportError.readFailed
        }
        input.markAsFinished()
        return
      }
      guard input.append(sample) else {
        throw writer.error ?? ExportError.writeFailed
      }
    }
  }

  @MainActor
  private func presentPicker(for outputURL: URL) {
    temporaryDirectory = outputURL.deletingLastPathComponent()
    guard let presenter = topViewController() else {
      finish(with: FlutterError(code: "presentation", message: "无法打开文件导出界面", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forExporting: [outputURL], asCopy: true)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  @MainActor
  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(with: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: false)
  }

  private func finish(with value: Any?) {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
      self.temporaryDirectory = nil
    }
    let result = pendingResult
    pendingResult = nil
    result?(value)
  }
}

private enum ExportError: LocalizedError {
  case missingVideoTrack
  case missingAudioTrack
  case cannotCreateReader
  case cannotCreateWriter
  case cannotStartExport
  case readFailed
  case writeFailed

  var errorDescription: String? {
    switch self {
    case .missingVideoTrack: return "缓存中没有可导出的视频轨道"
    case .missingAudioTrack: return "缓存中没有可导出的音频轨道"
    case .cannotCreateReader: return "无法读取缓存媒体轨道"
    case .cannotCreateWriter: return "无法创建 MP4 输出轨道"
    case .cannotStartExport: return "无法启动视频导出任务"
    case .readFailed: return "读取缓存分片失败"
    case .writeFailed: return "写入 MP4 文件失败"
    }
  }
}
