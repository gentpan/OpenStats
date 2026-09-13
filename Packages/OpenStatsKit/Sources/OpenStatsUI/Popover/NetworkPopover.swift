import AppKit
import HelperShared
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
                RateHero(title: "下载", bytesPerSecond: rate?.downloadBytesPerSecond, color: DS.NetworkPalette.download)
                Rectangle().fill(DS.Palette.border).frame(width: DS.Size.stroke, height: DS.Space.s8)
                RateHero(title: "上传", bytesPerSecond: rate?.uploadBytesPerSecond, color: DS.NetworkPalette.upload)
            }
        }

        ForEach(MenuBarItem.network.popoverSections.filter { isDetailPage || settings.isVisible($0) }) { section in
            switch section {
            case .networkHistory: TrafficHistorySection()
            case .networkProbe: ProbeSection()
            case .networkInterface: InterfaceSection()
            case .networkAddresses: AddressSection()
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

        SectionCard(title: PopoverSection.networkHistory.title, trailing: { Text("最近 60 秒") }) {
            MirroredRateChart(upload: upload, download: download,
                              height: isDetailPage ? DS.Size.chartHeight * 3 : DS.Size.chartHeight + DS.Space.s6)
                .overlay(alignment: .topLeading) {
                    peakLabel("峰值 ↑", upload)
                }
                .overlay(alignment: .bottomLeading) {
                    peakLabel("峰值 ↓", download)
                }
        }
    }

    private func peakLabel(_ prefix: String, _ values: [Double]) -> some View {
        Text(verbatim: "\(prefix) \(Format.menuBarRate(max(values.max() ?? 0, MirroredRateChart.floor)))")
            .dsFont(.xs)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.textTertiary)
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
                Text(verbatim: "\(network.probeAddress ?? "—") · 每 \(settings.probeSeconds) 秒")
            }
        }) {
            if settings.probeEnabled {
                ProbeGrid(samples: network.probes.elements, columns: isDetailPage ? 40 : 20, rows: 3)
                HStack(spacing: DS.Space.s3) {
                    stat("延迟", network.latency.map(milliseconds) ?? "—")
                    stat("抖动", network.jitter.map(milliseconds) ?? "—")
                    stat("丢包", network.lossRate.map { Format.percent($0) } ?? "—",
                         tone: (network.lossRate ?? 0) > 0.05 ? .error : .neutral)
                }
            } else {
                HStack {
                    Text("定时 ping 一个地址，记录网络是否通畅").dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Button("开启") { settings.probeEnabled = true }
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
        let details = model.network.details
        let physical = details?.physical
        let totals = model.store.network

        SectionCard(title: PopoverSection.networkInterface.title) {
            if let physical {
                InfoRow(label: "接口", text: "\(physical.displayName)（\(physical.bsdName)）")
                InfoRow(label: "状态") {
                    StatusBadge(text: physical.isUp ? "已连接" : "未连接", tone: physical.isUp ? .success : .error)
                }
                InfoRow(label: "物理地址") { CopyableText(text: physical.hardwareAddress ?? "—") }
                if let wifi = physical.wifi {
                    if let ssid = wifi.ssid { InfoRow(label: "网络名称", text: ssid) }
                    InfoRow(label: "信号强度", text: "\(wifi.rssi) dBm · \(signalQuality(wifi.rssi))")
                    InfoRow(label: "传输速率", text: "\(Int(wifi.transmitRate)) Mbps")
                }
            } else {
                Text(details == nil ? "正在读取…" : "未连接网络").dsFont(.xs).foregroundStyle(DS.Palette.textTertiary)
            }
            if let tunnel = details?.tunnel {
                InfoRow(label: "VPN / 代理", text: "\(tunnel.name)（\(tunnel.bsdName)）")
            }
            if let totals {
                InfoRow(label: "开机后下载", text: Format.bytes(totals.totalDownloaded, base: .decimal))
                InfoRow(label: "开机后上传", text: Format.bytes(totals.totalUploaded, base: .decimal))
            }
        }
    }

    private func signalQuality(_ rssi: Int) -> String {
        rssi >= -50 ? "极好" : rssi >= -60 ? "良好" : rssi >= -70 ? "一般" : "较弱"
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

        SectionCard(title: PopoverSection.networkAddresses.title, trailing: {
            if lookup {
                MiniIconButton(systemName: "arrow.clockwise", help: "重新查询公网 IP") {
                    network.lookUpPublicAddresses()
                }
                .disabled(network.isLookingUpPublic)
            }
        }) {
            InfoRow(label: "本地 IPv4") { CopyableText(text: physical?.ipv4.first ?? "—") }
            InfoRow(label: "本地 IPv6") { CopyableText(text: physical?.ipv6.first ?? "—") }
            InfoRow(label: "路由器") { CopyableText(text: physical?.router ?? "—") }
            if lookup {
                InfoRow(label: "公网 IPv4") { publicValue(publicAddresses?.ipv4, loading: network.isLookingUpPublic) }
                InfoRow(label: "公网 IPv6") { publicValue(publicAddresses?.ipv6, loading: network.isLookingUpPublic) }
                if let publicAddresses, let code = publicAddresses.countryCode {
                    InfoRow(label: "归属地") {
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
                    InfoRow(label: "网络运营方") { Text(verbatim: organization).lineLimit(1).truncationMode(.middle) }
                }
                if let publicAddresses, publicAddresses.countryCode != nil || publicAddresses.asn != nil {
                    InfoRow(label: "数据来源", text: publicAddresses.source == .localDatabase ? "本地 GeoLite2（MaxMind）" : "ipinfo.io 在线查询")
                }
            } else {
                InfoRow(label: "公网 IP", text: "查询已关闭")
            }
        }
    }

    @ViewBuilder
    private func publicValue(_ value: String?, loading: Bool) -> some View {
        if loading && value == nil {
            Text("查询中…").foregroundStyle(DS.Palette.textTertiary)
        } else {
            CopyableText(text: value ?? "—")
        }
    }

    private func location(_ addresses: PublicAddresses, code: String) -> String {
        let country = Locale(identifier: "zh-Hans").localizedString(forRegionCode: code) ?? code
        return [country, addresses.city].compactMap { $0 }.joined(separator: " · ")
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
            InfoRow(label: "正在使用") {
                Text(verbatim: network.details.map { $0.dnsServers.isEmpty ? "—" : $0.dnsServers.joined(separator: "\n") } ?? "—")
            }
            InfoRow(label: "配置方式", text: manual.isEmpty ? "自动（由路由器分配）" : matched?.title ?? "手动")

            if let tunnel = network.details?.tunnel {
                InfoBanner(icon: "info.circle", text: "流量经过 \(tunnel.name)，系统 DNS 可能由它接管，修改后不一定生效。", tone: .neutral)
            }

            if let physical {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1), count: 3), spacing: DS.Space.s1) {
                    ForEach(DNSPreset.allCases) { preset in
                        ChipButton(title: preset.title, isSelected: !editingManual && matched == preset) {
                            editingManual = false
                            apply(preset.servers, service: physical.serviceName)
                        }
                    }
                    ChipButton(title: "手动", isSelected: editingManual || (!manual.isEmpty && matched == nil)) {
                        manualText = manual.joined(separator: ", ")
                        editingManual.toggle()
                    }
                }
                .disabled(maintenance.isApplyingDNS)

                if editingManual {
                    HStack(spacing: DS.Space.s2) {
                        TextField("例如 1.1.1.1, 8.8.8.8", text: $manualText)
                            .textFieldStyle(.plain)
                            .dsFont(.xs)
                            .padding(.horizontal, DS.Space.s2)
                            .frame(height: DS.Size.controlHeight)
                            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Palette.neutral300, lineWidth: DS.Size.stroke))
                            .onSubmit { applyManual(service: physical.serviceName) }
                        Button("应用") { applyManual(service: physical.serviceName) }
                            .buttonStyle(DSButtonStyle(kind: .primary))
                            .disabled(DNSConfiguration.parse(manualText)?.isEmpty != false)
                    }
                }
            }

            HStack(spacing: DS.Space.s2) {
                Button(maintenance.running == .flushDNS ? "正在刷新…" : "刷新 DNS 缓存") {
                    Task { await maintenance.run(.flushDNS) }
                }
                .buttonStyle(DSButtonStyle(kind: .secondary))
                .disabled(maintenance.running != nil)
                Spacer(minLength: 0)
            }

            if maintenance.isApplyingDNS {
                Text("正在修改 DNS…").dsFont(.xs).foregroundStyle(DS.Palette.textSecondary)
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
                Text("下载").frame(width: DS.Size.valueColumn, alignment: .trailing)
                Text("上传").frame(width: DS.Size.valueColumn, alignment: .trailing)
            }
        }) {
            ProcessList(count: processes.count, rowCount: 8, emptyText: "正在统计各进程流量…") { index in
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
