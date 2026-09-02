#!/usr/bin/env swift
//
// gen-icon.swift — reproducible «dial diurno» app icon for Cénit (FER-158).
//
// Draws the brand glyph with CoreGraphics and emits the three iOS 18 appearances
// (light / dark / tinted) as 1024×1024 PNGs plus the matching Contents.json, so
// the AppIcon set is regenerable from source instead of being an opaque binary.
//
// The glyph is the «dial diurno»: a 24-hour ring, the daytime arc swept in warm
// ember-orange over the top, the cénit notch at 12 o'clock (the highest point —
// the name), and a green "now" dot riding the arc. No needle: the dot leads.
// Colours come from `InstrumentoTheme.base` in CenitDesign (kept in sync by
// hand; this script has no package deps so it runs as a plain `swift` file).
//
// Run:  swift Tools/gen-icon.swift CenitApp/Resources/Assets.xcassets/AppIcon.appiconset
// (defaults to that path when no argument is given). Legible down to 29 px.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (InstrumentoTheme.base — Packages/CenitDesign/Sources/CenitDesign/Instrumento.swift)

struct RGBA { let r, g, b, a: CGFloat }
func hex(_ s: String, alpha: CGFloat = 1) -> RGBA {
    var h = s; if h.hasPrefix("#") { h.removeFirst() }
    let v = UInt32(h, radix: 16) ?? 0
    return RGBA(r: CGFloat((v >> 16) & 0xFF) / 255,
                g: CGFloat((v >> 8) & 0xFF) / 255,
                b: CGFloat(v & 0xFF) / 255, a: alpha)
}

let paper     = hex("#F4F1E8")  // warm bone paper — the recommended (light) field
let ink       = hex("#221D16")  // warm near-black ink — the cénit notch on paper
let ember     = hex("#C4631F")  // dataStrain — the daytime arc
let green     = hex("#0C8F62")  // verdict/dataRecovery — the "now" dot
let trackLight = hex("#C7BEA9") // the night portion of the ring on paper
let inkDark   = hex("#1E1A14")  // dark-appearance field

// MARK: - Appearance

enum Appearance: String, CaseIterable {
    case light, dark, tinted

    /// Background fill for the whole icon (icons are opaque squares; iOS rounds).
    /// The recommended "light" face is warm paper; dark/tinted sit on warm ink.
    var background: RGBA {
        self == .light ? paper : inkDark
    }
    /// The night portion of the 24h ring (the full track under the day arc).
    var track: RGBA {
        switch self {
        case .light:  return trackLight
        case .dark:   return RGBA(r: paper.r, g: paper.g, b: paper.b, a: 0.22)
        case .tinted: return RGBA(r: 1, g: 1, b: 1, a: 0.28)
        }
    }
    /// The daytime arc.
    var arc: RGBA {
        // Tinted icons are grayscale: iOS composites the user's tint by luminance,
        // so the arc/dot are bright whites of slightly different weight.
        self == .tinted ? RGBA(r: 1, g: 1, b: 1, a: 0.92) : ember
    }
    /// The "now" dot.
    var dot: RGBA { self == .tinted ? RGBA(r: 1, g: 1, b: 1, a: 1) : green }
    /// The cénit notch — ink on paper, paper on ink, white when tinted.
    var notch: RGBA {
        switch self {
        case .light:  return ink
        case .dark:   return paper
        case .tinted: return RGBA(r: 1, g: 1, b: 1, a: 1)
        }
    }
}

// MARK: - Drawing

let size: CGFloat = 1024

func draw(_ ap: Appearance) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    func set(_ c: RGBA) { ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
                          ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }

    // Background
    set(ap.background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let center = CGPoint(x: size / 2, y: size / 2)
    let radius: CGFloat = 344        // fills the rounded tile while clearing the corner mask
    let ringWidth: CGFloat = 54

    // CoreGraphics angles are math-convention (0 = +x / 3 o'clock, CCW positive).
    // 12 o'clock (top, the cénit) = 90°. Day arc spans sunrise→sunset over the top:
    // 9 o'clock (180°) → 12 (90°) → 3 o'clock (0°), i.e. the upper half.
    func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
    func pointOnRing(_ angleDeg: CGFloat, _ r: CGFloat = radius) -> CGPoint {
        CGPoint(x: center.x + r * cos(deg(angleDeg)), y: center.y + r * sin(deg(angleDeg)))
    }

    // 1) Full 24h track ring.
    ctx.setLineCap(.round)
    ctx.setLineWidth(ringWidth)
    set(ap.track)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: deg(360), clockwise: false)
    ctx.strokePath()

    // 2) Daytime arc (upper half), warm ember.
    set(ap.arc)
    ctx.setLineWidth(ringWidth)
    ctx.addArc(center: center, radius: radius, startAngle: deg(180), endAngle: deg(0), clockwise: true)
    ctx.strokePath()

    // 3) Cénit notch at 12 o'clock — a short tick crossing the ring at the highest point.
    set(ap.notch)
    ctx.setLineCap(.round)
    ctx.setLineWidth(22)
    let notchInner = pointOnRing(90, radius - ringWidth / 2 - 4)
    let notchOuter = pointOnRing(90, radius + ringWidth / 2 + 16)
    ctx.move(to: notchInner)
    ctx.addLine(to: notchOuter)
    ctx.strokePath()

    // 4) "Now" dot riding the arc — mid-morning (~10 o'clock → 150°).
    let nowAngle: CGFloat = 150
    let nowCenter = pointOnRing(nowAngle)
    // Halo cut so the dot reads clean against the ember arc.
    set(ap.background)
    ctx.fillEllipse(in: CGRect(x: nowCenter.x - 52, y: nowCenter.y - 52, width: 104, height: 104))
    set(ap.dot)
    ctx.fillEllipse(in: CGRect(x: nowCenter.x - 36, y: nowCenter.y - 36, width: 72, height: 72))

    return ctx.makeImage()!
}

// MARK: - Output

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "CenitApp/Resources/Assets.xcassets/AppIcon.appiconset"
let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

func write(_ image: CGImage, _ name: String) {
    let url = outURL.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create \(name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name)")
}

let files: [(Appearance, String)] = [
    (.light,  "icon-light-1024.png"),
    (.dark,   "icon-dark-1024.png"),
    (.tinted, "icon-tinted-1024.png"),
]
for (ap, name) in files { write(draw(ap), name) }

let contents = """
{
  "images" : [
    {
      "filename" : "icon-light-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-dark-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-tinted-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try! contents.write(to: outURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
