import Foundation
import AppKit
import SunroomCore

/// A real, currently-open macOS window discovered via the window server.
public struct ManagedWindow: Identifiable, Hashable, Sendable {
    public var id: UInt32 { windowNumber }
    public let windowNumber: UInt32
    public let ownerPID: Int32
    public let appName: String
    public let windowTitle: String
    public let bundleIdentifier: String?
    /// Frame in AppKit global coordinates (origin bottom-left of the primary display).
    public let frame: CGRect
    public let layer: Int
    public let isOnScreen: Bool

    public init(
        windowNumber: UInt32,
        ownerPID: Int32,
        appName: String,
        windowTitle: String,
        bundleIdentifier: String?,
        frame: CGRect,
        layer: Int,
        isOnScreen: Bool
    ) {
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.appName = appName
        self.windowTitle = windowTitle
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
    }

    public var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    public var reference: WindowReference {
        WindowReference(
            windowNumber: windowNumber,
            ownerPID: ownerPID,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            windowTitle: windowTitle
        )
    }
}

/// Screen geometry helpers. macOS has two coordinate spaces that matter here:
/// AppKit's global space (origin bottom-left of the primary display, y up) and
/// the window server's (origin top-left of the primary display, y down).
public enum ScreenGeometry {
    public static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    public static func appKitRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryHeight - (rect.origin.y + rect.height), width: rect.width, height: rect.height)
    }

    public static func topLeftRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryHeight - (rect.origin.y + rect.height), width: rect.width, height: rect.height)
    }

    public static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    /// The visible area of the screen a window is on, minus menu bar and Dock.
    public static func usableFrame(for rect: CGRect) -> CGRect {
        screen(containing: rect)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

/// Discovers real windows through `CGWindowListCopyWindowInfo`.
public final class WindowDiscovery {
    public init() {}

    /// All manageable windows: layer 0, on screen, owned by another app, and
    /// large enough to be a real window rather than a tooltip or badge.
    public func manageableWindows(excludingProcessIDs: Set<Int32> = [], includeOffscreen: Bool = false) -> [ManagedWindow] {
        var excluded = excludingProcessIDs
        excluded.insert(ProcessInfo.processInfo.processIdentifier)

        let options: CGWindowListOption = includeOffscreen
            ? [.optionAll]
            : [.optionOnScreenOnly, .excludeDesktopElements]

        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [ManagedWindow] = []
        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32, !excluded.contains(ownerPID) else { continue }
            guard let windowNumber = entry[kCGWindowNumber as String] as? UInt32 else { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            // Skip tiny windows (badges, tooltips) and absurd ones.
            guard bounds.width >= 120, bounds.height >= 80, bounds.width < 20000, bounds.height < 20000 else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? "App"
            let title = entry[kCGWindowName as String] as? String ?? ""
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? !includeOffscreen

            // Skip the menu bar extras and the Dock even when they report layer 0.
            if ownerName == "Window Server" || ownerName == "Dock" { continue }

            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
            result.append(
                ManagedWindow(
                    windowNumber: windowNumber,
                    ownerPID: ownerPID,
                    appName: ownerName,
                    windowTitle: title,
                    bundleIdentifier: bundleID,
                    frame: ScreenGeometry.appKitRect(fromTopLeft: bounds),
                    layer: layer,
                    isOnScreen: onScreen
                )
            )
        }
        return result.sorted { lhs, rhs in
            if lhs.appName != rhs.appName { return lhs.appName < rhs.appName }
            return lhs.windowTitle < rhs.windowTitle
        }
    }

    /// Frontmost app's windows first — used by "Add front window".
    public func frontmostWindows() -> [ManagedWindow] {
        guard let front = NSWorkspace.shared.frontmostApplication else { return [] }
        return manageableWindows().filter { $0.ownerPID == front.processIdentifier }
    }
}
