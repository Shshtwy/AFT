import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var store: DeviceStore
    var body: some View {
        HStack {
            Spacer()
            Text(store.statusBarText).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(.bar)
    }
}
