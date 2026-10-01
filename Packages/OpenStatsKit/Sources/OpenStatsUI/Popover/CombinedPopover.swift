import Localization
import Metrics
import SMC
import SwiftUI

/// 菜单栏合并为一个图标时点击弹出的面板：顶部一排标签切换“总览”与这台 Mac 上的各项。
/// 总览把所有指标、高占用进程与常用工具集中在一页；点标签看某一项的完整详情，与每项独立时的弹窗相同
struct CombinedPopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = tabItems
        // 风扇与温度共用一个详情页；标签对应的项目在这台 Mac 上没有时回到总览
        let requested = model.combinedPopoverTab == .fan ? .temperature : model.combinedPopoverTab
        let tab = requested.flatMap { items.contains($0) ? $0 : nil }

        PopoverFrame(width: DS.Size.dashboardPopoverWidth) {
            VStack(spacing: DS.Space.s3) {
                PopoverTabStrip(items: items, selection: tab) { model.combinedPopoverTab = $0 }
                if let tab {
                    PopoverHeader(item: tab)
                } else {
                    HealthHeader {
                        let page = PanelTab.overview
                        MiniIconButton(systemName: page.symbol, help: tr("在主窗口打开“\(page.title)”")) { model.openMainWindow(page) }
                        MiniIconButton(systemName: "gearshape", help: tr("设置")) { model.openSettings() }
                    }
                }
            }
        } content: {
            if let tab {
                PopoverDetail(item: tab).id(tab)
            } else {
                DashboardPopover()
            }
        }
    }

    /// 标签里列出全部项目（与菜单栏里开了哪些无关）；风扇并在“温度”里，没有电池的 Mac 不显示电池
    private var tabItems: [MenuBarItem] {
        MenuBarItem.allCases.filter { item in
            switch item {
            case .fan: false
            case .battery: model.store.battery != nil
            default: true
            }
        }
    }
}

// MARK: - 标签

/// 顶部标签：总览 + 各项，苹果标准分段样式（灰色底槽、各段等宽、选中段品牌蓝），名称在悬停提示里
private struct PopoverTabStrip: View {
    let items: [MenuBarItem]
    let selection: MenuBarItem?
    let select: (MenuBarItem?) -> Void
    @Namespace private var namespace

    private static var radius: CGFloat { DS.Radius.md - DS.Space.s1 / 2 }

    var body: some View {
        HStack(spacing: 0) {
            segment(nil, symbol: overviewSymbol, title: tr("总览"))
            ForEach(items) { item in
                segment(item, symbol: item.symbol, title: item.popoverTitle)
            }
        }
        .background(DS.Palette.track, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }

    private func segment(_ item: MenuBarItem?, symbol: String, title: String) -> some View {
        let selected = item == selection
        return Button { select(item) } label: {
            Image(systemName: symbol)
                .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))
                .foregroundStyle(selected ? DS.Palette.onPrimary : DS.Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Size.segmentHeight + DS.Space.s1)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                            .fill(DS.Palette.primary)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 总览的图标；主窗口“仪表盘”已经用了方格图标，这里换成仪表盘指针以示区别
private let overviewSymbol = "gauge.with.dots.needle.50percent"

// MARK: - 总览

/// 总览：两列指标卡片（与主窗口仪表盘共用），下面是电池、高占用进程与常用工具
private struct DashboardPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            WeightedRow {
                CPUTile()
                GPUTile()
            }
            WeightedRow {
                MemoryTile()
                DiskTile()
            }
            WeightedRow {
                NetworkTile()
                FanTile()
            }
            if model.store.battery != nil { BatteryCard() }
            TopProcessesCard()
            ToolsCard()
        }
        .padding(.top, DS.Space.s1)
        .padding(.bottom, DS.Space.s2)
        // 总览用实色卡片排版，不用弹窗详情的分隔线样式
        .environment(\.isPopover, false)
    }
}

/// 常用工具：摄像头与麦克风占用、防休眠与清理入口，以及累计清理记录
private struct ToolsCard: View {
    @Environment(AppModel.self) private var model
    @State private var media = MediaUsage()

    var body: some View {
        let keepAwake = model.keepAwake
        let tally = model.cleanupTally

        Card(padding: DS.Space.s3, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: media.camera ? "video.fill" : "video")
                    .foregroundStyle(media.camera ? DS.Palette.success : DS.Palette.textSecondary)
                    .help(media.camera ? tr("摄像头使用中") : tr("摄像头未在使用"))
                Image(systemName: media.microphone ? "mic.fill" : "mic")
                    .foregroundStyle(media.microphone ? DS.Palette.warning : DS.Palette.textSecondary)
                    .help(media.microphone ? tr("麦克风使用中") : tr("麦克风未在使用"))
                Text(mediaText)
                    .dsFont(.xs, weight: .medium)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                ToolButton(icon: "cup.and.saucer", title: tr("防休眠"), isOn: keepAwake.isActive) {
                    Task { await keepAwake.setActive(!keepAwake.isActive) }
                }
                ToolButton(icon: "sparkles", title: tr("清理"), isOn: false) {
                    model.openMainWindow(.cleaner)
                }
            }
            .font(.system(size: DS.TextSize.sm.rawValue, weight: .medium))

            HairlineDivider()

            HStack(spacing: DS.Space.s1) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                Text(tr("清理记录")).dsFont(.xs, weight: .semibold)
            }
            .foregroundStyle(DS.Palette.textSecondary)

            HStack(alignment: .top, spacing: DS.Space.s3) {
                stat(Format.bytes(tally.freedBytes, base: .decimal), label: tr("已清理"))
                stat("\(tally.uninstalledApps)", label: tr("已卸载"))
                stat("\(tally.optimizations)", label: tr("已优化"))
            }
        }
        .task {
            // 读设备状态很快，面板打开期间每 2 秒刷新一次
            while !Task.isCancelled {
                media = MediaUsageSampler.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var mediaText: String {
        switch (media.camera, media.microphone) {
        case (true, true): tr("摄像头、麦克风使用中")
        case (true, false): tr("摄像头使用中")
        case (false, true): tr("麦克风使用中")
        case (false, false): tr("未在使用")
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
            Text(verbatim: value)
                .dsFont(.lg, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 工具卡片里的文字按钮：图标加名称，开启时用品牌色
private struct ToolButton: View {
    let icon: String
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(isOn || hovering ? DS.Palette.primary : DS.Palette.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
