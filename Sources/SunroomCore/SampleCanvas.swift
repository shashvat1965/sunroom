import Foundation

/// The canvas a new install opens: a small, curated tour that doubles as the
/// screenshot in the README. Kept in code so it can be tested.
public enum SampleCanvas {

    public static func welcome() -> CanvasDocument {
        var document = CanvasDocument(name: "Welcome to Sunroom", background: .aurora, gridStyle: .dots)

        var hero = CanvasNode(
            kind: .text,
            frame: CanvasRect(x: -520, y: -380, width: 640, height: 220),
            title: "Sunroom",
            text: """
            An infinite canvas for your Mac.

            Pan, zoom, and arrange windows, notes and images on one endless plane.
            Press ⌘K to search. Hold space to drag the world.
            """,
            style: NodeStyle(accent: ColorToken.sunflower.rawValue, fontSize: 17, cornerRadius: 26)
        )
        hero.isLocked = true

        var stickyStart = CanvasNode(
            kind: .note,
            frame: CanvasRect(x: -520, y: -104, width: 300, height: 240),
            title: "Start here",
            text: "Double-click to edit.\nDrag to move. ⌘⏎ to commit.\n⇧⌘F fits everything.",
            style: NodeStyle(accent: ColorToken.apricot.rawValue, fontSize: 15)
        )
        stickyStart.isLocked = false

        var stickyWindows = CanvasNode(
            kind: .note,
            frame: CanvasRect(x: -190, y: -104, width: 300, height: 240),
            title: "Windows, on the canvas",
            text: "Open the Windows panel, then drag any window onto the plane. Click a card to fly the real window to it.",
            style: NodeStyle(accent: ColorToken.sky.rawValue, fontSize: 15)
        )

        var stickyKeys = CanvasNode(
            kind: .note,
            frame: CanvasRect(x: 140, y: -104, width: 300, height: 240),
            title: "Keyboard first",
            text: "Space + drag to pan\n⌘= / ⌘− to zoom\n⌘0 to reset\n⌘K command palette\n⌘⇧N new note",
            style: NodeStyle(accent: ColorToken.mint.rawValue, fontSize: 15)
        )

        var frame = CanvasNode(
            kind: .group,
            frame: CanvasRect(x: -560, y: -140, width: 1040, height: 320),
            title: "A little tour",
            style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 28)
        )

        var footer = CanvasNode(
            kind: .text,
            frame: CanvasRect(x: -520, y: 240, width: 640, height: 90),
            title: "",
            text: "Sunroom is open source. Nothing leaves your Mac.",
            style: NodeStyle(accent: ColorToken.slate.rawValue, fontSize: 13, cornerRadius: 18, opacity: 0.85)
        )

        document.insert(frame, at: 0)
        document.insert(hero)
        document.insert(footer)
        document.insert(stickyStart)
        document.insert(stickyWindows)
        document.insert(stickyKeys)

        stickyStart.groupID = frame.id
        stickyWindows.groupID = frame.id
        stickyKeys.groupID = frame.id
        if let index = document.index(of: stickyStart.id) { document.nodes[index] = stickyStart }
        if let index = document.index(of: stickyWindows.id) { document.nodes[index] = stickyWindows }
        if let index = document.index(of: stickyKeys.id) { document.nodes[index] = stickyKeys }

        document.transform = CanvasTransform(translation: CanvasPoint(x: 720, y: 460), zoom: 1)
        return document
    }

    /// A dense canvas used by performance tests and the "Open sample" command.
    public static func stressTest(nodeCount: Int = 400) -> CanvasDocument {
        var document = CanvasDocument(name: "Stress Test", background: .midnight, gridStyle: .dots)
        let tokens = ColorToken.allCases
        let sizes = [CanvasSize(width: 240, height: 160), CanvasSize(width: 320, height: 220), CanvasSize(width: 200, height: 200)]
        let frames = LayoutEngine.grid(
            sizes: (0..<nodeCount).map { sizes[$0 % sizes.count] },
            spacing: 32
        )
        for index in 0..<nodeCount {
            let node = CanvasNode(
                kind: index % 7 == 0 ? .note : .text,
                frame: frames[index],
                title: "Card \(index + 1)",
                text: "Synthetic card for layout and performance checks.",
                style: NodeStyle(accent: tokens[index % tokens.count].rawValue, fontSize: 13)
            )
            document.insert(node)
        }
        return document
    }
}
