import AppKit
import SwiftUI
import SunroomCore
import SunroomKit

/// Headless-ish screenshot mode used for documentation.
///
/// Screen capture permission is not required because the app renders its own
/// window into a bitmap, which also makes the screenshots deterministic in CI.
///
///     Sunroom.app/Contents/MacOS/Sunroom --snapshot docs/images --quit-after-snapshot
@MainActor
enum SnapshotMode {
    static func runIfRequested(model: AppModel, window: NSWindow?) async {
        guard let directory = model.launchOptions.snapshotDirectory, let window else { return }

        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .aqua)

        // Give SwiftUI and the canvas a frame or two to settle.
        resize(window, to: NSSize(width: 1440, height: 900))
        try? await Task.sleep(nanoseconds: 1_400_000_000)

        write(window: window, to: base.appendingPathComponent("canvas-light.png"))
        try? await Task.sleep(nanoseconds: 300_000_000)

        model.isInspectorPresented = true
        model.selection = Set(model.document.nodes.prefix(1).map(\.id))
        try? await Task.sleep(nanoseconds: 700_000_000)
        write(window: window, to: base.appendingPathComponent("inspector.png"))
        model.isInspectorPresented = false

        model.isPalettePresented = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        write(window: window, to: base.appendingPathComponent("palette.png"))
        model.isPalettePresented = false

        model.isOnboardingPresented = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        write(window: window, to: base.appendingPathComponent("onboarding.png"))
        model.isOnboardingPresented = false

        model.selection = []
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(nanoseconds: 900_000_000)
        write(window: window, to: base.appendingPathComponent("canvas-dark.png"))

        model.isWindowLibraryPresented = true
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        if let sheet = window.attachedSheet {
            write(window: sheet, to: base.appendingPathComponent("windows.png"))
        }
        model.isWindowLibraryPresented = false
        NSApp.appearance = nil
        try? await Task.sleep(nanoseconds: 700_000_000)

        // Search and inline editing, at light appearance.
        model.isSearchFocused = true
        model.searchQuery = "win"
        try? await Task.sleep(nanoseconds: 900_000_000)
        write(window: window, to: base.appendingPathComponent("search.png"))
        model.searchQuery = ""
        model.isSearchFocused = false

        if let note = model.document.nodes.first(where: { $0.kind == .note }) {
            model.editingNodeID = note.id
            try? await Task.sleep(nanoseconds: 900_000_000)
            write(window: window, to: base.appendingPathComponent("editing.png"))
            model.editingNodeID = nil
        }

        if model.launchOptions.quitsAfterSnapshot {
            try? await Task.sleep(nanoseconds: 400_000_000)
            NSApp.terminate(nil)
        }
    }

    // MARK: - Canvas mode capture

    /// Enters canvas mode, captures the actual screen (needs Screen Recording),
    /// dives into one window, captures again, then restores the desktop.
    static func captureCanvasMode(model: AppModel, directory: String) async {
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        model.toggleCanvasMode()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await captureScreen(to: base.appendingPathComponent("canvas-mode.png"), label: "canvas")

        if let first = model.canvasMode.windows.first {
            model.canvasMode.selection = first.id
            model.canvasMode.dive(into: first.id)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await captureScreen(to: base.appendingPathComponent("canvas-focused.png"), label: "focused")
            model.canvasMode.surface()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await captureScreen(to: base.appendingPathComponent("canvas-back.png"), label: "back")
        }

        model.canvasMode.exit()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await captureScreen(to: base.appendingPathComponent("canvas-restored.png"), label: "restored")
    }

    private static func captureScreen(to url: URL, label: String) async {
        let capture = WindowCaptureService()
        guard let image = await capture.captureFullScreen(display: nil),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("canvas shot \(label): failed (Screen Recording not granted?)")
            return
        }
        try? png.write(to: url)
        print("canvas shot \(label): \(url.path) (\(png.count / 1024) KB)")
    }

    private static func resize(_ window: NSWindow, to size: NSSize) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
    }

    private static func write(window: NSWindow, to url: URL) {
        // Capturing our own window through the window server does not require
        // Screen Recording permission (the app is capturing itself).
        if let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                print("snapshot: \(url.path) (\(data.count / 1024) KB) via window server")
                return
            }
        }

        guard let view = window.contentView else { return }
        let scale = window.backingScaleFactor
        let pixelWidth = Int(view.bounds.width * scale)
        let pixelHeight = Int(view.bounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }

        context.cgContext.scaleBy(x: scale, y: scale)
        // Layer rendering captures SwiftUI and AppKit layer trees; view
        // cacheDisplay returns blank for layer-backed content.
        if let layer = view.layer {
            layer.render(in: context.cgContext)
        } else {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            print("snapshot: \(url.path) (\(data.count / 1024) KB)")
        } catch {
            print("snapshot failed: \(error)")
        }
    }
}
