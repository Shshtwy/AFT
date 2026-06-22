import Foundation

struct TransferProgress: Equatable {
    var sent: UInt64
    var total: UInt64
}

struct DeviceInfo: Equatable, Sendable {
    let name: String
    let storageId: UInt32
}

protocol MTPProviding: Actor {
    func connect() async throws -> DeviceInfo
    func disconnect() async
    func list(parent: UInt32, storage: UInt32) async throws -> [MTPEntry]
    func freeSpace() async -> UInt64
    func download(objectId: UInt32, to url: URL,
                  onProgress: @escaping @Sendable (TransferProgress) -> Void) async throws
    func upload(from url: URL, parent: UInt32, storage: UInt32,
                onProgress: @escaping @Sendable (TransferProgress) -> Void) async throws -> MTPEntry
    func createFolder(name: String, parent: UInt32, storage: UInt32) async throws -> MTPEntry
    func delete(objectId: UInt32, name: String) async throws
    func rename(objectId: UInt32, to name: String) async throws
    /// Total size of a folder's contents, computed by recursively summing files.
    func folderSize(of folderId: UInt32, storage: UInt32) async throws -> UInt64
}
