import SwiftUI

@main
struct QuickRemindApp: App {
    @State private var store = ReminderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    store.checkAccess()
                    if store.permission == .notDetermined {
                        await store.requestAccess()
                    }
                    _ = await AlarmService.shared.requestAuthorization()
                }
        }
    }
}
