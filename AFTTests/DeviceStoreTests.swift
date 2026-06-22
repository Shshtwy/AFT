import XCTest
@testable import AFT

@MainActor
final class DeviceStoreTests: XCTestCase {
    private func sampleTree() -> [UInt32: [MTPEntry]] {
        let root: [MTPEntry] = [
            MTPEntry(id: 10, storageId: 1, parentId: 0, name: "DCIM",
                     isFolder: true, size: 0, modified: nil, children: nil),
            MTPEntry(id: 11, storageId: 1, parentId: 0, name: "screen.png",
                     isFolder: false, size: 372_000, modified: Date(), children: []),
        ]
        let dcim: [MTPEntry] = [
            MTPEntry(id: 20, storageId: 1, parentId: 10, name: "img.jpg",
                     isFolder: false, size: 1000, modified: Date(), children: []),
        ]
        return [0: root, 10: dcim]
    }

    func testConnectLoadsRoot() async {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.deviceName, "Pixel 10 Pro XL")
        XCTAssertEqual(store.rootEntries.count, 2)
        XCTAssertEqual(store.freeSpace, 104_710_000_000)
    }

    func testOpenFolderNavigates() async {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        await store.open(folderId: 10)
        XCTAssertEqual(store.rootEntries.count, 1)
        XCTAssertEqual(store.rootEntries.first?.name, "img.jpg")
        XCTAssertTrue(store.canGoBack)
    }

    func testBackRestoresParent() async {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        await store.open(folderId: 10)
        await store.goBack()
        XCTAssertEqual(store.rootEntries.count, 2)
        XCTAssertFalse(store.canGoBack)
    }

    func testStatusBarString() async {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        store.selection = [11]
        XCTAssertTrue(store.statusBarText.hasPrefix("1 of 2 selected, "))
    }

    func testDownloadCompletes() async throws {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        await store.download(ids: [11], to: dir)
        XCTAssertNil(store.activeTransfer)
        XCTAssertNil(store.errorMessage)
    }

    func testCalculateFolderSize() async {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        let dcim = store.rootEntries.first { $0.name == "DCIM" }!
        XCTAssertEqual(store.sizeDisplay(for: dcim), "--")  // not yet computed
        await store.calculateSize(for: dcim)
        XCTAssertEqual(store.folderSizes[dcim.id], 1000)     // one 1000-byte child
        XCTAssertFalse(store.calculatingSizes.contains(dcim.id))
    }

    func testUploadReloadsFolder() async {
        let store = DeviceStore(service: MockMTPService(tree: sampleTree()))
        await store.connect()
        let f = URL(fileURLWithPath: "/etc/hosts")
        await store.upload(urls: [f])
        XCTAssertNil(store.activeTransfer)
    }
}
