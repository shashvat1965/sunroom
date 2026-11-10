import Foundation
import AppKit
import ScreenCaptureKit

/// Captures live thumbnails of real windows with ScreenCaptureKit.
///
/// Snapshot cadence is deliberately modest (default 1s per window, two in
/// flight at once). A canvas can show dozens of cards; capturing all of them at
/// 60fps would burn battery for no benefit, and the cards are static most of
/// the time. Requests are coalesced per window so hovering or panning cannot
/// queue up work.
@MainActor
public final class WindowCaptureService {

    public struct Snapshot {
        public let image: NSImage
        public let capturedAt: Date
        public let pixelSize: CGSize
    }

    public private(set) var snapshots: [UInt32: Snapshot] = [:]
    public var onSnapshot: ((UInt32, Snapshot) -> Void)?

    /// Seconds between refreshes of the same window.
    public var refreshInterval: TimeInterval = 1.0

    private var windowsByID: [UInt32: SCWindow] = [:]
    private var inFlight: Set<UInt32> = []
    private var lastRequest: [UInt32: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var hasAccess = false

    public init() {}

    public var isCapturing: Bool { hasAccess }

    // MARK: Lifecycle

    /// Starts capture only when permission is already granted. Never prompts:
    /// a first launch must not throw a system dialog at someone who has not
    /// asked for previews yet.
    public func start() async {
        guard CGPreflightScreenCaptureAccess() else {
            hasAccess = false
            return
        }
        hasAccess = true
        await refreshShareableContent()
        startRefreshLoop()
    }

    /// Explicitly asks for Screen Recording, then starts if it was granted.
    @discardableResult
    public func requestPermissionAndStart() async -> Bool {
        let granted = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        hasAccess = granted
        guard granted else { return false }
        await refreshShareableContent()
        startRefreshLoop()
        return true
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Cache the shareable content so per-window captures do not enumerate the
    /// window server each time. Called on a slow cadence to pick up new windows.
    public func refreshShareableContent() async {
        guard hasAccess else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            var map: [UInt32: SCWindow] = [:]
            for window in content.windows {
                map[window.windowID] = window
            }
            windowsByID = map
        } catch {
            // ScreenCaptureKit throws when the user revokes permission while
            // running; fall through with the last known content.
            hasAccess = CGPreflightScreenCaptureAccess()
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.refreshShareableContent()
            }
        }
    }

    // MARK: Capture

    /// Requests a snapshot if the cached one is older than `refreshInterval`.
    public func requestSnapshot(windowNumber: UInt32, force: Bool = false) {
        guard hasAccess, !inFlight.contains(windowNumber) else { return }
        let now = Date()
        if !force, let last = lastRequest[windowNumber], now.timeIntervalSince(last) < refreshInterval { return }
        guard inFlight.count < 2 else { return }
        guard let window = windowsByID[windowNumber] else { return }

        inFlight.insert(windowNumber)
        lastRequest[windowNumber] = now

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetWidth = max(320, min(1600, window.frame.width * scale))
        let targetHeight = max(200, min(1200, window.frame.height * scale))

        Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(windowNumber) }
            do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(targetWidth)
                configuration.height = Int(targetHeight)
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                configuration.captureResolution = .best
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let image = NSImage(cgImage: cgImage, size: NSSize(width: window.frame.width, height: window.frame.height))
                let snapshot = Snapshot(image: image, capturedAt: Date(), pixelSize: CGSize(width: cgImage.width, height: cgImage.height))
                self.snapshots[windowNumber] = snapshot
                self.onSnapshot?(windowNumber, snapshot)
            } catch {
                // Window closed between enumeration and capture, or capture was
                // denied. Drop it from the cache and move on.
                if (error as NSError).code == -3801 {
                    self.windowsByID.removeValue(forKey: windowNumber)
                }
            }
        }
    }

    /// Captures everything visible on screen at once — used for the "freeze"
    /// mode where the canvas shows one static image instead of live cards.
    public func captureFullScreen(display: SCDisplay?) async -> NSImage? {
        guard hasAccess else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let screen = display ?? content.displays.first else { return nil }
            let filter = SCContentFilter(display: screen, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = screen.width
            configuration.height = screen.height
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSImage(cgImage: image, size: NSSize(width: screen.width, height: screen.height))
        } catch {
            return nil
        }
    }

    public func invalidate(windowNumber: UInt32) {
        snapshots.removeValue(forKey: windowNumber)
        lastRequest.removeValue(forKey: windowNumber)
        windowsByID.removeValue(forKey: windowNumber)
    }

    public func prune(keeping windowNumbers: Set<UInt32>) {
        for key in snapshots.keys where !windowNumbers.contains(key) {
            snapshots.removeValue(forKey: key)
        }
        for key in windowsByID.keys where !windowNumbers.contains(key) {
            windowsByID.removeValue(forKey: key)
        }
    }
}
