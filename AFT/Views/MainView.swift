import SwiftUI

struct IdentifiedTransfer: Identifiable {
    let id = UUID(); let state: TransferState
}

struct MainView: View {
    @EnvironmentObject var store: DeviceStore
    @State private var showNewFolder = false
    @State private var newFolderName = "untitled folder"

    var body: some View {
        Group {
            if store.isConnected {
                FileTableView()
            } else {
                WaitingView(store: store)
            }
        }
        .safeAreaInset(edge: .bottom) { if store.isConnected { StatusBarView() } }
        .navigationTitle(store.isConnected ? store.deviceName : "Android File Transfer")
        .toolbar { AFTToolbar(store: store, showNewFolder: $showNewFolder) }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await store.newFolder(named: newFolderName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .sheet(item: Binding(
            get: { store.activeTransfer.map { IdentifiedTransfer(state: $0) } },
            set: { _ in })) { wrapper in
            CopyProgressSheet(state: wrapper.state)
        }
    }
}
