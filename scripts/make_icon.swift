import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDir = scriptURL.deletingLastPathComponent()
let iconsetDir = scriptDir.appendingPathComponent("AppIcon.iconset")
let outputIcns = scriptDir.appendingPathComponent("AppIcon.icns")
let resourcesPNG = scriptDir.appendingPathComponent("AppIcon.png")

let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Mika+ Familien-Palette
let mint = NSColor(red: 0.30, green: 0.82, blue: 0.65, alpha: 1.0)
let bgTop = NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1.0)
let bgBottom = NSColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1.0)
let badgeTextColor = NSColor.white

func drawIcon(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    let detailed = pixelSize >= 64
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.2237
    let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
    NSGraphicsContext.current?.saveGraphicsState()
    bgPath.addClip()

    // Hintergrund-Gradient
    let bgGradient = NSGradient(colors: [bgTop, bgBottom])!
    bgGradient.draw(in: bounds, angle: -90)

    // Subtile horizontale Scanlines (wie ScreenSnap/FileScope)
    if detailed {
        let scanlineSpacing = max(3.0, size / 170.0)
        let scanlineHeight = max(0.5, size / 1500.0)
        NSColor(white: 1.0, alpha: 0.022).set()
        var y: CGFloat = 0
        while y < size {
            NSRect(x: 0, y: y, width: size, height: scanlineHeight).fill()
            y += scanlineSpacing
        }
    }

    // Weicher mint-Glow hinter dem Gauge
    let glowCenter = NSPoint(x: size / 2, y: size * 0.55)
    let glow = NSGradient(colors: [
        mint.withAlphaComponent(0.28),
        mint.withAlphaComponent(0.0)
    ])!
    glow.draw(fromCenter: glowCenter, radius: 0,
              toCenter: glowCenter, radius: size * 0.42,
              options: [])

    // Gauge-Bogen: 270° offen unten, von 225° (links unten) über oben nach -45° (rechts unten)
    let gaugeCenter = NSPoint(x: size / 2, y: size * 0.55)
    let gaugeRadius = size * 0.28
    let strokeW = size * 0.030

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setStrokeColor(mint.cgColor)
    ctx.setLineWidth(strokeW)
    ctx.beginPath()
    ctx.addArc(center: gaugeCenter, radius: gaugeRadius,
               startAngle: .pi * (5.0/4.0),
               endAngle: .pi * (-1.0/4.0),
               clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // Tick-Marks entlang des Bogens
    if detailed {
        let tickCount = 5
        let arcStart: CGFloat = .pi * (5.0/4.0)
        let totalSweep: CGFloat = .pi * 3.0 / 2.0
        let tickLen = size * 0.045
        let tickWidth = size * 0.018
        ctx.saveGState()
        ctx.setStrokeColor(mint.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(tickWidth)
        ctx.setLineCap(.round)
        let outerR = gaugeRadius - strokeW * 0.5 - size * 0.015
        let innerR = outerR - tickLen
        for i in 0..<tickCount {
            let t = CGFloat(i) / CGFloat(tickCount - 1)
            let angle = arcStart - t * totalSweep
            ctx.move(to: NSPoint(
                x: gaugeCenter.x + innerR * cos(angle),
                y: gaugeCenter.y + innerR * sin(angle)
            ))
            ctx.addLine(to: NSPoint(
                x: gaugeCenter.x + outerR * cos(angle),
                y: gaugeCenter.y + outerR * sin(angle)
            ))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Nadel: zeigt in den oberen rechten Bereich (Tempo!)
    let needleAngle: CGFloat = .pi / 4   // 45°, dynamisch
    let needleLen = gaugeRadius * 0.82
    let needleTip = NSPoint(
        x: gaugeCenter.x + needleLen * cos(needleAngle),
        y: gaugeCenter.y + needleLen * sin(needleAngle)
    )
    ctx.saveGState()
    ctx.setStrokeColor(mint.cgColor)
    ctx.setLineWidth(size * 0.028)
    ctx.setLineCap(.round)
    ctx.move(to: gaugeCenter)
    ctx.addLine(to: needleTip)
    ctx.strokePath()

    // Hub (mit dunklem Innendot für mehr Tiefe)
    let hubR = size * 0.045
    ctx.setFillColor(mint.cgColor)
    ctx.fillEllipse(in: NSRect(
        x: gaugeCenter.x - hubR, y: gaugeCenter.y - hubR,
        width: hubR * 2, height: hubR * 2
    ))
    if detailed {
        let innerR = hubR * 0.42
        ctx.setFillColor(bgBottom.cgColor)
        ctx.fillEllipse(in: NSRect(
            x: gaugeCenter.x - innerR, y: gaugeCenter.y - innerR,
            width: innerR * 2, height: innerR * 2
        ))
    }
    ctx.restoreGState()

    // M+ Pill-Badge rechts unten
    if detailed {
        let badgeWidth = size * 0.27
        let badgeHeight = size * 0.16
        let badgeMargin = size * 0.07
        let badgeRect = NSRect(
            x: size - badgeMargin - badgeWidth,
            y: badgeMargin,
            width: badgeWidth,
            height: badgeHeight
        )
        let badgeRadius = badgeHeight / 2

        // Optional weicher Schatten unterhalb der Pill
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.008),
            blur: size * 0.025,
            color: NSColor(white: 0, alpha: 0.45).cgColor
        )
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRadius, yRadius: badgeRadius)
        mint.setFill()
        badgePath.fill()
        ctx.restoreGState()

        let badgeFontSize = badgeHeight * 0.58
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: badgeFontSize, weight: .heavy),
            .foregroundColor: badgeTextColor
        ]
        let badgeText = NSAttributedString(string: "M+", attributes: badgeAttrs)
        let textSize = badgeText.size()
        let textOrigin = NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2 + badgeHeight * 0.02
        )
        badgeText.draw(at: textOrigin)
    }

    NSGraphicsContext.current?.restoreGraphicsState()
    img.unlockFocus()

    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("no cgImage")
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

let exports: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixelSize) in exports {
    let data = drawIcon(pixelSize: pixelSize)
    try data.write(to: iconsetDir.appendingPathComponent(name))
    print("✓ \(name) (\(pixelSize)px, \(data.count / 1024) KB)")
}

// Standalone 1024er PNG für Resources/Preview ablegen
let bigPNG = drawIcon(pixelSize: 1024)
try bigPNG.write(to: resourcesPNG)
print("✓ AppIcon.png (1024px Preview)")

// .icns bauen
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcns.path]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✓ AppIcon.icns generiert")
} else {
    print("✗ iconutil fehlgeschlagen")
    exit(1)
}
