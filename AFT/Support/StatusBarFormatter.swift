import Foundation

enum StatusBarFormatter {
    static func string(selected: Int, total: Int, freeBytes: UInt64) -> String {
        let free = AFTByteFormatter.string(freeBytes)
        if selected > 0 {
            return "\(selected) of \(total) selected, \(free) available"
        }
        if total == 1 { return "1 item, \(free) available" }
        return "\(total) items, \(free) available"
    }
}
