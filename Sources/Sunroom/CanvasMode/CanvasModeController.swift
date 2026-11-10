import Foundation
import AppKit
import SwiftUI
import SunroomCore
import SunroomKit

/// Owns "canvas mode": the desktop as one plane of live windows.
///
/// Entering gathers every manageable window, lays them on a plane that keeps
/// their real arrangement, zooms out so all of them fit, and moves the real
/// windows to match (Accessibility). While the mode is on, a full-screen
/// transparent overlay owns the pointer and trackpad so panning, zooming,
/// dragging and clicking can be routed to the plane instead of the apps below.
@MainActor
public final class CanvasModeController: ObservableObject {

    public enum Phase: Equatable {
        case off
        case canvas
        case focused(String)

        public var isActive: Bool { self != .off }
    }

    public struct TilePreview: Equatable {
        public var zone: TileZone
        public var frame: CanvasRect
    }

    // MARK: Published state

    @Published public private(set) var phase: Phase = .off
    @Published public private(set) var windows: [PlaneWindow] = []
    @Published public private(set) var camera: CanvasTransform = .identity
    @Published public var selection: String?
    @Published public var tilePreview: TilePreview?
    @Published public var statusMessage: String?
    @Published public var isBusy = false
    @Published public var showLabels = true

    // MARK: Dependencies

    private let discovery = WindowDiscovery()
    private let ax: AccessibilityWindowController
    private let arranger: WindowArranger
    private let layoutStore: PlaneLayoutStore

    // MARK: Runtime state

    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var restoreFrames: [UInt32: CGRect] = [:]
    private var originalPlaneFrames: [String: CanvasRect] = [:]
    private var backgroundWindow: PlaneBackgroundWindow?
    private var overlayWindow: PlaneOverlayWindow?
    private var applyWorkItem: DispatchWorkItem?
    private var lastApply = Date.distantPast
    private var dragState: DragState?
    private var focusedCamera: CanvasTransform = .identity

    private struct DragState {
        var id: String
        var startPlanePoint: CanvasPoint
        var startFrame: CanvasRect
        var didMove: Bool
    }

    // MARK: Init

    public init(ax: AccessibilityWindowController, layoutStore: PlaneLayoutStore = PlaneLayoutStore()) {
        self.ax = ax
        self.arranger = WindowArranger(ax: ax)
        self.layoutStore = layoutStore
    }

    public var isTrusted: Bool { ax.isTrusted }

    public var isFocused: Bool {
        if case .focused = phase { return true }
        return false
    }

    public var bounds: CanvasRect? {
        CanvasRect.bounding(windows.map(\.planeFrame))
    }

    public var selectedWindow: PlaneWindow? {
        guard let selection else { return nil }
        return windows.first { $0.id == selection }
    }

    // MARK: Toggle

    public func toggle() {
        switch phase {
        case .off:
            enter()
        case .canvas:
            exit()
        case .focused:
            surface()
        }
    }

    // MARK: Enter / exit

    public func enter() {
        guard phase == .off else { return }
        guard ax.isTrusted else {
            statusMessage = "Accessibility is required to move windows."
            return
        }
        guard let targetScreen = screenUnderPointer() ?? NSScreen.main else { return }
        screen = targetScreen
        isBusy = true

        // Each display keeps its own canvas: windows whose centre lives on
        // another screen are left exactly as they are.
        let discovered = discovery.manageableWindows().filter { window in
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            return screen.frame.contains(center)
        }
        guard !discovered.isEmpty else {
            isBusy = false
            statusMessage = "No windows to arrange."
            return
        }

        restoreFrames = Dictionary(uniqueKeysWithValues: discovered.map { ($0.windowNumber, $0.frame) })
        let saved = layoutStore.load()
        var items: [PlaneWindow] = []
        for window in discovered {
            let topLeft = ScreenGeometry.topLeftRect(fromAppKit: window.frame)
            let key = PlaneWindow.identityKey(bundleIdentifier: window.bundleIdentifier, appName: window.appName, title: window.windowTitle)
            let planeFrame = saved[key] ?? CanvasRect(topLeft)
            items.append(
                PlaneWindow(
                    id: key,
                    windowNumber: window.windowNumber,
                    ownerPID: window.ownerPID,
                    appName: window.appName,
                    title: window.windowTitle,
                    bundleIdentifier: window.bundleIdentifier,
                    planeFrame: planeFrame,
                    originalFrame: CanvasRect(topLeft)
                )
            )
        }

        // New windows (no saved position) are parked next to the existing cluster
        // instead of landing on top of it.
        var occupied = items.filter { saved[$0.id] != nil }.map(\.planeFrame)
        for index in items.indices where saved[items[index].id] == nil {
            let spot = PlaneLayoutEngine.parkingSpot(for: items[index].planeFrame.size, avoiding: occupied)
            items[index].planeFrame = spot
            occupied.append(spot)
        }

        let planeBounds = CanvasRect.bounding(items.map(\.planeFrame)) ?? CanvasRect(origin: .zero, size: CanvasSize(width: 1200, height: 800))
        let localScreen = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        let zoom = PlaneLayoutEngine.fittingZoom(for: planeBounds, in: localScreen)
        camera = PlaneLayoutEngine.camera(fitting: planeBounds, in: localScreen, zoom: zoom)

        windows = items
        originalPlaneFrames = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.planeFrame) })
        selection = items.first?.id
        phase = .canvas
        showChrome()
        applyCameraToWindows(animated: true)
        statusMessage = "\(items.count) windows · ⌃⌥Space to go back · Esc to restore"
        isBusy = false
    }

    public func exit() {
        guard phase.isActive else { return }
        hideChrome()
        let frames = restoreFrames
        let pids = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowNumber, $0.ownerPID) })
        arranger.animate(frames: frames, pids: pids, duration: 0.22) { [weak self] in
            self?.finishExit()
        }
        // Fall back to an immediate reset if AX stalls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.finishExit()
        }
    }

    private func finishExit() {
        guard phase != .off else { return }
        phase = .off
        windows = []
        restoreFrames = [:]
        selection = nil
        tilePreview = nil
        dragState = nil
        statusMessage = nil
        isBusy = false
        WindowRegistry.mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Focusing

    public func dive(into id: String) {
        guard let item = windows.first(where: { $0.id == id }) else { return }
        focusedCamera = camera
        selection = id
        phase = .focused(id)
        hideChrome()

        let local = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        var target = local.insetBy(6)
        // Keep a little air around the window, matching the menu bar.
        target = target.insetBy(4)
        let appKit = globalAppKitRect(forLocal: target)
        arranger.animate(
            frames: [item.windowNumber: appKit],
            pids: [item.windowNumber: item.ownerPID],
            duration: 0.26
        ) { [weak self] in
            self?.arranger.focus(windowNumber: item.windowNumber, pid: item.ownerPID)
        }
    }

    /// Back to the zoomed-out plane without leaving the mode.
    public func surface() {
        guard case .focused = phase else { return }
        phase = .canvas
        camera = focusedCamera
        selection = windows.first?.id
        showChrome()
        applyCameraToWindows(animated: true)
        statusMessage = "\(windows.count) windows · ⌃⌥Space to go back · Esc to restore"
    }

    // MARK: Camera

    public func pan(by delta: CanvasPoint) {
        guard phase == .canvas else { return }
        camera = camera.panning(by: delta)
        scheduleApply()
    }

    public func zoom(by factor: Double, anchor: CanvasPoint) {
        guard phase == .canvas else { return }
        let previous = camera.zoom
        camera = camera.zooming(by: factor, anchor: anchor).clampedZoom(minimum: 0.33, maximum: 1.0)
        if abs(camera.zoom - previous) > 0.0001 {
            scheduleApply()
        }
    }

    public func fitAll() {
        guard phase == .canvas, let bounds else { return }
        let local = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        let zoom = PlaneLayoutEngine.fittingZoom(for: bounds, in: local)
        camera = PlaneLayoutEngine.camera(fitting: bounds, in: local, zoom: zoom)
        scheduleApply(force: true)
    }

    public func focus(_ id: String) {
        guard let item = windows.first(where: { $0.id == id }) else { return }
        selection = id
        let local = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        camera = PlaneLayoutEngine.camera(focusing: item.planeFrame, in: local, scale: 0.92)
    }

    // MARK: Keyboard

    public func selectNearest(_ direction: PlaneLayoutEngine.Direction) {
        guard let reference = selectedWindow?.planeFrame ?? bounds else { return }
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.planeFrame) })
        if let next = PlaneLayoutEngine.nearest(to: reference, in: frames, direction: direction) {
            selection = next
        }
    }

    public func focusSelection() {
        if let selection {
            dive(into: selection)
        }
    }

    // MARK: Dragging

    public func beginDrag(at localPoint: CanvasPoint) {
        let planePoint = camera.canvasPoint(fromScreen: localPoint)
        guard let hit = windows.last(where: { $0.planeFrame.contains(planePoint) }) else {
            dragState = nil
            selection = nil
            return
        }
        selection = hit.id
        dragState = DragState(id: hit.id, startPlanePoint: planePoint, startFrame: hit.planeFrame, didMove: false)
    }

    public func updateDrag(to localPoint: CanvasPoint) {
        guard var drag = dragState else { return }
        let planePoint = camera.canvasPoint(fromScreen: localPoint)
        let delta = CanvasPoint(x: planePoint.x - drag.startPlanePoint.x, y: planePoint.y - drag.startPlanePoint.y)
        guard abs(delta.x) > 3 || abs(delta.y) > 3 else { return }
        drag.didMove = true
        dragState = drag
        guard let index = windows.firstIndex(where: { $0.id == drag.id }) else { return }
        windows[index].planeFrame = drag.startFrame.offsetBy(delta)
        tilePreview = tilePreview(at: localPoint, ignoring: drag.id)
        scheduleApply(force: true)
    }

    public func endDrag(at localPoint: CanvasPoint) {
        guard let drag = dragState else { return }
        dragState = nil
        guard drag.didMove, let index = windows.firstIndex(where: { $0.id == drag.id }) else {
            if let selection = selection { dive(into: selection) }
            return
        }

        let localScreen = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        if let zone = TileZone.zone(for: CanvasPoint(x: Double(localPoint.x), y: Double(localPoint.y)), in: localScreen) {
            let frame = zone.frame(in: localScreen)
            windows[index].planeFrame = CanvasRect(
                x: Double(frame.minX - camera.translation.x) / camera.zoom,
                y: Double(frame.minY - camera.translation.y) / camera.zoom,
                width: frame.width / camera.zoom,
                height: frame.height / camera.zoom
            )
            tilePreview = nil
            applyCameraToWindows(animated: true)
            persist()
            return
        }

        // Dropped onto another window: stack it neatly on top.
        let dropped = windows[index].planeFrame
        let center = dropped.center
        if let target = windows.last(where: { $0.id != drag.id && $0.planeFrame.contains(center) }) {
            let targetIndex = windows.firstIndex(where: { $0.id == target.id }) ?? 0
            windows[index].planeFrame = PlaneLayoutEngine.stacked(dropped, onto: windows[targetIndex].planeFrame)
        }
        tilePreview = nil
        applyCameraToWindows(animated: false)
        persist()
    }

    private func tilePreview(at localPoint: CanvasPoint, ignoring id: String) -> TilePreview? {
        let localScreen = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        guard let zone = TileZone.zone(for: CanvasPoint(x: Double(localPoint.x), y: Double(localPoint.y)), in: localScreen) else {
            return nil
        }
        return TilePreview(zone: zone, frame: zone.frame(in: localScreen))
    }

    // MARK: Applying frames

    /// Coalesced so a drag or a pan does not queue a hundred AX batches.
    private func scheduleApply(force: Bool = false) {
        guard phase == .canvas else { return }
        applyWorkItem?.cancel()
        let now = Date()
        let minimumInterval = force ? 0.0 : 1.0 / 30.0
        let delay = max(0, minimumInterval - now.timeIntervalSince(lastApply))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastApply = Date()
            self.applyCameraToWindows(animated: false)
        }
        applyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func applyCameraToWindows(animated: Bool) {
        guard phase == .canvas else { return }
        var frames: [UInt32: CGRect] = [:]
        var pids: [UInt32: Int32] = [:]
        for item in windows {
            let local = camera.screenRect(fromCanvas: item.planeFrame)
            let clamped = clampToScreen(local)
            frames[item.windowNumber] = globalAppKitRect(forLocal: clamped)
            pids[item.windowNumber] = item.ownerPID
        }
        if animated {
            arranger.animate(frames: frames, pids: pids, duration: 0.26)
        } else {
            arranger.apply(frames: frames, pids: pids)
        }
    }

    private func clampToScreen(_ rect: CanvasRect) -> CanvasRect {
        let local = CanvasRect(x: 0, y: 0, width: Double(screen.frame.width), height: Double(screen.frame.height))
        let minimumWidth = 160.0
        let minimumHeight = 110.0
        var width = max(minimumWidth, rect.width)
        var height = max(minimumHeight, rect.height)
        width = min(width, local.width)
        height = min(height, local.height)
        var x = rect.minX
        var y = rect.minY
        if x + width > local.maxX { x = local.maxX - width }
        if y + height > local.maxY { y = local.maxY - height }
        x = max(local.minX, x)
        y = max(local.minY, y)
        return CanvasRect(x: x, y: y, width: width, height: height)
    }

    private func globalAppKitRect(forLocal rect: CanvasRect) -> CGRect {
        let primaryHeight = ScreenGeometry.primaryHeight
        let offsetX = screen.frame.minX
        let offsetY = primaryHeight - screen.frame.maxY
        let topLeft = CGRect(
            x: rect.minX + offsetX,
            y: rect.minY + offsetY,
            width: rect.width,
            height: rect.height
        )
        return ScreenGeometry.appKitRect(fromTopLeft: topLeft)
    }

    private func localRect(forAppKit rect: CGRect) -> CanvasRect {
        let topLeft = ScreenGeometry.topLeftRect(fromAppKit: rect)
        let offsetX = screen.frame.minX
        let offsetY = ScreenGeometry.primaryHeight - screen.frame.maxY
        return CanvasRect(
            x: Double(topLeft.minX - offsetX),
            y: Double(topLeft.minY - offsetY),
            width: Double(topLeft.width),
            height: Double(topLeft.height)
        )
    }

    // MARK: Persistence

    public func persist() {
        layoutStore.save(Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.planeFrame) }))
    }

    // MARK: Chrome windows

    private func showChrome() {
        // The board window would otherwise sit on the plane as a stray object.
        WindowRegistry.mainWindow?.orderOut(nil)
        if backgroundWindow == nil {
            backgroundWindow = PlaneBackgroundWindow(screen: screen)
        }
        backgroundWindow?.setScreen(screen)
        backgroundWindow?.orderFrontRegardless()

        if overlayWindow == nil {
            let overlay = PlaneOverlayWindow(controller: self)
            overlayWindow = overlay
        }
        overlayWindow?.setScreen(screen)
        overlayWindow?.orderFrontRegardless()
        overlayWindow?.makeKey()
    }

    private func hideChrome() {
        overlayWindow?.orderOut(nil)
        backgroundWindow?.orderOut(nil)
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    // MARK: Debug / preview

    public func previewLayoutForRendering() -> [PlaneWindow] {
        windows
    }
}

// MARK: - Layout persistence

/// Remembers where each window lived on the plane, keyed by app + title.
public final class PlaneLayoutStore {
    private let url: URL
    private let queue = DispatchQueue(label: "com.shashvat1965.sunroom.plane-layout", qos: .utility)

    public init(location: StorageLocation = .applicationSupport()) {
        self.url = location.root.appendingPathComponent("plane-layout.json")
    }

    public func load() -> [String: CanvasRect] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CanvasRect].self, from: data) else {
            return [:]
        }
        return decoded
    }

    public func save(_ layout: [String: CanvasRect]) {
        let url = self.url
        queue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(layout)
                try data.write(to: url, options: [.atomic])
            } catch {
                NSLog("Sunroom: could not save plane layout: \(error.localizedDescription)")
            }
        }
    }
}

extension CanvasTransform {
    /// Keeps the plane camera inside a usable zoom range.
    func clampedZoom(minimum: Double, maximum: Double) -> CanvasTransform {
        let clamped = Geometry.clamp(zoom, minimum, maximum)
        guard clamped != zoom else { return self }
        // Keep the viewport centre stable while clamping.
        let center = CanvasPoint(x: 0, y: 0)
        return zooming(to: clamped, anchor: center)
    }
}
