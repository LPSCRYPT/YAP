import SwiftUI
import UserNotifications

// MARK: - Who talked how much (Plaud and Omi show this)

struct TalkTimeView: View {
    @EnvironmentObject var model: AppModel
    let note: Note

    var body: some View {
        if let phrases = model.store.words(for: note.name), let turns = model.store.turns(for: note.name) {
            let parts = Speakers.talkTime(phrases, turns: turns)
            let total = parts.reduce(0) { $0 + $1.seconds }
            if parts.count >= 2, total > 0 {
                let names = model.names(for: note)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who talked").font(.headline)
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            ForEach(parts, id: \.person) { p in
                                SpeakerLinesView.color(p.person)
                                    .frame(width: max(4, g.size.width * p.seconds / total - 2))
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    FlowRow(parts.map { p in
                        (SpeakerLinesView.color(p.person),
                         "\(names[p.person] ?? Speakers.name(p.person)) \(Int((p.seconds / total * 100).rounded()))% · \(duration(Int(p.seconds)))")
                    })
                }
                Divider()
            }
        }
    }
}

/// Little colored labels that wrap onto new lines.
private struct FlowRow: View {
    let items: [(Color, String)]
    init(_ items: [(Color, String)]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(item.0).frame(width: 8, height: 8)
                    Text(item.1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Evening recap notification (Omi's daily summary, made on the phone)

enum DailyRecap {
    static let id = "daily-recap"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "dailyRecap") }
    static var hour: Int { UserDefaults.standard.object(forKey: "dailyRecapHour") as? Int ?? 21 }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Schedules (or replaces) tonight's recap from today's conversations. Nothing leaves the phone.
    static func refresh(_ notes: [Note]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }
        let cal = Calendar.current
        let today = notes.filter { !$0.discarded && cal.isDateInToday($0.date) }
        guard !today.isEmpty,
              let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()), fire > Date() else { return }
        let minutes = today.reduce(0) { $0 + $1.seconds } / 60
        let open = today.flatMap { $0.insights?.actionItems ?? [] }.filter { !$0.done }
        let topics = today.compactMap { $0.insights?.title }.prefix(3)

        let content = UNMutableNotificationContent()
        content.title = "Your day: \(today.count) conversation\(today.count == 1 ? "" : "s"), \(minutes) min"
        var body: [String] = []
        if !topics.isEmpty { body.append(topics.joined(separator: " · ")) }
        if !open.isEmpty {
            body.append("\(open.count) to-do\(open.count == 1 ? "" : "s"): " + open.prefix(2).map(\.text).joined(separator: "; "))
        }
        content.body = body.isEmpty ? "Tap to look back at today." : body.joined(separator: "\n")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

struct DailyRecapSettings: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("dailyRecap") private var on = false
    @AppStorage("dailyRecapHour") private var hour = 21

    var body: some View {
        Section {
            Toggle("Evening recap", isOn: $on)
                .onChange(of: on) { _, now in
                    Task {
                        if now, !(await DailyRecap.requestPermission()) { on = false }
                        DailyRecap.refresh(model.store.notes)
                    }
                }
            if on {
                Picker("Time", selection: $hour) {
                    ForEach(17..<24) { h in Text(String(format: "%d:00", h)).tag(h) }
                }
                .onChange(of: hour) { _, _ in DailyRecap.refresh(model.store.notes) }
            }
        } footer: {
            Text("A notification with today's conversations and open to-dos. Made on this phone.")
        }
    }
}
