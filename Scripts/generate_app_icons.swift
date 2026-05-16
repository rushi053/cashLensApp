#!/usr/bin/env swift
//
// Generates the alternate-app-icon PNGs used by CashLens's Personalization
// system. Re-runnable: edit `iconCatalog`, run the script, drop the resulting
// PNGs into the matching `.appiconset` folders.
//
// Each icon is 1024×1024, rendered with CoreGraphics so the output is
// pixel-deterministic and matches the existing primary AppIcon's geometry
// exactly (same disc radius, same coin rim, same stroke widths).
//
// Usage:  swift Scripts/generate_app_icons.swift <output-dir>
//

import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers
import AppKit

// MARK: - Catalog

struct IconSpec {
    /// Used only for the output filename — matches the asset catalog folder.
    let id: String
    /// Background fill (full canvas).
    let bgHex: String
    /// "Coin" colour. The coin rim, dollar sign and arc highlight are all
    /// drawn in `bgHex` over a `coinHex` filled disc.
    let coinHex: String
}

let cream = "#F0E8D8"
let darkInk = "#1B1D22"
let pureWhite = "#FFFFFF"

let iconCatalog: [IconSpec] = [
    IconSpec(id: "AppIcon-Ocean",     bgHex: "#3D8BF5", coinHex: cream),
    IconSpec(id: "AppIcon-Forest",    bgHex: "#2FA060", coinHex: cream),
    IconSpec(id: "AppIcon-Sunset",    bgHex: "#EE6B2D", coinHex: cream),
    IconSpec(id: "AppIcon-Berry",     bgHex: "#D8417A", coinHex: cream),
    IconSpec(id: "AppIcon-Graphite",  bgHex: "#4D5563", coinHex: cream),
    IconSpec(id: "AppIcon-MonoLight", bgHex: pureWhite, coinHex: darkInk),
    IconSpec(id: "AppIcon-MonoDark",  bgHex: darkInk,   coinHex: pureWhite),
]

// MARK: - Geometry (matches the primary icon)

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)
let outerDiscRadius: CGFloat = 410     // outer cream disc
let innerRingRadius: CGFloat = 350     // theme-coloured carved-out rim
let innerRingWidth: CGFloat = 26
let dollarFontSize: CGFloat = 460
let arcRadius: CGFloat = 270           // upper-right glint arc
let arcLineWidth: CGFloat = 32

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

/// Picks a heavy/black weight from the system's rounded family. Falls back to
/// SF Pro / Helvetica if rounded isn't available on this machine.
func pickDollarFont(size: CGFloat) -> CTFont {
    let candidates = [
        "SFProRounded-Black",
        "SFProRounded-Heavy",
        "SFProDisplay-Black",
        "SFProDisplay-Heavy",
        "Helvetica-Bold",
    ]
    for name in candidates {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let postName = CTFontCopyPostScriptName(font) as String
        if postName.lowercased().contains(name.lowercased().split(separator: "-").first!.lowercased()) {
            return font
        }
    }
    return CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
}

func renderIcon(_ spec: IconSpec, to outURL: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        FileHandle.standardError.write(Data("✗ Could not create CGContext for \(spec.id)\n".utf8))
        return
    }

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

    // 3. Inner background-coloured ring (creates the coin rim look)
    ctx.setStrokeColor(bg)
    ctx.setLineWidth(innerRingWidth)
    ctx.strokeEllipse(in: CGRect(
        x: center.x - innerRingRadius,
        y: center.y - innerRingRadius,
        width:  innerRingRadius * 2,
        height: innerRingRadius * 2
    ))

    // 4. "$" glyph in background colour, centred via CTLine bounds
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

    ctx.saveGState()
    ctx.textPosition = CGPoint(
        x: center.x - bounds.midX,
        y: center.y - bounds.midY
    )
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // 5. Glint arc — upper-right inside the inner area
    ctx.setStrokeColor(bg)
    ctx.setLineWidth(arcLineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addArc(
        center: center,
        radius: arcRadius,
        startAngle: CGFloat.pi * 0.10,    // ~ +18° (upper right)
        endAngle:   CGFloat.pi * 0.42,    // ~ +76°
        clockwise:  false
    )
    ctx.strokePath()

    // 6. Write PNG
    guard let cgImage = ctx.makeImage() else {
        FileHandle.standardError.write(Data("✗ makeImage failed for \(spec.id)\n".utf8))
        return
    }
    guard let dest = CGImageDestinationCreateWithURL(
        outURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        FileHandle.standardError.write(Data("✗ destination create failed for \(spec.id)\n".utf8))
        return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    if !CGImageDestinationFinalize(dest) {
        FileHandle.standardError.write(Data("✗ finalize failed for \(spec.id)\n".utf8))
        return
    }
    print("✓ \(spec.id) → \(outURL.path)")
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: swift Scripts/generate_app_icons.swift <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for spec in iconCatalog {
    let url = outDir.appendingPathComponent("\(spec.id).png")
    renderIcon(spec, to: url)
}

print("Done. Wrote \(iconCatalog.count) icon(s) to \(outDir.path)")
