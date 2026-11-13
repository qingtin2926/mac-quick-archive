import Cocoa

// Build-time helper script to generate AppIcon.iconset and ToolbarIcon(@2x).png
let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: IconGenerator <iconset_dir> <toolbar_resources_dir>\n", stderr)
    exit(1)
}

let iconsetDir = URL(fileURLWithPath: args[1])
let toolbarDir = URL(fileURLWithPath: args[2])
let fm = FileManager.default
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try fm.createDirectory(at: toolbarDir, withIntermediateDirectories: true)

func savePNG(_ image: NSImage, pixelWidth: Int, pixelHeight: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }

    rep.size = NSSize(width: pixelWidth, height: pixelHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try pngData.write(to: url)
    }
}

func drawAppIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let pad = size * 0.095
    let boxRect = NSRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
    let radius = boxRect.width * 0.225

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: NSColor(white: 0, alpha: 0.28).cgColor)
    let bgPath = NSBezierPath(roundedRect: boxRect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.92, alpha: 1.0).setFill()
    bgPath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    bgPath.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.12, green: 0.38, blue: 0.90, alpha: 1.0)
    ])
    gradient?.draw(in: boxRect, angle: -65)

    let centerX = size * 0.5
    let toothW = size * 0.075
    let toothH = size * 0.042
    let startY = boxRect.maxY - size * 0.08
    let endY = boxRect.minY + size * 0.42

    NSColor(white: 1.0, alpha: 0.94).setFill()
    var index = 0
    var curY = startY
    while curY > endY {
        let offsetX = (index % 2 == 0) ? -toothW * 0.55 : toothW * 0.05
        let tRect = NSRect(x: centerX + offsetX, y: curY, width: toothW * 0.5, height: toothH * 0.72)
        NSBezierPath(roundedRect: tRect, xRadius: toothH * 0.2, yRadius: toothH * 0.2).fill()
        curY -= toothH * 0.95
        index += 1
    }

    let sliderW = size * 0.15
    let sliderH = size * 0.19
    let sliderRect = NSRect(x: centerX - sliderW * 0.5, y: endY - sliderH * 0.75, width: sliderW, height: sliderH)
    let sliderPath = NSBezierPath(roundedRect: sliderRect, xRadius: sliderW * 0.28, yRadius: sliderW * 0.28)
    NSColor.white.setFill()
    sliderPath.fill()

    let holeW = sliderW * 0.38
    let holeH = sliderH * 0.36
    let holeRect = NSRect(x: centerX - holeW * 0.5, y: sliderRect.minY + sliderH * 0.22, width: holeW, height: holeH)
    NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.89, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: holeRect, xRadius: holeW * 0.3, yRadius: holeW * 0.3).fill()

    let barH = size * 0.12
    let barRect = NSRect(x: boxRect.minX, y: boxRect.minY, width: boxRect.width, height: barH)
    NSColor(white: 0.0, alpha: 0.14).setFill()
    barRect.fill()

    ctx.restoreGState()
    img.unlockFocus()
    return img
}

let iconSpecs: [(String, Int)] = [
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

for (filename, px) in iconSpecs {
    let img = drawAppIcon(size: CGFloat(px))
    try savePNG(img, pixelWidth: px, pixelHeight: px, to: iconsetDir.appendingPathComponent(filename))
}

// Generate crisp 16pt (16px & 32px @2x) badge icon for Finder Toolbar (matches Bandizip 32x32 @2x standard)
func drawToolbarBadge(px: Int) -> NSImage {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let circle = NSBezierPath(ovalIn: rect)

    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.72, blue: 0.62, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.88, alpha: 1.0)
    ])
    grad?.draw(in: circle, angle: -55)

    // Crisp white zipper icon inside badge
    NSColor.white.setFill()
    let cx = s * 0.5
    let toothW = s * 0.11
    let toothH = s * 0.085
    var y = rect.maxY - s * 0.17
    var i = 0
    while y > rect.minY + s * 0.43 {
        let ox = (i % 2 == 0) ? -toothW : 0
        let r = NSRect(x: cx + ox, y: y, width: toothW, height: toothH * 0.8)
        NSBezierPath(roundedRect: r, xRadius: toothH * 0.2, yRadius: toothH * 0.2).fill()
        y -= toothH * 1.05
        i += 1
    }

    // Zipper pull slider
    let pw = s * 0.24
    let ph = s * 0.24
    let pullRect = NSRect(x: cx - pw * 0.5, y: rect.minY + s * 0.16, width: pw, height: ph)
    NSBezierPath(roundedRect: pullRect, xRadius: pw * 0.28, yRadius: pw * 0.28).fill()

    // Inner dot on slider
    let hw = pw * 0.38
    let hh = ph * 0.38
    let holeRect = NSRect(x: cx - hw * 0.5, y: pullRect.minY + ph * 0.31, width: hw, height: hh)
    NSColor(calibratedRed: 0.10, green: 0.54, blue: 0.78, alpha: 1.0).setFill()
    NSBezierPath(ovalIn: holeRect).fill()

    img.unlockFocus()
    return img
}

let tb1x = drawToolbarBadge(px: 16)
try savePNG(tb1x, pixelWidth: 16, pixelHeight: 16, to: toolbarDir.appendingPathComponent("ToolbarIcon.png"))

let tb2x = drawToolbarBadge(px: 32)
try savePNG(tb2x, pixelWidth: 32, pixelHeight: 32, to: toolbarDir.appendingPathComponent("ToolbarIcon@2x.png"))
