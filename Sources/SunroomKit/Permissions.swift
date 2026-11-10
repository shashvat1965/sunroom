import Foundation
import AppKit
import ApplicationServices

/// The two TCC permissions Sunroom can use. Both are optional: without them the
/// canvas still works as a notes/thinking surface.
public enum PermissionKind: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording

    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    public var explanation: String {
        switch self {
        case .accessibility:
            return "Lets Sunroom move and focus your windows. macOS requires this for any app that arranges other apps' windows."
        case .screenRecording:
            return "Lets Sunroom draw live previews of your windows on the canvas. Captures stay on this Mac."
        }
    }

    public var symbolName: String {
        switch self {
        case .accessibility: return "hand.raised"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }

    var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screenRecording: return "Privacy_ScreenCapture"
        }
    }
}

public enum PermissionStatus: String, Sendable {
    case granted
    case denied
    case unknown
}

/// Wraps the two TCC checks and the deep links into System Settings.
public final class PermissionsCenter {
    public static let shared = PermissionsCenter()

    private init() {}

    public func status(of kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            if #available(macOS 11.0, *) {
                return CGPreflightScreenCaptureAccess() ? .granted : .denied
            }
            return .unknown
        }
    }

    /// Asks macOS to show the permission prompt. Returns the status right after
    /// asking, which is usually still `.denied` until the user toggles it.
    @discardableResult
    public func request(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            if #available(macOS 11.0, *) {
                _ = CGRequestScreenCaptureAccess()
            }
        }
        return status(of: kind)
    }

    public func openSystemSettings(for kind: PermissionKind) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// The notification macOS posts when TCC changes; useful to refresh UI.
    public var permissionDidChangeNotification: Notification.Name {
        Notification.Name("com.apple.accessibility.api")
    }
}
