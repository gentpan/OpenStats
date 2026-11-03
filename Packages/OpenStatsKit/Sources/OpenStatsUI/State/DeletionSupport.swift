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

/// 当前在运行的应用，每次现读，不用旧快照
@Sendable
func liveRunningApps() -> RunningApps {
    func read() -> RunningApps {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // 正常的 Mac 上不可能一个应用都没有；空列表说明读取失败，不能当成“没有应用在运行”
        return running.isEmpty ? .unknown : .known(running)
    }
    if Thread.isMainThread { return read() }
    return DispatchQueue.main.sync { read() }
}
