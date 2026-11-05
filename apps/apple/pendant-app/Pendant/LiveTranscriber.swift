import AVFoundation
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif
#if canImport(Speech)
import Speech
#endif

/// Words on screen while the pendant records, like Omi's live transcript.
/// The pendant streams its Opus audio over Bluetooth as it records (PendantLink "live" packets).
/// We decode each 20 ms packet as it arrives and feed it to Apple's on-device speech engine.
/// Nothing leaves the phone. When recording stops, this live transcript (with who said what)
/// becomes the note's transcript, so the note isn't transcribed a second time.
@MainActor
final class LiveTranscriber: ObservableObject {
    /// True from the first live packet until the pendant stops recording.
    @Published private(set) var active = false
    @Published private(set) var startedAt: Date?
    /// Finished sentences, and the words still being worked out (they change as you talk).
    @Published private(set) var partialText = ""
    @Published private(set) var problem: String?
    /// Pendant out of range: it keeps recording, and the text catches up when it's back
    @Published private(set) var paused = false
    /// Part of the audio never reached us live, so the note gets transcribed from the file instead
    private var incomplete = false
    /// Finished phrases with word times, and who spoke when (from the speaker model)
    @Published private(set) var phrases: [[TimedText]] = []
    @Published private(set) var turns: [SpeakerTurn] = []

    var finalText: String { phrases.map { $0.map(\.text).joined().trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
    var text: String { [finalText, partialText].filter { !$0.isEmpty }.joined(separator: " ") }
    /// The transcript so far, split by speaker when more than one person is talking.
    var lines: [SpeakerLine] { Speakers.lines(phrases, turns: turns, minPeople: 1) }

    enum VoiceModel { case loading, ready, unavailable }
    /// State of the "who's speaking" model (downloads once, the first time)
    @Published private(set) var voiceModel: VoiceModel = .loading

    /// The pendant note this live transcript belongs to
    private(set) var noteName: String?
    private var textDone = false
    private var speakersDone = false

    #if canImport(FluidAudio)
    private var speakers: LiveDiarizer?
    #endif

    private var parser = OpusStreamParser()
    private var decoder: OpusLiveDecoder?
    private var engine: AnyObject?

    func start(note: String) {
        stopEngine()
        noteName = note
        paused = false
        incomplete = false
        textDone = false
        speakersDone = !Speakers.isIncluded
        voiceModel = Speakers.isIncluded ? .loading : .unavailable
        parser = OpusStreamParser()
        decoder = nil
        phrases = []
        turns = []
        partialText = ""
        problem = nil
        startedAt = Date()
        active = true
        #if canImport(FluidAudio)
        let d = LiveDiarizer()
        d.onTurns = { [weak self, weak d] t in
            guard let self, let d, self.speakers === d else { return }
            self.turns = t
        }
        d.onReady = { [weak self, weak d] ok in
            guard let self, let d, self.speakers === d else { return }
            self.voiceModel = ok ? .ready : .unavailable
        }
        d.onDone = { [weak self, weak d] in
            guard let self, let d, self.speakers === d else { return }
            self.speakersDone = true
        }
        speakers = d
        #endif
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let e = LiveEngine()
            engine = e
            Task {
                do {
                    try await e.run { [weak self] text, pieces in
                        guard let self, self.engine === e else { return }
                        if let pieces {
                            if !text.isEmpty { self.phrases.append(pieces) }
                            self.partialText = ""
                        } else {
                            self.partialText = text
                        }
                    }
                } catch {
                    if self.engine === e { self.problem = "Live text stopped: \(error.localizedDescription)" }
                }
                if self.engine === e { self.textDone = true }
            }
            return
        }
        #endif
        // Before iOS 26: Apple's classic recognizer, restarted every 50 s (it has a time limit)
        let c = ClassicLiveEngine { [weak self] text, pieces in
            guard let self else { return }
            if let pieces {
                if !text.isEmpty { self.phrases.append(pieces) }
                self.partialText = ""
            } else {
                self.partialText = text
            }
        }
        if let c {
            engine = c
            c.onDone = { [weak self, weak c] in
                guard let self, let c, self.engine === c else { return }
                self.textDone = true
            }
            Task { _ = await Transcriber.authorize() }
            return
        }
        textDone = true
        problem = "Live text isn't available on this device. The note is still transcribed when you stop."
    }

    func feed(_ bytes: Data) {
        guard active else { return }
        for packet in parser.push(bytes) {
            if decoder == nil, let h = parser.header { decoder = OpusLiveDecoder(rate: h.rate, frameSamples: h.frameSamples) }
            guard let pcm = decoder?.decode(packet) else { continue }
            #if canImport(FluidAudio)
            speakers?.append(Self.to16k(pcm))
            #endif
            (engine as? ClassicLiveEngine)?.append(pcm)
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { (engine as? LiveEngine)?.append(pcm) }
            #endif
        }
    }

    /// 48 kHz decoder output -> 16 kHz for the speaker model. The audio was 16 kHz to begin with,
    /// so averaging every 3 samples is enough.
    private static func to16k(_ pcm: AVAudioPCMBuffer) -> [Float] {
        guard let p = pcm.floatChannelData?[0] else { return [] }
        let n = Int(pcm.frameLength) / 3
        return (0..<n).map { i in (p[3 * i] + p[3 * i + 1] + p[3 * i + 2]) / 3 }
    }

    /// Recording stopped. Let the engine finish the last words; the text stays on screen.
    func finish() {
        active = false
        paused = false
        #if canImport(FluidAudio)
        speakers?.finish()
        #endif
        (engine as? ClassicLiveEngine)?.finish()
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { (engine as? LiveEngine)?.finish() }
        #endif
    }

    /// The finished live transcript for a note, once the last words and speakers are in
    /// (waits up to 10 s). nil if this note wasn't transcribed live, or live text had a problem.
    func result(for name: String) async -> (phrases: [[TimedText]], turns: [SpeakerTurn])? {
        guard noteName == name else { return nil }
        for _ in 0..<100 where !(textDone && speakersDone) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard noteName == name, textDone, problem == nil, !incomplete, !phrases.isEmpty else { return nil }
        return (phrases, turns)
    }

    func setPaused(_ p: Bool) { if active { paused = p } }
    func markIncomplete() { incomplete = true }

    /// Clear the screen (after the note is saved and the user closes the live view).
    func clear() {
        stopEngine()
        #if canImport(FluidAudio)
        speakers = nil
        #endif
        phrases = []
        turns = []
        partialText = ""
        problem = nil
        startedAt = nil
    }

    private func stopEngine() {
        (engine as? ClassicLiveEngine)?.cancel()
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { (engine as? LiveEngine)?.cancel() }
        #endif
        engine = nil
    }
}

#if compiler(>=6.2)
/// Apple SpeechAnalyzer fed from a stream of audio buffers, reporting words as they're heard.
@available(iOS 26.0, *)
@MainActor
private final class LiveEngine {
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var waiting: [AVAudioPCMBuffer] = []   // audio that came in while the engine was starting
    private var ended = false

    /// onText(text, pieces): pieces with word times for a finished phrase, nil while still guessing.
    func run(_ onText: @escaping @MainActor (String, [TimedText]?) -> Void) async throws {
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: Transcriber.preferredLocale)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale = found else { throw Transcriber.Failure.unavailable }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()   // first time only, on the phone
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !Vocabulary.words.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Vocabulary.words
            try? await analyzer.setContext(context)
        }
        self.analyzer = analyzer
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        try await analyzer.start(inputSequence: stream)

        // Send what arrived during setup, then end if recording already stopped
        let early = waiting
        waiting = []
        early.forEach(append)
        if ended { finish() }

        for try await result in transcriber.results {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isFinal {
                onText(text, Speakers.pieces(of: result.text, phrase: result.range))
            } else {
                onText(text, nil)
            }
        }
    }

    func append(_ pcm: AVAudioPCMBuffer) {
        guard let input, let format else { waiting.append(pcm); return }
        if pcm.format == format { input.yield(AnalyzerInput(buffer: pcm)); return }
        if converter == nil { converter = AVAudioConverter(from: pcm.format, to: format) }
        guard let converter,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity:
                AVAudioFrameCount(Double(pcm.frameLength) * format.sampleRate / pcm.format.sampleRate) + 64)
        else { return }
        var given = false
        var error: NSError?
        // .noDataNow (not end of stream) keeps the resampler's state between packets
        _ = converter.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return pcm
        }
        if out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    func finish() {
        ended = true
        guard let input, let analyzer else { return }
        input.finish()
        self.input = nil
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }

    func cancel() {
        input?.finish()
        input = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    }
}
#endif

/// Live text for phones without iOS 26: SFSpeechRecognizer fed audio buffers. One request can't
/// run for long, so a new one starts every ~50 s of audio; each keeps its own time offset.
@MainActor
private final class ClassicLiveEngine {
    var onDone: (() -> Void)?
    private let recognizer: SFSpeechRecognizer
    private let onText: (String, [TimedText]?) -> Void
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tasks: [SFSpeechRecognitionTask] = []
    private var open = 0          // requests still waiting for their final result
    private var fed = 0.0         // seconds of audio given so far
    private var requestStart = 0.0
    private var ending = false
    private var nextID = 0
    private var closed: Set<Int> = []

    init?(onText: @escaping (String, [TimedText]?) -> Void) {
        guard let r = SFSpeechRecognizer(locale: Transcriber.preferredLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              r.isAvailable else { return nil }
        recognizer = r
        self.onText = onText
    }

    func append(_ pcm: AVAudioPCMBuffer) {
        guard !ending else { return }
        if request == nil { begin() }
        request?.append(pcm)
        fed += Double(pcm.frameLength) / pcm.format.sampleRate
        if fed - requestStart > 50 { request?.endAudio(); request = nil }
    }

    private func begin() {
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        r.addsPunctuation = true
        r.contextualStrings = Vocabulary.words
        let offset = fed
        requestStart = fed
        open += 1
        nextID += 1
        let id = nextID
        let task = recognizer.recognitionTask(with: r) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal == true
            let pieces = isFinal ? result.map { Transcriber.timedPieces($0.bestTranscription, offset: offset) } : nil
            Task { @MainActor in
                guard let self, !self.closed.contains(id) else { return }
                if isFinal { self.onText(text, pieces ?? []) } else if result != nil { self.onText(text, nil) }
                if isFinal || error != nil {
                    self.closed.insert(id)
                    self.open -= 1
                    if self.ending && self.open == 0 { self.onDone?() }
                }
            }
        }
        tasks.append(task)
        request = r
    }

    func finish() {
        ending = true
        request?.endAudio()
        request = nil
        if open == 0 { onDone?() }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
        request = nil
    }
}

/// Reads the pendant's Opus stream as it arrives:
///   "PDO1"  u16 sample_rate  u16 frame_samples   then per 20 ms frame:  u16 len  <len bytes>
struct OpusStreamParser {
    struct Header { let rate: Int; let frameSamples: Int }
    private(set) var header: Header?
    private var buffer = Data()

    /// Adds bytes and returns every complete Opus packet now available.
    mutating func push(_ bytes: Data) -> [Data] {
        buffer.append(bytes)
        var out: [Data] = []
        var b = [UInt8](buffer)
        var i = 0
        if header == nil {
            guard b.count >= 8 else { return [] }
            guard b[0] == 0x50, b[1] == 0x44, b[2] == 0x4F, b[3] == 0x31 else { buffer = Data(); return [] }
            header = Header(rate: Int(b[4]) | Int(b[5]) << 8, frameSamples: Int(b[6]) | Int(b[7]) << 8)
            i = 8
        }
        while i + 2 <= b.count {
            let n = Int(b[i]) | Int(b[i + 1]) << 8
            guard n > 0 else { i += 2; continue }
            guard i + 2 + n <= b.count else { break }
            out.append(Data(b[(i + 2)..<(i + 2 + n)]))
            i += 2 + n
        }
        b.removeFirst(i)
        buffer = Data(b)
        return out
    }
}

/// Decodes one Opus packet at a time into 48 kHz mono float audio (Apple's Opus decoder rate).
final class OpusLiveDecoder {
    private let decoder: AVAudioConverter
    private let opusFormat: AVAudioFormat
    private let pcmFormat: AVAudioFormat
    private let framesPerPacket: AVAudioFrameCount
    private let packet: AVAudioCompressedBuffer

    init?(rate: Int, frameSamples: Int) {
        guard rate > 0, frameSamples > 0 else { return nil }
        let decodeRate = 48000.0
        framesPerPacket = AVAudioFrameCount(Double(frameSamples) * decodeRate / Double(rate))
        var asbd = AudioStreamBasicDescription(
            mSampleRate: decodeRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(framesPerPacket), mBytesPerFrame: 0, mChannelsPerFrame: 1,
            mBitsPerChannel: 0, mReserved: 0)
        guard let o = AVAudioFormat(streamDescription: &asbd),
              let p = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: decodeRate, channels: 1, interleaved: false),
              let d = AVAudioConverter(from: o, to: p) else { return nil }
        opusFormat = o
        pcmFormat = p
        decoder = d
        packet = AVAudioCompressedBuffer(format: o, packetCapacity: 1, maximumPacketSize: 1500)
    }

    func decode(_ data: Data) -> AVAudioPCMBuffer? {
        guard data.count <= 1500,
              let frame = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: framesPerPacket * 2) else { return nil }
        data.withUnsafeBytes { packet.data.copyMemory(from: $0.baseAddress!, byteCount: data.count) }
        packet.byteLength = UInt32(data.count)
        packet.packetCount = 1
        packet.packetDescriptions?[0] = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count))
        var fed = false
        var error: NSError?
        let status = decoder.convert(to: frame, error: &error) { _, s in
            if fed { s.pointee = .noDataNow; return nil }
            fed = true
            s.pointee = .haveData
            return self.packet
        }
        guard status != .error, frame.frameLength > 0 else { return nil }
        return frame
    }
}
