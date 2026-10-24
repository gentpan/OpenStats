//
//  FanControl.swift
//  OpenStats
//
//  风扇读写。Apple Silicon 解锁流程参考 exelban/stats (MIT)：
//  Copyright © 2021 Serhiy Mytrovtsiy. All rights reserved.
//

import Foundation

public struct FanState: Sendable, Equatable, Identifiable {
    public let id: Int
    public var current: Double
    public var minimum: Double
    public var maximum: Double
    public var target: Double
    public var isManual: Bool
    /// 风扇从停转起步：Apple 芯片的固件先低速拖转约 5 秒，期间转速读数为 0
    public var isStarting: Bool

    public init(id: Int, current: Double, minimum: Double, maximum: Double, target: Double, isManual: Bool,
                isStarting: Bool = false) {
        self.id = id
        self.current = current
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.isManual = isManual
        self.isStarting = isStarting
    }

    /// 当前转速占这台风扇最高转速的比例（以最高转速为 100%，比“最低到最高”的区间比例更直观）
    public var fraction: Double {
        guard maximum > 0 else { return 0 }
        return min(1, max(0, current / maximum))
    }
}

public final class FanControl {
    private let smc: SMCConnection
    private var lowercaseModeKey: Bool?
    /// 风扇个数是固定的，第一次读到后记住；读不到（0）时下次再试
    private var cachedCount: Int?
    /// 每台风扇的最低、最高转速：完整读取时刷新，只读转速时沿用
    private var limits: [Int: (minimum: Double, maximum: Double)] = [:]
    /// 上一次完整读取的目标转速与模式，只读转速时沿用
    private var lastDetail: [Int: (target: Double, isManual: Bool)] = [:]

    public init(smc: SMCConnection) {
        self.smc = smc
    }

    public var fanCount: Int {
        if let cachedCount { return cachedCount }
        let count = Int(smc.double(SMCKey("FNum")) ?? 0)
        if count > 0 { cachedCount = count }
        return count
    }

    /// `detail` 为真时读全部状态（每台 6 个键）；为假时只读当前转速（每台 1 个键），
    /// 最低、最高、目标转速与模式沿用上次完整读取的结果。只显示菜单栏转速时用后者，少唤醒 SMC
    public func read(detail: Bool = true) -> [FanState] {
        (0..<fanCount).compactMap { id in
            guard let current = smc.double(SMCKey("F\(id)Ac")) else { return nil }
            if !detail, let limit = limits[id] {
                let last = lastDetail[id]
                return FanState(id: id, current: current, minimum: limit.minimum, maximum: limit.maximum,
                                target: last?.target ?? current, isManual: last?.isManual ?? false)
            }
            let minimum = smc.double(SMCKey("F\(id)Mn")) ?? 0
            let maximum = smc.double(SMCKey("F\(id)Mx")) ?? 0
            limits[id] = (minimum, maximum)
            guard detail else {
                return FanState(id: id, current: current, minimum: minimum, maximum: maximum, target: current, isManual: false)
            }
            let target = smc.double(SMCKey("F\(id)Tg")) ?? current
            let mode = smc.double(modeKey(id)) ?? 0
            lastDetail[id] = (target, mode == 1)
            // F0St：3 停转、1 起步、5 运行；没有这个键的机型按“有目标转速但还没转起来”判断
            let starting = smc.double(SMCKey("F\(id)St")).map { $0 == 1 } ?? (mode == 1 && target > 0)
            return FanState(id: id, current: current, minimum: minimum, maximum: maximum,
                            target: target, isManual: mode == 1, isStarting: starting && current == 0)
        }
    }

    // MARK: 写入（需要 root）

    /// 设为手动并指定目标转速；转速会被限制在固件给出的 min...max 之间。
    public func setManual(fan id: Int, rpm: Double) throws {
        let minimum = smc.double(SMCKey("F\(id)Mn")) ?? 0
        let maximum = smc.double(SMCKey("F\(id)Mx")) ?? rpm
        let clamped = min(max(rpm, minimum), maximum)

        #if arch(arm64)
        if smc.double(modeKey(id)) != 1 {
            try unlockManualMode(fan: id)
        }
        try writeWithRetry(SMCKey("F\(id)Tg"), value: clamped)
        #else
        try smc.write(SMCKey("F\(id)Md"), value: 1)
        try smc.write(SMCKey("F\(id)Tg"), value: clamped)
        #endif
    }

    public func setAutomatic(fan id: Int) throws {
        #if arch(arm64)
        if smc.double(modeKey(id)) != 0 {
            try writeWithRetry(modeKey(id), value: 0)
        }
        #else
        try smc.write(SMCKey("F\(id)Md"), value: 0)
        #endif
    }

    /// 全部风扇恢复系统自动控制
    public func resetAll() throws {
        var firstError: Error?
        for id in 0..<fanCount {
            do { try setAutomatic(fan: id) } catch { firstError = firstError ?? error }
        }
        #if arch(arm64)
        // M1–M4 需要复位 Ftst，让 thermalmonitord 接管
        let ftst = SMCKey("Ftst")
        if smc.exists(ftst), smc.double(ftst) == 1 {
            do { try writeWithRetry(ftst, value: 0) } catch { firstError = firstError ?? error }
        }
        #endif
        if let firstError { throw firstError }
    }

    // MARK: 私有

    private func modeKey(_ id: Int) -> SMCKey {
        if lowercaseModeKey == nil {
            lowercaseModeKey = smc.exists(SMCKey("F0md"))
        }
        return SMCKey(lowercaseModeKey == true ? "F\(id)md" : "F\(id)Md")
    }

    #if arch(arm64)
    private func unlockManualMode(fan id: Int) throws {
        // M5 及以后：直接写模式键即可
        if (try? smc.write(modeKey(id), value: 1)) != nil { return }

        // M1–M4：先写 Ftst=1，等待 thermalmonitord 让出控制权。
        // 不固定等 3 秒：每 50 毫秒试写一次模式键并读回确认，控制权一交出来就继续，最多等 15 秒
        let ftst = SMCKey("Ftst")
        guard smc.exists(ftst) else { throw SMCError.firmwareRejected(modeKey(id), 0) }
        if smc.double(ftst) != 1 {
            try writeWithRetry(ftst, value: 1, attempts: 100)
        }
        let key = modeKey(id)
        for _ in 0..<300 {
            if (try? smc.write(key, value: 1)) != nil, smc.double(key) == 1 { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SMCError.firmwareRejected(key, 0)
    }

    private func writeWithRetry(_ key: SMCKey, value: Double, attempts: Int = 10, delay: TimeInterval = 0.05) throws {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                try smc.write(key, value: value)
                return
            } catch {
                lastError = error
                if attempt < attempts - 1 { Thread.sleep(forTimeInterval: delay) }
            }
        }
        throw lastError ?? SMCError.firmwareRejected(key, 0)
    }
    #endif
}
