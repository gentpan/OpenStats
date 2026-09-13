import Localization
import Metrics
import SwiftUI

/// 磁盘：容量、实时读写、SSD 健康（SMART）与读写最多的应用
struct DiskPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            WeightedRow(weights: [1, 1]) {
                CapacityCard()
                ActivityCard()
            }
            .fixedSize(horizontal: false, vertical: true)
            HealthCard()
            DiskProcessesCard()
        }
    }
}

private struct CapacityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let disk = model.store.disk
        Card {
            CardHeader(icon: "internaldrive", title: disk?.volumeName ?? tr("启动磁盘"),
                       detail: disk.map { tr("共 \(Format.bytes($0.total, base: .decimal))") } ?? tr("读取中"))
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                Text(verbatim: disk.map { "\(Int(($0.usedFraction * 100).rounded()))" } ?? "—")
                    .dsFont(.xxl, weight: .semibold)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .monospacedDigit()
                Text(verbatim: "%").dsFont(.sm).foregroundStyle(DS.Palette.textSecondary)
                Spacer()
            }
            ProgressTrack(fraction: disk?.usedFraction ?? 0,
                          color: (disk?.usedFraction ?? 0) > 0.9 ? DS.Palette.warning : DS.Palette.primary)
            if let disk {
                InfoRow(label: tr("已用"), text: Format.bytes(disk.used, base: .decimal))
                InfoRow(label: tr("可用"), text: Format.bytes(disk.available, base: .decimal))
                Text(tr("可用空间包含系统可以随时清除的缓存，与访达显示一致"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ActivityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let reads = store.diskReadHistory.elements
        let writes = store.diskWriteHistory.elements
        Card {
            CardHeader(icon: "arrow.up.arrow.down", title: tr("读写速度"), detail: tr("所有磁盘合计"))
            HStack(spacing: DS.Space.s4) {
                rate(tr("读取"), store.diskActivity?.readRate, color: DS.NetworkPalette.download)
                rate(tr("写入"), store.diskActivity?.writeRate, color: DS.NetworkPalette.upload)
                Spacer()
            }
            // 上半写入、下半读取，与网络流量图同一套配色
            MirroredRateChart(upload: writes, download: reads, height: DS.Size.chartHeight * 2)
            InfoRow(label: tr("60 秒峰值")) {
                Text(verbatim: tr("读 \(Format.menuBarRate(reads.max() ?? 0)) · 写 \(Format.menuBarRate(writes.max() ?? 0))"))
            }
        }
    }

    private func rate(_ label: String, _ value: Double?, color: NSColor) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s1) {
                Circle().fill(Color(nsColor: color)).frame(width: DS.Space.s2, height: DS.Space.s2)
                Text(label).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
            }
            Text(verbatim: value.map(Format.menuBarRate) ?? "—")
                .dsFont(.lg, weight: .semibold)
                .foregroundStyle(DS.Palette.textPrimary)
                .monospacedDigit()
        }
    }
}

private struct HealthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let health = model.store.diskHealth
        Card {
            CardHeader(icon: "heart.text.square", title: tr("SSD 健康"), detail: health?.model ?? tr("读取中"))
            if let health {
                let tone = tone(health)
                HStack(alignment: .center, spacing: DS.Space.s6) {
                    RingGauge(fraction: Double(health.remainingLife) / 100, color: tone.color, size: DS.Space.s16 + DS.Space.s6) {
                        VStack(spacing: 0) {
                            Text(verbatim: "\(health.remainingLife)%")
                                .dsFont(.base, weight: .semibold)
                                .foregroundStyle(DS.Palette.textPrimary)
                                .monospacedDigit()
                            Text(tr("剩余寿命")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        StatusBadge(text: summary(health), tone: tone)
                        Text(tr("寿命按厂商估算的已用比例计算；写入量越大消耗越快，日常使用通常可用很多年"))
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                WeightedRow(weights: [1, 1], spacing: DS.Space.s6) {
                    VStack(spacing: DS.Space.s2) {
                        InfoRow(label: tr("累计写入"), text: Format.bytes(health.bytesWritten, base: .decimal))
                        InfoRow(label: tr("累计读取"), text: Format.bytes(health.bytesRead, base: .decimal))
                        InfoRow(label: tr("备用空间"), text: tr("\(health.availableSpare)%（阈值 \(health.availableSpareThreshold)%）"))
                        if let temperature = health.temperature {
                            InfoRow(label: tr("温度"), text: Format.temperature(temperature, fahrenheit: model.settings.useFahrenheit))
                        }
                    }
                    VStack(spacing: DS.Space.s2) {
                        InfoRow(label: tr("通电时间"), text: tr("\(health.powerOnHours.formatted()) 小时"))
                        InfoRow(label: tr("通电次数"), text: health.powerCycles.formatted())
                        InfoRow(label: tr("异常断电"), text: health.unsafeShutdowns.formatted())
                        InfoRow(label: tr("介质错误"), text: health.mediaErrors.formatted())
                    }
                }
            } else {
                Text(tr("正在读取 SMART 信息；外置磁盘或不支持 NVMe SMART 的磁盘不显示"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    private func tone(_ health: DiskHealth) -> Tone {
        if health.criticalWarning != 0 || health.mediaErrors > 0 || health.availableSpare < health.availableSpareThreshold { return .error }
        return health.remainingLife < 20 ? .warning : .success
    }

    private func summary(_ health: DiskHealth) -> String {
        if health.criticalWarning != 0 { return tr("磁盘报告了严重警告，建议尽快备份") }
        if health.mediaErrors > 0 { return tr("出现介质错误，建议备份") }
        if health.availableSpare < health.availableSpareThreshold { return tr("备用空间低于阈值，建议备份") }
        return health.remainingLife < 20 ? tr("寿命偏低，注意备份") : tr("状态良好")
    }
}

private struct DiskProcessesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = ProcessRowModel.grouped(model.store.processes)
            .compactMap { row in row.disk.map { (row, $0.read + $0.write) } }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
        let peak = rows.first?.1 ?? 1

        Card {
            CardHeader(icon: "list.bullet.rectangle", title: tr("读写最多的应用"), detail: tr("只含当前用户的进程"))
            if rows.isEmpty {
                Text(tr("最近没有应用在读写磁盘")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
            ForEach(Array(rows), id: \.0.id) { row, total in
                VStack(spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        AppIconCache.shared.image(bundlePath: row.bundlePath)
                            .resizable()
                            .frame(width: DS.Size.iconInline, height: DS.Size.iconInline)
                        Text(verbatim: row.title)
                            .dsFont(.xs, weight: .medium)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: tr("读 \(Format.menuBarRate(row.disk?.read ?? 0)) · 写 \(Format.menuBarRate(row.disk?.write ?? 0))"))
                            .dsFont(.xs, weight: .medium)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .monospacedDigit()
                    }
                    ProgressTrack(fraction: total / peak, height: DS.Space.s1)
                }
            }
        }
    }
}
