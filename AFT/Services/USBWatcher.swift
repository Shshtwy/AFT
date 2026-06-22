import Foundation
import IOKit
import IOKit.usb

final class USBWatcher {
    var onAttach: (() -> Void)?
    var onDetach: (() -> Void)?

    /// USB vendor IDs of common Android phone makers. Used to tell "a phone is
    /// plugged in but not in MTP mode" from "nothing connected".
    private static let androidVendorIDs: Set<Int> = [
        0x18d1, // Google / Pixel
        0x04e8, // Samsung
        0x22b8, // Motorola
        0x2717, // Xiaomi
        0x12d1, // Huawei
        0x2a70, // OnePlus / Oppo
        0x05c6, // Qualcomm (generic Android)
        0x0bb4, // HTC
        0x19d2, // ZTE
        0x1004, // LG
        0x0fce, // Sony
    ]

    /// True if any connected USB device looks like an Android phone, regardless
    /// of whether it currently exposes an MTP interface.
    static func isAndroidPhoneConnected() -> Bool {
        let match = IOServiceMatching(kIOUSBDeviceClassName)
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }
        var found = false
        while case let dev = IOIteratorNext(iter), dev != 0 {
            if let num = IORegistryEntryCreateCFProperty(dev, "idVendor" as CFString,
                                                         kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber,
               androidVendorIDs.contains(num.intValue) {
                found = true
            }
            IOObjectRelease(dev)
            if found { break }
        }
        return found
    }

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    func start() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let match = IOServiceMatching(kIOUSBDeviceClassName)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let addedCB: IOServiceMatchingCallback = { ctx, iter in
            let me = Unmanaged<USBWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            me.drain(iter); me.onAttach?()
        }
        let removedCB: IOServiceMatchingCallback = { ctx, iter in
            let me = Unmanaged<USBWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            me.drain(iter); me.onDetach?()
        }

        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
            match, addedCB, selfPtr, &addedIter)
        drain(addedIter)   // arm + handle already-connected devices

        IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
            match, removedCB, selfPtr, &removedIter)
        drain(removedIter)
    }

    private func drain(_ iter: io_iterator_t) {
        while case let obj = IOIteratorNext(iter), obj != 0 { IOObjectRelease(obj) }
    }

    func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
    }
    deinit { stop() }
}
