#!/usr/bin/env swift
//
// Renders julia's app icon — the palette with a lit jump target and an
// agent replying in typing dots — into AppIcon.appiconset. Design chosen
// via mockups/icon-options-6.html (concept D2). Rerun after any tweak:
//
//   swift scripts/GenerateAppIcon.swift
//
import AppKit

let canvas: CGFloat = 1024
let inset: CGFloat = 100
let tileRadius: CGFloat = 185
let blue = CGColor(srgbRed: 0x6A / 255, green: 0xB0 / 255, blue: 0xF3 / 255, alpha: 1)

func makeContext(size: Int) -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
              data: nil, width: size, height: size,
              bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { fatalError("no context") }
    return ctx
}

func fillRoundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

let ctx = makeContext(size: Int(canvas))
// Flip to y-down so geometry matches the mockup's canvas coordinates.
ctx.translateBy(x: 0, y: canvas)
ctx.scaleBy(x: 1, y: -1)

let tile = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

// Tile with drop shadow (shadow offsets live in device space, which the
// flip inverted — positive height moves the shadow down on screen).
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 36,
              color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(tilePath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [
        CGColor(srgbRed: 0x26 / 255, green: 0x2B / 255, blue: 0x33 / 255, alpha: 1),
        CGColor(srgbRed: 0x19 / 255, green: 0x1D / 255, blue: 0x23 / 255, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: inset),
                       end: CGPoint(x: 0, y: canvas - inset),
                       options: [])
ctx.restoreGState()

// The clipped gradient can't cast the shadow itself; redo shadow under
// the tile with a solid pass first, then re-draw gradient on top.
// (Order above already yields both: clip discards the shadow, so paint
// a shadow-casting shape beneath.)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 36,
              color: CGColor(gray: 0, alpha: 0.35))
ctx.setFillColor(CGColor(srgbRed: 0x19 / 255, green: 0x1D / 255, blue: 0x23 / 255, alpha: 1))
ctx.addPath(tilePath)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: inset),
                       end: CGPoint(x: 0, y: canvas - inset),
                       options: [])
ctx.restoreGState()

// Rim
ctx.saveGState()
ctx.addPath(tilePath)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

let x: CGFloat = 220
let w: CGFloat = canvas - 440

// Search bar
ctx.setFillColor(CGColor(gray: 1, alpha: 0.13))
fillRoundedRect(ctx, CGRect(x: x, y: 240, width: w, height: 130), radius: 46)

// Prompt glyph, drawn via CoreText with the text matrix un-flipped
ctx.saveGState()
let font = NSFont.monospacedSystemFont(ofSize: 108, weight: .semibold)
let prompt = NSAttributedString(string: "❯", attributes: [
    .font: font,
    .foregroundColor: NSColor(cgColor: blue) ?? .systemBlue,
])
let line = CTLineCreateWithAttributedString(prompt)
ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
ctx.textPosition = CGPoint(x: x + 42, y: 310 + 38)
CTLineDraw(line, ctx)
ctx.restoreGState()

// Caret
ctx.setFillColor(blue)
ctx.fill(CGRect(x: x + 130, y: 262, width: 14, height: 88))

// Rows: jump target lit, others resting
let rows: [CGFloat] = [430, 560, 690]
for (index, y) in rows.enumerated() {
    ctx.setFillColor(index == 1 ? blue : CGColor(gray: 1, alpha: 0.10))
    fillRoundedRect(ctx, CGRect(x: x, y: y, width: w, height: 100), radius: 38)
}

// Typing dots on the bottom row — an agent is replying
ctx.setFillColor(CGColor(gray: 1, alpha: 0.6))
for i in -1...1 {
    let cx = x + 130 + CGFloat(i) * 52
    ctx.fillEllipse(in: CGRect(x: cx - 15, y: rows[2] + 50 - 15, width: 30, height: 30))
}

ctx.restoreGState()

guard let master = ctx.makeImage() else { fatalError("no image") }

// Emit every size the appiconset needs.
let outputDirectory = URL(filePath: "Julia/Assets.xcassets/AppIcon.appiconset")
let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]
for size in pixelSizes {
    let scaled = makeContext(size: size)
    scaled.interpolationQuality = .high
    scaled.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = scaled.makeImage() else { fatalError("no scaled image \(size)") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png \(size)") }
    let url = outputDirectory.appending(path: "icon_\(size).png")
    do {
        try png.write(to: url)
        print("wrote \(url.path())")
    } catch {
        fatalError("write failed: \(error)")
    }
}
