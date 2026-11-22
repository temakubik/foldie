import AppKit
import CoreGraphics
import Foundation

func renderFoldieIconPNG(size: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    let s = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let insetRect = rect.insetBy(dx: s * 0.08, dy: s * 0.08)
    let cornerRadius = insetRect.width * 0.225

    // Background rounded squircle with rich blue-indigo gradient
    let bgPath = CGPath(roundedRect: insetRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let gradientColors = [
        CGColor(red: 0.14, green: 0.56, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.22, green: 0.28, blue: 0.88, alpha: 1.0),
        CGColor(red: 0.12, green: 0.14, blue: 0.42, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: insetRect.minX, y: insetRect.maxY),
            end: CGPoint(x: insetRect.maxX, y: insetRect.minY),
            options: []
        )
    }

    // Subtle glowing radial highlight at top
    let glowColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            radial,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.82),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.5, y: s * 0.82),
            endRadius: s * 0.55,
            options: []
        )
    }
    ctx.restoreGState()

    // Subtle glass rim
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.setLineWidth(max(1.0, s * 0.014))
    ctx.strokePath()
    ctx.restoreGState()

    // Draw stylized frosted folder with 3 layered menu-bar pill bars inside
    let folderW = s * 0.58
    let folderH = s * 0.44
    let folderX = (s - folderW) / 2
    let folderY = s * 0.24

    let tabPath = CGMutablePath()
    let tabR = s * 0.045
    tabPath.addRoundedRect(
        in: CGRect(x: folderX, y: folderY + folderH * 0.55, width: folderW * 0.46, height: folderH * 0.52),
        cornerWidth: tabR,
        cornerHeight: tabR
    )
    ctx.setFillColor(CGColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 0.42))
    ctx.addPath(tabPath)
    ctx.fillPath()

    let pillSpecs: [(yFrac: CGFloat, wFrac: CGFloat, alpha: CGFloat)] = [
        (0.84, 0.72, 0.55),
        (0.74, 0.82, 0.78),
        (0.64, 0.90, 0.95)
    ]
    for spec in pillSpecs {
        let pw = folderW * spec.wFrac
        let ph = s * 0.068
        let px = (s - pw) / 2
        let py = folderY + folderH * spec.yFrac
        let pill = CGPath(roundedRect: CGRect(x: px, y: py, width: pw, height: ph), cornerWidth: ph / 2, cornerHeight: ph / 2, transform: nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: spec.alpha))
        ctx.addPath(pill)
        ctx.fillPath()
    }

    let bodyRect = CGRect(x: folderX, y: folderY, width: folderW, height: folderH * 0.78)
    let bodyR = s * 0.065
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: bodyR, cornerHeight: bodyR, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.fillPath()
    ctx.restoreGState()

    let dotSize = s * 0.058
    let dotSpacing = s * 0.095
    let dotY = bodyRect.midY - dotSize / 2
    let dotColors: [CGColor] = [
        CGColor(red: 0.10, green: 0.52, blue: 1.0, alpha: 0.95),
        CGColor(red: 0.40, green: 0.35, blue: 0.95, alpha: 0.95),
        CGColor(red: 0.18, green: 0.78, blue: 0.52, alpha: 0.95)
    ]
    for (idx, color) in dotColors.enumerated() {
        let offset = CGFloat(idx - 1) * dotSpacing
        let dotRect = CGRect(x: bodyRect.midX + offset - dotSize / 2, y: dotY, width: dotSize, height: dotSize)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: dotRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in specs {
    guard let png = renderFoldieIconPNG(size: spec.pixels) else { continue }
    let fileURL = outputDir.appendingPathComponent(spec.name)
    try png.write(to: fileURL)
}
