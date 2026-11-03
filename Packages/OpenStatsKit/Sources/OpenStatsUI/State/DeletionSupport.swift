import AppKit
import Cleaner

/// 界面层提供给删除入口的两样东西：能弹出管理员授权的废纸篓执行器，以及随时可读的“当前在运行的应用”。

/// 用 NSWorkspace 移到废纸篓：遇到 root 拥有的应用会请求授权，移动后可以在废纸篓里“放回原处”
struct WorkspaceTrasher: Trasher {
    func trash(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle([url]) { moved, error in // SAFE: 界面层的授权版废纸篓执行器，调用方已通过删除入口的全部判断
                    if let trashed = moved[url] ?? moved.values.first {
                        continuation.resume(returning: trashed)
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.fileWriteUnknown))
                    }
                }
            }
        }
    }
}

/// 运行中应用的各种名字（小写）：显示名、应用包的文件名、CFBundleName / DisplayName / Executable、包名最后一段。
/// Application Support 里的目录以应用名命名（Slack、Code、discord），不是包名，靠这些名字认出它属于哪个运行中的应用。
/// 宁可多拦：名字撞上了只会让一次清理跳过。必须在主线程调用
@MainActor
func currentRunningApplicationNames() -> Set<String> {
    var names = Set<String>()
    for app in NSWorkspace.shared.runningApplications {
        if let name = app.localizedName { names.insert(name.lowercased()) }
        if let identifier = app.bundleIdentifier, let last = identifier.split(separator: ".").last { names.insert(last.lowercased()) }
        guard let url = app.bundleURL else { continue }
        names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
        if let info = Bundle(url: url)?.infoDictionary {
            for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
                if let value = info[key] as? String { names.insert(value.lowercased()) }
            }
        }
    }
    return names
}

/// 当前在运行的应用，每次现读，不用旧快照
@Sendable
func liveRunningApps() -> RunningApps {
    func read() -> RunningApps {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // 正常的 Mac 上不可能一个应用都没有；空列表说明读取失败，不能当成“没有应用在运行”
        return running.isEmpty ? .unknown : .known(running, names: MainActor.assumeIsolated { currentRunningApplicationNames() })
    }
    if Thread.isMainThread { return read() }
    return DispatchQueue.main.sync { read() }
}
