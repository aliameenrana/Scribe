import Foundation

struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
    var text: String

    var timeLabel: String {
        TranscriptSegment.formatTime(start)
    }

    static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct TranscriptLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    var code: String? { id.isEmpty ? nil : id }
}

enum SupportedLanguages {
    static let all: [TranscriptLanguage] = [
        TranscriptLanguage(id: "", name: "Auto-detect"),
        TranscriptLanguage(id: "en", name: "English"),
        TranscriptLanguage(id: "es", name: "Spanish"),
        TranscriptLanguage(id: "fr", name: "French"),
        TranscriptLanguage(id: "de", name: "German"),
        TranscriptLanguage(id: "it", name: "Italian"),
        TranscriptLanguage(id: "pt", name: "Portuguese"),
        TranscriptLanguage(id: "nl", name: "Dutch"),
        TranscriptLanguage(id: "ru", name: "Russian"),
        TranscriptLanguage(id: "zh", name: "Chinese"),
        TranscriptLanguage(id: "ja", name: "Japanese"),
        TranscriptLanguage(id: "ko", name: "Korean"),
        TranscriptLanguage(id: "ar", name: "Arabic"),
        TranscriptLanguage(id: "hi", name: "Hindi"),
        TranscriptLanguage(id: "ur", name: "Urdu"),
        TranscriptLanguage(id: "tr", name: "Turkish"),
        TranscriptLanguage(id: "pl", name: "Polish"),
        TranscriptLanguage(id: "sv", name: "Swedish"),
        TranscriptLanguage(id: "id", name: "Indonesian"),
        TranscriptLanguage(id: "vi", name: "Vietnamese")
    ]
}
