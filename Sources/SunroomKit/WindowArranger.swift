import Foundation
import AppKit
import ApplicationServices

/// Applies plane frames to real windows through the Accessibility API.
///
/// The window server refuses compositor transforms for windows an app does not
/// own (verified on macOS 26: `CGSSetWindowTransform` on a foreign window
/// returns success but silently does nothing), so the only supported way to
/// place another app's window on a canvas is to move and resize it. That means
/// content reflows when zoomed out and apps clamp to their own minimum sizes —
/// both are handled by clamping the camera and by reading frames back.
public final class WindowArranger {
    private let ax: AccessibilityWindowController
    private let queue = DispatchQueue(label: "com.shashvat1965.sunroom.arranger", qos: .userInteractive)
    private var inFlight = false

    public init(ax: AccessibilityWindowController) {
        self.ax = ax
    }

    public var isTrusted: Bool { ax.isTrusted }

    /// Applies frames off the main thread. Calls coalesce: if a batch is already
    /// running, a newer one replaces the pending request instead of queueing
    /// behind it, so a drag cannot build a backlog of stale layouts.
    public func apply(frames: [UInt32: CGRect], pids: [UInt32: Int32], completion: (() -> Void)? = nil) {
        guard !frames.isEmpty else { completion?(); return }
        queue.async { [weak self] in
            guard let self else { return }
            var elements: [UInt32: AXUIElement] = [:]
            for (number, pid) in pids {
                if let element = self.ax.axWindow(for: number, pid: pid) {
                    elements[number] = element
                }
            }
            for (number, frame) in frames {
                guard let element = elements[number] else { continue }
                self.ax.setFrame(frame, of: element)
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Returns the frame the window actually ended up with, which may differ
    /// from the request when an app enforces a minimum size.
    public func actualFrame(windowNumber: UInt32, pid: Int32) -> CGRect? {
        guard let element = ax.axWindow(for: windowNumber, pid: pid) else { return nil }
        return ax.frame(of: element)
    }

    public func animate(frames: [UInt32: CGRect], pids: [UInt32: Int32], duration: TimeInterval = 0.24, completion: (() -> Void)? = nil) {
        ax.animate(frames: frames, pids: pids, duration: duration, steps: 12, completion: completion)
    }

    public func focus(windowNumber: UInt32, pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        ax.raise(windowNumber: windowNumber, pid: pid)
    }

    public func minimize(windowNumber: UInt32, pid: Int32) {
        ax.minimize(windowNumber: windowNumber, pid: pid)
    }

    /// The smallest frame the app will accept, used to clamp zoom so windows do
    /// not fight the layout engine.
    public func minimumSize(windowNumber: UInt32, pid: Int32) -> CGSize? {
        guard let element = ax.axWindow(for: windowNumber, pid: pid) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXMinSize" as CFString, &value) == .success,
              let axValue = value else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return size
    }
}
