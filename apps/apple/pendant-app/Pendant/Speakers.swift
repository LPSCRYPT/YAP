import AVFoundation
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif
#if canImport(Speech)
import Speech
#endif

/// A piece of transcript text with where it is in the audio (seconds from the start; -1 = unknown).
struct TimedText: Codable, Hashable {
    var text: String
    var start: Double
    var end: Double
}

/// One person talking from `start` to `end` (seconds). Slots come from the model, numbered from 0.
struct SpeakerTurn: Codable, Hashable {
    let speaker: Int
    let start: Double
    let end: Double
}

/// One line of a transcript: who said it (nil when we can't tell) and what they said.
struct SpeakerLine: Identifiable, Hashable {
    let id: Int
    let speaker: Int?   // Person 1, 2, 3… in the order people first speak
    var text: String
    /// Seconds into the recording where the line starts (-1 = unknown)
    var start: Double = -1
}

/// "Who's speaking", on the phone. Uses NVIDIA's Sortformer model through FluidAudio
/// (Core ML, runs on the Neural Engine). Up to 4 voices per conversation. The model downloads once
/// from Hugging Face; audio never leaves the phone.
enum Speakers {
    #if canImport(FluidAudio)
    static let isIncluded = true
    #else
    static let isIncluded = false
    #endif

    static func name(_ n: Int) -> String { "Person \(n)" }

    /// Who spoke when in a saved recording. Reads the file a minute at a time.
    /// nil if the model isn't available (not downloaded yet and no internet).
    /// `onPartial` gets who-spoke-when so far after every 30 s of audio, so bubbles can show while it works.
    static func turns(for url: URL, onPartial: (@Sendable ([SpeakerTurn]) -> Void)? = nil) async -> [SpeakerTurn]? {
        #if canImport(FluidAudio)
        // The faster "efficient" model for files (about 4x the speed); the live one if that can't load
        var config = SpeakerModels.fileConfig
        var loaded = try? await SpeakerModels.shared.load(forFiles: true)
        if loaded == nil { config = SpeakerModels.config; loaded = try? await SpeakerModels.shared.load() }
        guard let models = loaded else { return nil }
        return try? await Task.detached(priority: .userInitiated) {
            let diarizer = SortformerDiarizer(config: config)
            diarizer.initialize(models: models)
            let file = try AVAudioFile(forReading: url)
            let rate = file.processingFormat.sampleRate
            let chunk = AVAudioFrameCount(rate * 30)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return [] }
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try file.read(into: buf, frameCount: chunk)
                guard buf.frameLength > 0, let s = buf.floatChannelData?[0] else { break }
                let samples = Array(UnsafeBufferPointer(start: s, count: Int(buf.frameLength)))
                _ = try diarizer.process(samples: samples, sourceSampleRate: rate)
                onPartial?(turns(from: diarizer.timeline))
            }
            _ = try diarizer.finalizeSession()
            return turns(from: diarizer.timeline)
        }.value
        #else
        return nil
        #endif
    }

    #if canImport(FluidAudio)
    static func turns(from timeline: DiarizerTimeline) -> [SpeakerTurn] {
        timeline.speakers.values.flatMap { s in
            (s.finalizedSegments + s.tentativeSegments).map {
                SpeakerTurn(speaker: s.index, start: Double($0.startTime), end: Double($0.endTime))
            }
        }
        .sorted { $0.start < $1.start }
    }
    #endif

    /// Groups transcript pieces into lines by speaker. `results` is one list of pieces per
    /// recognized phrase; pieces inside a phrase are joined as-is, phrases with a space.
    /// Names are shown only when at least `minPeople` voices were found.
    static func lines(_ results: [[TimedText]], turns: [SpeakerTurn], minPeople: Int = 2) -> [SpeakerLine] {
        var numbers: [Int: Int] = [:]   // model's speaker slot -> 1, 2, 3 in order of appearance
        var lines: [SpeakerLine] = []
        var current: Int?
        for pieces in results {
            var first = true
            for piece in pieces {
                var who = current
                if let slot = speaker(at: (piece.start + piece.end) / 2, turns) {
                    if let n = numbers[slot] { who = n } else { who = numbers.count + 1; numbers[slot] = who }
                }
                let text = first ? piece.text.trimmingCharacters(in: .whitespaces) : piece.text
                if lines.isEmpty || who != current {
                    lines.append(SpeakerLine(id: lines.count, speaker: who, text: text, start: piece.start))
                    current = who
                } else {
                    lines[lines.count - 1].text += (first ? " " : "") + text
                }
                first = false
            }
        }
        let people = Set(lines.compactMap(\.speaker))
        if people.count < max(1, minPeople) {
            let all = lines.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            // minPeople 1: no separate voices found, so it's all one person (still shown as a bubble)
            return all.isEmpty ? [] : [SpeakerLine(id: 0, speaker: minPeople <= 1 ? 1 : nil, text: all, start: lines.first?.start ?? -1)]
        }
        return lines.map { SpeakerLine(id: $0.id, speaker: $0.speaker, text: $0.text.trimmingCharacters(in: .whitespaces), start: $0.start) }
            .filter { !$0.text.isEmpty }
    }

    /// Model slot for each person number (Person 1, 2…), numbered like `lines` does.
    static func slots(_ results: [[TimedText]], turns: [SpeakerTurn]) -> [Int: Int] {
        var numbers: [Int: Int] = [:]
        for pieces in results {
            for piece in pieces {
                if let slot = speaker(at: (piece.start + piece.end) / 2, turns), numbers[slot] == nil {
                    numbers[slot] = numbers.count + 1
                }
            }
        }
        return Dictionary(uniqueKeysWithValues: numbers.map { ($0.value, $0.key) })
    }

    /// Seconds each Person N talked.
    static func talkTime(_ results: [[TimedText]], turns: [SpeakerTurn]) -> [(person: Int, seconds: Double)] {
        slots(results, turns: turns).map { n, slot in
            (n, turns.filter { $0.speaker == slot }.reduce(0) { $0 + max(0, $1.end - $1.start) })
        }
        .filter { $0.1 >= 1 }
        .sorted { $0.0 < $1.0 }
    }

    /// Transcript text saved to disk: "Person 1: …" lines, or plain text for one voice.
    static func text(_ lines: [SpeakerLine]) -> String {
        lines.map { l in l.speaker.map { "\(name($0)): \(l.text)" } ?? l.text }.joined(separator: "\n")
    }

    /// Reads a saved transcript back into lines ("Person 2: hello" -> 2, "hello").
    /// Also reads the older "Speaker 2:" form.
    static func parse(_ text: String) -> [SpeakerLine] {
        text.split(separator: "\n", omittingEmptySubsequences: true).enumerated().map { i, raw in
            let line = String(raw)
            for prefix in ["Person ", "Speaker "] where line.hasPrefix(prefix) {
                if let colon = line.firstIndex(of: ":"),
                   let n = Int(line[line.index(line.startIndex, offsetBy: prefix.count)..<colon]) {
                    return SpeakerLine(id: i, speaker: n, text: line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                }
            }
            return SpeakerLine(id: i, speaker: nil, text: line)
        }
    }

    /// The words only, without "Person N:" names (to compare two versions of a transcript).
    static func words(_ text: String) -> String {
        parse(text).map(\.text).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Keeps the phrases and turns between `from` and `to` seconds, with times moved to start at 0.
    static func slice(_ phrases: [[TimedText]], _ turns: [SpeakerTurn], from: Double, to: Double)
        -> (phrases: [[TimedText]], turns: [SpeakerTurn]) {
        let p = phrases.filter { ph in
            guard let t = ph.first?.start else { return false }
            return t >= from - 0.5 && t < to
        }.map { $0.map { TimedText(text: $0.text, start: $0.start - from, end: $0.end - from) } }
        let t = turns.filter { $0.end > from && $0.start < to }
            .map { SpeakerTurn(speaker: $0.speaker, start: max(0, $0.start - from), end: $0.end - from) }
        return (p, t)
    }

    /// The speaker talking at time t, or the nearest one within half a second.
    private static func speaker(at t: Double, _ turns: [SpeakerTurn]) -> Int? {
        guard t >= 0 else { return nil }
        if let hit = turns.first(where: { $0.start <= t && t <= $0.end }) { return hit.speaker }
        let near = turns.min { distance(t, $0) < distance(t, $1) }
        if let near, distance(t, near) <= 0.5 { return near.speaker }
        return nil
    }

    private static func distance(_ t: Double, _ turn: SpeakerTurn) -> Double {
        t < turn.start ? turn.start - t : max(0, t - turn.end)
    }

    #if compiler(>=6.2)
    /// Splits a recognized phrase into timed pieces using the word times SpeechAnalyzer attaches.
    @available(iOS 26.0, *)
    static func pieces(of text: AttributedString, phrase: CMTimeRange) -> [TimedText] {
        var out: [TimedText] = []
        for run in text.runs {
            let s = String(text[run.range].characters)
            if let r = run.audioTimeRange, r.start.isNumeric, r.end.isNumeric {
                out.append(TimedText(text: s, start: r.start.seconds, end: r.end.seconds))
            } else if !out.isEmpty {
                out[out.count - 1].text += s   // spaces and punctuation carry no time
            } else {
                let a = phrase.start.isNumeric ? phrase.start.seconds : -1
                let b = phrase.end.isNumeric ? phrase.end.seconds : a
                out.append(TimedText(text: s, start: a, end: b))
            }
        }
        return out
    }
    #endif
}

#if canImport(FluidAudio)
/// Loads the speaker model once and keeps it while the app runs.
actor SpeakerModels {
    static let shared = SpeakerModels()
    /// ~1 s delay when live, good accuracy (about 20% error on hard meeting audio).
    static let config = SortformerConfig.balancedV2_1
    /// Saved recordings: same accuracy family, bigger steps, about 4x faster than the live one.
    static let fileConfig = SortformerConfig.efficientV2_1
    private var models: [Bool: SortformerModels] = [:]
    private var loading: [Bool: Task<SortformerModels, Error>] = [:]

    func load(forFiles: Bool = false) async throws -> SortformerModels {
        if let m = models[forFiles] { return m }
        if let t = loading[forFiles] { return try await t.value }   // one download shared by everyone
        let config = forFiles ? Self.fileConfig : Self.config
        let task = Task { try await SortformerModels.loadFromHuggingFace(config: config) }
        loading[forFiles] = task
        defer { loading[forFiles] = nil }
        let m = try await task.value
        models[forFiles] = m
        return m
    }
}

/// Live "who's speaking" for the live transcript. Runs the model off the main thread.
final class LiveDiarizer {
    /// All called on the main thread.
    var onTurns: (([SpeakerTurn]) -> Void)?
    var onReady: ((Bool) -> Void)?      // model loaded (true) or couldn't load (false)
    var onDone: (() -> Void)?           // last turns delivered after finish()

    private let queue = DispatchQueue(label: "pendant.live-speakers", qos: .userInitiated)
    private var diarizer: SortformerDiarizer?
    private var waiting: [Float] = []   // audio that came in while the model loads
    private var finished = false
    private var failed = false

    init() {
        Task { [weak self] in
            let models = try? await SpeakerModels.shared.load()
            self?.queue.async {
                guard let self else { return }
                guard let models else {
                    self.failed = true
                    self.waiting = []
                    let done = self.finished
                    DispatchQueue.main.async { self.onReady?(false); if done { self.onDone?() } }
                    return
                }
                let d = SortformerDiarizer(config: SpeakerModels.config)
                d.initialize(models: models)
                self.diarizer = d
                let early = self.waiting
                self.waiting = []
                if !early.isEmpty { _ = try? d.process(samples: early) }
                DispatchQueue.main.async { self.onReady?(true) }
                if self.finished { _ = try? d.finalizeSession() }
                self.publish(d, done: self.finished)
            }
        }
    }

    /// 16 kHz mono samples, in order.
    func append(_ samples: [Float]) {
        queue.async {
            guard !self.failed else { return }
            guard let d = self.diarizer else { self.waiting += samples; return }
            if (try? d.process(samples: samples)) != nil { self.publish(d, done: false) }
        }
    }

    func finish() {
        queue.async {
            self.finished = true
            if self.failed { DispatchQueue.main.async { self.onDone?() }; return }
            guard let d = self.diarizer else { return }   // still loading: init finishes up
            _ = try? d.finalizeSession()
            self.publish(d, done: true)
        }
    }

    private func publish(_ d: SortformerDiarizer, done: Bool) {
        let turns = Speakers.turns(from: d.timeline)
        DispatchQueue.main.async {
            self.onTurns?(turns)
            if done { self.onDone?() }
        }
    }
}
#endif
