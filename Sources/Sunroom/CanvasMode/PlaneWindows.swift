import AppKit
import SunroomCore
import SunroomKit

// MARK: - Background

/// The canvas surface itself, drawn behind every app window.
///
/// It sits one level above the wallpaper and below normal windows, so real
/// windows composite on top of it exactly as if the desktop had become a sheet
/// of paper.
final class PlaneBackgroundWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = PlaneBackgroundView(frame: NSRect(origin: .zero, size: screen.frame.size))
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView?.needsDisplay = true
    }
}

final class PlaneBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        let size = bounds.size

        // Night-sky gradient, warmed from the top right like the app.
        NSColor(srgbRed: 0.055, green: 0.06, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        if let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.12, green: 0.10, blue: 0.18, alpha: 1),
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        ]) {
            gradient.draw(in: bounds, angle: -70)
        }
        if let bloom = NSGradient(colorsAndLocations:
            (NSColor(srgbRed: 1.0, green: 0.62, blue: 0.30, alpha: 0.20), 0.0),
            (NSColor(srgbRed: 1.0, green: 0.50, blue: 0.25, alpha: 0.0), 1.0)
        ) {
            let center = CGPoint(x: size.width * 0.86, y: -size.height * 0.1)
            bloom.draw(
                fromCenter: center,
                radius: 0,
                toCenter: center,
                radius: max(size.width, size.height) * 0.9,
                options: [.drawsAfterEndingLocation]
            )
        }

        // Dot grid keeps the sense of a plane.
        NSColor(white: 1, alpha: 0.075).setFill()
        let spacing: CGFloat = 44
        var y: CGFloat = 12
        while y < size.height {
            var x: CGFloat = 12
            while x < size.width {
                NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 2, height: 2)).fill()
                x += spacing
            }
            y += spacing
        }

        // Faint vignette so windows read as objects on the surface.
        if let vignette = NSGradient(colorsAndLocations:
            (NSColor.black.withAlphaComponent(0.0), 0.55),
            (NSColor.black.withAlphaComponent(0.34), 1.0)
        ) {
            vignette.draw(in: bounds, relativeCenterPosition: .zero)
        }

        context.flushGraphics()
    }
}

// MARK: - Overlay

/// Transparent, full-screen, above every window: it owns the pointer and the
/// trackpad while canvas mode is on, and draws the selection chrome.
final class PlaneOverlayWindow: NSWindow {
    private weak var controller: CanvasModeController?

    init(controller: CanvasModeController) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        self.controller = controller
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = PlaneOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: controller)
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func setScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        if let view = contentView as? PlaneOverlayView {
            view.frame = NSRect(origin: .zero, size: screen.frame.size)
            view.controller = controller
            view.needsDisplay = true
        }
    }
}

final class PlaneOverlayView: NSView {
    weak var controller: CanvasModeController?
    private var trackingAreaRef: NSTrackingArea?

    init(frame: NSRect, controller: CanvasModeController) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }
        let camera = controller.camera
        let selection = controller.selection
        let accent = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.18, alpha: 1)

        // Selection ring and labels for every window.
        for item in controller.windows {
            let rect = camera.screenRect(fromCanvas: item.planeFrame).cgRect
            let isSelected = item.id == selection
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 12, yRadius: 12)
            if isSelected {
                accent.setStroke()
                path.lineWidth = 2.5
                path.stroke()
                accent.withAlphaComponent(0.10).setFill()
                path.fill()
            } else {
                NSColor.white.withAlphaComponent(0.10).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            if controller.showLabels, rect.height > 40, rect.width > 120 {
                let label = item.displayLabel
                let app = item.appName
                let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                let appFont = NSFont.systemFont(ofSize: 10, weight: .regular)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: isSelected ? NSColor.white : NSColor.white.withAlphaComponent(0.72),
                ]
                let appAttributes: [NSAttributedString.Key: Any] = [
                    .font: appFont,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.42),
                ]
                let labelSize = (label as NSString).size(withAttributes: attributes)
                let appSize = (app as NSString).size(withAttributes: appAttributes)
                let chipWidth = min(rect.width, max(labelSize.width, appSize.width) + 22)
                let chip = CGRect(x: rect.minX, y: rect.minY - 34, width: chipWidth, height: 28)
                NSColor(white: 0.08, alpha: 0.82).setFill()
                NSBezierPath(roundedRect: chip, xRadius: 9, yRadius: 9).fill()
                (label as NSString).draw(
                    in: CGRect(x: chip.minX + 9, y: chip.minY + 4, width: chip.width - 18, height: 14),
                    withAttributes: attributes
                )
                _ = appSize
            }
        }

        // Tile preview.
        if let preview = controller.tilePreview {
            let rect = preview.frame.cgRect
            accent.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            accent.withAlphaComponent(0.85).setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            path.lineWidth = 2
            path.stroke()
        }

        drawHUD(controller)
    }

    private func drawHUD(_ controller: CanvasModeController) {
        let count = controller.windows.count
        let zoom = Int((controller.camera.zoom * 100).rounded())
        let hint = "⌃⌥Space  back   ·   Esc  restore   ·   drag to move   ·   drop on an edge to tile   ·   click to go in"

        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let hintFont = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        let title = "SUNROOM  ·  \(count) WINDOWS  ·  \(zoom)%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .kern: 0.8,
        ]
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: hintFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let hintSize = (hint as NSString).size(withAttributes: hintAttributes)

        let pillWidth = max(titleSize.width, hintSize.width) + 32
        let pill = CGRect(x: bounds.midX - pillWidth / 2, y: bounds.maxY - 74, width: pillWidth, height: 46)
        NSColor(white: 0.07, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 15, yRadius: 15).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: pill, xRadius: 15, yRadius: 15)
        border.lineWidth = 1
        border.stroke()

        (title as NSString).draw(
            at: CGPoint(x: pill.midX - titleSize.width / 2, y: pill.minY + 8),
            withAttributes: attributes
        )
        (hint as NSString).draw(
            at: CGPoint(x: pill.midX - hintSize.width / 2, y: pill.minY + 25),
            withAttributes: hintAttributes
        )

        if let status = controller.statusMessage, controller.windows.isEmpty {
            let statusFont = NSFont.systemFont(ofSize: 13)
            let statusAttributes: [NSAttributedString.Key: Any] = [.font: statusFont, .foregroundColor: NSColor.white.withAlphaComponent(0.8)]
            let size = (status as NSString).size(withAttributes: statusAttributes)
            (status as NSString).draw(
                at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY),
                withAttributes: statusAttributes
            )
        }
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.beginDrag(at: CanvasPoint(convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.updateDrag(to: CanvasPoint(convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        controller?.endDrag(at: CanvasPoint(convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        var dx = Double(event.scrollingDeltaX)
        var dy = Double(event.scrollingDeltaY)
        if event.modifierFlags.contains(.option) {
            // Option-scroll is a zoom convenience for mice.
            if abs(dy) > 0.01 {
                let anchor = CanvasPoint(convert(event.locationInWindow, from: nil))
                controller?.zoom(by: 1 + dy * 0.01, anchor: anchor)
            }
            return
        }
        if event.modifierFlags.contains(.shift) { swap(&dx, &dy) }
        let sensitivity = event.hasPreciseScrollingDeltas ? 1.0 : 8.0
        controller?.pan(by: CanvasPoint(x: dx * sensitivity, y: dy * sensitivity))
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let anchor = CanvasPoint(convert(event.locationInWindow, from: nil))
        controller?.zoom(by: 1 + Double(event.magnification), anchor: anchor)
        needsDisplay = true
    }

    override func smartMagnify(with event: NSEvent) {
        controller?.fitAll()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // escape
            controller?.exit()
        case 36, 76: // return
            controller?.focusSelection()
        case 123:
            controller?.selectNearest(.left); needsDisplay = true
        case 124:
            controller?.selectNearest(.right); needsDisplay = true
        case 125:
            controller?.selectNearest(.down); needsDisplay = true
        case 126:
            controller?.selectNearest(.up); needsDisplay = true
        case 3: // f
            controller?.fitAll(); needsDisplay = true
        case 48: // tab
            cycleSelection(backwards: event.modifierFlags.contains(.shift))
        default:
            super.keyDown(with: event)
        }
    }

    private func cycleSelection(backwards: Bool) {
        guard let controller, !controller.windows.isEmpty else { return }
        let ids = controller.windows.map(\.id)
        if let current = controller.selection, let index = ids.firstIndex(of: current) {
            let next = backwards ? (index - 1 + ids.count) % ids.count : (index + 1) % ids.count
            controller.selection = ids[next]
        } else {
            controller.selection = ids.first
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = CanvasPoint(convert(event.locationInWindow, from: nil))
        if let controller, controller.windows.contains(where: { controller.camera.screenRect(fromCanvas: $0.planeFrame).contains(point) }) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }
}
