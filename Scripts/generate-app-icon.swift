// generate-app-icon.swift
// ProWork uygulama ikonunu CoreGraphics ile üretir.
// Kullanım: swift Scripts/generate-app-icon.swift <size> <output.png>
//
// Konsept: yeşil→mavi gradient zemin üzerinde büyük beyaz saat halkası
// (12/3/6/9 çentikleriyle), ortasında beyaz play üçgeni.

import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 3,
      let size = Double(CommandLine.arguments[1]) else {
    print("Usage: swift generate-app-icon.swift <size> <output.png>")
    exit(1)
}
let outputPath = CommandLine.arguments[2]
let s = CGFloat(size)

// Palet: turkuaz → mavi (yeşil hissi azaltılmış, mavi ağırlıklı)
let colorStart = NSColor(red: 0x06/255.0, green: 0xB6/255.0, blue: 0xD4/255.0, alpha: 1) // #06B6D4 cyan-500
let colorEnd   = NSColor(red: 0x25/255.0, green: 0x63/255.0, blue: 0xEB/255.0, alpha: 1) // #2563EB blue-600

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil,
    width: Int(s),
    height: Int(s),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let cornerRadius = s * 0.225
let bgRect = CGRect(x: 0, y: 0, width: s, height: s)

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Background
ctx.saveGState()
ctx.addPath(roundedRectPath(bgRect, radius: cornerRadius))
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs,
                        colors: [colorStart.cgColor, colorEnd.cgColor] as CFArray,
                        locations: [0, 1])!
ctx.drawLinearGradient(
    bgGrad,
    start: CGPoint(x: 0, y: s),
    end:   CGPoint(x: s, y: 0),
    options: []
)
let highlight = CGGradient(colorsSpace: cs,
                           colors: [NSColor.white.withAlphaComponent(0.18).cgColor,
                                    NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
ctx.drawLinearGradient(highlight,
                       start: CGPoint(x: s/2, y: s),
                       end:   CGPoint(x: s/2, y: s * 0.4),
                       options: [])
ctx.restoreGState()

// MARK: - Clock ring (white, large)
let center = CGPoint(x: s/2, y: s/2)
let ringR = s * 0.32
let ringW = s * 0.06

ctx.saveGState()
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(ringW)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: ringR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()
ctx.restoreGState()

// MARK: - Hour ticks at 12, 3, 6, 9
ctx.saveGState()
for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 2) {
    let outerR = ringR - ringW * 0.7
    let innerR = ringR - ringW * 1.7
    let x1 = center.x + cos(angle) * innerR
    let y1 = center.y + sin(angle) * innerR
    let x2 = center.x + cos(angle) * outerR
    let y2 = center.y + sin(angle) * outerR
    ctx.setLineWidth(ringW * 0.55)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.move(to: CGPoint(x: x1, y: y1))
    ctx.addLine(to: CGPoint(x: x2, y: y2))
    ctx.strokePath()
}
ctx.restoreGState()

// MARK: - Play triangle (white, centered)
ctx.saveGState()
let triR = s * 0.14
ctx.setFillColor(NSColor.white.cgColor)
ctx.move(to: CGPoint(x: center.x - triR * 0.55, y: center.y + triR * 0.85))
ctx.addLine(to: CGPoint(x: center.x - triR * 0.55, y: center.y - triR * 0.85))
ctx.addLine(to: CGPoint(x: center.x + triR * 0.95, y: center.y))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// MARK: - Save PNG
let cgImg = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: cgImg)
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: outputPath))
print("✓ \(Int(s))×\(Int(s)) → \(outputPath)")
