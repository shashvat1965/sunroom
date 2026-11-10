import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SunroomCore
import SunroomKit

// MARK: - Sidebar

/// The floating left rail: canvases, objects and the windows of this Mac.
struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var isAllWindowsHovering = false

    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline().padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    newCanvasButton
                    canvasesSection
                    Hairline().padding(.horizontal, 6)
                    objectsSection
                    Hairline().padding(.horizontal, 6)
                    thisMacSection
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Hairline().padding(.horizontal, 12)
            footer
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        .glassPanel(cornerRadius: Theme.Metric.panelRadius)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            appMark
            Text("Sunroom")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text("BETA")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Color.sunroomAccentDeep)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Capsule(style: .continuous).fill(Color.sunroomAccent.opacity(0.18)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.sunroomAccent.opacity(0.22), lineWidth: 0.5))
                .accessibilityLabel("Beta")
            Spacer(minLength: 2)
            Button {
                withAnimation(Self.spring) { isPresented = false }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle(size: 24))
            .help("Hide sidebar")
            .accessibilityLabel("Hide sidebar")
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.sunroomAccent, Color.sunroomAccentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.18), radius: 0.6, y: 0.5)
        }
        .frame(width: 22, height: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.45), lineWidth: 0.6)
        }
        .shadow(color: Color.sunroomAccentDeep.opacity(0.35), radius: 4, y: 1.5)
        .accessibilityHidden(true)
    }

    // MARK: Sections

    private var newCanvasButton: some View {
        Button {
            model.newCanvas()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 10.5, weight: .bold))
                Text("New Canvas").font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                KeyCap("⌘N").environment(\.colorScheme, .light)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(isProminent: true, size: 32))
        .help("Create a new canvas")
        .accessibilityLabel("New canvas")
        .padding(.horizontal, 6)
    }

    private var canvasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader("Canvases", trailing: AnyView(
                Text("\(model.summaries.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            ))
            .padding(.horizontal, 6)

            VStack(spacing: 2) {
                if model.summaries.isEmpty {
                    Text("No canvases yet. Start a new one above.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.summaries) { summary in
                        SidebarCanvasRow(model: model, summary: summary)
                    }
                }
            }
        }
    }

    private var objectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader("Objects").padding(.horizontal, 6)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                SidebarObjectTile(symbol: "note.text", label: "Note", tint: .sunflower,
                                  help: "Place a note on the canvas") { model.addNote() }
                SidebarObjectTile(symbol: "text.alignleft", label: "Text", tint: .sky,
                                  help: "Place a text card on the canvas") { model.addText() }
                SidebarObjectTile(symbol: "rectangle.dashed", label: "Frame", tint: .lilac,
                                  help: "Place a frame to group things") { model.addFrame() }
                SidebarObjectTile(symbol: "photo", label: "Image", tint: .mint,
                                  help: "Choose an image from this Mac") { chooseImage() }
            }
        }
    }

    private var thisMacSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader("This Mac", trailing: AnyView(
                Button {
                    model.refreshWindows()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle(size: 20))
                .help("Refresh windows")
                .accessibilityLabel("Refresh windows")
            ))
            .padding(.horizontal, 6)

            if model.permissionStatus[.accessibility] != .granted {
                permissionCard
            }

            if recentWindows.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("No windows visible")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            } else {
                VStack(spacing: 1) {
                    ForEach(recentWindows) { window in
                        SidebarWindowRow(window: window) { model.addWindow(window) }
                    }
                }
            }

            Button {
                model.isWindowLibraryPresented = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("All windows…").font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 2)
                    Text("\(model.availableWindows.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 7)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isAllWindowsHovering ? 0.055 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(Self.spring) { isAllWindowsHovering = hovering }
            }
            .help("Browse every window on this Mac")
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sunroomAccentDeep)
                Text("Let Sunroom arrange windows")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(2)
            }
            Text("Accessibility lets Sunroom move and focus other apps' windows. Everything else works without it.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Grant Access") {
                model.requestPermission(.accessibility)
            }
            .buttonStyle(GlassButtonStyle(size: 24))
            .help("Open Accessibility settings")
            .accessibilityHint("Opens System Settings so Sunroom can move windows")
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.sunroomAccent.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.sunroomAccent.opacity(0.22), lineWidth: 0.7)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(workspaceStats)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle(size: 24))
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            Button {
                // Intentionally quiet: the tooltip is the help.
            } label: {
                Image(systemName: "questionmark")
            }
            .buttonStyle(IconButtonStyle(size: 24))
            .help("Tip: press ⌘K for commands, Space to pan")
            .accessibilityLabel("Help")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Derived

    private var recentWindows: [ManagedWindow] { Array(model.availableWindows.prefix(4)) }

    private var workspaceStats: String {
        let objects = model.document.nodes.count
        let windows = model.windowNodes.count
        return "\(objects) \(objects == 1 ? "object" : "objects") · \(windows) \(windows == 1 ? "window" : "windows")"
    }

    // MARK: Actions

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add Image"
        panel.message = "Choose an image to place on the canvas."
        if panel.runModal() == .OK, let url = panel.url {
            model.addImage(from: url)
        }
    }
}

// MARK: - Canvas row

private struct SidebarCanvasRow: View {
    @ObservedObject var model: AppModel
    let summary: CanvasSummary

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draft = ""
    @State private var confirmDelete = false
    @FocusState private var renameFocused: Bool

    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    private var isSelected: Bool { model.document.id == summary.id }

    private var subtitle: String {
        "\(summary.nodeCount) \(summary.nodeCount == 1 ? "object" : "objects") · \(SidebarUI.relativeTime(summary.updatedAt))"
    }

    var body: some View {
        HStack(spacing: 8) {
            swatch
            if isRenaming {
                TextField("Canvas name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .focused($renameFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.name)
                        .font(isSelected ? Theme.Typo.rowEmphasis() : Theme.Typo.row())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isHovering {
                    menuButton.transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(minHeight: 38)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.sunroomAccent.opacity(0.17) : Color.primary.opacity(isHovering ? 0.055 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelected ? Color.sunroomAccent.opacity(0.32) : .clear, lineWidth: 0.8)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture(count: 2) { beginRename() }
        .onTapGesture {
            guard !isRenaming else { return }
            model.openCanvas(id: summary.id)
        }
        .onHover { hovering in
            withAnimation(Self.spring) { isHovering = hovering }
        }
        .animation(Self.spring, value: isSelected)
        .alert("Delete “\(summary.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.deleteCanvas(id: summary.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This canvas will be permanently deleted. You can't undo this.")
        }
        .contextMenu {
            Button("Rename") { beginRename() }
            Button("Duplicate") { model.duplicateCanvas(id: summary.id) }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var swatch: some View {
        let colors = Theme.canvasColors(for: summary.background, isDark: false)
        let ink: Color = summary.background.isDark ? .white : .black
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(nsColor: colors.top), Color(nsColor: colors.bottom)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            VStack(alignment: .leading, spacing: 1.5) {
                RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                    .fill(ink.opacity(0.24))
                    .frame(width: 7, height: 2)
                HStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                        .fill(ink.opacity(0.32))
                        .frame(width: 4, height: 2)
                    RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                        .fill(ink.opacity(0.16))
                        .frame(width: 4, height: 2)
                }
            }
        }
        .frame(width: 18, height: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.20), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
        .accessibilityHidden(true)
    }

    private var menuButton: some View {
        Menu {
            Button("Rename") { beginRename() }
            Button("Duplicate") { model.duplicateCanvas(id: summary.id) }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Canvas actions for \(summary.name)")
        .accessibilityLabel("Actions for \(summary.name)")
    }

    private func beginRename() {
        guard !isRenaming else { return }
        draft = summary.name
        isRenaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { renameFocused = true }
    }

    private func commitRename() {
        guard isRenaming else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != summary.name {
            model.renameCanvas(id: summary.id, to: trimmed)
        }
        isRenaming = false
    }
}

// MARK: - Object tile

private struct SidebarObjectTile: View {
    let symbol: String
    let label: String
    let tint: ColorToken
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 22, height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color(token: tint).opacity(0.20))
                    }
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(isHovering ? 0.28 : 0.14), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(isHovering ? 0.10 : 0), radius: 8, y: 3)
            .offset(y: isHovering ? -1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Self.spring) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel("Add \(label)")
    }

    private var symbolColor: Color {
        Color(nsColor: Theme.iconNSColor(tint, isDark: colorScheme == .dark))
    }
}

// MARK: - Window row

private struct SidebarWindowRow: View {
    let window: ManagedWindow
    let onAdd: () -> Void

    @State private var isHovering = false

    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: AppIconProvider.shared.icon(bundleIdentifier: window.bundleIdentifier, pid: window.ownerPID))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(window.appName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(window.displayTitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 2)
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(IconButtonStyle(size: 20))
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help("Add \(window.appName) to the canvas")
            .accessibilityLabel("Add \(window.displayTitle)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Self.spring) { isHovering = hovering }
        }
        .contextMenu {
            Button("Add to Canvas") { onAdd() }
        }
    }
}

// MARK: - Shared formatting

enum SidebarUI {
    /// Compact, human relative time: "just now", "2m ago", "3h ago", "4d ago".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 50 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
