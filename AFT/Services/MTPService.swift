import Foundation

actor MTPService: MTPProviding {
    private let bridge = MTPBridge()

    func connect() async throws -> DeviceInfo {
        // A missing/charging-only device is normal while polling — surface it
        // as a typed connectFailed the store can suppress, not a raw NSError.
        do { try bridge.openFirstDevice() }
        catch { throw MTPError.connectFailed }
        return DeviceInfo(name: bridge.deviceFriendlyName() ?? "Android device",
                          storageId: bridge.primaryStorageId())
    }

    func disconnect() async { bridge.close() }

    func freeSpace() async -> UInt64 { bridge.freeSpaceBytes() }

    func list(parent: UInt32, storage: UInt32) async throws -> [MTPEntry] {
        let arr = try bridge.listFolder(parent, storageId: storage)
        return arr.map(MTPEntry.init).sorted(by: folderFirst)
    }

    func download(objectId: UInt32, to url: URL,
                  onProgress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        try bridge.downloadObject(objectId, toPath: url.path,
            progress: { onProgress(TransferProgress(sent: $0, total: $1)) })
    }

    func upload(from url: URL, parent: UInt32, storage: UInt32,
                onProgress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MTPEntry {
        var err: NSError?
        let newId = bridge.uploadFile(url.path, toParent: parent, storageId: storage,
            progress: { onProgress(TransferProgress(sent: $0, total: $1)) }, error: &err)
        if newId == 0 { throw err.map(MTPError.init) ?? MTPError.copyFailed(url.lastPathComponent) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        return MTPEntry(id: newId, storageId: storage, parentId: parent,
                        name: url.lastPathComponent, isFolder: false,
                        size: size ?? 0, modified: Date(), children: [])
    }

    func createFolder(name: String, parent: UInt32, storage: UInt32) async throws -> MTPEntry {
        var err: NSError?
        let newId = bridge.createFolder(name, inParent: parent, storageId: storage, error: &err)
        if newId == 0 { throw err.map(MTPError.init) ?? MTPError.createFolderFailed }
        return MTPEntry(id: newId, storageId: storage, parentId: parent, name: name,
                        isFolder: true, size: 0, modified: nil, children: [])
    }

    func delete(objectId: UInt32, name: String) async throws {
        try bridge.deleteObject(objectId)
    }

    func rename(objectId: UInt32, to name: String) async throws {
        try bridge.renameObject(objectId, toName: name)
    }

    func folderSize(of folderId: UInt32, storage: UInt32) async throws -> UInt64 {
        try Task.checkCancellation()
        var total: UInt64 = 0
        let children = try bridge.listFolder(folderId, storageId: storage).map(MTPEntry.init)
        for child in children {
            try Task.checkCancellation()
            if child.isFolder {
                total += try await folderSize(of: child.id, storage: storage)
            } else {
                total += child.size
            }
        }
        return total
    }

    private func folderFirst(_ a: MTPEntry, _ b: MTPEntry) -> Bool {
        if a.isFolder != b.isFolder { return a.isFolder }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
