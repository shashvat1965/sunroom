import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

/// The Settings scene. Native grouped forms for scanning, a warm glass header
/// so it still reads as Sunroom, and direct bindings into `AppModel.settings`.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView {
                windows
                    .tabItem { Label("Windows", systemImage: "macwindow") }
                general
                    .tabItem { Label("General", systemImage: "gearshape") }
                canvas
                    .tabItem { Label("Canvas", systemImage: "rectangle.on.rectangle") }
                shortcuts
                    .tabItem { Label("Shortcuts", systemImage: "command") }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(preferredScheme)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            model.refreshPermissions()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.sunroomAccent, .sunroomAccentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.7))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Sunroom")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Settings")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("Version 1.0")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background {
            LinearGradient(
                colors: [
                    Color.sunroomAccent.opacity(colorScheme == .dark ? 0.10 : 0.16),
                    Color.sunroomAccentDeep.opacity(colorScheme == .dark ? 0.03 : 0.05),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var preferredScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Accent color") {
                    AccentChoice(selection: $model.settings.accent)
                }
            }

            Section("Behavior") {
                Toggle("Open Sunroom at login", isOn: launchBinding)
                    .disabled(!LaunchAtLogin.isAvailable)
                Toggle("Restore the last canvas on launch", isOn: $model.settings.restoreLastCanvas)
                Toggle("Reduce motion", isOn: $model.settings.reduceMotion)
                Toggle("Show the minimap", isOn: $model.settings.showMinimap)
            }

            Section {
                Text(LaunchAtLogin.isAvailable
                     ? "Preferences save as you change them. Canvas contents live with each canvas file."
                     : "Running from a build folder, so login items are unavailable. The packaged app can open at login.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                launchAtLogin = newValue
                if !LaunchAtLogin.setEnabled(newValue) {
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            }
        )
    }

    // MARK: Canvas

    private var canvas: some View {
        Form {
            Section("Grid") {
                Picker("Style", selection: gridStyle) {
                    ForEach(GridStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: gridSpacing, in: 16...128, step: 8) {
                    Text("Grid spacing  ·  \(Int(model.document.gridSpacing)) pt")
                        .font(Theme.Typo.row())
                        .monospacedDigit()
                }

                Toggle("Show the grid", isOn: $model.settings.showGrid)
            }

            Section("Snapping") {
                Toggle("Snap to edges of nearby objects", isOn: $model.settings.snapEnabled)
                Toggle("Snap to the grid", isOn: $model.settings.snapToGrid)
                    .disabled(!model.settings.snapEnabled)
            }

            Section("Background") {
                Picker("Canvas background", selection: background) {
                    ForEach(CanvasBackground.allCases, id: \.rawValue) { background in
                        Text(background.displayName).tag(background)
                    }
                }
                .pickerStyle(.segmented)

                Text("Applied to \(model.document.name) right away. Grid and background travel with the canvas file.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var gridStyle: Binding<GridStyle> {
        Binding(
            get: { model.document.gridStyle },
            set: { newValue in
                model.document.gridStyle = newValue
                model.persist()
            }
        )
    }

    private var gridSpacing: Binding<Double> {
        Binding(
            get: { model.document.gridSpacing },
            set: { newValue in
                model.document.gridSpacing = max(8, newValue)
                model.persist()
            }
        )
    }

    private var background: Binding<CanvasBackground> {
        Binding(
            get: { model.document.background },
            set: { newValue in
                model.document.background = newValue
                model.persist()
            }
        )
    }

    // MARK: Windows

    private var windows: some View {
        Form {
            Section("Live previews") {
                Toggle("Capture window previews", isOn: $model.settings.capturePreviews)
                LabeledContent("Capture interval") {
                    Text(String(format: "%.1f s", model.settings.captureInterval))
                        .font(Theme.Typo.mono())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.settings.captureInterval, in: 0.5...4, step: 0.5)
                    .tint(.sunroomAccent)
                Text("Shorter intervals feel more live and use a little more CPU.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: model.settings.capturePreviews) { _, enabled in
                if enabled { model.startCapture() } else { model.capture.stop() }
            }

            Section("Permissions") {
                ForEach(PermissionKind.allCases, id: \.rawValue) { kind in
                    PermissionRow(model: model, kind: kind)
                }
            }

            Section {
                Button {
                    model.captureDesktop()
                } label: {
                    Label("Capture desktop now", systemImage: "square.on.square.dashed")
                }
                .disabled(!model.hasAccessibility)

                Text("Windows are read locally through the Accessibility and ScreenCaptureKit APIs. Previews stay in memory on this Mac — Sunroom has no accounts, analytics, or servers.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Form {
            Section("Global shortcut") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Summon Sunroom")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Works from any app, including full-screen spaces.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(model.settings.hotKey.displayString)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.6))
                        }
                        .accessibilityLabel("Current shortcut \(model.settings.hotKey.displayString)")
                }
            }

            Section("Reference") {
                ForEach(Self.shortcutRows, id: \.0) { row in
                    HStack(spacing: 12) {
                        Text(row.0)
                            .font(Theme.Typo.row())
                        Spacer(minLength: 8)
                        KeyCap(row.1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                Text("The global shortcut is fixed in this release. Remapping it is coming in a future version.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private static let shortcutRows: [(String, String)] = [
        ("Command palette", "⌘K"),
        ("Pan the canvas", "Space + drag"),
        ("Fit everything", "⇧⌘F"),
        ("New note", "⌘N"),
        ("Inspector", "⌥⌘I"),
        ("Capture desktop", "⌃⌥C"),
        ("Undo / redo", "⌘Z / ⇧⌘Z"),
    ]
}

// MARK: - Small pieces

private struct AccentChoice: View {
    @Binding var selection: ColorToken
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ColorToken.allCases, id: \.rawValue) { token in
                Button {
                    selection = token
                } label: {
                    Circle()
                        .fill(Color(nsColor: Theme.fill(for: token, isDark: colorScheme == .dark)))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(colorScheme == .dark ? 0.2 : 0.55), lineWidth: 0.6)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(selection == token ? 0.7 : 0), lineWidth: 1.8)
                                .padding(-2.5)
                        }
                }
                .buttonStyle(.plain)
                .help(token.displayName)
                .accessibilityLabel(token.displayName)
                .accessibilityAddTraits(selection == token ? [.isSelected] : [])
            }
        }
    }
}

private struct PermissionRow: View {
    @ObservedObject var model: AppModel
    let kind: PermissionKind

    private var status: PermissionStatus { model.permissionStatus[kind] ?? .unknown }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sunroomAccentDeep)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(kind.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                    StatusPill(status: status)
                }
                Text(kind.explanation)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 5) {
                if status != .granted {
                    Button("Grant") { model.requestPermission(kind) }
                        .buttonStyle(GlassButtonStyle(isProminent: true, size: 24))
                        .help("Ask macOS for \(kind.displayName) access")
                }
                Button("Open Settings") { PermissionsCenter.shared.openSystemSettings(for: kind) }
                    .buttonStyle(GlassButtonStyle(size: 24))
                    .help("Open the \(kind.displayName) pane in System Settings")
            }
            .fixedSize()
        }
        .padding(.vertical, 3)
    }
}

private struct StatusPill: View {
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
        case .granted: return "Granted"
        case .denied: return "Not granted"
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
