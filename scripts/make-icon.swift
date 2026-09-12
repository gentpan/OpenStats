#!/usr/bin/env swift
//
//  生成 AppIcon.appiconset：纯色圆角底 + 白色脉搏折线（不使用 SF Symbols，避免许可问题）
//  用法：swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
//

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let primary = NSColor(srgbRed: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0, alpha: 1)

/// 与界面中 PulseMark 的折线点一致（单位坐标，原点在左上）
let pulse: [CGPoint] = [
    CGPoint(x: 0.00, y: 0.56), CGPoint(x: 0.26, y: 0.56), CGPoint(x: 0.36, y: 0.30),
    CGPoint(x: 0.50, y: 0.80), CGPoint(x: 0.62, y: 0.40), CGPoint(x: 0.70, y: 0.56),
    CGPoint(x: 1.00, y: 0.56),
]

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let size = CGFloat(pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS 图标栅格：1024 画布内 824 的圆角矩形
    let inset = size * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    primary.setFill()
    NSBezierPath(roundedRect: body, xRadius: size * 185 / 1024, yRadius: size * 185 / 1024).fill()

    let markInset = body.width * 0.18
    let mark = body.insetBy(dx: markInset, dy: markInset)
    let path = NSBezierPath()
    for (index, point) in pulse.enumerated() {
        let p = NSPoint(x: mark.minX + point.x * mark.width, y: mark.maxY - point.y * mark.height)
        index == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.lineWidth = size * 64 / 1024
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    NSColor.white.setStroke()
    path.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("已生成 \(images.count) 张图标到 \(output.path)")
