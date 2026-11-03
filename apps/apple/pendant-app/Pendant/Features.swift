import AppIntents
import AVFoundation
import EventKit
import SwiftUI
import UIKit

// MARK: - To-dos across all conversations (like Omi's Tasks tab)

struct TodosView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("todosShowDone") private var showDone = false
    @State private var message: String?

    struct Todo: Identifiable {
        let note: Note
        let index: Int
        let item: NoteInsights.Item
        var id: String { "\(note.name)#\(index)" }
    }

    private var todos: [Todo] {
        model.store.notes.filter { !$0.discarded }.flatMap { n in
            (n.insights?.actionItems ?? []).enumerated().map { Todo(note: n, index: $0.offset, item: $0.element) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let open = todos.filter { !$0.item.done }
                Section {
                    if open.isEmpty {
                        Text("Nothing to do. Tasks from your conversations show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(open) { row($0) }
                } header: { Text("To do (\(open.count))") }
                if showDone {
                    let done = todos.filter(\.item.done)
                    if !done.isEmpty {
                        Section("Done (\(done.count))") { ForEach(done) { row($0) } }
                    }
                }
            }
            .navigationTitle("To-dos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Show done", isOn: $showDone)
                        Button("Add all open to Reminders", systemImage: "list.bullet.circle") {
                            add(todos.filter { !$0.item.done })
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .navigationDestination(for: Note.self) { NoteDetailView(name: $0.name) }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func row(_ t: Todo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button { model.store.toggleActionItem(t.index, for: t.note.name) } label: {
                Image(systemName: t.item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(t.item.done ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            NavigationLink(value: t.note) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.item.text).strikethrough(t.item.done).foregroundStyle(t.item.done ? .secondary : .primary)
                    Text("\(t.note.heading) · \(t.note.date.formatted(.dateTime.day().month().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .swipeActions {
            Button("Reminders", systemImage: "list.bullet.circle") { add([t]) }.tint(.orange)
        }
    }

    private func add(_ items: [Todo]) {
        guard !items.isEmpty else { message = "No open tasks."; return }
        Task {
            do {
                let n = try await Reminders.add(items.map { ($0.item.text, "From \"\($0.note.heading)\" in Pendant") })
                message = n == 1 ? "Added to Reminders." : "Added \(n) tasks to Reminders."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct SimpleError: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}

/// Sends tasks to Apple Reminders (stays on your devices / your iCloud, your choice in iOS).
enum Reminders {
    private static let store = EKEventStore()

    static func add(_ items: [(title: String, notes: String)]) async throws -> Int {
        guard try await store.requestFullAccessToReminders() else {
            throw SimpleError("Allow Reminders for Pendant in Settings.")
        }
        guard let list = store.defaultCalendarForNewReminders() else { throw SimpleError("No Reminders list found.") }
        for item in items {
            let r = EKReminder(eventStore: store)
            r.title = item.title
            r.notes = item.notes
            r.calendar = list
            try store.save(r, commit: false)
        }
        try store.commit()
        return items.count
    }
}

// MARK: - Record with the phone (when the pendant isn't around)

@MainActor
final class PhoneRecorder: NSObject, ObservableObject {
    static let shared = PhoneRecorder()
    @Published private(set) var recording = false
    @Published private(set) var started: Date?
    @Published private(set) var level: Float = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?

    /// 16 kHz mono WAV, like the pendant's recordings.
    func start() async -> Bool {
        guard !recording else { return true }
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("phone-\(UUID().uuidString).wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                           AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let r = try AVAudioRecorder(url: u, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { return false }
            recorder = r
            url = u
        } catch { return false }
        recording = true
        started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                self.level = max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50))
            }
        }
        return true
    }

    /// Stops and hands back the file (nil if nothing was recording).
    func stop() -> URL? {
        guard recording else { return nil }
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        recording = false
        started = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }
}

extension AppModel {
    static let shared = AppModel()

    /// Saves a phone recording as a note (P0001_yyyyMMdd_HHmmss.wav) and transcribes it.
    func finishPhoneRecording() {
        showPhoneRecorder = false
        guard let url = PhoneRecorder.shared.stop(), let data = try? Data(contentsOf: url) else { return }
        let next = (store.notes.filter { $0.name.hasPrefix("P") }.map(\.number).max() ?? 0) + 1
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let name = String(format: "P%04d_", next) + f.string(from: Date()) + ".wav"
        store.save(name: name, audio: data)
        try? FileManager.default.removeItem(at: url)
        queueTranscription(name)
    }
}

struct PhoneRecordView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var rec = PhoneRecorder.shared
    @State private var failed = false
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                if let s = rec.started {
                    Text(s, style: .timer).font(.system(size: 56, weight: .light).monospacedDigit())
                } else {
                    Text(failed ? "Allow the microphone for Pendant in Settings." : "Starting…")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Capsule().fill(.red.opacity(0.8))
                    .frame(width: 40 + CGFloat(rec.level) * 220, height: 10)
                    .animation(.easeOut(duration: 0.1), value: rec.level)
                Text("Recording with this phone. It keeps going with the screen locked.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
                Button { model.finishPhoneRecording() } label: {
                    Label("Stop and save", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                .disabled(!rec.recording)
            }
            .padding()
            .navigationTitle("Phone recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if rec.recording { confirmDiscard = true } else { model.showPhoneRecorder = false } }
                }
            }
            .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    if let u = rec.stop() { try? FileManager.default.removeItem(at: u) }
                    model.showPhoneRecorder = false
                }
                Button("Save it", role: .cancel) { model.finishPhoneRecording() }
            }
            .task { if !rec.recording { failed = !(await rec.start()) } }
        }
        .interactiveDismissDisabled(rec.recording)
    }
}

// MARK: - Siri and Shortcuts

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start recording"
    static var description = IntentDescription("Records on your pendant, or with the phone when the pendant isn't connected.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let m = AppModel.shared
        if m.link.connected { m.startLive() } else { m.showPhoneRecorder = true }
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop recording"
    static var description = IntentDescription("Stops the pendant or phone recording and saves it.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let m = AppModel.shared
        if PhoneRecorder.shared.recording { m.finishPhoneRecording() }
        if m.link.liveNote != nil { m.stopLive() }
        return .result()
    }
}

struct PendantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(),
                    phrases: ["Start recording with \(.applicationName)", "Record with \(.applicationName)"],
                    shortTitle: "Start recording", systemImageName: "record.circle")
        AppShortcut(intent: StopRecordingIntent(),
                    phrases: ["Stop recording with \(.applicationName)"],
                    shortTitle: "Stop recording", systemImageName: "stop.circle")
    }
}

// MARK: - Language and custom words

/// Names and words the recognizer should expect (people, places, Hinglish words…).
enum Vocabulary {
    static var words: [String] {
        get { UserDefaults.standard.stringArray(forKey: "customWords") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "customWords") }
    }

    static let languages: [(id: String, name: String)] = [
        ("", "Same as the phone"), ("en-IN", "English (India)"), ("en-US", "English (US)"), ("en-GB", "English (UK)"),
        ("hi-IN", "Hindi"), ("es-ES", "Spanish"), ("fr-FR", "French"), ("de-DE", "German"),
    ]
}

struct VocabularyView: View {
    @AppStorage("transcriptionLanguage") private var language = ""
    @State private var words = Vocabulary.words
    @State private var newWord = ""

    var body: some View {
        List {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(Vocabulary.languages, id: \.id) { Text($0.name).tag($0.id) }
                }
            } footer: {
                Text("English (India) works best for Hinglish. Parakeet v2 is English only.")
            }
            Section {
                HStack {
                    TextField("Add a name or word", text: $newWord)
                        .textInputAutocapitalization(.words)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(words, id: \.self) { Text($0) }
                    .onDelete { words.remove(atOffsets: $0); Vocabulary.words = words }
            } header: { Text("Custom words") } footer: {
                Text("Names of people, places and products you say often, so they're spelled right. Used by Apple Speech and the Apple classic recognizer.")
            }
        }
        .navigationTitle("Language and words")
    }

    private func add() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !words.contains(w) else { return }
        words.append(w)
        Vocabulary.words = words
        newWord = ""
    }
}

// MARK: - Share as PDF

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum PDFExport {
    /// A paged A4 PDF of the title, summary, to-dos and transcript, in a temporary file.
    @MainActor
    static func make(_ note: Note, lines: [SpeakerLine], names: [Int: String]) -> URL? {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var html = "<html><body style='font-family:-apple-system;font-size:11pt;line-height:1.4'>"
        html += "<h2>\(esc(note.heading))</h2><p style='color:#666'>\(esc(note.date.formatted(date: .complete, time: .shortened))) · \(duration(note.seconds))</p>"
        if let i = note.insights {
            if let o = i.overview { html += "<p><i>\(esc(o))</i></p>" }
            html += "<h3>Summary</h3><p>\(esc(i.summary))</p>"
            if !i.actionItems.isEmpty {
                html += "<h3>Action items</h3><ul>" + i.actionItems.map { "<li>\($0.done ? "☑" : "☐") \(esc($0.text))</li>" }.joined() + "</ul>"
            }
        }
        html += "<h3>Transcript</h3>"
        for l in lines {
            let who = l.speaker.map { "<b>\(esc(names[$0] ?? Speakers.name($0))):</b> " } ?? ""
            let at = l.start >= 0 ? "<span style='color:#999'>[\(duration(Int(l.start)))]</span> " : ""
            html += "<p>\(at)\(who)\(esc(l.text))</p>"
        }
        html += "</body></html>"

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 40, dy: 48), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let safe = note.heading.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}
