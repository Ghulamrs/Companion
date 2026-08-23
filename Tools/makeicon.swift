import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The app icon, drawn rather than drafted in an editor so it can be regenerated
// and adjusted in one place. Built on the accent colour the app already uses to
// tint its own message bubbles, so the icon belongs to the app rather than
// merely sitting beside it.

let side = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// No alpha: an app icon is opaque, and iOS applies its own rounding and mask.
guard let ctx = CGContext(
    data: nil, width: Int(side), height: Int(side),
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

// Work in top-left origin, which is how the geometry below reads.
ctx.translateBy(x: 0, y: side)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, 1])!
}

// The accent from Assets.xcassets, lightened and darkened for the gradient.
let accent = rgb(0.839, 0.416, 0.361)
let light  = rgb(0.925, 0.573, 0.502)
let dark   = rgb(0.706, 0.290, 0.243)

let gradient = CGGradient(
    colorsSpace: space,
    colors: [light, accent, dark] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: side, y: side),
    options: []
)

// A speech bubble: the app is a conversation, and the empty state already uses
// this shape. Kept large and simple, because this is read at 60 points.
let bubble = CGRect(x: 214, y: 286, width: 596, height: 396)
let path = CGMutablePath()
path.addRoundedRect(in: bubble, cornerWidth: 132, cornerHeight: 132)

// The tail. Both upper vertices sit *inside* the bubble and on its straight
// bottom edge — not in the rounded corner, where the curve pulls away from a
// straight edge and leaves a visible notch at the join.
let tail = CGMutablePath()
tail.move(to: CGPoint(x: 404, y: 640))
tail.addLine(to: CGPoint(x: 566, y: 640))
tail.addLine(to: CGPoint(x: 366, y: 818))
tail.closeSubpath()

ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
ctx.addPath(path)
ctx.addPath(tail)
ctx.fillPath()

// Three dots: a reply arriving, which is the one thing this app does.
ctx.setFillColor(accent)
for x in [364.0, 512.0, 660.0] {
    ctx.fillEllipse(in: CGRect(x: x - 40, y: 444, width: 80, height: 80))
}

guard let image = ctx.makeImage() else { exit(1) }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")

// Regenerate with:
//
//   swift Tools/makeicon.swift \
//         Companion/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Xcode derives every smaller size from this one 1024×1024 file.
