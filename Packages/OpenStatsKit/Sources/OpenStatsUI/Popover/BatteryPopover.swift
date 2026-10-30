import AppKit
import Localization
import Metrics
import SwiftUI

/// 电池详情：电量与充电状态、最近 24 小时电量曲线、功耗、健康度，以及已连接蓝牙设备的电量。
/// 没有电池的 Mac（mini、Studio、iMac）只显示蓝牙设备
struct BatteryPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let settings = model.settings
        let store = model.store
        let battery = store.battery

        BatteryHero(battery: battery)

        ForEach(MenuBarItem.battery.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .batteryHistory:
                if battery != nil {
                    BatteryHistorySection()
                }
            case .batteryHealth:
                if let battery {
                    BatteryHealthSection(battery: battery)
                }
            case .batteryBluetooth:
                BluetoothSection()
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - 顶部

private struct BatteryHero: View {
    let battery: BatteryStatus?
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            if let battery {
                let tone = battery.tone
                let temperature = model.store.sensors?.temperature(.battery)
                PopoverHero(label: tr("电量"), value: Format.percent(battery.level), valueColor: tone.color, splitsUnit: false,
                            caption: caption(battery),
                            stats: [
                                HeroStat(label: battery.isPluggedIn ? tr("电源") : tr("耗电"),
                                         value: battery.isPluggedIn ? battery.adapterWatts.map { "\($0) W" } ?? "—"
                                                                    : model.store.power?.battery.map { Format.watts(abs($0)) } ?? "—"),
                                HeroStat(label: tr("温度"),
                                         value: temperature.map { Format.temperature($0.maximum, fahrenheit: model.settings.useFahrenheit) } ?? "—",
                                         tone: temperature.map { Tone.forTemperatureText($0.maximum) } ?? .neutral),
                                HeroStat(label: tr("健康度"), value: battery.health.map(Format.percent) ?? "—",
                                         tone: (battery.health ?? 1) < 0.8 ? .warning : .neutral),
                            ])
                ProgressTrack(fraction: battery.level, color: tone.color, height: DS.Space.s2 + DS.Space.s1 / 2)
            } else {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "desktopcomputer")
                        .dsFont(.lg)
                        .foregroundStyle(DS.Palette.textSecondary)
                    VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                        Text(tr("这台 Mac 没有电池")).dsFont(.sm, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                        Text(tr("这里只显示已连接蓝牙设备的电量")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

extension BatteryHero {
    /// 状态，后面跟剩余或充满所需时间；接着电源时写一个闪电
    func caption(_ battery: BatteryStatus) -> String {
        var parts = [battery.isPluggedIn ? "⚡︎ " + battery.stateText : battery.stateText]
        if let minutes = battery.minutesRemaining {
            parts.append(battery.isCharging ? tr("\(Format.duration(minutes: minutes))后充满") : tr("还能用 \(Format.duration(minutes: minutes))"))
        }
        return parts.joined(separator: " · ")
    }
}

extension MemoryPressure {
    /// 内存压力的颜色：正常绿色、偏高橙色、严重红色
    var tone: Tone {
        switch self {
        case .normal: .success
        case .warning: .warning
        case .critical: .error
        }
    }
}

extension BatteryStatus {
    /// 电量颜色：低于 20% 红色，充电中蓝色，其余绿色。各处的电量条、圆环与数字都用它
    var tone: Tone {
        level < 0.2 ? .error : isCharging ? .primary : .success
    }

    /// 充电中 / 已充满 / 电源供电 / 电池供电
    var stateText: String {
        if isCharging { return tr("充电中") }
        if isPluggedIn { return isFullyCharged ? tr("已充满") : tr("电源供电") }
        return tr("电池供电")
    }
}

// MARK: - 电量历史

/// 最近 24 小时的电量曲线，来自本机历史库；打开期间每 5 分钟重新读一次
private struct BatteryHistorySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let values = model.history.batteryPoints.compactMap(\.battery)
        SectionCard(title: PopoverSection.batteryHistory.title, trailing: { Text(tr("最近 24 小时")) }) {
            if values.count > 1 {
                LineHistoryChart(values: values, capacity: values.count, maxValue: 1, color: DS.Palette.success,
                                 grid: isDetailPage, height: detailChartHeight(isDetailPage))
            } else {
                Text(tr("还没有足够的记录。菜单栏显示电池或打开这个页面时，每分钟记录一次电量"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            while !Task.isCancelled {
                model.history.loadBattery()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}

// MARK: - 健康

private struct BatteryHealthSection: View {
    let battery: BatteryStatus
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard(title: PopoverSection.batteryHealth.title) {
            InfoRow(label: tr("健康度")) {
                Text(verbatim: battery.health.map { Format.percent($0) } ?? "—")
                    .foregroundStyle(battery.health.map { $0 < 0.8 ? DS.Palette.warning : DS.Palette.textPrimary } ?? DS.Palette.textPrimary)
            }
            // 读到系统的值时，健康度跟系统设置一致，我们自己的推算另起一行；读不到时健康度就是推算值，不重复显示
            if battery.systemHealth != nil, let estimated = battery.estimatedHealth {
                InfoRow(label: tr("推算健康度")) {
                    Text(verbatim: Format.percent(estimated))
                        .foregroundStyle(estimated < 0.8 ? DS.Palette.warning : DS.Palette.textPrimary)
                }
            }
            InfoRow(label: tr("循环次数"), text: battery.cycleCount.map { $0.formatted() } ?? "—")
            // 温度与电源已在顶部；这里放顶部没有的电芯读数
            if let full = battery.fullChargeCapacity, let design = battery.designCapacity {
                InfoRow(label: tr("满充 / 设计容量")) {
                    UnitText(text: "\(full.formatted()) / \(design.formatted()) mAh", size: .xs)
                }
            }
            if let voltage = battery.voltage {
                InfoRow(label: tr("电压")) {
                    UnitText(text: "\(voltage.formatted(.number.precision(.fractionLength(2)))) V", size: .xs)
                }
            }
            if let amperage = battery.amperage {
                InfoRow(label: abs(amperage) < 0.01 ? tr("电流") : amperage < 0 ? tr("放电电流") : tr("充电电流")) {
                    UnitText(text: "\(abs(amperage).formatted(.number.precision(.fractionLength(2)))) A", size: .xs)
                }
                .help(tr("电池此刻的电流；接着电源时也可能短暂由电池补电"))
            }
            Text(battery.systemHealth != nil
                 ? tr("健康度与“系统设置 › 电池”里的最大容量一致；推算健康度是满充容量与设计容量之比，会随使用小幅浮动。低于 80% 时苹果建议更换电池")
                 : tr("健康度是现在充满时的容量与出厂容量之比，低于 80% 时苹果建议更换电池"))
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            // macOS 26 起系统自带充电上限；新款机型已不开放第三方写入 SMC 充电控制键，不另做一套
            if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) {
                Text(tr("充电上限可在系统设置中设为 80%–100%，长期接电源时有助于延缓电池老化"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(tr("系统电池设置…")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(DSButtonStyle(kind: .ghost))
            }
        }
    }
}

// MARK: - 蓝牙设备

/// 已连接蓝牙设备的电量；弹窗打开期间每分钟刷新，也可以手动刷新
private struct BluetoothSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bluetooth = model.bluetooth
        SectionCard(title: PopoverSection.batteryBluetooth.title, trailing: {
            if let updatedAt = bluetooth.updatedAt {
                Text(verbatim: updatedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale)))
            }
            RefreshButton(loading: bluetooth.isReading, help: tr("重新读取蓝牙设备电量")) { bluetooth.refresh() }
        }) {
            BluetoothDeviceList(devices: bluetooth.devices)
        }
    }
}

/// 蓝牙设备电量列表：本机信息页与电池弹窗共用
struct BluetoothDeviceList: View {
    let devices: [BluetoothDevice]?

    var body: some View {
        if let devices {
            if devices.isEmpty {
                Text(tr("没有已连接的蓝牙设备")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
            ForEach(devices) { device in
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: device.kind.symbol)
                        .dsFont(.sm)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: DS.Size.iconStandalone)
                    Text(verbatim: device.name)
                        .dsFont(.xs, weight: .medium)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    if device.batteries.isEmpty {
                        Text(tr("不提供电量")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    }
                    ForEach(device.batteries, id: \.label) { battery in
                        HStack(spacing: DS.Space.s1) {
                            if device.batteries.count > 1 {
                                Text(verbatim: battery.label).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                            }
                            ProgressTrack(fraction: Double(battery.percent) / 100,
                                          color: battery.percent <= 20 ? DS.Palette.error : DS.Palette.success,
                                          height: DS.Space.s1 + DS.Space.s1 / 2)
                                .frame(width: DS.Space.s8)
                            Text(verbatim: "\(battery.percent)%")
                                .dsFont(.xs, weight: .medium)
                                .foregroundStyle(DS.Palette.textPrimary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        } else {
            Text(tr("正在读取…")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
        }
    }
}
