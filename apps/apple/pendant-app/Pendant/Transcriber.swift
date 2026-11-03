import AVFoundation
import Foundation
import Speech
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Free transcription on the phone. Audio never leaves the phone.
/// Long recordings are cut into ~1 minute pieces at quiet moments (so no word is cut in half),
/// and each piece is transcribed on its own. That keeps memory low and shows progress.
/// Which engine, best first (same order Omi uses):
///   1. iOS 26+: Apple's SpeechAnalyzer, with word times (used for "who's speaking").
///   2. iOS 17-25, English: NVIDIA Parakeet TDT v2 on the Neural Engine, through FluidAudio.
///      Downloads once (~450 MB); very accurate, with word times.
///   3. Anything else: Apple's classic recognizer (on-device where the phone supports it).
enum Transcriber {
    enum Failure: LocalizedError {
        case notAllowed, unavailable
        var errorDescription: String? {
            switch self {
            case .notAllowed: return "Allow Speech Recognition for Pendant in Settings."
            case .unavailable: return "Speech recognition isn't available for your language on this device."
            }
        }
    }

    /// The language picked in Settings, or the phone's.
    static var preferredLocale: Locale {
        let id = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? ""
        return id.isEmpty ? Locale.current : Locale(identifier: id)
    }

    /// Target piece length. Each cut moves back up to `searchSeconds` to land in a pause.
    static let pieceSeconds = 30.0
    static let searchSeconds = 8.0

    /// The transcript as phrases of timed pieces (times in seconds from the start of the file).
    /// Pieces from the classic recognizer have no times (start = end = -1).
    /// `partial` gets everything transcribed so far after each ~1 minute piece, so the app can show it right away.
    static func transcribe(_ url: URL, progress: @escaping @MainActor (Double) -> Void = { _ in },
                           partial: @escaping @MainActor ([[TimedText]]) -> Void = { _ in }) async throws -> [[TimedText]] {
        guard await authorize() else { throw Failure.notAllowed }
        let pieces = try cut(url)
        defer { pieces.forEach { try? FileManager.default.removeItem(at: $0.url) } }
        let engine = TranscriptionEngine.current   // Settings → Models
        var hasAnalyzer = false
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), engine == .auto || engine == .apple {
            hasAnalyzer = true
            do { return try await transcribeWithAnalyzer(pieces, progress: progress, partial: partial) }
            catch { if engine == .apple { throw error } }
        }
        #endif
        #if canImport(FluidAudio)
        if engine == .parakeetEnglish || engine == .parakeetMulti {
            return try await Parakeet.transcribe(pieces, multilingual: engine == .parakeetMulti, progress: progress, partial: partial)
        }
        // Automatic: only on phones without iOS 26, so nobody downloads it without need
        if engine == .auto, !hasAnalyzer, Parakeet.suitsLanguage {
            do { return try await Parakeet.transcribe(pieces, multilingual: false, progress: progress, partial: partial) }
            catch { /* e.g. model not downloaded and offline: fall through */ }
        }
        #endif
        if engine == .apple { throw Failure.unavailable }   // picked Apple Speech, but this iOS doesn't have it
        return try await transcribeClassic(pieces, progress: progress, partial: partial)
    }

    /// Apple Speech model for this language: true = on the device, false = not yet, nil = needs iOS 26.
    static func appleSpeechStatus() async -> Bool? {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            guard let t = await appleTranscriber() else { return nil }
            return await AssetInventory.status(forModules: [t]) == .installed
        }
        #endif
        return nil
    }

    static func installAppleSpeech() async throws {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            guard let t = await appleTranscriber() else { throw Failure.unavailable }
            if let r = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await r.downloadAndInstall() }
            return
        }
        #endif
        throw Failure.unavailable
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func appleTranscriber() async -> SpeechTranscriber? {
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: Transcriber.preferredLocale)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale = found else { return nil }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    }
    #endif

    /// Plain text of a transcript.
    static func plain(_ phrases: [[TimedText]]) -> String {
        phrases
            .map { $0.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func transcribeWithAnalyzer(_ pieces: [Piece], progress: @escaping @MainActor (Double) -> Void,
                                               partial: @escaping @MainActor ([[TimedText]]) -> Void) async throws -> [[TimedText]] {
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: Transcriber.preferredLocale)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale = found else { throw Failure.unavailable }
        func makeTranscriber() -> SpeechTranscriber {
            // Word times let us line the words up with who was speaking
            SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                              attributeOptions: [.audioTimeRange])
        }
        // First time only: iOS downloads the speech model for this language (no audio is sent anywhere)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber()]) {
            try await install.downloadAndInstall()
        }

        var all: [[TimedText]] = []
        for (i, piece) in pieces.enumerated() {
            let transcriber = makeTranscriber()
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if !Vocabulary.words.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = Vocabulary.words
                try? await analyzer.setContext(context)
            }
            let file = try AVAudioFile(forReading: piece.url)
            async let results: [[TimedText]] = transcriber.results.reduce(into: []) { out, result in
                if result.isFinal { out.append(Speakers.pieces(of: result.text, phrase: result.range)) }
            }
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            // Times in this piece -> times in the whole recording
            for phrase in try await results {
                all.append(phrase.map { TimedText(text: $0.text, start: $0.start + piece.offset, end: $0.end + piece.offset) })
            }
            await partial(all)
            await progress(Double(i + 1) / Double(pieces.count))
        }
        return all
    }
    #endif

    private static func transcribeClassic(_ pieces: [Piece], progress: @escaping @MainActor (Double) -> Void,
                                          partial: @escaping @MainActor ([[TimedText]]) -> Void) async throws -> [[TimedText]] {
        guard let recognizer = SFSpeechRecognizer(locale: Transcriber.preferredLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw Failure.unavailable }
        var all: [[TimedText]] = []
        for (i, piece) in pieces.enumerated() {
            if let t = try await recognize(piece.url, with: recognizer) {
                let timed = timedPieces(t, offset: piece.offset)
                if !timed.isEmpty { all.append(timed) }
            }
            await partial(all)
            await progress(Double(i + 1) / Double(pieces.count))
        }
        return all
    }

    /// Words with times from the classic recognizer (times are only there in final results).
    static func timedPieces(_ t: SFTranscription, offset: Double) -> [TimedText] {
        let segs = t.segments
        guard !segs.isEmpty else {
            let s = t.formattedString
            return s.isEmpty ? [] : [TimedText(text: s, start: -1, end: -1)]
        }
        return segs.enumerated().map { i, s in
            TimedText(text: (i == 0 ? "" : " ") + s.substring,
                      start: offset + s.timestamp, end: offset + s.timestamp + s.duration)
        }
    }

    static func authorize() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    private static func recognize(_ url: URL, with recognizer: SFSpeechRecognizer) async throws -> SFTranscription? {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = Vocabulary.words
        return try await withCheckedThrowingContinuation { c in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    c.resume(returning: result.bestTranscription)
                } else if let error {
                    done = true
                    // "No speech detected" just means a silent piece
                    if (error as NSError).code == 1110 { c.resume(returning: nil) } else { c.resume(throwing: error) }
                }
            }
        }
    }

    struct Piece { let url: URL; let offset: Double }

    /// Cuts a recording into temporary ~1 minute pieces. Each cut lands at the quietest 50 ms
    /// in the last few seconds before the minute mark, so words aren't split.
    static func cut(_ url: URL) throws -> [Piece] {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let rate = format.sampleRate
        let total = input.length
        let target = AVAudioFramePosition(pieceSeconds * rate)
        let search = AVAudioFramePosition(searchSeconds * rate)
        var out: [Piece] = []
        var start: AVAudioFramePosition = 0
        while start < total {
            var end = min(total, start + target)
            // Not the last piece (and the rest isn't tiny): look for a pause to cut at
            if end < total, total - end > AVAudioFramePosition(rate * 5) {
                let from = end - search
                if let q = try quietest(input, from: from, frames: search, rate: rate) { end = from + q }
            }
            input.framePosition = start
            let count = AVAudioFrameCount(end - start)
            guard count > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
            try input.read(into: buf, frameCount: count)
            if buf.frameLength == 0 { break }
            let piece = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            let file = try AVAudioFile(forWriting: piece, settings: input.fileFormat.settings,
                                       commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try file.write(from: buf)
            out.append(Piece(url: piece, offset: Double(start) / rate))
            start += AVAudioFramePosition(buf.frameLength)
        }
        return out
    }

    /// Offset (in frames from `from`) of the middle of the quietest 50 ms window.
    private static func quietest(_ file: AVAudioFile, from: AVAudioFramePosition, frames: AVAudioFramePosition,
                                 rate: Double) throws -> AVAudioFramePosition? {
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        file.framePosition = from
        try file.read(into: buf, frameCount: AVAudioFrameCount(frames))
        guard let s = buf.floatChannelData?[0] else { return nil }
        let n = Int(buf.frameLength)
        let win = max(1, Int(rate * 0.05))
        var best = Float.greatestFiniteMagnitude
        var bestAt = -1
        var i = 0
        while i + win <= n {
            var e: Float = 0
            for k in i..<(i + win) { e += s[k] * s[k] }
            if e < best { best = e; bestAt = i + win / 2 }
            i += win / 2
        }
        return bestAt > 0 ? AVAudioFramePosition(bestAt) : nil
    }
}

#if canImport(FluidAudio)
/// NVIDIA Parakeet TDT 0.6B v2 (English) through FluidAudio, for phones without iOS 26.
/// This is what Omi uses on iOS 17+. Runs on the Neural Engine; audio stays on the phone.
enum Parakeet {
    /// Parakeet v2 is English only; other languages use Apple's classic recognizer.
    static var suitsLanguage: Bool { Transcriber.preferredLocale.language.languageCode?.identifier == "en" }

    private actor Loader {
        static let shared = Loader()
        private var manager: AsrManager?
        private var multilingual: Bool?
        func get(multilingual multi: Bool) async throws -> AsrManager {
            if let manager, multilingual == multi { return manager }
            manager = nil   // free the other one first
            let models = try await AsrModels.downloadAndLoad(version: multi ? .v3 : .v2)
            let m = AsrManager(config: .default)
            try await m.loadModels(models)
            manager = m
            multilingual = multi
            return m
        }
    }

    static func transcribe(_ pieces: [Transcriber.Piece], multilingual: Bool, progress: @escaping @MainActor (Double) -> Void,
                           partial: @escaping @MainActor ([[TimedText]]) -> Void) async throws -> [[TimedText]] {
        let asr = try await Loader.shared.get(multilingual: multilingual)
        var all: [[TimedText]] = []
        for (i, piece) in pieces.enumerated() {
            var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            let result = try await asr.transcribe(piece.url, decoderState: &state)
            all += phrases(result, offset: piece.offset)
            await partial(all)
            await progress(Double(i + 1) / Double(pieces.count))
        }
        return all
    }

    /// Words with times, grouped into phrases at sentence ends and pauses (like SpeechAnalyzer).
    private static func phrases(_ r: ASRResult, offset: Double) -> [[TimedText]] {
        let words = buildWordTimings(from: r.tokenTimings ?? [])
        guard !words.isEmpty else {
            let t = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [[TimedText(text: t, start: offset, end: offset + r.duration)]]
        }
        var out: [[TimedText]] = []
        var current: [TimedText] = []
        var lastEnd = -1.0
        for w in words {
            let start = offset + w.startTime, end = offset + w.endTime
            if !current.isEmpty, start - lastEnd > 0.8 { out.append(current); current = [] }
            current.append(TimedText(text: (current.isEmpty ? "" : " ") + w.word, start: start, end: end))
            lastEnd = end
            if let c = w.word.last, ".?!".contains(c) { out.append(current); current = [] }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
#endif
