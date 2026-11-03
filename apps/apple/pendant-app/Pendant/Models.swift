import Foundation
import SwiftUI
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Which engine turns saved recordings into text. All of them run on this device.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case auto, apple, parakeetEnglish, parakeetMulti, appleClassic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic (best for this device)"
        case .apple: return "Apple Speech (iOS 26)"
        case .parakeetEnglish: return "Parakeet v2, English"
        case .parakeetMulti: return "Parakeet v3, 25 languages"
        case .appleClassic: return "Apple classic"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Apple Speech on iOS 26, otherwise Parakeet for English, otherwise Apple classic."
        case .apple: return "Built into iOS 26. Small download from Apple, managed by iOS."
        case .parakeetEnglish: return "NVIDIA model, very accurate for English. About 450 MB."
        case .parakeetMulti: return "NVIDIA model for English and 24 European languages. About 480 MB."
        case .appleClassic: return "Older Apple recognizer. No download; less accurate."
        }
    }

    static var current: TranscriptionEngine {
        UserDefaults.standard.string(forKey: "transcriptionEngine").flatMap(Self.init) ?? .auto
    }
}

/// The models the app can download, what's on the device, and how big it is.
@MainActor
final class ModelManager: ObservableObject {
    enum Item: String, CaseIterable, Identifiable {
        case appleSpeech, parakeetV2, parakeetV3, qwen, speakers, voiceID
        var id: String { rawValue }

        var name: String {
            switch self {
            case .appleSpeech: return "Apple Speech"
            case .parakeetV2: return "Parakeet v2 (English)"
            case .parakeetV3: return "Parakeet v3 (multilingual)"
            case .qwen: return "Qwen3 0.6B"
            case .speakers: return "Who's speaking (Sortformer)"
            case .voiceID: return "Voice fingerprints (WeSpeaker)"
            }
        }

        var purpose: String {
            switch self {
            case .appleSpeech: return "Transcription"
            case .parakeetV2, .parakeetV3: return "Transcription"
            case .qwen: return "Summaries"
            case .speakers: return "Telling people apart"
            case .voiceID: return "Knowing who is who"
            }
        }

        /// Rough download size, shown before downloading
        var approxSize: String {
            switch self {
            case .appleSpeech: return "managed by iOS"
            case .parakeetV2: return "about 450 MB"
            case .parakeetV3: return "about 480 MB"
            case .qwen: return "about 350 MB"
            case .speakers: return "about 60 MB"
            case .voiceID: return "about 30 MB"
            }
        }

        /// A substring of the folder name the model is saved in
        fileprivate var folderKey: String {
            switch self {
            case .appleSpeech: return ""
            case .parakeetV2: return "parakeet-tdt-0.6b-v2"
            case .parakeetV3: return "parakeet-tdt-0.6b-v3"
            case .qwen: return "qwen3-0.6b"
            case .speakers: return "sortformer"
            case .voiceID: return "speaker-diarization"
            }
        }
    }

    enum State: Equatable {
        case checking, missing, downloading, ready(bytes: Int64?), unavailable(String)
    }

    @Published private(set) var states: [Item: State] = [:]
    @Published var error: String?

    init() { Task { await refresh() } }

    func state(_ item: Item) -> State { states[item] ?? .checking }

    func refresh() async {
        for item in Item.allCases where states[item] != .downloading {
            states[item] = await check(item)
        }
    }

    var totalBytes: Int64 {
        states.values.reduce(0) { sum, s in
            if case .ready(let b?) = s { return sum + b }
            return sum
        }
    }

    private func check(_ item: Item) async -> State {
        switch item {
        case .appleSpeech:
            switch await Transcriber.appleSpeechStatus() {
            case .some(true): return .ready(bytes: nil)
            case .some(false): return .missing
            case .none: return .unavailable("Needs iOS 26")
            }
        case .qwen:
            guard LocalModel.isIncluded else { return .unavailable("Not in this build") }
        case .parakeetV2, .parakeetV3, .speakers, .voiceID:
            #if canImport(FluidAudio)
            break
            #else
            return .unavailable("Not in this build")
            #endif
        }
        let key = item.folderKey
        let bytes = await Task.detached(priority: .utility) { () -> Int64? in
            let dirs = Self.folders(matching: key)
            guard !dirs.isEmpty else { return nil }
            return dirs.reduce(0) { $0 + Self.size($1) }
        }.value
        guard let bytes, bytes > 1_000_000 else { return .missing }
        return .ready(bytes: bytes)
    }

    func download(_ item: Item) {
        guard states[item] != .downloading else { return }
        states[item] = .downloading
        Task {
            do {
                switch item {
                case .appleSpeech:
                    try await Transcriber.installAppleSpeech()
                case .qwen:
                    try await LocalModel.preload()
                #if canImport(FluidAudio)
                case .parakeetV2:
                    _ = try await AsrModels.download(version: .v2)
                case .parakeetV3:
                    _ = try await AsrModels.download(version: .v3)
                case .speakers:
                    _ = try await SpeakerModels.shared.load()
                case .voiceID:
                    _ = try await DiarizerModels.downloadIfNeeded()
                #else
                default: break
                #endif
                }
            } catch {
                self.error = "Couldn't download \(item.name): \(error.localizedDescription)"
            }
            states[item] = await check(item)
        }
    }

    /// Removes a downloaded model. It downloads again the next time it's needed.
    func remove(_ item: Item) {
        guard item != .appleSpeech else { return }
        for dir in Self.folders(matching: item.folderKey) { try? FileManager.default.removeItem(at: dir) }
        Task { states[item] = await check(item) }
    }

    // MARK: Files

    /// Where the model libraries save their files.
    nonisolated private static var roots: [URL] {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return [support.appendingPathComponent("FluidAudio/Models"),
                caches.appendingPathComponent("huggingface/hub"),
                caches.appendingPathComponent("models"),
                docs.appendingPathComponent("huggingface")]
    }

    /// Model folders (up to 3 levels down) whose name contains `key`.
    nonisolated private static func folders(matching key: String) -> [URL] {
        guard !key.isEmpty else { return [] }
        let fm = FileManager.default
        var out: [URL] = []
        func walk(_ dir: URL, depth: Int) {
            guard depth <= 3, let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for u in items where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if u.lastPathComponent.lowercased().contains(key) { out.append(u) } else { walk(u, depth: depth + 1) }
            }
        }
        for r in roots { walk(r, depth: 0) }
        return out
    }

    nonisolated private static func size(_ dir: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys) else { return 0 }
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}

/// Settings → Models: pick engines and manage downloads.
struct ModelsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var models = ModelManager()
    @AppStorage("transcriptionEngine") private var engine = TranscriptionEngine.auto.rawValue
    @State private var removing: ModelManager.Item?

    var body: some View {
        List {
            Section {
                Picker("Transcription", selection: $engine) {
                    ForEach(TranscriptionEngine.allCases) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title)
                            Text(e.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(e.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Transcription") } footer: {
                Text("Used for new recordings and \"Transcribe again\". Live transcription always uses the fastest one.")
            }

            Section {
                Picker("Summaries", selection: $model.summaryEngine) {
                    ForEach(SummaryEngine.allCases) { Text($0.title).tag($0) }
                }
                if let why = model.summaryUnavailable {
                    Text(why).font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Summaries") }

            Section {
                ForEach(ModelManager.Item.allCases) { item in row(item) }
            } header: { Text("Downloads") } footer: {
                Text("Everything runs on this device. Models download once from Hugging Face (Apple Speech from Apple), then work offline. \(models.totalBytes > 0 ? "In use: \(bytes(models.totalBytes))." : "")")
            }
        }
        .navigationTitle("Models")
        .refreshable { await models.refresh() }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let r = removing { models.remove(r) } }
        } message: { Text("It downloads again the next time it's needed. Your notes aren't touched.") }
        .alert("Download failed", isPresented: Binding(
            get: { models.error != nil }, set: { if !$0 { models.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(models.error ?? "") }
    }

    @ViewBuilder private func row(_ item: ModelManager.Item) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(caption(item)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch models.state(item) {
            case .checking, .downloading:
                ProgressView()
            case .missing:
                Button { models.download(item) } label: { Image(systemName: "arrow.down.circle").font(.title2) }
                    .buttonStyle(.borderless)
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
            case .unavailable:
                EmptyView()
            }
        }
        .swipeActions {
            if case .ready = models.state(item), item != .appleSpeech {
                Button("Remove", role: .destructive) { removing = item }
            }
        }
    }

    private func caption(_ item: ModelManager.Item) -> String {
        switch models.state(item) {
        case .checking: return item.purpose
        case .downloading: return "\(item.purpose) · downloading…"
        case .missing: return "\(item.purpose) · not downloaded (\(item.approxSize))"
        case .ready(let b): return "\(item.purpose) · on device\(b.map { " · \(bytes($0))" } ?? "")"
        case .unavailable(let why): return "\(item.purpose) · \(why)"
        }
    }

    private func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
}

/// Settings: models, pendant options, people.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section {
                NavigationLink { ModelsView() } label: {
                    Label("Models and downloads", systemImage: "cpu")
                }
                NavigationLink { VocabularyView() } label: {
                    Label("Language and custom words", systemImage: "character.book.closed")
                }
                NavigationLink { PeopleView() } label: {
                    Label(model.people.me == nil ? "Teach Pendant your voice" : "People", systemImage: "person.2")
                }
            }
            Section("Pendant") {
                Toggle("Free up pendant after download", isOn: $model.deleteAfterDownload)
                Toggle("Split on 2 min of quiet, hide silent clips", isOn: $model.autoSplit)
            }
            Section {
                LabeledContent("Notes", value: "\(model.store.notes.filter { !$0.discarded }.count)")
                LabeledContent("Recorded", value: totalTime)
            } footer: {
                Text("Your notes, audio and voices stay on this device.")
            }
        }
        .navigationTitle("Settings")
    }

    private var totalTime: String {
        let s = model.store.notes.filter { !$0.discarded }.reduce(0) { $0 + $1.seconds }
        return s >= 3600 ? String(format: "%d h %02d min", s / 3600, (s % 3600) / 60) : "\(s / 60) min"
    }
}
