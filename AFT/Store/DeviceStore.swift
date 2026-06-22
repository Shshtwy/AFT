import Foundation
import SwiftUI

/// Which column the file list is sorted by.
enum SortField { case name, modified, size }

/// One visible line in the outline: an entry plus its indentation depth.
struct OutlineRow: Identifiable, Hashable {
    let entry: MTPEntry
    let depth: Int
    var id: UInt32 { entry.id }
}

struct TransferState: Equatable {
    var title: String
    var itemCount: Int
    var currentName: String
    var sent: UInt64
    var total: UInt64
    var secondsRemaining: Double?
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var phoneNeedsMTP = false
    @Published var deviceName = ""
    @Published var rootEntries: [MTPEntry] = []
    @Published var expanded = Set<UInt32>()
    @Published var selection = Set<UInt32>()

    /// Lazily-loaded children for expanded folders, keyed by folder object id.
    private var childrenCache: [UInt32: [MTPEntry]] = [:]
    @Published var freeSpace: UInt64 = 0
    @Published var activeTransfer: TransferState?
    @Published var errorMessage: String?
    /// Computed folder sizes (object id -> total bytes), cached for the session.
    @Published var folderSizes: [UInt32: UInt64] = [:]
    /// Folders whose size is currently being computed.
    @Published var calculatingSizes: Set<UInt32> = []
    /// True while the "calculate all visible folders" batch is running.
    @Published var isCalculatingAll = false
    /// Column sort state for the file list.
    @Published var sortField: SortField = .name
    @Published var sortAscending = true

    private var sizeTasks: [UInt32: Task<Void, Never>] = [:]
    private var calcAllTask: Task<Void, Never>?

    private let service: any MTPProviding
    private var storageId: UInt32 = 0
    private var history = NavigationHistory(root: 0)
    private var monitorTask: Task<Void, Never>?

    init(service: any MTPProviding) { self.service = service }

    /// Continuously poll for a device until connected. Charging-only phones are
    /// not an error — we just keep waiting and hint the user to switch to MTP.
    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, !self.isConnected { await self.connect() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var statusBarText: String {
        StatusBarFormatter.string(selected: selection.count,
                                  total: rootEntries.count, freeBytes: freeSpace)
    }

    /// Flattened, depth-tagged rows for the outline: root entries plus the
    /// cached children of any expanded folder, recursively, in sort order.
    var visibleRows: [OutlineRow] {
        var rows: [OutlineRow] = []
        func walk(_ entries: [MTPEntry], depth: Int) {
            for e in sortedLevel(entries) {
                rows.append(OutlineRow(entry: e, depth: depth))
                if e.isFolder, expanded.contains(e.id), let kids = childrenCache[e.id] {
                    walk(kids, depth: depth + 1)
                }
            }
        }
        walk(rootEntries, depth: 0)
        return rows
    }

    /// Sort one level: folders always first, then by the active column/direction.
    /// Size sort uses a folder's computed size when known (else 0).
    private func sortedLevel(_ entries: [MTPEntry]) -> [MTPEntry] {
        entries.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let ascending: Bool
            switch sortField {
            case .name:
                ascending = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified:
                ascending = (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            case .size:
                ascending = sizeValue(a) < sizeValue(b)
            }
            return sortAscending ? ascending : !ascending
        }
    }

    private func sizeValue(_ e: MTPEntry) -> UInt64 {
        e.isFolder ? (folderSizes[e.id] ?? 0) : e.size
    }

    func isExpanded(_ id: UInt32) -> Bool { expanded.contains(id) }

    /// Find a visible entry (root level or an expanded folder's child) by id.
    func entry(for id: UInt32) -> MTPEntry? {
        visibleRows.first { $0.entry.id == id }?.entry
    }

    /// A drag-out payload for an entry; downloads on drop (see DraggableEntry).
    func draggable(_ entry: MTPEntry) -> DraggableEntry {
        DraggableEntry(entry: entry, service: service)
    }

    /// What to show in the Size column for an entry: a file's size, a folder's
    /// computed size if known, "Calculating…" while in progress, else "--".
    func sizeDisplay(for entry: MTPEntry) -> String {
        guard entry.isFolder else { return AFTByteFormatter.string(entry.size) }
        if calculatingSizes.contains(entry.id) { return "Calculating…" }
        if let bytes = folderSizes[entry.id] { return AFTByteFormatter.string(bytes) }
        return "--"
    }

    /// Recursively compute a folder's size on the background actor and cache it.
    /// Cancellation-aware (see MTPService.folderSize).
    func calculateSize(for entry: MTPEntry) async {
        guard entry.isFolder, !calculatingSizes.contains(entry.id) else { return }
        calculatingSizes.insert(entry.id)
        defer { calculatingSizes.remove(entry.id) }
        do {
            folderSizes[entry.id] = try await service.folderSize(of: entry.id, storage: entry.storageId)
        } catch is CancellationError {
            // cancelled — leave the folder uncomputed
        } catch { present(error) }
    }

    /// Start (or no-op) a cancellable size calculation for one folder.
    func startSizeCalculation(for entry: MTPEntry) {
        guard entry.isFolder, sizeTasks[entry.id] == nil, folderSizes[entry.id] == nil else { return }
        let id = entry.id
        sizeTasks[id] = Task { [weak self] in
            await self?.calculateSize(for: entry)
            self?.sizeTasks[id] = nil
        }
    }

    func cancelSizeCalculation(for id: UInt32) {
        sizeTasks[id]?.cancel()
        sizeTasks[id] = nil
    }

    /// Calculate sizes for every visible folder that isn't cached, one by one.
    func startCalculateAllVisibleFolders() {
        guard calcAllTask == nil else { return }
        isCalculatingAll = true
        let folders = visibleRows.map(\.entry).filter { $0.isFolder && folderSizes[$0.id] == nil }
        calcAllTask = Task { [weak self] in
            guard let self else { return }
            for folder in folders {
                if Task.isCancelled { break }
                await self.calculateSize(for: folder)
            }
            self.isCalculatingAll = false
            self.calcAllTask = nil
        }
    }

    func cancelCalculateAll() {
        calcAllTask?.cancel()
        calcAllTask = nil
        isCalculatingAll = false
    }

    /// Invalidate cached sizes for the current folder and its ancestors (their
    /// totals include the modified folder), plus the parents of specific items.
    private func invalidateSizeCache(parentsOf ids: Set<UInt32> = []) {
        for fid in history.stack[0...history.index] { folderSizes[fid] = nil }
        for id in ids {
            if let parent = entry(for: id)?.parentId { folderSizes[parent] = nil }
        }
    }

    func toggleExpand(_ entry: MTPEntry) async {
        guard entry.isFolder else { return }
        if expanded.contains(entry.id) {
            expanded.remove(entry.id)
            return
        }
        if childrenCache[entry.id] == nil {
            do { childrenCache[entry.id] = try await service.list(parent: entry.id, storage: storageId) }
            catch { present(error); return }
        }
        expanded.insert(entry.id)
    }

    func connect() async {
        guard !isConnecting, !isConnected else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let info = try await service.connect()
            let free = await service.freeSpace()
            // A device can "open" while still locked / access-not-granted: storage
            // enumerates as id 0 / 0 bytes. Treat that as not-ready, but DO NOT
            // close — the handle stays open and the next poll re-reads storage on
            // the same handle (closing/reopening leaks the USB claim on macOS).
            guard info.storageId != 0, free > 0 else {
                phoneNeedsMTP = USBWatcher.isAndroidPhoneConnected()
                return
            }
            deviceName = info.name
            storageId = info.storageId
            history = NavigationHistory(root: 0)
            freeSpace = free
            await reload()
            isConnected = true
            phoneNeedsMTP = false
        } catch {
            // No MTP device is normal while polling — never alert. If a phone is
            // physically plugged in, hint the user to switch it to File Transfer.
            phoneNeedsMTP = USBWatcher.isAndroidPhoneConnected()
        }
    }

    func disconnect() async {
        sizeTasks.values.forEach { $0.cancel() }; sizeTasks = [:]
        cancelCalculateAll()
        await service.disconnect()
        isConnected = false; deviceName = ""; rootEntries = []; selection = []
        folderSizes = [:]; calculatingSizes = []
    }

    func open(folderId: UInt32) async {
        history.push(folderId)
        await reload()
    }
    func goBack() async { if history.back() != nil { await reload() } }
    func goForward() async { if history.forward() != nil { await reload() } }

    func newFolder(named name: String) async {
        do {
            _ = try await service.createFolder(name: name, parent: history.current, storage: storageId)
            invalidateSizeCache()
            await reload()
        } catch { present(error) }
    }

    func delete(ids: Set<UInt32>) async {
        for id in ids {
            let name = entry(for: id)?.name ?? ""
            do { try await service.delete(objectId: id, name: name) }
            catch { present(error); break }
        }
        invalidateSizeCache(parentsOf: ids)
        selection = []; await reload()
    }

    func rename(id: UInt32, to name: String) async {
        do { try await service.rename(objectId: id, to: name); await reload() }
        catch { present(error) }
    }

    func reload() async {
        // Navigating to a new folder level invalidates the expansion tree.
        expanded.removeAll()
        childrenCache.removeAll()
        do { rootEntries = try await service.list(parent: history.current, storage: storageId) }
        catch { present(error) }
    }

    func present(_ error: Error) {
        errorMessage = (error as? MTPError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Transfers

    func download(ids: Set<UInt32>, to directory: URL) async {
        let entries = visibleRows.map(\.entry).filter { ids.contains($0.id) && !$0.isFolder }
        guard !entries.isEmpty else { return }
        let start = Date()
        for (i, e) in entries.enumerated() {
            activeTransfer = TransferState(title: "Copy", itemCount: entries.count,
                currentName: e.name, sent: 0, total: e.size, secondsRemaining: nil)
            let dest = directory.appendingPathComponent(e.name)
            do {
                try await service.download(objectId: e.id, to: dest) { [weak self] p in
                    Task { @MainActor in
                        self?.updateProgress(p, index: i, of: entries.count, start: start)
                    }
                }
            } catch { present(error); break }
        }
        activeTransfer = nil
    }

    func upload(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        let start = Date()
        for (i, url) in urls.enumerated() {
            let total = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            activeTransfer = TransferState(title: "Copy", itemCount: urls.count,
                currentName: url.lastPathComponent, sent: 0, total: total ?? 0, secondsRemaining: nil)
            do {
                _ = try await service.upload(from: url, parent: history.current,
                                             storage: storageId) { [weak self] p in
                    Task { @MainActor in
                        self?.updateProgress(p, index: i, of: urls.count, start: start)
                    }
                }
            } catch { present(error); break }
        }
        activeTransfer = nil
        invalidateSizeCache()
        await reload()
    }

    private func updateProgress(_ p: TransferProgress, index: Int, of count: Int, start: Date) {
        guard var t = activeTransfer else { return }
        t.sent = p.sent; t.total = p.total
        let elapsed = Date().timeIntervalSince(start)
        if p.sent > 0, elapsed > 0.5 {
            let rate = Double(p.sent) / elapsed
            t.secondsRemaining = rate > 0 ? Double(p.total - p.sent) / rate : nil
        }
        activeTransfer = t
    }
}
