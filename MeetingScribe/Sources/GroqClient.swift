import Foundation

enum GroqClient {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let chatEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    static let model = "whisper-large-v3"
    static let summaryModel = "openai/gpt-oss-120b"

    /// Groq's free tier allows 20 requests/min and 2000 requests/day for whisper-large-v3
    /// (confirmed via the x-ratelimit-* response headers on this account). A 30+ minute
    /// meeting chunked into 2-minute pieces is ~15 requests, comfortably under the per-minute
    /// cap on its own, but back-to-back sessions or a shared key can still trip 429s.
    static let maxRetriesPerChunk = 8
    static let baseRetryDelay: TimeInterval = 1

    /// language: ISO-639-1 code (e.g. "en", "es"), or nil to let Whisper auto-detect.
    /// chunkOffset: seconds to add to every segment timestamp so they read as absolute time in the full recording.
    static func transcribe(fileURL: URL, apiKey: String, language: String?, chunkOffset: Double) async throws -> ChunkResult {
        var attempt = 0
        while true {
            do {
                return try await transcribeOnce(fileURL: fileURL, apiKey: apiKey, language: language, chunkOffset: chunkOffset)
            } catch let error as RateLimitError {
                attempt += 1
                if attempt >= maxRetriesPerChunk {
                    throw TranscriptionError.rateLimited
                }
                let backoff = min(baseRetryDelay * pow(2, Double(attempt - 1)), 60)
                let jitter = Double.random(in: 0...(backoff * 0.25))
                let delay = error.retryAfter ?? (backoff + jitter)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private static func transcribeOnce(fileURL: URL, apiKey: String, language: String?, chunkOffset: Double) async throws -> ChunkResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", model)
        appendField("response_format", "verbose_json")
        appendField("temperature", "0")
        appendField("timestamp_granularities[]", "segment")
        if let language, !language.isEmpty {
            appendField("language", language)
        }

        let audioData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.apiError("No response from Groq.")
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            throw RateLimitError(retryAfter: retryAfter)
        }

        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(GroqErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "Request failed with status \(http.statusCode)."
            throw TranscriptionError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(GroqVerboseResponse.self, from: data)
        let segments = (decoded.segments ?? []).map { seg in
            TranscriptSegment(
                start: seg.start + chunkOffset,
                end: seg.end + chunkOffset,
                text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return ChunkResult(text: decoded.text, segments: segments, detectedLanguage: decoded.language)
    }

    /// Groq's on-demand tier caps gpt-oss-120b at 8000 tokens/minute — confirmed live via the
    /// x-ratelimit-limit-tokens response header, and it is a HARD per-minute ceiling across every
    /// request this key makes, not per-request. gpt-oss-120b also burns a hidden "reasoning" pass
    /// before its real answer (seen eating 500+ tokens on trivial prompts), so completions cost far
    /// more than they look like from the output alone. Rather than overlapping audio-style chunks
    /// (meant for continuity across a cut, not needed for text already in full), transcripts are
    /// split at segment boundaries into token-budgeted pieces, summarized independently (map), then
    /// merged into one final pass (reduce). Chunks are kept small and requests are paced with a
    /// delay between them so consecutive map-reduce calls don't stack inside the same rolling
    /// minute window and blow the shared TPM budget even though each one looks small alone.
    private static let charsPerTokenEstimate = 4.0
    private static let maxPromptTokens = 1200
    private static var maxPromptChars: Int { Int(Double(maxPromptTokens) * charsPerTokenEstimate) }
    private static let interChunkDelay: TimeInterval = 4
    private static let maxRetriesPerRequest = 8
    private static let summaryBaseRetryDelay: TimeInterval = 2

    static func summarize(transcript: String, style: SummaryStyle, apiKey: String) async throws -> String {
        try await summarize(segments: [transcript], style: style, apiKey: apiKey)
    }

    /// segments: transcript pieces in original order (e.g. one string per TranscriptSegment's text,
    /// or already-grouped chunks); callers don't need to pre-chunk, this does it by character budget.
    static func summarize(segments: [String], style: SummaryStyle, apiKey: String) async throws -> String {
        let chunks = chunkByBudget(segments)

        if chunks.count <= 1 {
            let text = chunks.first ?? ""
            return try await summarizeSingle(transcript: text, style: style, apiKey: apiKey, isPartial: false)
        }

        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            if index > 0 {
                try await Task.sleep(nanoseconds: UInt64(interChunkDelay * 1_000_000_000))
            }
            let partial = try await summarizeSingle(transcript: chunk, style: style, apiKey: apiKey, isPartial: true)
            partials.append(partial)
        }

        try await Task.sleep(nanoseconds: UInt64(interChunkDelay * 1_000_000_000))
        return try await mergePartialSummaries(partials, style: style, apiKey: apiKey)
    }

    /// Greedily packs transcript segments into chunks under the character budget, only ever
    /// splitting between segments (whole sentences from Whisper), never mid-sentence.
    private static func chunkByBudget(_ segments: [String]) -> [String] {
        var chunks: [String] = []
        var current = ""

        for segment in segments {
            let candidate = current.isEmpty ? segment : current + " " + segment
            if candidate.count > maxPromptChars && !current.isEmpty {
                chunks.append(current)
                current = segment
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func summarizeSingle(transcript: String, style: SummaryStyle, apiKey: String, isPartial: Bool) async throws -> String {
        let systemPrompt = """
        You summarize meeting transcripts into clean bullet points. Rules:
        - Never skip or soften a decision, action item, deadline, number, or name. Every concrete point in the transcript must appear somewhere in your summary.
        - Each bullet is short: one line, plain language, no filler.
        - Group related points under short headers only if the meeting clearly covered distinct topics; otherwise a flat list is fine.
        - Action items go in their own "Action Items" section at the end, each with the owner if mentioned.
        - Do not invent information that is not in the transcript.
        - Output plain text using "-" for bullets and "##" for section headers. No other formatting.
        """

        let partialNote = isPartial
            ? " This is one segment of a longer meeting; summarize only what's in this excerpt, don't assume context outside it."
            : ""

        let userPrompt: String
        switch style {
        case .short:
            userPrompt = "Summarize this transcript as a short, tight bullet list: the key points only, maximum brevity, but still capture every action item and decision.\(partialNote) Transcript:\n\n\(transcript)"
        case .comprehensive:
            userPrompt = "Summarize this transcript comprehensively: cover every important point, decision, number, and action item discussed, organized into clear bullets. Do not skip anything of substance, but keep each bullet concise.\(partialNote) Transcript:\n\n\(transcript)"
        }

        return try await chatCompletion(system: systemPrompt, user: userPrompt, apiKey: apiKey)
    }

    private static func mergePartialSummaries(_ partials: [String], style: SummaryStyle, apiKey: String) async throws -> String {
        let systemPrompt = """
        You merge several partial meeting summaries (each covering a different time range of the same meeting, in order) into one final summary. Rules:
        - Never drop a decision, action item, deadline, number, or name present in any partial summary.
        - Combine duplicate or closely related points into one bullet; do not list the same point twice.
        - Keep the same output format as the inputs: "-" bullets and "##" section headers, with a final "Action Items" section listing every action item from every part, each with its owner if mentioned.
        - Do not invent information not present in the partial summaries.
        """

        let numbered = partials.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n")
        let styleNote = style == .short
            ? "Keep the merged result short and tight overall."
            : "Keep the merged result comprehensive, covering everything from every part."
        let userPrompt = "Merge these partial summaries from the same meeting into one final summary. \(styleNote)\n\n\(numbered)"

        return try await chatCompletion(system: systemPrompt, user: userPrompt, apiKey: apiKey)
    }

    private static func chatCompletion(system: String, user: String, apiKey: String) async throws -> String {
        var attempt = 0
        while true {
            do {
                return try await chatCompletionOnce(system: system, user: user, apiKey: apiKey)
            } catch let error as RateLimitError {
                attempt += 1
                if attempt >= maxRetriesPerRequest {
                    throw TranscriptionError.rateLimited
                }
                let backoff = min(summaryBaseRetryDelay * pow(2, Double(attempt - 1)), 60)
                let jitter = Double.random(in: 0...(backoff * 0.25))
                let delay = error.retryAfter ?? (backoff + jitter)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private static func chatCompletionOnce(system: String, user: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = GroqChatRequest(
            model: summaryModel,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.apiError("No response from Groq.")
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            throw RateLimitError(retryAfter: retryAfter)
        }

        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(GroqErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "Summary request failed with status \(http.statusCode)."
            throw TranscriptionError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(GroqChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw TranscriptionError.apiError("Groq returned an empty summary.")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SummaryStyle: String, CaseIterable, Identifiable {
    case short = "Short"
    case comprehensive = "Comprehensive"
    var id: String { rawValue }
}

private struct GroqChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct GroqChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

struct ChunkResult {
    let text: String
    let segments: [TranscriptSegment]
    let detectedLanguage: String?
}

private struct GroqVerboseResponse: Decodable {
    let text: String
    let language: String?
    let segments: [GroqSegment]?
}

private struct GroqSegment: Decodable {
    let start: Double
    let end: Double
    let text: String
}

private struct GroqErrorResponse: Decodable {
    struct ErrorBody: Decodable { let message: String }
    let error: ErrorBody
}
