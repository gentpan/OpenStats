import AppKit
import Cleaner
import Foundation
import Localization
import Metrics
import Observation

/// 回收结果只以系统返回的源路径为准，不把未成功的项目计入清理记录。
struct UninstallResultSummary: Sendable {
    let successfulItems: [AppLeftover]
    let failedItems: [AppLeftover]
    let applicationWasRequested: Bool
    let applicationMoved: Bool

    init(app: InstalledApp, requested: [AppLeftover], movedSources: Set<URL>) {
        let movedPaths = Set(movedSources.map { $0.standardizedFileURL.path })
        let appPath = app.url.standardizedFileURL.path
        successfulItems = requested.filter { movedPaths.contains($0.url.standardizedFileURL.path) }
        failedItems = requested.filter { !movedPaths.contains($0.url.standardizedFileURL.path) }
        applicationWasRequested = requested.contains { $0.url.standardizedFileURL.path == appPath }
        applicationMoved = successfulItems.contains { $0.url.standardizedFileURL.path == appPath }
    }

    var movedCount: Int { successfulItems.count }
    var leftoverCount: Int { movedCount - (applicationMoved ? 1 : 0) }
    var freedBytes: UInt64 { successfulItems.reduce(0) { $0 + $1.size } }
    var isPartial: Bool { !failedItems.isEmpty }
}

/// 卸载应用：列出已安装的应用，查找残留文件，连同残留一起移到废纸篓，并从程序坞移除图标
@MainActor
@Observable
public final class UninstallerController {
    public private(set) var apps: [InstalledApp] = []
    public private(set) var sizes: [String: UInt64] = [:]
    public private(set) var isLoading = false
    public private(set) var selected: InstalledApp?
    public private(set) var leftovers: [AppLeftover] = []
    public private(set) var isScanning = false
    public private(set) var isRemoving = false
    public private(set) var unreadableDirectories: [URL] = []
    public private(set) var otherInstalledCopies: [URL] = []
    public private(set) var outcome: (text: String, isError: Bool)?
    var chosen: Set<String> = []
    @ObservationIgnored var tally: CleanupTally?
    /// 有应用启动或退出时变化，让“正在运行”的提示跟着刷新
    private var runningRevision = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let scanner: @Sendable (InstalledApp) -> AppUninstallScan
    @ObservationIgnored private var selectedScan: AppUninstallScan?
    private var scanGeneration = UUID()

    public convenience init() {
        self.init(scanner: { AppUninstaller.scan(for: $0) })
    }

    init(scanner: @escaping @Sendable (InstalledApp) -> AppUninstallScan) {
        self.scanner = scanner
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runningRevision += 1 }
            })
        }
    }

    var chosenSize: UInt64 {
        leftovers.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func loadApps() {
        guard !isLoading else { return }
        isLoading = true
        let own = Bundle.main.bundleIdentifier.map { Set([$0]) } ?? []
        Task {
            let apps = await Task.detached { AppUninstaller.installedApps(excluding: own) }.value
            self.apps = apps.filter { (try? AppUninstaller.validate($0)) != nil }
            isLoading = false
            // 体积在后台逐个计算，列表先显示出来
            for app in self.apps where sizes[app.id] == nil {
                let url = app.url
                sizes[app.id] = await Task.detached { CleanEngine.allocatedSize(of: url) }.value
            }
        }
    }

    func select(_ app: InstalledApp?) {
        let generation = UUID()
        scanGeneration = generation
        selectedScan = nil
        selected = app
        leftovers = []
        chosen = []
        outcome = nil
        unreadableDirectories = []
        otherInstalledCopies = []
        isScanning = false
        guard let app else { return }
        isScanning = true
        let scanner = self.scanner
        Task {
            let scan = await Task.detached { scanner(app) }.value
            guard scanGeneration == generation else { return }
            leftovers = scan.items
            selectedScan = scan
            unreadableDirectories = scan.unreadableDirectories
            otherInstalledCopies = scan.otherInstalledCopies
            chosen = Self.initialSelection(for: scan.items)
            isScanning = false
        }
    }

    static func initialSelection(for items: [AppLeftover]) -> Set<String> {
        Set(items.filter { !$0.requiresReview }.map(\.id))
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 拖进来的 .app
    func select(url: URL) {
        guard let app = AppUninstaller.app(at: url) else {
            outcome = (tr("不是应用程序"), true)
            return
        }
        do {
            try AppUninstaller.validate(app)
            select(app)
        } catch {
            outcome = ("\(error)", true)
        }
    }

    func toggle(_ leftover: AppLeftover) {
        // 应用本体必须一起移除，否则没有意义
        guard leftover.kind != .application else { return }
        if chosen.contains(leftover.id) { chosen.remove(leftover.id) } else { chosen.insert(leftover.id) }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        _ = runningRevision
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    func quit(_ app: InstalledApp) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).forEach { $0.terminate() }
    }

    func uninstall() {
        guard let app = selected, !isRemoving else { return }
        var requested = leftovers.filter { chosen.contains($0.id) }
        // 用户查看清单后可能又安装了一份副本，回收前重查，保留副本仍在使用的数据。
        let installations = AppUninstaller.checkOtherInstallations(of: app)
        otherInstalledCopies = installations.otherInstalledCopies
        if installations.preservesSharedData {
            unreadableDirectories = Array(Set(unreadableDirectories + installations.unreadableDirectories)).sorted { $0.path < $1.path }
            requested.removeAll { $0.kind != .application }
            leftovers.removeAll { $0.kind != .application }
            chosen = Self.initialSelection(for: leftovers)
        }
        do {
            if requested.contains(where: { $0.kind == .application }) { try AppUninstaller.validate(app) }
            guard !isRunning(app) else { throw AppUninstallError.running }
            for item in requested {
                if let selectedScan { try AppUninstaller.validateLeftover(item.url, for: app, scan: selectedScan) }
                else { try AppUninstaller.validateLeftover(item.url, for: app) }
            }
        } catch {
            outcome = ("\(error)", true)
            return
        }
        guard !requested.isEmpty else {
            outcome = (tr("请先选择要移到废纸篓的项目。"), true)
            return
        }
        let urls = requested.map(\.url)
        let requestedItems = requested
        isRemoving = true
        outcome = nil
        // NSWorkspace 负责需要管理员权限的情况（例如 root 拥有的应用），并能在废纸篓中“放回原处”
        NSWorkspace.shared.recycle(urls) { [weak self] moved, error in
            let summary = UninstallResultSummary(app: app, requested: requestedItems, movedSources: Set(moved.keys))
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.isRemoving = false
                if summary.movedCount == 0 {
                    if self.selected == app {
                        self.outcome = (tr("没有移动任何文件\(message.map { tr("：\($0)") } ?? "")"), true)
                    }
                    return
                }
                let dock: Bool
                if summary.applicationMoved {
                    // 只有本体已进废纸篓时，才移除列表与程序坞图标并计一次卸载。
                    dock = Self.removeDockTile(for: app.url)
                    self.apps.removeAll { $0 == app }
                    self.sizes.removeValue(forKey: app.id)
                    self.tally?.recordUninstall(bytes: summary.freedBytes)
                } else {
                    dock = false
                    self.tally?.recordClean(bytes: summary.freedBytes)
                }
                Log.app.notice("回收 \(app.bundleIdentifier, privacy: .public)，移到废纸篓 \(summary.movedCount) 项，未移动 \(summary.failedItems.count) 项")
                // 回收期间可能已选择其他应用，完成旧操作不覆盖新应用的详情。
                guard self.selected == app else { return }
                let partial = summary.isPartial ? tr("，\(summary.failedItems.count) 项未能移动") : ""
                let freed = Format.bytes(summary.freedBytes, base: .decimal)
                let text: String
                if summary.applicationMoved {
                    text = tr("已将 \(app.name) 与 \(summary.leftoverCount) 项残留移到废纸篓，约 \(freed)\(dock ? tr("，已从程序坞移除") : "")\(partial)。需要时可以在废纸篓里放回。")
                } else {
                    let appFailure = summary.applicationWasRequested ? "\n" + tr("应用本体未能移动，仍保留在原处，可重试。") : ""
                    text = tr("已将 \(app.name) 的 \(summary.leftoverCount) 项残留移到废纸篓，约 \(freed)\(partial)。需要时可以在废纸篓里放回。") + appFailure
                }
                self.outcome = (text, summary.isPartial || message != nil)
                let movedIDs = Set(summary.successfulItems.map(\.id))
                self.leftovers.removeAll { movedIDs.contains($0.id) }
                self.chosen.subtract(movedIDs)
                if self.leftovers.isEmpty { self.selected = nil }
            }
        }
    }

    /// 修改程序坞偏好里的 persistent-apps 并重启程序坞
    private static func removeDockTile(for url: URL) -> Bool {
        let domain = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        guard let tiles = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]],
              let updated = AppUninstaller.removingDockTile(for: url, from: tiles) else { return false }
        CFPreferencesSetAppValue(key, updated as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        return true
    }
}
