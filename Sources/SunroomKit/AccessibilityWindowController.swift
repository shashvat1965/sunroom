import Foundation
import AppKit
import ApplicationServices

/// Moves and inspects other apps' windows through the Accessibility API.
///
/// All calls are no-ops when Accessibility is not granted; callers check
/// `isTrusted` and surface the permission UI instead of failing silently.
public final class AccessibilityWindowController {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Dynamic lookup of the private-but-stable `_AXUIElementGetWindow`, which
    /// lets us map a CGWindowID to an AXUIElement. Every macOS window manager
    /// (yabai, AeroSpace, Rectangle) relies on it.
    private static let getWindowFunction: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    // MARK: Window lookup

    public func axWindow(for windowNumber: UInt32, pid: Int32) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        if let getWindow = Self.getWindowFunction {
            for window in windows {
                var candidate: CGWindowID = 0
                if getWindow(window, &candidate) == .success, candidate == windowNumber {
                    return window
                }
            }
        }
        // Fallback: never guess among several windows — that could move the
        // wrong app window. Only unambiguous single-window apps qualify.
        return windows.count == 1 ? windows[0] : nil
    }

    public func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: Frame

    public func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(window, kAXPositionAttribute),
              let size = sizeAttribute(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Sets position and size. Size is applied before position because macOS
    /// clamps position to keep a window on screen; growing first avoids a
    /// visible jump when moving to a larger frame.
    @discardableResult
    public func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        var size = frame.size
        var position = frame.origin
        let sizeValue = AXValueCreate(.cgSize, &size)
        let positionValue = AXValueCreate(.cgPoint, &position)
        var success = true
        if let sizeValue {
            if AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) != .success { success = false }
        }
        if let positionValue {
            if AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) != .success { success = false }
        }
        return success
    }

    @discardableResult
    public func setFrame(_ frame: CGRect, windowNumber: UInt32, pid: Int32) -> Bool {
        guard isTrusted, let window = axWindow(for: windowNumber, pid: pid) else { return false }
        return setFrame(frame, of: window)
    }

    // MARK: Actions

    @discardableResult
    public func raise(windowNumber: UInt32, pid: Int32) -> Bool {
        guard isTrusted else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard let window = axWindow(for: windowNumber, pid: pid) else { return false }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    @discardableResult
    public func minimize(windowNumber: UInt32, pid: Int32) -> Bool {
        guard isTrusted, let window = axWindow(for: windowNumber, pid: pid) else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success, settable.boolValue else {
            return false
        }
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    @discardableResult
    public func toggleFullScreen(windowNumber: UInt32, pid: Int32) -> Bool {
        guard isTrusted, let window = axWindow(for: windowNumber, pid: pid) else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, "AXFullScreen" as CFString, &settable) == .success, settable.boolValue else {
            return false
        }
        var current: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &current)
        let next = !(current as? Bool ?? false)
        return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, next ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    @discardableResult
    public func close(windowNumber: UInt32, pid: Int32) -> Bool {
        guard isTrusted, let window = axWindow(for: windowNumber, pid: pid) else { return false }
        var closeButton: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
              let button = closeButton else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Centers the window in its screen's usable area, keeping its size.
    @discardableResult
    public func center(windowNumber: UInt32, pid: Int32) -> Bool {
        guard let window = axWindow(for: windowNumber, pid: pid), let frame = frame(of: window) else { return false }
        let usable = ScreenGeometry.usableFrame(for: frame)
        let target = CGRect(
            x: usable.midX - frame.width / 2,
            y: usable.midY - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
        return setFrame(target, of: window)
    }

    // MARK: Batch animation

    /// Animates a set of windows to new frames on a background serial queue.
    /// AX has no animation API, so this is a short eased tween — the same
    /// technique yabai uses. Every frame is two synchronous IPC round-trips, so
    /// the work must never happen on the main thread.
    private let animationQueue = DispatchQueue(label: "com.shashvat1965.sunroom.ax-animation", qos: .userInitiated)

    public func animate(
        frames: [UInt32: CGRect],
        pids: [UInt32: Int32],
        duration: TimeInterval = 0.22,
        steps: Int = 12,
        completion: (() -> Void)? = nil
    ) {
        guard isTrusted, !frames.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }
        var elements: [UInt32: (AXUIElement, CGRect)] = [:]
        for (windowNumber, _) in frames {
            guard let pid = pids[windowNumber], let window = axWindow(for: windowNumber, pid: pid),
                  let current = frame(of: window) else { continue }
            elements[windowNumber] = (window, current)
        }
        guard !elements.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }
        let stepCount = max(1, steps)
        animationQueue.async {
            for step in 1...stepCount {
                let raw = Double(step) / Double(stepCount)
                // easeOutCubic
                let t = 1 - pow(1 - raw, 3)
                for (windowNumber, payload) in elements {
                    guard let target = frames[windowNumber] else { continue }
                    let (element, start) = payload
                    let interpolated = CGRect(
                        x: start.origin.x + (target.origin.x - start.origin.x) * t,
                        y: start.origin.y + (target.origin.y - start.origin.y) * t,
                        width: start.width + (target.width - start.width) * t,
                        height: start.height + (target.height - start.height) * t
                    )
                    self.setFrame(interpolated, of: element)
                }
                Thread.sleep(forTimeInterval: duration / Double(stepCount))
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: Private

    private func pointAttribute(_ window: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let axValue = value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ window: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let axValue = value else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
