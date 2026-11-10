import SwiftUI
import AppKit
import SunroomCore

// MARK: - Tokens

/// One place for every color, radius and type ramp in the app.
///
/// Sunroom is deliberately warm: a sunlit canvas with graphite glass furniture,
/// rather than the cold blue-gray of most Mac utilities.
public enum Theme {

    // MARK: Metrics

    public enum Metric {
        public static let panelRadius: CGFloat = 20
        public static let controlRadius: CGFloat = 12
        public static let cardRadius: CGFloat = 18
        public static let hairline: CGFloat = 1
        public static let panelPadding: CGFloat = 14
        public static let toolbarHeight: CGFloat = 46
    }

    // MARK: Type

    public enum Typo {
        public static func panelTitle() -> Font { .system(size: 12, weight: .semibold) }
        public static func row() -> Font { .system(size: 12.5, weight: .regular) }
        public static func rowEmphasis() -> Font { .system(size: 12.5, weight: .medium) }
        public static func heading() -> Font { .system(size: 22, weight: .semibold, design: .rounded) }
        public static func mono() -> Font { .system(size: 11, weight: .medium, design: .monospaced) }
    }

    // MARK: Node colors

    public static func fill(for token: ColorToken, isDark: Bool) -> NSColor {
        switch token {
        case .sunflower: return isDark ? NSColor(srgbRed: 0.78, green: 0.60, blue: 0.20, alpha: 1) : NSColor(srgbRed: 1.00, green: 0.86, blue: 0.52, alpha: 1)
        case .apricot: return isDark ? NSColor(srgbRed: 0.76, green: 0.47, blue: 0.27, alpha: 1) : NSColor(srgbRed: 1.00, green: 0.80, blue: 0.66, alpha: 1)
        case .rose: return isDark ? NSColor(srgbRed: 0.70, green: 0.34, blue: 0.47, alpha: 1) : NSColor(srgbRed: 1.00, green: 0.78, blue: 0.84, alpha: 1)
        case .lilac: return isDark ? NSColor(srgbRed: 0.48, green: 0.38, blue: 0.74, alpha: 1) : NSColor(srgbRed: 0.85, green: 0.79, blue: 1.00, alpha: 1)
        case .sky: return isDark ? NSColor(srgbRed: 0.28, green: 0.50, blue: 0.68, alpha: 1) : NSColor(srgbRed: 0.76, green: 0.88, blue: 1.00, alpha: 1)
        case .mint: return isDark ? NSColor(srgbRed: 0.25, green: 0.60, blue: 0.46, alpha: 1) : NSColor(srgbRed: 0.77, green: 0.94, blue: 0.85, alpha: 1)
        case .sand: return isDark ? NSColor(srgbRed: 0.55, green: 0.48, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.93, green: 0.89, blue: 0.82, alpha: 1)
        case .slate: return isDark ? NSColor(srgbRed: 0.33, green: 0.37, blue: 0.43, alpha: 1) : NSColor(srgbRed: 0.86, green: 0.89, blue: 0.93, alpha: 1)
        case .graphite: return NSColor(srgbRed: 0.18, green: 0.19, blue: 0.22, alpha: 1)
        }
    }

    public static func textColor(on token: ColorToken, isDark: Bool) -> NSColor {
        if isDark { return NSColor(white: 0.97, alpha: 1) }
        switch token {
        case .sunflower, .apricot, .rose, .lilac, .sky, .mint, .sand, .slate:
            return NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        case .graphite:
            return NSColor(white: 0.96, alpha: 1)
        }
    }

    /// A saturated version of a pastel token, for glyphs on light glass where
    /// the pastel alone would be illegible.
    public static func iconNSColor(_ token: ColorToken, isDark: Bool) -> NSColor {
        let base = fill(for: token, isDark: false)
        if isDark { return base.blended(withFraction: 0.12, of: .white) ?? base }
        return base.blended(withFraction: 0.58, of: .black) ?? base
    }

    public static func accentNSColor(_ token: ColorToken) -> NSColor {
        fill(for: token, isDark: false).blended(withFraction: 0.18, of: .black) ?? fill(for: token, isDark: false)
    }

    // MARK: Canvas backgrounds

    public static func canvasColors(for background: CanvasBackground, isDark: Bool) -> (top: NSColor, bottom: NSColor, bloom: NSColor) {
        switch background {
        case .aurora:
            return isDark
                ? (NSColor(srgbRed: 0.09, green: 0.09, blue: 0.14, alpha: 1), NSColor(srgbRed: 0.13, green: 0.11, blue: 0.19, alpha: 1), NSColor(srgbRed: 1.0, green: 0.62, blue: 0.28, alpha: 0.16))
                : (NSColor(srgbRed: 0.98, green: 0.97, blue: 0.96, alpha: 1), NSColor(srgbRed: 0.95, green: 0.94, blue: 0.97, alpha: 1), NSColor(srgbRed: 1.0, green: 0.70, blue: 0.35, alpha: 0.18))
        case .dawn:
            return isDark
                ? (NSColor(srgbRed: 0.11, green: 0.08, blue: 0.10, alpha: 1), NSColor(srgbRed: 0.18, green: 0.11, blue: 0.13, alpha: 1), NSColor(srgbRed: 0.95, green: 0.40, blue: 0.35, alpha: 0.18))
                : (NSColor(srgbRed: 0.99, green: 0.96, blue: 0.93, alpha: 1), NSColor(srgbRed: 0.97, green: 0.90, blue: 0.87, alpha: 1), NSColor(srgbRed: 1.0, green: 0.55, blue: 0.38, alpha: 0.20))
        case .graphite:
            return isDark
                ? (NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1), NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1), NSColor(white: 1, alpha: 0.04))
                : (NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1), NSColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1), NSColor(white: 1, alpha: 0.35))
        case .midnight:
            return (NSColor(srgbRed: 0.05, green: 0.06, blue: 0.11, alpha: 1), NSColor(srgbRed: 0.08, green: 0.09, blue: 0.16, alpha: 1), NSColor(srgbRed: 0.35, green: 0.45, blue: 1.0, alpha: 0.16))
        case .paper:
            return isDark
                ? (NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1), NSColor(srgbRed: 0.17, green: 0.16, blue: 0.14, alpha: 1), NSColor(srgbRed: 0.9, green: 0.8, blue: 0.6, alpha: 0.10))
                : (NSColor(srgbRed: 0.98, green: 0.97, blue: 0.94, alpha: 1), NSColor(srgbRed: 0.95, green: 0.93, blue: 0.89, alpha: 1), NSColor(srgbRed: 0.85, green: 0.75, blue: 0.55, alpha: 0.14))
        }
    }

    public static func gridColor(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0.25, alpha: 0.11)
    }
}

// MARK: - SwiftUI colors

public extension Color {
    init(token: ColorToken) {
        self.init(nsColor: Theme.fill(for: token, isDark: false))
    }

    static let sunroomAccent = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.69, blue: 0.24, alpha: 1))
    static let sunroomAccentDeep = Color(nsColor: NSColor(srgbRed: 0.95, green: 0.52, blue: 0.15, alpha: 1))
}

// MARK: - Glass

/// Liquid Glass on macOS 26, with a faithful material fallback on 14/15.
///
/// The fallback is not a downgrade in taste: `.ultraThinMaterial` plus a
/// hairline highlight and a soft shadow reads as glass on older systems too.
public struct GlassBackground: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?
    public var strokeOpacity: Double
    public var shadow: Bool

    public init(cornerRadius: CGFloat = Theme.Metric.panelRadius, tint: Color? = nil, strokeOpacity: Double = 0.55, shadow: Bool = true) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.strokeOpacity = strokeOpacity
        self.shadow = shadow
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background {
                    ZStack {
                        shape.fill(.clear)
                        if let tint { shape.fill(tint.opacity(0.35)) }
                    }
                }
                .glassEffect(.regular.tint(tint ?? .clear).interactive(false), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(strokeOpacity * 0.9), .white.opacity(strokeOpacity * 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                }
                .shadow(color: .black.opacity(shadow ? 0.16 : 0), radius: shadow ? 26 : 0, y: shadow ? 10 : 0)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.22)) }
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(strokeOpacity * 0.8), .white.opacity(strokeOpacity * 0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                }
                .shadow(color: .black.opacity(shadow ? 0.14 : 0), radius: shadow ? 20 : 0, y: shadow ? 8 : 0)
        }
    }
}

public extension View {
    func glassPanel(cornerRadius: CGFloat = Theme.Metric.panelRadius, tint: Color? = nil, shadow: Bool = true) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }
}

// MARK: - Buttons

public struct GlassButtonStyle: ButtonStyle {
    public var isProminent: Bool
    public var size: CGFloat

    public init(isProminent: Bool = false, size: CGFloat = 30) {
        self.isProminent = isProminent
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isProminent ? Color.black.opacity(0.85) : Color.primary)
            .padding(.horizontal, size * 0.42)
            .frame(height: size)
            .background {
                let shape = Capsule(style: .continuous)
                if isProminent {
                    shape.fill(
                        LinearGradient(
                            colors: [Color.sunroomAccent, Color.sunroomAccentDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(shape.strokeBorder(.white.opacity(0.45), lineWidth: 0.7))
                    .shadow(color: Color.sunroomAccentDeep.opacity(0.35), radius: 8, y: 3)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.7))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Square, borderless icon button used in toolbars and card chrome.
public struct IconButtonStyle: ButtonStyle {
    public var isActive: Bool
    public var size: CGFloat

    public init(isActive: Bool = false, size: CGFloat = 30) {
        self.isActive = isActive
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : Color.primary.opacity(0.8))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(isActive ? Color.sunroomAccent : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.0001))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                            .strokeBorder(Color.white.opacity(isActive ? 0.35 : 0), lineWidth: 0.7)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isActive)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }
}

// MARK: - Small pieces

public struct Hairline: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

public struct PanelHeader: View {
    public let title: String
    public var trailing: AnyView?

    public init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

/// A key cap, e.g. ⌘K, drawn the way macOS menus draw them.
public struct KeyCap: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
            }
    }
}
