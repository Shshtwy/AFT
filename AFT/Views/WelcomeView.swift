import SwiftUI

/// Shown whenever no MTP device is connected. Distinguishes "a phone is plugged
/// in but charging-only" from "nothing connected", and always keeps waiting.
struct WaitingView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(spacing: 14) {
            if store.phoneNeedsMTP {
                Image(systemName: "iphone.gen3.badge.exclamationmark")
                    .font(.system(size: 48)).foregroundStyle(.orange)
                Text("Phone detected — not in File Transfer mode").font(.title3)
                Text("On your phone, tap the USB notification and choose\n“File Transfer” / “Android Auto” (MTP).")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView().controlSize(.large)
                Text("Waiting for an Android device…").font(.title3)
                Text("Connect your phone with a USB cable, unlock it, and choose\nFile Transfer (MTP) mode.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
