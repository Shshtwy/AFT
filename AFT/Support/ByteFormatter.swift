import Foundation

enum AFTByteFormatter {
    static func string(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(bytes))
    }
    static func folderDisplay(isFolder: Bool) -> String { isFolder ? "--" : "" }
    static func sizeColumn(_ entry: MTPEntry) -> String {
        entry.isFolder ? "--" : string(entry.size)
    }
}
