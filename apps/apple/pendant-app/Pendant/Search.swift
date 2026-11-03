import Foundation
import NaturalLanguage
import SwiftUI

/// Search across every conversation, on the phone.
/// Two signals, like Omi's search: matching words (title, summary, to-dos, transcript, names)
/// and meaning (Apple's built-in sentence embeddings, so "trip" also finds "flight to Delhi").
/// The meaning index lives in memory only (rebuilt each launch); nothing is written to disk.
@MainActor
final class SearchIndex {
    struct Hit: Identifiable {
        let note: Note
        let snippet: String
        let score: Double
        var id: String { note.name }
    }

    private struct Entry: Codable {
        var key: String              // changes when the note's text changes
        var vectors: [[Float]]
        var texts: [String]
    }

    private var entries: [String: Entry] = [:]
    private lazy var embedding: NLEmbedding? = {
        let lang = NLLanguage(rawValue: Locale.current.language.languageCode?.identifier ?? "en")
        return NLEmbedding.sentenceEmbedding(for: lang) ?? NLEmbedding.sentenceEmbedding(for: .english)
    }()


    /// The searchable pieces of a note: its heading/summary, then the transcript in ~300 character parts.
    private static func pieces(_ note: Note, names: [Int: String]) -> [String] {
        var out: [String] = []
        if let i = note.insights {
            out.append([i.title, i.overview, i.summary].compactMap { $0 }.joined(separator: ". "))
            if !i.actionItems.isEmpty { out.append(i.actionItems.map(\.text).joined(separator: ". ")) }
        }
        if let t = note.transcript, t != AppModel.noSpeech {
            let lines = Speakers.parse(t).map { l in
                l.speaker.map { "\(names[$0] ?? Speakers.name($0)): \(l.text)" } ?? l.text
            }
            out += Summarizer.split(lines.joined(separator: " "), size: 300)
        }
        return out.filter { !$0.isEmpty }
    }

    private func entry(for note: Note, names: [Int: String]) -> Entry {
        let texts = Self.pieces(note, names: names)
        let key = "\(texts.joined().hashValue)"
        if let e = entries[note.name], e.key == key { return e }
        let vectors = texts.map { t in embedding?.vector(for: t).map { $0.map(Float.init) } ?? [] }
        let e = Entry(key: key, vectors: vectors, texts: texts)
        entries[note.name] = e
        return e
    }

    func search(_ query: String, in notes: [Note], names: (Note) -> [Int: String]) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let words = q.lowercased().split(separator: " ").map(String.init)
        let qv = embedding?.vector(for: q).map { $0.map(Float.init) }
        var hits: [Hit] = []
        for note in notes where !note.discarded {
            let e = entry(for: note, names: names(note))
            var best = 0.0
            var snippet = e.texts.first ?? ""
            for (i, text) in e.texts.enumerated() {
                let lower = text.lowercased()
                let found = words.filter { lower.contains($0) }.count
                var score = Double(found) / Double(max(1, words.count))   // 1.0 = every word is there
                if let qv, i < e.vectors.count, !e.vectors[i].isEmpty {
                    score += max(0, Double(PeopleStore.cosine(qv, e.vectors[i])) - 0.3)   // meaning
                }
                if score > best { best = score; snippet = text }
            }
            if best >= 0.35 { hits.append(Hit(note: note, snippet: snippet, score: best)) }
        }
        return hits.sorted { $0.score > $1.score }.prefix(30).map { $0 }
    }

    func forget(_ name: String) { entries[name] = nil }
}

/// Search results under the search bar.
struct SearchResultsView: View {
    @EnvironmentObject var model: AppModel
    let query: String

    var body: some View {
        let hits = model.search(query)
        if hits.isEmpty {
            Section { Text("Nothing found for \"\(query)\"").foregroundStyle(.secondary) }
        } else {
            Section("\(hits.count) found") {
                ForEach(hits) { hit in
                    NavigationLink(value: hit.note) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.note.heading).font(.headline).lineLimit(1)
                            Text(hit.note.date, format: .dateTime.weekday().day().month().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(hit.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
    }
}
