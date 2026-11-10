import Foundation

// MARK: - Node kind

public enum NodeKind: String, Codable, CaseIterable, Sendable {
    case note
    case text
    case image
    case link
    case window
    case group
    case shape

    /// Human label used by menus, the inspector and the command palette.
    public var displayName: String {
        switch self {
        case .note: return "Note"
        case .text: return "Text Card"
        case .image: return "Image"
        case .link: return "Link"
        case .window: return "Window"
        case .group: return "Frame"
        case .shape: return "Shape"
        }
    }

    public var symbolName: String {
        switch self {
        case .note: return "note.text"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .window: return "macwindow"
        case .group: return "rectangle.dashed"
        case .shape: return "square.on.circle"
        }
    }

    /// Frames and images are containers: they sit behind their contents.
    public var isContainer: Bool {
        self == .group
    }

    /// Whether double-clicking opens an inline editor.
    public var isTextual: Bool {
        self == .note || self == .text
    }

    /// Whether the node can host a live snapshot.
    public var isSnapshotable: Bool {
        self == .window || self == .image || self == .link
    }
}

// MARK: - Window reference

/// A stable-ish pointer at a real macOS window that this node mirrors.
public struct WindowReference: Codable, Hashable, Sendable {
    public var windowNumber: UInt32
    public var ownerPID: Int32
    public var bundleIdentifier: String?
    public var appName: String
    public var windowTitle: String

    public init(
        windowNumber: UInt32,
        ownerPID: Int32,
        bundleIdentifier: String? = nil,
        appName: String,
        windowTitle: String
    ) {
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

// MARK: - Style

public struct NodeStyle: Codable, Hashable, Sendable {
    public var accent: String
    public var fill: String?
    public var textColor: String?
    public var fontSize: Double
    public var cornerRadius: Double
    public var opacity: Double
    public var imageContentMode: String

    public init(
        accent: String = ColorToken.sunflower.rawValue,
        fill: String? = nil,
        textColor: String? = nil,
        fontSize: Double = 15,
        cornerRadius: Double = 18,
        opacity: Double = 1,
        imageContentMode: String = "fit"
    ) {
        self.accent = accent
        self.fill = fill
        self.textColor = textColor
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.imageContentMode = imageContentMode
    }

    public static let `default` = NodeStyle()
}

// MARK: - Node

public struct CanvasNode: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: NodeKind
    public var frame: CanvasRect
    public var title: String
    public var text: String
    public var style: NodeStyle
    public var linkURL: String?
    public var imageAssetName: String?
    public var windowReference: WindowReference?
    public var groupID: UUID?
    public var isLocked: Bool
    public var isCollapsed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: NodeKind,
        frame: CanvasRect,
        title: String = "",
        text: String = "",
        style: NodeStyle = .default,
        linkURL: String? = nil,
        imageAssetName: String? = nil,
        windowReference: WindowReference? = nil,
        groupID: UUID? = nil,
        isLocked: Bool = false,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame.standardized
        self.title = title
        self.text = text
        self.style = style
        self.linkURL = linkURL
        self.imageAssetName = imageAssetName
        self.windowReference = windowReference
        self.groupID = groupID
        self.isLocked = isLocked
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The string used by search and the outline.
    public var searchableText: String {
        [title, text, windowReference?.appName, windowReference?.windowTitle, linkURL]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Short label for the minimap, outline and accessibility.
    public var displayLabel: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if let reference = windowReference { return reference.windowTitle.isEmpty ? reference.appName : reference.windowTitle }
        if let linkURL, let url = URL(string: linkURL), let host = url.host, !host.isEmpty { return host }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.displayName : String(trimmed.prefix(60))
    }

    public var isResizable: Bool { kind != .window && !isLocked }

    public mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Background & grid

public enum CanvasBackground: String, Codable, CaseIterable, Sendable {
    case aurora
    case dawn
    case graphite
    case midnight
    case paper

    public var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .dawn: return "Dawn"
        case .graphite: return "Graphite"
        case .midnight: return "Midnight"
        case .paper: return "Paper"
        }
    }

    public var isDark: Bool {
        self == .graphite || self == .midnight
    }
}

public enum GridStyle: String, Codable, CaseIterable, Sendable {
    case dots
    case lines
    case none

    public var displayName: String {
        switch self {
        case .dots: return "Dots"
        case .lines: return "Lines"
        case .none: return "None"
        }
    }
}

// MARK: - Document

public struct CanvasDocument: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var nodes: [CanvasNode]
    public var transform: CanvasTransform
    public var background: CanvasBackground
    public var gridStyle: GridStyle
    public var gridSpacing: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Canvas",
        nodes: [CanvasNode] = [],
        transform: CanvasTransform = .identity,
        background: CanvasBackground = .aurora,
        gridStyle: GridStyle = .dots,
        gridSpacing: Double = 48,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String = ""
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.nodes = nodes
        self.transform = transform
        self.background = background
        self.gridStyle = gridStyle
        self.gridSpacing = max(8, gridSpacing)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
    }

    public static func empty(named name: String = "Untitled Canvas") -> CanvasDocument {
        CanvasDocument(name: name)
    }

    // MARK: Queries

    public func node(withID id: UUID) -> CanvasNode? {
        nodes.first { $0.id == id }
    }

    public func index(of id: UUID) -> Int? {
        nodes.firstIndex { $0.id == id }
    }

    public var bounds: CanvasRect? {
        CanvasRect.bounding(nodes.map(\.frame))
    }

    /// Nodes in painting order: frames first, then everything else, each group
    /// preserving relative order.
    public var paintOrder: [CanvasNode] {
        let containers = nodes.enumerated().filter { $0.element.kind.isContainer }
        let rest = nodes.enumerated().filter { !$0.element.kind.isContainer }
        return (containers + rest).map(\.element)
    }

    /// Topmost node containing `point`, matching the painting order semantics
    /// (later nodes win).
    public func hitTest(_ point: CanvasPoint, includingLocked: Bool = false) -> CanvasNode? {
        for node in nodes.reversed() where includingLocked || !node.isLocked {
            if node.frame.contains(point) { return node }
        }
        return nil
    }

    public func nodes(intersecting rect: CanvasRect, includingLocked: Bool = true) -> [CanvasNode] {
        nodes.filter { $0.frame.intersects(rect) && (includingLocked || !$0.isLocked) }
    }

    public func children(of groupID: UUID) -> [CanvasNode] {
        nodes.filter { $0.groupID == groupID }
    }

    public var canvasSummary: CanvasSummary {
        CanvasSummary(
            id: id,
            name: name,
            nodeCount: nodes.count,
            updatedAt: updatedAt,
            background: background,
            previewBounds: bounds
        )
    }
}

// MARK: - Summary

/// Lightweight record for the sidebar so listing canvases does not decode every node.
public struct CanvasSummary: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var nodeCount: Int
    public var updatedAt: Date
    public var background: CanvasBackground
    public var previewBounds: CanvasRect?

    public init(
        id: UUID,
        name: String,
        nodeCount: Int,
        updatedAt: Date,
        background: CanvasBackground,
        previewBounds: CanvasRect? = nil
    ) {
        self.id = id
        self.name = name
        self.nodeCount = nodeCount
        self.updatedAt = updatedAt
        self.background = background
        self.previewBounds = previewBounds
    }
}

// MARK: - Color tokens

/// Canvas colors are stored as token names, not hex, so a theme change or an
/// accessibility pass restyles every document without migration.
public enum ColorToken: String, Codable, CaseIterable, Sendable {
    case sunflower
    case apricot
    case rose
    case lilac
    case sky
    case mint
    case sand
    case slate
    case graphite

    public var displayName: String {
        switch self {
        case .sunflower: return "Sunflower"
        case .apricot: return "Apricot"
        case .rose: return "Rose"
        case .lilac: return "Lilac"
        case .sky: return "Sky"
        case .mint: return "Mint"
        case .sand: return "Sand"
        case .slate: return "Slate"
        case .graphite: return "Graphite"
        }
    }
}
