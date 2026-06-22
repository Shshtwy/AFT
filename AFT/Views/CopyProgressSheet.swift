import SwiftUI

struct CopyProgressSheet: View {
    let state: TransferState
    @EnvironmentObject var store: DeviceStore

    private var fraction: Double {
        state.total == 0 ? 0 : Double(state.sent) / Double(state.total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.itemCount > 1
                 ? "Copying \(state.itemCount) items"
                 : "Copying \"\(state.currentName)\"").font(.headline)
            ProgressView(value: fraction)
            HStack {
                Text("\(AFTByteFormatter.string(state.sent)) of \(AFTByteFormatter.string(state.total))")
                Spacer()
                Text(TimeRemainingFormatter.string(state.secondsRemaining))
            }.font(.callout).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 420)
    }
}
