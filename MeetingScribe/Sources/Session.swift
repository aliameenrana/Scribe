import Foundation

struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceName: String
    var createdAt: Date
    var durationSeconds: Double

    var originalSegments: [SavedSegment]
    var editedSegments: [SavedSegment]

    var summary: String
    var summaryStyle: String
    var detectedLanguageLabel: String?

    var audioFileName: String?

    struct SavedSegment: Codable, Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    var editedTranscript: String {
        editedSegments.map(\.text).joined(separator: " ")
    }

    var originalTranscript: String {
        originalSegments.map(\.text).joined(separator: " ")
    }

    var wasEdited: Bool {
        originalSegments.map(\.text) != editedSegments.map(\.text)
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let sessionsDirectory: URL
    private let indexURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scribe", isDirectory: true)
        sessionsDirectory = base.appendingPathComponent("Sessions", isDirectory: true)
        indexURL = base.appendingPathComponent("sessions.json")
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Session].self, from: data) else {
            return
        }
        sessions = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func audioURL(for session: Session) -> URL? {
        guard let name = session.audioFileName else { return nil }
        let url = sessionsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func save(
        sourceName: String,
        durationSeconds: Double,
        originalSegments: [TranscriptSegment],
        editedSegments: [TranscriptSegment],
        summary: String,
        summaryStyle: SummaryStyle,
        detectedLanguageLabel: String?,
        sourceAudioURL: URL?
    ) -> Session {
        let id = UUID()
        var audioFileName: String?

        if let sourceAudioURL {
            let ext = sourceAudioURL.pathExtension.isEmpty ? "m4a" : sourceAudioURL.pathExtension
            let destName = "\(id.uuidString).\(ext)"
            let destURL = sessionsDirectory.appendingPathComponent(destName)
            if (try? FileManager.default.copyItem(at: sourceAudioURL, to: destURL)) != nil {
                audioFileName = destName
            }
        }

        let session = Session(
            id: id,
            sourceName: sourceName,
            createdAt: Date(),
            durationSeconds: durationSeconds,
            originalSegments: originalSegments.map { Session.SavedSegment(start: $0.start, end: $0.end, text: $0.text) },
            editedSegments: editedSegments.map { Session.SavedSegment(start: $0.start, end: $0.end, text: $0.text) },
            summary: summary,
            summaryStyle: summaryStyle.rawValue,
            detectedLanguageLabel: detectedLanguageLabel,
            audioFileName: audioFileName
        )

        sessions.insert(session, at: 0)
        persistIndex()
        return session
    }

    func update(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        persistIndex()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        if let name = session.audioFileName {
            try? FileManager.default.removeItem(at: sessionsDirectory.appendingPathComponent(name))
        }
        persistIndex()
    }
}
