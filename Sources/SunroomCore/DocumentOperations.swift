import Foundation

// MARK: - Document editing primitives
//
// These are pure value-type operations. The app wraps them in an undo stack;
// tests call them directly. Keeping them here (rather than in views) is what
// makes the editor testable without a window server.

public extension CanvasDocument {

    // MARK: Insertion

    @discardableResult
    mutating func insert(_ node: CanvasNode, at index: Int? = nil) -> UUID {
        var newNode = node
        newNode.touch()
        if let index, index >= 0, index <= nodes.count {
            nodes.insert(newNode, at: index)
        } else {
            nodes.append(newNode)
        }
        touch()
        return newNode.id
    }

    /// Inserts a node on top of everything else. Containers are painted first
    /// regardless of array position, so appending is the correct top of stack.
    @discardableResult
    mutating func insertOnTop(_ node: CanvasNode) -> UUID {
        insert(node)
    }

    @discardableResult
    mutating func remove(ids: Set<UUID>) -> [CanvasNode] {
        guard !ids.isEmpty else { return [] }
        let removed = nodes.filter { ids.contains($0.id) }
        nodes.removeAll { ids.contains($0.id) }
        // Re-parent orphans out of deleted groups.
        for index in nodes.indices {
            if let groupID = nodes[index].groupID, ids.contains(groupID) {
                nodes[index].groupID = nil
            }
        }
        touch()
        return removed
    }

    @discardableResult
    mutating func remove(id: UUID) -> CanvasNode? {
        remove(ids: [id]).first
    }

    // MARK: Movement

    mutating func move(ids: Set<UUID>, by delta: CanvasPoint) {
        guard !ids.isEmpty, delta != .zero else { return }
        for index in nodes.indices where ids.contains(nodes[index].id) && !nodes[index].isLocked {
            nodes[index].frame = nodes[index].frame.offsetBy(delta)
            nodes[index].touch()
        }
        touch()
    }

    mutating func setFrame(id: UUID, to frame: CanvasRect) {
        guard let index = index(of: id) else { return }
        nodes[index].frame = frame.standardized
        nodes[index].touch()
        touch()
    }

    mutating func resize(id: UUID, to frame: CanvasRect, minimum: CanvasSize = CanvasSize(width: 60, height: 44)) {
        guard let index = index(of: id), !nodes[index].isLocked else { return }
        var newFrame = frame.standardized
        if newFrame.width < minimum.width { newFrame.size.width = minimum.width }
        if newFrame.height < minimum.height { newFrame.size.height = minimum.height }
        nodes[index].frame = newFrame
        nodes[index].touch()
        touch()
    }

    mutating func nudge(ids: Set<UUID>, dx: Double, dy: Double) {
        move(ids: ids, by: CanvasPoint(x: dx, y: dy))
    }

    // MARK: Z-order

    mutating func bringToFront(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let moved = nodes.filter { ids.contains($0.id) }
        nodes.removeAll { ids.contains($0.id) }
        nodes.append(contentsOf: moved)
        touch()
    }

    mutating func sendToBack(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let moved = nodes.filter { ids.contains($0.id) }
        nodes.removeAll { ids.contains($0.id) }
        nodes.insert(contentsOf: moved, at: 0)
        touch()
    }

    mutating func bringForward(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var i = nodes.count - 2
        while i >= 0 {
            if ids.contains(nodes[i].id) && !ids.contains(nodes[i + 1].id) {
                nodes.swapAt(i, i + 1)
            }
            i -= 1
        }
        touch()
    }

    mutating func sendBackward(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var i = 1
        while i < nodes.count {
            if ids.contains(nodes[i].id) && !ids.contains(nodes[i - 1].id) {
                nodes.swapAt(i, i - 1)
            }
            i += 1
        }
        touch()
    }

    // MARK: Alignment

    enum Alignment: String, CaseIterable, Sendable {
        case left, centerHorizontal, right, top, centerVertical, bottom

        public var displayName: String {
            switch self {
            case .left: return "Align Left"
            case .centerHorizontal: return "Align Center"
            case .right: return "Align Right"
            case .top: return "Align Top"
            case .centerVertical: return "Align Middle"
            case .bottom: return "Align Bottom"
            }
        }

        public var symbolName: String {
            switch self {
            case .left: return "align.horizontal.left"
            case .centerHorizontal: return "align.horizontal.center"
            case .right: return "align.horizontal.right"
            case .top: return "align.vertical.top"
            case .centerVertical: return "align.vertical.center"
            case .bottom: return "align.vertical.bottom"
            }
        }
    }

    mutating func align(ids: Set<UUID>, to alignment: Alignment, relativeTo reference: CanvasRect? = nil) {
        let selected = nodes.filter { ids.contains($0.id) && !$0.isLocked }
        guard !selected.isEmpty else { return }
        let target = reference ?? CanvasRect.bounding(selected.map(\.frame)) ?? .zero
        for node in selected {
            guard let index = index(of: node.id) else { continue }
            var frame = node.frame
            switch alignment {
            // Alignment moves objects; it must never resize them. (Using the
            // edge-setting helpers here would stretch the node instead.)
            case .left: frame = frame.offsetBy(dx: target.minX - frame.minX, dy: 0)
            case .centerHorizontal: frame = frame.offsetBy(dx: target.center.x - frame.center.x, dy: 0)
            case .right: frame = frame.offsetBy(dx: target.maxX - frame.maxX, dy: 0)
            case .top: frame = frame.offsetBy(dx: 0, dy: target.minY - frame.minY)
            case .centerVertical: frame = frame.offsetBy(dx: 0, dy: target.center.y - frame.center.y)
            case .bottom: frame = frame.offsetBy(dx: 0, dy: target.maxY - frame.maxY)
            }
            nodes[index].frame = frame
            nodes[index].touch()
        }
        touch()
    }

    /// Spreads the selection so gaps between neighbours are equal along an axis.
    mutating func distribute(ids: Set<UUID>, horizontally: Bool, gap: Double? = nil) {
        var selected = nodes.filter { ids.contains($0.id) && !$0.isLocked }
        guard selected.count >= 2 else { return }
        selected.sort { lhs, rhs in
            horizontally ? lhs.frame.minX < rhs.frame.minX : lhs.frame.minY < rhs.frame.minY
        }
        let start = horizontally ? selected[0].frame.minX : selected[0].frame.minY
        let end = horizontally ? selected[selected.count - 1].frame.maxX : selected[selected.count - 1].frame.maxY
        let totalSize = selected.reduce(0) { $0 + (horizontally ? $1.frame.width : $1.frame.height) }
        let computedGap = gap ?? max(0, (end - start - totalSize) / Double(selected.count - 1))
        var cursor = start
        for node in selected {
            guard let index = index(of: node.id) else { continue }
            var frame = node.frame
            if horizontally {
                frame = frame.offsetBy(dx: cursor - frame.minX, dy: 0)
                cursor += frame.width + computedGap
            } else {
                frame = frame.offsetBy(dx: 0, dy: cursor - frame.minY)
                cursor += frame.height + computedGap
            }
            nodes[index].frame = frame
            nodes[index].touch()
        }
        touch()
    }

    // MARK: Grouping

    /// Creates a frame around the selection and parents the selected nodes to it.
    @discardableResult
    mutating func group(ids: Set<UUID>, title: String = "Frame") -> UUID? {
        let selected = nodes.filter { ids.contains($0.id) }
        guard selected.count >= 1, let bounds = CanvasRect.bounding(selected.map(\.frame)) else { return nil }
        let expanded = bounds.insetBy(-32)
        let groupNode = CanvasNode(
            kind: .group,
            frame: expanded,
            title: title,
            style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 24)
        )
        nodes.insert(groupNode, at: 0)
        for node in selected {
            guard let index = index(of: node.id) else { continue }
            nodes[index].groupID = groupNode.id
            nodes[index].touch()
        }
        touch()
        return groupNode.id
    }

    /// Removes the group frame but keeps its contents in place.
    mutating func ungroup(ids: Set<UUID>) {
        let groupIDs = Set(nodes.filter { ids.contains($0.id) && $0.kind == .group }.map(\.id))
        guard !groupIDs.isEmpty else { return }
        for index in nodes.indices {
            if let groupID = nodes[index].groupID, groupIDs.contains(groupID) {
                nodes[index].groupID = nil
                nodes[index].touch()
            }
        }
        nodes.removeAll { groupIDs.contains($0.id) }
        touch()
    }

    /// Re-parents every node inside the frame's bounds to that frame.
    mutating func adoptContainedNodes(inFrame id: UUID) {
        guard let frame = node(withID: id), frame.kind == .group else { return }
        let bounds = frame.frame.insetBy(-1)
        for index in nodes.indices where nodes[index].id != id && nodes[index].groupID == nil {
            if bounds.encloses(nodes[index].frame) {
                nodes[index].groupID = id
            }
        }
        touch()
    }

    // MARK: Duplication

    @discardableResult
    mutating func duplicate(ids: Set<UUID>, offset: CanvasPoint = CanvasPoint(x: 28, y: 28)) -> Set<UUID> {
        let originals = nodes.filter { ids.contains($0.id) }
        guard !originals.isEmpty else { return [] }
        var mapping: [UUID: UUID] = [:]
        var newIDs: Set<UUID> = []
        for original in originals {
            let newID = UUID()
            mapping[original.id] = newID
            newIDs.insert(newID)
        }
        var copies: [CanvasNode] = []
        for original in originals {
            var copy = original
            copy.id = mapping[original.id] ?? UUID()
            copy.frame = original.frame.offsetBy(offset)
            copy.title = original.title.isEmpty ? "" : "\(original.title) Copy"
            copy.createdAt = Date()
            copy.updatedAt = Date()
            copy.isLocked = false
            if let groupID = original.groupID, let mapped = mapping[groupID] {
                copy.groupID = mapped
            } else if let groupID = original.groupID, !ids.contains(groupID) {
                copy.groupID = groupID
            }
            copies.append(copy)
        }
        nodes.append(contentsOf: copies)
        touch()
        return newIDs
    }

    // MARK: Properties

    mutating func rename(id: UUID, title: String) {
        guard let index = index(of: id) else { return }
        nodes[index].title = title
        nodes[index].touch()
        touch()
    }

    mutating func setText(id: UUID, text: String) {
        guard let index = index(of: id) else { return }
        nodes[index].text = text
        nodes[index].touch()
        touch()
    }

    mutating func setStyle(id: UUID, style: NodeStyle) {
        guard let index = index(of: id) else { return }
        nodes[index].style = style
        nodes[index].touch()
        touch()
    }

    mutating func setAccent(ids: Set<UUID>, accent: ColorToken) {
        for index in nodes.indices where ids.contains(nodes[index].id) {
            nodes[index].style.accent = accent.rawValue
            nodes[index].touch()
        }
        touch()
    }

    mutating func toggleLock(ids: Set<UUID>) {
        let allLocked = nodes.filter { ids.contains($0.id) }.allSatisfy(\.isLocked)
        for index in nodes.indices where ids.contains(nodes[index].id) {
            nodes[index].isLocked = !allLocked
            nodes[index].touch()
        }
        touch()
    }

    mutating func toggleCollapse(id: UUID) {
        guard let index = index(of: id) else { return }
        nodes[index].isCollapsed.toggle()
        nodes[index].touch()
        touch()
    }

    // MARK: Housekeeping

    mutating func touch() {
        updatedAt = Date()
    }

    /// Size-aware migration hook. Unknown/newer fields are ignored by Codable,
    /// older documents get sensible defaults.
    mutating func migrateIfNeeded() {
        if schemaVersion < 1 {
            schemaVersion = 1
        }
        if gridSpacing < 16 { gridSpacing = 48 }
        if transform.zoom < CanvasTransform.minZoom || transform.zoom > CanvasTransform.maxZoom {
            transform.zoom = 1
        }
        for index in nodes.indices {
            nodes[index].frame = nodes[index].frame.standardized
            if nodes[index].style.opacity <= 0 { nodes[index].style.opacity = 1 }
        }
    }

    /// Total selection bounds, or nil when empty.
    func bounds(of ids: Set<UUID>) -> CanvasRect? {
        CanvasRect.bounding(nodes.filter { ids.contains($0.id) }.map(\.frame))
    }

    /// Ids of all nodes fully inside `rect` (marquee semantics).
    func ids(fullyInside rect: CanvasRect) -> Set<UUID> {
        Set(nodes.filter { rect.encloses($0.frame) }.map(\.id))
    }

    /// Ids of nodes touching `rect` (loose marquee, used for touch/pen input).
    func ids(touching rect: CanvasRect) -> Set<UUID> {
        Set(nodes.filter { rect.intersects($0.frame) }.map(\.id))
    }
}
