import Foundation

/// Minimal parser for the "##" header / "-" bullet markdown shape the summarization
/// prompt asks Groq to produce. Not a general markdown parser — just enough structure
/// to render the summary with real visual hierarchy instead of raw text with literal "##".
enum SummaryMarkdown {
    enum Block: Identifiable {
        case header(String)
        case bullet(String)
        case paragraph(String)

        var id: String {
            switch self {
            case .header(let text): return "h_\(text)"
            case .bullet(let text): return "b_\(text)"
            case .paragraph(let text): return "p_\(text)"
            }
        }
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("## ") {
                blocks.append(.header(String(line.dropFirst(3))))
            } else if line.hasPrefix("##") {
                blocks.append(.header(line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                blocks.append(.paragraph(line))
            }
        }

        return blocks
    }
}
