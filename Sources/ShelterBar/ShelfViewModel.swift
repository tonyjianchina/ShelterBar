import AppKit
import Combine

@MainActor
final class ShelfViewModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var residentItems: [ShelfItem] = []
    @Published var hasAccessibilityPermission = AccessibilityPermission.isGranted
    @Published var hasScreenCapturePermission = ScreenCapturePermission.isGranted
    @Published var inputPermissionHint: String?
    @Published var screenCapturePermissionHint: String?
    @Published var isPinned = UserDefaults.standard.bool(forKey: "shelf.isPinned")
    @Published var isBusy = false
    @Published var message: String?
    @Published var isDropTargeted = false
    @Published var isDraggingToMenuBar = false
    var onPermissionRequest: (() -> Void)?
    var onScreenCapturePermissionRequest: (() -> Void)?
    var onRefresh: (() -> Void)?

    private let source: any ShelfItemSource
    private var knownItems: [String: ShelfItem] = [:]
    private var iconCache: [String: MenuBarIconSnapshot] = [:]
    private let defaults: UserDefaults
    private let isTrusted: @MainActor () -> Bool
    private let isVisible: @MainActor (CGRect) -> Bool
    private let isLogicallyHidden: @MainActor (ShelfItem) -> Bool
    private var sessionCollected = Set<String>()
    /// Glyphs persisted from earlier captures; used while an item is stowed
    /// off-screen and cannot be captured again (e.g. right after launch).
    private let iconStore: MenuBarIconDiskCache?
    var allItems: [ShelfItem] { Array(knownItems.values) }

    var inputPermissionGuidance: String {
        inputPermissionHint ?? "允许辅助功能和输入监控后，即可拖动顶部图标"
    }

    init(
        source: any ShelfItemSource, defaults: UserDefaults = .standard,
        isTrusted: @escaping @MainActor () -> Bool = { AccessibilityPermission.isGranted },
        isVisible: @escaping @MainActor (CGRect) -> Bool = MenuBarGeometry.isOnMenuBar,
        isLogicallyHidden: @escaping @MainActor (ShelfItem) -> Bool = { _ in false },
        iconStore: MenuBarIconDiskCache? = nil
    ) {
        self.source = source
        self.iconStore = iconStore
        self.defaults = defaults
        self.isTrusted = isTrusted
        self.isVisible = isVisible
        self.isLogicallyHidden = isLogicallyHidden
        isPinned = defaults.bool(forKey: "shelf.isPinned")
    }

    var collectedIDs: Set<String> {
        Set(defaults.stringArray(forKey: "shelf.collectedItems") ?? []).union(sessionCollected)
    }

    func scan() -> [ShelfItem] { source.items() }

    func refresh() {
        hasAccessibilityPermission = isTrusted()
        guard hasAccessibilityPermission else {
            iconCache.removeAll()
            knownItems.removeAll()
            items = []
            residentItems = []
            return
        }
        if !hasScreenCapturePermission { iconCache.removeAll() }
        let fresh = scan()
        var byID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in collectedIDs where byID[id] == nil {
            if let old = knownItems[id], old.application?.isTerminated == false,
               let frame = old.menuBarReference.currentFrame(), frame.width > 1 {
                old.menuBarReference.frame = frame
                byID[id] = old
            }
        }
        iconCache = iconCache.filter { id, icon in byID[id]?.menuBarReference.pid == icon.pid }
        for (id, var item) in byID {
            if let snapshot = iconCache[id] {
                item.icon = snapshot.image
                item.hasMenuBarIcon = true
            } else if hasScreenCapturePermission, let cached = iconStore?.image(for: id) {
                item.icon = cached
                item.hasMenuBarIcon = true
            } else {
                item.icon = MenuBarIconPresentation.placeholder(accessibilityDescription: item.title)
                item.hasMenuBarIcon = false
            }
            byID[id] = item
        }
        knownItems = byID
        if !fresh.isEmpty { iconStore?.prune(keeping: collectedIDs) }
        let order = defaults.stringArray(forKey: "shelf.itemOrder") ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let ordered = byID.values.sorted {
            let a = rank[$0.id] ?? Int.max, b = rank[$1.id] ?? Int.max
            return a == b ? $0.id < $1.id : a < b
        }
        // Only confirmed off-row items appear in the shelf. Expanded recovery
        // mode never duplicates a real icon that is still on the top bar.
        items = ordered.filter {
            collectedIDs.contains($0.id)
                && (isLogicallyHidden($0) || !isVisible($0.menuBarReference.frame))
        }
        residentItems = ordered.filter {
            !isLogicallyHidden($0) && isVisible($0.menuBarReference.frame)
        }
    }

    func remember(_ item: ShelfItem) { knownItems[item.id] = item }
    func applyMenuBarIcons(_ snapshots: [MenuBarIconSnapshot]) {
        guard hasAccessibilityPermission, hasScreenCapturePermission else {
            iconCache.removeAll()
            refresh()
            return
        }
        let collected = collectedIDs
        for snapshot in snapshots where knownItems[snapshot.id]?.menuBarReference.pid == snapshot.pid {
            iconCache[snapshot.id] = snapshot
            if collected.contains(snapshot.id) { iconStore?.store(snapshot.image, for: snapshot.id) }
        }
        refresh()
    }
    func hasMenuBarIcon(for item: ShelfItem) -> Bool {
        iconCache[item.id]?.pid == item.menuBarReference.pid
    }
    func item(withID id: String) -> ShelfItem? { knownItems[id] }
    /// Shelf items that show only a placeholder (no live or persisted glyph).
    var itemsMissingIcons: [ShelfItem] { items.filter { !$0.hasMenuBarIcon } }
    func setCollected(_ value: Bool, id: String) {
        var ids = Set(defaults.stringArray(forKey: "shelf.collectedItems") ?? [])
        if value {
            if knownItems[id]?.hasPersistentIdentity == true {
                ids.insert(id)
                if hasScreenCapturePermission, let snapshot = iconCache[id] {
                    iconStore?.store(snapshot.image, for: id)
                }
            } else { sessionCollected.insert(id) }
        } else {
            ids.remove(id)
            sessionCollected.remove(id)
        }
        defaults.set(ids.sorted(), forKey: "shelf.collectedItems")
    }

    func move(_ id: String, before target: String) {
        guard id != target, items.contains(where: { $0.id == id }),
              items.contains(where: { $0.id == target }) else { return }
        var order = items.map(\.id)
        order.removeAll { $0 == id }
        guard let index = order.firstIndex(of: target) else { return }
        order.insert(id, at: index)
        defaults.set(order, forKey: "shelf.itemOrder")
        refresh()
    }

    var pendingRestore: MenuBarPendingRestore? {
        get {
            defaults.data(forKey: "shelf.pendingRestore")
                .flatMap { try? JSONDecoder().decode(MenuBarPendingRestore.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "shelf.pendingRestore")
            } else {
                defaults.removeObject(forKey: "shelf.pendingRestore")
            }
        }
    }

    func setPinned(_ value: Bool) {
        isPinned = value
        defaults.set(value, forKey: "shelf.isPinned")
    }

    func requestAccessibilityPermission() { onPermissionRequest?() }
    func openAccessibilitySettings() {
        inputPermissionHint = (AccessibilityPermission.openSettings()
            ? AccessibilityPermission.RequestResult.settingsOpened : .settingsUnavailable).guidance
    }
    func requestScreenCapturePermission() { onScreenCapturePermissionRequest?() }
    func openScreenCaptureSettings() { ScreenCapturePermission.openSettings() }
}
