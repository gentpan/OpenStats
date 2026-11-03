import Foundation
import Testing

/// 静态审计：用户数据的删除只能经过 DeletionService。源码里任何直接的删除或移动调用，
/// 要么在删除入口自己的文件里，要么在同一行的**调用之后**写明 `// SAFE: <理由>`（自己的临时文件等），否则测试失败。
@Suite("删除入口审计")
struct DeletionAuditTests {
    /// 仓库根目录：本文件在 Packages/OpenStatsKit/Tests/CleanerTests/ 下
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 删除、移到废纸篓、移动/替换文件，以及直接起 rm 进程
    private static let destructiveCalls = ["removeItem(", "trashItem(", "unlink(", "removefile(", ".recycle(", "moveItem(",
                                           "replaceItemAt(", "rmdir(", "\"/bin/rm\"", "\"/usr/bin/rm\""]
    /// 删除入口自己的文件：只有这里允许直接调用
    private static let funnelFiles: Set<String> = [
        "Packages/OpenStatsKit/Sources/Cleaner/Deletion/DeletionService.swift",
        "Packages/OpenStatsKit/Sources/Cleaner/Deletion/Trasher.swift",
    ]
    private static let sourceRoots = ["Packages/OpenStatsKit/Sources", "Helper", "App", "Widget"]

    @Test func onlyTheDeletionFunnelRemovesFiles() throws {
        var offenders: [String] = []
        var scanned = 0
        for root in Self.sourceRoots {
            let directory = repositoryRoot.appendingPathComponent(root)
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let relative = String(url.path.dropFirst(repositoryRoot.path.count + 1))
                if Self.funnelFiles.contains(relative) { continue }
                scanned += 1
                let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }  // 整行注释（含 ///）
                    // 整行扫描，不按 // 截断：行内的 https:// 之类会把后面的调用截掉
                    guard let call = Self.destructiveCalls.compactMap({ line.range(of: $0)?.lowerBound }).min() else { continue }
                    // SAFE 必须写在调用之后，字符串里或调用之前出现的不算
                    if let safe = line.range(of: "// SAFE:"), safe.lowerBound > call { continue }
                    offenders.append("\(relative):\(index + 1)  \(trimmed)")
                }
            }
        }
        #expect(scanned > 50, "审计没有扫到足够的源文件（\(scanned)），路径可能不对")
        #expect(offenders.isEmpty, "这些地方绕过了删除入口，改用 DeletionService，或在同一行写明 // SAFE: 理由\n\(offenders.joined(separator: "\n"))")
    }

    @Test func everySafeAnnotationGivesAReason() throws {
        var empty: [String] = []
        for root in Self.sourceRoots {
            let directory = repositoryRoot.appendingPathComponent(root)
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    guard let range = line.range(of: "// SAFE:") else { continue }
                    if line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty {
                        empty.append("\(url.lastPathComponent):\(index + 1)")
                    }
                }
            }
        }
        #expect(empty.isEmpty, "SAFE 注释必须写明理由：\(empty.joined(separator: ", "))")
    }
}
