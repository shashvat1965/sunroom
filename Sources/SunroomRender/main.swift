#!/usr/bin/env swift
import Foundation
import AppKit
import SunroomCore
import SunroomKit

// Renders canvases to PNG without launching the app or needing screen-capture
// permission. Used for the README screenshots, for visual review in CI, and as
// a fast way to iterate on the canvas look.

@MainActor
func render(document: CanvasDocument, to path: String, scale: CGFloat = 2, padding: Double = 96, dark: Bool = false) -> Bool {
    let contentBounds = (document.bounds ?? CanvasRect(x: 0, y: 0, width: 1200, height: 800)).insetBy(-padding)
    let width = contentBounds.width
    let height = contentBounds.height
    guard width > 1, height > 1 else { return false }

    let camera = CanvasTransform(
        translation: CanvasPoint(x: -contentBounds.minX * Double(scale), y: -contentBounds.minY * Double(scale)),
        zoom: Double(scale)
    )
    let pixelSize = NSSize(width: width * scale, height: height * scale)

    let options = CanvasRenderer.Options(
        isDark: dark,
        selection: [],
        snapshots: [:],
        levelOfDetail: .full,
        gridStyle: document.gridStyle,
        showGrid: true,
        guides: [],
        marquee: nil,
        editingNodeID: nil,
        dimmedNodeIDs: [],
        showSelectionChrome: false
    )

    let image = NSImage(size: pixelSize, flipped: true) { rect in
        CanvasRenderer().draw(
            document: document,
            camera: camera,
            in: rect.size,
            options: options
        )
        return true
    }

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return false
    }
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(png.count / 1024) KB)")
        return true
    } catch {
        print("failed to write \(path): \(error)")
        return false
    }
}

@MainActor
func main() {
    _ = NSApplication.shared
    let arguments = CommandLine.arguments
    var outputDirectory = "docs/images"
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--out":
            index += 1
            if index < arguments.count { outputDirectory = arguments[index] }
        default:
            break
        }
        index += 1
    }

    let canvasMode = SampleCanvas.canvasModeIllustration()
    _ = render(document: canvasMode, to: "\(outputDirectory)/canvas-mode.png", scale: 2, padding: 120, dark: true)

    var welcome = SampleCanvas.welcome()
    welcome.transform = .identity
    _ = render(document: welcome, to: "\(outputDirectory)/hero.png", scale: 2, padding: 120, dark: false)
    _ = render(document: welcome, to: "\(outputDirectory)/hero-dark.png", scale: 2, padding: 120, dark: true)

    var stress = SampleCanvas.stressTest(nodeCount: 120)
    stress.background = .midnight
    _ = render(document: stress, to: "\(outputDirectory)/stress.png", scale: 1, padding: 80, dark: true)

    var dawn = SampleCanvas.welcome()
    dawn.background = .dawn
    dawn.name = "Dawn"
    _ = render(document: dawn, to: "\(outputDirectory)/theme-dawn.png", scale: 2, padding: 110, dark: true)

    var paper = SampleCanvas.welcome()
    paper.background = .paper
    paper.name = "Paper"
    _ = render(document: paper, to: "\(outputDirectory)/theme-paper.png", scale: 2, padding: 110, dark: false)
}

MainActor.assumeIsolated {
    main()
}
