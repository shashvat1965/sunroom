import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

/// Everything the canvas view needs to draw one frame.
public struct CanvasViewState: Equatable {
    public var document: CanvasDocument
    public var camera: CanvasTransform
    public var selection: Set<UUID>
    public var settings: AppSettings
    public var snapshots: [UInt32: NSImage]
    public var levelOfDetail: LevelOfDetail
    public var snapGuides: [SnapGuide]
    public var marquee: CanvasRect?
    public var editingNodeID: UUID?
    public var isDark: Bool
    public var searchQuery: String

    public static func == (lhs: CanvasViewState, rhs: CanvasViewState) -> Bool {
        lhs.document == rhs.document
            && lhs.camera == rhs.camera
            && lhs.selection == rhs.selection
            && lhs.settings == rhs.settings
            && lhs.snapGuides == rhs.snapGuides
            && lhs.marquee == rhs.marquee
            && lhs.editingNodeID == rhs.editingNodeID
            && lhs.isDark == rhs.isDark
            && lhs.levelOfDetail == rhs.levelOfDetail
            && lhs.searchQuery == rhs.searchQuery
            && lhs.snapshots.count == rhs.snapshots.count
    }
}

/// The interactive canvas: a flipped, layer-backed NSView that draws the world
/// and owns every pointer and keyboard affordance.
///
/// It keeps a local copy of the document while a gesture is in flight so
/// dragging stays at display refresh rate, then commits one undoable change on
/// mouse-up. SwiftUI state is authoritative between gestures.
public final class CanvasView: NSView {

    public weak var model: AppModel?
    private let renderer = CanvasRenderer()

    private var state = CanvasViewState(
        document: .empty(),
        camera: .identity,
        selection: [],
        settings: .default,
        snapshots: [:],
        levelOfDetail: .full,
        snapGuides: [],
        marquee: nil,
        editingNodeID: nil,
        isDark: false,
        searchQuery: ""
    )

    // Working document during a gesture.
    private var workingDocument: CanvasDocument?
    private var workingCamera: CanvasTransform

    fileprivate enum DragMode {
        case none
        case pan(startScreen: CanvasPoint, startTranslation: CanvasPoint)
        case move(ids: Set<UUID>, startCanvas: CanvasPoint, originals: [UUID: CanvasRect], didMove: Bool)
        case resize(handle: SelectionHandle, ids: Set<UUID>, startBounds: CanvasRect, originals: [UUID: CanvasRect])
        case marquee(start: CanvasPoint, additive: Bool, base: Set<UUID>)
        case place(tool: AppModel.Tool)
    }

    private var dragMode: DragMode = .none
    private var isSpaceDown = false
    private var trackingAreaRef: NSTrackingArea?
    private var lastCameraPublish = Date.distantPast
    private var didBeginUndo = false

    // MARK: Init

    public override init(frame frameRect: NSRect) {
        workingCamera = .identity
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        workingCamera = .identity
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL])
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var isOpaque: Bool { true }

    // MARK: State

    public func update(state newState: CanvasViewState) {
        let cameraChanged = newState.camera != state.camera
        state = newState
        if dragMode.isIdle {
            workingDocument = nil
            workingCamera = newState.camera
        } else if cameraChanged, case .none = dragMode {
            workingCamera = newState.camera
        }
        needsDisplay = true
    }

    private var document: CanvasDocument {
        workingDocument ?? state.document
    }

    private var camera: CanvasTransform {
        get { workingCamera }
        set { workingCamera = newValue }
    }

    private var visibleRectInCanvas: CanvasRect {
        camera.visibleCanvasRect(in: CanvasSize(bounds.size))
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.imageInterpolation = .high

        var dimmed: Set<UUID> = []
        let trimmedQuery = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            let hits = Set(document.search(trimmedQuery).map(\.id))
            dimmed = Set(document.nodes.map(\.id)).subtracting(hits)
        }

        let options = CanvasRenderer.Options(
            isDark: state.isDark,
            selection: dragMode.isMarquee ? state.selection : state.selection,
            snapshots: state.snapshots,
            levelOfDetail: state.levelOfDetail,
            gridStyle: state.settings.showGrid ? state.document.gridStyle : .none,
            showGrid: state.settings.showGrid,
            guides: state.snapGuides,
            marquee: state.marquee,
            editingNodeID: state.editingNodeID,
            dimmedNodeIDs: dimmed
        )

        renderer.draw(document: document, camera: camera, in: bounds.size, options: options)

        if let toastHint = dragMode.placementHint {
            drawPlacementHint(toastHint)
        }
    }

    private func drawPlacementHint(_ hint: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = (hint as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: bounds.midX - size.width / 2 - 10, y: bounds.maxY - 44, width: size.width + 20, height: 24)
        NSColor.windowBackgroundColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        (hint as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 6), withAttributes: attributes)
    }

    // MARK: Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let screenPoint = CanvasPoint(convert(event.locationInWindow, from: nil))
        let canvasPoint = camera.canvasPoint(fromScreen: screenPoint)
        let modifiers = event.modifierFlags

        if state.editingNodeID != nil {
            commitActiveEdit()
        }

        // Placing a new object with an armed tool.
        if let tool = model?.tool, tool != .select, tool != .pan {
            place(tool: tool, at: canvasPoint)
            return
        }

        if isSpaceDown || model?.tool == .pan || modifiers.contains(.option) {
            dragMode = .pan(startScreen: screenPoint, startTranslation: camera.translation)
            NSCursor.closedHand.set()
            return
        }

        // Selection handles take priority over content.
        if let handle = handleHitTest(screenPoint: screenPoint) {
            beginResize(handle: handle, at: canvasPoint)
            return
        }

        if let node = hitTestNode(at: canvasPoint) {
            let additive = modifiers.contains(.command) || modifiers.contains(.shift)
            if additive {
                var next = state.selection
                if next.contains(node.id) { next.remove(node.id) } else { next.insert(node.id) }
                model?.selection = next
            } else if !state.selection.contains(node.id) {
                model?.selection = [node.id]
            }
            // Frame drag moves its children too.
            var ids = state.selection.isEmpty ? [node.id] : state.selection
            if node.kind == .group {
                ids.formUnion(document.children(of: node.id).map(\.id))
            }
            if node.isLocked {
                dragMode = .none
                return
            }
            beginMove(ids: Set(ids), at: canvasPoint)
            return
        }

        if modifiers.contains(.command) || modifiers.contains(.shift) {
            dragMode = .marquee(start: canvasPoint, additive: true, base: state.selection)
        } else {
            model?.selection = []
            dragMode = .marquee(start: canvasPoint, additive: false, base: [])
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let screenPoint = CanvasPoint(convert(event.locationInWindow, from: nil))
        let canvasPoint = camera.canvasPoint(fromScreen: screenPoint)
        let modifiers = event.modifierFlags

        switch dragMode {
        case .none:
            break

        case .pan(let startScreen, let startTranslation):
            let delta = CanvasPoint(x: screenPoint.x - startScreen.x, y: screenPoint.y - startScreen.y)
            camera = CanvasTransform(translation: startTranslation + delta, zoom: camera.zoom)
            publishCameraIfNeeded(force: true)

        case .move(let ids, let startCanvas, let originals, _):
            var delta = CanvasPoint(x: canvasPoint.x - startCanvas.x, y: canvasPoint.y - startCanvas.y)
            if modifiers.contains(.shift) {
                if abs(delta.x) > abs(delta.y) { delta.y = 0 } else { delta.x = 0 }
            }

            // Snap the selection bounds against everything not being dragged.
            let movingBounds = CanvasRect.bounding(originals.values.map { $0.offsetBy(delta) }) ?? .zero
            let targets = document.nodes
                .filter { !ids.contains($0.id) && $0.kind != .group }
                .map(\.frame)
            var snapped = movingBounds.origin
            if state.settings.snapEnabled {
                let result = Snapping.snap(
                    rect: movingBounds,
                    targets: targets,
                    configuration: SnapConfiguration(
                        tolerance: 7 / camera.zoom,
                        snapToGrid: state.settings.snapToGrid,
                        gridSpacing: document.gridSpacing
                    )
                )
                snapped = result.adjustedOrigin
                model?.snapGuides = result.guides
            }
            delta = CanvasPoint(x: delta.x + (snapped.x - movingBounds.minX), y: delta.y + (snapped.y - movingBounds.minY))

            var doc = document
            for (id, original) in originals {
                if let index = doc.index(of: id) {
                    doc.nodes[index].frame = original.offsetBy(delta)
                }
            }
            workingDocument = doc
            dragMode = .move(ids: ids, startCanvas: startCanvas, originals: originals, didMove: true)
            needsDisplay = true

        case .resize(let handle, let ids, let startBounds, let originals):
            var newBounds = startBounds
            if handle.movesLeft { newBounds = newBounds.withMinX(min(canvasPoint.x, newBounds.maxX - 40)) }
            if handle.movesRight { newBounds = newBounds.withMaxX(max(canvasPoint.x, newBounds.minX + 40)) }
            if handle.movesTop { newBounds = newBounds.withMinY(min(canvasPoint.y, newBounds.maxY - 32)) }
            if handle.movesBottom { newBounds = newBounds.withMaxY(max(canvasPoint.y, newBounds.minY + 32)) }

            let scaleX = startBounds.width == 0 ? 1 : newBounds.width / startBounds.width
            let scaleY = startBounds.height == 0 ? 1 : newBounds.height / startBounds.height
            var doc = document
            for (id, original) in originals {
                guard let index = doc.index(of: id) else { continue }
                let relativeX = (original.minX - startBounds.minX) * scaleX
                let relativeY = (original.minY - startBounds.minY) * scaleY
                let frame = CanvasRect(
                    x: newBounds.minX + relativeX,
                    y: newBounds.minY + relativeY,
                    width: max(24, original.width * scaleX),
                    height: max(24, original.height * scaleY)
                )
                doc.nodes[index].frame = frame
            }
            workingDocument = doc
            dragMode = .resize(handle: handle, ids: ids, startBounds: startBounds, originals: originals)
            needsDisplay = true

        case .marquee(let start, let additive, let base):
            let rect = CanvasRect(corner: start, corner: canvasPoint)
            model?.marqueeRect = rect
            let hit = document.ids(fullyInside: rect)
            model?.selection = additive ? base.union(hit) : hit
            needsDisplay = true

        case .place(let tool):
            _ = tool
            break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .move(let ids, _, _, let didMove):
            if didMove, let doc = workingDocument, !ids.isEmpty {
                model?.commitInteractiveEdit(document: doc, label: "Move")
            }
        case .resize:
            if let doc = workingDocument {
                model?.commitInteractiveEdit(document: doc, label: "Resize")
            }
        case .marquee:
            model?.marqueeRect = nil
        case .pan:
            publishCameraIfNeeded(force: true)
        case .none, .place:
            break
        }
        model?.snapGuides = []
        workingDocument = nil
        dragMode = .none
        NSCursor.arrow.set()
        needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        let screenPoint = CanvasPoint(convert(event.locationInWindow, from: nil))
        if handleHitTest(screenPoint: screenPoint) != nil {
            NSCursor.crosshair.set()
            return
        }
        let canvasPoint = camera.canvasPoint(fromScreen: screenPoint)
        if let node = hitTestNode(at: canvasPoint) {
            if node.kind == .window { NSCursor.pointingHand.set() } else { NSCursor.openHand.set() }
        } else {
            NSCursor.arrow.set()
        }
    }

    public override func otherMouseDown(with event: NSEvent) {
        // Middle-button pan, the way every canvas app pans.
        let screenPoint = CanvasPoint(convert(event.locationInWindow, from: nil))
        dragMode = .pan(startScreen: screenPoint, startTranslation: camera.translation)
        NSCursor.closedHand.set()
    }

    public override func otherMouseDragged(with event: NSEvent) {
        guard case .pan(let startScreen, let startTranslation) = dragMode else { return }
        let screenPoint = CanvasPoint(convert(event.locationInWindow, from: nil))
        let delta = CanvasPoint(x: screenPoint.x - startScreen.x, y: screenPoint.y - startScreen.y)
        camera = CanvasTransform(translation: startTranslation + delta, zoom: camera.zoom)
        publishCameraIfNeeded(force: true)
        needsDisplay = true
    }

    public override func otherMouseUp(with event: NSEvent) {
        if case .pan = dragMode {
            model?.camera = camera
            NSCursor.arrow.set()
            dragMode = .none
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        let screenPoint = CanvasPoint(convert(event.locationInWindow, from: nil))
        let canvasPoint = camera.canvasPoint(fromScreen: screenPoint)
        if let node = hitTestNode(at: canvasPoint) {
            if !state.selection.contains(node.id) {
                model?.selection = [node.id]
            }
            let menu = ContextMenuBuilder.menu(for: node, model: model)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            let menu = ContextMenuBuilder.canvasMenu(model: model, at: canvasPoint)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let factor = 1 + Double(event.scrollingDeltaY) * 0.012
            let anchor = CanvasPoint(convert(event.locationInWindow, from: nil))
            camera = camera.zooming(by: max(0.5, min(1.8, factor)), anchor: anchor)
            publishCameraIfNeeded()
            needsDisplay = true
            return
        }
        // Trackpad two-finger scroll pans; shift swaps axes like every other
        // canvas app.
        var dx = Double(event.scrollingDeltaX)
        var dy = Double(event.scrollingDeltaY)
        if event.modifierFlags.contains(.shift) { swap(&dx, &dy) }
        let sensitivity = event.hasPreciseScrollingDeltas ? 1.0 : 8.0
        camera = camera.panning(by: CanvasPoint(x: dx * sensitivity, y: dy * sensitivity))
        publishCameraIfNeeded()
        needsDisplay = true
    }

    public override func magnify(with event: NSEvent) {
        let anchor = CanvasPoint(convert(event.locationInWindow, from: nil))
        camera = camera.zooming(by: 1 + Double(event.magnification), anchor: anchor)
        publishCameraIfNeeded()
        needsDisplay = true
    }

    public override func smartMagnify(with event: NSEvent) {
        let point = CanvasPoint(convert(event.locationInWindow, from: nil))
        let canvasPoint = camera.canvasPoint(fromScreen: point)
        if let node = hitTestNode(at: canvasPoint) {
            model?.fitSelection()
            model?.selection = [node.id]
            if let node = document.node(withID: node.id) {
                model?.camera = camera.centering(on: node.frame.center, in: CanvasSize(bounds.size))
            }
        } else {
            model?.fitAll()
        }
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 49: // space
            if !isSpaceDown {
                isSpaceDown = true
                NSCursor.openHand.set()
            }
            return
        case 53: // escape
            if !state.selection.isEmpty {
                model?.selection = []
            } else {
                model?.searchQuery = ""
            }
            needsDisplay = true
            return
        case 51, 117: // delete / forward delete
            model?.deleteSelection()
            return
        case 36, 76: // return / enter
            if let first = state.selection.first, let node = document.node(withID: first) {
                if node.kind.isTextual {
                    model?.editingNodeID = node.id
                } else if node.kind == .window {
                    model?.focusWindow(for: node)
                }
            }
            return
        case 48: // tab
            cycleSelection(backwards: event.modifierFlags.contains(.shift))
            return
        case 123, 124, 125, 126: // arrows
            let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
            switch event.keyCode {
            case 123: model?.nudge(dx: -step, dy: 0)
            case 124: model?.nudge(dx: step, dy: 0)
            case 125: model?.nudge(dx: 0, dy: step)
            case 126: model?.nudge(dx: 0, dy: -step)
            default: break
            }
            return
        default:
            break
        }
        if command {
            super.keyDown(with: event)
            return
        }
        // Type to search, the way a canvas should behave.
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            model?.searchQuery += characters
            model?.isSearchFocused = true
            return
        }
        super.keyDown(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceDown = false
            NSCursor.arrow.set()
            return
        }
        super.keyUp(with: event)
    }

    public override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            // Ctrl-drag is reserved for a future precision mode; keep cursor sane.
        }
        super.flagsChanged(with: event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event)
    }

    private func cycleSelection(backwards: Bool) {
        let ids = document.nodes.map(\.id)
        guard !ids.isEmpty else { return }
        if let current = state.selection.first, let index = ids.firstIndex(of: current) {
            let next = backwards ? (index - 1 + ids.count) % ids.count : (index + 1) % ids.count
            model?.selection = [ids[next]]
        } else {
            model?.selection = [ids[0]]
        }
    }

    // MARK: Cursor rects

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    // MARK: Drag & drop

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp", "pdf"]
        var handled = false
        for url in urls where imageExtensions.contains(url.pathExtension.lowercased()) {
            model?.addImage(from: url)
            handled = true
        }
        return handled
    }

    // MARK: Hit testing

    private func hitTestNode(at point: CanvasPoint) -> CanvasNode? {
        // Topmost first; frames are containers and only hit their header band so
        // you can still grab the canvas inside them.
        for node in document.nodes.reversed() {
            if node.kind == .group {
                let headerBand = CanvasRect(x: node.frame.minX, y: node.frame.minY - 22 / camera.zoom, width: node.frame.width, height: 26 / camera.zoom)
                if headerBand.contains(point) { return node }
                continue
            }
            if node.frame.contains(point) { return node }
        }
        return nil
    }

    private func handleHitTest(screenPoint: CanvasPoint) -> SelectionHandle? {
        guard !state.selection.isEmpty, let bounds = document.bounds(of: state.selection) else { return nil }
        let threshold = 9.0
        for handle in SelectionHandle.allCases {
            let point = camera.screenPoint(fromCanvas: CanvasPoint(handle.point(in: bounds.cgRect)))
            if abs(point.x - screenPoint.x) <= threshold, abs(point.y - screenPoint.y) <= threshold {
                return handle
            }
        }
        return nil
    }

    // MARK: Gesture setup

    private func beginMove(ids: Set<UUID>, at point: CanvasPoint) {
        var originals: [UUID: CanvasRect] = [:]
        for node in document.nodes where ids.contains(node.id) {
            originals[node.id] = node.frame
        }
        dragMode = .move(ids: ids, startCanvas: point, originals: originals, didMove: false)
        NSCursor.closedHand.set()
    }

    private func beginResize(handle: SelectionHandle, at point: CanvasPoint) {
        guard let bounds = document.bounds(of: state.selection) else { return }
        var originals: [UUID: CanvasRect] = [:]
        for node in document.nodes where state.selection.contains(node.id) {
            originals[node.id] = node.frame
        }
        dragMode = .resize(handle: handle, ids: state.selection, startBounds: bounds, originals: originals)
        _ = point
    }

    private func place(tool: AppModel.Tool, at point: CanvasPoint) {
        switch tool {
        case .note: model?.addNote(at: point)
        case .text: model?.addText(at: point)
        case .frame: model?.addFrame(at: point)
        case .select, .pan: break
        }
    }

    private func commitActiveEdit() {
        model?.editingNodeID = nil
    }

    private func publishCameraIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastCameraPublish) > 1.0 / 30.0 else { return }
        lastCameraPublish = now
        model?.camera = camera
    }
}

// MARK: - DragMode helpers

fileprivate extension CanvasView.DragMode {
    var isIdle: Bool {
        if case .none = self { return true }
        return false
    }

    var isMarquee: Bool {
        if case .marquee = self { return true }
        return false
    }

    var placementHint: String? {
        nil
    }
}

// MARK: - SwiftUI bridge

public struct CanvasSurface: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var isDark: Bool

    public init(model: AppModel, isDark: Bool) {
        self.model = model
        self.isDark = isDark
    }

    public func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.model = model
        MenuActionRouter.model = model
        return view
    }

    public func updateNSView(_ view: CanvasView, context: Context) {
        view.model = model
        view.update(
            state: CanvasViewState(
                document: model.document,
                camera: model.camera,
                selection: model.selection,
                settings: model.settings,
                snapshots: model.windowSnapshots,
                levelOfDetail: model.levelOfDetail,
                snapGuides: model.snapGuides,
                marquee: model.marqueeRect,
                editingNodeID: model.editingNodeID,
                isDark: isDark,
                searchQuery: model.searchQuery
            )
        )
    }
}
