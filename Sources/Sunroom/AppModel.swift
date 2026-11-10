import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SunroomCore
import SunroomKit

/// The single source of truth for the running app.
///
/// Views never touch the file store, the Accessibility API or ScreenCaptureKit
/// directly; they call intent methods here. That keeps window-server side
/// effects in one auditable place and makes the UI layer previewable.
@MainActor
public final class AppModel: ObservableObject {

    // MARK: Tool

    public enum Tool: String, CaseIterable, Identifiable, Sendable {
        case select
        case pan
        case note
        case text
        case frame

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .select: return "Select"
            case .pan: return "Hand"
            case .note: return "Note"
            case .text: return "Text"
            case .frame: return "Frame"
            }
        }

        public var symbolName: String {
            switch self {
            case .select: return "cursorarrow"
            case .pan: return "hand.draw"
            case .note: return "note.text"
            case .text: return "text.alignleft"
            case .frame: return "rectangle.dashed"
            }
        }
    }

    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public var message: String
        public var systemImage: String
        public var isError: Bool = false
    }

    // MARK: Published state

    @Published public private(set) var summaries: [CanvasSummary] = []
    @Published public var document: CanvasDocument {
        didSet { scheduleSave() }
    }
    @Published public var camera: CanvasTransform
    @Published public var viewportSize: CGSize = .zero
    /// Chrome that floats over the canvas. Fitting and centering keep content
    /// clear of it instead of hiding cards behind the sidebar.
    @Published public var canvasInsets = NSEdgeInsets(top: 70, left: 276, bottom: 56, right: 0)
    private var hasPerformedInitialFit = false
    @Published public var selection: Set<UUID> = []
    @Published public var editingNodeID: UUID?
    @Published public var tool: Tool = .select
    @Published public var settings: AppSettings {
        didSet { settingsStore.save(settings) }
    }
    @Published public var snapGuides: [SnapGuide] = []
    @Published public var marqueeRect: CanvasRect?
    @Published public var toast: Toast?
    @Published public var availableWindows: [ManagedWindow] = []
    @Published public var permissionStatus: [PermissionKind: PermissionStatus] = [:]
    @Published public var windowSnapshots: [UInt32: NSImage] = [:]
    @Published public var isPalettePresented = false
    @Published public var isWindowLibraryPresented = false
    @Published public var isInspectorPresented = false
    @Published public var isOnboardingPresented = false
    @Published public var isSearchFocused = false
    @Published public var isShortcutSheetPresented = false
    @Published public var isApplyingLayout = false
    @Published public var isCapturingDesktop = false
    @Published public var searchQuery = ""

    // MARK: Services

    public let launchOptions: LaunchOptions
    public let store: DocumentFileStore
    public let settingsStore: SettingsStore
    public let windowDiscovery: WindowDiscovery
    public let ax: AccessibilityWindowController
    public let capture: WindowCaptureService
    public let hotKeys: HotKeyCenter

    private let undoStack = UndoStack()
    private var autosave: AutosaveController?
    private var copiedNodes: [CanvasNode] = []
    private var pasteCounter = 0
    private var windowRefreshTimer: Timer?
    private var toastTask: Task<Void, Never>?
    private var captureObserver: NSObjectProtocol?

    // MARK: Init

    public init(
        store: DocumentFileStore = DocumentFileStore(),
        settingsStore: SettingsStore = SettingsStore(),
        launchOptions: LaunchOptions = LaunchOptions.current()
    ) {
        self.launchOptions = launchOptions
        self.store = store
        self.settingsStore = settingsStore
        self.windowDiscovery = WindowDiscovery()
        self.ax = AccessibilityWindowController()
        self.capture = WindowCaptureService()
        self.hotKeys = HotKeyCenter()
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings

        try? store.prepare()

        let loaded = store.loadAll()
        self.summaries = loaded.map(\.canvasSummary)

        let initial: CanvasDocument
        if let requested = launchOptions.canvasID, let match = loaded.first(where: { $0.id == requested }) {
            initial = match
        } else if loadedSettings.restoreLastCanvas, let last = loaded.first {
            initial = last
        } else if let last = loaded.first {
            initial = last
        } else {
            initial = SampleCanvas.welcome()
        }
        self.document = initial
        self.camera = initial.transform
        self.isInspectorPresented = loadedSettings.inspectorVisible

        self.autosave = AutosaveController { [weak self] document in
            guard let self else { return }
            StoreWriter.write(document, to: self.store)
        }

        if loaded.isEmpty {
            persist(force: true)
            isOnboardingPresented = true
        }

        refreshPermissions()
        configureHotKeys()
        startWindowRefresh()
        observePermissionChanges()
    }

    public struct LaunchOptions: Sendable {
        public var canvasID: UUID?
        public var showsOnboarding: Bool
        public var snapshotDirectory: String?
        public var quitsAfterSnapshot: Bool

        public init(
            canvasID: UUID? = nil,
            showsOnboarding: Bool = false,
            snapshotDirectory: String? = nil,
            quitsAfterSnapshot: Bool = false
        ) {
            self.canvasID = canvasID
            self.showsOnboarding = showsOnboarding
            self.snapshotDirectory = snapshotDirectory
            self.quitsAfterSnapshot = quitsAfterSnapshot
        }

        public static func current() -> LaunchOptions {
            let args = ProcessInfo.processInfo.arguments
            var id: UUID?
            if let index = args.firstIndex(of: "--canvas"), args.count > index + 1 {
                id = UUID(uuidString: args[index + 1])
            }
            var snapshotDirectory: String?
            if let index = args.firstIndex(of: "--snapshot"), args.count > index + 1 {
                snapshotDirectory = args[index + 1]
            }
            return LaunchOptions(
                canvasID: id,
                showsOnboarding: args.contains("--onboarding") || args.contains("--first-run"),
                snapshotDirectory: snapshotDirectory,
                quitsAfterSnapshot: args.contains("--quit-after-snapshot")
            )
        }
    }

    // MARK: Derived

    public var selectedNodes: [CanvasNode] {
        document.nodes.filter { selection.contains($0.id) }
    }

    public var selectionBounds: CanvasRect? {
        document.bounds(of: selection)
    }

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }
    public var undoLabel: String? { undoStack.undoLabel }
    public var redoLabel: String? { undoStack.redoLabel }

    public var windowNodes: [CanvasNode] {
        document.nodes.filter { $0.kind == .window }
    }

    public var visibleCanvasBounds: CanvasRect {
        camera.visibleCanvasRect(in: CanvasSize(viewportSize))
    }

    /// The part of the window the canvas should treat as usable.
    public var effectiveViewport: CanvasSize {
        CanvasSize(
            width: max(120, viewportSize.width - canvasInsets.left - canvasInsets.right),
            height: max(120, viewportSize.height - canvasInsets.top - canvasInsets.bottom)
        )
    }

    private var effectiveCenterScreen: CanvasPoint {
        CanvasPoint(
            x: Double(canvasInsets.left) + Double(effectiveViewport.width) / 2,
            y: Double(canvasInsets.top) + Double(effectiveViewport.height) / 2
        )
    }

    public var levelOfDetail: LevelOfDetail {
        LevelOfDetail.forZoom(camera.zoom)
    }

    public var hasAccessibility: Bool { permissionStatus[.accessibility] == .granted }
    public var hasScreenRecording: Bool { permissionStatus[.screenRecording] == .granted }

    // MARK: Document lifecycle

    public func newCanvas(named name: String? = nil) {
        let generated = name ?? "Canvas \(summaries.count + 1)"
        var canvas = CanvasDocument.empty(named: generated)
        let center = camera.canvasPoint(fromScreen: CanvasPoint(x: Double(viewportSize.width) / 2, y: Double(viewportSize.height) / 2))
        canvas.transform = CanvasTransform(translation: CanvasPoint(x: Double(viewportSize.width) / 2, y: Double(viewportSize.height) / 2), zoom: 1)
        _ = center
        open(canvas, resetUndo: true)
        persist(force: true)
        showToast("Created \(canvas.name)", systemImage: "plus.rectangle.on.rectangle")
    }

    public func open(_ canvas: CanvasDocument, resetUndo: Bool = true) {
        persist(force: true)
        document = canvas
        camera = canvas.transform
        selection = []
        editingNodeID = nil
        if resetUndo { undoStack.reset() }
        if !summaries.contains(where: { $0.id == canvas.id }) {
            summaries.insert(canvas.canvasSummary, at: 0)
        }
    }

    public func openCanvas(id: UUID) {
        guard id != document.id else { return }
        do {
            let canvas = try store.loadCanvas(id: id)
            open(canvas)
        } catch {
            showToast(error.localizedDescription, systemImage: "exclamationmark.triangle", isError: true)
        }
    }

    public func deleteCanvas(id: UUID) {
        do {
            try store.delete(id: id)
            summaries.removeAll { $0.id == id }
            if document.id == id {
                if let next = summaries.first {
                    openCanvas(id: next.id)
                } else {
                    var fresh = SampleCanvas.welcome()
                    fresh.id = UUID()
                    open(fresh, resetUndo: true)
                }
            }
        } catch {
            showToast("Could not delete canvas", systemImage: "exclamationmark.triangle", isError: true)
        }
    }

    public func renameCanvas(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if id == document.id {
            document.name = trimmed
            document.touch()
        } else if var other = try? store.loadCanvas(id: id) {
            other.name = trimmed
            other.touch()
            try? store.save(other)
        }
        if let index = summaries.firstIndex(where: { $0.id == id }) {
            summaries[index].name = trimmed
            summaries[index].updatedAt = Date()
        }
    }

    public func duplicateCanvas(id: UUID) {
        guard let original = (id == document.id ? document : (try? store.loadCanvas(id: id))) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = "\(original.name) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        let idMap = Dictionary(uniqueKeysWithValues: copy.nodes.map { ($0.id, UUID()) })
        for index in copy.nodes.indices {
            copy.nodes[index].id = idMap[copy.nodes[index].id] ?? UUID()
            if let group = copy.nodes[index].groupID {
                copy.nodes[index].groupID = idMap[group]
            }
        }
        try? store.save(copy)
        summaries.insert(copy.canvasSummary, at: 0)
        showToast("Duplicated canvas", systemImage: "square.on.square")
    }

    public func reloadSummaries() {
        summaries = store.loadSummaries()
    }

    // MARK: Undo

    private func record(_ label: String, coalescingKey: String? = nil) {
        undoStack.record(document, label: label, coalescingKey: coalescingKey)
    }

    /// Used by the canvas after a drag/resize gesture: one undo step for the
    /// whole gesture, applied atomically when the mouse comes up.
    /// Commits an inline text edit as one undoable change.
    public func commitTextEdit(nodeID: UUID, title: String, text: String) {
        guard let existing = document.node(withID: nodeID) else { return }
        guard existing.title != title || existing.text != text else { return }
        record("Edit Text")
        if let index = document.index(of: nodeID) {
            document.nodes[index].title = title
            document.nodes[index].text = text
            document.nodes[index].touch()
            document.touch()
        }
    }

    public func renameNode(id: UUID, to title: String) {
        guard let node = document.node(withID: id), node.title != title else { return }
        record("Rename")
        document.rename(id: id, title: title)
    }

    public func setFrame(nodeID: UUID, to frame: CanvasRect) {
        guard document.node(withID: nodeID)?.frame != frame else { return }
        record("Resize")
        document.setFrame(id: nodeID, to: frame)
    }

    public func setFontSize(nodeID: UUID, to size: Double) {
        guard let node = document.node(withID: nodeID) else { return }
        var style = node.style
        style.fontSize = max(9, min(64, size))
        record("Change Font Size", coalescingKey: "fontSize-\(nodeID)")
        document.setStyle(id: nodeID, style: style)
    }

    public func commitInteractiveEdit(document newDocument: CanvasDocument, label: String) {
        guard newDocument.nodes != document.nodes else { return }
        undoStack.record(document, label: label)
        var merged = newDocument
        merged.updatedAt = Date()
        document = merged
    }

    public func undo() {
        guard let restored = undoStack.undo(current: document) else { return }
        document = restored
        selection = selection.intersection(Set(restored.nodes.map(\.id)))
        showToast("Undo \(undoStack.redoLabel ?? "")".trimmingCharacters(in: .whitespaces), systemImage: "arrow.uturn.backward")
    }

    public func redo() {
        guard let restored = undoStack.redo(current: document) else { return }
        document = restored
        selection = selection.intersection(Set(restored.nodes.map(\.id)))
        showToast("Redo \(undoStack.undoLabel ?? "")".trimmingCharacters(in: .whitespaces), systemImage: "arrow.uturn.forward")
    }

    // MARK: Node creation

    @discardableResult
    public func addNote(at point: CanvasPoint? = nil, accent: ColorToken? = nil) -> UUID {
        record("Add Note")
        let center = point ?? camera.canvasPoint(fromScreen: effectiveCenterScreen)
        let frame = CanvasRect(x: center.x - 140, y: center.y - 110, width: 280, height: 220)
        let node = CanvasNode(
            kind: .note,
            frame: frame,
            title: "New Note",
            text: "",
            style: NodeStyle(accent: (accent ?? settings.accent).rawValue, fontSize: 15)
        )
        document.insertOnTop(node)
        selection = [node.id]
        editingNodeID = node.id
        tool = .select
        return node.id
    }

    @discardableResult
    public func addText(at point: CanvasPoint? = nil) -> UUID {
        record("Add Text")
        let center = point ?? camera.canvasPoint(fromScreen: effectiveCenterScreen)
        let node = CanvasNode(
            kind: .text,
            frame: CanvasRect(x: center.x - 200, y: center.y - 70, width: 400, height: 140),
            title: "Heading",
            text: "Write something worth keeping.",
            style: NodeStyle(accent: ColorToken.slate.rawValue, fontSize: 16, cornerRadius: 16)
        )
        document.insertOnTop(node)
        selection = [node.id]
        tool = .select
        return node.id
    }

    @discardableResult
    public func addFrame(at point: CanvasPoint? = nil) -> UUID {
        record("Add Frame")
        let center = point ?? camera.canvasPoint(fromScreen: effectiveCenterScreen)
        let node = CanvasNode(
            kind: .group,
            frame: CanvasRect(x: center.x - 320, y: center.y - 220, width: 640, height: 440),
            title: "Frame",
            style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 28)
        )
        document.insert(node, at: 0)
        selection = [node.id]
        tool = .select
        return node.id
    }

    public func addImage(from url: URL) {
        guard let assetName = try? store.importAsset(from: url) else {
            showToast("Could not import image", systemImage: "exclamationmark.triangle", isError: true)
            return
        }
        guard let image = NSImage(contentsOf: url) else { return }
        record("Add Image")
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1.4
        let width = 420.0
        let center = camera.canvasPoint(fromScreen: CanvasPoint(x: Double(viewportSize.width) / 2, y: Double(viewportSize.height) / 2))
        let node = CanvasNode(
            kind: .image,
            frame: CanvasRect(x: center.x - width / 2, y: center.y - width / aspect / 2, width: width, height: width / aspect),
            title: url.deletingPathExtension().lastPathComponent,
            style: NodeStyle(accent: ColorToken.sand.rawValue, cornerRadius: 20),
            imageAssetName: assetName
        )
        document.insertOnTop(node)
        selection = [node.id]
        showToast("Added image", systemImage: "photo")
    }

    public func addImageData(_ data: Data, name: String) {
        let ext = name.contains(".") ? String(name.split(separator: ".").last ?? "png") : "png"
        guard let assetName = try? store.importAsset(data: data, preferredExtension: ext) else { return }
        record("Paste Image")
        let center = camera.canvasPoint(fromScreen: CanvasPoint(x: Double(viewportSize.width) / 2, y: Double(viewportSize.height) / 2))
        let node = CanvasNode(
            kind: .image,
            frame: CanvasRect(x: center.x - 240, y: center.y - 170, width: 480, height: 340),
            title: name,
            style: NodeStyle(accent: ColorToken.sand.rawValue, cornerRadius: 20),
            imageAssetName: assetName
        )
        document.insertOnTop(node)
        selection = [node.id]
        showToast("Pasted image", systemImage: "photo")
    }

    @discardableResult
    public func addLink(_ rawURL: String, at point: CanvasPoint? = nil) -> UUID? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized), url.host != nil else {
            showToast("That doesn't look like a link", systemImage: "link.badge.plus", isError: true)
            return nil
        }
        record("Add Link")
        let center = point ?? camera.canvasPoint(fromScreen: effectiveCenterScreen)
        let node = CanvasNode(
            kind: .link,
            frame: CanvasRect(x: center.x - 180, y: center.y - 70, width: 360, height: 140),
            title: url.host ?? url.absoluteString,
            text: url.absoluteString,
            style: NodeStyle(accent: ColorToken.sky.rawValue, cornerRadius: 20),
            linkURL: url.absoluteString
        )
        document.insertOnTop(node)
        selection = [node.id]
        showToast("Added link", systemImage: "link")
        return node.id
    }

    /// Adds a live window card. Cards are sized proportionally to the real
    /// window so a canvas of windows reads like a desktop.
    @discardableResult
    public func addWindow(_ window: ManagedWindow, at point: CanvasPoint? = nil) -> UUID {
        record("Add Window")
        let scale = 0.42
        let width = Double(window.frame.width) * scale
        let height = Double(window.frame.height) * scale
        let center = point ?? camera.canvasPoint(fromScreen: effectiveCenterScreen)
        let node = CanvasNode(
            kind: .window,
            frame: CanvasRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
            title: window.displayTitle,
            text: window.appName,
            style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 14),
            windowReference: window.reference
        )
        document.insertOnTop(node)
        selection = [node.id]
        if settings.capturePreviews, hasScreenRecording {
            capture.requestSnapshot(windowNumber: window.windowNumber, force: true)
        }
        return node.id
    }

    // MARK: Selection editing

    public func deleteSelection() {
        guard !selection.isEmpty else { return }
        record("Delete")
        document.remove(ids: selection)
        selection = []
        editingNodeID = nil
    }

    public func duplicateSelection() {
        guard !selection.isEmpty else { return }
        record("Duplicate")
        let newIDs = document.duplicate(ids: selection)
        selection = newIDs
    }

    public func copySelection() {
        copiedNodes = document.nodes.filter { selection.contains($0.id) }
        pasteCounter = 0
        if !copiedNodes.isEmpty {
            showToast("Copied \(copiedNodes.count) item\(copiedNodes.count == 1 ? "" : "s")", systemImage: "doc.on.doc")
        }
    }

    public func paste() {
        guard !copiedNodes.isEmpty else { return }
        record("Paste")
        pasteCounter += 1
        let offset = CanvasPoint(x: 24 * Double(pasteCounter), y: 24 * Double(pasteCounter))
        var mapping: [UUID: UUID] = [:]
        for node in copiedNodes { mapping[node.id] = UUID() }
        var newIDs: Set<UUID> = []
        for node in copiedNodes {
            var copy = node
            copy.id = mapping[node.id] ?? UUID()
            copy.frame = node.frame.offsetBy(offset)
            copy.createdAt = Date()
            copy.updatedAt = Date()
            if let group = node.groupID { copy.groupID = mapping[group] }
            document.insertOnTop(copy)
            newIDs.insert(copy.id)
        }
        selection = newIDs
    }

    public func align(_ alignment: CanvasDocument.Alignment) {
        guard selection.count > 1 else { return }
        record(alignment.displayName)
        document.align(ids: selection, to: alignment)
    }

    public func distribute(horizontally: Bool) {
        guard selection.count > 2 else { return }
        record(horizontally ? "Distribute Horizontally" : "Distribute Vertically")
        document.distribute(ids: selection, horizontally: horizontally)
    }

    public func groupSelection() {
        guard selection.count >= 2 else { return }
        record("Group")
        if let id = document.group(ids: selection) {
            selection.insert(id)
        }
    }

    public func ungroupSelection() {
        record("Ungroup")
        document.ungroup(ids: selection)
    }

    public func bringToFront() {
        guard !selection.isEmpty else { return }
        record("Bring to Front")
        document.bringToFront(ids: selection)
    }

    public func sendToBack() {
        guard !selection.isEmpty else { return }
        record("Send to Back")
        document.sendToBack(ids: selection)
    }

    public func nudge(dx: Double, dy: Double) {
        guard !selection.isEmpty else { return }
        record("Nudge", coalescingKey: "nudge")
        document.move(ids: selection, by: CanvasPoint(x: dx, y: dy))
    }

    public func setAccent(_ token: ColorToken) {
        guard !selection.isEmpty else { return }
        record("Change Color")
        document.setAccent(ids: selection, accent: token)
    }

    public func toggleLock() {
        guard !selection.isEmpty else { return }
        record("Lock")
        document.toggleLock(ids: selection)
    }

    public func arrangeSelection(_ mode: LayoutEngine.Arrangement) {
        guard selection.count > 1 else { return }
        record("Arrange \(mode.displayName)")
        let nodes = selectedNodes
        let frames = LayoutEngine.reflow(nodes: nodes, mode: mode)
        for (node, frame) in zip(nodes, frames) {
            document.setFrame(id: node.id, to: frame)
        }
    }

    public func arrangeAll(_ mode: LayoutEngine.Arrangement) {
        guard document.nodes.count > 1 else { return }
        record("Tidy Up")
        let frames = LayoutEngine.reflow(nodes: document.nodes, mode: mode)
        for (node, frame) in zip(document.nodes, frames) {
            document.setFrame(id: node.id, to: frame)
        }
        fitAll()
    }

    // MARK: Camera

    public func setCamera(_ transform: CanvasTransform, animated: Bool = false) {
        guard !animated || settings.reduceMotion == false else {
            camera = transform
            return
        }
        camera = transform
    }

    public func pan(by delta: CanvasPoint) {
        camera = camera.panning(by: delta)
    }

    public func zoom(by factor: Double, anchor: CanvasPoint? = nil) {
        camera = camera.zooming(by: factor, anchor: anchor ?? effectiveCenterScreen)
    }

    public func zoomIn() { zoom(by: 1.25) }
    public func zoomOut() { zoom(by: 0.8) }

    public func resetZoom() {
        camera = camera.zooming(to: 1, anchor: effectiveCenterScreen)
    }

    /// Frames the whole document the first time the window has a real size.
    public func performInitialFitIfNeeded() {
        guard !hasPerformedInitialFit, viewportSize.width > 100, !document.nodes.isEmpty else { return }
        hasPerformedInitialFit = true
        fitAll()
    }

    public func fitAll() {
        guard let bounds = document.bounds else {
            camera = .identity
            return
        }
        var transform = CanvasTransform.identity.fitting(bounds, in: effectiveViewport, padding: 72)
        transform.translation = transform.translation + CanvasPoint(x: Double(canvasInsets.left), y: Double(canvasInsets.top))
        camera = transform
    }

    public func fitSelection() {
        guard let bounds = selectionBounds else { fitAll(); return }
        var transform = CanvasTransform.identity.fitting(bounds, in: effectiveViewport, padding: 110, maxZoom: 1.6)
        transform.translation = transform.translation + CanvasPoint(x: Double(canvasInsets.left), y: Double(canvasInsets.top))
        camera = transform
    }

    public func centerOnNode(id: UUID, animated: Bool = true) {
        guard let node = document.node(withID: id) else { return }
        var transform = camera.centering(on: node.frame.center, in: effectiveViewport)
        transform.translation = transform.translation + CanvasPoint(x: Double(canvasInsets.left), y: Double(canvasInsets.top))
        camera = transform
        selection = [id]
    }

    public func selectAll() {
        selection = Set(document.nodes.filter { !$0.isLocked }.map(\.id))
    }

    public func deselectAll() {
        selection = []
        editingNodeID = nil
    }

    // MARK: Windows

    public func refreshWindows() {
        availableWindows = windowDiscovery.manageableWindows()
        if settings.capturePreviews, hasScreenRecording {
            for node in windowNodes {
                if let reference = node.windowReference {
                    capture.requestSnapshot(windowNumber: reference.windowNumber)
                }
            }
        }
    }

    public func refreshPermissions() {
        var status: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases {
            status[kind] = PermissionsCenter.shared.status(of: kind)
        }
        permissionStatus = status
    }

    public func requestPermission(_ kind: PermissionKind) {
        PermissionsCenter.shared.request(kind)
        refreshPermissions()
        if permissionStatus[kind] == .granted {
            if kind == .screenRecording { startCapture() }
        } else {
            PermissionsCenter.shared.openSystemSettings(for: kind)
        }
    }

    public func startCapture() {
        guard settings.capturePreviews, hasScreenRecording else { return }
        capture.refreshInterval = settings.captureInterval
        Task { [weak self] in
            guard let self else { return }
            await self.capture.start()
            self.refreshWindows()
        }
    }

    /// Called from the UI when the user explicitly asks for previews, so the
    /// system prompt appears in context rather than at launch.
    public func enablePreviews() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.capture.requestPermissionAndStart()
            self.refreshPermissions()
            if granted {
                self.settings.capturePreviews = true
                self.refreshWindows()
            } else {
                PermissionsCenter.shared.openSystemSettings(for: .screenRecording)
            }
        }
    }

    /// Focuses the real window behind a card: brings it forward and closes the
    /// canvas, so you land in the app you were looking at.
    public func focusWindow(for node: CanvasNode) {
        guard let reference = node.windowReference else { return }
        guard hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        if reference.ownerPID > 0 {
            NSRunningApplication(processIdentifier: reference.ownerPID)?.activate(options: [.activateAllWindows])
        }
        ax.raise(windowNumber: reference.windowNumber, pid: reference.ownerPID)
        NSApp.hide(nil)
    }

    /// Moves the real window to match the card's layout position, then hides the
    /// canvas so you can use it.
    public func sendWindowToCanvasPosition(_ node: CanvasNode) {
        guard let reference = node.windowReference else { return }
        guard hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        let mapper = currentDesktopMapper()
        let screen = ScreenGeometry.usableFrame(for: NSScreen.main?.frame ?? .zero)
        let target = mapper.appKitFrame(forCanvas: node.frame, usableScreen: screen)
        ax.animate(
            frames: [reference.windowNumber: target],
            pids: [reference.windowNumber: reference.ownerPID]
        )
        showToast("Moved \(node.displayLabel)", systemImage: "macwindow")
    }

    /// Captures the current desktop as window cards laid out like the real
    /// screens, so the canvas becomes a map you can rearrange.
    public func captureDesktop() {
        guard hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        isCapturingDesktop = true
        let windows = windowDiscovery.manageableWindows()
        guard !windows.isEmpty else {
            isCapturingDesktop = false
            showToast("No windows to capture", systemImage: "macwindow", isError: true)
            return
        }
        record("Capture Desktop")

        let screenRects = NSScreen.screens.compactMap { ScreenGeometry.topLeftRect(fromAppKit: $0.frame) }
        let mapper = DesktopPlaneMapper.fitting(
            screens: screenRects,
            target: visibleCanvasBounds.expandedBy(-40)
        )

        var newIDs: Set<UUID> = []
        for window in windows {
            let topLeft = ScreenGeometry.topLeftRect(fromAppKit: window.frame)
            let canvasFrame = mapper.canvasRect(forDesktopTopLeft: topLeft)
            // Existing cards for the same window are refreshed instead of duplicated.
            if var existing = document.nodes.first(where: { $0.windowReference?.windowNumber == window.windowNumber }) {
                existing.frame = canvasFrame
                existing.title = window.displayTitle
                existing.windowReference = window.reference
                if let index = document.index(of: existing.id) {
                    document.nodes[index] = existing
                }
                continue
            }
            let node = CanvasNode(
                kind: .window,
                frame: canvasFrame,
                title: window.displayTitle,
                text: window.appName,
                style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 12),
                windowReference: window.reference
            )
            document.insertOnTop(node)
            newIDs.insert(node.id)
        }
        selection = newIDs
        isCapturingDesktop = false
        startCapture()
        for node in windowNodes {
            if let number = node.windowReference?.windowNumber {
                capture.requestSnapshot(windowNumber: number, force: true)
            }
        }
        showToast("Captured \(windows.count) windows", systemImage: "square.on.square.dashed")
    }

    /// Lays the real windows out to match the canvas cards, then steps aside.
    public func applyLayoutToDesktop() {
        guard hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        let nodes = windowNodes.compactMap { node -> (CanvasNode, WindowReference)? in
            guard let reference = node.windowReference else { return nil }
            return (node, reference)
        }
        guard !nodes.isEmpty else {
            showToast("Add some window cards first", systemImage: "macwindow", isError: true)
            return
        }
        isApplyingLayout = true
        let mapper = currentDesktopMapper()
        let screen = ScreenGeometry.usableFrame(for: NSScreen.main?.frame ?? .zero)
        var frames: [UInt32: CGRect] = [:]
        var pids: [UInt32: Int32] = [:]
        for (node, reference) in nodes {
            frames[reference.windowNumber] = mapper.appKitFrame(forCanvas: node.frame, usableScreen: screen)
            pids[reference.windowNumber] = reference.ownerPID
        }
        ax.animate(frames: frames, pids: pids) { [weak self] in
            guard let self else { return }
            self.isApplyingLayout = false
            self.showToast("Arranged \(frames.count) windows", systemImage: "rectangle.3.group")
            NSApp.hide(nil)
        }
    }

    public func centerWindow(_ node: CanvasNode) {
        guard let reference = node.windowReference, hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        ax.center(windowNumber: reference.windowNumber, pid: reference.ownerPID)
        showToast("Centered \(node.displayLabel)", systemImage: "scope")
    }

    public func minimizeWindow(_ node: CanvasNode) {
        guard let reference = node.windowReference, hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        ax.minimize(windowNumber: reference.windowNumber, pid: reference.ownerPID)
    }

    public func toggleFullScreenWindow(_ node: CanvasNode) {
        guard let reference = node.windowReference, hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        ax.toggleFullScreen(windowNumber: reference.windowNumber, pid: reference.ownerPID)
    }

    public func closeWindow(_ node: CanvasNode) {
        guard let reference = node.windowReference, hasAccessibility else {
            requestPermission(.accessibility)
            return
        }
        ax.close(windowNumber: reference.windowNumber, pid: reference.ownerPID)
    }

    /// A mapper anchored to the current camera so card positions correspond to
    /// where the windows sit on screen right now.
    public func currentDesktopMapper() -> DesktopPlaneMapper {
        // 1:1 with the canvas at zoom 1, anchored to the camera origin.
        DesktopPlaneMapper(
            scale: 1,
            origin: CanvasPoint(x: -camera.translation.x / camera.zoom, y: -camera.translation.y / camera.zoom)
        )
    }

    // MARK: Export

    public func exportPNG(scale: CGFloat = 2) {
        let bounds = (document.bounds ?? CanvasRect(x: 0, y: 0, width: 1200, height: 800)).insetBy(-80)
        guard bounds.width > 1, bounds.height > 1 else { return }
        let pixelWidth = Int(bounds.width * Double(scale))
        let pixelHeight = Int(bounds.height * Double(scale))
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth < 24000, pixelHeight < 24000 else { return }

        let exportCamera = CanvasTransform(
            translation: CanvasPoint(x: -bounds.minX * Double(scale), y: -bounds.minY * Double(scale)),
            zoom: Double(scale)
        )
        let canvasOptions = CanvasRenderer.Options(
            isDark: document.background.isDark,
            selection: [],
            snapshots: windowSnapshots,
            levelOfDetail: .full,
            gridStyle: document.gridStyle,
            showGrid: settings.showGrid,
            guides: [],
            marquee: nil,
            editingNodeID: nil,
            dimmedNodeIDs: [],
            showSelectionChrome: false
        )

        // NSImage's drawing handler gives us a flipped, AppKit-native context so
        // text and shadows match what is on screen.
        let image = NSImage(size: NSSize(width: bounds.width * scale, height: bounds.height * scale), flipped: true) { rect in
            CanvasRenderer().draw(
                document: self.document,
                camera: exportCamera,
                in: rect.size,
                options: canvasOptions
            )
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            showToast("Export failed", systemImage: "exclamationmark.triangle", isError: true)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(document.name).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
            showToast("Exported PNG", systemImage: "square.and.arrow.up")
        }
    }

    public func exportDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(document.name).sunroom.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportJSON(document, to: url)
                showToast("Exported canvas", systemImage: "square.and.arrow.up")
            } catch {
                showToast("Export failed", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }

    public func importDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported = try store.importJSON(from: url)
                try store.save(imported)
                summaries.insert(imported.canvasSummary, at: 0)
                open(imported)
                showToast("Imported \(imported.name)", systemImage: "square.and.arrow.down")
            } catch {
                showToast("That file isn't a Sunroom canvas", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }

    // MARK: Toast

    public func showToast(_ message: String, systemImage: String = "checkmark.circle", isError: Bool = false) {
        let toast = Toast(message: message, systemImage: systemImage, isError: isError)
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.toast?.id == toast.id { self?.toast = nil }
            }
        }
    }

    // MARK: Persistence

    public func scheduleSave() {
        // The camera lives on the model; keep the document's copy in sync so a
        // reopen lands where the user left off.
        var snapshot = document
        snapshot.transform = camera
        autosave?.schedule(snapshot)
        if let index = summaries.firstIndex(where: { $0.id == document.id }) {
            summaries[index].name = document.name
            summaries[index].nodeCount = document.nodes.count
            summaries[index].updatedAt = document.updatedAt
            summaries[index].background = document.background
        } else {
            summaries.insert(document.canvasSummary, at: 0)
        }
    }

    public func persist(force: Bool = false) {
        var snapshot = document
        snapshot.transform = camera
        if force {
            autosave?.flush(snapshot)
        } else {
            scheduleSave()
        }
    }

    public func flushPendingWrites() {
        persist(force: true)
    }

    // MARK: Services wiring

    private func configureHotKeys() {
        var bindings: [HotKeyCenter.Action: HotKeyCenter.Combo] = [
            .toggleCanvas: settings.hotKey,
            .newNote: HotKeyCenter.Combo(keyCode: 45, modifiers: UInt32(1 << 11) | UInt32(1 << 8)) // ⌃⌥N
        ]
        bindings[.captureDesktop] = nil
        hotKeys.registerAll(bindings)
        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleCanvas:
                self.toggleWindowVisibility()
            case .newNote:
                self.addNote()
            case .captureDesktop:
                self.captureDesktop()
            }
        }
    }

    public func toggleWindowVisibility() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "sunroom.main" }) {
            if window.isVisible && window.isKeyWindow {
                NSApp.hide(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                refreshWindows()
            }
        }
    }

    private func startWindowRefresh() {
        windowRefreshTimer?.invalidate()
        windowRefreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWindows()
            }
        }
        refreshWindows()
    }

    private func observePermissionChanges() {
        captureObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        capture.onSnapshot = { [weak self] windowNumber, snapshot in
            Task { @MainActor in
                self?.windowSnapshots[windowNumber] = snapshot.image
            }
        }
    }

    public func shutdown() {
        flushPendingWrites()
        windowRefreshTimer?.invalidate()
        if let captureObserver { NotificationCenter.default.removeObserver(captureObserver) }
        capture.stop()
    }
}

/// Serializes document writes off the main thread.
enum StoreWriter {
    static let queue = DispatchQueue(label: "com.shashvat1965.sunroom.store", qos: .utility)

    static func write(_ document: CanvasDocument, to store: DocumentFileStore) {
        queue.async {
            try? store.save(document)
        }
    }
}
