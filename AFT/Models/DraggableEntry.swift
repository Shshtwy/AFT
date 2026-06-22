import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Wraps an MTP entry so it can be dragged out to Finder. The file (or folder,
/// recursively) is downloaded to a temp location only when the drop is accepted.
struct DraggableEntry: Transferable, Sendable {
    let entry: MTPEntry
    let service: any MTPProviding

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { dragged in
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = try await dragged.download(into: dir)
            return SentTransferredFile(url)
        }
    }

    /// Download this entry into `dir`, returning the created file/folder URL.
    func download(into dir: URL) async throws -> URL {
        let dest = dir.appendingPathComponent(entry.name)
        try await write(to: dest)
        return dest
    }

    /// Write this entry's content to an exact destination URL (file → write the
    /// file; folder → create the directory and recurse). Used by the AppKit
    /// file-promise drag, where the destination path is provided by the drop.
    func write(to dest: URL) async throws {
        if entry.isFolder {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let children = try await service.list(parent: entry.id, storage: entry.storageId)
            for child in children {
                try await DraggableEntry(entry: child, service: service)
                    .write(to: dest.appendingPathComponent(child.name))
            }
        } else {
            try await service.download(objectId: entry.id, to: dest) { _ in }
        }
    }
}
