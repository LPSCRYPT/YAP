import AVFoundation
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Someone the app knows by voice. "You" is the person with isMe = true.
/// Voices are stored as 256-number fingerprints (speaker embeddings), never as audio.
/// Everything stays in Documents/people.json on the phone.
struct Person: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var isMe = false
    /// A few voice fingerprints from different conversations (newest last, at most 8)
    var voices: [[Float]] = []
}

/// The people list, plus matching a voice to a person.
@MainActor
final class PeopleStore: ObservableObject {
    @Published private(set) var people: [Person] = []

    private let url: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("people.json")

    init() {
        people = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Person].self, from: $0) } ?? []
    }

    var me: Person? { people.first { $0.isMe } }
    func person(_ id: UUID) -> Person? { people.first { $0.id == id } }

    /// Name to show: "You" for the owner.
    func displayName(_ id: UUID) -> String? {
        guard let p = person(id) else { return nil }
        return p.isMe ? "You" : p.name
    }

    /// Save your own voice (replaces an earlier one).
    func setMyVoice(_ voice: [Float]) {
        if let i = people.firstIndex(where: { $0.isMe }) {
            people[i].voices = [voice]
        } else {
            people.insert(Person(name: "You", isMe: true, voices: [voice]), at: 0)
        }
        save()
    }

    /// Adds a voice sample to someone (new person when `id` is nil). Returns their id.
    @discardableResult
    func teach(_ voice: [Float]?, to id: UUID?, newName: String? = nil) -> UUID? {
        if let id, let i = people.firstIndex(where: { $0.id == id }) {
            if let voice { people[i].voices = Array((people[i].voices + [voice]).suffix(8)) }
            save()
            return id
        }
        guard let name = newName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let p = Person(name: name, voices: voice.map { [$0] } ?? [])
        people.append(p)
        save()
        return p.id
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = people.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        people[i].name = name
        save()
    }

    func remove(_ id: UUID) {
        people.removeAll { $0.id == id }
        save()
    }

    /// How close a voice is to someone (best of their saved fingerprints).
    func score(_ voice: [Float], _ id: UUID) -> Float {
        person(id)?.voices.map { Self.cosine(voice, $0) }.max() ?? 0
    }

    /// Learning in the background: keeps the first (enrolled) voice plus the 7 newest, so at
    /// most 8 fingerprints (about 8 KB) per person. Only called when a match is very sure.
    func learn(_ voice: [Float], for id: UUID) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        var v = people[i].voices
        guard let first = v.first else { return }
        v = [first] + Array((v.dropFirst() + [voice]).suffix(7))
        people[i].voices = v
        save()
    }

    /// Cosine similarity at or above this counts as the same voice. Speaker fingerprints of one
    /// person usually score 0.6-0.9; different people mostly below 0.4.
    static let sameVoice: Float = 0.5

    /// Best match for each voice, each person used once (strongest match wins).
    func match(_ voices: [Int: [Float]]) -> [Int: UUID] {
        var pairs: [(speaker: Int, person: UUID, score: Float)] = []
        for (speaker, v) in voices {
            for p in people where !p.voices.isEmpty {
                let best = p.voices.map { Self.cosine(v, $0) }.max() ?? 0
                if best >= Self.sameVoice { pairs.append((speaker, p.id, best)) }
            }
        }
        var out: [Int: UUID] = [:]
        var used: Set<UUID> = []
        for pair in pairs.sorted(by: { $0.score > $1.score }) where out[pair.speaker] == nil && !used.contains(pair.person) {
            out[pair.speaker] = pair.person
            used.insert(pair.person)
        }
        return out
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(people) { try? data.write(to: url, options: .atomic) }
    }
}

/// Voice fingerprints with the WeSpeaker model (FluidAudio, Core ML, on the phone).
/// The model downloads once (a few MB) from Hugging Face.
enum VoicePrint {
    #if canImport(FluidAudio)
    private actor Loader {
        static let shared = Loader()
        private var diarizer: DiarizerManager?
        func embedding(_ samples: [Float]) throws -> [Float]? { try diarizer.map { try VoicePrint.average($0, samples) } ?? nil }
        func load() async throws {
            if diarizer != nil { return }
            let models = try await DiarizerModels.downloadIfNeeded()
            let d = DiarizerManager()
            d.initialize(models: models)
            diarizer = d
        }
    }

    /// Averages fingerprints over 10 s windows (the model's window). nil if under 3 s of audio.
    private static func average(_ d: DiarizerManager, _ samples: [Float]) throws -> [Float]? {
        var sum = [Float](repeating: 0, count: 256)
        var n = 0
        var i = 0
        while i < samples.count {
            let chunk = Array(samples[i..<min(samples.count, i + 160_000)])
            i += 160_000
            if chunk.count < 48_000 { continue }
            let e = try d.extractSpeakerEmbedding(from: chunk)
            guard e.count == 256, e.contains(where: { $0 != 0 }) else { continue }
            for k in 0..<256 { sum[k] += e[k] }
            n += 1
        }
        guard n > 0 else { return nil }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? sum.map { $0 / norm } : nil
    }
    #endif

    /// Fingerprint of 16 kHz mono audio of one person.
    static func of(_ samples: [Float]) async -> [Float]? {
        #if canImport(FluidAudio)
        guard samples.count >= 48_000, (try? await Loader.shared.load()) != nil else { return nil }
        return try? await Loader.shared.embedding(samples)
        #else
        return nil
        #endif
    }

    /// 16 kHz mono samples from a file, only inside the given time ranges (seconds), up to `limit` seconds.
    static func samples(_ url: URL, ranges: [(Double, Double)] = [], limit: Double = 40) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        else { return [] }
        let rate = file.processingFormat.sampleRate
        let wanted: [(Double, Double)] = ranges.isEmpty ? [(0.0, Double(file.length) / rate)] : ranges
        var out: [Float] = []
        let cap = Int(limit * 16_000)
        for (a, b) in wanted where b > a {
            let start = AVAudioFramePosition(max(0, a) * rate)
            let count = AVAudioFrameCount(max(0, min(Double(file.length) - Double(start), (b - a) * rate)))
            guard count > 0, let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { continue }
            file.framePosition = start
            guard (try? file.read(into: buf, frameCount: count)) != nil else { continue }
            out += resample(buf, to: target)
            if out.count >= cap { break }
        }
        return Array(out.prefix(cap))
    }

    private static func resample(_ buf: AVAudioPCMBuffer, to target: AVAudioFormat) -> [Float] {
        if buf.format.sampleRate == 16_000, buf.format.commonFormat == .pcmFormatFloat32, let p = buf.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: p, count: Int(buf.frameLength)))
        }
        guard let conv = AVAudioConverter(from: buf.format, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity:
                AVAudioFrameCount(Double(buf.frameLength) * 16_000 / buf.format.sampleRate) + 256) else { return [] }
        var given = false
        var error: NSError?
        _ = conv.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return buf
        }
        guard let p = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: p, count: Int(out.frameLength)))
    }
}

/// Records your voice with the phone's microphone for 20 seconds (for "teach it your voice").
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var level: Float = 0
    static let seconds = 20.0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("my-voice.wav")

    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record(forDuration: Self.seconds) else { return false }
            recorder = r
        } catch { return false }
        recording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                self.level = max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50))
                self.elapsed = r.currentTime
                if !r.isRecording { self.stop() }
            }
        }
        return true
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
