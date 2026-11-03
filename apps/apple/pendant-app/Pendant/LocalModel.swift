import Foundation
#if canImport(MLXLLM)
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

/// Summaries with a small open model (Qwen3) running on the phone's GPU through Apple's MLX.
/// Works on any iPhone, with or without Apple Intelligence. The model downloads once
/// from Hugging Face the first time it's used; after that everything stays on the phone.
enum LocalModel {
    #if canImport(MLXLLM)
    static let isIncluded = true
    #else
    static let isIncluded = false
    #endif

    /// Tested on Qwen3 0.6B: the example is what makes it list tasks instead of folding them into the summary.
    static let instructions = """
    You turn voice note transcripts into a short summary and a to-do list. Only use what is in the transcript. Do not invent anything.

    Reply in exactly this format:
    TITLE: <2 to 6 words>
    CATEGORY: <one of: work, meeting, study, personal, health, money, ideas, shopping, travel, other>
    OVERVIEW: <one short sentence>
    SUMMARY: <two to four sentences>
    TASKS:
    - <one task per line>

    A task is only a clear commitment: someone says they will do, must do, or are asked to do something specific. Ideas, opinions, plans being discussed, past events and small talk are not tasks. Most conversations have no tasks: then write "TASKS: none".

    Example 1
    Transcript: We had lunch and talked about movies. Sam liked the new one, I thought it was too long.
    TITLE: Lunch and movie talk
    CATEGORY: personal
    OVERVIEW: Sam and I talked about movies over lunch.
    SUMMARY: Over lunch we talked about the new movie. Sam liked it and I found it too long.
    TASKS: none

    Example 2
    Transcript: Talked to Sam about the launch. It moves to May. I need to update the website and email the beta users tomorrow.
    TITLE: Launch moved to May
    CATEGORY: work
    OVERVIEW: Sam and I moved the launch to May.
    SUMMARY: The launch moves to May after a talk with Sam.
    TASKS:
    - Update the website.
    - Email the beta users tomorrow.
    """

    /// Keeps each request well inside what a small model handles well.
    static let pieceChars = 6_000

    static func summarize(_ transcript: String, engine: SummaryEngine,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> NoteInsights {
        #if canImport(MLXLLM)
        let model = try await Loader.shared.load(engine, progress: progress)
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = Summarizer.split(text, size: pieceChars)
        if pieces.count <= 1 {
            return parse(try await ask(model, "Transcript:\n\(text)"))
        }
        var parts: [NoteInsights] = []
        for (i, piece) in pieces.enumerated() {
            parts.append(parse(try await ask(model, "This is part \(i + 1) of \(pieces.count) of a long note.\n\nTranscript:\n\(piece)")))
        }
        let combined = parts.enumerated().map { i, p in
            "Part \(i + 1): \(p.summary)\nTasks: \(p.actionItems.map(\.text).joined(separator: "; "))"
        }.joined(separator: "\n\n")
        return parse(try await ask(model, "These are summaries of the parts of one long voice note. Write a title, category and overview for the whole note, one summary of the whole note and one list of its tasks, without duplicates.\n\n\(combined)"))
        #else
        throw Summarizer.Failure.unavailable(Summarizer.unavailableReason(engine) ?? "")
        #endif
    }

    /// Downloads (and loads) the model ahead of time, from Settings → Models.
    static func preload() async throws {
        #if canImport(MLXLLM)
        _ = try await Loader.shared.load(.qwenSmall) { _ in }
        #endif
    }

    /// Reads the SUMMARY / TASKS reply. Lenient, since small models drift from the format.
    static func parse(_ reply: String) -> NoteInsights {
        var text = reply
        // Drop any <think>…</think> block if the model reasoned anyway
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
        var summary: [String] = []
        var tasks: [String] = []
        var title: String?, overview: String?, category: NoteCategory?
        var inTasks = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE:") {
                title = Summarizer.cleanTitle(String(line.dropFirst(6)))
            } else if upper.hasPrefix("CATEGORY:") {
                category = NoteCategory(loose: String(line.dropFirst(9)))
            } else if upper.hasPrefix("OVERVIEW:") {
                overview = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("SUMMARY:") {
                inTasks = false
                summary.append(String(line.dropFirst("SUMMARY:".count)))
            } else if upper.hasPrefix("TASKS:") || upper.hasPrefix("ACTION ITEMS:") {
                inTasks = true
            } else if inTasks, let bullet = line.range(of: #"^([-*•]|\d+[.)])\s*"#, options: .regularExpression) {
                tasks.append(String(line[bullet.upperBound...]))
            } else if !inTasks, !line.isEmpty {
                summary.append(line)
            }
        }
        return NoteInsights(
            summary: summary.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            actionItems: tasks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "none" }
                .map { NoteInsights.Item(text: $0) },
            title: title,
            overview: overview.flatMap { $0.isEmpty ? nil : $0 },
            category: category ?? (title == nil ? nil : .other))
    }

    #if canImport(MLXLLM)
    private static func ask(_ model: ModelContainer, _ prompt: String) async throws -> String {
        // A fresh session each time so earlier pieces don't fill up the context
        let session = ChatSession(
            model, instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: 600, temperature: 0.2),
            additionalContext: ["enable_thinking": false])
        return try await session.respond(to: prompt)
    }

    /// Loads a model once and keeps it in memory while the app runs.
    private actor Loader {
        static let shared = Loader()
        private var loaded: (SummaryEngine, ModelContainer)?

        func load(_ engine: SummaryEngine, progress: @escaping @Sendable (Double) -> Void) async throws -> ModelContainer {
            if let loaded, loaded.0 == engine { return loaded.1 }
            loaded = nil  // free the other model first
            let config = LLMRegistry.qwen3_0_6b_4bit
            let container = try await #huggingFaceLoadModelContainer(configuration: config) { p in
                progress(p.fractionCompleted)
            }
            loaded = (engine, container)
            return container
        }
    }
    #endif
}
