// Draws the Wakey Wakey app icon: the crescent Luna from the logo, glowing on the night sky.
// Usage: swift ios/Tools/make_icon.swift <output.png>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha,
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Draw with y pointing down, like the logo's SVG coordinates.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
let full = CGRect(x: 0, y: 0, width: size, height: size)

// Night sky: deep indigo fading to near-black, with a periwinkle glow at the top.
let sky = CGGradient(colorsSpace: space, colors: [rgb(0x262A52), rgb(0x14152A), rgb(0x0C0D16)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xA5B4FC, 0.38), rgb(0xA5B4FC, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 80), startRadius: 0, endCenter: CGPoint(x: 512, y: 80), endRadius: 760, options: [])

// Faint background stars.
for (x, y, r, a) in [(170.0, 190.0, 5.0, 0.55), (860.0, 250.0, 4.0, 0.5), (130.0, 700.0, 4.0, 0.35),
                     (880.0, 790.0, 5.0, 0.4), (300.0, 900.0, 3.0, 0.3), (760.0, 120.0, 3.0, 0.45)] {
    ctx.setFillColor(rgb(0xFFFFFF, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// Luna, in the logo's 64-unit coordinates, scaled up and centered.
let s: CGFloat = 12.5
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + (x - 32) * s, y: 530 + (y - 31) * s) }
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
    let c = p(cx, cy)
    return CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s)
}
// The crescent: the moon's disc with a bite taken out of its upper right.
let disc = circle(32.34, 31.23, 26)
let bite = circle(60.16, 21.41, 21)

/// Limits drawing to the crescent: inside the disc, and outside the bite.
func crescentClip() {
    ctx.addEllipse(in: disc)
    ctx.clip()
    ctx.addRect(full)
    ctx.addEllipse(in: bite)
    ctx.clip(using: .evenOdd)
}

// Soft gold glow behind the crescent.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 90, color: rgb(0xF6D98B, 0.55))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
crescentClip()
ctx.setFillColor(rgb(0xF3CF7A))
ctx.fill(full)
ctx.endTransparencyLayer()
ctx.restoreGState()

ctx.saveGState()
crescentClip()
let gold = CGGradient(colorsSpace: space, colors: [rgb(0xFFF6D6), rgb(0xF6D98B), rgb(0xE9BE62)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawRadialGradient(gold, startCenter: p(22, 22), startRadius: 0, endCenter: p(22, 22), endRadius: 40 * s, options: [.drawsAfterEndLocation])
// Craters and a rosy cheek.
ctx.setFillColor(rgb(0xE2B55A, 0.45))
ctx.fillEllipse(in: circle(17, 18, 3.2))
ctx.fillEllipse(in: circle(30, 50, 2.6))
ctx.setFillColor(rgb(0xFF9FB0, 0.6))
ctx.fillEllipse(in: circle(12.5, 38, 2.6))
ctx.fillEllipse(in: circle(32, 37.5, 2.6))
ctx.restoreGState()

// The sleepy smile: closed happy eyes and a little grin.
ctx.setStrokeColor(rgb(0x5B4630))
ctx.setLineWidth(3 * s)
ctx.setLineCap(.round)
for x: CGFloat in [12.5, 25] {
    ctx.move(to: p(x, 31.5))
    ctx.addQuadCurve(to: p(x + 7, 31.5), control: p(x + 3.5, 27.5))
}
ctx.move(to: p(18, 37.5))
ctx.addQuadCurve(to: p(26, 37.5), control: p(22, 42))
ctx.strokePath()

// Sparkles in the moon's bite.
func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let c = p(x, y), d = r * s
    ctx.move(to: CGPoint(x: c.x, y: c.y - d))
    ctx.addQuadCurve(to: CGPoint(x: c.x + d, y: c.y), control: c)
    ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y + d), control: c)
    ctx.addQuadCurve(to: CGPoint(x: c.x - d, y: c.y), control: c)
    ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y - d), control: c)
    ctx.fillPath()
}
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xFFF3C4, 0.8))
ctx.setFillColor(rgb(0xFFF3C4))
sparkle(52, 15, 5)
sparkle(59, 31, 3)
ctx.restoreGState()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: output)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote", output)
