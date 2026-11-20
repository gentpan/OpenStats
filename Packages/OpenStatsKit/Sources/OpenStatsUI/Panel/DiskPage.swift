import Cleaner
import Localization
import Metrics
import SwiftUI

/// 磁盘：容量、实时读写、空间分析、文件系统检查、本地快照、其他磁盘、SSD 健康（SMART）与读写最多的应用
struct DiskPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            WeightedRow(weights: [1, 1]) {
                CapacityCard()
                ActivityCard()
            }
            .fixedSize(horizontal: false, vertical: true)
            SpaceCard()
            WeightedRow(weights: [1, 1]) {
                VerifyCard()
                SnapshotsCard()
            }
            .fixedSize(horizontal: false, vertical: true)
            VolumesCard()
            HealthCard()
            DiskProcessesCard()
        }
        .onAppear { model.diskTools.pageOpened() }
    }
}

// MARK: - 空间占用

private struct SpaceCard: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: SpaceScanResult.File?

    var body: some View {
        let tools = model.diskTools
        Card {
            CardHeader(icon: "chart.pie", title: tr("空间占用")) {
                HStack(spacing: DS.Space.s3) {
                    Text(tr("家目录")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                    Group {
                        switch tools.scanPhase {
                        case .scanning:
                            Button(tr("停止")) { tools.cancelScan() }.buttonStyle(DSButtonStyle(kind: .secondary))
                        case .finished:
                            Button(tr("重新分析")) { tools.startScan() }.buttonStyle(DSButtonStyle(kind: .secondary))
                        default:
                            Button(tr("开始分析")) { tools.startScan() }.buttonStyle(DSButtonStyle(kind: .primary))
                        }
                    }
                    .fixedSize()
                }
            }
            switch tools.scanPhase {
            case .idle:
                Text(tr("统计家目录里每个文件夹占多少空间，并找出最大的文件；只读取大小，不改动任何文件。文件多时需要几十秒。"))
                    .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .scanning(let progress):
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: tr("已扫描 \(progress.items) 个条目 · \(Format.bytes(progress.bytes, base: .decimal))") + (progress.current.isEmpty ? "" : " · \(progress.current)"))
                        .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary).monospacedDigit().lineLimit(1)
                }
            case .failed(let message):
                InfoBanner(icon: "exclamationmark.triangle", text: message, tone: .error)
            case .finished(let result):
                results(result, tools: tools)
            }
        }
        .confirmationDialog(tr("移到废纸篓？"), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { file in
            Button(tr("移到废纸篓"), role: .destructive) { tools.trash(file) }
            Button(tr("取消"), role: .cancel) {}
        } message: { file in
            Text(verbatim: tr("“\(file.name)”（\(Format.bytes(file.bytes, base: .decimal))）会移到废纸篓，可以从废纸篓放回。"))
        }
    }

    @ViewBuilder
    private func results(_ result: SpaceScanResult, tools: DiskToolsController) -> some View {
        let top = result.folders.prefix(8)
        let peak = top.first?.bytes ?? 1
        Text(verbatim: tr("共 \(Format.bytes(result.totalBytes, base: .decimal))，\(result.scannedItems) 个条目 · \(result.date.formatted(.relative(presentation: .named).locale(L10n.locale)))"))
            .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
        WeightedRow(weights: [1, 1], spacing: DS.Space.s6) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(tr("按文件夹")).dsFont(.xs, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                ForEach(Array(top)) { folder in
                    VStack(spacing: DS.Space.s1) {
                        HStack(spacing: DS.Space.s2) {
                            Text(verbatim: folder.name).dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: Format.bytes(folder.bytes, base: .decimal))
                                .dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textPrimary).monospacedDigit()
                        }
                        ProgressTrack(fraction: peak > 0 ? Double(folder.bytes) / Double(peak) : 0, height: DS.Space.s1, showsTrack: false)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { tools.reveal(folder.url) }
                    .help(tr("在访达中显示"))
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(tr("最大的文件")).dsFont(.xs, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                if result.largestFiles.isEmpty {
                    Text(tr("没有超过 50 MB 的文件")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                }
                ForEach(result.largestFiles.prefix(8)) { file in
                    HStack(spacing: DS.Space.s2) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: file.name).dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                            Text(verbatim: file.url.deletingLastPathComponent().path.replacingOccurrences(of: result.root.path, with: "~"))
                                .dsFont(.xs).foregroundStyle(DS.Palette.textTertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: Format.bytes(file.bytes, base: .decimal))
                            .dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textPrimary).monospacedDigit()
                        IconButton(systemName: "magnifyingglass", help: tr("在访达中显示")) { tools.reveal(file.url) }
                        if SpaceScanner.canTrash(file.url) {
                            IconButton(systemName: "trash", help: tr("移到废纸篓")) { confirming = file }
                        }
                    }
                }
                if let outcome = tools.trashOutcome {
                    InfoBanner(icon: outcome.isError ? "exclamationmark.triangle" : "checkmark.circle.fill", text: outcome.text,
                               tone: outcome.isError ? .error : .success)
                }
            }
        }
    }
}

// MARK: - 文件系统检查

private struct VerifyCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tools = model.diskTools
        Card {
            CardHeader(icon: "stethoscope", title: tr("文件系统检查")) {
                Button(tools.verifyPhase == .running ? tr("检查中…") : tr("检查")) { tools.verify() }
                    .buttonStyle(DSButtonStyle(kind: .secondary))
                    .disabled(tools.verifyPhase == .running)
                    .fixedSize()
            }
            switch tools.verifyPhase {
            case .running:
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(tr("正在核对启动盘的文件系统结构，通常几秒到几十秒")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                }
            case .finished(let result):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    StatusBadge(text: result.ok ? tr("状态正常") : tr("发现问题"), tone: result.ok ? .success : .error)
                    Text(verbatim: result.summary).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !result.ok {
                        Text(tr("请打开系统自带的“磁盘工具”，选择启动盘运行“急救”进行修复"))
                            .dsFont(.xs).foregroundStyle(DS.Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .failed(let message):
                InfoBanner(icon: "exclamationmark.triangle", text: message, tone: .error)
            case .idle:
                Text(tr("相当于“磁盘工具”里的急救，但只检查不修改：核对启动盘的目录结构、文件分配与快照元数据是否一致。"))
                    .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let verified = tools.lastVerified {
                    HStack(spacing: DS.Space.s2) {
                        StatusBadge(text: tools.lastVerifiedOK ? tr("上次检查正常") : tr("上次检查发现问题"), tone: tools.lastVerifiedOK ? .success : .error)
                        Text(verbatim: verified.formatted(.relative(presentation: .named).locale(L10n.locale)))
                            .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    }
                } else {
                    Text(tr("尚未检查")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
    }
}

// MARK: - 本地快照

private struct SnapshotsCard: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        let tools = model.diskTools
        Card {
            CardHeader(icon: "clock.arrow.circlepath", title: tr("本地快照")) {
                Button(tools.isDeletingSnapshots ? tr("删除中…") : tr("全部删除")) { confirming = true }
                    .buttonStyle(DSButtonStyle(kind: .secondary))
                    .disabled(tools.snapshots.isEmpty || tools.isDeletingSnapshots)
                    .fixedSize()
            }
            Text(tr("Time Machine 在备份之间会先在本机留下快照，它们占的空间计入“可清除”，系统缺空间时会自动删。手动删除不影响已完成的备份。"))
                .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            if !tools.snapshotsLoaded {
                Text(tr("读取中")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            } else if tools.snapshots.isEmpty {
                Text(tr("现在没有本地快照")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            } else {
                Text(tr("\(tools.snapshots.count) 个")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
            }
            ForEach(tools.snapshots.prefix(6)) { snapshot in
                InfoRow(label: snapshot.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? snapshot.identifier) {
                    Text(verbatim: snapshot.date.map { $0.formatted(.relative(presentation: .named).locale(L10n.locale)) } ?? "")
                }
            }
            if tools.snapshots.count > 6 {
                Text(verbatim: tr("还有 \(tools.snapshots.count - 6) 个")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
            if let outcome = tools.snapshotOutcome {
                InfoBanner(icon: outcome.isError ? "exclamationmark.triangle" : "checkmark.circle.fill", text: outcome.text,
                           tone: outcome.isError ? .error : .success)
            }
        }
        .confirmationDialog(tr("删除全部本地快照？"), isPresented: $confirming, titleVisibility: .visible) {
            Button(tr("删除"), role: .destructive) { tools.deleteAllSnapshots() }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("需要管理员权限。已完成的 Time Machine 备份不受影响，只是本机上这些快照对应的时间点无法再从本地恢复。"))
        }
    }
}

// MARK: - 其他磁盘

private struct VolumesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tools = model.diskTools
        if !tools.volumes.isEmpty || tools.volumeOutcome != nil {
            Card {
                CardHeader(icon: "externaldrive", title: tr("其他磁盘"), detail: tr("外置硬盘、U 盘、镜像与网络共享"))
                ForEach(tools.volumes) { volume in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: volume.isLocal ? (volume.isInternal ? "internaldrive" : "externaldrive") : "network")
                                .dsFont(.base)
                                .foregroundStyle(DS.Palette.textSecondary)
                                .frame(width: DS.Size.iconStandalone)
                            Text(verbatim: volume.name).dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: tr("可用 \(Format.bytes(volume.available, base: .decimal)) / 共 \(Format.bytes(volume.total, base: .decimal))"))
                                .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary).monospacedDigit()
                            IconButton(systemName: "magnifyingglass", help: tr("在访达中显示")) { tools.reveal(volume.url) }
                            if volume.isEjectable || volume.isRemovable || !volume.isLocal {
                                Button(tools.ejecting.contains(volume.id) ? tr("推出中…") : tr("推出")) { tools.eject(volume) }
                                    .buttonStyle(DSButtonStyle(kind: .secondary))
                                    .disabled(tools.ejecting.contains(volume.id))
                            }
                        }
                        ProgressTrack(fraction: volume.usedFraction,
                                      color: volume.usedFraction > 0.9 ? DS.Palette.warning : DS.Palette.data, height: DS.Space.s1)
                    }
                }
                if let outcome = tools.volumeOutcome {
                    InfoBanner(icon: outcome.isError ? "exclamationmark.triangle" : "checkmark.circle.fill", text: outcome.text,
                               tone: outcome.isError ? .error : .success)
                }
            }
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
            DiskComposition(disk: disk)
            if disk != nil {
                Text(tr("可清除是系统随时可以腾出的缓存；访达显示的“可用”把它算在内"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 启动磁盘里装了什么：与内存水位同样的宽条，下面两列图例。
/// 系统卷、用户数据、虚拟内存、启动与恢复等辅助卷、可清除缓存、可用；拿不到分卷数据时退回“已用 / 可清除 / 可用”。
/// 主窗口卡片与详情弹窗共用；总览里只画一条与电池条同高的细条，组成写在悬停提示里
struct DiskComposition: View {
    let disk: DiskUsage?

    var body: some View {
        let items = disk.map(Self.items) ?? []
        WaterlineBar(segments: items.map { (Double($0.bytes), $0.color) }, total: Double(disk?.total ?? 1))
        if !items.isEmpty {
            WaterlineLegend(items: items.map { .init(label: $0.label, value: Format.bytes($0.bytes, base: .decimal),
                                                     color: $0.color, help: $0.help) })
        }
    }

    static func items(_ disk: DiskUsage) -> [(label: String, bytes: UInt64, color: Color, help: String?)] {
        guard let parts = disk.breakdown else {
            return [(tr("已用"), disk.used, disk.usedFraction > 0.9 ? DS.Palette.warning : DS.Palette.data, nil),
                    (tr("可清除"), disk.purgeable, DS.Palette.dataSoft, nil),
                    (tr("空闲"), disk.free, DS.Palette.track, nil)]
        }
        return [
            (tr("用户数据"), parts.data, DS.Palette.data, tr("应用、文稿、照片与各种用户资料")),
            (tr("系统"), parts.system, DS.Palette.secondary, tr("只读的 macOS 系统卷")),
            (tr("启动与恢复"), parts.other, DS.Palette.neutral500, tr("启动、恢复、更新等系统辅助卷与快照")),
            (tr("虚拟内存"), parts.virtualMemory, DS.Palette.warning, tr("交换文件与睡眠镜像")),
            (tr("可清除"), parts.purgeable, DS.Palette.dataSoft, tr("系统随时可以腾出的缓存")),
            (tr("空闲"), parts.free, DS.Palette.track, tr("真正空着的空间，不含可清除的缓存")),
        ]
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
            // 两组数值各占一半宽度：数字长短变化时位置不动
            HStack(spacing: DS.Space.s4) {
                rate(tr("读取"), store.diskActivity?.readRate, color: DS.NetworkPalette.download)
                    .frame(maxWidth: .infinity, alignment: .leading)
                rate(tr("写入"), store.diskActivity?.writeRate, color: DS.NetworkPalette.upload)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 上半读取、下半写入，与网络流量图同一套配色与比例尺规则
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

    private func tone(_ health: DiskHealth) -> Tone { health.tone }
    private func summary(_ health: DiskHealth) -> String { health.summary }
}

extension DiskHealth {
    /// 有严重警告、介质错误或备用空间不足为红色，寿命偏低为橙色
    var tone: Tone {
        if criticalWarning != 0 || mediaErrors > 0 || availableSpare < availableSpareThreshold { return .error }
        return remainingLife < 20 ? .warning : .success
    }

    var summary: String {
        if criticalWarning != 0 { return tr("磁盘报告了严重警告，建议尽快备份") }
        if mediaErrors > 0 { return tr("出现介质错误，建议备份") }
        if availableSpare < availableSpareThreshold { return tr("备用空间低于阈值，建议备份") }
        return remainingLife < 20 ? tr("寿命偏低，注意备份") : tr("状态良好")
    }
}

private struct DiskProcessesCard: View {
    var body: some View {
        Card {
            CardHeader(icon: "list.bullet.rectangle", title: tr("读写最多的应用"), detail: tr("只含当前用户的进程"))
            DiskProcessRows(rowCount: 5)
        }
    }
}

/// 读写磁盘最多的应用，主窗口磁盘页与菜单栏弹窗共用
private struct DiskProcessRows: View {
    @Environment(AppModel.self) private var model
    let rowCount: Int

    var body: some View {
        // 顺序、条形长度与数字都按最近十几秒的平均速率：列表不随每秒的波动跳动，数字与条形也对得上
        let grouped = Dictionary(uniqueKeysWithValues: ProcessRowModel.grouped(model.store.processes).map { ($0.id, $0) })
        let rows = model.store.diskRanking.ranked(limit: rowCount)
            .compactMap { entry in grouped[entry.id].map { ($0, entry.score) } }
        let peak = rows.first?.1 ?? 1

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
                    Text(verbatim: tr("读 \(Format.menuBarRate(model.store.diskReadAverage.scores[row.id] ?? 0)) · 写 \(Format.menuBarRate(model.store.diskWriteAverage.scores[row.id] ?? 0))"))
                        .dsFont(.xs, weight: .medium)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: total / peak, height: DS.Space.s1, showsTrack: false)
            }
        }
    }
}

// MARK: - 菜单栏弹窗

/// 菜单栏“磁盘”项的窄详情：容量、读写速度、SSD 健康、读写最多的应用，区块可在设置里逐个隐藏
struct DiskPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let store = model.store

        DiskHero()

        ForEach(MenuBarItem.disk.popoverSections.filter { settings.isVisible($0) }) { section in
            switch section {
            case .diskActivity:
                let reads = store.diskReadHistory.elements
                let writes = store.diskWriteHistory.elements
                SectionCard(title: section.title, trailing: { Text(tr("所有磁盘合计")) }) {
                    HStack(spacing: DS.Space.s3) {
                        LegendItem(color: Color(nsColor: DS.NetworkPalette.download), label: tr("读取"),
                                   value: store.diskActivity.map { Format.menuBarRate($0.readRate) } ?? "—")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LegendItem(color: Color(nsColor: DS.NetworkPalette.upload), label: tr("写入"),
                                   value: store.diskActivity.map { Format.menuBarRate($0.writeRate) } ?? "—")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    MirroredRateChart(upload: writes, download: reads, height: DS.Size.chartHeight)
                    InfoRow(label: tr("60 秒峰值")) {
                        Text(verbatim: tr("读 \(Format.menuBarRate(reads.max() ?? 0)) · 写 \(Format.menuBarRate(writes.max() ?? 0))"))
                    }
                }
            case .diskHealth:
                let health = store.diskHealth
                SectionCard(title: section.title,
                            hint: tr("寿命按厂商估算的已用比例计算；写入量越大消耗越快，日常使用通常可用很多年"),
                            trailing: { Text(verbatim: health?.model ?? "") }) {
                    if let health {
                        HStack(spacing: DS.Space.s3) {
                            RingGauge(fraction: Double(health.remainingLife) / 100, color: health.tone.color, size: DS.Space.s12 + DS.Space.s2) {
                                Text(verbatim: "\(health.remainingLife)%")
                                    .dsFont(.sm, weight: .semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Palette.textPrimary)
                            }
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                StatusBadge(text: health.summary, tone: health.tone)
                                Text(verbatim: tr("剩余寿命 \(health.remainingLife)% · 已写入 \(Format.bytes(health.bytesWritten, base: .decimal))"))
                                    .dsFont(.xs)
                                    .foregroundStyle(DS.Palette.textSecondary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                        if let temperature = health.temperature {
                            InfoRow(label: tr("温度"), text: Format.temperature(temperature, fahrenheit: settings.useFahrenheit))
                        }
                        InfoRow(label: tr("通电时间"), text: tr("\(health.powerOnHours.formatted()) 小时"))
                        InfoRow(label: tr("异常断电"), text: health.unsafeShutdowns.formatted())
                    } else {
                        Text(tr("正在读取 SMART 信息；外置磁盘或不支持 NVMe SMART 的磁盘不显示"))
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .diskProcesses:
                SectionCard(title: section.title, hint: tr("只含当前用户的进程；数字与条形都是最近十几秒的平均速率"),
                            trailing: { Text(tr("最近十几秒平均")) }) {
                    DiskProcessRows(rowCount: 5)
                }
            default:
                EmptyView()
            }
        }
    }
}

/// 磁盘弹窗顶部：占用比例与卷名，右侧是可用、可清除与 SSD 健康，下面是磁盘组成的水位条与图例；
/// 插着外置磁盘时在下面逐个列出
private struct DiskHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let disk = model.store.disk
        let health = model.store.diskHealth
        let fraction = disk?.usedFraction ?? 0
        let volumes = model.diskTools.volumes.filter { !$0.isInternal }

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            PopoverHero(label: tr("磁盘占用"), value: disk.map { Format.percent($0.usedFraction) } ?? "—",
                        caption: disk.map { "\($0.volumeName) · " + tr("共 \(Format.bytes($0.total, base: .decimal))") } ?? tr("读取中"),
                        stats: [
                            HeroStat(label: tr("可用"), value: disk.map { Format.bytes($0.available, base: .decimal) } ?? "—",
                                     tone: fraction > 0.9 ? .warning : .neutral),
                            health.map { health in
                                HeroStat(label: tr("SSD 健康"), value: "\(health.remainingLife)%",
                                         tone: health.tone == .success ? .neutral : health.tone, help: health.summary)
                            },
                            health.map { health in
                                HeroStat(label: tr("已写入"), value: Format.bytes(health.bytesWritten, base: .decimal),
                                         help: tr("这块 SSD 出厂以来累计写入的数据量"))
                            },
                        ].compactMap { $0 })
            // 磁盘里装了什么：水位条加两列图例
            DiskComposition(disk: disk)
            // 外置硬盘、U 盘、镜像与网络共享
            ForEach(volumes) { volume in
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: volume.isLocal ? "externaldrive" : "network")
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: DS.Size.iconInline)
                    Text(verbatim: volume.name).dsFont(.xs).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: tr("可用 \(Format.bytes(volume.available, base: .decimal)) / 共 \(Format.bytes(volume.total, base: .decimal))"))
                        .dsFont(.xs)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
