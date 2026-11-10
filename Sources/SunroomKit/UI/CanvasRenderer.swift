import AppKit
import SunroomCore

/// Draws the canvas with AppKit into the current graphics context.
///
/// The whole world is vector-drawn (no per-node views), which keeps a
/// thousand-node canvas smooth and makes zooming pixel-perfect: text and
/// strokes are rasterized at the current scale instead of being scaled bitmaps.
///
/// Node geometry is expressed in canvas units. The context is scaled by the
/// camera before nodes are drawn, so node drawing code never multiplies by
/// zoom — that would double-scale everything. Chrome that should stay a
/// constant size on screen (selection handles, guides, marquee) is drawn after
/// the camera transform is popped, in screen space.
@MainActor
public final class CanvasRenderer {

    public struct Options {
        public var isDark: Bool
        public var selection: Set<UUID>
        public var snapshots: [UInt32: NSImage]
        public var levelOfDetail: LevelOfDetail
        public var gridStyle: GridStyle
        public var showGrid: Bool
        public var guides: [SnapGuide]
        public var marquee: CanvasRect?
        public var editingNodeID: UUID?
        public var dimmedNodeIDs: Set<UUID>
        public var showSelectionChrome: Bool

        public init(
            isDark: Bool,
            selection: Set<UUID> = [],
            snapshots: [UInt32: NSImage] = [:],
            levelOfDetail: LevelOfDetail = .full,
            gridStyle: GridStyle = .dots,
            showGrid: Bool = true,
            guides: [SnapGuide] = [],
            marquee: CanvasRect? = nil,
            editingNodeID: UUID? = nil,
            dimmedNodeIDs: Set<UUID> = [],
            showSelectionChrome: Bool = true
        ) {
            self.isDark = isDark
            self.selection = selection
            self.snapshots = snapshots
            self.levelOfDetail = levelOfDetail
            self.gridStyle = gridStyle
            self.showGrid = showGrid
            self.guides = guides
            self.marquee = marquee
            self.editingNodeID = editingNodeID
            self.dimmedNodeIDs = dimmedNodeIDs
            self.showSelectionChrome = showSelectionChrome
        }
    }

    public init() {}

    // MARK: - Entry point

    public func draw(
        document: CanvasDocument,
        camera: CanvasTransform,
        in size: CGSize,
        options: Options
    ) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        drawBackground(document: document, camera: camera, size: size, options: options)

        let visible = camera.visibleCanvasRect(in: CanvasSize(size)).expandedBy(240 / max(camera.zoom, 0.02))

        context.saveGraphicsState()
        context.cgContext.translateBy(x: CGFloat(camera.translation.x), y: CGFloat(camera.translation.y))
        context.cgContext.scaleBy(x: CGFloat(camera.zoom), y: CGFloat(camera.zoom))

        for node in document.nodes where node.kind.isContainer && node.frame.intersects(visible) {
            drawContainer(node, camera: camera, options: options)
        }
        for node in document.nodes where !node.kind.isContainer && node.frame.intersects(visible) {
            drawNode(node, camera: camera, options: options)
        }

        context.restoreGraphicsState()

        // Screen-space chrome.
        if options.showSelectionChrome {
            drawSelection(document: document, camera: camera, options: options)
            drawGuides(options.guides, camera: camera)
            drawMarquee(options.marquee, camera: camera)
        }
    }

    // MARK: - Background

    private func drawBackground(document: CanvasDocument, camera: CanvasTransform, size: CGSize, options: Options) {
        let colors = Theme.canvasColors(for: document.background, isDark: options.isDark)
        if let gradient = NSGradient(starting: colors.top, ending: colors.bottom) {
            gradient.draw(in: CGRect(origin: .zero, size: size), angle: -90)
        } else {
            colors.top.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        }

        // Warm light entering from the top-right; makes the plane feel like a room.
        let bloomCenter = CGPoint(x: size.width * 0.84, y: size.height * 0.02)
        let bloomRadius = max(size.width, size.height) * 0.8
        if let radial = NSGradient(colorsAndLocations:
            (colors.bloom, 0.0),
            (colors.bloom.withAlphaComponent(0), 1.0)
        ) {
            radial.draw(
                fromCenter: bloomCenter,
                radius: 0,
                toCenter: bloomCenter,
                radius: bloomRadius,
                options: [.drawsAfterEndingLocation]
            )
        }

        guard options.showGrid, document.gridStyle != .none else { return }

        var spacing = document.gridSpacing
        var screenSpacing = spacing * camera.zoom
        while screenSpacing < 16 {
            spacing *= 2
            screenSpacing = spacing * camera.zoom
        }
        guard screenSpacing < 460 else { return }

        let visible = camera.visibleCanvasRect(in: CanvasSize(size))
        let base = Theme.gridColor(isDark: options.isDark)
        let fade = min(1.0, max(0.18, (screenSpacing - 14) / 40))
        let color = base.withAlphaComponent(base.alphaComponent * fade)
        color.setFill()
        color.setStroke()

        let startX = floor(visible.minX / spacing) * spacing
        let startY = floor(visible.minY / spacing) * spacing

        switch options.gridStyle {
        case .dots:
            let radius = min(1.7, max(0.75, 0.9 * camera.zoom + 0.35))
            var y = startY
            while y <= visible.maxY {
                var x = startX
                while x <= visible.maxX {
                    let point = camera.screenPoint(fromCanvas: CanvasPoint(x: x, y: y))
                    NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
                    x += spacing
                }
                y += spacing
            }
        case .lines:
            let path = NSBezierPath()
            path.lineWidth = 1
            var x = startX
            while x <= visible.maxX {
                let point = camera.screenPoint(fromCanvas: CanvasPoint(x: x, y: visible.minY))
                path.move(to: NSPoint(x: point.x, y: 0))
                path.line(to: NSPoint(x: point.x, y: size.height))
                x += spacing
            }
            var y = startY
            while y <= visible.maxY {
                let point = camera.screenPoint(fromCanvas: CanvasPoint(x: visible.minX, y: y))
                path.move(to: NSPoint(x: 0, y: point.y))
                path.line(to: NSPoint(x: size.width, y: point.y))
                y += spacing
            }
            path.stroke()
        case .none:
            break
        }
    }

    // MARK: - Node dispatch

    private func drawNode(_ node: CanvasNode, camera: CanvasTransform, options: Options) {
        let rect = node.frame.cgRect
        let alpha: CGFloat = (options.dimmedNodeIDs.contains(node.id) ? 0.24 : 1.0) * node.style.opacity
        guard alpha > 0.01 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)

        switch node.kind {
        case .note: drawNote(node, rect: rect, options: options)
        case .text: drawTextCard(node, rect: rect, options: options)
        case .link: drawLink(node, rect: rect, options: options)
        case .image: drawImage(node, rect: rect, options: options)
        case .window: drawWindow(node, rect: rect, camera: camera, options: options)
        case .group: break
        case .shape: drawShape(node, rect: rect, options: options)
        }
    }

    private func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func token(_ node: CanvasNode) -> ColorToken {
        ColorToken(rawValue: node.style.accent) ?? .sunflower
    }

    private func accent(_ node: CanvasNode) -> NSColor {
        Theme.fill(for: token(node), isDark: false)
    }

    /// Draws a soft drop shadow then restores the shadow-free state.
    private func withShadow(color: NSColor, blur: CGFloat, offsetY: CGFloat, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = CGSize(width: 0, height: offsetY)
        shadow.set()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTopSheen(in rect: CGRect, path: NSBezierPath, strength: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let gradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(strength),
            NSColor.white.withAlphaComponent(0)
        ]) {
            gradient.draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.6), angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Note

    private func drawNote(_ node: CanvasNode, rect: CGRect, options: Options) {
        let radius = CGFloat(node.style.cornerRadius)
        let path = rounded(rect, radius)
        let base = accent(node)
        // In dark mode a solid pastel is muddy, so notes become tinted glass:
        // a translucent accent over the canvas, the way light passes through.
        let fill = options.isDark ? base.withAlphaComponent(0.34) : base

        withShadow(
            color: NSColor.black.withAlphaComponent(options.isDark ? 0.42 : 0.18),
            blur: 14,
            offsetY: -5
        ) {
            fill.setFill()
            path.fill()
        }

        drawTopSheen(in: rect, path: path, strength: options.isDark ? 0.16 : 0.32)

        NSColor.white.withAlphaComponent(options.isDark ? 0.12 : 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard options.levelOfDetail != .silhouette else { return }

        let inset: CGFloat = 20
        let content = rect.insetBy(dx: inset, dy: inset)
        let textColor = Theme.textColor(on: token(node), isDark: options.isDark)

        if options.levelOfDetail == .blocks {
            drawText(node.displayLabel, in: content, font: .systemFont(ofSize: 13, weight: .medium), color: textColor.withAlphaComponent(0.9), maxLines: 3)
            return
        }

        var cursorY = content.minY - 1
        if !node.title.isEmpty {
            let font = roundedFont(size: 16, weight: .semibold)
            let height = ceil(font.ascender - font.descender + font.leading)
            drawText(node.title, in: CGRect(x: content.minX, y: cursorY, width: content.width, height: height * 1.1), font: font, color: textColor, maxLines: 1)
            cursorY += height + 6
        }

        if !node.text.isEmpty, options.levelOfDetail == .full {
            let font = NSFont.systemFont(ofSize: CGFloat(node.style.fontSize), weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor.withAlphaComponent(0.76),
                .paragraphStyle: paragraph,
            ]
            (node.text as NSString).draw(
                with: CGRect(x: content.minX, y: cursorY, width: content.width, height: max(0, content.maxY - cursorY)),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes
            )
        }

        if node.isLocked, options.levelOfDetail == .full {
            let badge = CGRect(x: rect.maxX - 26, y: rect.maxY - 26, width: 12, height: 12)
            textColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -5, dy: -5)).fill()
            if let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
                image.draw(in: badge)
            }
        }
    }

    // MARK: - Text card

    private func drawTextCard(_ node: CanvasNode, rect: CGRect, options: Options) {
        let radius = CGFloat(node.style.cornerRadius)
        guard options.levelOfDetail != .silhouette else {
            (options.isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.labelColor.withAlphaComponent(0.10)).setFill()
            rounded(rect, radius * 0.5).fill()
            return
        }

        if options.levelOfDetail == .full {
            let fill = options.isDark ? NSColor.white.withAlphaComponent(0.045) : NSColor.white.withAlphaComponent(0.52)
            let path = rounded(rect, radius)
            fill.setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.06).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let inset: CGFloat = 20
        let content = rect.insetBy(dx: inset, dy: inset)
        let primary = options.isDark ? NSColor(white: 0.96, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
        let secondary = primary.withAlphaComponent(0.68)

        var cursorY = content.minY + 1
        if !node.title.isEmpty {
            let font = roundedFont(size: max(18, CGFloat(node.style.fontSize) + 8), weight: .semibold)
            let height = ceil(font.ascender - font.descender + font.leading)
            drawText(node.title, in: CGRect(x: content.minX, y: cursorY, width: content.width, height: height * 1.15), font: font, color: primary, maxLines: 1)
            cursorY += height + 8
        }
        if !node.text.isEmpty, options.levelOfDetail == .full {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(node.style.fontSize), weight: .regular),
                .foregroundColor: secondary,
                .paragraphStyle: paragraph,
            ]
            (node.text as NSString).draw(
                with: CGRect(x: content.minX, y: cursorY, width: content.width, height: max(0, content.maxY - cursorY)),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes
            )
        }
    }

    // MARK: - Link

    private func drawLink(_ node: CanvasNode, rect: CGRect, options: Options) {
        let radius = CGFloat(node.style.cornerRadius)
        let path = rounded(rect, radius)
        let fill = options.isDark ? NSColor.white.withAlphaComponent(0.075) : NSColor.white.withAlphaComponent(0.74)

        withShadow(color: NSColor.black.withAlphaComponent(options.isDark ? 0.30 : 0.10), blur: 12, offsetY: -4) {
            fill.setFill()
            path.fill()
        }
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard options.levelOfDetail != .silhouette else { return }

        let inset: CGFloat = 16
        let iconSize: CGFloat = 36
        let iconRect = CGRect(x: rect.minX + inset, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
        let badge = rounded(iconRect, iconSize * 0.3)
        accent(node).setFill()
        badge.fill()

        if let symbol = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let configured = symbol.withSymbolConfiguration(config) {
                let tinted = NSImage(size: configured.size)
                tinted.lockFocus()
                configured.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                (accent(node).blended(withFraction: 0.62, of: .black) ?? accent(node)).set()
                NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: CGRect(
                    x: iconRect.midX - configured.size.width / 2,
                    y: iconRect.midY - configured.size.height / 2,
                    width: configured.size.width,
                    height: configured.size.height
                ))
            }
        }

        let textX = iconRect.maxX + 12
        let available = CGRect(x: textX, y: rect.minY + inset, width: max(10, rect.maxX - inset - textX), height: rect.height - inset * 2)
        let host = node.title.isEmpty ? (URL(string: node.linkURL ?? "")?.host ?? "Link") : node.title
        let hostFont = roundedFont(size: 15, weight: .semibold)
        drawText(host, in: CGRect(x: available.minX, y: available.minY + 2, width: available.width, height: 20), font: hostFont, color: options.isDark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.10, alpha: 1), maxLines: 1)

        if options.levelOfDetail == .full, let raw = node.linkURL, let url = URL(string: raw) {
            let pathText = url.path.isEmpty ? "/" : url.path
            drawText(pathText, in: CGRect(x: available.minX, y: available.minY + 24, width: available.width, height: 16), font: .systemFont(ofSize: 11.5), color: options.isDark ? NSColor(white: 0.72, alpha: 1) : NSColor(white: 0.42, alpha: 1), maxLines: 1)
        }
    }

    // MARK: - Image

    private func drawImage(_ node: CanvasNode, rect: CGRect, options: Options) {
        let radius = CGFloat(node.style.cornerRadius)
        let path = rounded(rect, radius)

        withShadow(color: NSColor.black.withAlphaComponent(options.isDark ? 0.40 : 0.16), blur: 16, offsetY: -5) {
            (options.isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.white).setFill()
            path.fill()
        }

        if let name = node.imageAssetName, let image = AssetImageCache.shared.image(named: name) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let imageSize = image.size
            let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            image.draw(
                in: CGRect(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2, width: drawSize.width, height: drawSize.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
            NSGraphicsContext.restoreGraphicsState()
        } else {
            (options.isDark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0.35, alpha: 0.35)).setFill()
            if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 30, weight: .light)) {
                symbol.draw(in: CGRect(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
            }
        }

        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Window card

    private func drawWindow(_ node: CanvasNode, rect: CGRect, camera: CanvasTransform, options: Options) {
        let radius = CGFloat(node.style.cornerRadius)
        let path = rounded(rect, radius)

        withShadow(color: NSColor.black.withAlphaComponent(options.isDark ? 0.48 : 0.22), blur: 18, offsetY: -6) {
            (options.isDark ? NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1) : NSColor(white: 0.99, alpha: 1)).setFill()
            path.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let titleBarHeight: CGFloat = 26
        let titleBar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleBarHeight)
        (options.isDark ? NSColor(srgbRed: 0.22, green: 0.23, blue: 0.26, alpha: 1) : NSColor(white: 0.94, alpha: 1)).setFill()
        NSBezierPath(rect: titleBar).fill()

        let dotRadius: CGFloat = 4.5
        let dotY = titleBar.midY
        let lightColors: [NSColor] = [
            NSColor(srgbRed: 0.98, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.75, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 0.30, green: 0.80, blue: 0.35, alpha: 1),
        ]
        for (index, color) in lightColors.enumerated() {
            color.setFill()
            let x = rect.minX + 12 + CGFloat(index) * dotRadius * 3.1
            NSBezierPath(ovalIn: CGRect(x: x - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)).fill()
        }

        if options.levelOfDetail != .silhouette, rect.width > 120 {
            drawText(
                node.displayLabel,
                in: CGRect(x: rect.minX + 52, y: dotY - 7, width: max(10, rect.width - 66), height: 15),
                font: .systemFont(ofSize: 10.5, weight: .medium),
                color: options.isDark ? NSColor(white: 0.78, alpha: 1) : NSColor(white: 0.36, alpha: 1),
                maxLines: 1
            )
        }

        let content = CGRect(x: rect.minX, y: rect.minY + titleBarHeight, width: rect.width, height: max(0, rect.height - titleBarHeight))
        let snapshot = node.windowReference.flatMap { options.snapshots[$0.windowNumber] }
        if options.levelOfDetail == .full, let snapshot {
            let imageSize = snapshot.size
            let scale = max(content.width / max(imageSize.width, 1), content.height / max(imageSize.height, 1))
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            snapshot.draw(
                in: CGRect(x: content.midX - drawSize.width / 2, y: content.midY - drawSize.height / 2, width: drawSize.width, height: drawSize.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.medium.rawValue]
            )
        } else {
            (options.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0.965, alpha: 1)).setFill()
            NSBezierPath(rect: content).fill()
            if options.levelOfDetail != .silhouette {
                let iconSize = max(16, min(content.width, content.height) * 0.34)
                let icon = AppIconProvider.shared.icon(
                    bundleIdentifier: node.windowReference?.bundleIdentifier,
                    pid: node.windowReference?.ownerPID
                )
                let iconY = content.midY - iconSize / 2 - (content.height > 90 ? 9 : 0)
                icon.draw(in: CGRect(x: content.midX - iconSize / 2, y: iconY, width: iconSize, height: iconSize))
                if content.height > 90, options.levelOfDetail == .full {
                    let appName = node.windowReference?.appName ?? node.text
                    if !appName.isEmpty {
                        drawText(
                            appName,
                            in: CGRect(x: content.minX + 8, y: iconY + iconSize + 7, width: content.width - 16, height: 15),
                            font: .systemFont(ofSize: 11, weight: .medium),
                            color: options.isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.48, alpha: 1),
                            maxLines: 1,
                            alignment: .center
                        )
                    }
                }
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        if options.levelOfDetail == .full, snapshot != nil {
            NSColor(srgbRed: 0.24, green: 0.82, blue: 0.45, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.maxX - 18, y: rect.minY + titleBarHeight / 2 - 3, width: 6, height: 6)).fill()
        }

        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
        _ = camera
    }

    private func drawShape(_ node: CanvasNode, rect: CGRect, options: Options) {
        let path = rounded(rect, CGFloat(node.style.cornerRadius))
        accent(node).withAlphaComponent(0.85).setFill()
        path.fill()
        _ = options
    }

    // MARK: - Container

    private func drawContainer(_ node: CanvasNode, camera: CanvasTransform, options: Options) {
        let rect = node.frame.cgRect
        let radius = CGFloat(node.style.cornerRadius)
        let base = Theme.fill(for: token(node), isDark: false)
        let path = rounded(rect, radius)

        base.withAlphaComponent(options.isDark ? 0.09 : 0.20).setFill()
        path.fill()

        let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        border.setLineDash([6, 5], count: 2, phase: 0)
        (options.isDark
            ? NSColor.white.withAlphaComponent(0.20)
            : (base.blended(withFraction: 0.42, of: .black) ?? base).withAlphaComponent(0.40)
        ).setStroke()
        border.lineWidth = 1.2
        border.stroke()

        guard options.levelOfDetail != .silhouette else { return }
        let label = node.title.isEmpty ? "Frame" : node.title
        drawText(
            label,
            in: CGRect(x: rect.minX + 4, y: rect.minY - 20, width: max(20, rect.width - 8), height: 15),
            font: roundedFont(size: 11.5, weight: .semibold),
            color: options.isDark ? NSColor(white: 0.76, alpha: 0.9) : NSColor(white: 0.34, alpha: 0.9),
            maxLines: 1
        )
        _ = camera
    }

    // MARK: - Selection (screen space)

    private func drawSelection(document: CanvasDocument, camera: CanvasTransform, options: Options) {
        guard !options.selection.isEmpty else { return }
        let accent = NSColor(srgbRed: 1.0, green: 0.60, blue: 0.14, alpha: 1)

        for node in document.nodes where options.selection.contains(node.id) {
            let screenRect = camera.screenRect(fromCanvas: node.frame.standardized)
            let rect = screenRect.cgRect.insetBy(dx: -2, dy: -2)
            let radius = min(28, CGFloat(node.style.cornerRadius) * camera.zoom + 2)
            let path = rounded(rect, radius)
            accent.setStroke()
            path.lineWidth = 1.7
            path.stroke()
        }

        guard let bounds = document.bounds(of: options.selection) else { return }
        let boundsScreen = camera.screenRect(fromCanvas: bounds).cgRect

        if options.selection.count > 1 {
            let path = rounded(boundsScreen.insetBy(dx: -7, dy: -7), 7)
            path.setLineDash([5, 4], count: 2, phase: 0)
            accent.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let handleSize: CGFloat = 7.5
        for handle in SelectionHandle.allCases {
            let point = handle.point(in: boundsScreen)
            let rect = CGRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2, width: handleSize, height: handleSize)
            let path = NSBezierPath(roundedRect: rect, xRadius: handleSize * 0.3, yRadius: handleSize * 0.3)
            NSColor.white.setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }
    }

    private func drawGuides(_ guides: [SnapGuide], camera: CanvasTransform) {
        guard !guides.isEmpty else { return }
        let accent = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.52, alpha: 0.92)
        accent.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for guide in guides {
            switch guide.orientation {
            case .vertical:
                let start = camera.screenPoint(fromCanvas: CanvasPoint(x: guide.position, y: guide.start))
                let end = camera.screenPoint(fromCanvas: CanvasPoint(x: guide.position, y: guide.end))
                path.move(to: NSPoint(x: start.x, y: start.y - 10))
                path.line(to: NSPoint(x: end.x, y: end.y + 10))
            case .horizontal:
                let start = camera.screenPoint(fromCanvas: CanvasPoint(x: guide.start, y: guide.position))
                let end = camera.screenPoint(fromCanvas: CanvasPoint(x: guide.end, y: guide.position))
                path.move(to: NSPoint(x: start.x - 10, y: start.y))
                path.line(to: NSPoint(x: end.x + 10, y: end.y))
            }
        }
        path.stroke()
    }

    private func drawMarquee(_ marquee: CanvasRect?, camera: CanvasTransform) {
        guard let marquee else { return }
        let rect = camera.screenRect(fromCanvas: marquee).cgRect
        let path = rounded(rect, 4)
        NSColor(srgbRed: 1.0, green: 0.60, blue: 0.14, alpha: 0.10).setFill()
        path.fill()
        NSColor(srgbRed: 1.0, green: 0.60, blue: 0.14, alpha: 0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Text helpers

    private func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    private func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, maxLines: Int, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.maximumLineHeight = ceil(font.ascender - font.descender + font.leading) * 1.05
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let height = min(rect.height, lineHeight * CGFloat(maxLines) + 2)
        (text as NSString).draw(
            with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }
}

// MARK: - Handles

public enum SelectionHandle: String, CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    public var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    public var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    public var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    public var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    public var cursor: NSCursor {
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}

// MARK: - Asset cache

/// Decodes canvas images once and keeps them in memory, with a bounded count.
public final class AssetImageCache {
    public static let shared = AssetImageCache()
    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let limit = 64

    private init() {}

    public func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let url = DocumentFileStore.defaultStore.assetURL(for: name)
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        order.append(name)
        if order.count > limit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return image
    }

    public func clear() {
        cache.removeAll()
        order.removeAll()
    }
}
