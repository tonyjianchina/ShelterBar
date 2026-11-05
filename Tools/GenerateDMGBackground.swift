#!/usr/bin/swift

import AppKit
import Foundation

// Keep the canvas and the icon lane in sync with Tools/DMGLayout.py.
let canvasSize = NSSize(width: 720, height: 520)

guard CommandLine.arguments.count == 2 else {
    fputs("usage: GenerateDMGBackground.swift <output.png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to allocate the DMG background canvas\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create the DMG background context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let canvas = NSRect(origin: .zero, size: canvasSize)
let background = NSGradient(colors: [
    NSColor(calibratedWhite: 0.99, alpha: 1),
    NSColor(calibratedWhite: 0.96, alpha: 1),
])
background?.draw(in: canvas, angle: -90)

// Use top-left coordinates, like Finder's icon positions, for the guide.
func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasSize.height - top - height, width: width, height: height)
}

func drawText(
    _ text: String, in frame: NSRect, size: CGFloat,
    weight: NSFont.Weight = .regular, gray: CGFloat = 0.16,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    (text as NSString).draw(in: frame, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(calibratedWhite: gray, alpha: 1),
        .paragraphStyle: paragraph,
    ])
}

func drawStep(_ number: Int, title: String, top: CGFloat) {
    let badge = NSBezierPath(ovalIn: rect(x: 44, top: top, width: 28, height: 28))
    NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
    badge.fill()
    drawText(
        String(number), in: rect(x: 44, top: top + 4, width: 28, height: 20),
        size: 14, weight: .semibold, gray: 0.30, alignment: .center
    )
    drawText(
        title, in: rect(x: 84, top: top + 2, width: 592, height: 26),
        size: 17, weight: .semibold
    )
}

drawText(
    "安装 ShelterBar", in: rect(x: 44, top: 30, width: 632, height: 36),
    size: 26, weight: .semibold, alignment: .center
)
drawText(
    "只需三步，即可开始整理菜单栏。", in: rect(x: 44, top: 74, width: 632, height: 24),
    size: 14, gray: 0.42, alignment: .center
)

drawStep(1, title: "把 ShelterBar 拖到 Applications", top: 116)

// Reserve the entire lane for Finder's real, draggable icons and their labels.
// Icon centers: (180, 210) and (540, 210); labels stay above the divider.
let arrowY = canvasSize.height - 210
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 330, y: arrowY))
arrow.line(to: NSPoint(x: 390, y: arrowY))
arrow.move(to: NSPoint(x: 380, y: arrowY + 10))
arrow.line(to: NSPoint(x: 390, y: arrowY))
arrow.line(to: NSPoint(x: 380, y: arrowY - 10))
NSColor(calibratedWhite: 0.50, alpha: 1).setStroke()
arrow.stroke()

NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
rect(x: 44, top: 316, width: 632, height: 1).fill()

drawStep(2, title: "第一次打开会提示无法打开", top: 342)
drawText(
    "请到「系统设置 › 隐私与安全性」底部点「仍要打开」。",
    in: rect(x: 84, top: 378, width: 592, height: 24), size: 14, gray: 0.34
)
drawStep(3, title: "按提示开启辅助功能等所需权限", top: 432)
drawText(
    "辅助功能、输入监控为必需；屏幕录制仅用于读取图标，可稍后开启。",
    in: rect(x: 84, top: 468, width: 592, height: 24), size: 13, gray: 0.34
)

graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let imageData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render the DMG background\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try imageData.write(to: outputURL, options: .atomic)
} catch {
    fputs("failed to write DMG background: \(error)\n", stderr)
    exit(1)
}
