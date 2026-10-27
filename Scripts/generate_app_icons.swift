#!/usr/bin/env swift
//
// Generates the alternate-app-icon PNGs used by CashLens's Personalization
// system. Re-runnable: edit `iconCatalog`, run the script — it writes into
// both the `.appiconset` folders AND the parallel `IconPreview-*.imageset`
// folders (iOS 18+ can't load appiconsets via UIImage/Image for in-app
// previews — those imagesets are required).
//
// Geometry is traced from the handcrafted primary `AppIcon` (Mauve):
// smaller cream disc, thinner coin rim, lighter dollar, thinner glint.
// Colours are the exact `primaryLightHex` swatches from `AppTheme` so
// theme ↔ icon pairing in Appearance Studio stays truthful.
//
// Usage:
//   swift Scripts/generate_app_icons.swift
//   swift Scripts/generate_app_icons.swift <assets-dir>
//

import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers
import AppKit

// MARK: - Catalog

struct IconSpec {
    /// Appiconset id / PNG stem (e.g. "AppIcon-Ocean").
    let id: String
    /// Matching `IconPreview-*` imageset name.
    let previewId: String
    /// Background + glyph colour — must equal the theme's `primaryLightHex`.
    let bgHex: String
    /// Coin fill.
    let coinHex: String
}

/// Soft cream sampled from the handcrafted primary AppIcon (#FAF7EF),
/// not the warmer #F0E8D8 the v1 generator used (that made alternates
/// look heavier / muddier next to Mauve).
let cream = "#FAF7EF"       // sampled from primary AppIcon
let ink = "#2C3038"         // Ink theme `primaryLightHex`
let monoBlack = "#1B1D22"   // deeper black for Mono Dark (distinct from Ink)
let pureWhite = "#FFFFFF"

// bgHex values are copied verbatim from `AppTheme.*.primaryLightHex`
// (except Mono Dark, which is a true-black companion, not a theme pair).
// Keep them in sync — Appearance Studio's "Complete the look" pairing
// depends on the icon reading as the same swatch as the theme chip.
let iconCatalog: [IconSpec] = [
    IconSpec(id: "AppIcon-Ocean",     previewId: "IconPreview-Ocean",     bgHex: "#2E7CF6", coinHex: cream),
    IconSpec(id: "AppIcon-Forest",    previewId: "IconPreview-Forest",    bgHex: "#23A55E", coinHex: cream),
    IconSpec(id: "AppIcon-Sunset",    previewId: "IconPreview-Sunset",    bgHex: "#F4693B", coinHex: cream),
    IconSpec(id: "AppIcon-Berry",     previewId: "IconPreview-Berry",     bgHex: "#D8417A", coinHex: cream),
    // Ink theme (persisted id "graphite") — near-black + cream coin.
    IconSpec(id: "AppIcon-Graphite",  previewId: "IconPreview-Graphite",  bgHex: ink,       coinHex: cream),
    IconSpec(id: "AppIcon-MonoLight", previewId: "IconPreview-MonoLight", bgHex: pureWhite, coinHex: ink),
    // Distinct from Ink: deeper black ground, pure-white coin.
    IconSpec(id: "AppIcon-MonoDark",  previewId: "IconPreview-MonoDark",  bgHex: monoBlack, coinHex: pureWhite),
]

// MARK: - Geometry (traced from primary AppIcon @ 1024)
//
// Primary disc outer edge sits ~x=170 → radius ≈ 342. The generated
// family previously used 410, which packed a Black-weight dollar into
// a larger disc and read as "thick / off" next to Mauve. These numbers
// restore the original proportions: more cream rim, thinner ring,
// lighter glyph, thinner glint.

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)
let outerDiscRadius: CGFloat = 348
let innerRingRadius: CGFloat = 262      // stroke centred here
let innerRingWidth: CGFloat = 18
let dollarFontSize: CGFloat = 385
let arcRadius: CGFloat = 208
let arcLineWidth: CGFloat = 20
let arcStart: CGFloat = .pi * 0.12
let arcEnd: CGFloat = .pi * 0.40

// MARK: - Helpers

func parseHex(_ s: String) -> CGColor {
    var hex = s
    if hex.hasPrefix("#") { hex.removeFirst() }
    let v = UInt32(hex, radix: 16) ?? 0
    let r = CGFloat((v >> 16) & 0xFF) / 255
    let g = CGFloat((v >> 8)  & 0xFF) / 255
    let b = CGFloat( v        & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

/// Prefer rounded Bold/Semibold — Black/Heavy was the "thick" look.
func pickDollarFont(size: CGFloat) -> CTFont {
    let candidates = [
        "SFProRounded-Bold",
        "SFProRounded-Semibold",
        "SFProDisplay-Bold",
        "Helvetica-Bold",
    ]
    for name in candidates {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let postName = (CTFontCopyPostScriptName(font) as String).lowercased()
        let familyHint = name.lowercased().split(separator: "-").first.map(String.init) ?? ""
        if postName.contains(familyHint) || postName.contains("bold") || postName.contains("semibold") {
            return font
        }
    }
    return CTFontCreateUIFontForLanguage(.system, size, nil)
        ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
}

func writePNG(_ cgImage: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(dest, cgImage, nil)
    return CGImageDestinationFinalize(dest)
}

func renderIcon(_ spec: IconSpec) -> CGImage? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // Default CG bitmap space: origin bottom-left, +Y up. Matches the
    // primary AppIcon's coordinate assumptions for the glint arc.
    let bg = parseHex(spec.bgHex)
    let coin = parseHex(spec.coinHex)

    // 1. Background
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    // 2. Outer cream disc
    ctx.setFillColor(coin)
    ctx.fillEllipse(in: CGRect(
        x: center.x - outerDiscRadius,
        y: center.y - outerDiscRadius,
        width:  outerDiscRadius * 2,
        height: outerDiscRadius * 2
    ))

    // 3. Thin coin rim (theme colour)
    ctx.setStrokeColor(bg)
    ctx.setLineWidth(innerRingWidth)
    ctx.setLineCap(.round)
    ctx.strokeEllipse(in: CGRect(
        x: center.x - innerRingRadius,
        y: center.y - innerRingRadius,
        width:  innerRingRadius * 2,
        height: innerRingRadius * 2
    ))

    // 4. "$" glyph — Bold rounded, not Black (the thick look).
    let font = pickDollarFont(size: dollarFontSize)
    let attrString = CFAttributedStringCreate(
        nil,
        "$" as CFString,
        [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: bg,
        ] as CFDictionary
    )!
    let line = CTLineCreateWithAttributedString(attrString)
    let bounds = CTLineGetImageBounds(line, ctx)
    ctx.textPosition = CGPoint(
        x: center.x - bounds.midX,
        y: center.y - bounds.midY
    )
    CTLineDraw(line, ctx)

    // 5. Glint arc — upper-right, thinner than v1
    ctx.setStrokeColor(bg)
    ctx.setLineWidth(arcLineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addArc(
        center: center,
        radius: arcRadius,
        startAngle: arcStart,
        endAngle:   arcEnd,
        clockwise:  false
    )
    ctx.strokePath()

    return ctx.makeImage()
}

func ensureImagesetContents(at dir: URL, filename: String) {
    let json = """
    {
      "images" : [
        {
          "filename" : "\(filename)",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try? json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// MARK: - Main

let args = CommandLine.arguments
let assetsDir: URL = {
    if args.count >= 2 {
        return URL(fileURLWithPath: args[1])
    }
    // Default: repo Assets.xcassets next to Scripts/
    let scriptDir = URL(fileURLWithPath: args[0]).deletingLastPathComponent()
    return scriptDir
        .deletingLastPathComponent()
        .appendingPathComponent("CashLens/Assets.xcassets")
}()

guard FileManager.default.fileExists(atPath: assetsDir.path) else {
    fputs("Assets directory not found: \(assetsDir.path)\n", stderr)
    exit(1)
}

var wrote = 0
for spec in iconCatalog {
    guard let image = renderIcon(spec) else {
        fputs("✗ render failed for \(spec.id)\n", stderr)
        continue
    }

    let appiconset = assetsDir.appendingPathComponent("\(spec.id).appiconset")
    try? FileManager.default.createDirectory(at: appiconset, withIntermediateDirectories: true)
    let appPNG = appiconset.appendingPathComponent("\(spec.id).png")
    guard writePNG(image, to: appPNG) else {
        fputs("✗ write failed \(appPNG.path)\n", stderr)
        continue
    }

    let previewSet = assetsDir.appendingPathComponent("\(spec.previewId).imageset")
    try? FileManager.default.createDirectory(at: previewSet, withIntermediateDirectories: true)
    let previewPNG = previewSet.appendingPathComponent("\(spec.previewId).png")
    guard writePNG(image, to: previewPNG) else {
        fputs("✗ write failed \(previewPNG.path)\n", stderr)
        continue
    }
    ensureImagesetContents(at: previewSet, filename: "\(spec.previewId).png")

    print("✓ \(spec.id)  bg=\(spec.bgHex)")
    wrote += 1
}

print("Done. Wrote \(wrote)/\(iconCatalog.count) icon(s) into \(assetsDir.path)")
