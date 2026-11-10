import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

/// The right-hand glass inspector: contextual controls for nothing, one node,
/// or a multi-selection. Mutations go through `AppModel` so undo and autosave
/// stay in one place.
struct InspectorView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PanelHeader("Inspector")
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        model.isInspectorPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(size: 24))
                .help("Close inspector")
                .accessibilityLabel("Close inspector")
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Hairline()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if model.selection.isEmpty {
                        EmptyInspector(model: model)
                    } else if model.selectedNodes.count > 1 {
                        MultiInspector(model: model, nodes: model.selectedNodes)
                    } else if let node = model.selectedNodes.first {
                        NodeInspector(model: model, node: node).id(node.id)
                    }
                }
                .padding(Theme.Metric.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassPanel(cornerRadius: 20)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: model.selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }
}

// MARK: - Mutation helpers

@MainActor
private func inspectorCommit(_ model: AppModel, _ label: String, _ body: (inout CanvasDocument) -> Void) {
    var next = model.document
    body(&next)
    model.commitInteractiveEdit(document: next, label: label)
}

@MainActor
private func inspectorStyle(_ model: AppModel, _ node: CanvasNode, _ label: String, _ change: (inout NodeStyle) -> Void) {
    var style = node.style
    change(&style)
    inspectorCommit(model, label) { $0.setStyle(id: node.id, style: style) }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title)
            content
        }
    }
}

private struct InspectorFooter: View {
    @ObservedObject var model: AppModel
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { model.toggleLock() } label: {
                Label(isLocked ? "Unlock" : "Lock", systemImage: isLocked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(GlassButtonStyle(size: 28))
            .help(isLocked ? "Allow editing" : "Prevent editing")
            .accessibilityLabel(isLocked ? "Unlock selection" : "Lock selection")

            Spacer(minLength: 0)

            Button { model.duplicateSelection() } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Duplicate (⌘D)")
            .accessibilityLabel("Duplicate selection")

            Button { model.deleteSelection() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Delete (⌫)")
            .accessibilityLabel("Delete selection")
        }
    }
}

// MARK: - Empty

private struct EmptyInspector: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private let tips = [
        ("cursorarrow.rays", "Click a card to edit it here or in place."),
        ("rectangle.dashed", "Drag a box on empty canvas to pick several."),
        ("command", "Press ⌘K to search and jump anywhere."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "sun.max")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.sunroomAccentDeep)
                .frame(width: 46, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.sunroomAccent.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.sunroomAccent.opacity(0.25), lineWidth: 0.7)
                        }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Select something\non the canvas")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Details for whatever you pick show up here — position, color, and controls that only make sense for that thing.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(tips, id: \.1) { tip in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: tip.0)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.sunroomAccentDeep)
                            .frame(width: 16, height: 16)
                        Text(tip.1)
                            .font(Theme.Typo.row())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
                    }
            }

            Button { model.captureDesktop() } label: {
                Label("Capture desktop", systemImage: "square.on.square.dashed")
            }
            .buttonStyle(GlassButtonStyle(isProminent: true, size: 30))
            .help("Turn every open window into a card on this canvas")
        }
        .padding(.top, 4)
    }
}

// MARK: - Multi selection

private struct MultiInspector: View {
    @ObservedObject var model: AppModel
    let nodes: [CanvasNode]

    private var hasGroup: Bool { nodes.contains { $0.kind == .group } }
    private var allLocked: Bool { !nodes.isEmpty && nodes.allSatisfy(\.isLocked) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("\(nodes.count)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.sunroomAccent.opacity(0.22))
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(nodes.count) items selected").font(.system(size: 13, weight: .semibold))
                    if let bounds = model.selectionBounds {
                        Text("\(Int(bounds.width)) × \(Int(bounds.height))")
                            .font(Theme.Typo.mono())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            InspectorSection("Align") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(CanvasDocument.Alignment.allCases, id: \.rawValue) { alignment in
                        Button { model.align(alignment) } label: {
                            Image(systemName: alignment.symbolName)
                        }
                        .buttonStyle(IconButtonStyle(size: 34))
                        .help(alignment.displayName)
                        .accessibilityLabel(alignment.displayName)
                    }
                }
            }

            InspectorSection("Distribute") {
                HStack(spacing: 6) {
                    distribute("Horizontal", "arrow.left.and.right", true)
                    distribute("Vertical", "arrow.up.and.down", false)
                }
            }

            InspectorSection("Group & Arrange") {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Button { model.groupSelection() } label: {
                            Label("Group", systemImage: "square.on.square").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle(size: 28))
                        .disabled(nodes.count < 2)

                        Button { model.ungroupSelection() } label: {
                            Label("Ungroup", systemImage: "square.split.2x2").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle(size: 28))
                        .disabled(!hasGroup)
                    }

                    Menu {
                        ForEach(LayoutEngine.Arrangement.allCases, id: \.rawValue) { mode in
                            Button(mode.displayName) { model.arrangeSelection(mode) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                            Text("Lay out selection")
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.24), lineWidth: 0.6))
                        }
                        .contentShape(Capsule(style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Arrange selection")
                }
            }

            InspectorSection("Color") {
                AccentSwatches(selection: ColorToken(rawValue: nodes.first?.style.accent ?? "") ?? .sunflower) {
                    model.setAccent($0)
                }
            }

            Hairline()
            InspectorFooter(model: model, isLocked: allLocked)
        }
    }

    private func distribute(_ title: String, _ icon: String, _ horizontal: Bool) -> some View {
        Button { model.distribute(horizontally: horizontal) } label: {
            Image(systemName: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(size: 28))
        .disabled(nodes.count <= 2)
        .help("Distribute \(title.lowercased())")
        .accessibilityLabel("Distribute \(title.lowercased())")
    }
}

// MARK: - Single node

private struct NodeInspector: View {
    @ObservedObject var model: AppModel
    let node: CanvasNode

    @Environment(\.colorScheme) private var colorScheme
    @State private var titleDraft: String
    @State private var textDraft: String
    @State private var opacity: Double
    @FocusState private var titleFocused: Bool
    @FocusState private var textFocused: Bool

    init(model: AppModel, node: CanvasNode) {
        self.model = model
        self.node = node
        _titleDraft = State(initialValue: node.title)
        _textDraft = State(initialValue: node.text)
        _opacity = State(initialValue: node.style.opacity)
    }

    private var tok: ColorToken { ColorToken(rawValue: node.style.accent) ?? .sunflower }
    private var tint: Color { Color(nsColor: Theme.fill(for: tok, isDark: colorScheme == .dark)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: node.kind.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.28 : 0.55))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                            }
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    TextField("Untitled", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .semibold))
                        .focused($titleFocused)
                        .onSubmit(commitTitle)
                        .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
                        .onChange(of: node.title) { _, value in if !titleFocused { titleDraft = value } }
                        .accessibilityLabel("Title")
                    HStack(spacing: 5) {
                        Text(node.kind.displayName)
                        if node.isLocked {
                            Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            InspectorSection("Position & Size") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    NumberField(label: "X", value: node.frame.origin.x) { setFrame(x: $0) }
                    NumberField(label: "Y", value: node.frame.origin.y) { setFrame(y: $0) }
                    NumberField(label: "W", value: node.frame.width) { setFrame(width: $0) }
                        .disabled(!node.isResizable)
                    NumberField(label: "H", value: node.frame.height) { setFrame(height: $0) }
                        .disabled(!node.isResizable)
                }
                .disabled(node.isLocked)
            }

            InspectorSection("Appearance") {
                VStack(spacing: 10) {
                    AccentSwatches(selection: tok) { model.setAccent($0) }

                    if node.kind.isTextual {
                        labelledRow("Text size") {
                            MiniStepper(value: node.style.fontSize, range: 11...28, step: 1) {
                                model.setFontSize(nodeID: node.id, to: $0)
                            }
                        }
                    }

                    labelledRow("Corners") {
                        MiniStepper(value: node.style.cornerRadius, range: 0...40, step: 2) { radius in
                            inspectorStyle(model, node, "Change Corner Radius") { $0.cornerRadius = radius }
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Opacity").font(Theme.Typo.row()).foregroundStyle(.secondary)
                        Slider(value: $opacity, in: 0.1...1, onEditingChanged: { editing in
                            if !editing { inspectorStyle(model, node, "Change Opacity") { $0.opacity = opacity } }
                        })
                        .tint(.sunroomAccent)
                        .controlSize(.small)
                        Text("\(Int((opacity * 100).rounded()))%")
                            .font(Theme.Typo.mono())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .onChange(of: node.style.opacity) { _, value in opacity = value }
                }
                .disabled(node.isLocked)
            }

            kindTools

            Hairline()
            InspectorFooter(model: model, isLocked: node.isLocked)
        }
    }

    @ViewBuilder
    private var kindTools: some View {
        switch node.kind {
        case .window:
            WindowTools(model: model, node: node)
        case .link:
            LinkTools(model: model, node: node)
        case .image:
            InspectorSection("Image") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(node.imageAssetName ?? "No asset")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        guard let name = node.imageAssetName else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.assetURL(for: name)])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(size: 28))
                    .disabled(node.imageAssetName == nil)
                }
            }
        case .note, .text:
            InspectorSection("Text") {
                TextEditor(text: $textDraft)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 11.5))
                    .focused($textFocused)
                    .frame(minHeight: 78)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(textFocused ? Color.sunroomAccent.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 0.7)
                            }
                    }
                    .onChange(of: textFocused) { _, focused in if !focused { commitText() } }
                    .onChange(of: node.text) { _, value in if !textFocused { textDraft = value } }
                    .disabled(node.isLocked)
                    .accessibilityLabel("Body text")
            }
        case .group, .shape:
            EmptyView()
        }
    }

    private func labelledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(Theme.Typo.row()).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            content().frame(width: 96)
        }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != node.title else { return }
        model.renameNode(id: node.id, to: trimmed)
    }

    private func commitText() {
        guard textDraft != node.text else { return }
        model.commitTextEdit(nodeID: node.id, title: node.title, text: textDraft)
    }

    private func setFrame(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        var frame = node.frame
        if let x { frame.origin.x = x }
        if let y { frame.origin.y = y }
        if let width { frame.size.width = max(60, width) }
        if let height { frame.size.height = max(44, height) }
        model.setFrame(nodeID: node.id, to: frame)
    }
}

// MARK: - Kind-specific tools

private struct WindowTools: View {
    @ObservedObject var model: AppModel
    let node: CanvasNode

    var body: some View {
        InspectorSection("Window") {
            VStack(spacing: 8) {
                Toggle("Live previews", isOn: Binding(
                    get: { model.settings.capturePreviews },
                    set: { newValue in
                        model.settings.capturePreviews = newValue
                        if newValue { model.startCapture() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Continuously refresh a snapshot of this window")

                Button { model.focusWindow(for: node) } label: {
                    Label("Focus window", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(isProminent: true, size: 28))

                Button { model.sendWindowToCanvasPosition(node) } label: {
                    Label("Move window here", systemImage: "macwindow.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(size: 28))
                .help("Arrange the real window to match this card's place on the canvas")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                    tool("Center", "scope") { model.centerWindow(node) }
                    tool("Minimize", "minus.square") { model.minimizeWindow(node) }
                    tool("Full screen", "arrow.up.left.and.arrow.down.right") { model.toggleFullScreenWindow(node) }
                    tool("Close", "xmark.square") { model.closeWindow(node) }
                }

                if let reference = node.windowReference {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reference.appName).font(Theme.Typo.rowEmphasis()).lineLimit(1)
                        Text(reference.bundleIdentifier ?? "Unknown bundle")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func tool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(size: 26))
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct LinkTools: View {
    @ObservedObject var model: AppModel
    let node: CanvasNode
    @State private var draft: String

    init(model: AppModel, node: CanvasNode) {
        self.model = model
        self.node = node
        _draft = State(initialValue: node.linkURL ?? node.text)
    }

    private var url: URL? {
        let raw = (node.linkURL ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.contains("://") ? raw : "https://\(raw)")
    }

    var body: some View {
        InspectorSection("Link") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    TextField("https://", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .onSubmit(commit)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
                        }
                        .accessibilityLabel("Link URL")

                    Button {
                        commit()
                        if let url { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help("Open in browser")
                    .accessibilityLabel("Open link")
                }
                if let url {
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func commit() {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard normalized != node.linkURL else { return }
        inspectorCommit(model, "Change Link") { doc in
            guard let index = doc.index(of: node.id) else { return }
            doc.nodes[index].linkURL = normalized
            doc.nodes[index].touch()
            doc.touch()
        }
    }
}

// MARK: - Fields

private struct NumberField: View {
    let label: String
    let value: Double
    let onCommit: (Double) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(label: String, value: Double, onCommit: @escaping (Double) -> Void) {
        self.label = label
        self.value = value
        self.onCommit = onCommit
        _text = State(initialValue: Self.format(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typo.mono())
                .monospacedDigit()
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onChange(of: value) { _, newValue in if !focused { text = Self.format(newValue) } }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(focused ? Color.sunroomAccent.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: 0.7)
                        }
                }
                .accessibilityLabel(label)
        }
        .onAppear { text = Self.format(value) }
    }

    private func commit() {
        if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")), parsed != value {
            onCommit(parsed)
        }
        text = Self.format(value)
    }

    private static func format(_ value: Double) -> String {
        abs(value.rounded() - value) < 0.05 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

private struct MiniStepper: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) { onChange(max(range.lowerBound, value - step)) }
            Text(value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value))
                .font(Theme.Typo.mono())
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            stepButton("plus", enabled: value < range.upperBound) { onChange(min(range.upperBound, value + step)) }
        }
        .frame(height: 26)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary.opacity(0.7) : Color.primary.opacity(0.2))
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }
}

private struct AccentSwatches: View {
    @Environment(\.colorScheme) private var colorScheme
    let selection: ColorToken
    let onSelect: (ColorToken) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
            ForEach(ColorToken.allCases, id: \.rawValue) { token in
                Button { onSelect(token) } label: {
                    Circle()
                        .fill(Color(nsColor: Theme.fill(for: token, isDark: colorScheme == .dark)))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(colorScheme == .dark ? 0.22 : 0.6), lineWidth: 0.7)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(selection == token ? 0.7 : 0), lineWidth: 2)
                                .padding(-3)
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
