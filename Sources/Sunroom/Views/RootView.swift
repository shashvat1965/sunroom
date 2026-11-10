import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

/// The main window: an infinite canvas with floating glass furniture.
public struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSidebarVisible = true

    public init(model: AppModel) {
        self.model = model
    }

    private var isDark: Bool { colorScheme == .dark }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasSurface(model: model, isDark: isDark)
                .ignoresSafeArea()

            // Subtle edge shading so floating glass panels sit in a room.
            LinearGradient(
                colors: [Color.black.opacity(isSidebarVisible ? 0.10 : 0), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 260)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            if isSidebarVisible {
                SidebarView(model: model, isPresented: $isSidebarVisible)
                    .padding(.leading, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 10) {
                TopBarView(model: model, isSidebarVisible: $isSidebarVisible, showShortcutCheatSheet: $model.isShortcutSheetPresented)
                    .padding(.top, 14)
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.leading, isSidebarVisible ? 276 : 0)

            if model.isInspectorPresented {
                HStack(spacing: 0) {
                    Spacer()
                    InspectorView(model: model)
                        .frame(width: 286)
                        .padding(.trailing, 14)
                        .padding(.vertical, 14)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if let editingID = model.editingNodeID,
               let node = model.document.node(withID: editingID),
               node.kind.isTextual {
                TextEditingOverlay(model: model, node: node)
                    .zIndex(15)
            }

            if let toast = model.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 74)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if model.isPalettePresented {
                CommandPaletteView(model: model)
                    .transition(.opacity)
                    .zIndex(20)
            }

            if model.isOnboardingPresented {
                OnboardingView(model: model)
                    .zIndex(30)
            }

            if model.isShortcutSheetPresented {
                ShortcutSheet(isPresented: $model.isShortcutSheetPresented)
                    .zIndex(40)
            }
        }
        .onChange(of: isSidebarVisible) { _, visible in
            model.canvasInsets.left = visible ? 276 : 0
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isSidebarVisible)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.isInspectorPresented)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: model.toast)
        .animation(.easeOut(duration: 0.18), value: model.isPalettePresented)
        .sheet(isPresented: $model.isWindowLibraryPresented) {
            WindowLibraryView(model: model)
                .frame(width: 760, height: 560)
        }
        .onAppear {
            if model.viewportSize == .zero {
                model.viewportSize = CGSize(width: 1440, height: 900)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                model.performInitialFitIfNeeded()
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { model.viewportSize = proxy.size }
                .onChange(of: proxy.size) { _, newValue in model.viewportSize = newValue }
        })
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text("\(model.camera.zoomPercentage)%")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(toolHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassPanel(cornerRadius: 12, shadow: false)

            Spacer(minLength: 0)

            if model.settings.showMinimap {
                MinimapView(model: model)
                    .frame(width: 190, height: 132)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var toolHint: String {
        if !model.selection.isEmpty {
            let count = model.selection.count
            return "\(count) selected  ·  ⌘K for commands"
        }
        switch model.tool {
        case .select: return "Space to pan  ·  ⌘K for commands"
        case .pan: return "Drag to pan"
        case .note: return "Click to place a note"
        case .text: return "Click to place text"
        case .frame: return "Click to place a frame"
        }
    }
}

// MARK: - Top bar

struct TopBarView: View {
    @ObservedObject var model: AppModel
    @Binding var isSidebarVisible: Bool
    @Binding var showShortcutCheatSheet: Bool
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    withAnimation { isSidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(IconButtonStyle(isActive: isSidebarVisible, size: 28))
                .help("Toggle sidebar (⌃⌘S)")

                if isEditingTitle {
                    TextField("Canvas name", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($titleFocused)
                        .frame(width: 170)
                        .onSubmit { commitTitle() }
                        .onExitCommand { isEditingTitle = false }
                } else {
                    Button {
                        titleDraft = model.document.name
                        isEditingTitle = true
                        titleFocused = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(model.document.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Rename canvas")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .glassPanel(cornerRadius: 13, shadow: false)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ForEach(AppModel.Tool.allCases) { tool in
                    Button {
                        model.tool = tool
                    } label: {
                        Image(systemName: tool.symbolName)
                    }
                    .buttonStyle(IconButtonStyle(isActive: model.tool == tool, size: 30))
                    .help(tool.displayName)
                    .keyboardShortcut(shortcut(for: tool), modifiers: [])
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .glassPanel(cornerRadius: 13, shadow: false)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button {
                    model.isPalettePresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Search")
                            .font(.system(size: 12))
                        KeyCap("⌘K")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Command palette (⌘K)")

                Divider().frame(height: 16)

                Button {
                    model.isWindowLibraryPresented = true
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help("Windows on this Mac (⇧⌘W)")

                Button {
                    withAnimation { model.isInspectorPresented.toggle() }
                    model.settings.inspectorVisible = model.isInspectorPresented
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(IconButtonStyle(isActive: model.isInspectorPresented, size: 28))
                .help("Inspector (⌥⌘I)")

                Menu {
                    Button("Export as PNG…") { model.exportPNG() }
                    Button("Export canvas…") { model.exportDocument() }
                    Button("Import canvas…") { model.importDocument() }
                    Divider()
                    Button("Capture desktop windows") { model.captureDesktop() }
                    Button("Apply layout to desktop") { model.applyLayoutToDesktop() }
                    Divider()
                    Button("Keyboard shortcuts") { showShortcutCheatSheet = true }
                    Button("Settings…") { openSettings() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .buttonStyle(IconButtonStyle(size: 28))
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .glassPanel(cornerRadius: 13, shadow: false)
        }
    }

    private func shortcut(for tool: AppModel.Tool) -> KeyEquivalent {
        switch tool {
        case .select: return "v"
        case .pan: return "h"
        case .note: return "n"
        case .text: return "t"
        case .frame: return "f"
        }
    }

    private func commitTitle() {
        model.renameCanvas(id: model.document.id, to: titleDraft)
        isEditingTitle = false
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Toast

struct ToastView: View {
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(toast.isError ? Color.red : Color.sunroomAccentDeep)
            Text(toast.message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassPanel(cornerRadius: 14)
    }
}

// MARK: - Minimap

struct MinimapView: View {
    @ObservedObject var model: AppModel
    @State private var isDragging = false

    private var contentBounds: CanvasRect? {
        model.document.bounds
    }

    var body: some View {
        GeometryReader { proxy in
            let size = CanvasSize(proxy.size)
            let viewport = model.camera.visibleCanvasRect(in: CanvasSize(model.viewportSize))
            let bounds = MinimapProjection.bounds(content: contentBounds, viewport: viewport)
            let projection = MinimapProjection(canvasBounds: bounds, viewport: viewport, minimapSize: size, padding: 8)

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(model.document.nodes.prefix(220)) { node in
                    let rect = projection.rect(for: node.frame)
                    RoundedRectangle(cornerRadius: max(0.8, min(3, rect.width * 0.12)), style: .continuous)
                        .fill(nodeColor(node).opacity(node.kind == .group ? 0.28 : 0.75))
                        .frame(width: max(1.2, rect.width), height: max(1.2, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                }
                let viewRect = projection.rect(for: viewport)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.sunroomAccent, lineWidth: 1.4)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.sunroomAccent.opacity(0.10))
                    )
                    .frame(width: max(6, viewRect.width), height: max(6, viewRect.height))
                    .offset(x: viewRect.minX, y: viewRect.minY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let canvasPoint = projection.canvasPoint(for: CanvasPoint(x: Double(value.location.x), y: Double(value.location.y)))
                        model.camera = model.camera.centering(on: canvasPoint, in: CanvasSize(model.viewportSize))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .padding(6)
        .glassPanel(cornerRadius: 16)
        .overlay(alignment: .topLeading) {
            Text("MAP")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(9)
        }
        .help("Click or drag to fly the camera")
    }

    private func nodeColor(_ node: CanvasNode) -> Color {
        let token = ColorToken(rawValue: node.style.accent) ?? .sunflower
        return Color(nsColor: Theme.fill(for: token, isDark: true))
    }
}

// MARK: - Text editing overlay

struct TextEditingOverlay: View {
    @ObservedObject var model: AppModel
    let node: CanvasNode
    @State private var draft: String = ""
    @State private var titleDraft: String = ""
    @FocusState private var focused: Bool

    private var screenRect: CGRect {
        model.camera.screenRect(fromCanvas: node.frame).cgRect
    }

    var body: some View {
        let rect = screenRect
        let scale = max(0.25, min(1.4, model.camera.zoom))
        VStack(alignment: .leading, spacing: 0) {
            if node.kind == .note {
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15 * scale, weight: .semibold))
                    .padding(.bottom, 6)
            }
            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .font(.system(size: node.style.fontSize * scale))
                .focused($focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(width: max(160, rect.width), height: max(90, rect.height))
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.sunroomAccent.opacity(0.8), lineWidth: 1.2)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .position(x: rect.midX, y: rect.midY)
        .onAppear {
            draft = node.text
            titleDraft = node.title
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onExitCommand { commit() }
    }

    private func commit() {
        guard model.editingNodeID == node.id else { return }
        model.commitTextEdit(nodeID: node.id, title: titleDraft, text: draft)
        model.editingNodeID = nil
    }
}

// MARK: - Shortcuts

struct ShortcutSheet: View {
    @Binding var isPresented: Bool

    private let groups: [(String, [(String, String)])] = [
        ("Canvas", [
            ("Pan", "Space + drag"),
            ("Zoom", "Pinch or ⌘scroll"),
            ("Fit everything", "⇧⌘F"),
            ("Fit selection", "⌘F"),
            ("Reset zoom", "⌘0"),
            ("New note", "⌘N"),
            ("New text", "⌘⇧T"),
            ("New frame", "⌘⇧G"),
            ("Delete", "⌫"),
            ("Duplicate", "⌘D"),
        ]),
        ("Navigation", [
            ("Command palette", "⌘K"),
            ("Search canvas", "type anywhere"),
            ("Cycle objects", "Tab"),
            ("Nudge", "↑ ↓ ← →"),
            ("Nudge further", "⇧ + arrows"),
        ]),
        ("Windows", [
            ("Windows on this Mac", "⇧⌘W"),
            ("Capture desktop", "⌃⌥C"),
            ("Summon canvas", "⌥Space"),
            ("Undo / redo", "⌘Z / ⇧⌘Z"),
            ("Inspector", "⌥⌘I"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Keyboard shortcuts")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Spacer()
                    Button { withAnimation { isPresented = false } } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle(size: 24))
                }
                HStack(alignment: .top, spacing: 34) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(group.0.uppercased())
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(.tertiary)
                            ForEach(group.1, id: \.0) { row in
                                HStack(spacing: 12) {
                                    Text(row.0)
                                        .font(.system(size: 12))
                                        .frame(width: 128, alignment: .leading)
                                    Text(row.1)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 760)
            .glassPanel(cornerRadius: 22)
        }
    }
}
