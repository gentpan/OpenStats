import Foundation
import Localization

/// “系统数据”里的大件：设备备份、系统更新包、安装器、本地模型、虚拟磁盘。
/// 按 macOS 与各工具公开的存放位置独立编写。会丢东西或要重新下载很久的，一律默认不勾选、移到废纸篓；
/// 只能用工具自己的命令安全删除的（Docker、Ollama、模拟器），只列出占用和处理办法，不进删除入口
extension RuleCatalog {
    // MARK: 设备

    static let deviceBackups = CleanRule(
        id: "large.deviceBackups", category: .large, title: tr("iPhone / iPad 备份"),
        detail: tr("访达备份到这台 Mac 的设备数据，每个可能有几十 GB。删除后不能再用它恢复设备"),
        symbol: "iphone", selectedByDefault: false, policy: .trash,
        // 正在备份的会不断写入：一小时内改过的不动
        minimumAge: 3600, requiresFullDiskAccess: true, itemLabel: deviceBackupLabel
    ) { env in
        try childrenIfExists(of: env.home + "/Library/Application Support/MobileSync/Backup").filter { backup in
            isDirectory(backup) && FileManager.default.fileExists(atPath: backup.appendingPathComponent("Info.plist").path)
        }
    }

    /// “Peter 的 iPhone · 2026-10-02”：设备名与上次备份日期写在每个备份的 Info.plist 里（加密备份也是明文）
    static func deviceBackupLabel(_ url: URL) -> String {
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist"))
        let name = (info?["Device Name"] as? String) ?? (info?["Display Name"] as? String) ?? url.lastPathComponent
        guard let date = info?["Last Backup Date"] as? Date else { return name }
        return name + " · " + date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    static let deviceFirmware = CleanRule(
        id: "large.deviceFirmware", category: .large, title: tr("设备系统更新包"),
        detail: tr("访达为 iPhone、iPad 下载的 .ipsw 系统文件，更新或恢复设备时会重新下载"),
        symbol: "arrow.down.app", selectedByDefault: false, policy: .trash
    ) { env in
        var urls: [URL] = []
        for device in ["iPhone", "iPad", "iPod"] {
            urls += try childrenIfExists(of: env.home + "/Library/iTunes/\(device) Software Updates")
                .filter { $0.pathExtension.lowercased() == "ipsw" }
        }
        return urls
    }

    static let macOSInstallers = CleanRule(
        id: "large.macOSInstallers", category: .large, title: tr("macOS 安装器"),
        detail: tr("应用程序文件夹里的“安装 macOS”应用，每个 12–15 GB，需要时可以从 App Store 重新下载"),
        symbol: "laptopcomputer", selectedByDefault: false, policy: .trash, minimumAge: 600,
        // 安装器正在运行（正在升级系统）就不动
        ownerName: { $0.deletingPathExtension().lastPathComponent },
        itemLabel: { $0.deletingPathExtension().lastPathComponent }
    ) { env in
        try childrenIfExists(of: env.applications).filter(SafetyGuard.isMacOSInstaller)
    }

    // MARK: 本地模型

    static let aiModels = CleanRule(
        id: "large.aiModels", category: .large, title: tr("本地 AI 模型"),
        detail: tr("Hugging Face、LM Studio 与 PyTorch 下载的模型，按模型分条，删除后需要重新下载"),
        symbol: "brain", selectedByDefault: false, policy: .trash,
        ownerName: aiModelOwner, itemLabel: aiModelLabel
    ) { env in
        // Hugging Face 的缓存：每个模型或数据集一个目录，里面的快照指向同目录的文件，整个目录删掉就是官方的删除方式
        var urls = try childrenIfExists(of: env.home + "/.cache/huggingface/hub").filter { url in
            let name = url.lastPathComponent
            return isDirectory(url) && (name.hasPrefix("models--") || name.hasPrefix("datasets--"))
        }
        // LM Studio：models/<发布者>/<模型>，新版在 ~/.lmstudio，旧版在 ~/.cache/lm-studio
        for base in [".lmstudio/models", ".cache/lm-studio/models"] {
            for publisher in try childrenIfExists(of: env.home + "/" + base) where isDirectory(publisher) {
                urls += try children(of: publisher.path).filter(isDirectory)
            }
        }
        // PyTorch Hub 下载的权重文件
        urls += try childrenIfExists(of: env.home + "/.cache/torch/hub/checkpoints")
        return urls
    }

    static func aiModelOwner(_ url: URL) -> String? {
        url.pathComponents.contains("huggingface") || url.pathComponents.contains("torch") ? nil : "LM Studio"
    }

    /// “Hugging Face › meta-llama/Llama-3-8B”“LM Studio › lmstudio-community/Qwen3-8B-GGUF”
    static func aiModelLabel(_ url: URL) -> String {
        let name = url.lastPathComponent
        if url.pathComponents.contains("torch") { return "PyTorch › " + name }
        if url.pathComponents.contains("huggingface") {
            if name.hasPrefix("datasets--") {
                return "Hugging Face › " + tr("数据集 \(name.dropFirst("datasets--".count).replacingOccurrences(of: "--", with: "/"))")
            }
            return "Hugging Face › " + name.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
        }
        return "LM Studio › " + url.deletingLastPathComponent().lastPathComponent + "/" + name
    }

    static let ollamaModels = CleanRule(
        manual: "large.ollamaModels", category: .large, title: tr("Ollama 模型"),
        detail: tr("Ollama 下载的本地模型，按模型列出"), symbol: "brain.head.profile",
        advice: tr("Ollama 的模型文件彼此共用，直接删除文件会损坏它的索引。请在终端用 ollama list 查看、用 ollama rm 加模型名删除不用的模型。")
    ) { env in
        OllamaModels.entries(home: env.home)
    }

    // MARK: 邮件

    static let mailDownloads = CleanRule(
        id: "large.mailDownloads", category: .large, title: tr("邮件附件副本"),
        detail: tr("在“邮件”里打开过的附件会另存一份副本，原件仍在邮件里"),
        symbol: "envelope", selectedByDefault: false, policy: .trash,
        blockingApps: [("com.apple.mail", tr("邮件"))], requiresFullDiskAccess: true, itemLabel: mailDownloadLabel
    ) { env in
        try childrenIfExists(of: env.home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
    }

    /// 每个附件放在一个随机命名的目录里：显示里面的文件名
    static func mailDownloadLabel(_ url: URL) -> String {
        guard isDirectory(url),
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path).filter({ !$0.hasPrefix(".") }).sorted(),
              let first = names.first else { return url.lastPathComponent }
        return names.count > 1 ? tr("\(first) 等 \(names.count) 个文件") : first
    }

    // MARK: 虚拟磁盘（只提示）

    static let containerDisks = CleanRule(
        manual: "large.containerDisks", category: .large, title: tr("Docker 虚拟磁盘"),
        detail: tr("Docker Desktop、OrbStack、Colima、Podman 的虚拟磁盘，所有镜像、容器和数据卷都在里面"),
        symbol: "shippingbox.circle",
        advice: tr("不要直接删除这些文件，否则所有镜像、容器和数据卷都会丢失。请在 Docker Desktop 或 OrbStack 的设置里清理，或在终端运行 docker system prune 删除停止的容器和不再使用的镜像。"),
        // Docker Desktop 与 OrbStack 的数据在它们的容器里：没有权限时去读会让系统弹授权框
        requiresFullDiskAccess: true
    ) { env in
        [("Library/Containers/com.docker.docker/Data/vms", "Docker Desktop"),
         ("Library/Group Containers/HUAQ24HBR6.dev.orbstack/data", "OrbStack"),
         (".colima", "Colima"),
         (".lima", "Lima"),
         (".local/share/containers/podman/machine", "Podman")].compactMap { relative, name in
            let url = URL(fileURLWithPath: env.home + "/" + relative)
            return FileManager.default.fileExists(atPath: url.path) ? ManualEntry(url: url, title: name) : nil
        }
    }

    static let virtualMachines = CleanRule(
        manual: "large.virtualMachines", category: .large, title: tr("虚拟机"),
        detail: tr("UTM、Parallels、VMware Fusion、VirtualBox、Tart 的虚拟机"), symbol: "pc",
        advice: tr("虚拟机里是完整的系统和你的数据。请在对应的虚拟机软件里删除不再需要的虚拟机，它的快照和配置会一起清掉。")
    ) { env in
        var places: [(relative: String, app: String, ext: String?)] = [
            ("Parallels", "Parallels", "pvm"),
            ("Virtual Machines.localized", "VMware Fusion", "vmwarevm"),
            ("VirtualBox VMs", "VirtualBox", nil),
            (".tart/vms", "Tart", nil),
        ]
        // 这两处受系统保护：只有拿到完全磁盘访问权限才看，免得弹授权框
        if env.hasFullDiskAccess {
            places.append(("Library/Containers/com.utmapp.UTM/Data/Documents", "UTM", "utm"))
            places.append(("Documents/Virtual Machines.localized", "VMware Fusion", "vmwarevm"))
        }
        var entries: [ManualEntry] = []
        for place in places {
            let found = (try? childrenIfExists(of: env.home + "/" + place.relative)) ?? []
            for url in found where isDirectory(url) && (place.ext == nil || url.pathExtension.lowercased() == place.ext) {
                entries.append(ManualEntry(url: url, title: place.app + " › " + url.deletingPathExtension().lastPathComponent))
            }
        }
        return entries
    }

    // MARK: 开发者（模拟器，只提示）

    static let unavailableSimulators = CleanRule(
        manual: "developer.unavailableSimulators", category: .developer, title: tr("不可用的模拟器"),
        detail: tr("对应的系统版本已经删掉，这些模拟器打不开了，数据还占着空间"), symbol: "iphone.slash",
        advice: tr("在终端运行 xcrun simctl delete unavailable，会一次删掉所有不可用的模拟器。")
    ) { env in
        env.simulators()?.unavailableDeviceEntries() ?? []
    }

    static let unusedSimulatorRuntimes = CleanRule(
        manual: "developer.unusedSimulatorRuntimes", category: .developer, title: tr("没有模拟器在用的系统版本"),
        detail: tr("已下载的模拟器系统（运行时），没有任何模拟器在用，每个 5–10 GB"), symbol: "square.stack.3d.up",
        advice: tr("在 Xcode 设置的“组件”里删除不需要的版本（旧版 Xcode 里叫“平台”）。")
    ) { env in
        env.simulators()?.unusedRuntimeEntries() ?? []
    }

    // MARK: 开发者（包管理器）

    static let gradleCaches = CleanRule(
        id: "developer.gradle", category: .developer, title: tr("Gradle 缓存"),
        detail: tr("~/.gradle/caches 与下载的 Gradle 发行版，下次构建时重新下载"),
        symbol: "hammer.circle", selectedByDefault: false,
        blockingApps: [("com.google.android.studio", "Android Studio"), ("com.jetbrains.intellij", "IntelliJ IDEA"),
                       ("com.jetbrains.intellij.ce", "IntelliJ IDEA CE")],
        itemLabel: homeRelativeLabel
    ) { env in
        existingItems([".gradle/caches"], home: env.home) + (try childrenIfExists(of: env.home + "/.gradle/wrapper/dists"))
    }

    static let javascriptPackageCaches = CleanRule(
        id: "developer.jsPackageCaches", category: .developer, title: tr("pnpm / bun 包缓存"),
        detail: tr("pnpm 的包仓库与 bun 的下载缓存，下次安装依赖时重新下载"),
        symbol: "shippingbox", selectedByDefault: false, itemLabel: homeRelativeLabel
    ) { env in
        // 不含 yarn 的全局缓存：Yarn 4 默认的 PnP 项目直接从那里读包，删了项目就跑不起来
        existingItems(["Library/pnpm/store", ".bun/install/cache"], home: env.home)
    }

    // MARK: 工具

    static func isDirectory(_ url: URL) -> Bool {
        FileIdentity.status(of: url.path)?.isDirectory == true
    }
}
