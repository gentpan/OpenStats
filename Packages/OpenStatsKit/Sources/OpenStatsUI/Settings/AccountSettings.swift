import AccountSync
import AppKit
import Localization
import SwiftUI

/// 设置 · 账号与同步：登录、同步状态、首次登录的二选一、退出与删除
struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDelete = false

    var body: some View {
        let sync = model.sync
        Group {
            if let user = sync.user {
                signedIn(user: user, sync: sync)
            } else {
                signedOut(sync: sync)
            }
        }
        .onAppear { sync.pageOpened() }
    }

    // MARK: 未登录

    @ViewBuilder
    private func signedOut(sync: SyncController) -> some View {
        SettingsGroup(caption: tr("账号")) {
            GroupRow(showsDivider: false) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SettingRow(title: tr("登录以同步设置"),
                               subtitle: tr("换一台 Mac 登录后，菜单栏、外观、通知与快捷键等偏好会自动恢复。不登录也能使用全部功能。")) {
                        EmptyView()
                    }
                    HStack(spacing: DS.Space.s2) {
                        ForEach(sync.providers) { provider in
                            Button {
                                sync.signIn(with: provider)
                            } label: {
                                HStack(spacing: DS.Space.s2) {
                                    ProviderLogo(provider: provider)
                                    Text(tr("使用 \(provider.title) 登录"))
                                }
                            }
                            .buttonStyle(DSButtonStyle(kind: .secondary))
                            .disabled(sync.phase == .signingIn)
                        }
                        if sync.phase == .signingIn {
                            ProgressView().controlSize(.small)
                            Button(tr("取消")) { sync.cancelSignIn() }.buttonStyle(DSButtonStyle(kind: .ghost))
                        }
                    }
                    if case .failed(let message) = sync.phase {
                        InfoBanner(icon: "exclamationmark.triangle", text: message, tone: .error)
                    }
                }
            }
        }
        privacyGroup
    }

    // MARK: 已登录

    @ViewBuilder
    private func signedIn(user: SyncUser, sync: SyncController) -> some View {
        SettingsGroup(caption: tr("账号")) {
            GroupRow(showsDivider: false) {
                HStack(spacing: DS.Space.s3) {
                    Avatar(url: user.avatar)
                    VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                        Text(user.displayName).dsFont(.sm, weight: .medium).foregroundStyle(DS.Palette.textPrimary)
                        Text(accountSubtitle(user)).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer(minLength: DS.Space.s4)
                    Button(tr("退出登录")) { sync.signOut() }
                        .buttonStyle(DSButtonStyle(kind: .secondary))
                        .disabled(sync.phase == .syncing)
                }
            }
        }

        SettingsGroup(caption: tr("同步")) {
            GroupRow(showsDivider: false) {
                SettingRow(title: statusTitle(sync), subtitle: statusSubtitle(sync)) {
                    Button(sync.phase == .syncing ? tr("正在同步…") : tr("立即同步")) { sync.syncNow() }
                        .buttonStyle(DSButtonStyle(kind: .secondary))
                        .disabled(sync.phase == .syncing || sync.conflict != nil)
                }
            }
            if let conflict = sync.conflict {
                GroupRow {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        InfoBanner(icon: "arrow.triangle.2.circlepath",
                                   text: tr("云端已有 \(conflict.remoteDevice ?? tr("另一台 Mac")) 在 \(Self.relative(conflict.remoteUpdatedAt)) 保存的设置，和这台 Mac 上的不一样。要用哪一份？"),
                                   tone: .warning)
                        HStack(spacing: DS.Space.s2) {
                            Spacer()
                            Button(tr("上传本机设置")) { sync.resolveConflict(useRemote: false) }
                                .buttonStyle(DSButtonStyle(kind: .secondary))
                            Button(tr("使用云端设置")) { sync.resolveConflict(useRemote: true) }
                                .buttonStyle(DSButtonStyle(kind: .primary))
                        }
                    }
                }
            }
            if case .failed(let message) = sync.phase {
                GroupRow { InfoBanner(icon: "exclamationmark.triangle", text: message, tone: .error) }
            }
            GroupRow {
                Text(tr("同步的内容：菜单栏项目与风格、刷新频率、外观与语言、详情弹窗的区块、连接探测、通知、快捷键、风扇安全温度、合盖电量下限。当前页面、辅助工具、历史记录与归属地库留在本机。"))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SettingsGroup(caption: tr("数据")) {
            GroupRow(showsDivider: false) {
                SettingRow(title: tr("删除云端数据"), subtitle: tr("删除账号、所有登录方式与云端保存的设置；这台 Mac 上的设置保留")) {
                    Button(tr("删除…")) { confirmingDelete = true }
                        .buttonStyle(DSButtonStyle(kind: .secondary))
                        .disabled(sync.phase == .syncing)
                        .confirmationDialog(tr("删除云端数据？"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button(tr("删除"), role: .destructive) { sync.deleteAccount() }
                            Button(tr("取消"), role: .cancel) {}
                        } message: {
                            Text(tr("账号与云端设置会立即删除，无法恢复。"))
                        }
                }
            }
        }
        privacyGroup
    }

    private var privacyGroup: some View {
        SettingsGroup(caption: tr("隐私")) {
            GroupRow(showsDivider: false) {
                SettingRow(title: tr("云端只保存邮箱、姓名与设置文档"),
                           subtitle: tr("服务器在 getopenstats.com，不上传任何监控数据；随时可以删除。")) {
                    Button(tr("隐私政策")) {
                        if let url = URL(string: "https://getopenstats.com/privacy.html") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(DSButtonStyle(kind: .ghost))
                }
            }
        }
    }

    // MARK: 文案

    private func accountSubtitle(_ user: SyncUser) -> String {
        let providers = user.providers.compactMap(SyncProvider.init(rawValue:)).map(\.title).joined(separator: " / ")
        let via = providers.isEmpty ? "" : tr("通过 \(providers) 登录")
        guard let email = user.email, !email.isEmpty, email != user.displayName else { return via }
        return via.isEmpty ? email : "\(email) · \(via)"
    }

    private func statusTitle(_ sync: SyncController) -> String {
        switch sync.phase {
        case .syncing: tr("正在同步")
        case .failed: tr("同步失败")
        default: sync.conflict != nil ? tr("等待选择") : tr("已开启同步")
        }
    }

    private func statusSubtitle(_ sync: SyncController) -> String {
        guard let date = sync.lastSyncedAt else { return tr("设置改动后 2 秒内上传；启动、唤醒与每 15 分钟检查一次云端") }
        return tr("上次同步：\(Self.relative(date))")
    }

    private static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(L10n.locale))
    }
}

/// 头像：圆形，取不到时用系统人像图标
private struct Avatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: DS.Space.s6))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .frame(width: DS.Space.s8, height: DS.Space.s8)
        .clipShape(Circle())
    }
}

/// 登录按钮上的品牌标志，16 pt 行内尺寸。Google 用四色 G；Apple 与 GitHub 的标志本身只有单色版本，
/// 按品牌规范用文字色绘制，浅色模式下为黑、深色模式下为白
struct ProviderLogo: View {
    let provider: SyncProvider
    var size: CGFloat = DS.Size.iconInline

    var body: some View {
        Group {
            switch provider {
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: size - DS.Space.s1 / 2, weight: .medium))
                    .foregroundStyle(DS.Palette.textPrimary)
            case .github:
                if let image = LogoCache.shared.image(named: "github", template: true) {
                    Image(nsImage: image).resizable().scaledToFit().foregroundStyle(DS.Palette.textPrimary)
                }
            case .google:
                if let image = LogoCache.shared.image(named: "google", template: false) {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 包内 Resources/Logos 下的 SVG：GitHub 标志来自 Octicons（MIT），Google 标志为其品牌资源
@MainActor
final class LogoCache {
    static let shared = LogoCache()
    private var images: [String: NSImage] = [:]

    func image(named name: String, template: Bool) -> NSImage? {
        if let image = images[name] { return image }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Logos"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = template
        images[name] = image
        return image
    }
}
