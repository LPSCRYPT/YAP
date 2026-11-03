import AVFoundation
import SwiftUI
import UIKit

// MARK: - Notes list

struct NotesView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResultsView(query: query)
                } else {
                    Section { PendantCard() }

                    if model.live.active && !model.showLive {
                        Section {
                            Button { model.showLive = true } label: {
                                HStack {
                                    Image(systemName: "waveform").foregroundStyle(.red).symbolEffect(.pulse)
                                    Text(model.live.text.isEmpty ? "Recording live. Tap to watch." : model.live.text)
                                        .lineLimit(2).foregroundStyle(.primary)
                                }
                            }
                        }
                    }

                    if let p = model.modelDownload {
                        Section {
                            ProgressView("Downloading the summary model (one time)", value: p).font(.caption)
                        }
                    }

                    let shown = model.store.notes.filter { !$0.discarded }
                    if shown.isEmpty {
                        Section {
                            Text("Notes you record on the pendant show up here.").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(days(shown), id: \.day) { group in
                        Section(dayTitle(group.day)) {
                            ForEach(group.notes) { note in
                                NavigationLink(value: note) { NoteRow(note: note) }
                            }
                            .onDelete { idx in idx.map { group.notes[$0] }.forEach(model.delete) }
                        }
                    }
                    let hidden = model.store.notes.filter(\.discarded)
                    if !hidden.isEmpty {
                        Section {
                            NavigationLink { DiscardedView() } label: {
                                Label("Discarded (\(hidden.count))", systemImage: "archivebox")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search conversations")
            .navigationTitle("Pendant")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
            .navigationDestination(for: Note.self) { NoteDetailView(name: $0.name) }
            .sheet(isPresented: $model.showLive, onDismiss: { if !model.live.active { model.live.clear() } }) {
                LiveView().environmentObject(model)
            }
            .refreshable { model.sync() }
            .alert("Something went wrong", isPresented: Binding(
                get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.lastError ?? "") }
        }
    }

    private struct Day { let day: Date; let notes: [Note] }

    /// Notes grouped by the day they were recorded, newest first.
    private func days(_ notes: [Note]) -> [Day] {
        Dictionary(grouping: notes) { Calendar.current.startOfDay(for: $0.date) }
            .map { Day(day: $0.key, notes: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private func dayTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct PendantCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(model.link.connected ? .blue : .gray).frame(width: 10, height: 10)
                Text(model.link.status).font(.subheadline)
                Spacer()
                if model.link.connected {
                    Button("Sync", action: model.sync).buttonStyle(.bordered)
                }
            }
            if model.link.connected {
                if model.link.liveNote != nil {
                    Button(role: .destructive, action: model.stopLive) {
                        Label("Stop recording", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.startLive()
                } label: {
                        Label("Start live", systemImage: "waveform").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let name = model.link.downloading {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading Note \(Int(name.dropFirst().prefix(4)) ?? 0)")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: model.link.progress)
                }
            } else if model.link.connected {
                Text(model.newOnDevice == 0 ? "All notes are on your phone"
                                            : "\(model.newOnDevice) new on pendant")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NoteRow: View {
    @EnvironmentObject var model: AppModel
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.heading).font(.headline).lineLimit(1)
                Spacer()
                Text(duration(note.seconds)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 6) {
                if let c = note.insights?.category {
                    Label(c.label, systemImage: c.symbol).labelStyle(.titleAndIcon)
                    Text("·")
                }
                Text(note.date, format: .dateTime.weekday().day().month().hour().minute())
            }
            .font(.caption).foregroundStyle(.secondary)
            if model.transcribing.contains(note.name) {
                Label(model.transcribeProgress[note.name].map { "Transcribing… \(Int($0 * 100))%" } ?? "Transcribing…",
                      systemImage: "waveform").font(.caption).foregroundStyle(.blue)
            } else if let t = note.insights?.overview ?? note.insights?.summary ?? note.transcript {
                Text(t).font(.subheadline).lineLimit(2).foregroundStyle(.secondary)
            }
            if let open = note.insights?.actionItems.filter({ !$0.done }).count, open > 0 {
                Label("\(open) to do", systemImage: "checklist").font(.caption).foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Note detail

struct NoteDetailView: View {
    @EnvironmentObject var model: AppModel
    let name: String
    @StateObject private var player = Player()
    @State private var naming: Int?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var copied = false

    private var note: Note? { model.store.notes.first { $0.name == name } }

    var body: some View {
        if let note {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.heading).font(.title2.bold())
                        HStack(spacing: 6) {
                            if let c = note.insights?.category {
                                Label(c.label, systemImage: c.symbol)
                                Text("·")
                            }
                            Text(note.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                        if note.insights?.title != nil {
                            Text(note.title).font(.caption).foregroundStyle(.tertiary)
                        }
                    }

                    PlayerBar(player: player, url: note.audioURL, seconds: note.seconds)

                    Divider()

                    if model.transcribing.contains(note.name) {
                        if let p = model.transcribeProgress[note.name], p > 0 {
                            ProgressView("Transcribing on your device… \(Int(p * 100))%", value: p)
                        } else {
                            ProgressView("Transcribing on your device…")
                        }
                        // Show what's done so far
                        if let ph = model.partialPhrases[note.name], !ph.isEmpty {
                            lines(AppModel.paragraphs(ph), note: note, tapNames: false)
                        }
                    } else if let t = note.transcript, !t.isEmpty {
                        SummarySection(note: note)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Transcript").font(.headline)
                                Spacer()
                                if model.labelingSpeakers.contains(note.name) {
                                    Label("Finding who spoke…", systemImage: "person.2.wave.2")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else if t != AppModel.noSpeech {
                                    Text("Tap a line to play it").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            lines(model.displayLines(for: note), note: note, tapNames: true)
                        }
                    } else {
                        Button("Transcribe") { model.queueTranscription(note.name) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle(note.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let t = note.transcript, !t.isEmpty {
                            ShareLink("Share text", item: shareText(note, transcript: model.withNames(t, note: note.name)))
                            Button("Copy text", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = shareText(note, transcript: model.withNames(t, note: note.name))
                                copied = true
                            }
                        }
                        ShareLink("Share audio", item: note.audioURL)
                        if note.insights != nil {
                            Button("Rename", systemImage: "pencil") { newTitle = note.heading; renaming = true }
                        }
                        if note.transcript != nil {
                            Button("Summarize again", systemImage: "sparkles") {
                                model.store.setInsights(nil, for: note.name)
                                model.queueSummary(note.name)
                            }
                        }
                        Button("Transcribe again", systemImage: "waveform") {
                            model.store.setTranscript("", for: note.name)
                            model.queueTranscription(note.name)
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onDisappear { player.stop() }
            .sheet(item: Binding(get: { naming.map(SpeakerPick.init) }, set: { naming = $0?.number })) { pick in
                NamePersonSheet(noteName: note.name, number: pick.number).environmentObject(model)
            }
            .alert("Rename", isPresented: $renaming) {
                TextField("Title", text: $newTitle)
                Button("Save") {
                    let t = newTitle.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty, var i = note.insights { i.title = t; model.store.setInsights(i, for: note.name) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
        } else {
            Text("Note deleted").foregroundStyle(.secondary)
        }
    }

    /// Transcript lines; tapping one plays the audio from there, and the line being played is highlighted.
    private func lines(_ l: [SpeakerLine], note: Note, tapNames: Bool) -> some View {
        let playing = player.time > 0 ? l.last(where: { $0.start >= 0 && $0.start <= player.time + 0.15 })?.id : nil
        return SpeakerLinesView(lines: l, names: model.names(for: note),
                                onTapSpeaker: tapNames ? { naming = $0 } : nil,
                                current: playing,
                                onTapLine: { line in
                                    guard line.start >= 0 else { return }
                                    player.seek(note.audioURL, to: max(0, line.start - 0.3))
                                })
    }
}

/// Play/pause, a scrubber, skip 15 s and playback speed.
struct PlayerBar: View {
    @ObservedObject var player: Player
    let url: URL
    let seconds: Int

    var body: some View {
        let total = player.length > 0 ? player.length : Double(max(1, seconds))
        VStack(spacing: 6) {
            Slider(value: Binding(get: { min(player.time, total) },
                                  set: { player.seek(url, to: $0, play: player.playing) }),
                   in: 0...total)
            HStack {
                Text(duration(Int(player.time))).monospacedDigit()
                Spacer()
                Text("-" + duration(Int(max(0, total - player.time)))).monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 32) {
                Button { player.cycleRate() } label: {
                    Text(player.rate == 1 ? "1×" : player.rate == 1.5 ? "1.5×" : "2×")
                        .font(.subheadline.bold().monospacedDigit()).frame(width: 44)
                }
                Button { player.skip(url, by: -15) } label: { Image(systemName: "gobackward.15").font(.title2) }
                Button { player.toggle(url) } label: {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52))
                }
                Button { player.skip(url, by: 15) } label: { Image(systemName: "goforward.15").font(.title2) }
                Color.clear.frame(width: 44, height: 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }
}

private func shareText(_ note: Note, transcript: String) -> String {
    guard let i = note.insights else { return transcript }
    var out = i.title.map { "\($0)\n\n" } ?? ""
    out += "Summary\n\(i.summary)\n\n"
    if !i.actionItems.isEmpty {
        out += "Action items\n" + i.actionItems.map { ($0.done ? "[x] " : "[ ] ") + $0.text }.joined(separator: "\n") + "\n\n"
    }
    return out + "Transcript\n" + transcript
}

/// Summary and checkable action items, made on the phone.
struct SummarySection: View {
    @EnvironmentObject var model: AppModel
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let i = note.insights {
                if let o = i.overview, !o.isEmpty {
                    Text(o).font(.callout.italic()).foregroundStyle(.secondary)
                }
                Text("Summary").font(.headline)
                Text(i.summary).textSelection(.enabled)
                if !i.actionItems.isEmpty {
                    Text("Action items").font(.headline).padding(.top, 4)
                    ForEach(Array(i.actionItems.enumerated()), id: \.offset) { idx, item in
                        Button { model.store.toggleActionItem(idx, for: note.name) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? .green : .secondary)
                                Text(item.text)
                                    .strikethrough(item.done)
                                    .foregroundStyle(item.done ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if model.summarizing.contains(note.name) {
                if let p = model.modelDownload {
                    ProgressView("Downloading summary model (one time)…", value: p)
                } else {
                    ProgressView("Summarizing on your iPhone…")
                }
            } else if note.transcript == AppModel.noSpeech {
                EmptyView()
            } else if let why = model.summaryUnavailable {
                Label(why, systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button("Summarize", systemImage: "sparkles") { model.queueSummary(note.name) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
    }
}

/// Small audio player for one note at a time.
final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var time: Double = 0
    @Published var length: Double = 0
    @Published var rate: Float = 1
    private var player: AVAudioPlayer?
    private var timer: Timer?

    private func prepare(_ url: URL) {
        guard player?.url != url else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.enableRate = true
        player?.prepareToPlay()
        length = player?.duration ?? 0
    }

    func toggle(_ url: URL) { playing ? pause() : play(url) }

    func play(_ url: URL) {
        prepare(url)
        player?.rate = rate
        player?.play()
        playing = player?.isPlaying ?? false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            self.time = p.currentTime
        }
    }

    func pause() {
        player?.pause()
        playing = false
    }

    /// Jump to `t` seconds (and play, unless `play` is false).
    func seek(_ url: URL, to t: Double, play: Bool = true) {
        prepare(url)
        guard let p = player else { return }
        p.currentTime = max(0, min(t, p.duration))
        time = p.currentTime
        if play { self.play(url) }
    }

    func skip(_ url: URL, by d: Double) {
        prepare(url)
        seek(url, to: (player?.currentTime ?? 0) + d, play: playing)
    }

    func cycleRate() {
        rate = rate == 1 ? 1.5 : (rate == 1.5 ? 2 : 1)
        player?.rate = rate
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        playing = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playing = false
        time = 0
        timer?.invalidate()
    }
}

func duration(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

// MARK: - Live transcript

/// Words appear as you talk. Made on the phone from the pendant's live audio.
struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var live: LiveTranscriber { model.live }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if live.text.isEmpty {
                            Text(live.active ? "Listening…" : (model.link.liveNote == nil ? "Starting the pendant…" : "Listening…"))
                                .foregroundStyle(.secondary)
                        } else {
                            SpeakerLinesView(lines: live.lines, partial: live.partialText)
                            if live.active, live.voiceModel == .loading {
                                Label("Getting the voice model ready (one-time download)…", systemImage: "person.2.wave.2")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else if live.voiceModel == .unavailable, Speakers.isIncluded {
                                Label("Couldn't load the voice model, so people aren't told apart this time.",
                                      systemImage: "person.2.slash")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if live.paused {
                            Label("Pendant out of range. It keeps recording, and the text catches up when it's back.",
                                  systemImage: "antenna.radiowaves.left.and.right.slash")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        if let p = live.problem {
                            Label(p, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                        }
                        if !live.active && live.startedAt != nil {
                            Label("Saved. The title and summary will be in your notes in a moment.",
                                  systemImage: "checkmark.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: live.text) { _, _ in
                    withAnimation { scroll.scrollTo("end", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if live.active || model.link.liveNote != nil {
                        Button(role: .destructive, action: model.stopLive) {
                            Label("Stop recording", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                    } else {
                        Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if live.active, let start = live.startedAt {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(start, style: .timer).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Speakers

/// Transcript as chat bubbles, one per turn, with "Person 1", "Person 2"… like Omi.
struct SpeakerLinesView: View {
    let lines: [SpeakerLine]
    var partial: String = ""
    /// Known names for person numbers ("You", "Sam")
    var names: [Int: String] = [:]
    /// Tap a name to say who it is
    var onTapSpeaker: ((Int) -> Void)?
    /// The line being played right now (highlighted)
    var current: Int?
    /// Tap a line to play the audio from there
    var onTapLine: ((SpeakerLine) -> Void)?

    static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal]
    static func color(_ n: Int?) -> Color { n.map { colors[($0 - 1) % colors.count] } ?? .gray }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines) { line in
                bubble(line, Text(line.text)
                       + Text(line.id == lines.last?.id && !partial.isEmpty ? " " + partial : "").foregroundColor(.secondary))
            }
            if lines.isEmpty, !partial.isEmpty {
                bubble(nil, Text(partial).foregroundColor(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ line: SpeakerLine?, _ text: Text) -> some View {
        let who = line?.speaker
        let isCurrent = line != nil && line?.id == current
        let tappable = onTapLine != nil && (line?.start ?? -1) >= 0
        return HStack(alignment: .top, spacing: 10) {
            if let who {
                Text("\(who)")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Self.color(who)))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let who {
                        Button { onTapSpeaker?(who) } label: {
                            HStack(spacing: 3) {
                                Text(names[who] ?? Speakers.name(who)).font(.caption.bold())
                                if onTapSpeaker != nil, names[who] == nil {
                                    Image(systemName: "pencil").font(.caption2)
                                }
                            }
                            .foregroundStyle(Self.color(who))
                        }
                        .buttonStyle(.plain)
                        .disabled(onTapSpeaker == nil)
                    }
                    if tappable, let s = line?.start {
                        Text(duration(Int(s))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                text
                    .padding(.horizontal, who == nil ? 0 : 12).padding(.vertical, who == nil ? 0 : 8)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(who == nil ? Color.clear : Self.color(who).opacity(isCurrent ? 0.3 : 0.12)))
                    .overlay(alignment: .leading) {
                        if who == nil && isCurrent {
                            Rectangle().fill(Color.accentColor).frame(width: 3).offset(x: -8)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if tappable, let line { onTapLine?(line) } }
                    .contextMenu {
                        if let line {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = line.text }
                            if tappable { Button("Play from here", systemImage: "play") { onTapLine?(line) } }
                        }
                    }
            }
        }
    }

    /// Reads a saved transcript back into lines.
    static func parse(_ text: String) -> [SpeakerLine] { Speakers.parse(text) }
}

// MARK: - People

struct SpeakerPick: Identifiable {
    let number: Int
    var id: Int { number }
}

/// "Who is Person 2?": pick someone you know, or type a new name. Their voice is remembered.
struct NamePersonSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let noteName: String
    let number: Int
    @State private var newName = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.people.people) { p in
                        Button(p.isMe ? "You" : p.name) { save(p.id, nil) }
                    }
                    if model.people.me == nil {
                        Button("This is me") { saveMe() }
                    }
                }
                Section("Someone new") {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.words)
                        .onSubmit { save(nil, newName) }
                    Button("Save") { save(nil, newName) }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section {
                    Text("Pendant remembers this voice (as a fingerprint, on this phone) and puts the name on it in other conversations.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(saving)
            .overlay { if saving { ProgressView() } }
            .navigationTitle("Who is \(Speakers.name(number))?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(_ id: UUID?, _ name: String?) {
        saving = true
        Task {
            await model.name(number, in: noteName, as: id, newName: name)
            dismiss()
        }
    }

    private func saveMe() {
        saving = true
        Task {
            await model.nameAsMe(number, in: noteName)
            dismiss()
        }
    }
}

/// Your voice and the people Pendant knows.
struct PeopleView: View {
    @EnvironmentObject var model: AppModel
    @State private var enrolling = false
    @State private var renaming: Person?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                Button { enrolling = true } label: {
                    Label(model.people.me == nil ? "Teach Pendant your voice (20 s)" : "Record your voice again",
                          systemImage: "waveform.badge.mic")
                }
            } footer: {
                Text("Then your words show as \"You\" instead of Person 1. Only a voice fingerprint is kept, on this phone.")
            }
            Section("People") {
                let others = model.people.people.filter { !$0.isMe }
                if others.isEmpty {
                    Text("Tap a Person label in a conversation to name them.").foregroundStyle(.secondary)
                }
                ForEach(others) { p in
                    Button(p.name) { renaming = p; renameText = p.name }
                        .foregroundStyle(.primary)
                }
                .onDelete { idx in idx.map { others[$0].id }.forEach(model.people.remove) }
            }
        }
        .navigationTitle("People")
        .sheet(isPresented: $enrolling) { EnrollVoiceView().environmentObject(model) }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let p = renaming { model.people.rename(p.id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Read a few sentences out loud for 20 seconds.
struct EnrollVoiceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rec = VoiceRecorder()
    @State private var state = "Read this out loud in your normal voice:"
    @State private var busy = false
    @State private var started = false

    private let script = """
    Hi, this is my voice. I'm teaching my pendant how I sound, so it can tell when I'm the one talking. \
    Yesterday I went for a walk, had some coffee with a friend, and we talked about plans for the weekend. \
    I like trying new food, listening to music, and building things. Today I need to finish a few tasks, \
    reply to some messages, and maybe call my family in the evening.
    """

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(state).font(.headline).multilineTextAlignment(.center)
                ScrollView { Text(script).font(.title3).padding() }
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))
                if rec.recording {
                    ProgressView(value: rec.elapsed, total: VoiceRecorder.seconds)
                    Capsule().fill(.blue).frame(width: 40 + CGFloat(rec.level) * 200, height: 8)
                        .animation(.easeOut(duration: 0.1), value: rec.level)
                }
                if busy { ProgressView("Learning your voice…") }
                Button {
                    if rec.recording { rec.stop() } else { start() }
                } label: {
                    Label(rec.recording ? "Stop" : "Start recording", systemImage: rec.recording ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(busy)
            }
            .padding()
            .navigationTitle("Your voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { rec.stop(); dismiss() } } }
            .onChange(of: rec.recording) { _, now in if !now && started { finish() } }
        }
    }

    private func start() {
        Task {
            if await rec.start() { started = true; state = "Keep reading…" }
            else { state = "Allow the microphone for Pendant in Settings." }
        }
    }

    private func finish() {
        started = false
        busy = true
        state = "Saving…"
        Task {
            let ok = await model.saveMyVoice(rec.url)
            busy = false
            if ok { dismiss() } else { state = "Couldn't learn your voice. Try again in a quieter spot, reading a bit longer." }
        }
    }
}

/// Recordings where nobody talked. Hidden from the list, never deleted without asking.
struct DiscardedView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let hidden = model.store.notes.filter(\.discarded)
        List {
            Section {
                ForEach(hidden) { note in
                    NavigationLink(value: note) { NoteRow(note: note) }
                        .swipeActions(edge: .leading) {
                            Button("Restore") { model.restore(note) }.tint(.blue)
                        }
                }
                .onDelete { idx in idx.map { hidden[$0] }.forEach(model.delete) }
            } footer: {
                Text("No speech was found in these. Swipe right to put one back, left to delete it.")
            }
        }
        .navigationTitle("Discarded")
    }
}
