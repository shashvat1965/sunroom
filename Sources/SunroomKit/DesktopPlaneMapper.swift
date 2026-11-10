import Foundation
import AppKit
import ServiceManagement
import SunroomCore

/// Maps real desktop geometry onto canvas geometry and back.
///
/// The desktop is treated as a rectangle in window-server coordinates (origin
/// top-left of the primary display). A fixed scale keeps a captured desktop
/// comfortably visible on the canvas, and the offset lets the whole map sit
/// wherever the user's camera already is.
public struct DesktopPlaneMapper: Hashable, Sendable {
    /// Canvas points per screen point.
    public var scale: Double
    /// Canvas position of the primary display's top-left corner.
    public var origin: CanvasPoint

    public init(scale: Double = 0.5, origin: CanvasPoint = .zero) {
        self.scale = max(0.05, scale)
        self.origin = origin
    }

    /// Builds a mapper that fits the union of all displays into `target`.
    public static func fitting(screens: [CGRect], target: CanvasRect, padding: Double = 120) -> DesktopPlaneMapper {
        guard let union = CanvasRect.bounding(screens.map(CanvasRect.init)) else {
            return DesktopPlaneMapper()
        }
        let availableWidth = max(1, target.width - padding * 2)
        let availableHeight = max(1, target.height - padding * 2)
        let scale = min(availableWidth / max(union.width, 1), availableHeight / max(union.height, 1))
        let origin = CanvasPoint(
            x: target.minX + padding + (availableWidth - union.width * scale) / 2 - union.minX * scale,
            y: target.minY + padding + (availableHeight - union.height * scale) / 2 - union.minY * scale
        )
        return DesktopPlaneMapper(scale: scale, origin: origin)
    }

    /// `rect` must be in window-server space (y down from the primary display).
    public func canvasRect(forDesktopTopLeft rect: CGRect) -> CanvasRect {
        CanvasRect(
            x: origin.x + Double(rect.origin.x) * scale,
            y: origin.y + Double(rect.origin.y) * scale,
            width: Double(rect.width) * scale,
            height: Double(rect.height) * scale
        )
    }

    public func desktopTopLeftRect(forCanvas rect: CanvasRect) -> CGRect {
        CGRect(
            x: (rect.minX - origin.x) / scale,
            y: (rect.minY - origin.y) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    /// A window's target AppKit frame for a canvas rect, clamped so at least a
    /// title bar stays on screen.
    public func appKitFrame(forCanvas rect: CanvasRect, usableScreen: CGRect) -> CGRect {
        let topLeft = desktopTopLeftRect(forCanvas: rect)
        var frame = ScreenGeometry.appKitRect(fromTopLeft: topLeft)
        let minWidth: CGFloat = 240
        let minHeight: CGFloat = 160
        frame.size.width = max(minWidth, frame.width)
        frame.size.height = max(minHeight, frame.height)
        // Keep the frame on the display: macOS itself clamps aggressively, and
        // unclamped math produces silently wrong layouts.
        if frame.maxX > usableScreen.maxX { frame.origin.x = usableScreen.maxX - frame.width }
        if frame.minX < usableScreen.minX { frame.origin.x = usableScreen.minX }
        if frame.maxY > usableScreen.maxY { frame.origin.y = usableScreen.maxY - frame.height }
        if frame.minY < usableScreen.minY { frame.origin.y = usableScreen.minY }
        return frame
    }
}

/// App icons for the window list, cached per bundle id.
@MainActor
public final class AppIconProvider {
    public static let shared = AppIconProvider()
    private var cache: [String: NSImage] = [:]

    private init() {}

    public func icon(bundleIdentifier: String?, pid: Int32? = nil) -> NSImage {
        if let bundleIdentifier, let cached = cache[bundleIdentifier] { return cached }
        var image: NSImage?
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else if let pid, let running = NSRunningApplication(processIdentifier: pid) {
            image = running.icon
        }
        let resolved = image ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        resolved.size = NSSize(width: 32, height: 32)
        if let bundleIdentifier { cache[bundleIdentifier] = resolved }
        return resolved
    }
}

/// Launch at login, via the modern `SMAppService` API.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    public static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *), isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Sunroom: launch at login failed: \(error.localizedDescription)")
            return false
        }
    }
}
