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
            HStack(spacing: DS.Space.s3) {
                RateHero(title: tr("下载"), bytesPerSecond: rate?.downloadBytesPerSecond, color: DS.NetworkPalette.download)
                Rectangle().fill(DS.Palette.border).frame(width: DS.Size.stroke, height: DS.Space.s8)
                RateHero(title: tr("上传"), bytesPerSecond: rate?.uploadBytesPerSecond, color: DS.NetworkPalette.upload)
            }
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

private struct RateHero: View {
    let title: String
    let bytesPerSecond: Double?
    let color: NSColor

    var body: some View {
        let parts = (bytesPerSecond.map { Format.menuBarRate($0) } ?? "— KB/s").split(separator: " ", maxSplits: 1).map(String.init)
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HeroValue(value: parts.first ?? "—", unit: parts.count > 1 ? parts[1] : nil)
            HStack(spacing: DS.Space.s1) {
                Circle().fill(Color(nsColor: color)).frame(width: DS.Size.barHeight, height: DS.Size.barHeight)
                Text(title).dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 流量历史

private struct TrafficHistorySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isDetailPage) private var isDetailPage

    var body: some View {
        let store = model.store
        let upload = store.uploadHistory.elements
        let download = store.downloadHistory.elements

        // 峰值放在标题行，图表上不压任何文字
        SectionCard(title: PopoverSection.networkHistory.title, trailing: {
            HStack(spacing: DS.Space.s1) {
                Text(tr("60 秒峰值"))
                peak("↑", upload, color: DS.NetworkPalette.upload)
                peak("↓", download, color: DS.NetworkPalette.download)
            }
            .monospacedDigit()
        }) {
            MirroredRateChart(upload: upload, download: download,
                              height: isDetailPage ? DS.Size.chartHeight * 3 : DS.Size.chartHeight + DS.Space.s6)
        }
    }

    private func peak(_ arrow: String, _ values: [Double], color: NSColor) -> some View {
        HStack(spacing: DS.Space.s1 / 2) {
            Text(verbatim: arrow).foregroundStyle(Color(nsColor: color)).fontWeight(.semibold)
            Text(verbatim: Format.menuBarRate(max(values.max() ?? 0, MirroredRateChart.floor)))
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

        SectionCard(title: PopoverSection.networkProbe.title, trailing: {
            if settings.probeEnabled {
                Text(verbatim: tr("\(network.probeAddress ?? "—") · 每 \(settings.probeSeconds) 秒"))
            }
        }) {
            if settings.probeEnabled {
                ProbeGrid(samples: network.probes.elements, columns: isDetailPage ? 40 : 20, rows: 3)
                HStack(spacing: DS.Space.s3) {
                    stat(tr("延迟"), network.latency.map(milliseconds) ?? "—")
                    stat(tr("抖动"), network.jitter.map(milliseconds) ?? "—")
                    stat(tr("丢包"), network.lossRate.map { Format.percent($0) } ?? "—",
                         tone: (network.lossRate ?? 0) > 0.05 ? .error : .neutral)
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

    private func milliseconds(_ value: Double) -> String {
        value < 10 ? "\(value.formatted(.number.precision(.fractionLength(1)))) ms" : "\(Int(value.rounded())) ms"
    }

    private func stat(_ label: String, _ value: String, tone: Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            Text(verbatim: value)
                .dsFont(.sm, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(tone == .neutral ? DS.Palette.textPrimary : tone.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 接口

private struct InterfaceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let network = model.network
        let details = network.details
        let physical = details?.physical
        let totals = model.store.network

        SectionCard(title: PopoverSection.networkInterface.title, trailing: {
            // 右上角重置：把上传 / 下载从现在起重新累计，标出起算时间
            if let totals {
                if let since = network.trafficBaseline?.date {
                    Text(verbatim: tr("自 \(since.formatted(Date.FormatStyle(locale: L10n.locale).month().day().hour().minute())) 起"))
                }
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
        }) {
            if let physical {
                InfoRow(label: tr("接口"), text: tr("\(physical.displayName)（\(physical.bsdName)）"))
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
            if let totals {
                let counted = network.trafficTotals(totals)
                let sinceReset = network.trafficBaseline != nil
                InfoRow(label: sinceReset ? tr("重置后下载") : tr("开机后下载"), text: Format.bytes(counted.download, base: .decimal))
                InfoRow(label: sinceReset ? tr("重置后上传") : tr("开机后上传"), text: Format.bytes(counted.upload, base: .decimal))
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

    var body: some View {
        let network = model.network
        let physical = network.details?.physical
        let lookup = model.settings.publicIPLookup
        let publicAddresses = network.publicAddresses

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            // 标题、数据来源字标、IPv4 / IPv6 切换、刷新排在一行；320 宽放不下时字标依次缩小，卡片不会被撑宽
            ViewThatFits(in: .horizontal) {
                header(publicAddresses, logoHeight: DS.TextSize.sm.rawValue)
                header(publicAddresses, logoHeight: DS.TextSize.xs.rawValue)
                header(publicAddresses, logoHeight: DS.TextSize.xs.rawValue - DS.Space.s1 / 2)
            }
            InfoRow(label: tr("本地 IPv4")) { CopyableText(text: physical?.ipv4.first ?? "—") }
            InfoRow(label: tr("本地 IPv6")) { CopyableText(text: physical?.ipv6.first ?? "—") }
            InfoRow(label: tr("路由器")) { CopyableText(text: physical?.router ?? "—") }
            if lookup {
                InfoRow(label: tr("公网 IPv4")) { publicValue(publicAddresses?.ipv4, loading: network.isLookingUpPublic) }
                InfoRow(label: tr("公网 IPv6")) { publicValue(publicAddresses?.ipv6, loading: network.isLookingUpPublic) }
                if let publicAddresses, let code = publicAddresses.countryCode {
                    InfoRow(label: tr("归属地")) {
                        HStack(spacing: DS.Space.s2) {
                            FlagImage(countryCode: code)
                            Text(verbatim: location(publicAddresses, code: code))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                if let asn = publicAddresses?.asn {
                    InfoRow(label: "ASN") { CopyableText(text: asn) }
                }
                if let organization = publicAddresses?.organization {
                    InfoRow(label: tr("网络运营方")) { Text(verbatim: organization).lineLimit(1).truncationMode(.middle) }
                }
                // 原生 / 广播、IP 类型、网络类型做成徽章，一眼看结论；反向解析、住宅概率等细节不在弹窗里占行
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
        let country = Locale(identifier: L10n.isEnglish ? "en" : "zh-Hans").localizedString(forRegionCode: code) ?? code
        let region = L10n.isEnglish ? (addresses.regionEnglish ?? addresses.region) : addresses.region
        let city = L10n.isEnglish ? (addresses.cityEnglish ?? addresses.city) : addresses.city
        var parts: [String] = [country]
        for part in [region, city].compactMap({ $0 }) where part != parts.last { parts.append(part) }
        return parts.joined(separator: " · ")
    }

    /// 标题行：IP 地址 · 数据来源 ……… [IPv4 | IPv6] ⟳
    private func header(_ addresses: PublicAddresses?, logoHeight: CGFloat) -> some View {
        let network = model.network
        return HStack(spacing: DS.Space.s2) {
            Text(PopoverSection.networkAddresses.title)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
            if let source = sourceAccessory(addresses, logoHeight: logoHeight) {
                source
            }
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
        }
    }

    /// 标题后的数据来源：CleanIP.io 用它的字标（默认与标题文字同高，点了打开官网），其他来源写名字
    private func sourceAccessory(_ addresses: PublicAddresses?, logoHeight: CGFloat) -> AnyView? {
        guard let addresses, addresses.countryCode != nil || addresses.asn != nil else { return nil }
        switch addresses.source {
        case .online(.cleanIP):
            return AnyView(CleanIPLink(height: logoHeight, help: tr("数据来源：cleanip.io，点击打开官网")))
        case .online(let provider):
            return AnyView(Text(verbatim: provider.displayName).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary).fixedSize())
        case .localDatabase:
            return AnyView(Text("GeoLite2").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary).fixedSize())
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
        if let ipType = addresses.ipType?.lowercased() {
            switch ipType {
            case "residential ip": badges.append(Badge(icon: "house.fill", text: tr("住宅 IP"), tone: .success))
            case "datacenter ip", "hosting ip": badges.append(Badge(icon: "server.rack", text: tr("机房 IP"), tone: .warning))
            case "mobile ip": badges.append(Badge(icon: "iphone.radiowaves.left.and.right", text: tr("移动网络 IP"), tone: .success))
            case "business ip": badges.append(Badge(icon: "building.2.fill", text: tr("企业 IP"), tone: .success))
            default: badges.append(Badge(icon: "questionmark.circle", text: addresses.ipType ?? "", tone: .neutral))
            }
        }
        if let asnType = addresses.asnType {
            switch asnType {
            case "isp": badges.append(Badge(icon: "wifi.router.fill", text: "ISP", tone: .success))
            case "mobile": badges.append(Badge(icon: "antenna.radiowaves.left.and.right", text: tr("移动运营商"), tone: .success))
            case "business": badges.append(Badge(icon: "building.2.fill", text: tr("企业网络"), tone: .success))
            case "education": badges.append(Badge(icon: "graduationcap.fill", text: tr("教育网"), tone: .success))
            case "government": badges.append(Badge(icon: "building.columns.fill", text: tr("政府"), tone: .success))
            case "hosting": badges.append(Badge(icon: "server.rack", text: tr("机房"), tone: .warning))
            default: break
            }
        }
        return badges
    }

    static func sourceLabel(_ source: PublicAddresses.Source) -> String {
        switch source {
        case .localDatabase: tr("本地 GeoLite2（MaxMind）")
        case .online(let provider): tr("\(provider.displayName) 在线查询")
        }
    }

    static func networkTypeLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "residential", "isp": tr("住宅宽带")
        case "business": tr("企业")
        case "hosting", "datacenter", "data center": tr("机房")
        case "mobile", "cellular": tr("移动网络")
        case "education": tr("教育网")
        case "government": tr("政府")
        default: raw
        }
    }

    static func ipTypeLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "residential ip": tr("住宅 IP")
        case "datacenter ip", "hosting ip": tr("机房 IP")
        case "mobile ip": tr("移动网络 IP")
        case "business ip": tr("企业 IP")
        default: raw
        }
    }
}

// MARK: - IP 纯净度

/// CleanIP.io 给出的纯净度评分与风险标记；其他数据源没有这一项
private struct PuritySection: View {
    @Environment(AppModel.self) private var model

    /// 标题行里“查看完整报告”链接的三种长度
    enum ReportStyle { case full, short, icon }

    var body: some View {
        let settings = model.settings
        let network = model.network
        let addresses = network.publicAddresses
        let hint = tr("纯净度看信誉、来路、邻居与网络类型四项；机房 IP 常见信誉高、来路和类型偏低。数据来自 cleanip.io")

        Card(padding: DS.Space.s3, spacing: DS.Space.s2) {
            // 标题、地址族徽章、置信度、报告链接、刷新按钮排成一行；宽度不够时报告链接依次缩成“完整报告”、只剩图标
            ViewThatFits(in: .horizontal) {
                header(addresses, report: .full)
                header(addresses, report: .short)
                header(addresses, report: .icon)
            }
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
                ScoreBand(score: purity.score).help(hint)
                if let risk = addresses?.risk {
                    InfoRow(label: tr("风险评分")) {
                        Text(verbatim: "\(risk.score)/100" + (risk.label.map { " · \(Self.riskLabel($0))" } ?? ""))
                    }
                    InfoRow(label: tr("风险标记")) {
                        Text(verbatim: risk.flags.isEmpty ? tr("未检出") : risk.flags.map(Self.flagLabel).joined(separator: "、"))
                            .foregroundStyle(risk.flags.isEmpty ? DS.Palette.success : DS.Palette.error)
                    }
                }
                if let recommendation = purity.recommendation, !L10n.isEnglish {
                    Text(verbatim: recommendation)
                        .dsFont(.xs)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !settings.publicIPLookup {
                Text(tr("查询已关闭")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            } else if settings.geoSource != .cleanIP {
                Text(tr("纯净度评分来自 CleanIP.io。在「设置 · 网络」把归属地数据源改为 CleanIP.io 后显示。"))
                    .dsFont(.xs).foregroundStyle(DS.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else if network.isLookingUpPublic {
                Text(tr("正在查询…")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            } else {
                Text(tr("暂时没有拿到评分，稍后会再试")).dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    /// 标题行：IP 纯净度 · [IPv4] · [置信度 92%] · 查看完整报告 ↗ ……… ⟳
    private func header(_ addresses: PublicAddresses?, report: ReportStyle) -> some View {
        let network = model.network
        // 320 宽的弹窗里这一行很挤：标题与徽章之间只留最小间距，右侧刷新按钮自带留白
        return HStack(spacing: DS.Space.s1) {
            Text(PopoverSection.networkPurity.title)
                .dsFont(.xs, weight: .semibold)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: DS.Space.s1) {
                if let family = network.shownFamily {
                    TagBadge(text: family.title, tone: .primary, compact: true)
                }
                if let confidence = addresses?.purity?.confidence {
                    TagBadge(text: tr("置信度 \(confidence)%"), tone: Self.confidenceTone(confidence), compact: true)
                }
            }
            if let url = addresses?.reportURL {
                ReportLink(url: url, style: report).padding(.leading, DS.Space.s1)
            }
            Spacer(minLength: 0)
            RefreshButton(loading: network.isLookingUpPublic, help: tr("强制刷新：忽略缓存，立即重新查询公网 IP 与归属地")) {
                network.lookUpPublicAddresses(force: true)
            }
        }
    }

    /// 置信度高的绿、中等的灰、低的黄
    static func confidenceTone(_ confidence: Int) -> TagBadge.Tone {
        confidence >= 80 ? .success : confidence >= 50 ? .neutral : .warning
    }

    static func riskLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "very clean": tr("非常干净")
        case "clean": tr("干净")
        case "low risk", "low": tr("低风险")
        case "medium risk", "medium", "moderate": tr("中等风险")
        case "high risk", "high": tr("高风险")
        case "very high risk", "critical": tr("极高风险")
        default: raw
        }
    }

    static func flagLabel(_ flag: String) -> String {
        switch flag {
        case "vpn": "VPN"
        case "proxy": tr("代理")
        case "residentialProxy": tr("住宅代理")
        case "tor": "Tor"
        case "relay": tr("中继")
        case "datacenter": tr("机房")
        case "hosting": tr("托管")
        case "abuser": tr("滥用记录")
        default: flag
        }
    }
}

// MARK: - DNS

private struct DNSSection: View {
    @Environment(AppModel.self) private var model
    @State private var editingManual = false
    @State private var manualText = ""

    var body: some View {
        let network = model.network
        let maintenance = model.maintenance
        let physical = network.details?.physical
        let manual = physical?.manualDNS ?? []
        let matched = DNSPreset.matching(manual)

        SectionCard(title: PopoverSection.networkDNS.title, trailing: {
            if let physical { Text(verbatim: physical.serviceName) }
        }) {
            InfoRow(label: tr("正在使用")) {
                Text(verbatim: network.details.map { $0.dnsServers.isEmpty ? "—" : $0.dnsServers.joined(separator: "\n") } ?? "—")
            }
            InfoRow(label: tr("配置方式"), text: manual.isEmpty ? tr("自动（由路由器分配）") : matched?.title ?? tr("手动"))

            if let tunnel = network.details?.tunnel {
                InfoBanner(icon: "info.circle", text: tr("流量经过 \(tunnel.name)，系统 DNS 可能由它接管，修改后不一定生效。"), tone: .neutral)
            }

            if let physical {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1), count: 3), spacing: DS.Space.s1) {
                    ForEach(DNSPreset.allCases) { preset in
                        ChipButton(title: preset.title, isSelected: !editingManual && matched == preset) {
                            editingManual = false
                            apply(preset.servers, service: physical.serviceName)
                        }
                    }
                    ChipButton(title: tr("手动"), isSelected: editingManual || (!manual.isEmpty && matched == nil)) {
                        manualText = manual.joined(separator: ", ")
                        editingManual.toggle()
                    }
                }
                .disabled(maintenance.isApplyingDNS)

                if editingManual {
                    HStack(spacing: DS.Space.s2) {
                        TextField(tr("例如 1.1.1.1, 8.8.8.8"), text: $manualText)
                            .textFieldStyle(.plain)
                            .dsFont(.xs)
                            .padding(.horizontal, DS.Space.s2)
                            .frame(height: DS.Size.controlHeight)
                            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Palette.neutral300, lineWidth: DS.Size.stroke))
                            .onSubmit { applyManual(service: physical.serviceName) }
                        Button(tr("应用")) { applyManual(service: physical.serviceName) }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                            .disabled(DNSConfiguration.parse(manualText)?.isEmpty != false)
                    }
                }
            }

            HStack(spacing: DS.Space.s2) {
                Button(maintenance.running == .flushDNS ? tr("正在刷新…") : tr("刷新 DNS 缓存")) {
                    Task { await maintenance.run(.flushDNS) }
                }
                .buttonStyle(DSButtonStyle(kind: .secondary))
                .disabled(maintenance.running != nil)
                Spacer(minLength: 0)
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
            ProcessList(count: processes.count, rowCount: 5, emptyText: tr("正在统计各进程流量…")) { index in
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

/// 纯净度标题行里的“查看完整报告”链接；`icon` 只剩一个外链图标
private struct ReportLink: View {
    let url: URL
    let style: PuritySection.ReportStyle
    @State private var hovering = false

    var body: some View {
        let help = tr("在 cleanip.io 查看这个 IP 的完整报告")
        if style == .icon {
            MiniIconButton(systemName: "arrow.up.forward.square", help: help) { NSWorkspace.shared.open(url) }
        } else {
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: DS.Space.s1 / 2) {
                    Text(style == .full ? tr("查看完整报告") : tr("完整报告"))
                        .dsFont(.xs, weight: .medium)
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: DS.TextSize.xs.rawValue, weight: .semibold))
                }
                .foregroundStyle(hovering ? DS.Palette.primaryHover : DS.Palette.primary)
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(help)
        }
    }
}
