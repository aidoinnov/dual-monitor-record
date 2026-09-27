import AVFoundation
import CoreVideo
import Foundation

enum WindowsVideoConverter {
    enum ConversionError: LocalizedError {
        case noVideoTrack
        case unsupportedSize(Int, Int)
        case cannotConfigure
        case readingFailed(String)
        case writingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "영상 트랙을 찾을 수 없습니다."
            case .unsupportedSize(let width, let height):
                return "Windows 호환 H.264 변환은 최대 4096×4096입니다. 현재 영상: \(width)×\(height)"
            case .cannotConfigure: return "MP4 변환기를 구성할 수 없습니다."
            case .readingFailed(let message): return "원본 영상을 읽지 못했습니다: \(message)"
            case .writingFailed(let message): return "MP4 파일을 만들지 못했습니다: \(message)"
            }
        }
    }

    static func convert(_ sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let width = Int(abs(naturalSize.width))
        let height = Int(abs(naturalSize.height))
        guard width <= 4096, height <= 4096 else {
            throw ConversionError.unsupportedSize(width, height)
        }

        let outputURL = outputURL(for: sourceURL)
        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ConversionError.cannotConfigure }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 14_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ])
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = try await track.load(.preferredTransform)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput)
        guard writer.canAdd(writerInput) else { throw ConversionError.cannotConfigure }
        writer.add(writerInput)

        guard writer.startWriting(), reader.startReading() else {
            throw ConversionError.cannotConfigure
        }
        writer.startSession(atSourceTime: .zero)

        while reader.status == .reading, let sample = readerOutput.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            if !adaptor.append(imageBuffer, withPresentationTime: timestamp) {
                reader.cancelReading()
                writer.cancelWriting()
                throw ConversionError.writingFailed(writer.error?.localizedDescription ?? "알 수 없는 오류")
            }
        }

        guard reader.status == .completed else {
            writer.cancelWriting()
            throw ConversionError.readingFailed(reader.error?.localizedDescription ?? "알 수 없는 오류")
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ConversionError.writingFailed(writer.error?.localizedDescription ?? "알 수 없는 오류")
        }
        return outputURL
    }

    static func outputURL(for sourceURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let suffix = baseName.hasSuffix("-windows") ? "-converted" : "-windows"
        return sourceURL.deletingLastPathComponent()
            .appendingPathComponent(baseName + suffix)
            .appendingPathExtension("mp4")
    }
}
