import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

/// First-run overlay. Three pages on a dimmed, blurred canvas: the promise, the
/// two optional permissions, and the three moves that make the canvas feel
/// like a place rather than a tool.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var page = 0
    @State private var direction: CGFloat = 1

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            SettingsView(model: model)
                .frame(width: 580, height: 470)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        }
        .ignoresSafeArea()
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    .black.opacity(colorScheme == .dark ? 0.38 : 0.16),
                    .black.opacity(colorScheme == .dark ? 0.58 : 0.34),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.sunroomAccent.opacity(0.20), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 520
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var parallaxBloom: some View {
        GeometryReader { proxy in
            Circle()
                .fill(RadialGradient(
                    colors: [Color.sunroomAccent.opacity(0.22), Color.sunroomAccentDeep.opacity(0.04), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: 280
                ))
                .frame(width: 560, height: 560)
                .blur(radius: 16)
                .offset(
                    x: proxy.size.width - 300 + CGFloat(page) * 34,
                    y: -280 - CGFloat(page) * 14
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        go(index)
                    } label: {
                        Capsule(style: .continuous)
                            .fill(index == page ? Color.sunroomAccent : Color.primary.opacity(0.18))
                            .frame(width: index == page ? 18 : 6, height: 6)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(index + 1) of 3")
                    .accessibilityAddTraits(index == page ? [.isSelected] : [])
                }
            }

            Spacer(minLength: 8)

            if page > 0 {
                Button("Back") { go(page - 1) }
                    .buttonStyle(GlassButtonStyle(size: 32))
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityLabel("Back")
            }

            Button {
                advance()
            } label: {
                HStack(spacing: 7) {
                    Text(primaryTitle)
                    Image(systemName: page == 2 ? "sparkles" : "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(GlassButtonStyle(isProminent: true, size: 36))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: String {
        switch page {
        case 0: return "Continue"
        case 1: return "Continue"
        default: return "Start exploring"
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 36 * direction)),
            removal: .opacity.combined(with: .offset(x: -36 * direction))
        )
    }

    // MARK: Navigation

    private func advance() {
        if page < 2 { go(page + 1) } else { dismiss() }
    }

    private func go(_ newPage: Int) {
        guard newPage != page else { return }
        direction = newPage > page ? 1 : -1
        withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) {
            page = newPage
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.22)) {
            model.isOnboardingPresented = false
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            SunMark(size: 88, hasRays: true)
                .padding(.bottom, 4)

            Text("WELCOME TO SUNROOM")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            Text("Your Mac has a plane,\nnot a stack.")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sunroom turns windows, notes and links into one calm surface you arrange by hand. Zoom out to see everything you're juggling; zoom in and get to work.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 430)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PermissionsPage: View {
    @ObservedObject var model: AppModel
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Two permissions, both optional.")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Sunroom is a fine notes surface without them. Grant these when you want it to arrange real windows and draw live previews.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                OnboardingPermissionRow(model: model, kind: .accessibility)
                OnboardingPermissionRow(model: model, kind: .screenRecording)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sunroomAccentDeep)
                Text("Everything is processed on this Mac. No account, no telemetry, no uploads — window data and previews never leave the machine.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)

            HStack {
                Spacer()
                Button("Skip for now", action: skip)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .underline()
                    .accessibilityLabel("Skip permissions for now")
                Spacer()
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

private struct FirstCanvasPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Three moves and you're home.")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Nothing here is permanent. Pan, search, and drag things around until the canvas looks like your desk.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                TipRow(icon: "hand.draw", title: "Pan the plane", detail: "Hold Space and drag anywhere to move the canvas under you.", cap: "Space + drag")
                TipRow(icon: "command", title: "Find anything", detail: "The palette searches notes, links and window titles as you type.", cap: "⌘K")
                TipRow(icon: "macwindow.on.rectangle", title: "Bring a window in", detail: "Pick a window from the library, or capture the whole desktop at once.", cap: "⇧⌘W")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

// MARK: - Pieces

private struct SunMark: View {
    var size: CGFloat
    var hasRays: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.sunroomAccent.opacity(0.5), Color.sunroomAccent.opacity(0)],
                    center: .center,
                    startRadius: 2,
                    endRadius: size * 0.9
                ))
                .frame(width: size * 2, height: size * 2)
                .blur(radius: 2)

            if hasRays {
                ForEach(0..<12, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.sunroomAccent.opacity(0.15), Color.sunroomAccent.opacity(0.5)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: size * 0.05, height: size * 0.16)
                        .offset(y: -size * 0.64)
                        .rotationEffect(.degrees(Double(index) * 30))
                }
            }

            Circle()
                .fill(LinearGradient(
                    colors: [Color.sunroomAccent, Color.sunroomAccentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: Color.sunroomAccentDeep.opacity(0.45), radius: 22, y: 8)
                .overlay {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.45), .clear], center: .topLeading, startRadius: 1, endRadius: size * 0.5))
                }
        }
        .frame(width: size * 1.7, height: size * 1.7)
        .accessibilityHidden(true)
    }
}

private struct TipRow: View {
    let icon: String
    let title: String
    let detail: String
    let cap: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.sunroomAccent.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.sunroomAccentDeep)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            KeyCap(cap)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingPermissionRow: View {
    @ObservedObject var model: AppModel
    let kind: PermissionKind

    private var status: PermissionStatus { model.permissionStatus[kind] ?? .unknown }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.sunroomAccent.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sunroomAccentDeep)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(kind.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    OnboardingStatusPill(status: status)
                }
                Text(kind.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                model.requestPermission(kind)
            } label: {
                Text(status == .granted ? "Granted" : "Grant")
            }
            .buttonStyle(GlassButtonStyle(isProminent: status != .granted, size: 27))
            .disabled(status == .granted)
            .help(status == .granted ? "\(kind.displayName) access is on" : "Ask macOS for \(kind.displayName) access")
            .accessibilityLabel(status == .granted ? "\(kind.displayName) granted" : "Grant \(kind.displayName) access")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                }
        }
    }
}

private struct OnboardingStatusPill: View {
    let status: PermissionStatus

    private var tint: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .unknown: return .secondary
        }
    }

    private var label: String {
        switch status {
        case .granted: return "On"
        case .denied: return "Off"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.24), lineWidth: 0.5))
        }
        .accessibilityLabel("Permission \(label)")
    }
}
