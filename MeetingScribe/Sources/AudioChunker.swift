import Foundation
import AVFoundation

struct AudioChunk {
    let url: URL
    let startOffset: Double
    let endOffset: Double
}

enum AudioChunker {
    static let chunkDuration: Double = 120

    static func chunk(fileURL: URL) throws -> [AudioChunk] {
        let asset = AVURLAsset(url: fileURL)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            throw TranscriptionError.invalidAudio
        }

        var chunks: [AudioChunk] = []
        var start: Double = 0
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var index = 0
        while start < duration {
            let end = min(start + chunkDuration, duration)
            let outURL = tempDir.appendingPathComponent("chunk_\(index).m4a")
            try exportChunk(asset: asset, start: start, end: end, to: outURL)
            chunks.append(AudioChunk(url: outURL, startOffset: start, endOffset: end))
            start = end
            index += 1
        }
        return chunks
    }

    private static func exportChunk(asset: AVURLAsset, start: Double, end: Double, to outURL: URL) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.exportFailed
        }
        exporter.outputURL = outURL
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        exporter.exportAsynchronously {
            if let error = exporter.error {
                exportError = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let exportError {
            throw exportError
        }
    }
}

enum TranscriptionError: LocalizedError {
    case invalidAudio
    case exportFailed
    case apiError(String)
    case missingAPIKey
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidAudio: return "This audio file could not be read."
        case .exportFailed: return "Could not prepare the audio for transcription."
        case .apiError(let message): return message
        case .missingAPIKey: return "No Groq API key is set."
        case .rateLimited: return "Groq's rate limit kept blocking requests after 8 retries. Scribe will automatically resume in about an hour."
        }
    }
}

struct RateLimitError: Error {
    let retryAfter: Double?
}
