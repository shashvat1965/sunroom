#!/usr/bin/env swift
//
//  make-icon.swift
//  Sunroom — infinite-canvas window manager for macOS
//
//  Draws the app icon (1024x1024) with Core Graphics, writes
//  Resources/AppIcon.png, then uses `sips` + `iconutil` to build
//  Resources/AppIcon.icns.
//
//  Usage:   swift Scripts/make-icon.swift
//  Idempotent — re-running overwrites the generated artifacts.
//
//  Visual: a warm sun low in the upper third, glowing behind a tilted pane of
//  Liquid Glass, on a deep indigo→violet canvas dusted with an infinite dot
//  grid. One translucent card floats on the pane. No text, no glyphs.
//

import Foundation
import CoreGraphics
import CoreText
import ImageIO

// MARK: - Paths

let scriptPath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
var repoRoot = scriptPath.deletingLastPathComponent().deletingLastPathComponent()
if !FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path) {
    repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

let resourcesDir = repoRoot.appendingPathComponent("Resources", isDirectory: true)
let pngURL = resourcesDir.appendingPathComponent("AppIcon.png")
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let iconsetURL = resourcesDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)

// MARK: - Small helpers

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { $0.1 } as CFArray,
        locations: stops.map { $0.0 }
    )
}

func linear(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)], from: CGPoint, to: CGPoint) {
    guard let g = gradient(stops) else { return }
    ctx.drawLinearGradient(
        g, start: from, end: to,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func radial(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)],
            center: CGPoint, startRadius: CGFloat, endRadius: CGFloat,
            startCenter: CGPoint? = nil) {
    guard let g = gradient(stops) else { return }
    ctx.drawRadialGradient(
        g, startCenter: startCenter ?? center, startRadius: startRadius,
        endCenter: center, endRadius: endRadius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

/// Continuous-curvature squircle (superellipse) — the macOS icon silhouette.
func squircle(in rect: CGRect, exponent n: CGFloat = 5.0, samples: Int = 1400) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let e = 2 / n
    for i in 0..<samples {
        let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), e)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), e)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Design geometry (1024pt design space, y down)

let designSize: CGFloat = 1024

// Apple's icon grid: 824pt content box, ~185pt continuous corners.
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)

let sunCenter = CGPoint(x: 474, y: 348)
let sunRadius: CGFloat = 150

let paneSize = CGSize(width: 536, height: 400)
let paneCenter = CGPoint(x: 528, y: 626)
let paneCorner: CGFloat = 44
let paneTilt: CGFloat = -6 * .pi / 180

let cardRect = CGRect(x: -40, y: -4, width: 270, height: 160)
let cardCorner: CGFloat = 22

// MARK: - Drawing

func drawIcon(_ ctx: CGContext) {
    let squirclePath = squircle(in: iconRect)
    let paneTransform = CGAffineTransform(translationX: paneCenter.x, y: paneCenter.y)
        .rotated(by: paneTilt)
    let paneLocalRect = CGRect(
        x: -paneSize.width / 2, y: -paneSize.height / 2,
        width: paneSize.width, height: paneSize.height
    )
    let toPaneLocal = paneTransform.inverted()

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // ---- Room: deep indigo -> violet, extra stops for depth ----
    linear(
        ctx,
        [
            (0.00, hex(0x0F0E24)),
            (0.20, hex(0x1B1B3A)),
            (0.55, hex(0x221C44)),
            (0.82, hex(0x2E2454)),
            (1.00, hex(0x3B2F63)),
        ],
        from: CGPoint(x: 512, y: 90),
        to: CGPoint(x: 512, y: 950)
    )

    // Violet bloom low-right so the field isn't a flat ramp.
    radial(
        ctx,
        [(0.00, hex(0x7A6BFF, 0.22)), (0.50, hex(0x5E4FCB, 0.09)), (1.00, hex(0x5E4FCB, 0.0))],
        center: CGPoint(x: 820, y: 900), startRadius: 0, endRadius: 520
    )

    // Shadowed upper-right corner: the room is lit from the upper left.
    radial(
        ctx,
        [(0.00, hex(0x07061A, 0.30)), (0.70, hex(0x07061A, 0.08)), (1.00, hex(0x07061A, 0.0))],
        center: CGPoint(x: 930, y: 150), startRadius: 0, endRadius: 460
    )

    // Warm ambient bloom around the sun (additive, so it never goes muddy).
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    radial(
        ctx,
        [
            (0.00, hex(0xFFCE86, 0.26)),
            (0.22, hex(0xFFC172, 0.15)),
            (0.52, hex(0xFFA85A, 0.05)),
            (0.82, hex(0xFF9448, 0.01)),
            (1.00, hex(0xFF9448, 0.0)),
        ],
        center: sunCenter, startRadius: sunRadius * 0.88, endRadius: sunRadius * 1.42
    )
    radial(
        ctx,
        [
            (0.00, hex(0xFFB870, 0.040)),
            (0.55, hex(0xFFA05A, 0.014)),
            (1.00, hex(0xFFA05A, 0.0)),
        ],
        center: sunCenter, startRadius: 0, endRadius: 380
    )
    ctx.restoreGState()

    // ---- Infinite-canvas dot grid ----
    let spacing: CGFloat = 84
    let dotRadius: CGFloat = 2.1
    let gridStart = iconRect.minX + 40
    var gy = gridStart
    while gy < iconRect.maxX {
        var gx = gridStart
        while gx < iconRect.maxX {
            let dx = (gx - 512) / 430
            let dy = (gy - 512) / 430
            let dist = sqrt(dx * dx + dy * dy)
            let fade = 1 - smoothstep(0.70, 1.02, dist)
            if fade > 0.01 {
                ctx.setFillColor(hex(0xFFFFFF, 0.095 * fade))
                ctx.fillEllipse(in: CGRect(
                    x: gx - dotRadius, y: gy - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                ))
            }
            gx += spacing
        }
        gy += spacing
    }

    // ---- Sun ----
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    radial(
        ctx,
        [
            (0.00, hex(0xFFDA8C, 0.55)),
            (0.26, hex(0xFFC273, 0.28)),
            (0.58, hex(0xFFA055, 0.08)),
            (1.00, hex(0xFF9E4A, 0.0)),
        ],
        center: sunCenter, startRadius: sunRadius * 0.80, endRadius: sunRadius * 1.95
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(
        x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius,
        width: sunRadius * 2, height: sunRadius * 2
    ))
    ctx.clip()
    // Off-centre highlight so the disc reads as a sphere, not a sticker.
    radial(
        ctx,
        [
            (0.00, hex(0xFFFCE8)),
            (0.22, hex(0xFFECAC)),
            (0.50, hex(0xFFD166)),
            (0.78, hex(0xFFAE55)),
            (1.00, hex(0xFF8B3C)),
        ],
        center: sunCenter,
        startRadius: 0,
        endRadius: sunRadius * 1.38,
        startCenter: CGPoint(x: sunCenter.x - sunRadius * 0.36, y: sunCenter.y - sunRadius * 0.44)
    )
    // Limb darkening on the lower-right.
    radial(
        ctx,
        [
            (0.58, hex(0xA84D12, 0.0)),
            (0.86, hex(0xA84D12, 0.10)),
            (1.00, hex(0x93400C, 0.34)),
        ],
        center: CGPoint(x: sunCenter.x + sunRadius * 0.20, y: sunCenter.y + sunRadius * 0.24),
        startRadius: 0, endRadius: sunRadius * 1.03
    )
    ctx.restoreGState()

    // ---- Soft contact shadow beneath the pane ----
    ctx.saveGState()
    ctx.translateBy(x: paneCenter.x, y: paneCenter.y)
    ctx.rotate(by: paneTilt)
    ctx.scaleBy(x: 1.0, y: 0.24)
    radial(
        ctx,
        [
            (0.00, hex(0x050312, 0.60)),
            (0.55, hex(0x050312, 0.30)),
            (0.82, hex(0x050312, 0.08)),
            (1.00, hex(0x050312, 0.0)),
        ],
        center: CGPoint(x: 0, y: 250),
        startRadius: 0,
        endRadius: 540
    )
    ctx.restoreGState()

    // ---- Glass pane ----
    ctx.saveGState()
    ctx.translateBy(x: paneCenter.x, y: paneCenter.y)
    ctx.rotate(by: paneTilt)

    let paneRound = rounded(paneLocalRect, paneCorner)
    let sunInPane = sunCenter.applying(toPaneLocal)

    ctx.saveGState()
    ctx.addPath(paneRound)
    ctx.clip()

    // 1 — Body: ~18% white, brightest at the upper left, thinning toward the
    //     shadow side so the room still shows through the glass.
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.320)),
            (0.30, hex(0xFFFFFF, 0.195)),
            (0.60, hex(0xEAF0FF, 0.115)),
            (0.84, hex(0xE2EAFF, 0.095)),
            (1.00, hex(0xC9D8FF, 0.105)),
        ],
        from: CGPoint(x: paneLocalRect.minX, y: paneLocalRect.minY),
        to: CGPoint(x: paneLocalRect.midX, y: paneLocalRect.maxY)
    )

    // 2 — Colour bled in from the room.
    linear(
        ctx,
        [
            (0.00, hex(0x7A6BFF, 0.055)),
            (0.60, hex(0x7A6BFF, 0.012)),
            (1.00, hex(0x7A6BFF, 0.0)),
        ],
        from: CGPoint(x: paneLocalRect.minX - 30, y: paneLocalRect.maxY + 30),
        to: CGPoint(x: paneLocalRect.maxX, y: paneLocalRect.minY)
    )

    // 3 — Sunlight diffusing through the glass.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    radial(
        ctx,
        [
            (0.00, hex(0xFFD08A, 0.140)),
            (0.45, hex(0xFFB063, 0.045)),
            (1.00, hex(0xFF9E4A, 0.0)),
        ],
        center: CGPoint(x: sunInPane.x, y: sunInPane.y + 40),
        startRadius: 0, endRadius: 290
    )
    ctx.restoreGState()

    // 4 — Reflected sky light: a long soft streak across the upper glass.
    //     Elliptical falloff keeps every edge feathered.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.translateBy(x: paneLocalRect.midX - 10, y: paneLocalRect.minY + 62)
    ctx.rotate(by: -0.05)
    ctx.scaleBy(x: 1.0, y: 0.20)
    radial(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.170)),
            (0.45, hex(0xFFF9EF, 0.080)),
            (0.78, hex(0xFFFFFF, 0.015)),
            (1.00, hex(0xFFFFFF, 0.0)),
        ],
        center: .zero, startRadius: 0, endRadius: 420
    )
    ctx.restoreGState()

    // Hotter glint where the streak is thickest.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.translateBy(x: paneLocalRect.minX + 150, y: paneLocalRect.minY + 62)
    ctx.rotate(by: -0.12)
    ctx.scaleBy(x: 1.0, y: 0.24)
    radial(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.230)),
            (0.50, hex(0xFFF6E4, 0.070)),
            (1.00, hex(0xFFFFFF, 0.0)),
        ],
        center: .zero, startRadius: 0, endRadius: 165
    )
    ctx.restoreGState()

    // 5 — Light pooling on the bottom inner edge.
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.0)),
            (0.80, hex(0xFFFFFF, 0.020)),
            (0.95, hex(0xFFFFFF, 0.085)),
            (1.00, hex(0xFFFFFF, 0.220)),
        ],
        from: CGPoint(x: paneLocalRect.midX, y: paneLocalRect.midY + 46),
        to: CGPoint(x: paneLocalRect.midX, y: paneLocalRect.maxY)
    )

    // 6 — Glass thickness: a dark inner rim on the shadow side.
    let thickRect = paneLocalRect.insetBy(dx: 3, dy: 3)
    let thickPath = rounded(thickRect, paneCorner - 3).copy(
        strokingWithWidth: 13, lineCap: .round, lineJoin: .round, miterLimit: 4
    )
    ctx.saveGState()
    ctx.addPath(thickPath)
    ctx.clip()
    linear(
        ctx,
        [
            (0.35, hex(0x1A1038, 0.0)),
            (0.75, hex(0x1A1038, 0.09)),
            (1.00, hex(0x1A1038, 0.15)),
        ],
        from: CGPoint(x: paneLocalRect.minX, y: paneLocalRect.minY),
        to: CGPoint(x: paneLocalRect.maxX, y: paneLocalRect.maxY)
    )
    ctx.restoreGState()
    ctx.restoreGState()

    // Rim: crisp, near-white at the top-left, cooler around the bottom.
    let borderPath = paneRound.copy(
        strokingWithWidth: 1.9, lineCap: .round, lineJoin: .round, miterLimit: 4
    )
    ctx.saveGState()
    ctx.addPath(borderPath)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.96)),
            (0.30, hex(0xFFFFFF, 0.60)),
            (0.62, hex(0xFFFFFF, 0.32)),
            (0.86, hex(0xFFFFFF, 0.40)),
            (1.00, hex(0xFFFFFF, 0.50)),
        ],
        from: CGPoint(x: paneLocalRect.minX, y: paneLocalRect.minY),
        to: CGPoint(x: paneLocalRect.maxX, y: paneLocalRect.maxY)
    )
    ctx.restoreGState()

    // Soft wide specular riding the top-left edge.
    let sweepPath = paneRound.copy(
        strokingWithWidth: 12, lineCap: .round, lineJoin: .round, miterLimit: 4
    )
    ctx.saveGState()
    ctx.addPath(sweepPath)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.55)),
            (0.14, hex(0xFFF6E0, 0.36)),
            (0.34, hex(0xFFFFFF, 0.06)),
            (1.00, hex(0xFFFFFF, 0.0)),
        ],
        from: CGPoint(x: paneLocalRect.minX + 10, y: paneLocalRect.minY + 110),
        to: CGPoint(x: paneLocalRect.minX + 300, y: paneLocalRect.minY + 30)
    )
    ctx.restoreGState()

    // Crisp hot specular line hugging the very top-left edge.
    let hotPath = paneRound.copy(
        strokingWithWidth: 3.2, lineCap: .round, lineJoin: .round, miterLimit: 4
    )
    ctx.saveGState()
    ctx.addPath(hotPath)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.98)),
            (0.16, hex(0xFFFFFF, 0.62)),
            (0.40, hex(0xFFFFFF, 0.0)),
            (1.00, hex(0xFFFFFF, 0.0)),
        ],
        from: CGPoint(x: paneLocalRect.minX + 4, y: paneLocalRect.minY + 120),
        to: CGPoint(x: paneLocalRect.minX + 250, y: paneLocalRect.minY + 6)
    )
    ctx.restoreGState()

    // Warm kiss where the sun passes behind the top edge of the glass.
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.addPath(hotPath)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFD79A, 0.0)),
            (0.42, hex(0xFFD79A, 0.16)),
            (0.62, hex(0xFFE7C4, 0.24)),
            (1.00, hex(0xFFD79A, 0.0)),
        ],
        from: CGPoint(x: sunInPane.x - 210, y: paneLocalRect.minY + 8),
        to: CGPoint(x: sunInPane.x + 200, y: paneLocalRect.minY + 4)
    )
    ctx.restoreGState()

    // ---- The card that lives on the canvas ----
    // A hair of extra rotation keeps it from looking like a picture in a frame.
    ctx.saveGState()
    ctx.translateBy(x: cardRect.midX, y: cardRect.midY)
    ctx.rotate(by: 0.0)
    ctx.translateBy(x: -cardRect.midX, y: -cardRect.midY)

    let cardPath = rounded(cardRect, cardCorner)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 20), blur: 30, color: hex(0x0A0620, 0.55))
    ctx.setFillColor(hex(0x120E2A, 0.30))
    ctx.addPath(cardPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFFCF2, 0.395)),
            (0.42, hex(0xF3F1FF, 0.315)),
            (1.00, hex(0xE2E8FF, 0.265)),
        ],
        from: CGPoint(x: cardRect.minX, y: cardRect.minY),
        to: CGPoint(x: cardRect.midX, y: cardRect.maxY)
    )
    // Sunlit corner.
    radial(
        ctx,
        [
            (0.00, hex(0xFFE3A8, 0.170)),
            (0.60, hex(0xFFD79A, 0.040)),
            (1.00, hex(0xFFD79A, 0.0)),
        ],
        center: CGPoint(x: cardRect.minX + 40, y: cardRect.minY + 36),
        startRadius: 0, endRadius: 150
    )
    // Top-edge catch light.
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.26)),
            (0.26, hex(0xFFFFFF, 0.0)),
            (1.00, hex(0xFFFFFF, 0.0)),
        ],
        from: CGPoint(x: cardRect.midX, y: cardRect.minY),
        to: CGPoint(x: cardRect.midX, y: cardRect.minY + 54)
    )
    // Thickness at the bottom of the card.
    linear(
        ctx,
        [
            (0.62, hex(0x1A1038, 0.0)),
            (1.00, hex(0x1A1038, 0.055)),
        ],
        from: CGPoint(x: cardRect.midX, y: cardRect.midY),
        to: CGPoint(x: cardRect.midX, y: cardRect.maxY)
    )
    ctx.restoreGState()

    let cardBorder = cardPath.copy(
        strokingWithWidth: 1.3, lineCap: .round, lineJoin: .round, miterLimit: 4
    )
    ctx.saveGState()
    ctx.addPath(cardBorder)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.85)),
            (0.50, hex(0xFFFFFF, 0.34)),
            (1.00, hex(0xFFFFFF, 0.46)),
        ],
        from: CGPoint(x: cardRect.minX, y: cardRect.minY),
        to: CGPoint(x: cardRect.maxX, y: cardRect.maxY)
    )
    ctx.restoreGState()

    ctx.restoreGState() // card rotation
    ctx.restoreGState() // pane transform

    // ---- Icon edge treatment (inside the squircle) ----
    // Vignette.
    radial(
        ctx,
        [
            (0.00, hex(0x0A0718, 0.0)),
            (0.62, hex(0x0A0718, 0.0)),
            (0.88, hex(0x0A0718, 0.10)),
            (1.00, hex(0x06030E, 0.30)),
        ],
        center: CGPoint(x: 512, y: 468), startRadius: 0, endRadius: 730
    )

    // Baked inner glow: soft light from above clinging to the contour.
    let rimPasses: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (6, 34, 0.055, 0.015),
        (10, 20, 0.065, 0.018),
        (14, 9, 0.080, 0.025),
    ]
    for (inset, width, topAlpha, bottomAlpha) in rimPasses {
        let p = squircle(in: iconRect.insetBy(dx: inset, dy: inset))
        let stroked = p.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
        ctx.saveGState()
        ctx.addPath(stroked)
        ctx.clip()
        linear(
            ctx,
            [
                (0.00, hex(0xFFFFFF, topAlpha)),
                (0.42, hex(0xFFFFFF, topAlpha * 0.35)),
                (1.00, hex(0xFFFFFF, bottomAlpha)),
            ],
            from: CGPoint(x: 512, y: iconRect.minY),
            to: CGPoint(x: 512, y: iconRect.maxY)
        )
        ctx.restoreGState()
    }

    // Crisp 1px inner light stroke.
    let innerLine = squircle(in: iconRect.insetBy(dx: 2.6, dy: 2.6)).copy(
        strokingWithWidth: 1.3, lineCap: .round, lineJoin: .round, miterLimit: 4
    )
    ctx.saveGState()
    ctx.addPath(innerLine)
    ctx.clip()
    linear(
        ctx,
        [
            (0.00, hex(0xFFFFFF, 0.42)),
            (0.35, hex(0xFFFFFF, 0.20)),
            (0.75, hex(0xFFFFFF, 0.09)),
            (1.00, hex(0xFFFFFF, 0.17)),
        ],
        from: CGPoint(x: 512, y: iconRect.minY),
        to: CGPoint(x: 512, y: iconRect.maxY)
    )
    ctx.restoreGState()

    // Dark outer definition line so the icon separates from light backgrounds.
    ctx.setStrokeColor(hex(0x000000, 0.20))
    ctx.setLineWidth(1.2)
    ctx.addPath(squircle(in: iconRect.insetBy(dx: 0.6, dy: 0.6)))
    ctx.strokePath()

    ctx.restoreGState()
}

// MARK: - Render (2x supersampled, then downsampled to 1024)

let scale: CGFloat = 2
let pixelSize = Int(designSize * scale)
guard let ctx = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("error: could not create bitmap context\n".utf8))
    exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

ctx.saveGState()
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: designSize)
ctx.scaleBy(x: 1, y: -1)
drawIcon(ctx)
ctx.restoreGState()

guard let bigImage = ctx.makeImage() else {
    FileHandle.standardError.write(Data("error: could not snapshot context\n".utf8))
    exit(1)
}

let finalSize = Int(designSize)
guard let outCtx = CGContext(
    data: nil,
    width: finalSize,
    height: finalSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("error: could not create output context\n".utf8))
    exit(1)
}
outCtx.interpolationQuality = .high
outCtx.clear(CGRect(x: 0, y: 0, width: finalSize, height: finalSize))
outCtx.draw(bigImage, in: CGRect(x: 0, y: 0, width: finalSize, height: finalSize))

guard let iconImage = outCtx.makeImage() else {
    FileHandle.standardError.write(Data("error: could not downsample icon\n".utf8))
    exit(1)
}

// MARK: - Write PNG

let fm = FileManager.default
do {
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    try? fm.removeItem(at: iconsetURL)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    pngURL as CFURL, "public.png" as CFString, 1, nil
) else {
    FileHandle.standardError.write(Data("error: could not create PNG destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, iconImage, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: could not write PNG\n".utf8))
    exit(1)
}

// MARK: - Iconset + ICNS

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let errPipe = Pipe()
    process.standardError = errPipe
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""
        throw NSError(
            domain: "make-icon", code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(tool) failed: \(message)"]
        )
    }
}

let iconsetEntries: [(name: String, pixels: Int)] = [
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

do {
    try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    for entry in iconsetEntries {
        let out = iconsetURL.appendingPathComponent(entry.name)
        try run("/usr/bin/sips", [
            "-z", "\(entry.pixels)", "\(entry.pixels)",
            pngURL.path, "--out", out.path,
        ])
    }
    try run("/usr/bin/iconutil", [
        "-c", "icns", iconsetURL.path, "-o", icnsURL.path,
    ])
    try fm.removeItem(at: iconsetURL)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

// MARK: - Summary

func describe(_ url: URL) -> String {
    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? NSNumber else { return "missing" }
    let bytes = size.intValue
    let human = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    return "\(bytes) bytes (\(human))"
}

print("Sunroom icon written:")
print("  \(pngURL.path)  —  \(describe(pngURL))")
print("  \(icnsURL.path) —  \(describe(icnsURL))")
print("  1024x1024 sRGB, \(iconsetEntries.count) iconset sizes via sips, packed with iconutil")
