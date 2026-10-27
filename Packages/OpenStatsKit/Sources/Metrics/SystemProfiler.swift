import Foundation

/// `system_profiler <类型> -json` 的调用与读数解析，蓝牙电量和电池健康度共用
enum SystemProfiler {
    /// 超过 `timeout` 秒就结束进程，相关系统服务卡住时不拖住采样
    static func run(_ dataType: String, detailLevel: String, timeout: TimeInterval) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = [dataType, "-json", "-detailLevel", detailLevel]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Data() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// 百分比读数：整数，或 "80%"、"75 %" 这样的文字；超出 0...100 视为无效
    static func percent(_ value: Any?) -> Int? {
        if let number = value as? Int { return (0...100).contains(number) ? number : nil }
        guard let text = value as? String, let number = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
        return (0...100).contains(number) ? number : nil
    }
}
