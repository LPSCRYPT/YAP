import AVFoundation
import Foundation

/// A note saved on the phone.
struct Note: Identifiable, Hashable {
    let name: String          // e.g. N0007_20261031_140210.wav
    let audioURL: URL
    let date: Date
    let seconds: Int
    var transcript: String?
    var insights: NoteInsights?
    /// Nobody talked: hidden from the list, kept under "Discarded" (never deleted silently, like Omi)
    var discarded = false
    /// Who each "Person N" is, once recognized or named
    var people: [Int: UUID] = [:]

    var id: String { name }
    var number: Int { Int(name.dropFirst().prefix(4)) ?? 0 }
    /// Part number when one recording was split into several conversations (N0007-2_…)
    var part: Int? {
        let head = name.split(separator: "_").first ?? ""
        guard let dash = head.firstIndex(of: "-") else { return nil }
        return Int(head[head.index(after: dash)...])
    }
    /// The made-up title once there is one, otherwise "Note 7"
    var heading: String { insights?.title ?? title }
    var title: String { part.map { "Note \(number), part \($0)" } ?? "Note \(number)" }
}

/// Keeps downloaded notes in Documents/Notes: <name>.wav, <name>.txt for the transcript
/// and <name>.summary.json for the summary and action items.
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = docs.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }()

    /// Every recording ever taken from the pendant, so ones that were split up,
    /// dropped as silent or deleted on the phone don't download again.
    private var fetched: Set<String> = []
    private var fetchedURL: URL { folder.appendingPathComponent("fetched.txt") }

    init() {
        let list = (try? String(contentsOf: fetchedURL, encoding: .utf8)) ?? ""
        fetched = Set(list.split(separator: "\n").map(String.init))
        reload()
    }

    func has(_ name: String) -> Bool { fetched.contains(name) || notes.contains { $0.name == name } }

    /// Remember a pendant recording as taken, whatever we end up keeping from it.
    func markFetched(_ name: String) {
        guard fetched.insert(name).inserted else { return }
        try? fetched.sorted().joined(separator: "\n").write(to: fetchedURL, atomically: true, encoding: .utf8)
    }

    func save(name: String, audio: Data) {
        try? audio.write(to: folder.appendingPathComponent(name), options: .atomic)
        reload()
    }

    /// Name for a piece of a split recording: same note number plus a part,
    /// and the clock time the piece starts. N0007_20261031_140210.wav + 2, 600 s
    /// -> N0007-2_20261031_141210.wav
    static func partName(_ name: String, part: Int, offsetSeconds: Int) -> String {
        let head = name.split(separator: "_").first ?? "N0000"
        let start = date(from: name).addingTimeInterval(TimeInterval(offsetSeconds))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return "\(head)-\(part)_\(f.string(from: start)).wav"
    }

    func setTranscript(_ text: String, for name: String) {
        try? text.write(to: transcriptURL(name), atomically: true, encoding: .utf8)
        if let i = notes.firstIndex(where: { $0.name == name }) { notes[i].transcript = text }
        // A new transcript makes the old summary stale
        setInsights(nil, for: name)
    }

    /// Swap in a transcript with speaker names, keeping the summary (the words are the same).
    func setLabeledTranscript(_ text: String, for name: String) {
        try? text.write(to: transcriptURL(name), atomically: true, encoding: .utf8)
        if let i = notes.firstIndex(where: { $0.name == name }) { notes[i].transcript = text }
    }

    /// Word times, kept so speakers can be worked out (again) later: <name>.words.json
    func saveWords(_ phrases: [[TimedText]], for name: String) {
        if let data = try? JSONEncoder().encode(phrases) { try? data.write(to: wordsURL(name), options: .atomic) }
    }

    func words(for name: String) -> [[TimedText]]? {
        (try? Data(contentsOf: wordsURL(name))).flatMap { try? JSONDecoder().decode([[TimedText]].self, from: $0) }
    }

    func saveTurns(_ turns: [SpeakerTurn], for name: String) {
        if let data = try? JSONEncoder().encode(turns) { try? data.write(to: sideURL(name, "turns.json"), options: .atomic) }
    }

    func turns(for name: String) -> [SpeakerTurn]? {
        (try? Data(contentsOf: sideURL(name, "turns.json"))).flatMap { try? JSONDecoder().decode([SpeakerTurn].self, from: $0) }
    }

    func setPeople(_ map: [Int: UUID], for name: String) {
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: sideURL(name, "people.json"), options: .atomic) }
        if let i = notes.firstIndex(where: { $0.name == name }) { notes[i].people = map }
    }

    func setDiscarded(_ on: Bool, for name: String) {
        let url = sideURL(name, "discarded")
        if on { try? Data().write(to: url) } else { try? FileManager.default.removeItem(at: url) }
        if let i = notes.firstIndex(where: { $0.name == name }) { notes[i].discarded = on }
    }

    private func sideURL(_ name: String, _ ext: String) -> URL {
        folder.appendingPathComponent((name as NSString).deletingPathExtension + "." + ext)
    }

    private func wordsURL(_ name: String) -> URL {
        folder.appendingPathComponent((name as NSString).deletingPathExtension + ".words.json")
    }

    func setInsights(_ insights: NoteInsights?, for name: String) {
        let url = insightsURL(name)
        if let insights, let data = try? JSONEncoder().encode(insights) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        if let i = notes.firstIndex(where: { $0.name == name }) { notes[i].insights = insights }
    }

    func toggleActionItem(_ index: Int, for name: String) {
        guard var insights = notes.first(where: { $0.name == name })?.insights,
              insights.actionItems.indices.contains(index) else { return }
        insights.actionItems[index].done.toggle()
        setInsights(insights, for: name)
    }

    func delete(_ note: Note) {
        try? FileManager.default.removeItem(at: note.audioURL)
        try? FileManager.default.removeItem(at: transcriptURL(note.name))
        try? FileManager.default.removeItem(at: insightsURL(note.name))
        try? FileManager.default.removeItem(at: wordsURL(note.name))
        for ext in ["turns.json", "people.json", "discarded"] { try? FileManager.default.removeItem(at: sideURL(note.name, ext)) }
        notes.removeAll { $0.name == note.name }
    }

    private func transcriptURL(_ name: String) -> URL {
        folder.appendingPathComponent((name as NSString).deletingPathExtension + ".txt")
    }

    private func insightsURL(_ name: String) -> URL {
        folder.appendingPathComponent((name as NSString).deletingPathExtension + ".summary.json")
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        notes = files.filter { $0.hasSuffix(".wav") }.map { name in
            let url = folder.appendingPathComponent(name)
            let secs = (try? AVAudioFile(forReading: url)).map { Int(Double($0.length) / $0.fileFormat.sampleRate) } ?? 0
            let text = try? String(contentsOf: transcriptURL(name), encoding: .utf8)
            let insights = (try? Data(contentsOf: insightsURL(name))).flatMap { try? JSONDecoder().decode(NoteInsights.self, from: $0) }
            var note = Note(name: name, audioURL: url, date: Self.date(from: name), seconds: secs,
                            transcript: text, insights: insights)
            note.discarded = FileManager.default.fileExists(atPath: sideURL(name, "discarded").path)
            note.people = (try? Data(contentsOf: sideURL(name, "people.json")))
                .flatMap { try? JSONDecoder().decode([Int: UUID].self, from: $0) } ?? [:]
            return note
        }
        .sorted { $0.date > $1.date }
    }

    /// N0007_20261031_140210.wav -> date (the pendant stores local time)
    static func date(from name: String) -> Date {
        let parts = name.split(separator: "_")
        guard parts.count >= 3 else { return .distantPast }
        let stamp = parts[1] + "_" + parts[2].prefix(6)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.date(from: String(stamp)) ?? .distantPast
    }
}
