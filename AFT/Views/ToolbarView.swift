import SwiftUI

struct AFTToolbar: ToolbarContent {
    @ObservedObject var store: DeviceStore
    @Binding var showNewFolder: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await store.goBack() } } label: {
                Image(systemName: "chevron.left")
            }.disabled(!store.canGoBack)
            Button { Task { await store.goForward() } } label: {
                Image(systemName: "chevron.right")
            }.disabled(!store.canGoForward)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if store.isCalculatingAll { store.cancelCalculateAll() }
                else { store.startCalculateAllVisibleFolders() }
            } label: {
                Image(systemName: store.isCalculatingAll ? "stop.circle" : "sum")
            }
            .help(store.isCalculatingAll ? "Stop calculating folder sizes"
                                         : "Calculate sizes of all visible folders")
            .disabled(!store.isConnected)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showNewFolder = true } label: {
                Image(systemName: "folder.badge.plus")
            }.disabled(!store.isConnected)
        }
    }
}
