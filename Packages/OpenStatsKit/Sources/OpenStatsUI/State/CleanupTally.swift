import Foundation
import Observation

/// 累计清理记录：清理释放的空间、卸载的应用数、执行过的系统优化次数（刷新 DNS、释放内存），显示在菜单栏总览面板
@MainActor
@Observable
public final class CleanupTally {
    public private(set) var freedBytes: UInt64
    public private(set) var uninstalledApps: Int
    public private(set) var optimizations: Int

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        freedBytes = UInt64(max(0, defaults.double(forKey: Keys.freedBytes)))
        uninstalledApps = defaults.integer(forKey: Keys.uninstalledApps)
        optimizations = defaults.integer(forKey: Keys.optimizations)
    }

    func recordClean(bytes: UInt64) {
        guard bytes > 0 else { return }
        freedBytes += bytes
        defaults.set(Double(freedBytes), forKey: Keys.freedBytes)
    }

    func recordUninstall(bytes: UInt64) {
        uninstalledApps += 1
        defaults.set(uninstalledApps, forKey: Keys.uninstalledApps)
        recordClean(bytes: bytes)
    }

    func recordOptimization() {
        optimizations += 1
        defaults.set(optimizations, forKey: Keys.optimizations)
    }

    private enum Keys {
        static let freedBytes = "cleanupFreedBytes"
        static let uninstalledApps = "cleanupUninstalledApps"
        static let optimizations = "cleanupOptimizations"
    }
}
