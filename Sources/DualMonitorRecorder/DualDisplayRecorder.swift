import AppKit
import AVFoundation
import CoreImage
import ScreenCaptureKit
import SwiftUI

@MainActor
final class DualDisplayRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "연결된 두 모니터를 동시에 녹화합니다."
    @Published private(set) var elapsedText = "00:00:00"
    @Published private(set) var savedFileURL: URL?
    @Published private(set) var windowsMP4URL: URL?
    @Published private(set) var isConverting = false
    @Published private(set) var conversionProgress = ""

    private var streams: [SCStream] = []
    private var streamOutputs: [DisplayStreamOutput] = []
    private var compositor: SideBySideCompositor?
    private var timer: Timer?
    private var startedAt: Date?
    private var globalHotKey: GlobalHotKey?
    private var controlServer: LocalControlServer?
    private var statusSocketServer: StatusWebSocketServer?
    private var lastLayoutPayload: [String: Any]?

    init() {
        globalHotKey = GlobalHotKey { [weak self] in
            self?.toggleRecording()
        }
    }

    func toggleRecording() {
        guard !isBusy else { return }
        isRecording ? stopRecording() : chooseDestinationAndStart()
    }

    func startRemoteControl() {
        guard controlServer == nil else { return }
        let server = LocalControlServer(recorder: self)
        server.start()
        controlServer = server
        let socketServer = StatusWebSocketServer(recorder: self)
        socketServer.start()
        statusSocketServer = socketServer
    }

    var statusPayload: [String: Any] {
        [
            "recording": isRecording,
            "busy": isBusy,
            "status": status,
            "elapsed": elapsedText,
            "savedFile": savedFileURL?.path as Any,
            "shortcut": "Command+F2",
            "hotKeyRegistered": globalHotKey?.isRegistered ?? false,
            "headless": CommandLine.arguments.contains("--headless"),
            "menuBarEnabled": true,
            "layout": lastLayoutPayload as Any,
            "converting": isConverting,
            "windowsFile": windowsMP4URL?.path as Any
        ]
    }

    func chooseDestinationAndStart() {
        DisplayOverlayPresenter.shared.hide()
        if !UserDefaults.standard.bool(forKey: RecorderSettings.askForLocationKey) {
            startAtConfiguredLocation()
            return
        }

        let panel = NSSavePanel()
        panel.title = "녹화 파일 저장"
        panel.nameFieldStringValue = "dual-monitor-\(Self.timestamp()).mov"
        panel.allowedContentTypes = [.quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        savedFileURL = nil
        windowsMP4URL = nil
        isBusy = true
        status = "화면 기록 권한과 모니터를 확인하는 중…"
        Task { await startRecording(to: url) }
    }

    private func startAtConfiguredLocation() {
        let folder = RecorderSettings.configuredFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("dual-monitor-\(Self.timestamp()).mov")
            savedFileURL = nil
            windowsMP4URL = nil
            isBusy = true
            status = "화면 기록 권한과 모니터를 확인하는 중…"
            Task { await startRecording(to: url) }
        } catch {
            status = "저장 폴더를 만들 수 없습니다. 설정에서 다른 폴더를 선택해 주세요."
        }
    }

    private func startRecording(to url: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let saved = RecorderSettings.displayPlacements()
            let enabledIDs = Set(saved.filter(\.isEnabled).map(\.id))
            let displays = saved.isEmpty
                ? content.displays
                : content.displays.filter { enabledIDs.contains($0.displayID) }
            guard !displays.isEmpty else { throw RecorderError.noDisplaysSelected }

            let layout = OutputLayout(displays: displays)
            lastLayoutPayload = [
                "outputWidth": layout.outputWidth,
                "outputHeight": layout.outputHeight,
                "displays": zip(displays, layout.placements).map { display, placement in
                    [
                        "displayID": display.displayID,
                        "x": placement.x,
                        "y": placement.y,
                        "width": placement.width,
                        "height": placement.height
                    ]
                }
            ]
            let compositor = try SideBySideCompositor(url: url, layout: layout)
            self.compositor = compositor

            for (index, display) in displays.enumerated() {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = layout.placements[index].width
                config.height = layout.placements[index].height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 5
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true

                let output = DisplayStreamOutput(index: index, compositor: compositor)
                let stream = SCStream(filter: filter, configuration: config, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: compositor.captureQueue)
                streams.append(stream)
                streamOutputs.append(output)
            }

            for stream in streams { try await stream.startCapture() }

            isRecording = true
            isBusy = false
            startedAt = Date()
            status = "선택한 모니터 \(displays.count)대를 녹화하고 있습니다."
            startTimer()
        } catch {
            await cleanupAfterFailure()
            isBusy = false
            status = Self.message(for: error)
        }
    }

    func stopRecording() {
        guard isRecording, !isBusy else { return }
        isBusy = true
        status = "녹화 파일을 마무리하는 중…"
        timer?.invalidate()

        Task {
            for stream in streams { try? await stream.stopCapture() }
            let outputURL = await compositor?.finish()
            streams.removeAll()
            streamOutputs.removeAll()
            compositor = nil
            isRecording = false
            elapsedText = "00:00:00"
            savedFileURL = outputURL
            if let outputURL, UserDefaults.standard.bool(forKey: RecorderSettings.autoConvertForWindowsKey) {
                status = "Windows용 MP4로 변환하는 중…"
                isConverting = true
                do {
                    windowsMP4URL = try await WindowsVideoConverter.convert(outputURL)
                    status = "MOV와 Windows용 MP4 저장 완료"
                } catch {
                    status = "MOV 저장 완료, MP4 변환 실패: \(error.localizedDescription)"
                }
                isConverting = false
            } else {
                status = outputURL == nil ? "녹화를 저장하지 못했습니다." : "저장 완료: \(outputURL!.lastPathComponent)"
            }
            isBusy = false
        }
    }

    func convertForWindows() {
        guard let savedFileURL, !isConverting, !isRecording else { return }
        isConverting = true
        status = "Windows용 H.264 MP4로 변환하는 중…"
        Task {
            do {
                windowsMP4URL = try await WindowsVideoConverter.convert(savedFileURL)
                status = "Windows용 MP4 저장 완료: \(windowsMP4URL!.lastPathComponent)"
            } catch {
                status = "MP4 변환 실패: \(error.localizedDescription)"
            }
            isConverting = false
            conversionProgress = ""
        }
    }

    func convertDroppedFiles(_ urls: [URL]) {
        let supported = urls.filter {
            ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased())
        }
        guard !supported.isEmpty, !isConverting, !isRecording else {
            if supported.isEmpty { status = "MOV, MP4 또는 M4V 파일을 넣어 주세요." }
            return
        }

        isConverting = true
        Task {
            var succeeded = 0
            var lastOutput: URL?
            for (index, sourceURL) in supported.enumerated() {
                conversionProgress = "\(index + 1) / \(supported.count)"
                status = "Windows용 MP4 변환 중: \(sourceURL.lastPathComponent)"
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                do {
                    lastOutput = try await WindowsVideoConverter.convert(sourceURL)
                    succeeded += 1
                } catch {
                    status = "\(sourceURL.lastPathComponent) 변환 실패: \(error.localizedDescription)"
                }
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }
            windowsMP4URL = lastOutput
            isConverting = false
            conversionProgress = ""
            status = "Windows용 MP4 변환 완료: \(succeeded) / \(supported.count)개"
        }
    }

    func openWindowsVideo() {
        guard let windowsMP4URL else { return }
        NSWorkspace.shared.open(windowsMP4URL)
    }

    func openSavedVideo() {
        guard let savedFileURL else { return }
        NSWorkspace.shared.open(savedFileURL)
    }

    func revealSavedVideo() {
        guard let savedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedFileURL])
    }

    private func cleanupAfterFailure() async {
        for stream in streams { try? await stream.stopCapture() }
        _ = await compositor?.cancel()
        streams.removeAll()
        streamOutputs.removeAll()
        compositor = nil
        isRecording = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                let seconds = Int(Date().timeIntervalSince(startedAt))
                self.elapsedText = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func message(for error: Error) -> String {
        if case RecorderError.noDisplaysSelected = error {
            return "녹화할 모니터가 없습니다. 설정에서 한 대 이상 선택해 주세요."
        }
        return "녹화를 시작할 수 없습니다. 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 권한을 허용해 주세요. (\(error.localizedDescription))"
    }
}

private enum RecorderError: Error {
    case noDisplaysSelected
    case writerSetupFailed
}

private struct OutputLayout {
    struct Placement {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    let placements: [Placement]
    let outputWidth: Int
    let outputHeight: Int

    init(displays: [SCDisplay]) {
        let saved = RecorderSettings.displayPlacements()
        let origins = displays.map { display -> (x: Double, y: Double) in
            if let item = saved.first(where: { $0.id == display.displayID }) {
                return (item.x, item.y)
            }
            return (Double(display.frame.origin.x), Double(display.frame.origin.y))
        }
        let minX = origins.map(\.x).min() ?? 0
        let minY = origins.map(\.y).min() ?? 0
        let maxX = zip(displays, origins).map { Double($0.0.width) + $0.1.x }.max() ?? 2
        let maxY = zip(displays, origins).map { Double($0.0.height) + $0.1.y }.max() ?? 2
        let nativeWidth = max(2, maxX - minX)
        let nativeHeight = max(2, maxY - minY)
        let widestDisplay = Double(displays.map(\.width).max() ?? 2)
        let scale = min(1, 2560 / widestDisplay, 7680 / nativeWidth, 4320 / nativeHeight)

        placements = zip(displays, origins).map { display, origin in
            Placement(
                x: PixelAlignment.coordinate(Int((origin.x - minX) * scale)),
                y: PixelAlignment.coordinate(Int((maxY - origin.y - Double(display.height)) * scale)),
                width: PixelAlignment.size(Int(Double(display.width) * scale)),
                height: PixelAlignment.size(Int(Double(display.height) * scale))
            )
        }
        outputWidth = PixelAlignment.size(Int(nativeWidth * scale))
        outputHeight = PixelAlignment.size(Int(nativeHeight * scale))
    }
}

private final class DisplayStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let index: Int
    weak var compositor: SideBySideCompositor?

    init(index: Int, compositor: SideBySideCompositor) {
        self.index = index
        self.compositor = compositor
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        compositor?.receive(sampleBuffer, displayIndex: index)
    }
}

private final class SideBySideCompositor: @unchecked Sendable {
    let captureQueue = DispatchQueue(label: "dual-monitor.capture", qos: .userInteractive)

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let layout: OutputLayout
    private let outputURL: URL
    private var latestFrames: [Int: CVPixelBuffer] = [:]
    private var firstTimestamp: CMTime?
    private var lastAppendedTimestamp = CMTime.invalid
    private var finished = false

    init(url: URL, layout: OutputLayout) throws {
        self.layout = layout
        self.outputURL = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: layout.outputWidth,
            AVVideoHeightKey: layout.outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 18_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: layout.outputWidth,
            kCVPixelBufferHeightKey as String: layout.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw RecorderError.writerSetupFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerSetupFailed }
    }

    func receive(_ sampleBuffer: CMSampleBuffer, displayIndex: Int) {
        dispatchPrecondition(condition: .onQueue(captureQueue))
        guard !finished, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestFrames[displayIndex] = imageBuffer
        guard latestFrames.count == layout.placements.count, input.isReadyForMoreMediaData else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstTimestamp == nil {
            firstTimestamp = timestamp
            writer.startSession(atSourceTime: .zero)
        }
        let relativeTime = CMTimeSubtract(timestamp, firstTimestamp!)
        if lastAppendedTimestamp.isValid,
           CMTimeCompare(relativeTime, CMTimeAdd(lastAppendedTimestamp, CMTime(value: 1, timescale: 60))) < 0 { return }
        guard let pool = adaptor.pixelBufferPool else { return }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
              let destination else { return }

        CVPixelBufferLockBaseAddress(destination, [])
        if let base = CVPixelBufferGetBaseAddress(destination) {
            memset(base, 0, CVPixelBufferGetBytesPerRow(destination) * CVPixelBufferGetHeight(destination))
        }
        CVPixelBufferUnlockBaseAddress(destination, [])

        for index in layout.placements.indices {
            guard let frame = latestFrames[index] else { continue }
            let placement = layout.placements[index]
            let source = CIImage(cvPixelBuffer: frame)
            let sx = CGFloat(placement.width) / source.extent.width
            let sy = CGFloat(placement.height) / source.extent.height
            let image = source.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .transformed(by: CGAffineTransform(translationX: CGFloat(placement.x), y: CGFloat(placement.y)))
            let bounds = CGRect(x: placement.x, y: placement.y, width: placement.width, height: placement.height)
            context.render(image, to: destination, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        }

        if adaptor.append(destination, withPresentationTime: relativeTime) {
            lastAppendedTimestamp = relativeTime
        }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                guard !self.finished else { continuation.resume(returning: nil); return }
                self.finished = true
                self.input.markAsFinished()
                self.writer.finishWriting {
                    continuation.resume(returning: self.writer.status == .completed ? self.outputURL : nil)
                }
            }
        }
    }

    func cancel() async -> URL? {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                self.finished = true
                self.writer.cancelWriting()
                try? FileManager.default.removeItem(at: self.outputURL)
                continuation.resume(returning: nil)
            }
        }
    }
}
