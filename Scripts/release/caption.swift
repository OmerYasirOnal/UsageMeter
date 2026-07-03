import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func load(_ p: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func save(_ img: CGImage, _ p: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: p) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
func rp(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

func drawCentered(_ ctx: CGContext, _ text: String, _ font: CTFont, _ color: CGColor, _ centerX: CGFloat, _ baselineY: CGFloat) {
    let attr = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
    let astr = CFAttributedStringCreate(nil, text as CFString, attr)!
    let line = CTLineCreateWithAttributedString(astr)
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: centerX - b.width / 2 - b.origin.x, y: baselineY)
    CTLineDraw(line, ctx)
}

// args: input cropX cropY cropW cropH output headline subhead
let a = CommandLine.arguments
let full = load(a[1])
let cx = Int(a[2])!, cyTop = Int(a[3])!, cw = Int(a[4])!, ch = Int(a[5])!
let out = a[6]
let headline = a[7]
let subhead = a[8]
// CGImage.cropping uses a TOP-LEFT origin coordinate space.
let cropped = full.cropping(to: CGRect(x: cx, y: cyTop, width: cw, height: ch))!

let CW = 2880, CH = 1800
let ctx = CGContext(data: nil, width: CW, height: CH, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Kiln: warm cream gradient background
let g = CGGradient(colorsSpace: cs, colors: [
    rgb(0.99, 0.97, 0.94), rgb(0.96, 0.92, 0.87)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CH), end: CGPoint(x: 0, y: 0), options: [])

// captions — Kiln ink (deep teal) headline + terracotta subhead
let hFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 88, nil)
let sFont = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 42, nil)
drawCentered(ctx, headline, hFont, rgb(0.06, 0.29, 0.27), CGFloat(CW) / 2, CGFloat(CH) - 150)
drawCentered(ctx, subhead, sFont, rgb(0.76, 0.25, 0.05), CGFloat(CW) / 2, CGFloat(CH) - 232)

// window: fit into region below captions
let topFromTop: CGFloat = 320, bottomPad: CGFloat = 70, maxW: CGFloat = 2140
let availH = CGFloat(CH) - topFromTop - bottomPad
let aspect = CGFloat(cw) / CGFloat(ch)
var dw = maxW, dh = dw / aspect
if dh > availH { dh = availH; dw = dh * aspect }
let dx = (CGFloat(CW) - dw) / 2
let dyBL = bottomPad + (availH - dh) / 2
let frame = CGRect(x: dx, y: dyBL, width: dw, height: dh)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 64, color: rgb(0, 0, 0, 0.30))
ctx.addPath(rp(frame, 26)); ctx.setFillColor(rgb(1, 1, 1)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rp(frame, 26)); ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(cropped, in: frame)
ctx.restoreGState()

save(ctx.makeImage()!, out)
print("wrote \(out)  window \(Int(dw))x\(Int(dh)) at \(Int(dx)),\(Int(dyBL))")
