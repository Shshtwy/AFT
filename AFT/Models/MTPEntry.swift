import Foundation

struct MTPEntry: Identifiable, Hashable {
    let id: UInt32
    let storageId: UInt32
    let parentId: UInt32
    var name: String
    let isFolder: Bool
    let size: UInt64
    let modified: Date?
    var children: [MTPEntry]?   // nil = not yet loaded

    init(id: UInt32, storageId: UInt32, parentId: UInt32, name: String,
         isFolder: Bool, size: UInt64, modified: Date?, children: [MTPEntry]? = nil) {
        self.id = id; self.storageId = storageId; self.parentId = parentId
        self.name = name; self.isFolder = isFolder; self.size = size
        self.modified = modified; self.children = children
    }
}

extension MTPEntry {
    init(_ o: MTPEntryObjC) {
        self.init(id: o.objectId, storageId: o.storageId, parentId: o.parentId,
                  name: o.name, isFolder: o.isFolder, size: o.size,
                  modified: o.modified, children: o.isFolder ? nil : [])
    }
}
