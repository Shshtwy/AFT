import Foundation
@testable import AFT

actor MockMTPService: MTPProviding {
    var tree: [UInt32: [MTPEntry]]   // parentId -> children
    var free: UInt64 = 104_710_000_000
    var connectCount = 0

    init(tree: [UInt32: [MTPEntry]]) { self.tree = tree }

    func connect() async throws -> DeviceInfo {
        connectCount += 1
        return DeviceInfo(name: "Pixel 10 Pro XL", storageId: 1)
    }
    func disconnect() async {}
    func freeSpace() async -> UInt64 { free }
    func list(parent: UInt32, storage: UInt32) async throws -> [MTPEntry] {
        tree[parent] ?? []
    }
    func download(objectId: UInt32, to url: URL,
                  onProgress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        onProgress(TransferProgress(sent: 100, total: 100))
    }
    func upload(from url: URL, parent: UInt32, storage: UInt32,
                onProgress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MTPEntry {
        MTPEntry(id: 999, storageId: storage, parentId: parent,
                 name: url.lastPathComponent, isFolder: false, size: 1, modified: Date(), children: [])
    }
    func createFolder(name: String, parent: UInt32, storage: UInt32) async throws -> MTPEntry {
        MTPEntry(id: 998, storageId: storage, parentId: parent, name: name,
                 isFolder: true, size: 0, modified: nil, children: [])
    }
    func delete(objectId: UInt32, name: String) async throws {}
    func rename(objectId: UInt32, to name: String) async throws {}
    func folderSize(of folderId: UInt32, storage: UInt32) async throws -> UInt64 {
        var total: UInt64 = 0
        for child in tree[folderId] ?? [] {
            if child.isFolder { total += try await folderSize(of: child.id, storage: storage) }
            else { total += child.size }
        }
        return total
    }
}
