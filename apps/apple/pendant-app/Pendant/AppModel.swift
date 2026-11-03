import Combine
import Foundation

/// Ties the pendant link, the saved notes and transcription together.
/// When the pendant connects, new notes download automatically and get transcribed.
@MainActor
final class AppModel: ObservableObject {
    let link = PendantLink()
    let store = NoteStore()
    let live = LiveTranscriber()
    let people = PeopleStore()
    let searchIndex = SearchIndex()

    func search(_ q: String) -> [SearchIndex.Hit] {
        searchIndex.search(q, in: store.notes, names: { [unowned self] in self.names(for: $0) })
    }
    /// The live transcript screen is open
    @Published var showLive = false
    /// The phone recording screen is open
    @Published var showPhoneRecorder = false

    @Published var transcribing: Set<String> = []
    /// How far along each transcription is (0...1), for long recordings
    @Published var transcribeProgress: [String: Double] = [:]
    /// Working out who's speaking in these notes
    @Published var labelingSpeakers: Set<String> = []
    /// What's transcribed so far, shown while the rest is still working (memory only)
    @Published var partialPhrases: [String: [[TimedText]]] = [:]
    @Published var summarizing: Set<String> = []
    /// Why summaries can't be made on this phone right now (nil when they can)
    @Published var summaryUnavailable: String?
    /// Progress of the one-time local model download (nil when not downloading)
    @Published var modelDownload: Double?

    /// Which model writes summaries. Changing it doesn't redo old notes; use "Summarize again".
    @Published var summaryEngine: SummaryEngine {
        didSet {
            UserDefaults.standard.set(summaryEngine.rawValue, forKey: "summaryEngine")
            summaryUnavailable = Summarizer.unavailableReason(summaryEngine)
            // Pick up notes that were waiting for a working model
            for n in store.notes where n.transcript != nil && n.insights == nil && n.transcript != Self.noSpeech {
            queueSummary(n.name)
        }
        }
    }
    @Published var lastError: String?

    /// Free up the pendant's storage once a note is safely on the phone.
    @Published var deleteAfterDownload: Bool {
        didSet { UserDefaults.standard.set(deleteAfterDownload, forKey: "deleteAfterDownload") }
    }

    private var bag: Set<AnyCancellable> = []
    private var transcribeQueue: [String] = []
    private var summarizeQueue: [String] = []

    init() {
        deleteAfterDownload = UserDefaults.standard.bool(forKey: "deleteAfterDownload")
        autoSplit = UserDefaults.standard.object(forKey: "autoSplit") as? Bool ?? true
        let engine = UserDefaults.standard.string(forKey: "summaryEngine").flatMap(SummaryEngine.init) ?? .preferred
        summaryEngine = engine
        summaryUnavailable = Summarizer.unavailableReason(engine)

        link.onFileReceived = { [weak self] name, data in
            Task { @MainActor in self?.received(name, data) }
        }
        // Forward changes so views watching the model refresh
        link.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        live.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        people.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)

        // Live packets arrive on the main thread (CoreBluetooth runs on the main queue)
        link.onLive = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch event {
                case .start(let name):
                    self.live.start(note: name)
                    self.showLive = true   // pendant started recording nearby: show it, like Omi
                case .bytes(let d): self.live.feed(d)
                case .end: self.live.finish()
                case .paused: self.live.setPaused(true)
                case .resumed: self.live.setPaused(false)
                case .incomplete: self.live.markIncomplete()
                }
            }
        }

        // New list from the pendant: fetch whatever we don't have yet
        link.$deviceNotes.receive(on: RunLoop.main).sink { [weak self] notes in
            guard let self else { return }
            for n in notes where !self.store.has(n.name) && !self.incoming.contains(n.name) { self.link.download(n.name) }
        }.store(in: &bag)

        // Transcribe anything saved earlier that has no text yet
        for n in store.notes where n.transcript == nil { queueTranscription(n.name) }
        // Find who spoke in notes that never got it (the queue doesn't survive closing the app)
        for n in store.notes where !n.discarded && n.transcript != nil && n.transcript != Self.noSpeech
            && store.words(for: n.name) != nil && store.turns(for: n.name) == nil { queueSpeakers(n.name) }
        // One voice only, from before single-person bubbles: label it now
        for n in store.notes where !n.discarded && store.turns(for: n.name) != nil
            && !(n.transcript.map { Speakers.parse($0).contains { $0.speaker != nil } } ?? true) { queueSpeakers(n.name) }
        // Drop to-dos saved before the stricter check (keeps ticks on the ones that stay)
        for n in store.notes {
            guard var i = n.insights, let t = n.transcript else { continue }
            let kept = i.actionItems.filteredTasks(transcript: t)
            if kept != i.actionItems { i.actionItems = kept; store.setInsights(i, for: n.name) }
        }
        // Summarize anything transcribed earlier that has no summary yet
        for n in store.notes where n.transcript != nil && n.insights == nil { queueSummary(n.name) }
        // Older notes have a summary but no title yet: add one, keeping their summary and ticks
        for n in store.notes where n.insights != nil && n.insights?.title == nil { queueSummary(n.name) }
    }

    var newOnDevice: Int { link.deviceNotes.filter { !store.has($0.name) }.count }

    func sync() { link.refreshList() }

    /// The app's live button: start recording on the pendant and watch the words come in.
    func startLive() {
        link.setRecording(true)
        showLive = true
    }

    func stopLive() { link.setRecording(false) }

    /// Split recordings into conversations on 2 min of quiet, and drop silent ones (like Omi).
    @Published var autoSplit: Bool {
        didSet { UserDefaults.standard.set(autoSplit, forKey: "autoSplit") }
    }

    private var incoming: Set<String> = []   // being split right now

    private func received(_ name: String, _ data: Data) {
        guard !store.has(name), !incoming.contains(name) else { return }
        incoming.insert(name)
        let split = autoSplit
        Task {
            var pieces: [Splitter.Piece]?
            if split { pieces = await Task.detached(priority: .userInitiated) { Splitter.split(data) }.value }
            // Recorded live? Then we already have the transcript and who spoke.
            let liveResult = await live.result(for: name)
            if let pieces {
                for (i, p) in pieces.enumerated() {
                    let partName = pieces.count == 1 ? name
                        : NoteStore.partName(name, part: i + 1, offsetSeconds: p.offsetSeconds)
                    let from = Double(p.offsetSeconds)
                    let to = from + Double(max(0, p.wav.count - 44)) / 32000   // 16 kHz, 16-bit
                    keep(partName, p.wav, live: liveResult.map { Speakers.slice($0.phrases, $0.turns, from: from, to: to) })
                }
            } else {
                keep(name, data, live: liveResult)
            }
            // Only now is it safely on the phone
            store.markFetched(name)
            incoming.remove(name)
            if deleteAfterDownload { link.deleteFromDevice(name) }
        }
    }

    private func keep(_ name: String, _ data: Data, live: (phrases: [[TimedText]], turns: [SpeakerTurn])? = nil) {
        store.save(name: name, audio: data)
        guard let live else { queueTranscription(name); return }
        if live.phrases.isEmpty {
            store.setTranscript(Self.noSpeech, for: name)
            if autoSplit { store.setDiscarded(true, for: name) }   // nobody talked: hide it, keep it
            return
        }
        store.saveWords(live.phrases, for: name)
        store.setTranscript(Speakers.text(Speakers.lines(live.phrases, turns: live.turns, minPeople: live.turns.isEmpty ? 2 : 1)), for: name)
        queueSummary(name)
        if live.turns.isEmpty {
            queueSpeakers(name)   // voice model wasn't ready live: do it now
        } else {
            store.saveTurns(live.turns, for: name)
            queueIdentify(name)
        }
    }

    func queueTranscription(_ name: String) {
        guard !transcribing.contains(name), !transcribeQueue.contains(name) else { return }
        transcribeQueue.append(name)
        if transcribeQueue.count == 1 { Task { await runTranscriptions() } }
    }

    private func runTranscriptions() async {
        while let name = transcribeQueue.first {
            transcribing.insert(name)
            if let note = store.notes.first(where: { $0.name == name }) {
                do {
                    transcribeProgress[name] = 0
                    let phrases = try await Transcriber.transcribe(note.audioURL, progress: { [weak self] p in
                        self?.transcribeProgress[name] = p
                    }, partial: { [weak self] ph in
                        self?.partialPhrases[name] = ph
                    })
                    let text = Transcriber.plain(phrases)
                    if text.isEmpty, autoSplit, note.transcript == nil {
                        // Nobody talked: hide it under Discarded instead of deleting (like Omi)
                        store.setTranscript(Self.noSpeech, for: name)
                        store.setDiscarded(true, for: name)
                    } else {
                        // Text first, so the note is usable right away; speakers are added after
                        store.saveWords(phrases, for: name)
                        store.setTranscript(text.isEmpty ? Self.noSpeech : text, for: name)
                        queueSummary(name)
                        if !text.isEmpty { queueSpeakers(name) }
                    }
                } catch {
                    lastError = "Couldn't transcribe: \(error.localizedDescription)"
                }
                transcribeProgress[name] = nil
                partialPhrases[name] = nil
            }
            transcribing.remove(name)
            transcribeQueue.removeFirst()
        }
    }

    static let noSpeech = "(No speech detected)"

    /// Transcript lines with where each starts in the audio (for tap-to-play).
    /// Built from the saved word times; falls back to the saved text.
    func displayLines(for note: Note) -> [SpeakerLine] {
        guard let t = note.transcript else { return [] }
        if let phrases = store.words(for: note.name),
           phrases.contains(where: { ($0.first?.start ?? -1) >= 0 }) {
            let labeled = Speakers.parse(t).contains { $0.speaker != nil }
            if labeled, let turns = store.turns(for: note.name) {
                let l = Speakers.lines(phrases, turns: turns, minPeople: 1)
                if l.contains(where: { $0.speaker != nil }) { return l }
            } else if !labeled {
                return Self.paragraphs(phrases)
            }
        }
        return Speakers.parse(t)
    }

    /// Phrases joined into paragraphs of about 20 seconds, each with its start time.
    static func paragraphs(_ phrases: [[TimedText]]) -> [SpeakerLine] {
        var out: [SpeakerLine] = []
        for ph in phrases {
            let text = ph.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let s = ph.first?.start ?? -1
            if out.isEmpty || (s >= 0 && (out[out.count - 1].start < 0 || s - out[out.count - 1].start >= 20)) {
                out.append(SpeakerLine(id: out.count, speaker: nil, text: text, start: s))
            } else {
                out[out.count - 1].text += " " + text
            }
        }
        return out
    }

    // MARK: Who's speaking (after the text is saved, so a slow first model download never blocks it)

    private var speakerQueue: [String] = []

    func queueSpeakers(_ name: String) {
        guard Speakers.isIncluded, !speakerQueue.contains(name) else { return }
        speakerQueue.append(name)
        if speakerQueue.count == 1 { Task { await runSpeakers() } }
    }

    private func runSpeakers() async {
        while let name = speakerQueue.first {
            labelingSpeakers.insert(name)
            if let note = store.notes.first(where: { $0.name == name }), let phrases = store.words(for: name),
               let turns = await Speakers.turns(for: note.audioURL) {
                store.saveTurns(turns, for: name)
                let lines = Speakers.lines(phrases, turns: turns, minPeople: 1)
                // Only if the text wasn't changed meanwhile
                if lines.contains(where: { $0.speaker != nil }),
                   let now = store.notes.first(where: { $0.name == name })?.transcript,
                   Speakers.words(now) == Speakers.words(Transcriber.plain(phrases)) {
                    store.setLabeledTranscript(Speakers.text(lines), for: name)
                    queueIdentify(name)
                }
            }
            labelingSpeakers.remove(name)
            speakerQueue.removeFirst()
        }
    }

    func queueSummary(_ name: String) {
        guard !summarizing.contains(name), !summarizeQueue.contains(name) else { return }
        summarizeQueue.append(name)
        if summarizeQueue.count == 1 { Task { await runSummaries() } }
    }

    private func runSummaries() async {
        while let name = summarizeQueue.first {
            let engine = summaryEngine
            summaryUnavailable = Summarizer.unavailableReason(engine)
            if summaryUnavailable != nil { summarizeQueue.removeAll(); break }
            summarizing.insert(name)
            if let text = store.notes.first(where: { $0.name == name })?.transcript,
               !text.isEmpty, text != Self.noSpeech {
                do {
                    let named = withNames(text, note: name)
                    let insights = try await Summarizer.summarize(named, engine: engine) { p in
                        Task { @MainActor [weak self] in self?.modelDownload = p < 1 ? p : nil }
                    }
                    modelDownload = nil
                    // Skip if the transcript changed while we were working
                    // (speaker names may have been added meanwhile; only the words matter)
                    if let current = store.notes.first(where: { $0.name == name }),
                       Speakers.words(current.transcript ?? "") == Speakers.words(text) {
                        if var old = current.insights {
                            // Only filling in a missing title: don't touch the summary or ticked items
                            old.title = insights.title; old.overview = insights.overview; old.category = insights.category
                            store.setInsights(old, for: name)
                        } else {
                            store.setInsights(insights, for: name)
                        }
                    }
                } catch {
                    modelDownload = nil
                    lastError = "Couldn't summarize: \(error.localizedDescription)"
                }
            }
            summarizing.remove(name)
            summarizeQueue.removeFirst()
        }
    }

    func delete(_ note: Note) {
        store.delete(note)
        searchIndex.forget(note.name)
    }

    func restore(_ note: Note) { store.setDiscarded(false, for: note.name) }

    // MARK: People (who is who, by voice)

    /// Display names for a note's "Person N" labels: "You", "Sam"…
    func names(for note: Note) -> [Int: String] {
        note.people.compactMapValues { people.displayName($0) }
    }

    /// Transcript with known names instead of "Person N", for summaries.
    func withNames(_ text: String, note name: String) -> String {
        guard let note = store.notes.first(where: { $0.name == name }), !note.people.isEmpty else { return text }
        let names = self.names(for: note)
        return Speakers.parse(text).map { l in
            guard let n = l.speaker else { return l.text }
            return "\(names[n] ?? Speakers.name(n)): \(l.text)"
        }.joined(separator: "\n")
    }

    /// Voice fingerprints of each person in a note (kept while the app runs, for naming)
    private var noteVoices: [String: [Int: [Float]]] = [:]
    private var identifyQueue: [String] = []

    func queueIdentify(_ name: String) {
        guard Speakers.isIncluded, !identifyQueue.contains(name) else { return }
        identifyQueue.append(name)
        if identifyQueue.count == 1 { Task { await runIdentify() } }
    }

    private func runIdentify() async {
        while let name = identifyQueue.first {
            if let voices = await voices(in: name) {
                let found = people.match(voices)
                if let note = store.notes.first(where: { $0.name == name }) {
                    // Names you picked yourself win over guesses
                    let map = found.merging(note.people) { _, mine in mine }
                    store.setPeople(map, for: name)
                    learnVoices(voices, map: map, note: name)
                }
            }
            identifyQueue.removeFirst()
        }
    }

    /// Gets better at knowing people from everyday conversations, on the phone.
    /// Only voices it's very sure about (0.7+) are learned; near-copies (0.97+) add nothing.
    /// Each conversation teaches once.
    private func learnVoices(_ voices: [Int: [Float]], map: [Int: UUID], note: String) {
        var done = Set(UserDefaults.standard.stringArray(forKey: "voiceLearnedNotes") ?? [])
        guard !done.contains(note) else { return }
        for (n, id) in map {
            guard let v = voices[n] else { continue }
            let s = people.score(v, id)
            if s >= 0.7 && s < 0.97 { people.learn(v, for: id) }
        }
        done.insert(note)
        UserDefaults.standard.set(Array(done.suffix(2000)), forKey: "voiceLearnedNotes")
    }

    private func voices(in name: String) async -> [Int: [Float]]? {
        if let v = noteVoices[name] { return v }
        guard let note = store.notes.first(where: { $0.name == name }),
              let phrases = store.words(for: name), let turns = store.turns(for: name) else { return nil }
        let slots = Speakers.slots(phrases, turns: turns)
        guard !slots.isEmpty else { return nil }
        var out: [Int: [Float]] = [:]
        for (n, slot) in slots {
            let ranges = turns.filter { $0.speaker == slot && $0.end - $0.start >= 1 }.map { ($0.start, $0.end) }
            let url = note.audioURL
            let samples = await Task.detached(priority: .utility) { VoicePrint.samples(url, ranges: ranges) }.value
            if let v = await VoicePrint.of(samples) { out[n] = v }
        }
        noteVoices[name] = out
        return out
    }

    /// "Person N in this note is …": an existing person, or a new one by name.
    func name(_ number: Int, in noteName: String, as person: UUID?, newName: String? = nil) async {
        let voice = await voices(in: noteName)?[number]
        guard let id = people.teach(voice, to: person, newName: newName),
              let note = store.notes.first(where: { $0.name == noteName }) else { return }
        var map = note.people.filter { $0.value != id }
        map[number] = id
        store.setPeople(map, for: noteName)
        rematchAll()
    }

    /// "Person N in this note is me."
    func nameAsMe(_ number: Int, in noteName: String) async {
        guard let voice = await voices(in: noteName)?[number] else { return }
        if let me = people.me { people.teach(voice, to: me.id) } else { people.setMyVoice(voice) }
        guard let me = people.me, let note = store.notes.first(where: { $0.name == noteName }) else { return }
        var map = note.people.filter { $0.value != me.id }
        map[number] = me.id
        store.setPeople(map, for: noteName)
        rematchAll()
    }

    /// Save your own voice from a recording of you talking.
    func saveMyVoice(_ url: URL) async -> Bool {
        let samples = await Task.detached(priority: .userInitiated) { VoicePrint.samples(url) }.value
        guard let v = await VoicePrint.of(samples) else { return false }
        people.setMyVoice(v)
        rematchAll()
        return true
    }

    /// After learning a voice, look again at notes that still have unknown people.
    private func rematchAll() {
        for n in store.notes where !n.discarded && store.turns(for: n.name) != nil {
            queueIdentify(n.name)
        }
    }
}
