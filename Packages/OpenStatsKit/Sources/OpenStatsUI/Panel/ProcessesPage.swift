import AppKit
import Metrics
import SwiftUI

struct ProcessesPage: View {
    enum Sort: String, CaseIterable {
        case cpu, memory

        var title: String { self == .cpu ? "按 CPU" : "按内存" }
    }

    @Environment(AppModel.self) private var model
    @State private var sort: Sort = .cpu
    private let visibleCount = 15

    var body: some View {
        let processes = sorted(model.store.processes)

        PageScroll {
            HStack {
                SegmentedControl(selection: $sort, options: Sort.allCases.map { ($0, $0.title) })
                    .frame(width: DS.Size.tileWidth)
                Spacer()
                Text(verbatim: "占用最高的 \(visibleCount) 个")
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            Card(padding: 0, spacing: 0) {
                HStack(spacing: DS.Space.s3) {
                    Text("进程")
                    Spacer()
                    Text("CPU").frame(width: DS.Size.valueColumn, alignment: .trailing)
                    Text("内存").frame(width: DS.Size.valueColumn, alignment: .trailing)
                }
                .dsFont(.xs, weight: .medium)
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s2)

                if processes.isEmpty {
                    HairlineDivider()
                    Text("正在读取进程…")
                        .dsFont(.sm)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(DS.Space.s6)
                } else {
                    ForEach(processes.prefix(visibleCount)) { process in
                        HairlineDivider()
                        ProcessRow(process: process, emphasis: sort)
                    }
                }
            }

            Text("仅列出当前用户有权限读取的进程，CPU 以单核满载为 100%。")
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    private func sorted(_ processes: [ProcessUsage]) -> [ProcessUsage] {
        switch sort {
        case .cpu: processes
        case .memory: processes.sorted { $0.memory > $1.memory }
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let emphasis: ProcessesPage.Sort
    @State private var hovering = false
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            AppIconCache.shared.image(for: process)
                .resizable()
                .frame(width: DS.Size.iconStandalone, height: DS.Size.iconStandalone)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .dsFont(.sm)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Text(cpuText)
                .dsFont(.sm, weight: emphasis == .cpu ? .semibold : .regular)
                .foregroundStyle(emphasis == .cpu ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .frame(width: DS.Size.valueColumn, alignment: .trailing)
            Text(Format.bytes(process.memory))
                .dsFont(.sm, weight: emphasis == .memory ? .semibold : .regular)
                .foregroundStyle(emphasis == .memory ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .frame(width: DS.Size.valueColumn, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .background(hovering ? DS.Palette.surfaceHover : .clear)
        .onHover { hovering = $0 }
        .contextMenu(isSnapshot ? nil : ContextMenu {
            if let path = process.appBundlePath ?? process.executablePath {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Button("拷贝 PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(process.pid), forType: .string)
            }
        })
    }

    private var title: String { process.displayName }

    private var subtitle: String {
        let pid = "PID \(process.pid)"
        guard let role = process.helperRole else { return pid }
        return "\(role) · \(pid)"
    }

    private var cpuText: String {
        let percent = process.cpu * 100
        return percent < 0.05 ? "0%" : "\(percent.formatted(.number.precision(.fractionLength(1))))%"
    }
}

/// 进程图标缓存：只保留 40px 小位图，避免每次刷新解码系统图标的全部分辨率
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private static let pixelSize: CGFloat = DS.Size.iconStandalone * 2
    private static let limit = 128
    private var cache: [String: CGImage] = [:]

    func image(for process: ProcessUsage) -> Image {
        let key = process.appBundlePath ?? "unix-executable"
        if let cached = cache[key] { return Image(decorative: cached, scale: 2) }

        let icon = process.appBundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .unixExecutable)
        var rect = NSRect(x: 0, y: 0, width: Self.pixelSize, height: Self.pixelSize)
        guard let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return Image(systemName: "app")
        }
        if cache.count >= Self.limit { cache.removeAll() }
        cache[key] = cgImage
        return Image(decorative: cgImage, scale: 2)
    }
}

extension ProcessUsage {
    private var appName: String? {
        appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }

    /// 应用的辅助进程显示为“主应用名”
    var displayName: String {
        guard let appName, name.hasPrefix(appName), name != appName else { return name }
        return appName
    }

    /// 辅助进程的角色，例如 “Helper (Renderer)”
    var helperRole: String? {
        guard let appName, name.hasPrefix(appName), name != appName else { return nil }
        let role = name.dropFirst(appName.count).trimmingCharacters(in: .whitespaces)
        return role.isEmpty ? nil : role
    }
}
