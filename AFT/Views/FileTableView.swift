import SwiftUI

/// The connected-device file browser: an AppKit NSTableView (reliable
/// selection / double-click / drag) with the faint Android watermark behind it.
struct FileTableView: View {
    @EnvironmentObject var store: DeviceStore

    var body: some View {
        FileListView(store: store)
            .background(
                Image("AndroidWatermark").resizable().scaledToFit()
                    .frame(width: 320).opacity(0.12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            )
    }
}
