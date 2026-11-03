import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Summary and action items for a note, saved next to the transcript as <name>.summary.json.
struct NoteInsights: Codable, Hashable {
    struct Item: Codable, Hashable {
        var text: String
        var done = false
    }
    var summary: String
    var actionItems: [Item]
    /// Short name for the conversation, e.g. "Trip plans with Sam" (nil on notes made before titles existed)
    var title: String?
    /// One sentence for the list
    var overview: String?
    var category: NoteCategory?
}

/// What a conversation is about, so the list is easy to scan (like Omi's categories).
enum NoteCategory: String, Codable, CaseIterable, Identifiable {
    case work, meeting, study, personal, health, money, ideas, shopping, travel, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .work: return "briefcase"
        case .meeting: return "person.2"
        case .study: return "book"
        case .personal: return "heart"
        case .health: return "cross.case"
        case .money: return "indianrupeesign.circle"
        case .ideas: return "lightbulb"
        case .shopping: return "cart"
        case .travel: return "airplane"
        case .other: return "tag"
        }
    }

    /// Lenient match for what a small model writes ("Meeting.", "work stuff", …)
    init(loose text: String) {
        let t = text.lowercased()
        self = Self.allCases.first { t.contains($0.rawValue) } ?? .other
    }
}

/// Which model writes the summaries. All of them run on the phone; nothing is sent anywhere.
enum SummaryEngine: String, CaseIterable, Identifiable {
    case apple, qwenSmall
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .qwenSmall: return "Qwen3 0.6B (about 350 MB)"
        }
    }

    var isLocalDownload: Bool { self != .apple }

    /// The engine to use when the user hasn't picked one.
    static var preferred: SummaryEngine {
        Summarizer.unavailableReason(.apple) == nil ? .apple : .qwenSmall
    }
}

/// Makes summaries on the phone, with Apple's on-device model or a small open model (MLX).
enum Summarizer {
    enum Failure: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self { case .unavailable(let why): return why }
        }
    }

    /// nil when this engine can make summaries, otherwise a short reason to show the user.
    static func unavailableReason(_ engine: SummaryEngine) -> String? {
        switch engine {
        case .apple: return appleUnavailableReason
        case .qwenSmall:
            return LocalModel.isIncluded ? nil : "Local models aren't in this build of the app yet."
        }
    }

    private static var appleUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings, or pick a local model."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading. Summaries will appear when it's ready."
            case .unavailable(.deviceNotEligible):
                return "This iPhone can't run Apple Intelligence. Pick a local model instead."
            case .unavailable:
                return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "Apple Intelligence needs iOS 26 or later. Pick a local model instead."
    }

    /// `progress` reports the one-time model download (0...1) for local engines.
    static func summarize(_ transcript: String, engine: SummaryEngine,
                          progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> NoteInsights {
        if let why = unavailableReason(engine) { throw Failure.unavailable(why) }
        switch engine {
        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) { return try await OnDevice.summarize(transcript) }
            #endif
            throw Failure.unavailable(appleUnavailableReason ?? "")
        case .qwenSmall:
            return try await LocalModel.summarize(transcript, engine: engine, progress: progress)
        }
    }

    /// Trims quotes, "Title:" and a trailing period, and keeps it short.
    static func cleanTitle(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("title:") { t = String(t.dropFirst(6)) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " \"'*.#“”"))
        let words = t.split(separator: " ")
        if words.count > 8 { t = words.prefix(8).joined(separator: " ") }
        return t.isEmpty ? nil : t
    }

    /// Splits on sentence ends (or spaces) into pieces of at most `size` characters,
    /// so long notes fit in a small model's context.
    static func split(_ text: String, size: Int) -> [String] {
        var pieces: [String] = []
        var rest = Substring(text)
        while rest.count > size {
            let window = rest.prefix(size)
            let cut = window.lastIndex(where: { ".?!".contains($0) }).map { rest.index(after: $0) }
                ?? window.lastIndex(of: " ")
                ?? window.endIndex
            pieces.append(String(rest[..<cut]))
            rest = rest[cut...].drop(while: { $0 == " " })
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
enum GeneratedCategory: String {
    case work, meeting, study, personal, health, money, ideas, shopping, travel, other
}

@available(iOS 26.0, *)
@Generable
struct GeneratedSummary {
    @Guide(description: "A short title for the note, 2 to 6 words, like a headline. No quotes, no ending period.")
    var title: String
    @Guide(description: "One short sentence saying what the note is about.")
    var overview: String
    @Guide(description: "The best fitting category for the note.")
    var category: GeneratedCategory
    @Guide(description: "Two to four sentences saying what the note is about and the key points, in plain language.")
    var summary: String
    @Guide(description: "Every task, follow-up, reminder or fix the speaker needs to do, in the order mentioned, each a short imperative sentence. Empty if there are none.", .maximumCount(10))
    var actionItems: [String]
}

@available(iOS 26.0, *)
private enum OnDevice {
    static let instructions = """
    You summarize voice notes recorded on a wearable pendant. The text is an automatic transcript and may have \
    errors or missing punctuation. Lines may start with "Person 1:", "Person 2:" when several people talk. Only use what is in the transcript. Do not invent tasks, names or dates.
    """

    /// The on-device model has a small context window (about 4,000 tokens), so long notes are
    /// summarized in pieces and the pieces are then combined.
    static let pieceChars = 6_000

    static func summarize(_ transcript: String) async throws -> NoteInsights {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = Summarizer.split(text, size: pieceChars)
        let result: GeneratedSummary
        if pieces.count <= 1 {
            result = try await ask("Summarize this voice note.\n\nTranscript:\n\(text)")
        } else {
            var parts: [GeneratedSummary] = []
            for (i, piece) in pieces.enumerated() {
                parts.append(try await ask("This is part \(i + 1) of \(pieces.count) of a long voice note. Summarize this part.\n\nTranscript:\n\(piece)"))
            }
            let combined = parts.enumerated().map { i, p in
                "Part \(i + 1): \(p.summary)\nTasks: \(p.actionItems.joined(separator: "; "))"
            }.joined(separator: "\n\n")
            result = try await ask("These are summaries of the parts of one long voice note. Write a title, overview and category for the whole note, one summary of the whole note and one list of its tasks, without duplicates.\n\n\(combined)")
        }
        return NoteInsights(
            summary: result.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            actionItems: result.actionItems
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { NoteInsights.Item(text: $0) },
            title: Summarizer.cleanTitle(result.title),
            overview: result.overview.trimmingCharacters(in: .whitespacesAndNewlines),
            category: NoteCategory(rawValue: result.category.rawValue) ?? .other)
    }

    private static func ask(_ prompt: String) async throws -> GeneratedSummary {
        // A fresh session each time so earlier pieces don't fill up the context window
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt, generating: GeneratedSummary.self,
                                         options: GenerationOptions(temperature: 0.2)).content
    }
}
#endif
