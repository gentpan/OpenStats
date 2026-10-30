import AppKit
import Localization
import Metrics
import SwiftUI

/// 本机信息：机型、芯片、内存、图形、显示器与标识。存储看磁盘页，电池与蓝牙设备看电池页，这里不重复
struct SystemInfoPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var revealSerial = false

    var body: some View {
        let store = model.store
        let system = store.system
        let topology = store.topology

        PageScroll {
            Card(padding: DS.Space.s4, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s4) {
                    Image(nsImage: NSImage(named: NSImage.computerName) ?? NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: DS.Space.s16 + DS.Space.s8, height: DS.Space.s16 + DS.Space.s8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text(verbatim: localizedModel(system.modelName))
                            .dsFont(.xl, weight: .semibold)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text(verbatim: tr("\(system.osVersion)（\(system.osBuild)）"))
                            .dsFont(.sm)
                            .foregroundStyle(DS.Palette.textSecondary)
                        // 芯片与内存在下面的“处理器”“内存与图形”里，这里只放那里没有的
                        FlowLayout(spacing: DS.Space.s2) {
                            if let disk = store.disk {
                                Chip(text: Format.capacity(disk.total, base: .decimal))
                            }
                            if let boot = system.bootDate {
                                Chip(text: tr("已运行 ") + Format.uptime(since: boot))
                                    .help(tr("启动于 \(boot.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L10n.locale)))"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            WeightedRow(weights: [1, 1]) {
                InfoCard(icon: "cpu", title: tr("处理器")) {
                    InfoRow(label: tr("芯片"), text: topology.brand)
                    InfoRow(label: tr("核心"), text: tr("\(topology.logicalCores) 核"))
                    ForEach(topology.clusters) { cluster in
                        InfoRow(label: cluster.name, text: tr("\(cluster.coreIndices.count) 核"))
                    }
                }
                InfoCard(icon: "memorychip", title: tr("内存与图形")) {
                    InfoRow(label: tr("内存"), text: Format.bytes(ProcessInfo.processInfo.physicalMemory))
                    InfoRow(label: tr("图形"), text: store.gpu?.name ?? topology.brand)
                    InfoRow(label: tr("图形核心"), text: store.gpu?.coreCount.map { tr("\($0) 核") } ?? "—")
                    InfoRow(label: tr("内存类型"), text: tr("统一内存（CPU 与 GPU 共享）"))
                }
            }

            InfoCard(icon: "display.2", title: tr("显示器")) {
                let displays = DisplayInfo.all()
                if displays.isEmpty {
                    Text(tr("没有检测到显示器")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                }
                ForEach(Array(displays.enumerated()), id: \.offset) { index, display in
                    if index > 0 { HairlineDivider() }
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .dsFont(.base)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(width: DS.Size.iconStandalone)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: display.name).dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                            Text(verbatim: display.summary).dsFont(.xs).monospacedDigit().foregroundStyle(DS.Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if display.isMain { Chip(text: tr("主显示器"), tone: .primary) }
                    }
                }
            }

            InfoCard(icon: "number", title: tr("标识")) {
                InfoRow(label: tr("机型标识符")) { CopyableText(text: system.modelIdentifier.isEmpty ? "—" : system.modelIdentifier) }
                InfoRow(label: tr("序列号")) {
                    HStack(spacing: DS.Space.s1) {
                        if revealSerial, !isSnapshot, let serial = system.serialNumber {
                            CopyableText(text: serial)
                        } else {
                            Text(verbatim: system.serialNumber.map { String(repeating: "•", count: min(12, $0.count)) } ?? "—")
                        }
                        if system.serialNumber != nil, !isSnapshot {
                            MiniIconButton(systemName: revealSerial ? "eye.slash" : "eye", help: revealSerial ? tr("隐藏序列号") : tr("显示序列号")) {
                                revealSerial.toggle()
                            }
                        }
                    }
                }
            }
        }
    }

    /// “MacBook Pro (16-inch, M5 Max)” → “MacBook Pro 16 英寸（M5 Max）”
    private func localizedModel(_ name: String) -> String {
        guard let open = name.firstIndex(of: "("), name.hasSuffix(")") else { return name }
        let base = name[..<open].trimmingCharacters(in: .whitespaces)
        var details = name[name.index(after: open)..<name.index(before: name.endIndex)]
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var size = ""
        if let index = details.firstIndex(where: { $0.hasSuffix("-inch") }) {
            size = tr(" \(details[index].dropLast("-inch".count)) 英寸")
            details.remove(at: index)
        }
        return details.isEmpty ? base + size : tr("\(base)\(size)（\(details.joined(separator: tr("，")))）")
    }

}

private struct InfoCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: icon).dsFont(.xs, weight: .semibold)
                Text(title).dsFont(.xs, weight: .semibold)
            }
            .foregroundStyle(DS.Palette.textSecondary)
            content
        }
    }
}

/// 显示器信息：名称、尺寸、原生分辨率与最高刷新率
struct DisplayInfo {
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let summary: String

    @MainActor
    static func all() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            var parts: [String] = []
            let millimeters = CGDisplayScreenSize(id)
            if millimeters.width > 0 {
                let inches = (millimeters.width * millimeters.width + millimeters.height * millimeters.height).squareRoot() / 25.4
                parts.append(tr("\(Int(inches.rounded())) 英寸"))
            }
            if let native = nativeResolution(id) { parts.append("\(native.width)×\(native.height)") }
            let points = screen.frame.size
            parts.append(tr("显示为 \(Int(points.width))×\(Int(points.height))"))
            if screen.maximumFramesPerSecond > 0 { parts.append("\(screen.maximumFramesPerSecond)Hz") }
            return DisplayInfo(name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                               isMain: CGDisplayIsMain(id) != 0, summary: parts.joined(separator: " · "))
        }
    }

    /// 面板的原生分辨率：优先取标记为原生的显示模式；缩放模式的像素可能比面板还多（如 6400×3600）
    private static func nativeResolution(_ id: CGDirectDisplayID) -> (width: Int, height: Int)? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode], !modes.isEmpty else { return nil }
        let nativeFlag: UInt32 = 0x0200_0000   // kDisplayModeNativeFlag
        let native = modes.filter { $0.ioFlags & nativeFlag != 0 }
        guard let best = (native.isEmpty ? modes : native)
            .max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }) else { return nil }
        return (best.pixelWidth, best.pixelHeight)
    }
}
