import Foundation
import Localization

/// 归属地与 IP 类型的文字：网络弹窗与出口窗口共用
enum GeoText {
    /// 国家 · 省 / 州 · 城市；英文界面优先用英文地名，重复的相邻项只留一个
    static func location(countryCode: String, region: String?, regionEnglish: String?, city: String?, cityEnglish: String?) -> String {
        let country = Locale(identifier: L10n.isEnglish ? "en" : "zh-Hans").localizedString(forRegionCode: countryCode) ?? countryCode
        let region = L10n.isEnglish ? (regionEnglish ?? region) : region
        let city = L10n.isEnglish ? (cityEnglish ?? city) : city
        var parts = [country]
        for part in [region, city].compactMap({ $0 }) where part != parts.last { parts.append(part) }
        return parts.joined(separator: " · ")
    }

    /// 数据源给的 IP 类型（residential ip、datacenter ip……）对应的徽章；不认识的返回 nil
    static func ipTypeBadge(_ raw: String) -> (icon: String, text: String, tone: TagBadge.Tone)? {
        let type = raw.lowercased()
        if type.contains("residential") { return ("house.fill", tr("住宅 IP"), .success) }
        if type.contains("mobile") { return ("iphone.radiowaves.left.and.right", tr("移动网络 IP"), .success) }
        if type.contains("business") { return ("building.2.fill", tr("企业 IP"), .success) }
        if type.contains("idc") || type.contains("datacenter") || type.contains("hosting") { return ("server.rack", tr("机房 IP"), .warning) }
        return nil
    }
}
