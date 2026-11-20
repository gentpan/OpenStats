import Cleaner
import Localization
import Metrics
import SwiftUI

struct CleanerPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            SummaryCard()
            if model.cleaner.needsFullDiskAccess {
                InfoBanner(icon: "lock.shield", text: tr("部分项目需要“完全磁盘访问权限”才能扫描（Safari 缓存、废纸篓、设备备份、邮件附件、Docker 磁盘、应用容器）。"), tone: .warning) {
                    Button(tr("去授权")) { model.cleaner.openFullDiskAccessSettings() }
                        .buttonStyle(DSButtonStyle(kind: .secondary))
                }
            }
            HStack(alignment: .top, spacing: DS.Space.s3) {
                VStack(spacing: DS.Space.s3) {
                    CategoryCard(category: .system)
                    CategoryCard(category: .browser)
                    CategoryCard(category: .large)
                    CategoryCard(category: .systemData)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: DS.Space.s3) {
                    CategoryCard(category: .developer)
                    CategoryCard(category: .apps)
                    CategoryCard(category: .downloads)
                    CategoryCard(category: .trash)
                }
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            CleanerFooter()
        }
        .onAppear { model.cleaner.scan(ifNeeded: true) }
    }
}

// MARK: - 汇总

private struct SummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cleaner = model.cleaner

        Card(padding: DS.Space.s3, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "sparkles").dsFont(.xs, weight: .semibold)
                Text(tr("磁盘清理")).dsFont(.xs, weight: .semibold)
                Spacer()
                if let last = cleaner.lastScan {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Chip(text: tr("扫描于 ") + Self.relative(last, now: context.date))
                    }
                }
            }
            .foregroundStyle(DS.Palette.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: headline)
                    .dsFont(.xxl, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(subline)
                    .dsFont(.sm)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }

            if let disk = model.store.disk {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    ProgressTrack(fraction: disk.usedFraction)
                    Text(verbatim: tr("\(disk.volumeName) 可用 \(Format.bytes(disk.available, base: .decimal)) · 共 \(Format.bytes(disk.total, base: .decimal))"))
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }

            if cleaner.isConfirming {
                InfoBanner(icon: "exclamationmark.triangle.fill", text: confirmationText, tone: .warning) {
                    HStack(spacing: DS.Space.s2) {
                        Button(tr("取消")) { cleaner.cancelClean() }
                            .buttonStyle(DSButtonStyle(kind: .secondary))
                        Button(tr("确认清理")) { cleaner.confirmClean() }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                    }
                }
            } else {
                HStack(spacing: DS.Space.s2) {
                    Button { cleaner.scan() } label: {
                        Label(cleaner.phase == .scanning ? tr("扫描中…") : tr("重新扫描"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DSButtonStyle(kind: .secondary))
                    .disabled(cleaner.isBusy)

                    Button { cleaner.requestClean() } label: {
                        Label(cleaner.phase == .cleaning ? tr("清理中…") : tr("清理所选 \(Format.bytes(cleaner.selectedBytes, base: .decimal))"),
                              systemImage: "trash")
                    }
                    .buttonStyle(DSButtonStyle(kind: .primary))
                    .disabled(cleaner.isBusy || cleaner.selectedBytes == 0)
                    Spacer()
                }
            }
        }
    }

    private var headline: String {
        let cleaner = model.cleaner
        if cleaner.phase == .finished { return Format.bytes(cleaner.report?.freedBytes ?? 0, base: .decimal) }
        return cleaner.scans.isEmpty ? tr("扫描中") : Format.bytes(cleaner.totalBytes, base: .decimal)
    }

    private var subline: String {
        let cleaner = model.cleaner
        switch cleaner.phase {
        case .idle, .scanning: return tr("正在计算可清理空间")
        case .cleaning: return tr("正在清理…")
        case .ready:
            let base = tr("可清理 · 已选 \(cleaner.selectedScans.count) 项")
            return cleaner.manualBytes > 0 ? base + tr(" · 另有 \(Format.bytes(cleaner.manualBytes, base: .decimal)) 需手动处理") : base
        case .finished:
            guard let report = cleaner.report else { return "" }
            var parts = [tr("已释放")]
            if report.trashedBytes > 0 { parts.append(tr("另有 \(Format.bytes(report.trashedBytes, base: .decimal)) 移到废纸篓")) }
            if report.skippedCount > 0 { parts.append(tr("跳过 \(report.skippedCount) 项")) }
            if !report.failures.isEmpty { parts.append(tr("\(report.failures.count) 项失败")) }
            return parts.joined(separator: " · ")
        }
    }

    private var confirmationText: String {
        let cleaner = model.cleaner
        let count = cleaner.selectedItemCount
        let trashNote = model.settings.cleanPrefersTrash ? tr("所有内容先移到废纸篓。") : tr("缓存与日志直接删除，下载内容移到废纸篓。")
        return tr("将清理 \(count) 个项目，共 \(Format.bytes(cleaner.selectedBytes, base: .decimal))。\(trashNote)")
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 1 ? tr("刚刚") : tr("\(Format.duration(minutes: minutes))前")
    }
}

// MARK: - 分类

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: CleanCategory

    var body: some View {
        let scans = model.cleaner.scans(in: category)
        // 全是只看不删的分类（系统数据）显示列出的总量；其余显示可清理的总量
        let analysisOnly = !scans.isEmpty && scans.allSatisfy(\.rule.isManual)
        let total = scans.filter { analysisOnly ? $0.blocked == nil : $0.isCleanable }.reduce(0) { $0 + $1.totalSize }

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            HStack {
                Text(category.title).dsFont(.xs, weight: .semibold).foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                if total > 0 {
                    Text(verbatim: Format.bytes(total, base: .decimal))
                        .dsFont(.xs, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            if scans.isEmpty {
                ForEach(0..<placeholderRows, id: \.self) { _ in
                    PlaceholderLine().frame(height: DS.Size.controlHeight)
                }
            }
            ForEach(Array(scans.enumerated()), id: \.element.id) { index, scan in
                if index > 0 { HairlineDivider() }
                RuleRow(scan: scan)
            }
        }
    }

    /// 扫描完成前占位，保持面板高度稳定
    private var placeholderRows: Int {
        RuleCatalog.rules().filter { $0.category == category }.count
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let scan: RuleScan
    @State private var expanded = false
    @State private var showsAll = false

    var body: some View {
        let cleaner = model.cleaner
        let manual = scan.rule.isManual
        let selected = cleaner.selection.contains(scan.id) && scan.isCleanable
        let hasItems = scan.blocked == nil && !scan.items.isEmpty

        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                if manual {
                    // 仅提示：占住复选框的位置，不能勾选
                    Image(systemName: "info.circle")
                        .dsFont(.sm)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: DS.Size.iconInline)
                        .help(tr("只显示占用，需要你自己处理"))
                } else {
                    DSCheckbox(isOn: selected, isMixed: cleaner.isPartial(scan)) { cleaner.toggle(scan) }
                        .disabled(!scan.isCleanable || cleaner.isBusy)
                }
                Image(systemName: scan.rule.symbol)
                    .dsFont(.sm)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: DS.Size.iconStandalone)
                VStack(alignment: .leading, spacing: 0) {
                    Text(scan.rule.title)
                        .dsFont(.sm, weight: .medium)
                        .foregroundStyle(scan.blocked == nil ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                    Text(statusText)
                        .dsFont(.xs)
                        .foregroundStyle(scan.blocked == nil ? DS.Palette.textTertiary : DS.Palette.warning)
                        .lineLimit(1)
                }
                .help(scan.rule.detail)
                Spacer(minLength: DS.Space.s1)
                if hasItems {
                    Text(verbatim: Format.bytes(scan.totalSize, base: .decimal))
                        .dsFont(.sm, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(manual ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .dsFont(.xs, weight: .semibold)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .frame(width: DS.Size.iconStandalone, height: DS.Size.iconStandalone)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(manual ? tr("查看包含的项目和处理办法") : tr("查看并挑选包含的项目"))
                }
            }

            if expanded && hasItems {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if let advice = scan.rule.manualAdvice {
                        Text(advice)
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.leading, DS.Size.iconStandalone + DS.Space.s2)
                    }
                    ForEach(visibleItems) { item in
                        ItemRow(scan: scan, item: item)
                    }
                    if scan.items.count > Self.previewLimit {
                        Button(showsAll ? tr("收起") : tr("显示全部 \(scan.items.count) 项")) { showsAll.toggle() }
                            .buttonStyle(.plain)
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .padding(.leading, DS.Size.iconStandalone + DS.Space.s2)
                    }
                }
                .padding(.leading, DS.Size.iconInline + DS.Space.s2)
            }
        }
    }

    private static let previewLimit = 6

    private var visibleItems: [CleanItem] {
        showsAll ? scan.items : Array(scan.items.prefix(Self.previewLimit))
    }

    private var statusText: String {
        if let blocked = scan.blocked { return blocked.title }
        if scan.items.isEmpty { return scan.rule.isManual ? tr("没有发现") : tr("无需清理") }
        if scan.rule.isManual { return tr("\(scan.items.count) 项 · 需手动处理") }
        let chosen = model.cleaner.selectedItems(in: scan).count
        var text = model.cleaner.isPartial(scan) ? tr("已选 \(chosen)/\(scan.items.count) 项") : tr("\(scan.items.count) 项")
        if scan.skippedCount > 0 { text += tr(" · \(scan.skippedCount) 项使用中") }
        if scan.rule.policy == .trash { text += tr(" · 移到废纸篓") }
        return text
    }
}

/// 展开后的一项：可清理的规则可以单独取消勾选；点名字在访达中显示
private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let scan: RuleScan
    let item: CleanItem

    var body: some View {
        let cleaner = model.cleaner
        HStack(spacing: DS.Space.s2) {
            // 不可勾选（仅提示）时留出同样的宽度，名字和上面的说明对齐
            if scan.isCleanable {
                DSCheckbox(isOn: cleaner.isSelected(item, in: scan)) { cleaner.toggle(item, in: scan) }
                    .disabled(cleaner.isBusy)
                    .frame(width: DS.Size.iconStandalone)
            } else {
                Color.clear.frame(width: DS.Size.iconStandalone, height: 1)
            }
            Button { cleaner.reveal(item) } label: {
                HStack {
                    Text(item.title).dsFont(.xs).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: Format.bytes(item.size, base: .decimal)).dsFont(.xs).monospacedDigit()
                }
                .foregroundStyle(DS.Palette.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.url.path)
        }
    }
}

// MARK: - 底部

private struct CleanerFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        HStack(spacing: DS.Space.s3) {
            DSToggle(isOn: $settings.cleanPrefersTrash, label: tr("缓存也先移到废纸篓"))
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("缓存也先移到废纸篓")).dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                Text(tr("可以恢复，但清空废纸篓前不会释放空间")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer()
            Button(tr("查看清理日志")) { model.cleaner.revealLog() }
                .buttonStyle(DSButtonStyle(kind: .ghost))
        }
        .padding(.horizontal, DS.Space.s1)
    }
}
