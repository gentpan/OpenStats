import AppKit
import HelperShared
import Localization
import Metrics
import SwiftUI

struct NetworkPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let settings = model.settings
        let store = model.store
        let rate = store.network

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            NetworkHero(rate: rate)
        }

        ForEach(MenuBarItem.network.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .networkHistory: TrafficHistorySection()
            case .networkProbe: ProbeSection()
            case .networkInterface: InterfaceSection()
            case .networkAddresses: AddressSection()
            case .networkPurity: PuritySection()
            case .networkDNS: DNSSection()
            case .networkProcesses: NetworkProcessesSection()
            default: EmptyView()
            }
        }
    }
}

/// 网络顶部：下载与上传并排两列，同样大的数字，各用自己的颜色；下面一行是连接摘要，右侧是延迟与丢包。
/// 延迟和丢包取自后台的连接探测（最近 60 次），关掉探测时不显示
private struct NetworkHero: View {
    let rate: NetworkRate?
    @Environment(AppModel.self) private var model

    var body: some View {
        let network = model.network
        let probes = network.probes.elements
        let probing = model.settings.probeEnabled && !probes.isEmpty
        let latest = probes.last
        let latency = latest?.latency
        // 探路由器时路由器有回应、外网却不通：读数不能写成“4 ms”让人以为一切正常
        let routerOnly = latest?.state == .routerOnly
        let loss = probes.isEmpty ? 0 : Double(probes.filter { $0.latency == nil }.count) / Double(probes.count)

        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // 两列各占一半宽度：数字长短变化时位置不动
            HStack(alignment: .top, spacing: DS.Space.s3) {
                RateColumn(arrow: "↓", label: tr("下载"), color: DS.NetworkPalette.download,
                           value: rate.map { Format.menuBarRate($0.downloadBytesPerSecond) } ?? "—")
                RateColumn(arrow: "↑", label: tr("上传"), color: DS.NetworkPalette.upload,
                           value: rate.map { Format.menuBarRate($0.uploadBytesPerSecond) } ?? "—")
            }
            HStack(spacing: DS.Space.s3) {
                Text(verbatim: connectionSummary(network.details))
                    .dsFont(.xs)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DS.Space.s2)
                if probing {
                    ProbeStat(label: tr("延迟"),
                              value: routerOnly ? tr("外网不通") : latency.map { "\(Int($0.rounded())) ms" } ?? tr("超时"),
                              tone: routerOnly ? .warning : latency.map { $0 >= 300 ? .error : $0 >= 100 ? .warning : .neutral } ?? .error,
                              help: routerOnly ? tr("路由器有回应，但路由器之外的网络没有回应") : tr("到探测目标的往返时间"))
                    ProbeStat(label: tr("丢包"), value: Format.percent(loss),
                              tone: loss >= 0.05 ? .error : loss > 0 ? .warning : .neutral,
                              help: tr("最近 \(probes.count) 次探测里没有回应的比例"))
                }
            }
        }
    }

    /// “Wi-Fi「家里」· 192.168.1.5”；有 VPN 时在后面注明
    private func connectionSummary(_ details: NetworkDetails?) -> String {
        guard let physical = details?.physical else { return details == nil ? tr("正在读取…") : tr("未连接网络") }
        var parts = [physical.wifi?.ssid.map { "\(physical.displayName)「\($0)」" } ?? physical.displayName]
        if let address = physical.ipv4.first { parts.append(address) }
        if details?.tunnel != nil { parts.append("VPN") }
        return parts.joined(separator: " · ")
    }
}

/// 顶部的一列速率：彩色箭头 + 名称一行小字，下面是大号读数
private struct RateColumn: View {
    let arrow: String
    let label: String
    let color: NSColor
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
            HStack(spacing: DS.Space.s1 / 2) {
                Text(verbatim: arrow).fontWeight(.bold).foregroundStyle(Color(nsColor: color))
                Text(verbatim: label).foregroundStyle(DS.Palette.textTertiary)
            }
            .dsFont(.xs)
            UnitText(text: value, size: .xl)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 连接摘要右侧的延迟 / 丢包：名称淡色、读数按好坏着色
private struct ProbeStat: View {
    let label: String
    let value: String
    let tone: Tone
    let help: String

    var body: some View {
        HStack(spacing: DS.Space.s1 / 2) {
            Text(verbatim: label).foregroundStyle(DS.Palette.textTertiary)
            Text(verbatim: value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? DS.Palette.textPrimary : tone.color)
        }
        .dsFont(.xs)
        .lineLimit(1)
        .fixedSize()
        .help(help)
    }
}

// MARK: - 流量历史

private struct TrafficHistorySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let store = model.store
        let network = model.network
        let upload = store.uploadHistory.elements
        let download = store.downloadHistory.elements

        // 峰值放在标题行，图表上不压任何文字
        SectionCard(title: PopoverSection.networkHistory.title, trailing: {
            HStack(spacing: DS.Space.s1) {
                // 与顶部一致：先下载、后上传
                Text(tr("60 秒峰值"))
                peak("↓", download, color: DS.NetworkPalette.download)
                peak("↑", upload, color: DS.NetworkPalette.upload)
            }
            .monospacedDigit()
        }) {
            MirroredRateChart(upload: upload, download: download,
                              height: isDetailPage ? DS.Size.chartHeight * 3 : DS.Size.chartHeight + DS.Space.s2)
            if let totals = store.network {
                let counted = network.trafficTotals(totals)
                // 累计流量并成一行：左边写从什么时候起算，右边是下载、上传与重置按钮
                HStack(spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                        Text(network.trafficBaseline != nil ? tr("重置后累计") : tr("开机后累计"))
                            .dsFont(.xs)
                            .foregroundStyle(DS.Palette.textSecondary)
                        if let since = network.trafficBaseline?.date {
                            Text(verbatim: tr("自 \(since.formatted(Date.FormatStyle(locale: L10n.locale).month().day().hour().minute())) 起"))
                                .dsFont(.xs)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                    Spacer(minLength: DS.Space.s2)
                    total("↓", counted.download, color: DS.NetworkPalette.download)
                    total("↑", counted.upload, color: DS.NetworkPalette.upload)
                    MiniIconButton(systemName: "arrow.counterclockwise",
                                   help: tr("重置上传与下载统计：从现在起重新累计。重启后自动回到开机后的累计；右键可改回")) {
                        network.resetTraffic(totals)
                    }
                    .contextMenu {
                        if network.trafficBaseline != nil {
                            Button(tr("改回开机后累计")) { network.clearTrafficBaseline() }
                        }
                    }
                }
            }
        }
    }

    private func total(_ arrow: String, _ bytes: UInt64, color: NSColor) -> some View {
        HStack(spacing: DS.Space.s1 / 2) {
            Text(verbatim: arrow).fontWeight(.bold).foregroundStyle(Color(nsColor: color))
            Text(verbatim: Format.bytes(bytes, base: .decimal))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .dsFont(.sm)
        .lineLimit(1)
        .fixedSize()
    }

    private func peak(_ arrow: String, _ values: [Double], color: NSColor) -> some View {
        HStack(spacing: DS.Space.s1 / 2) {
            Text(verbatim: arrow).foregroundStyle(Color(nsColor: color)).fontWeight(.semibold)
            // 写真实的峰值；图表空闲时按 64 KB/s 缩放只是为了不把噪声放大，不代表读数
            Text(verbatim: Format.menuBarRate(values.max() ?? 0))
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }
}

// MARK: - 连接探测

private struct ProbeSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        @Bindable var settings = model.settings
        let network = model.network

        // 只看通不通，标题右侧不再写探测地址与频率
        SectionCard(title: PopoverSection.networkProbe.title) {
            if settings.probeEnabled {
                // 只用来看网络通不通：60 格是最近 60 次探测，排成两行细格
                let samples = network.probes.elements
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ProbeGrid(samples: samples, columns: NetworkController.probeCapacity / 2, rows: 2)
                    // 橙格只在探路由器时出现，出现了才解释一句
                    if samples.suffix(NetworkController.probeCapacity).contains(where: { $0.state == .routerOnly }) {
                        Text(tr("橙格：路由器有回应，但外网不通")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    }
                }
            } else {
                HStack {
                    Text(tr("定时 ping 一个地址，记录网络是否通畅")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Button(tr("开启")) { settings.probeEnabled = true }
                        .buttonStyle(DSButtonStyle(kind: .ghost))
                }
            }
        }
    }
}

// MARK: - 接口

private struct InterfaceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let network = model.network
        let details = network.details
        let physical = details?.physical

        SectionCard(title: PopoverSection.networkInterface.title) {
            if let physical {
                InfoRow(label: tr("网卡"), text: tr("\(physical.displayName)（\(physical.bsdName)）"))
                InfoRow(label: tr("状态")) {
                    StatusBadge(text: physical.isUp ? tr("已连接") : tr("未连接"), tone: physical.isUp ? .success : .error)
                }
                InfoRow(label: tr("物理地址")) { CopyableText(text: physical.hardwareAddress ?? "—") }
                if let wifi = physical.wifi {
                    if let ssid = wifi.ssid { InfoRow(label: tr("网络名称"), text: ssid) }
                    InfoRow(label: tr("信号强度"), text: "\(wifi.rssi) dBm · \(signalQuality(wifi.rssi))")
                    InfoRow(label: tr("传输速率"), text: "\(Int(wifi.transmitRate)) Mbps")
                }
            } else {
                Text(details == nil ? tr("正在读取…") : tr("未连接网络")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
            if let tunnel = details?.tunnel {
                InfoRow(label: tr("VPN / 代理"), text: tr("\(tunnel.name)（\(tunnel.bsdName)）"))
            }
        }
    }

    private func signalQuality(_ rssi: Int) -> String {
        rssi >= -50 ? tr("极好") : rssi >= -60 ? tr("良好") : rssi >= -70 ? tr("一般") : tr("较弱")
    }
}

// MARK: - 地址

private struct AddressSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isPopover) private var isPopover

    var body: some View {
        let network = model.network
        let physical = network.details?.physical
        let lookup = model.settings.publicIPLookup
        let publicAddresses = network.publicAddresses

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            header
            // 本地地址与路由器只在主窗口的网络页显示，菜单栏弹窗里只看公网
            if !isPopover {
                InfoRow(label: tr("本地 IPv4")) { CopyableText(text: physical?.ipv4.first ?? "—") }
                // 没有 IPv6 就不占行：网卡没有 IPv6 地址时不显示本地 IPv6，拿不到公网 IPv6 时不显示公网 IPv6
                if let localIPv6 = physical?.ipv6.first {
                    InfoRow(label: tr("本地 IPv6")) { CopyableText(text: localIPv6) }
                }
                InfoRow(label: tr("路由器")) { CopyableText(text: physical?.router ?? "—") }
            }
            if lookup {
                // 国旗放在公网 IP 前面；国家与城市写在下面的“归属地”一行
                InfoRow(label: tr("公网 IPv4")) {
                    HStack(spacing: DS.Space.s2) {
                        if let code = publicAddresses?.countryCode {
                            FlagImage(countryCode: code)
                        }
                        publicValue(publicAddresses?.ipv4, loading: network.isLookingUpPublic)
                    }
                }
                if let publicIPv6 = publicAddresses?.ipv6 {
                    InfoRow(label: tr("公网 IPv6")) { CopyableText(text: publicIPv6) }
                }
                if let publicAddresses, let code = publicAddresses.countryCode {
                    InfoRow(label: tr("归属地")) {
                        Text(verbatim: location(publicAddresses, code: code))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let asn = publicAddresses?.asn {
                    InfoRow(label: "ASN") { CopyableText(text: asn) }
                }
                if let organization = publicAddresses?.organization {
                    InfoRow(label: tr("网络运营方")) { Text(verbatim: organization).lineLimit(1).truncationMode(.middle) }
                }
                // 只放两个徽章：原生 / 广播，以及 IP 类型（机房 IP、住宅 IP 等）；反向解析、住宅概率等细节不在弹窗里占行
                if let publicAddresses, !Self.badges(publicAddresses).isEmpty {
                    FlowLayout(spacing: DS.Space.s2) {
                        ForEach(Self.badges(publicAddresses), id: \.text) { badge in
                            TagBadge(icon: badge.icon, text: badge.text, tone: badge.tone)
                        }
                    }
                    .padding(.top, DS.Space.s1)
                }
            } else {
                InfoRow(label: tr("公网 IP"), text: tr("查询已关闭"))
            }
        }
    }

    @ViewBuilder
    private func publicValue(_ value: String?, loading: Bool) -> some View {
        if loading && value == nil {
            Text(tr("查询中…")).foregroundStyle(DS.Palette.textTertiary)
        } else {
            CopyableText(text: value ?? "—")
        }
    }

    /// 国家 · 省 / 州 · 城市；英文界面优先用英文地名，重复的相邻项只留一个
    private func location(_ addresses: PublicAddresses, code: String) -> String {
        GeoText.location(countryCode: code, region: addresses.region, regionEnglish: addresses.regionEnglish,
                         city: addresses.city, cityEnglish: addresses.cityEnglish)
    }

    /// 标题行：IP 地址 ……… [IPv4 | IPv6] ⟳；数据来源的字标只放在下面的纯净度区块里
    private var header: some View {
        let network = model.network
        return HStack(spacing: DS.Space.s2) {
            Text(PopoverSection.networkAddresses.title)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            if model.settings.publicIPLookup {
                HStack(spacing: DS.Space.s1) {
                    if network.hasDualStack {
                        PillSwitch(selection: Binding(get: { network.publicFamily }, set: { network.publicFamily = $0 }),
                                   options: IPFamily.allCases.map { ($0, $0.title) })
                    }
                    RefreshButton(loading: network.isLookingUpPublic, help: tr("强制刷新：忽略缓存，立即重新查询公网 IP 与归属地")) {
                        network.lookUpPublicAddresses(force: true)
                    }
                }
            }
            MiniIconButton(systemName: "arrow.triangle.branch", help: tr("出口与分流：检查 VPN 与代理是否生效、各网站从哪个出口出去")) {
                model.openEgressWindow()
            }
        }
    }

    struct Badge: Equatable {
        let icon: String
        let text: String
        let tone: TagBadge.Tone
    }

    /// 结论性徽章：原生 / 广播、住宅 / 机房、ASN 的类型
    static func badges(_ addresses: PublicAddresses) -> [Badge] {
        var badges: [Badge] = []
        if let isNative = addresses.isNative {
            badges.append(isNative ? Badge(icon: "checkmark.shield.fill", text: tr("原生 IP"), tone: .success)
                                   : Badge(icon: "antenna.radiowaves.left.and.right", text: tr("广播 IP"), tone: .warning))
        }
        if let ipType = addresses.ipType {
            if let known = GeoText.ipTypeBadge(ipType) {
                badges.append(Badge(icon: known.icon, text: known.text, tone: known.tone))
            } else {
                badges.append(Badge(icon: "questionmark.circle", text: ipType, tone: .neutral))
            }
        }
        return badges
    }
}

// MARK: - IP 纯净度

/// cleanip.io 给出的纯净度评分与风险标记
private struct PuritySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isPopover) private var isPopover

    var body: some View {
        // 菜单栏弹窗里默认收起成一行，只显示分数与等级
        if isPopover, !model.settings.isExpanded(.networkPurity) {
            let summary = collapsedSummary
            CollapsedSection(title: PopoverSection.networkPurity.title, summary: summary.text, summaryColor: summary.color) {
                withAnimation(DS.Motion.quick) { model.settings.setExpanded(.networkPurity, true) }
            }
        } else {
            card
        }
    }

    private var collapsedSummary: (text: String, color: Color) {
        let network = model.network
        if let purity = network.publicAddresses?.purity {
            return ("\(purity.score) \(purity.grade)", DS.Grade.color(for: purity.score))
        }
        if !model.settings.publicIPLookup { return (tr("查询已关闭"), DS.Palette.textTertiary) }
        if network.isLookingUpPublic { return (tr("正在查询…"), DS.Palette.textTertiary) }
        return ("—", DS.Palette.textTertiary)
    }

    @ViewBuilder
    private var card: some View {
        let settings = model.settings
        let network = model.network
        let addresses = network.publicAddresses
        let hint = tr("纯净度看信誉、来路、邻居与网络类型四项；机房 IP 常见信誉高、来路和类型偏低。数据来自 cleanip.io")

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            header(addresses)
            if let purity = addresses?.purity {
                // 分数在左、cleanip.io 字标在右，色带在下占满整行
                HStack(spacing: DS.Space.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                        Text(verbatim: "\(purity.score)")
                            .dsFont(.xxl, weight: .semibold)
                            .foregroundStyle(DS.Grade.color(for: purity.score))
                            .monospacedDigit()
                        Text(verbatim: purity.grade)
                            .dsFont(.base, weight: .semibold)
                            .foregroundStyle(DS.Grade.color(for: purity.score))
                        Text(verbatim: "/ 100").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
                    }
                    .help(hint)
                    Spacer(minLength: DS.Space.s2)
                    CleanIPLink(height: DS.Size.iconInline,
                                url: addresses?.reportURL ?? CleanIPLink.site,
                                help: tr("评分由 cleanip.io 提供，点击查看完整报告"))
                }
                // 风险评分与风险标记不在这里列出，想看细节点右上角的 cleanip.io 看完整报告
                ScoreBand(score: purity.score).help(hint)
                if let recommendation = purity.recommendation, !L10n.isEnglish {
                    Text(verbatim: recommendation)
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !settings.publicIPLookup {
                Text(tr("查询已关闭")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            } else if network.isLookingUpPublic {
                Text(tr("正在查询…")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            } else {
                Text(tr("暂时没有拿到评分，稍后会再试")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    /// 标题行：IP 纯净度 [IPv4] 置信度 92% ……… [↗ ⟳ ⌃]
    /// 置信度是标题旁的一行浅色小字，不再用带框徽章；右侧的完整报告、刷新、收起并成一组按钮
    private func header(_ addresses: PublicAddresses?) -> some View {
        let network = model.network
        return HStack(spacing: DS.Space.s2) {
            Text(PopoverSection.networkPurity.title)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
            if let family = network.shownFamily {
                TagBadge(text: family.title, tone: .primary, compact: true)
            }
            if let confidence = addresses?.purity?.confidence {
                HStack(spacing: DS.Space.s1 / 2) {
                    Text(tr("置信度")).foregroundStyle(DS.Palette.textTertiary)
                    Text(verbatim: "\(confidence)%")
                        .fontWeight(.medium)
                        .foregroundStyle(Self.confidenceColor(confidence))
                        .monospacedDigit()
                }
                .dsFont(.xs)
                .lineLimit(1)
                .fixedSize()
                .help(tr("cleanip.io 对这次评分的把握：各数据源结论越一致越高"))
            }
            Spacer(minLength: 0)
            HeaderActionGroup {
                if let url = addresses?.reportURL {
                    MiniIconButton(systemName: "arrow.up.forward", help: tr("在 cleanip.io 查看这个 IP 的完整报告")) {
                        NSWorkspace.shared.open(url)
                    }
                }
                RefreshButton(loading: network.isLookingUpPublic, help: tr("强制刷新：忽略缓存，立即重新查询公网 IP 与归属地")) {
                    network.lookUpPublicAddresses(force: true)
                }
                if isPopover {
                    MiniIconButton(systemName: "chevron.up", help: tr("收起")) {
                        withAnimation(DS.Motion.quick) { model.settings.setExpanded(.networkPurity, false) }
                    }
                }
            }
        }
    }

    /// 置信度高的绿、中等的灰、低的黄
    static func confidenceColor(_ confidence: Int) -> Color {
        confidence >= 80 ? DS.Palette.success : confidence >= 50 ? DS.Palette.textSecondary : DS.Palette.warning
    }
}

// MARK: - DNS

private struct DNSSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isPopover) private var isPopover
    @State private var editingManual = false
    @State private var manualText = ""

    var body: some View {
        // 菜单栏弹窗里默认收起成一行，只显示正在使用的 DNS
        if isPopover, !model.settings.isExpanded(.networkDNS) {
            let servers = model.network.details?.dnsServers ?? []
            CollapsedSection(title: PopoverSection.networkDNS.title,
                             summary: servers.first.map { servers.count > 1 ? "\($0) +\(servers.count - 1)" : $0 } ?? "—") {
                withAnimation(DS.Motion.quick) { model.settings.setExpanded(.networkDNS, true) }
            }
        } else {
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        let network = model.network
        let maintenance = model.maintenance
        let physical = network.details?.physical
        let manual = physical?.manualDNS ?? []
        let matched = DNSPreset.matching(manual)

        // 走代理隧道时标题旁放一个叹号，悬停才显示说明；刷新缓存是图标按钮，放在标题行右侧
        let tunnelWarning = network.details?.tunnel.map { tunnel in
            AnyView(Image(systemName: "exclamationmark.circle")
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.warning)
                .help(tr("流量经过 \(tunnel.name)，系统 DNS 可能由它接管，修改后不一定生效。"))
                .accessibilityLabel(tr("流量经过 \(tunnel.name)，系统 DNS 可能由它接管，修改后不一定生效。")))
        }
        // 网络服务与线路做成两个徽章：Wi-Fi / 有线，直连或经过哪个代理
        let actions = HStack(spacing: DS.Space.s2) {
            if let physical {
                TagBadge(icon: physical.wifi != nil ? "wifi" : "cable.connector", text: physical.serviceName, tone: .neutral, compact: true)
                if let tunnel = network.details?.tunnel {
                    TagBadge(icon: "globe", text: tr("经 \(tunnel.name)"), tone: .primary, compact: true)
                } else {
                    TagBadge(icon: "arrow.right", text: tr("直连"), tone: .neutral, compact: true)
                }
            }
            RefreshButton(loading: maintenance.running == .flushDNS, help: tr("刷新 DNS 缓存")) {
                Task { await maintenance.run(.flushDNS) }
            }
            .disabled(maintenance.running != nil)
        }
        SectionCard(title: PopoverSection.networkDNS.title, titleAccessory: tunnelWarning, trailing: {
            if isPopover {
                actions.collapseButton(.networkDNS, settings: model.settings)
            } else {
                actions
            }
        }) {
            InfoRow(label: tr("正在使用")) {
                Text(verbatim: network.details.map { $0.dnsServers.isEmpty ? "—" : $0.dnsServers.joined(separator: "\n") } ?? "—")
            }
            // 配置方式直接是一个下拉菜单：选预设立即切换，选“手动”展开输入框；比六个并排的按钮省两行
            if let physical {
                let isCustom = !manual.isEmpty && matched == nil
                HStack(spacing: DS.Space.s2) {
                    Text(tr("配置方式")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    if isCustom, !editingManual {
                        MiniIconButton(systemName: "pencil", help: tr("修改地址")) {
                            manualText = manual.joined(separator: ", ")
                            editingManual = true
                        }
                    }
                    Picker(tr("配置方式"), selection: Binding<DNSPreset?>(
                        get: { editingManual ? nil : manual.isEmpty ? .automatic : matched },
                        set: { choice in
                            if let choice {
                                editingManual = false
                                apply(choice.servers, service: physical.serviceName)
                            } else {
                                manualText = manual.joined(separator: ", ")
                                editingManual = true
                            }
                        })) {
                        ForEach(DNSPreset.allCases) { preset in
                            Text(preset.title).tag(DNSPreset?.some(preset))
                        }
                        Divider()
                        Text(tr("手动")).tag(DNSPreset?.none)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(maintenance.isApplyingDNS)
                }
            } else {
                InfoRow(label: tr("配置方式"), text: manual.isEmpty ? tr("自动（由路由器分配）") : matched?.title ?? tr("手动"))
            }

            if let physical {
                if editingManual {
                    HStack(spacing: DS.Space.s2) {
                        TextField(tr("例如 1.1.1.1, 8.8.8.8"), text: $manualText)
                            .textFieldStyle(.plain)
                            .dsFont(.xs)
                            .padding(.horizontal, DS.Space.s2)
                            .frame(height: DS.Size.controlHeight)
                            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(DS.Palette.neutral300, lineWidth: DS.Size.stroke))
                            .onSubmit { applyManual(service: physical.serviceName) }
                        Button(tr("应用")) { applyManual(service: physical.serviceName) }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                            .disabled(DNSConfiguration.parse(manualText)?.isEmpty != false)
                    }
                }
            }

            if maintenance.isApplyingDNS {
                Text(tr("正在修改 DNS…")).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
            } else if let outcome = maintenance.dnsOutcome ?? maintenance.outcomes[.flushDNS] {
                Text(outcome.text)
                    .dsFont(.xs)
                    .foregroundStyle(outcome.isError ? DS.Palette.error : DS.Palette.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applyManual(service: String) {
        guard let servers = DNSConfiguration.parse(manualText), !servers.isEmpty else { return }
        editingManual = false
        apply(servers, service: service)
    }

    private func apply(_ servers: [String], service: String) {
        Task {
            await model.maintenance.setDNSServers(servers, service: service)
            await model.network.refreshDetails()
        }
    }
}

// MARK: - 进程

private struct NetworkProcessesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let processes = model.network.processes

        SectionCard(title: PopoverSection.networkProcesses.title, trailing: {
            HStack(spacing: 0) {
                Text(tr("下载")).frame(width: DS.Size.valueColumn, alignment: .trailing)
                Text(tr("上传")).frame(width: DS.Size.valueColumn, alignment: .trailing)
            }
        }) {
            ProcessList(count: processes.count, rowCount: 5, emptyText: tr("正在统计各进程流量…"),
                        restText: tr("其他进程暂时没有流量")) { index in
                let process = processes[index]
                HStack(spacing: 0) {
                    ProcessNameLabel(icon: AppIconCache.shared.image(bundlePath: process.appBundlePath), name: process.localizedName)
                    Text(verbatim: Format.menuBarRate(process.download))
                        .frame(width: DS.Size.valueColumn, alignment: .trailing)
                    Text(verbatim: Format.menuBarRate(process.upload))
                        .frame(width: DS.Size.valueColumn, alignment: .trailing)
                }
                .dsFont(.xs)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textSecondary)
                .explainable(.init(process))
            }
        }
    }
}
