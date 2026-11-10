import Foundation

/// The canvas a new install opens: a small, curated tour that doubles as the
/// screenshot in the README. Kept in code so it can be tested.
public enum SampleCanvas {

    public static func welcome() -> CanvasDocument {
        var document = CanvasDocument(name: "Welcome to Sunroom", background: .aurora, gridStyle: .dots)

        let hero = CanvasNode(
            kind: .text,
            frame: CanvasRect(x: -640, y: -430, width: 660, height: 156),
            title: "Sunroom",
            text: "An infinite canvas for your Mac.\nWindows, notes and images on one endless plane.",
            style: NodeStyle(accent: ColorToken.sunflower.rawValue, fontSize: 16, cornerRadius: 24)
        )

        let link = CanvasNode(
            kind: .link,
            frame: CanvasRect(x: -640, y: -216, width: 660, height: 92),
            title: "github.com/shashvat1965/sunroom",
            text: "https://github.com/shashvat1965/sunroom",
            style: NodeStyle(accent: ColorToken.sky.rawValue, cornerRadius: 16),
            linkURL: "https://github.com/shashvat1965/sunroom"
        )

        let window = CanvasNode(
            kind: .window,
            frame: CanvasRect(x: 400, y: -430, width: 380, height: 306),
            title: "Design notes — Safari",
            text: "Safari",
            style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 12),
            windowReference: WindowReference(
                windowNumber: 0,
                ownerPID: 0,
                bundleIdentifier: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Design notes"
            )
        )

        let frame = CanvasNode(
            kind: .group,
            frame: CanvasRect(x: -660, y: -70, width: 1084, height: 244),
            title: "A little tour",
            style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 26)
        )

        let stickyStart = CanvasNode(
            kind: .note,
            frame: CanvasRect(x: -622, y: -10, width: 316, height: 170),
            title: "Start here",
            text: "Double-click to edit.\nDrag to move.\n⇧⌘F fits everything.",
            style: NodeStyle(accent: ColorToken.apricot.rawValue, fontSize: 15)
        )

        let stickyWindows = CanvasNode(
            kind: .note,
            frame: CanvasRect(x: -276, y: -10, width: 316, height: 170),
            title: "Windows",
            text: "Drag a window onto the plane.\nClick a card to fly to it.\nCards stay live.",
            style: NodeStyle(accent: ColorToken.sky.rawValue, fontSize: 15)
        )

        let stickyKeys = CanvasNode(
            kind: .note,
            frame: CanvasRect(x: 70, y: -10, width: 316, height: 170),
            title: "Keys",
            text: "Space + drag to pan\n⌘= / ⌘− to zoom\n⌘K for commands",
            style: NodeStyle(accent: ColorToken.mint.rawValue, fontSize: 15)
        )

        let footer = CanvasNode(
            kind: .text,
            frame: CanvasRect(x: -640, y: 224, width: 660, height: 68),
            title: "",
            text: "Open source. Local-first. Nothing leaves your Mac.",
            style: NodeStyle(accent: ColorToken.slate.rawValue, fontSize: 13, cornerRadius: 16, opacity: 0.9)
        )

        document.insert(frame, at: 0)
        document.insert(hero)
        document.insert(link)
        document.insert(window)
        document.insert(footer)
        document.insert(stickyStart)
        document.insert(stickyWindows)
        document.insert(stickyKeys)

        for id in [stickyStart.id, stickyWindows.id, stickyKeys.id] {
            if let index = document.index(of: id) { document.nodes[index].groupID = frame.id }
        }

        document.transform = CanvasTransform(translation: CanvasPoint(x: 820, y: 520), zoom: 1)
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

// MARK: - Canvas mode illustration

public extension SampleCanvas {
    /// A stand-in for the live canvas: the same window cards the desktop plane
    /// draws, laid out the way canvas mode arranges real windows. Used for
    /// documentation where a real permission grant is not available.
    static func canvasModeIllustration() -> CanvasDocument {
        var document = CanvasDocument(name: "Canvas mode", background: .midnight, gridStyle: .dots, gridSpacing: 44)

        let specifications: [(String, String, String, Double, Double, Double, Double)] = [
            ("Safari", "Design notes — Safari", "com.apple.Safari", -700, -420, 620, 400),
            ("Xcode", "Sunroom — Sources", "com.apple.dt.Xcode", 20, -470, 700, 470),
            ("Terminal", "sunroom — swift build", "com.apple.Terminal", 800, -360, 520, 320),
            ("Notes", "Launch checklist", "com.apple.Notes", -660, 60, 460, 340),
            ("Music", "Focus — playlist", "com.apple.Music", -120, 90, 520, 310),
            ("Finder", "Sunroom", "com.apple.finder", 480, 120, 480, 330)
        ]

        for (app, title, bundle, x, y, width, height) in specifications {
            let node = CanvasNode(
                kind: .window,
                frame: CanvasRect(x: x, y: y, width: width, height: height),
                title: title,
                text: app,
                style: NodeStyle(accent: ColorToken.slate.rawValue, cornerRadius: 12),
                windowReference: WindowReference(
                    windowNumber: 0,
                    ownerPID: 0,
                    bundleIdentifier: bundle,
                    appName: app,
                    windowTitle: title
                )
            )
            document.insert(node)
        }
        return document
    }
}
