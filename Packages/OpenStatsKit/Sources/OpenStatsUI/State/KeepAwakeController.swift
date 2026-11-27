import Foundation
import IOKit.pwr_mgt
import Localization
import Metrics
import Observation

@MainActor
@Observable
public final class KeepAwakeController {
    public enum Mode: String, CaseIterable, Identifiable {
        case display, system

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .display: tr("屏幕保持常亮")
            case .system: tr("仅系统不休眠")
            }
        }

        /// 菜单栏面板里的短写
        var shortTitle: String {
            switch self {
            case .display: tr("屏幕常亮")
            case .system: tr("允许关屏")
            }
        }

        var subtitle: String {
            switch self {
            case .display: tr("屏幕和系统都不会因闲置而关闭或休眠")
            case .system: tr("屏幕可按设置关闭，下载、编译等后台任务继续运行")
            }
        }

        /// IOPMLib 中的 CFSTR 宏无法直接导入 Swift，这里使用其字符串值
        var assertionType: String {
            switch self {
            case .display: "PreventUserIdleDisplaySleep"
            case .system: "PreventUserIdleSystemSleep"
            }
        }
    }

    public enum Duration: Int, CaseIterable, Identifiable {
        case hour1 = 60, hours2 = 120, hours4 = 240, hours8 = 480, hours12 = 720, unlimited = 0

        public var id: Int { rawValue }

        var title: String {
            switch self {
            case .hour1: tr("1 小时")
            case .hours2: tr("2 小时")
            case .hours4: tr("4 小时")
            case .hours8: tr("8 小时")
            case .hours12: tr("12 小时")
            case .unlimited: tr("不限")
            }
        }

        /// 菜单栏面板里的时长格子用的短写
        var shortTitle: String {
            self == .unlimited ? "∞" : "\(rawValue / 60)h"
        }
    }

    public private(set) var isActive = false
    public private(set) var mode: Mode = .display
    public private(set) var duration: Duration = .unlimited
    public private(set) var endDate: Date?
    /// 用户是否希望合盖后继续运行
    public private(set) var lidClosedRequested = false
    /// 辅助工具是否已实际关闭系统睡眠
    public private(set) var lidClosedActive = false
    public private(set) var notice: String?
    public private(set) var noticeIsError = false

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private let settings: AppSettings
    /// 让辅助工具开关“合盖不睡眠”，返回错误说明；测试里换成桩，不碰真实的系统设置
    @ObservationIgnored var setSleepDisabled: (Bool) async -> String?
    /// 合盖运行期间自己定时看电量。指标采样在屏幕睡眠（合盖时必然发生）时会暂停，
    /// 电量保护只挂在采样回调上的话，合上盖子之后它根本不会执行
    @ObservationIgnored var batteryWatchInterval: Swift.Duration = .seconds(60)
    /// 读电量与是否接着电源；测试里换成桩
    @ObservationIgnored var readPower: @Sendable () async -> (level: Double, isPluggedIn: Bool)? = {
        await Task.detached { BatterySampler.powerState() }.value
    }
    @ObservationIgnored private var batteryWatch: Task<Void, Never>?
    /// 关闭合盖运行时没能恢复系统睡眠，之后每隔多久再试一次；用完后按最后一个间隔一直试到成功
    @ObservationIgnored var restoreRetryDelays: [Swift.Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)]
    @ObservationIgnored private var restoreRetry: Task<Void, Never>?
    @ObservationIgnored private var isLoweringLidMode = false

    init(helper: HelperClient, settings: AppSettings) {
        self.settings = settings
        setSleepDisabled = { await helper.setSleepDisabled($0) }
    }

    func setActive(_ active: Bool) async {
        active ? await start() : await stop(reason: nil)
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        if isActive { takeAssertion() }
    }

    func setDuration(_ newDuration: Duration) {
        duration = newDuration
        if isActive { scheduleExpiry() }
    }

    func setLidClosed(_ requested: Bool) async {
        lidClosedRequested = requested
        guard isActive else { return }
        await applyLidMode()
    }

    func start() async {
        isActive = true
        notice = nil
        takeAssertion()
        scheduleExpiry()
        if lidClosedRequested { await applyLidMode() }
    }

    func stop(reason: String?) async {
        isActive = false
        endDate = nil
        expiryTask?.cancel()
        releaseAssertion()
        if let error = await restoreSleepIfStale() {
            // 界面已经显示关闭，系统却还禁止睡眠：合上盖子会一直运行，必须接着试到恢复为止
            show(tr("恢复系统睡眠失败：\(error)"), isError: true)
            scheduleRestoreRetry()
            return
        }
        if let reason { show(reason, isError: false) }
    }

    /// 已经不需要合盖运行、系统睡眠却还关着时把它恢复，返回错误说明
    private func restoreSleepIfStale() async -> String? {
        guard lidClosedActive, !(isActive && lidClosedRequested) else { return nil }
        if let error = await setSleepDisabled(false) { return error }
        lidClosedActive = false
        syncBatteryWatch()
        // 等待期间用户可能又打开了合盖运行，刚才那次恢复把它关掉了，重新下发
        if isActive, lidClosedRequested { await applyLidMode() }
        return nil
    }

    private func scheduleRestoreRetry() {
        guard restoreRetry == nil else { return }
        restoreRetry = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self, self.lidClosedActive, !(self.isActive && self.lidClosedRequested),
                      let delay = self.restoreRetryDelays.isEmpty ? nil
                        : self.restoreRetryDelays[min(attempt, self.restoreRetryDelays.count - 1)] else { break }
                attempt += 1
                try? await Task.sleep(for: delay, tolerance: delay / 6)
                guard !Task.isCancelled else { return }
                if await self.restoreSleepIfStale() == nil, !self.lidClosedActive {
                    self.show(tr("系统睡眠已恢复"), isError: false)
                    break
                }
            }
            self?.restoreRetry = nil
        }
    }

    /// 辅助工具重启或重连后重新下发合盖设置。新的辅助工具进程启动时会先把睡眠设置恢复成系统默认，
    /// 这边记着的“已生效”已经过时，不能拿它当作不用再发：先清掉再下发，否则界面一直显示合盖运行、实际合盖就睡
    func reapply() async {
        guard isActive, lidClosedRequested else {
            // 防休眠已经关了、上次却没能恢复系统睡眠：辅助工具回来了，立刻补发，不等下一次重试
            _ = await restoreSleepIfStale()
            return
        }
        lidClosedActive = false
        await applyLidMode()
    }

    /// 电池电量保护：使用电池供电且电量低于下限时关闭合盖运行（屏幕亮着时由指标采样调用）
    func evaluateBattery(_ battery: BatteryStatus?) {
        guard let battery else { return }
        evaluateBattery(level: battery.level, isPluggedIn: battery.isPluggedIn)
    }

    func evaluateBattery(level: Double, isPluggedIn: Bool) {
        guard lidClosedActive, !isPluggedIn, !isLoweringLidMode,
              level * 100 < Double(settings.lidModeBatteryFloor) else { return }
        isLoweringLidMode = true
        Task {
            defer { isLoweringLidMode = false }
            lidClosedRequested = false
            await applyLidMode()
            // 没关成功时 applyLidMode 已经给出错误，下次看电量会再试
            if !lidClosedActive {
                show(tr("电量低于 \(settings.lidModeBatteryFloor)%，已关闭合盖运行"), isError: false)
            }
        }
    }

    /// 合盖运行生效期间定时看电量，其余时候不跑
    private func syncBatteryWatch() {
        guard lidClosedActive else {
            batteryWatch?.cancel()
            batteryWatch = nil
            return
        }
        guard batteryWatch == nil else { return }
        batteryWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.batteryWatchInterval else { return }
                try? await Task.sleep(for: interval, tolerance: interval / 6)
                guard !Task.isCancelled, let self else { return }
                if let power = await self.readPower() {
                    self.evaluateBattery(level: power.level, isPluggedIn: power.isPluggedIn)
                }
            }
        }
    }

    /// 退出应用时释放电源断言（合盖设置由 HelperClient 同步恢复）
    func releaseForTermination() {
        releaseAssertion()
    }

    private func applyLidMode() async {
        let wanted = isActive && lidClosedRequested
        guard wanted != lidClosedActive else { return }
        defer { syncBatteryWatch() }
        if let error = await setSleepDisabled(wanted) {
            lidClosedRequested = lidClosedActive
            show(error, isError: true)
            return
        }
        lidClosedActive = wanted
    }

    private func takeAssertion() {
        releaseAssertion()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(mode.assertionType as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 tr("OpenStats 防休眠") as CFString,
                                                 &id)
        if result == kIOReturnSuccess {
            assertionID = id
        } else {
            show(tr("无法创建电源断言（\(result)）"), isError: true)
        }
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard duration != .unlimited else {
            endDate = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(duration.rawValue * 60))
        endDate = end
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            await self?.stop(reason: tr("已到设定时间，防休眠已关闭"))
        }
    }

    private func show(_ message: String, isError: Bool) {
        if isError { Log.power.error("\(message, privacy: .public)") } else { Log.power.info("\(message, privacy: .public)") }
        notice = message
        noticeIsError = isError
    }
}
