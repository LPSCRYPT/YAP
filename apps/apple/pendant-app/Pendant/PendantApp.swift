import SwiftUI

@main
struct PendantApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                NotesView()
                    .tabItem { Label("Conversations", systemImage: "waveform") }
                TodosView()
                    .tabItem { Label("To-dos", systemImage: "checklist") }
            }
            .environmentObject(model)
            .sheet(isPresented: $model.showPhoneRecorder) {
                PhoneRecordView().environmentObject(model)
            }
        }
    }
}
