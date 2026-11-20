import Foundation
import Localization

/// 临时文件、Maven、Go 模块与 Android 模拟器。按各工具公开的默认位置独立编写。
/// Homebrew、CocoaPods、Go 编译缓存、Playwright、Cypress 的缓存都在 ~/Library/Caches 里，已经算在“应用缓存”中
extension RuleCatalog {
    // MARK: 临时文件

    /// 临时目录里的条目要多久没动过才算没人用
    static let temporaryFileAge: TimeInterval = 3 * 86_400

    static let temporaryFiles = CleanRule(
        id: "system.temporaryFiles", category: .system, title: tr("过期的临时文件"),
        detail: tr("各应用放在用户临时目录里、3 天以上没有改动的文件。正在运行的应用的条目和系统进程的条目不动"),
        symbol: "clock.arrow.circlepath", selectedByDefault: false, checksOwnerApp: true,
        minimumAge: temporaryFileAge, itemLabel: temporaryItemLabel
    ) { env in
        guard let temporary = env.temporaryDirectory else { return [] }
        let now = env.now()
        return try childrenIfExists(of: temporary).filter { url in
            let name = url.lastPathComponent
            // 系统进程的临时条目由系统自己回收
            guard !name.hasPrefix("com.apple.") else { return false }
            guard let newest = newestModification(in: url) else { return false }
            return now.timeIntervalSince(newest) >= temporaryFileAge
        }
    }

    static func temporaryItemLabel(_ url: URL) -> String {
        tr("临时目录 › \(url.lastPathComponent)")
    }

    /// 目录里最新的修改时间（含目录本身）。条目太多就放弃（返回 nil，按“可能在用”处理），免得一个大目录拖慢整次扫描
    static func newestModification(in url: URL, limit: Int = 20_000) -> Date? {
        guard let status = FileIdentity.status(of: url.path), !status.isSymbolicLink,
              var newest = FileIdentity.modificationDate(of: url.path) else { return nil }
        guard status.isDirectory else { return newest }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey],
                                                              options: [], errorHandler: { _, _ in true }) else { return nil }
        var count = 0
        while let file = enumerator.nextObject() as? URL {
            count += 1
            if count > limit { return nil }
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest
    }

    // MARK: Java / Go

    static let mavenRepository = CleanRule(
        id: "developer.maven", category: .developer, title: tr("Maven 本地仓库"),
        detail: tr("~/.m2/repository 里下载的依赖，下次构建时重新下载；settings.xml 不动"),
        symbol: "cup.and.saucer", selectedByDefault: false,
        blockingApps: [("com.jetbrains.intellij", "IntelliJ IDEA"), ("com.jetbrains.intellij.ce", "IntelliJ IDEA CE"),
                       ("com.google.android.studio", "Android Studio")],
        itemLabel: homeRelativeLabel
    ) { env in
        existingItems([".m2/repository"], home: env.home)
    }

    static let goModules = CleanRule(
        manual: "developer.goModules", category: .developer, title: tr("Go 模块缓存"),
        detail: tr("~/go/pkg/mod 里下载的 Go 模块"), symbol: "chevron.left.forwardslash.chevron.right",
        advice: tr("Go 把模块缓存设成只读，直接删除会失败或只删掉一部分。请在终端运行 go clean -modcache，下次构建时会重新下载。")
    ) { env in
        let url = URL(fileURLWithPath: env.home + "/go/pkg/mod")
        return FileManager.default.fileExists(atPath: url.path) ? [ManualEntry(url: url, title: "~/go/pkg/mod")] : []
    }

    // MARK: Android（只提示）

    static let androidEmulators = CleanRule(
        manual: "developer.android", category: .developer, title: tr("Android 模拟器与系统镜像"),
        detail: tr("Android 模拟器（AVD）的数据，以及 SDK 里下载的模拟器系统镜像"), symbol: "candybarphone",
        advice: tr("模拟器请在 Android Studio 的 Device Manager 里删除，系统镜像请在 SDK Manager 里取消勾选后应用。直接删除文件会让 Android Studio 的记录对不上。")
    ) { env in
        var entries: [ManualEntry] = []
        for avd in (try? childrenIfExists(of: env.home + "/.android/avd")) ?? [] where avd.pathExtension == "avd" && isDirectory(avd) {
            entries.append(ManualEntry(url: avd, title: tr("模拟器 › \(avd.deletingPathExtension().lastPathComponent)")))
        }
        // system-images/<API>/<类型>/<架构>
        let images = env.home + "/Library/Android/sdk/system-images"
        for api in (try? childrenIfExists(of: images)) ?? [] where isDirectory(api) {
            for variant in (try? children(of: api.path)) ?? [] where isDirectory(variant) {
                for abi in (try? children(of: variant.path)) ?? [] where isDirectory(abi) {
                    let name = [api, variant, abi].map(\.lastPathComponent).joined(separator: "/")
                    entries.append(ManualEntry(url: abi, title: tr("系统镜像 › \(name)")))
                }
            }
        }
        return entries
    }
}
