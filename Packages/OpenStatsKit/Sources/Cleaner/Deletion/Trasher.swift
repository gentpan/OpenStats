import Foundation

/// 把一个条目移到废纸篓，返回它在废纸篓里的新位置（系统没给出时为 nil）。失败就抛出，调用方不会改成永久删除。
public protocol Trasher: Sendable {
    func trash(_ url: URL) async throws -> URL?
}

/// 普通用户权限下的废纸篓移动
public struct FileManagerTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) async throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result) // SAFE: 这是删除入口里唯一的废纸篓调用点
        return result as URL?
    }
}
