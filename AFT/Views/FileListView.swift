import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// File-promise provider that carries the MTP entry to download on drop.
final class EntryPromiseProvider: NSFilePromiseProvider {
    var draggable: DraggableEntry?
}

/// AppKit NSTableView-backed file list. SwiftUI's Table has unreliable cell
/// gestures (finicky selection, no drag-out); NSTableView gives native
/// selection, double-click, file-promise drag-out, and file drop-in.
struct FileListView: NSViewRepresentable {
    @ObservedObject var store: DeviceStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = 24
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))

        let name = NSTableColumn(identifier: .init("name"))
        name.title = "Name"; name.width = 320; name.minWidth = 180
        name.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        let mod = NSTableColumn(identifier: .init("mod"))
        mod.title = "Last Modified"; mod.width = 180
        mod.sortDescriptorPrototype = NSSortDescriptor(key: "mod", ascending: true)
        let size = NSTableColumn(identifier: .init("size"))
        size.title = "Size"; size.width = 90
        size.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
        table.addTableColumn(name)
        table.addTableColumn(mod)
        table.addTableColumn(size)
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        // Drag-in (upload) and drag-out (promise) support.
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        context.coordinator.tableView = table

        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(Coordinator.menuOpen(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Save to…", action: #selector(Coordinator.menuSaveTo(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Calculate Size", action: #selector(Coordinator.menuCalcSize(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Calculate All Folder Sizes", action: #selector(Coordinator.menuCalcAll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Cancel Size Calculation", action: #selector(Coordinator.menuCancelSize(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(Coordinator.menuDelete(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = context.coordinator }
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.store = store
        context.coordinator.syncIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                             NSFilePromiseProviderDelegate {
        var store: DeviceStore
        weak var tableView: NSTableView?
        private var rowIDs: [UInt32] = []
        private var isSyncingSelection = false
        private let promiseQueue = OperationQueue()
        private var lastSizes: [UInt32: UInt64] = [:]
        private var lastCalculating: Set<UInt32> = []

        init(store: DeviceStore) { self.store = store }

        /// Reload rows only when the visible set changed; always sync selection.
        func syncIfNeeded() {
            guard let table = tableView else { return }
            let ids = store.visibleRows.map(\.id)
            if ids != rowIDs {
                rowIDs = ids
                table.reloadData()
            } else if store.folderSizes != lastSizes || store.calculatingSizes != lastCalculating {
                // Folder-size results changed: refresh just the Size column,
                // preserving selection and scroll.
                let col = table.column(withIdentifier: .init("size"))
                if col >= 0 {
                    table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count),
                                     columnIndexes: IndexSet(integer: col))
                }
            }
            lastSizes = store.folderSizes
            lastCalculating = store.calculatingSizes
            // Sync selection store -> table without re-entrancy.
            let wanted = IndexSet(store.visibleRows.enumerated()
                .filter { store.selection.contains($0.element.id) }.map(\.offset))
            if wanted != table.selectedRowIndexes {
                isSyncingSelection = true
                table.selectRowIndexes(wanted, byExtendingSelection: false)
                isSyncingSelection = false
            }
        }

        private var rows: [OutlineRow] { store.visibleRows }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard row < rows.count else { return nil }
            let item = rows[row]
            switch tableColumn?.identifier.rawValue {
            case "name":
                return nameCell(for: item)
            case "mod":
                let text = item.entry.modified.map {
                    $0.formatted(date: .numeric, time: .shortened)
                } ?? "--"
                return textCell(text, secondary: true, alignment: .left)
            case "size":
                return textCell(store.sizeDisplay(for: item.entry),
                                secondary: true, alignment: .right)
            default:
                return nil
            }
        }

        private func textCell(_ string: String, secondary: Bool,
                              alignment: NSTextAlignment) -> NSView {
            let cell = NSTableCellView()
            let tf = NSTextField(labelWithString: string)
            tf.alignment = alignment
            tf.textColor = secondary ? .secondaryLabelColor : .labelColor
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func nameCell(for item: OutlineRow) -> NSView {
            let cell = NSTableCellView()

            let disclosure = NSButton()
            disclosure.bezelStyle = .inline
            disclosure.isBordered = false
            disclosure.imagePosition = .imageOnly
            disclosure.target = self
            disclosure.action = #selector(toggleDisclosure(_:))
            disclosure.translatesAutoresizingMaskIntoConstraints = false
            if item.entry.isFolder {
                let sym = store.isExpanded(item.entry.id) ? "chevron.down" : "chevron.right"
                disclosure.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
                disclosure.contentTintColor = .secondaryLabelColor
            } else {
                disclosure.image = nil
                disclosure.isEnabled = false
            }

            let icon = NSImageView()
            let symbol = item.entry.isFolder ? "folder.fill" : "doc"
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon.contentTintColor = item.entry.isFolder ? .controlAccentColor : .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false

            let tf = NSTextField(labelWithString: item.entry.name)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(disclosure)
            cell.addSubview(icon)
            cell.addSubview(tf)
            cell.textField = tf

            let indent = CGFloat(item.depth) * 16 + 4
            NSLayoutConstraint.activate([
                disclosure.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: indent),
                disclosure.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                disclosure.widthAnchor.constraint(equalToConstant: 14),
                icon.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        // MARK: - Actions

        @objc func toggleDisclosure(_ sender: NSButton) {
            guard let table = tableView else { return }
            let row = table.row(for: sender)
            guard row >= 0, row < rows.count else { return }
            let entry = rows[row].entry
            Task { await store.toggleExpand(entry) }
        }

        @objc func doubleClicked(_ sender: Any) {
            guard let table = tableView else { return }
            let row = table.clickedRow
            guard row >= 0, row < rows.count else { return }
            let entry = rows[row].entry
            if entry.isFolder { Task { await store.open(folderId: entry.id) } }
        }

        /// Ids the menu acts on: the clicked row if it's outside the selection,
        /// otherwise the whole selection.
        private func menuTargetIDs() -> Set<UInt32> {
            guard let table = tableView else { return [] }
            let clicked = table.clickedRow
            if clicked >= 0, clicked < rows.count {
                let id = rows[clicked].id
                if !store.selection.contains(id) { return [id] }
            }
            return store.selection
        }

        @objc func menuOpen(_ sender: Any) {
            guard let id = menuTargetIDs().first, let e = store.entry(for: id), e.isFolder else { return }
            Task { await store.open(folderId: id) }
        }

        @objc func menuSaveTo(_ sender: Any) {
            let ids = menuTargetIDs()
            guard !ids.isEmpty else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let dir = panel.url {
                Task { await store.download(ids: ids, to: dir) }
            }
        }

        @objc func menuCalcSize(_ sender: Any) {
            for id in menuTargetIDs() {
                if let e = store.entry(for: id), e.isFolder {
                    store.startSizeCalculation(for: e)
                }
            }
        }

        @objc func menuCalcAll(_ sender: Any) {
            store.startCalculateAllVisibleFolders()
        }

        @objc func menuCancelSize(_ sender: Any) {
            for id in menuTargetIDs() where store.calculatingSizes.contains(id) {
                store.cancelSizeCalculation(for: id)
            }
            if store.isCalculatingAll { store.cancelCalculateAll() }
        }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            let folders = menuTargetIDs().compactMap { store.entry(for: $0) }.filter(\.isFolder)
            switch item.action {
            case #selector(menuOpen(_:)):
                return folders.count == 1 || (menuTargetIDs().count == 1)
            case #selector(menuCalcSize(_:)):
                return folders.contains { store.folderSizes[$0.id] == nil && !store.calculatingSizes.contains($0.id) }
            case #selector(menuCalcAll(_:)):
                return !store.isCalculatingAll
            case #selector(menuCancelSize(_:)):
                return store.isCalculatingAll || folders.contains { store.calculatingSizes.contains($0.id) }
            default:
                return true
            }
        }

        @objc func menuDelete(_ sender: Any) {
            let ids = menuTargetIDs()
            guard !ids.isEmpty else { return }
            Task { await store.delete(ids: ids) }
        }

        func tableView(_ tableView: NSTableView,
                       sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sort = tableView.sortDescriptors.first else { return }
            switch sort.key {
            case "name": store.sortField = .name
            case "mod":  store.sortField = .modified
            case "size": store.sortField = .size
            default: break
            }
            store.sortAscending = sort.ascending
            // Order changed → visibleRows differ → syncIfNeeded reloads.
            syncIfNeeded()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table = tableView else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { idx -> UInt32? in
                idx < rows.count ? rows[idx].id : nil
            })
            store.selection = ids
        }

        // MARK: - Drag out (file promise)

        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < rows.count else { return nil }
            let entry = rows[row].entry
            let ext = (entry.name as NSString).pathExtension
            let typeID: String
            if entry.isFolder {
                typeID = UTType.folder.identifier
            } else {
                typeID = UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
            }
            let provider = EntryPromiseProvider(fileType: typeID, delegate: self)
            provider.draggable = store.draggable(entry)
            return provider
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 fileNameForType fileType: String) -> String {
            (filePromiseProvider as? EntryPromiseProvider)?.draggable?.entry.name ?? "file"
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            promiseQueue
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            guard let draggable = (filePromiseProvider as? EntryPromiseProvider)?.draggable else {
                completionHandler(nil); return
            }
            Task {
                do { try await draggable.write(to: url); completionHandler(nil) }
                catch { completionHandler(error) }
            }
        }

        // MARK: - Drag in (upload)

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            info.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) ? .copy : []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
            Task { await store.upload(urls: urls) }
            return true
        }
    }
}
