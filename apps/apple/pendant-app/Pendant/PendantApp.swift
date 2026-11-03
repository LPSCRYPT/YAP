import SwiftUI

@main
struct PendantApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            NotesView()
                .environmentObject(model)
        }
    }
}
