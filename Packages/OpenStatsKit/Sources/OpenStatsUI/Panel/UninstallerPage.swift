import Cleaner
import Localization
import Metrics
import SwiftUI
import UniformTypeIdentifiers

/// 卸载应用：左侧应用列表，右侧残留文件与卸载按钮；也可以把应用拖到页面上
struct UninstallerPage: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var confirming = false
    @State private var isDropTargeted = false

    var body: some View {
        let uninstaller = model.uninstaller

        HStack(alignment: .top, spacing: DS.Space.s3) {
            AppListColumn(search: $search)
                .frame(width: DS.Size.sidebarWidth + DS.Space.s16)
            PageScroll {
                if let app = uninstaller.selected {
                    AppDetailCard(app: app, confirm: { confirming = true })
                } else {
                    DropHint(isTargeted: isDropTargeted)
                }
                if let outcome = uninstaller.outcome {
                    InfoBanner(icon: outcome.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                               text: outcome.text, tone: outcome.isError ? .error : .success)
                }
            }
        }
        .padding(.leading, DS.Space.s3)
        .onAppear { if uninstaller.apps.isEmpty { uninstaller.loadApps() } }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in uninstaller.select(url: url) }
            }
            return true
        }
        .confirmationDialog(confirmationTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(tr("移到废纸篓"), role: .destructive) { uninstaller.uninstall() }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        guard let app = model.uninstaller.selected else { return "" }
        return includesApplication ? tr("卸载“\(app.name)”？") : tr("清理“\(app.name)”的残留？")
    }

    private var includesApplication: Bool {
        let uninstaller = model.uninstaller
        return uninstaller.leftovers.contains { $0.kind == .application && uninstaller.chosen.contains($0.id) }
    }

    private var confirmationMessage: String {
        let uninstaller = model.uninstaller
        let size = Format.bytes(uninstaller.chosenSize, base: .decimal)
        let count = uninstaller.chosen.count - (includesApplication ? 1 : 0)
        return includesApplication
            ? tr("应用与勾选的 \(count) 项残留会移到废纸篓，约 \(size)。清空废纸篓前都可以放回。")
            : tr("勾选的 \(count) 项残留会移到废纸篓，约 \(size)。清空废纸篓前都可以放回。")
    }
}

private struct AppListColumn: View {
    @Environment(AppModel.self) private var model
    @Binding var search: String

    var body: some View {
        let uninstaller = model.uninstaller
        let query = search.trimmingCharacters(in: .whitespaces)
        let apps = query.isEmpty ? uninstaller.apps
            : uninstaller.apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) }

        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                TextField(tr("搜索应用"), text: $search)
                    .textFieldStyle(.plain)
                    .dsFont(.sm)
                IconButton(systemName: "arrow.clockwise", help: tr("重新扫描")) { uninstaller.loadApps() }
            }
            .padding(.leading, DS.Space.s2)
            .frame(height: DS.Size.controlHeight)
            .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Palette.neutral300, lineWidth: DS.Size.stroke))

            Text(uninstaller.isLoading ? tr("正在扫描应用…") : tr("\(apps.count) 个应用，系统自带的不列出"))
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)

            ScrollView {
                LazyVStack(spacing: DS.Space.s1 / 2) {
                    ForEach(apps) { app in
                        AppListRow(app: app, size: uninstaller.sizes[app.id], isSelected: uninstaller.selected == app) {
                            uninstaller.select(app)
                        }
                    }
                }
                // 探针必须放在内容里才找得到这个列表自己的 NSScrollView；挂在外面时接了鼠标会显示一条粗的传统滚动条
                .overlayScrollers()
            }
        }
        .padding(.vertical, DS.Space.s3)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct AppListRow: View {
    let app: InstalledApp
    let size: UInt64?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                AppIconCache.shared.image(bundlePath: app.url.path)
                    .resizable()
                    .frame(width: DS.Size.iconStandalone + DS.Space.s1, height: DS.Size.iconStandalone + DS.Space.s1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: app.name)
                        .dsFont(.sm, weight: isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? DS.Palette.primary : DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: size.map { Format.bytes($0, base: .decimal) } ?? tr("计算中"))
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s1)
            .background(isSelected ? DS.Palette.primarySoft : hovering ? DS.Palette.surface : .clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AppDetailCard: View {
    @Environment(AppModel.self) private var model
    let app: InstalledApp
    let confirm: () -> Void

    var body: some View {
        @Bindable var uninstaller = model.uninstaller
        let running = uninstaller.isRunning(app)

        Card {
            HStack(spacing: DS.Space.s3) {
                AppIconCache.shared.image(bundlePath: app.url.path)
                    .resizable()
                    .frame(width: DS.Space.s12, height: DS.Space.s12)
                VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                    Text(verbatim: app.name).dsFont(.lg, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                    Text(verbatim: [app.version.map { tr("版本 \($0)") }, app.bundleIdentifier].compactMap { $0 }.joined(separator: " · "))
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if running {
                InfoBanner(icon: "exclamationmark.triangle", text: tr("\(app.name) 正在运行，卸载前需要先退出。"), tone: .warning) {
                    Button(tr("退出应用")) { uninstaller.quit(app) }
                        .buttonStyle(DSButtonStyle(kind: .secondary))
                }
            }

            HairlineDivider()
            HStack {
                Text(tr("将移到废纸篓")).dsFont(.sm, weight: .semibold).foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                Text(verbatim: uninstaller.isScanning ? tr("正在查找残留…") : tr("已选 \(uninstaller.chosen.count) 项 · \(Format.bytes(uninstaller.chosenSize, base: .decimal))"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            ForEach(AppLeftover.Kind.allCases, id: \.self) { kind in
                let items = uninstaller.leftovers.filter { $0.kind == kind }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(kind.title).dsFont(.xs, weight: .medium).foregroundStyle(DS.Palette.textSecondary)
                        ForEach(items) { item in
                            HStack(spacing: DS.Space.s2) {
                                DSCheckbox(isOn: uninstaller.chosen.contains(item.id)) { uninstaller.toggle(item) }
                                    .disabled(item.kind == .application)
                                VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                                    Text(verbatim: item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .dsFont(.xs)
                                        .foregroundStyle(DS.Palette.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(item.url.path)
                                    if item.requiresReview {
                                        Text(tr("可能与其他应用共用，默认保留"))
                                            .dsFont(.xs)
                                            .foregroundStyle(DS.Palette.textSecondary)
                                    }
                                }
                                Spacer(minLength: DS.Space.s2)
                                Text(verbatim: Format.bytes(item.size, base: .decimal))
                                    .dsFont(.xs)
                                    .foregroundStyle(DS.Palette.textTertiary)
                                    .monospacedDigit()
                                MiniIconButton(systemName: "magnifyingglass", help: tr("在访达中显示")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                        }
                    }
                }
            }

            HairlineDivider()
            HStack(spacing: DS.Space.s3) {
                Spacer()
                Button(actionTitle) { confirm() }
                    .buttonStyle(DSButtonStyle(kind: .primary))
                    .disabled(running || uninstaller.isScanning || uninstaller.isRemoving || uninstaller.chosen.isEmpty)
            }
            // 本体成功移除后才清除程序坞图标。
            Text(tr("查找应用数据、辅助组件和沙盒容器；可能共用的数据默认不勾选。所选项目会移到废纸篓，程序坞图标只在应用成功移除后清除。"))
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionTitle: String {
        let uninstaller = model.uninstaller
        if uninstaller.isRemoving { return tr("正在移除…") }
        return uninstaller.leftovers.contains { $0.kind == .application } ? tr("卸载") : tr("清理残留")
    }
}

private struct DropHint: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: DS.TextSize.xxl.rawValue))
                .foregroundStyle(isTargeted ? DS.Palette.primary : DS.Palette.textTertiary)
            Text(tr("从左侧选择应用，或把应用拖到这里"))
                .dsFont(.sm, weight: .medium)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(tr("找出应用留下的数据、缓存、容器与登录启动项，勾选后移到废纸篓，可以放回"))
                .dsFont(.xs)
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Space.s12)
        .background(isTargeted ? DS.Palette.primarySoft : DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}
