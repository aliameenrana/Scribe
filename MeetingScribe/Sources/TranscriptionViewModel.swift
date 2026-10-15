import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var isProcessing = false
    @Published var progressText: String = ""
    @Published var totalChunks: Int = 0
    @Published var completedChunks: Int = 0
    @Published var errorMessage: String?
    @Published var sourceName: String = ""
    @Published var selectedLanguage: String = ""
    @Published var detectedLanguageLabel: String?

    @Published var summary: String = ""
    @Published var isSummarizing = false
    @Published var summaryError: String?
    @Published var summaryStyle: SummaryStyle = .short

    @Published var isWaitingToResume = false
    @Published var resumeAt: Date?

    private(set) var playableAudioURL: URL?
    private var originalSegments: [TranscriptSegment] = []
    private(set) var currentSessionID: UUID?

    private var pendingChunks: [AudioChunk] = []
    private var pendingLanguageCode: String?
    private var pendingSummaryStyle: SummaryStyle = .short
    private var pendingDetectedLanguage: String?
    private var resumeTask: Task<Void, Never>?

    static let resumeDelay: TimeInterval = 3600

    weak var history: HistoryStore?

    var transcript: String {
        segments.map(\.text).joined(separator: " ")
    }

    var hasResult: Bool { !segments.isEmpty }

    func process(fileURL: URL) {
        guard !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        segments = []
        originalSegments = []
        detectedLanguageLabel = nil
        sourceName = fileURL.lastPathComponent
        progressText = "Preparing audio…"
        totalChunks = 0
        completedChunks = 0
        playableAudioURL = nil
        summary = ""
        summaryError = nil
        currentSessionID = nil
        isWaitingToResume = false
        resumeAt = nil
        resumeTask?.cancel()

        pendingLanguageCode = selectedLanguage.isEmpty ? nil : selectedLanguage
        pendingSummaryStyle = summaryStyle
        pendingDetectedLanguage = nil

        Task {
            do {
                guard let apiKey = KeychainStore.load(), !apiKey.isEmpty else {
                    throw TranscriptionError.missingAPIKey
                }

                let needsAccess = fileURL.startAccessingSecurityScopedResource()
                defer { if needsAccess { fileURL.stopAccessingSecurityScopedResource() } }

                // Copy locally so we can keep playing it back after the security-scoped handle closes.
                let localCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + fileURL.lastPathComponent)
                try? FileManager.default.removeItem(at: localCopy)
                try FileManager.default.copyItem(at: fileURL, to: localCopy)
                playableAudioURL = localCopy

                let chunks = try AudioChunker.chunk(fileURL: localCopy)
                totalChunks = chunks.count
                pendingChunks = chunks

                try await runChunks(apiKey: apiKey)
            } catch {
                errorMessage = error.localizedDescription
                progressText = ""
                isProcessing = false
            }
        }
    }

    /// Transcribes whatever remains in `pendingChunks`, continuing from `segments`/`completedChunks`
    /// so a rate-limit pause can resume later without redoing already-transcribed audio.
    private func runChunks(apiKey: String) async throws {
        var allSegments = segments

        while !pendingChunks.isEmpty {
            let chunk = pendingChunks[0]
            progressText = "Transcribing part \(completedChunks + 1) of \(totalChunks)…"

            do {
                let result = try await GroqClient.transcribe(
                    fileURL: chunk.url,
                    apiKey: apiKey,
                    language: pendingLanguageCode,
                    chunkOffset: chunk.startOffset
                )
                if pendingDetectedLanguage == nil {
                    pendingDetectedLanguage = result.detectedLanguage
                }
                allSegments.append(contentsOf: result.segments)
                completedChunks += 1
                segments = allSegments
                pendingChunks.removeFirst()
            } catch TranscriptionError.rateLimited {
                scheduleResume(apiKey: apiKey)
                return
            }
        }

        if let pendingDetectedLanguage {
            detectedLanguageLabel = SupportedLanguages.all.first {
                $0.id.lowercased() == pendingDetectedLanguage.lowercased()
            }?.name ?? pendingDetectedLanguage.capitalized
        }

        if let firstChunkDir = pendingChunks.first?.url.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: firstChunkDir)
        }

        originalSegments = allSegments
        progressText = "Done"
        isProcessing = false
        isWaitingToResume = false
        resumeAt = nil

        summarizeAndSave(style: pendingSummaryStyle, apiKey: apiKey)
    }

    private func scheduleResume(apiKey: String) {
        isWaitingToResume = true
        let fireDate = Date().addingTimeInterval(Self.resumeDelay)
        resumeAt = fireDate
        progressText = "Rate limited by Groq. Resuming automatically at \(Self.timeFormatter.string(from: fireDate))…"

        resumeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.resumeDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            do {
                try await runChunks(apiKey: apiKey)
            } catch {
                errorMessage = error.localizedDescription
                progressText = ""
                isProcessing = false
                isWaitingToResume = false
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func summarizeAndSave(style: SummaryStyle, apiKey: String) {
        guard !segments.isEmpty else { return }
        isSummarizing = true
        summaryError = nil
        let segmentTexts = segments.map(\.text)

        Task {
            do {
                let result = try await GroqClient.summarize(segments: segmentTexts, style: style, apiKey: apiKey)
                summary = result
                isSummarizing = false
                saveToHistory()
            } catch {
                summaryError = error.localizedDescription
                isSummarizing = false
                saveToHistory()
            }
        }
    }

    func summarize() {
        guard !segments.isEmpty, !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil
        let segmentTexts = segments.map(\.text)
        let style = summaryStyle

        Task {
            do {
                guard let apiKey = KeychainStore.load(), !apiKey.isEmpty else {
                    throw TranscriptionError.missingAPIKey
                }
                let result = try await GroqClient.summarize(segments: segmentTexts, style: style, apiKey: apiKey)
                summary = result
                isSummarizing = false
                saveToHistory()
            } catch {
                summaryError = error.localizedDescription
                isSummarizing = false
            }
        }
    }

    func setSummaryStyle(_ style: SummaryStyle) {
        guard style != summaryStyle else { return }
        summaryStyle = style
        summarize()
    }

    func updateSegment(_ id: UUID, text: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].text = text
        saveToHistory()
    }

    func deleteSegment(_ id: UUID) {
        segments.removeAll { $0.id == id }
        saveToHistory()
    }

    private func saveToHistory() {
        guard let history, !segments.isEmpty else { return }

        if let sessionID = currentSessionID,
           let existing = history.sessions.first(where: { $0.id == sessionID }) {
            var updated = existing
            updated.editedSegments = segments.map { Session.SavedSegment(start: $0.start, end: $0.end, text: $0.text) }
            updated.summary = summary
            updated.summaryStyle = summaryStyle.rawValue
            history.update(updated)
        } else {
            let saved = history.save(
                sourceName: sourceName,
                durationSeconds: segments.last?.end ?? 0,
                originalSegments: originalSegments,
                editedSegments: segments,
                summary: summary,
                summaryStyle: summaryStyle,
                detectedLanguageLabel: detectedLanguageLabel,
                sourceAudioURL: playableAudioURL
            )
            currentSessionID = saved.id
        }
    }

    func loadFromHistory(_ session: Session) {
        isProcessing = false
        errorMessage = nil
        currentSessionID = session.id
        sourceName = session.sourceName
        detectedLanguageLabel = session.detectedLanguageLabel
        summary = session.summary
        summaryStyle = SummaryStyle(rawValue: session.summaryStyle) ?? .short
        summaryError = session.summary.isEmpty ? "Summarization didn't complete for this session." : nil
        isSummarizing = false

        originalSegments = session.originalSegments.map {
            TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
        }
        segments = session.editedSegments.map {
            TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
        }

        playableAudioURL = history?.audioURL(for: session)
    }

    func reset() {
        resumeTask?.cancel()
        resumeTask = nil
        pendingChunks = []
        segments = []
        originalSegments = []
        errorMessage = nil
        progressText = ""
        totalChunks = 0
        completedChunks = 0
        sourceName = ""
        detectedLanguageLabel = nil
        playableAudioURL = nil
        summary = ""
        summaryError = nil
        isSummarizing = false
        currentSessionID = nil
        isWaitingToResume = false
        resumeAt = nil
    }
}
