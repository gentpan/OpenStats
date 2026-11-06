import AppKit
import Cleaner
import Foundation
import Observation

@MainActor
@Observable
public final class CleanerController {
    public enum Phase: Equatable {
        case idle, scanning, ready, cleaning, finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var scans: [RuleScan] = []
    public private(set) var lastScan: Date?
    public private(set) var report: CleanReport?
    public var selection: Set<String>
    /// 选中的规则里，用户单独取消勾选的条目（CleanItem.id）。重新扫描后仍然记得
    public var excludedItems: Set<String> = []
    public var isConfirming = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let tally: CleanupTally
    @ObservationIgnored private let rules = RuleCatalog.rules()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(settings: AppSettings, tally: CleanupTally) {
        self.settings = settings
        self.tally = tally
        selection = Set(rules.filter(\.selectedByDefault).map(\.id))
    }

    var isBusy: Bool { phase == .scanning || phase == .cleaning }

    func scan(ifNeeded: Bool = false) {
        guard !isBusy, !(ifNeeded && lastScan != nil) else { return }
        phase = .scanning
        isConfirming = false
        let environment = Self.environment()
        let rules = rules
        task = Task {
            let results = await CleanEngine.scan(rules, environment: environment)
            scans = results
            lastScan = Date()
            phase = .ready
        }
    }

    func requestClean() {
        guard phase == .ready || phase == .finished, selectedBytes > 0 else { return }
        isConfirming = true
    }

    func cancelClean() {
        isConfirming = false
    }

    func confirmClean() {
        guard isConfirming else { return }
        isConfirming = false
        phase = .cleaning
        let environment = Self.environment()
        let scans = scans
        let selection = selection
        let excluded = excludedItems
        let preferTrash = settings.cleanPrefersTrash
        task = Task {
            let result = await CleanEngine.clean(scans, selected: selection, excluded: excluded, preferTrash: preferTrash,
                                                 environment: environment)
            report = result
            tally.recordClean(bytes: result.freedBytes)
            phase = .finished
            // 清理后重新计算剩余可清理空间
            let rescanned = await CleanEngine.scan(rules, environment: Self.environment())
            self.scans = rescanned
            lastScan = Date()
        }
    }

    /// 整条规则：没选或只选了一部分时全选，全选时全不选
    func toggle(_ scan: RuleScan) {
        guard scan.isCleanable else { return }
        if selection.contains(scan.id) && !isPartial(scan) {
            selection.remove(scan.id)
        } else {
            selection.insert(scan.id)
        }
        excludedItems.subtract(scan.items.map(\.id))
        isConfirming = false
    }

    /// 单个条目。在没选的规则里勾一项，就只选这一项；一项都不剩时整条规则取消
    func toggle(_ item: CleanItem, in scan: RuleScan) {
        guard scan.isCleanable else { return }
        if !selection.contains(scan.id) {
            selection.insert(scan.id)
            excludedItems.formUnion(scan.items.map(\.id))
            excludedItems.remove(item.id)
        } else if excludedItems.contains(item.id) {
            excludedItems.remove(item.id)
        } else {
            excludedItems.insert(item.id)
            if scan.items.allSatisfy({ excludedItems.contains($0.id) }) {
                selection.remove(scan.id)
                excludedItems.subtract(scan.items.map(\.id))
            }
        }
        isConfirming = false
    }

    func isSelected(_ item: CleanItem, in scan: RuleScan) -> Bool {
        scan.isCleanable && selection.contains(scan.id) && !excludedItems.contains(item.id)
    }

    /// 规则选中了，但其中有条目被取消
    func isPartial(_ scan: RuleScan) -> Bool {
        selection.contains(scan.id) && scan.items.contains { excludedItems.contains($0.id) }
    }

    /// 这条规则里真正会处理的条目
    func selectedItems(in scan: RuleScan) -> [CleanItem] {
        guard scan.isCleanable, selection.contains(scan.id) else { return [] }
        return scan.items.filter { !excludedItems.contains($0.id) }
    }

    var totalBytes: UInt64 {
        scans.filter(\.isCleanable).reduce(0) { $0 + $1.totalSize }
    }

    /// 只提示、要用户自己处理的占用
    var manualBytes: UInt64 {
        scans.filter { $0.rule.isManual && $0.blocked == nil }.reduce(0) { $0 + $1.totalSize }
    }

    var selectedScans: [RuleScan] {
        scans.filter { !selectedItems(in: $0).isEmpty }
    }

    var selectedBytes: UInt64 {
        scans.reduce(0) { total, scan in total + selectedItems(in: scan).reduce(0) { $0 + $1.size } }
    }

    var selectedItemCount: Int {
        scans.reduce(0) { $0 + selectedItems(in: $1).count }
    }

    var needsFullDiskAccess: Bool {
        scans.contains { $0.blocked == .needsFullDiskAccess }
    }

    func scans(in category: CleanCategory) -> [RuleScan] {
        scans.filter { $0.rule.category == category }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealLog() {
        let log = CleanLog().url
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log])
        }
    }

    func reveal(_ item: CleanItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// 运行中的应用在主线程读取一次后传入后台扫描
    private static func environment() -> CleanEnvironment {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let names = currentRunningApplicationNames()
        // 正常的 Mac 上不可能一个应用都没有（至少有 Finder、程序坞）；空列表说明读取失败，按“可能在运行”处理
        return CleanEnvironment(runningBundleIdentifiers: { running }, runningAppsReadable: !running.isEmpty,
                                runningApplicationNames: { names },
                                interactiveTrasher: WorkspaceTrasher(),
                                hasFullDiskAccess: FullDiskAccess.isGranted(),
                                simulators: SimulatorInventory.loader())
    }
}
