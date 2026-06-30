import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Pure CoreGraphics icon renderer — fully headless (no display / AppKit / SwiftUI).
// Usage:
//   swift render.swift single <concept> <out.png> <size>
//   swift render.swift contact <out.png>     (3x2 grid of all concepts)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
// Claude coral accent = sRGB(0.851, 0.467, 0.341) = #D97757
let coralTop    = col(0.94, 0.57, 0.44)   // lighter top
let coralBottom = col(0.74, 0.35, 0.24)   // deeper bottom
let coralMid    = col(0.851, 0.467, 0.341)
let white       = col(1, 1, 1)

// Intended output pixel size of the current render (so glyphs can adapt for
// small-size legibility: drop fine detail and thicken strokes when tiny).
var gTargetPx = 1024

func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

// macOS-style continuous "squircle" via superellipse sampling.
func squircle(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2 / n), ct)
        let y = cy + b * copysign(pow(abs(st), 2 / n), st)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

// Sample an arc as a path. Angles in degrees (math convention, 0=+x, 90=up).
// Sweeps from startDeg to endDeg linearly (handles either direction).
func arcPath(center c: CGPoint, radius r: CGFloat, startDeg s: CGFloat, endDeg e: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let steps = 240
    for i in 0...steps {
        let a = deg(s + (e - s) * CGFloat(i) / CGFloat(steps))
        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}

func dot(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// Draw a tapered needle from the gauge center to a point at value angle.
func needle(_ ctx: CGContext, center c: CGPoint, angleDeg: CGFloat, length: CGFloat, baseW: CGFloat, color: CGColor) {
    let a = deg(angleDeg)
    let tip = CGPoint(x: c.x + length * cos(a), y: c.y + length * sin(a))
    // perpendicular for the base width
    let pa = a + .pi / 2
    let bx = baseW / 2 * cos(pa), by = baseW / 2 * sin(pa)
    let backLen = length * 0.18
    let back = CGPoint(x: c.x - backLen * cos(a), y: c.y - backLen * sin(a))
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x + bx, y: c.y + by))
    p.addLine(to: tip)
    p.addLine(to: CGPoint(x: c.x - bx, y: c.y - by))
    p.addLine(to: back)
    p.closeSubpath()
    ctx.setFillColor(color)
    ctx.addPath(p)
    ctx.fillPath()
}

// Draw one full icon (background squircle + glyph) into `frame`.
func drawIcon(_ ctx: CGContext, concept: String, frame f: CGRect) {
    let W = f.width
    let sq = squircle(f)

    // soft contact shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -W * 0.018), blur: W * 0.05, color: col(0, 0, 0, 0.28))
    ctx.setFillColor(coralBottom)
    ctx.addPath(sq); ctx.fillPath()
    ctx.restoreGState()

    // gradient fill clipped to squircle
    ctx.saveGState()
    ctx.addPath(sq); ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [coralTop, coralBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: f.midX, y: f.maxY), end: CGPoint(x: f.midX, y: f.minY), options: [])
    // subtle top sheen
    let sheen = CGGradient(colorsSpace: cs, colors: [col(1, 1, 1, 0.16), col(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: f.midX, y: f.maxY), end: CGPoint(x: f.midX, y: f.midY + W * 0.05), options: [])
    ctx.restoreGState()

    // glyph
    ctx.saveGState()
    ctx.addPath(sq); ctx.clip()   // keep glyph inside the squircle
    let cx = f.midX
    switch concept {

    case "gauge":
        // speedometer arc + ticks + needle, open at bottom
        let gc = CGPoint(x: cx, y: f.midY - W * 0.02)
        let R = W * 0.30
        let lw = W * 0.055
        ctx.setStrokeColor(white); ctx.setLineWidth(lw); ctx.setLineCap(.round)
        ctx.addPath(arcPath(center: gc, radius: R, startDeg: 210, endDeg: -30)); ctx.strokePath()
        // ticks
        for i in 0...8 {
            let a = deg(210 - 240 * CGFloat(i) / 8)
            let r1 = R - lw * 0.55, r2 = R - lw * 1.7
            let p = CGMutablePath()
            p.move(to: CGPoint(x: gc.x + r1 * cos(a), y: gc.y + r1 * sin(a)))
            p.addLine(to: CGPoint(x: gc.x + r2 * cos(a), y: gc.y + r2 * sin(a)))
            ctx.setStrokeColor(col(1, 1, 1, 0.55)); ctx.setLineWidth(W * 0.012); ctx.setLineCap(.round)
            ctx.addPath(p); ctx.strokePath()
        }
        needle(ctx, center: gc, angleDeg: 210 - 240 * 0.68, length: R * 0.92, baseW: W * 0.05, color: white)
        dot(ctx, gc, W * 0.035, white)

    case "gaugefill":
        // thick progress gauge: bright filled arc shows the consumption LEVEL,
        // faint remainder track (large sizes only), needle marks the value.
        // Size-adaptive per the design panel: drop the track & thicken when tiny.
        let px = CGFloat(gTargetPx)
        let showTrack = px > 32
        let showNeedle = px > 20
        let depth = px >= 256
        let gc = CGPoint(x: cx, y: f.midY - W * 0.05)   // optical center: nudge down
        let R = W * 0.275                               // breathing room from edge
        let lw = (px <= 32 ? W * 0.11 : W * 0.09)       // thicker arc when small
        let v: CGFloat = 0.68                           // "partly consumed"
        let fillEnd = 210 - 240 * v
        ctx.setLineCap(.round); ctx.setLineWidth(lw)
        // faint remainder track (large only)
        if showTrack {
            ctx.setStrokeColor(col(1, 1, 1, 0.30))
            ctx.addPath(arcPath(center: gc, radius: R, startDeg: fillEnd, endDeg: -30)); ctx.strokePath()
        }
        // bright filled arc (pure white, soft depth shadow at large sizes)
        ctx.saveGState()
        if depth { ctx.setShadow(offset: CGSize(width: 0, height: -W * 0.012), blur: W * 0.03, color: col(0, 0, 0, 0.22)) }
        ctx.setStrokeColor(white)
        ctx.addPath(arcPath(center: gc, radius: R, startDeg: 210, endDeg: fillEnd)); ctx.strokePath()
        ctx.restoreGState()
        // needle: thick, stops well inside the arc; anchored on a pivot hub
        if showNeedle {
            needle(ctx, center: gc, angleDeg: fillEnd,
                   length: px <= 32 ? R * 0.60 : R * 0.72,
                   baseW: px <= 32 ? W * 0.075 : W * 0.052, color: white)
        }
        dot(ctx, gc, px <= 32 ? W * 0.07 : W * 0.052, white)
        if px > 32 { dot(ctx, gc, W * 0.020, coralMid) }   // pivot center

    case "arcdots":
        // gauge made of dots + needle (mirrors the SF symbol the app uses)
        let gc = CGPoint(x: cx, y: f.midY - W * 0.02)
        let R = W * 0.30
        for i in 0...10 {
            let a = deg(210 - 240 * CGFloat(i) / 10)
            let big = (i % 5 == 0)
            dot(ctx, CGPoint(x: gc.x + R * cos(a), y: gc.y + R * sin(a)), W * (big ? 0.028 : 0.018), col(1, 1, 1, big ? 1 : 0.7))
        }
        needle(ctx, center: gc, angleDeg: 210 - 240 * 0.68, length: R * 0.86, baseW: W * 0.05, color: white)
        dot(ctx, gc, W * 0.04, white)

    case "ring":
        // progress ring / donut, ~74%
        let gc = CGPoint(x: cx, y: f.midY)
        let R = W * 0.26
        let lw = W * 0.10
        ctx.setLineCap(.round); ctx.setLineWidth(lw)
        ctx.setStrokeColor(col(1, 1, 1, 0.26))
        ctx.addPath(arcPath(center: gc, radius: R, startDeg: 90, endDeg: 90 - 360)); ctx.strokePath()
        ctx.setStrokeColor(white)
        ctx.addPath(arcPath(center: gc, radius: R, startDeg: 90, endDeg: 90 - 360 * 0.74)); ctx.strokePath()
        // inner subtle needle/dot
        dot(ctx, gc, W * 0.045, col(1, 1, 1, 0.9))

    case "bars":
        // ascending bar chart
        let n = 4
        let gap = W * 0.045
        let totalW = W * 0.40
        let barW = (totalW - gap * CGFloat(n - 1)) / CGFloat(n)
        let baseY = f.midY - W * 0.18
        let startX = cx - totalW / 2
        let heights: [CGFloat] = [0.14, 0.22, 0.30, 0.40]
        for i in 0..<n {
            let h = W * heights[i]
            let x = startX + CGFloat(i) * (barW + gap)
            let r = CGPath(roundedRect: CGRect(x: x, y: baseY, width: barW, height: h),
                           cornerWidth: barW * 0.35, cornerHeight: barW * 0.35, transform: nil)
            ctx.setFillColor(col(1, 1, 1, 0.55 + 0.15 * CGFloat(i)))
            ctx.addPath(r); ctx.fillPath()
        }

    case "dial":
        // minimal analog dial: thin ring, ticks, single bold needle
        let gc = CGPoint(x: cx, y: f.midY)
        let R = W * 0.30
        ctx.setStrokeColor(col(1, 1, 1, 0.9)); ctx.setLineWidth(W * 0.018)
        ctx.addPath(CGPath(ellipseIn: CGRect(x: gc.x - R, y: gc.y - R, width: 2 * R, height: 2 * R), transform: nil))
        ctx.strokePath()
        for i in 0..<12 {
            let a = deg(CGFloat(i) * 30)
            let big = (i % 3 == 0)
            let r1 = R - W * 0.01, r2 = R - W * (big ? 0.06 : 0.035)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: gc.x + r1 * cos(a), y: gc.y + r1 * sin(a)))
            p.addLine(to: CGPoint(x: gc.x + r2 * cos(a), y: gc.y + r2 * sin(a)))
            ctx.setStrokeColor(col(1, 1, 1, big ? 1 : 0.5)); ctx.setLineWidth(W * (big ? 0.018 : 0.01)); ctx.setLineCap(.round)
            ctx.addPath(p); ctx.strokePath()
        }
        needle(ctx, center: gc, angleDeg: 65, length: R * 0.8, baseW: W * 0.05, color: white)
        dot(ctx, gc, W * 0.045, white)

    default:
        break
    }
    ctx.restoreGState()
}

func makeContext(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let concepts = ["gauge", "gaugefill", "arcdots", "ring", "bars", "dial"]
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "contact"

if mode == "single" {
    let concept = args[2]
    let out = args[3]
    let size = args.count > 4 ? Int(args[4])! : 1024
    gTargetPx = size
    let ctx = makeContext(size)
    let inset = Double(size) * 0.085
    drawIcon(ctx, concept: concept, frame: CGRect(x: inset, y: inset,
                                                  width: Double(size) - 2 * inset,
                                                  height: Double(size) - 2 * inset))
    writePNG(ctx.makeImage()!, out)
    print("wrote \(out)")
} else if mode == "showcase" {
    // one concept: large hero on the left, small-size ladder (NN-upscaled) on the right.
    let concept = args[2]
    let out = args.count > 3 ? args[3] : "showcase.png"
    let hero = 760, pad = 50, ladderW = 360
    let Wd = pad + hero + 40 + ladderW + pad
    let Hd = pad + hero + pad
    let ctx = makeContext(max(Wd, Hd))
    ctx.setFillColor(col(0.12, 0.12, 0.13)); ctx.fill(CGRect(x: 0, y: 0, width: max(Wd, Hd), height: max(Wd, Hd)))
    let canvas = max(Wd, Hd)
    func topY(_ y: Int, _ h: Int) -> Int { canvas - y - h }   // convert top-down to y-up
    // hero
    gTargetPx = hero
    let hx = pad, hy = pad
    let hInset = Double(hero) * 0.085
    drawIcon(ctx, concept: concept, frame: CGRect(x: Double(hx) + hInset, y: Double(topY(hy, hero)) + hInset,
                                                  width: Double(hero) - 2 * hInset, height: Double(hero) - 2 * hInset))
    // ladder
    ctx.interpolationQuality = .none
    let sizes = [16, 32, 48, 64, 128]
    var cy = pad
    let lx = pad + hero + 40
    for s in sizes {
        gTargetPx = s
        let sctx = makeContext(s)
        let inset = Double(s) * 0.085
        drawIcon(sctx, concept: concept, frame: CGRect(x: inset, y: inset, width: Double(s) - 2 * inset, height: Double(s) - 2 * inset))
        let img = sctx.makeImage()!
        let drawn = min(s * 6, 150)
        ctx.draw(img, in: CGRect(x: lx, y: topY(cy, drawn), width: drawn, height: drawn))
        cy += drawn + 20
    }
    writePNG(ctx.makeImage()!, out)
    print("wrote showcase: \(concept)")
} else if mode == "strip" {
    // small-size legibility: each concept (rows) at 16/32/48px (cols), upscaled nearest-neighbor.
    let sizes = [16, 32, 48]
    let scales = [9, 5, 4]            // upscale factors -> 144,160,192
    let cellW = 220, cellH = 220
    let Wd = sizes.count * cellW, Hd = concepts.count * cellH
    let ctx = makeContext(max(Wd, Hd))
    ctx.setFillColor(col(0.12, 0.12, 0.13)); ctx.fill(CGRect(x: 0, y: 0, width: max(Wd, Hd), height: max(Wd, Hd)))
    ctx.interpolationQuality = .none
    for (ri, c) in concepts.enumerated() {
        for (ci, s) in sizes.enumerated() {
            gTargetPx = s
            let sctx = makeContext(s)
            let inset = Double(s) * 0.085
            drawIcon(sctx, concept: c, frame: CGRect(x: inset, y: inset, width: Double(s) - 2 * inset, height: Double(s) - 2 * inset))
            let img = sctx.makeImage()!
            let drawn = s * scales[ci]
            let ox = ci * cellW + (cellW - drawn) / 2
            let oyTop = ri * cellH + (cellH - drawn) / 2
            let oy = max(Wd, Hd) - oyTop - drawn   // y-up flip for top-down rows
            ctx.draw(img, in: CGRect(x: ox, y: oy, width: drawn, height: drawn))
        }
    }
    writePNG(ctx.makeImage()!, args.count > 2 ? args[2] : "strip.png")
    print("wrote strip: rows=\(concepts) cols=\(sizes)")
} else {
    // contact sheet: 3 columns x 2 rows, each cell 420px, icon 340 inset
    let cols = 3, rows = 2, cell = 420
    let Wd = cols * cell, Hd = rows * cell
    let ctx = makeContext(max(Wd, Hd))
    // bg
    ctx.setFillColor(col(0.12, 0.12, 0.13)); ctx.fill(CGRect(x: 0, y: 0, width: Wd, height: Hd))
    for (i, c) in concepts.enumerated() {
        let cxi = i % cols, cyi = i / cols
        // note: y-up, so row 0 at top means high y
        let ox = CGFloat(cxi * cell)
        let oy = CGFloat((rows - 1 - cyi) * cell)
        let inset: CGFloat = 40
        let frame = CGRect(x: ox + inset, y: oy + inset, width: CGFloat(cell) - 2 * inset, height: CGFloat(cell) - 2 * inset)
        gTargetPx = cell
        drawIcon(ctx, concept: c, frame: frame)
    }
    writePNG(ctx.makeImage()!, args.count > 2 ? args[2] : "contact.png")
    print("wrote contact sheet: \(concepts)")
}
