import Darwin
import Foundation

/// 文件的“身份”：自己的设备号与 inode，加上父目录的设备号与 inode，以及是不是目录。
/// 扫描时记下，删除前再比一次：预览之后路径可能被换成了别的东西（改名后在原处重建、换成指向别处的链接）。
/// 用 lstat，不跟随符号链接；不比修改时间，因为目录的修改时间会随内容变化而变。
///
/// 比较规则见 `isStillTheSame(as:)`：目录必须还是同一个 inode；普通文件的 inode 允许变化，
/// 因为很多程序（偏好设置的写入、`defaults write`、先写临时文件再改名）每次保存都会原子地换掉文件。
public struct FileIdentity: Sendable, Hashable {
    public let device: Int64
    public let inode: UInt64
    public let parentDevice: Int64
    public let parentInode: UInt64
    public let isDirectory: Bool

    /// 路径不存在或读不了时为 nil
    public static func capture(_ url: URL) -> FileIdentity? {
        guard let item = status(of: url.path),
              let parent = status(of: url.deletingLastPathComponent().path) else { return nil }
        return FileIdentity(device: item.device, inode: item.inode, parentDevice: parent.device, parentInode: parent.inode,
                            isDirectory: item.isDirectory)
    }

    /// 现在的状态（`current`）相对扫描时（`self`）是否还是同一个东西：
    /// 父目录必须没换、类型必须没变；目录还必须是同一个 inode，普通文件允许被原子改写。
    public func isStillTheSame(as current: FileIdentity) -> Bool {
        guard parentDevice == current.parentDevice, parentInode == current.parentInode,
              isDirectory == current.isDirectory else { return false }
        return isDirectory ? device == current.device && inode == current.inode : true
    }

    struct Status {
        let device: Int64
        let inode: UInt64
        let mode: mode_t
        var isSymbolicLink: Bool { mode & S_IFMT == S_IFLNK }
        var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
    }

    /// lstat 的结果；失败时同时给出 errno
    static func status(of path: String) -> Status? {
        var information = stat()
        guard path.withCString({ lstat($0, &information) }) == 0 else { return nil }
        return Status(device: Int64(information.st_dev), inode: UInt64(information.st_ino), mode: information.st_mode)
    }

    /// 现在的修改时间，直接读目录项（lstat）。不要用 URL.resourceValues：同一个 URL 对象取过一次就会缓存，
    /// 扫描时取的值会原样返回给清理时，“扫描之后被改过”就检测不到了
    static func modificationDate(of path: String) -> Date? {
        var information = stat()
        guard path.withCString({ lstat($0, &information) }) == 0 else { return nil }
        let time = information.st_mtimespec
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    /// 与 status(of:) 相同，但跟随符号链接，用来判断“这个路径最终是不是某个受保护目录”
    static func resolvedStatus(of path: String) -> Status? {
        var information = stat()
        guard path.withCString({ stat($0, &information) }) == 0 else { return nil }
        return Status(device: Int64(information.st_dev), inode: UInt64(information.st_ino), mode: information.st_mode)
    }
}
