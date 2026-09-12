import AppKit
import Metrics
import SMC
import SwiftUI

/// `OpenStats --snapshot <目录>`：用本机实时数据渲染各页面 PNG，用于设计走查
@MainActor
enum SnapshotRenderer {
    static func run(outputDirectory: URL) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "OpenStats.snapshot") ?? .standard
        let settings = AppSettings(defaults: defaults)
        settings.menuBarItems = [.cpu, .gpu, .memory, .network, .temperature]
        settings.setGaugeStyle(.ring, for: .gpu)
        settings.setGaugeStyle(.pie, for: .memory)
        let model = AppModel(settings: settings)
        model.isPanelVisible = true

        // 采集约 12 秒的真实数据，让历史曲线有内容
        var demand = MetricsDemand()
        demand.interval = .milliseconds(250)
        demand.memory = true
        demand.network = true
        demand.gpu = true
        demand.disk = true
        demand.battery = true
        demand.processes = true
        demand.temperatures = Set(TemperatureGroup.allCases)
        demand.fans = true
        await model.hub.update(demand)
        await model.hub.start { snapshot in model.handle(snapshot) }
        try? await Task.sleep(for: .seconds(12))
        await model.hub.stop()
        // 清理页展示真实扫描结果（只读，不删除任何文件）
        model.cleaner.scan()
        while model.cleaner.isBusy { try? await Task.sleep(for: .milliseconds(200)) }

        for (appearanceName, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            NSApp.appearance = appearance
            for tab in PanelTab.allCases {
                settings.panelTab = tab
                write(PanelRootView(), model: model, appearance: appearance,
                      to: outputDirectory.appendingPathComponent("panel-\(tab.rawValue)-\(suffix).png"))
            }
            for section in SettingsSection.allCases {
                write(SettingsView(section: section), model: model, appearance: appearance,
                      to: outputDirectory.appendingPathComponent("settings-\(section.rawValue)-\(suffix).png"))
            }
        }

        let menuBar = MenuBarRenderer.image(for: model)
        for dark in [false, true] {
            let preview = MenuBarRenderer.preview(menuBar, dark: dark)
            // 垫上菜单栏底色，便于查看
            let padded = NSImage(size: NSSize(width: preview.size.width + DS.Space.s4, height: preview.size.height), flipped: false) { rect in
                NSColor(hex: dark ? 0x1F2937 : 0xE5E7EB).setFill()
                rect.fill()
                preview.draw(in: NSRect(x: DS.Space.s2, y: 0, width: preview.size.width, height: preview.size.height))
                return true
            }
            writePNG(padded, scale: 2, to: outputDirectory.appendingPathComponent("menubar-\(dark ? "dark" : "light").png"))
        }
        print("截图已输出到 \(outputDirectory.path)")
    }

    /// 用真实的 NSHostingView 放进离屏窗口截图，渲染路径与 App 内一致
    private static func write<V: View>(_ view: V, model: AppModel, appearance: NSAppearance, to url: URL) {
        let hosting = NSHostingView(rootView: view
            .environment(model)
            .environment(\.isSnapshot, true))
        hosting.appearance = appearance
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func writePNG(_ image: NSImage, scale: CGFloat, to url: URL) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
