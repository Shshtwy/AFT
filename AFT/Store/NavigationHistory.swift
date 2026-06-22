import Foundation

struct NavigationHistory {
    private(set) var stack: [UInt32]
    private(set) var index: Int

    init(root: UInt32) { stack = [root]; index = 0 }

    var current: UInt32 { stack[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < stack.count - 1 }

    mutating func push(_ folder: UInt32) {
        if canGoForward { stack.removeSubrange((index + 1)...) }
        stack.append(folder); index += 1
    }
    mutating func back() -> UInt32? {
        guard canGoBack else { return nil }
        index -= 1; return current
    }
    mutating func forward() -> UInt32? {
        guard canGoForward else { return nil }
        index += 1; return current
    }
}
