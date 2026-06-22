import SwiftUI

@main
struct AFTApp: App {
    @StateObject private var store = DeviceStore(service: MTPService())
    private let watcher = USBWatcher()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 480)
                .task {
                    watcher.onAttach = { Task { await store.connect() } }
                    watcher.onDetach = { Task { await store.disconnect() } }
                    watcher.start()
                    store.startMonitoring()   // poll until a device appears
                }
        }
        .windowStyle(.titleBar)
    }
}
