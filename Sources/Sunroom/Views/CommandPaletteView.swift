import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SunroomCore
import SunroomKit

// MARK: - Command model

/// One row in the palette's command section.
///
/// Commands are values, rebuilt from the model whenever the palette renders.
/// `run` is the only side effect; everything the palette shows is derived.
struct PaletteCommand: Identifiable {
    let title: String
    let subtitle: String
    let symbol: String
    let shortcut: String?
    let run: () -> Void

    var id: String { title }
}

/// A flattened result: either an object on the canvas or a command.
private enum PaletteItem: Identifiable {
    case object(NodeSearchHit)
    case command(PaletteCommand)

    var id: String {
        switch self {
        case .object(let hit): return "object:\(hit.id.uuidString)"
        case .command(let command): return "command:\(command.id)"
        }
    }
}

private struct PaletteSection: Identifiable {
    let title: String
    let items: [PaletteItem]
    var id: String { title }
}

/// Data needed to draw a row, independent of where it came from.
private struct PaletteRowContent {
    let symbol: String
    let title: String
    let subtitle: String
    let shortcut: String?
    let tint: Color
}

// MARK: - Palette

/// The command palette: a Spotlight-grade search over canvas objects and every
/// meaningful action in Sunroom.
///
/// The interaction is deliberately unanimated by default (apart from hover and
/// scroll easing) so it feels like a reflex rather than a view transition.
/// RootView owns presentation through `model.isPalettePresented`.
struct CommandPaletteView: View {
    @ObservedObject var model: AppModel

    @State private var query = ""
    @State private var selectionIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    // MARK: Constants

    private static let recentTitles = [
        "New Note",
        "Search Objects",
        "Fit Everything",
        "Capture Desktop Windows",
        "Windows on this Mac",
        "Toggle Inspector",
        "Toggle Minimap",
        "New Canvas",
    ]

    private static let searchCommandTitle = "Search Objects"
    private static let maxObjects = 6

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.settings.reduceMotion
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            panel
                .padding(.top, 110)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: install)
        .onDisappear(perform: teardown)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchRow
            Hairline()
            resultsView
            Hairline()
            footer
        }
        .frame(width: 620)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassPanel(cornerRadius: 20)
    }

    // MARK: Search row

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("", text: $query, prompt: Text("Search objects and commands…"))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onSubmit { activateSelected() }
                .accessibilityLabel("Search objects and commands")

            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            KeyCap("esc")
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .onChange(of: query) { _, _ in
            selectionIndex = 0
        }
    }

    // MARK: Results

    private var resultsView: some View {
        let sections = self.sections
        let items = sections.flatMap(\.items)
        let selectedID = items.indices.contains(clampedSelection) ? items[clampedSelection].id : nil
        let activeSectionID = selectedID.flatMap { id in
            sections.first { $0.items.contains { $0.id == id } }?.id
        }
        let indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let estimatedHeight = CGFloat(items.count) * 44 + CGFloat(sections.count) * 30 + 16
        let height = min(402, max(items.isEmpty ? 140 : 60, estimatedHeight))

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(sections) { section in
                            sectionHeader(section.title, isActive: activeSectionID == section.id)
                            ForEach(section.items) { item in
                                let content = rowContent(for: item)
                                PaletteRow(
                                    content: content,
                                    isSelected: item.id == selectedID,
                                    index: indexByID[item.id] ?? 0,
                                    reduceMotion: reduceMotion,
                                    action: { activate(item) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(height: height)
            .onChange(of: selectionIndex) { _, newValue in
                let current = self.displayItems
                guard current.indices.contains(newValue) else { return }
                let id = current[newValue].id
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: query) { _, _ in
                guard let first = self.displayItems.first else { return }
                if reduceMotion {
                    proxy.scrollTo(first.id, anchor: .top)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(isActive ? Color.secondary : Color.primary.opacity(0.3))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("No results for “\(query)”")
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Text("Try a shorter search, or name a command like “export”.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("↑↓ navigate  ·  ⏎ open  ·  esc close")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text("tab sections  ·  ⌘1–9 open")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    // MARK: Result composition

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Visible sections in display order. Headers are not selectable.
    private var sections: [PaletteSection] {
        guard !trimmedQuery.isEmpty else {
            let recent = recentCommands
            let recentIDs = Set(recent.map(\.id))
            let rest = allCommands.filter { !recentIDs.contains($0.id) }
            var result = [PaletteSection(title: "Recent", items: recent.map(PaletteItem.command))]
            if !rest.isEmpty {
                result.append(PaletteSection(title: "All Commands", items: rest.map(PaletteItem.command)))
            }
            return result
        }

        var result: [PaletteSection] = []
        let objects = model.document.search(trimmedQuery)
            .prefix(Self.maxObjects)
            .map(PaletteItem.object)
        if !objects.isEmpty {
            result.append(PaletteSection(title: "Objects", items: objects))
        }
        let commands = filteredCommands(trimmedQuery)
        if !commands.isEmpty {
            result.append(PaletteSection(title: "Commands", items: commands.map(PaletteItem.command)))
        }
        return result
    }

    /// Flattened, selectable rows — the order ↑/↓ and ⌘1–9 walk.
    private var displayItems: [PaletteItem] {
        sections.flatMap(\.items)
    }

    private var clampedSelection: Int {
        let items = displayItems
        guard !items.isEmpty else { return 0 }
        return min(max(selectionIndex, 0), items.count - 1)
    }

    private var recentCommands: [PaletteCommand] {
        let commands = allCommands
        return Self.recentTitles.compactMap { title in
            commands.first { $0.title == title }
        }
    }

    private func filteredCommands(_ query: String) -> [PaletteCommand] {
        let all = allCommands
        return all
            .compactMap { command -> (PaletteCommand, Int)? in
                let titleScore = FuzzyMatcher.score(query: query, candidate: command.title)?.score
                let subtitleScore = FuzzyMatcher.score(query: query, candidate: command.subtitle).map { $0.score - 12 }
                guard let best = [titleScore, subtitleScore].compactMap({ $0 }).max(), best > 0 else {
                    return nil
                }
                return (command, best)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.title < rhs.0.title
            }
            .map(\.0)
    }

    // MARK: Row content

    private func rowContent(for item: PaletteItem) -> PaletteRowContent {
        switch item {
        case .object(let hit):
            let node = hit.node
            let token = ColorToken(rawValue: node.style.accent) ?? .sunflower
            return PaletteRowContent(
                symbol: node.kind.symbolName,
                title: node.displayLabel,
                subtitle: objectSubtitle(node),
                shortcut: "↵",
                tint: Color(nsColor: Theme.accentNSColor(token))
            )
        case .command(let command):
            return PaletteRowContent(
                symbol: command.symbol,
                title: command.title,
                subtitle: command.subtitle,
                shortcut: command.shortcut,
                tint: Color.primary.opacity(0.55)
            )
        }
    }

    private func objectSubtitle(_ node: CanvasNode) -> String {
        var parts: [String] = [node.kind.displayName]
        if let reference = node.windowReference {
            parts.append(reference.appName)
        } else if let link = node.linkURL, let host = URL(string: link)?.host {
            parts.append(host)
        } else {
            let body = node.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !body.isEmpty {
                parts.append(String(body.prefix(64)))
            } else if let groupID = node.groupID, let group = model.document.node(withID: groupID) {
                parts.append("in \(group.displayLabel)")
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Activation

    private func activateSelected() {
        let items = displayItems
        guard items.indices.contains(clampedSelection) else { return }
        activate(items[clampedSelection])
    }

    private func activate(_ item: PaletteItem) {
        switch item {
        case .object(let hit):
            model.centerOnNode(id: hit.id)
            dismiss()

        case .command(let command):
            if command.title == Self.searchCommandTitle {
                query = ""
                selectionIndex = 0
                focusSearch()
                return
            }
            // Close first so panels and window changes present on a settled
            // screen; the command itself runs one runloop later.
            dismiss()
            let run = command.run
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { run() }
        }
    }

    private func dismiss() {
        model.isPalettePresented = false
        model.isSearchFocused = false
    }

    private func focusSearch() {
        model.isSearchFocused = true
        searchFocused = true
        DispatchQueue.main.async { searchFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { searchFocused = true }
    }

    // MARK: Keyboard

    private func install() {
        model.isSearchFocused = true
        focusSearch()
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    private func teardown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        model.isSearchFocused = false
    }

    /// Returns true when the palette consumed the event.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isPalettePresented, NSApp.modalWindow == nil else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = flags.isEmpty || flags == .shift

        switch event.keyCode {
        case 53: // esc
            dismiss()
            return true
        case 48: // tab
            guard plain else { return false }
            toggleSection()
            return true
        case 125: // ↓
            guard plain else { return false }
            moveSelection(1)
            return true
        case 126: // ↑
            guard plain else { return false }
            moveSelection(-1)
            return true
        case 36, 76: // return, keypad enter
            guard plain else { return false }
            activateSelected()
            return true
        default:
            break
        }

        if flags == .command,
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            if characters.count == 1,
               let digit = characters.first?.wholeNumberValue,
               (1...9).contains(digit) {
                let items = displayItems
                let index = digit - 1
                guard index < items.count else { return true }
                selectionIndex = index
                activate(items[index])
                return true
            }
            if characters == "k" {
                dismiss()
                return true
            }
        }

        return false
    }

    private func moveSelection(_ delta: Int) {
        let items = displayItems
        guard !items.isEmpty else { return }
        let current = min(max(selectionIndex, 0), items.count - 1)
        selectionIndex = min(max(current + delta, 0), items.count - 1)
    }

    private func toggleSection() {
        let items = displayItems
        guard !items.isEmpty else { return }
        let firstObject = items.firstIndex { item in
            if case .object = item { return true }
            return false
        }
        let firstCommand = items.firstIndex { item in
            if case .command = item { return true }
            return false
        }
        guard let firstObject, let firstCommand else { return }

        let current = min(max(selectionIndex, 0), items.count - 1)
        let isOnObject: Bool = {
            if case .object = items[current] { return true }
            return false
        }()
        selectionIndex = isOnObject ? firstCommand : firstObject
    }

    // MARK: Commands

    private var allCommands: [PaletteCommand] {
        let model = self.model
        return [

            // Create
            PaletteCommand(
                title: "New Note",
                subtitle: "Drop a sticky note at the center of the canvas",
                symbol: "note.text",
                shortcut: "⌘N",
                run: { model.addNote() }
            ),
            PaletteCommand(
                title: "New Text Card",
                subtitle: "Add a heading-style text card",
                symbol: "text.alignleft",
                shortcut: "⇧⌘T",
                run: { model.addText() }
            ),
            PaletteCommand(
                title: "New Frame",
                subtitle: "Draw a container frame for a group of cards",
                symbol: "rectangle.dashed",
                shortcut: "⌃⌘F",
                run: { model.addFrame() }
            ),
            PaletteCommand(
                title: "New Canvas",
                subtitle: "Start a blank canvas",
                symbol: "plus.rectangle.on.rectangle",
                shortcut: "⌃⌘N",
                run: { model.newCanvas() }
            ),
            PaletteCommand(
                title: "Add Image…",
                subtitle: "Place an image file on the canvas",
                symbol: "photo",
                shortcut: "⇧⌘I",
                run: { Self.addImage(model) }
            ),
            PaletteCommand(
                title: "Add Link…",
                subtitle: "Place a URL as a link card",
                symbol: "link.badge.plus",
                shortcut: "⌘L",
                run: { Self.addLink(model) }
            ),

            // History and clipboard
            PaletteCommand(
                title: "Undo",
                subtitle: "Step back one edit",
                symbol: "arrow.uturn.backward",
                shortcut: "⌘Z",
                run: { model.undo() }
            ),
            PaletteCommand(
                title: "Redo",
                subtitle: "Reapply the last undone edit",
                symbol: "arrow.uturn.forward",
                shortcut: "⇧⌘Z",
                run: { model.redo() }
            ),
            PaletteCommand(
                title: "Duplicate",
                subtitle: "Copy the selection in place",
                symbol: "plus.square.on.square",
                shortcut: "⌘D",
                run: { model.duplicateSelection() }
            ),
            PaletteCommand(
                title: "Delete",
                subtitle: "Remove the selected objects",
                symbol: "trash",
                shortcut: "⌫",
                run: { model.deleteSelection() }
            ),
            PaletteCommand(
                title: "Copy",
                subtitle: "Copy the selected objects",
                symbol: "doc.on.doc",
                shortcut: "⌘C",
                run: { model.copySelection() }
            ),
            PaletteCommand(
                title: "Paste",
                subtitle: "Paste copied objects onto the canvas",
                symbol: "doc.on.clipboard",
                shortcut: "⌘V",
                run: { model.paste() }
            ),
            PaletteCommand(
                title: "Select All",
                subtitle: "Select every unlocked object",
                symbol: "square.dashed",
                shortcut: "⌘A",
                run: { model.selectAll() }
            ),
            PaletteCommand(
                title: "Deselect",
                subtitle: "Clear the selection",
                symbol: "xmark.square",
                shortcut: "⇧⌘A",
                run: { model.deselectAll() }
            ),

            // Z-order and grouping
            PaletteCommand(
                title: "Bring to Front",
                subtitle: "Move the selection above everything else",
                symbol: "arrow.up.to.line",
                shortcut: "⌘]",
                run: { model.bringToFront() }
            ),
            PaletteCommand(
                title: "Send to Back",
                subtitle: "Move the selection behind everything else",
                symbol: "arrow.down.to.line",
                shortcut: "⌘[",
                run: { model.sendToBack() }
            ),
            PaletteCommand(
                title: "Group",
                subtitle: "Wrap the selection in a frame",
                symbol: "rectangle.3.group",
                shortcut: "⌘G",
                run: { model.groupSelection() }
            ),
            PaletteCommand(
                title: "Ungroup",
                subtitle: "Remove the frame and release its contents",
                symbol: "square.on.square.dashed",
                shortcut: "⇧⌘G",
                run: { model.ungroupSelection() }
            ),

            // Align
            PaletteCommand(
                title: "Align Left",
                subtitle: "Align selected objects to the left edge",
                symbol: "align.horizontal.left",
                shortcut: "⌃⌥L",
                run: { model.align(.left) }
            ),
            PaletteCommand(
                title: "Align Center",
                subtitle: "Center selected objects horizontally",
                symbol: "align.horizontal.center",
                shortcut: "⌃⌥C",
                run: { model.align(.centerHorizontal) }
            ),
            PaletteCommand(
                title: "Align Right",
                subtitle: "Align selected objects to the right edge",
                symbol: "align.horizontal.right",
                shortcut: "⌃⌥R",
                run: { model.align(.right) }
            ),
            PaletteCommand(
                title: "Align Top",
                subtitle: "Align selected objects to the top edge",
                symbol: "align.vertical.top",
                shortcut: "⌃⌥T",
                run: { model.align(.top) }
            ),
            PaletteCommand(
                title: "Align Middle",
                subtitle: "Center selected objects vertically",
                symbol: "align.vertical.center",
                shortcut: "⌃⌥M",
                run: { model.align(.centerVertical) }
            ),
            PaletteCommand(
                title: "Align Bottom",
                subtitle: "Align selected objects to the bottom edge",
                symbol: "align.vertical.bottom",
                shortcut: "⌃⌥B",
                run: { model.align(.bottom) }
            ),
            PaletteCommand(
                title: "Distribute Horizontally",
                subtitle: "Even out the gaps between selected objects",
                symbol: "arrow.left.and.right",
                shortcut: "⌃⌥H",
                run: { model.distribute(horizontally: true) }
            ),
            PaletteCommand(
                title: "Distribute Vertically",
                subtitle: "Even out the vertical gaps in the selection",
                symbol: "arrow.up.and.down",
                shortcut: "⌃⌥V",
                run: { model.distribute(horizontally: false) }
            ),

            // Arrange
            PaletteCommand(
                title: "Arrange as Grid",
                subtitle: "Tidy the selection (or everything) into a grid",
                symbol: "square.grid.3x3",
                shortcut: "⌃⌥1",
                run: { Self.arrange(.grid, model: model) }
            ),
            PaletteCommand(
                title: "Arrange as Rows",
                subtitle: "Lay cards out in a single row",
                symbol: "rectangle.grid.1x2",
                shortcut: "⌃⌥2",
                run: { Self.arrange(.rows, model: model) }
            ),
            PaletteCommand(
                title: "Arrange as Columns",
                subtitle: "Lay cards out in a single column",
                symbol: "rectangle.grid.2x1",
                shortcut: "⌃⌥3",
                run: { Self.arrange(.columns, model: model) }
            ),
            PaletteCommand(
                title: "Arrange as Radial",
                subtitle: "Place cards evenly around a circle",
                symbol: "circle.grid.cross",
                shortcut: "⌃⌥4",
                run: { Self.arrange(.radial, model: model) }
            ),

            // Camera
            PaletteCommand(
                title: "Fit Everything",
                subtitle: "Frame all objects in the window",
                symbol: "arrow.up.left.and.arrow.down.right",
                shortcut: "⇧⌘F",
                run: { model.fitAll() }
            ),
            PaletteCommand(
                title: "Fit Selection",
                subtitle: "Zoom to the selected objects",
                symbol: "viewfinder",
                shortcut: "⌘F",
                run: { model.fitSelection() }
            ),
            PaletteCommand(
                title: "Reset Zoom",
                subtitle: "Return to 100%",
                symbol: "1.magnifyingglass",
                shortcut: "⌘0",
                run: { model.resetZoom() }
            ),
            PaletteCommand(
                title: "Zoom In",
                subtitle: "Zoom in one step",
                symbol: "plus.magnifyingglass",
                shortcut: "⌘+",
                run: { model.zoomIn() }
            ),
            PaletteCommand(
                title: "Zoom Out",
                subtitle: "Zoom out one step",
                symbol: "minus.magnifyingglass",
                shortcut: "⌘-",
                run: { model.zoomOut() }
            ),

            // View
            PaletteCommand(
                title: "Toggle Grid",
                subtitle: "Show or hide the canvas grid",
                symbol: "grid",
                shortcut: "⌃⌘G",
                run: { model.settings.showGrid.toggle() }
            ),
            PaletteCommand(
                title: "Toggle Minimap",
                subtitle: "Show or hide the minimap",
                symbol: "map",
                shortcut: "⇧⌘M",
                run: { model.settings.showMinimap.toggle() }
            ),
            PaletteCommand(
                title: "Toggle Inspector",
                subtitle: "Show or hide the inspector panel",
                symbol: "sidebar.right",
                shortcut: "⌥⌘I",
                run: {
                    model.isInspectorPresented.toggle()
                    model.settings.inspectorVisible = model.isInspectorPresented
                }
            ),

            // Windows
            PaletteCommand(
                title: "Windows on this Mac",
                subtitle: "Browse every manageable window",
                symbol: "macwindow.on.rectangle",
                shortcut: "⇧⌘W",
                run: { model.isWindowLibraryPresented = true }
            ),
            PaletteCommand(
                title: "Capture Desktop Windows",
                subtitle: "Lay out the current desktop as window cards",
                symbol: "square.on.square.dashed",
                shortcut: "⌃⌥C",
                run: { model.captureDesktop() }
            ),
            PaletteCommand(
                title: "Apply Layout to Desktop",
                subtitle: "Move real windows to match their cards",
                symbol: "rectangle.3.group",
                shortcut: "⌃⌥A",
                run: { model.applyLayoutToDesktop() }
            ),

            // Files
            PaletteCommand(
                title: "Export PNG",
                subtitle: "Save the canvas as an image",
                symbol: "square.and.arrow.up",
                shortcut: "⇧⌘E",
                run: { model.exportPNG() }
            ),
            PaletteCommand(
                title: "Export Canvas",
                subtitle: "Save the canvas as a Sunroom file",
                symbol: "arrow.up.doc",
                shortcut: "⌘E",
                run: { model.exportDocument() }
            ),
            PaletteCommand(
                title: "Import Canvas",
                subtitle: "Open a Sunroom file from disk",
                symbol: "square.and.arrow.down",
                shortcut: "⌘O",
                run: { model.importDocument() }
            ),

            // App
            PaletteCommand(
                title: "Toggle Appearance",
                subtitle: "Cycle System, Light and Dark",
                symbol: "circle.lefthalf.filled",
                shortcut: "⌃⌘A",
                run: { Self.cycleAppearance(model) }
            ),
            PaletteCommand(
                title: "Open Settings",
                subtitle: "Open Sunroom's settings window",
                symbol: "gearshape",
                shortcut: "⌘,",
                run: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            ),
            PaletteCommand(
                title: "Keyboard Shortcuts",
                subtitle: "See every shortcut in Sunroom",
                symbol: "keyboard",
                shortcut: "?",
                run: {
                    model.isPalettePresented = false
                    model.isShortcutSheetPresented = true
                }
            ),
            PaletteCommand(
                title: "Search Objects",
                subtitle: "Find something on this canvas",
                symbol: "magnifyingglass",
                shortcut: "⌘K",
                run: {}
            ),
        ]
    }

    // MARK: Command helpers

    private static func arrange(_ mode: LayoutEngine.Arrangement, model: AppModel) {
        if model.selection.count > 1 {
            model.arrangeSelection(mode)
        } else {
            model.arrangeAll(mode)
        }
    }

    private static func addImage(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.title = "Add Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.addImage(from: url)
        }
    }

    private static func addLink(_ model: AppModel) {
        let alert = NSAlert()
        alert.messageText = "Add a Link"
        alert.informativeText = "Paste a URL. Sunroom drops it on the canvas as a link card."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "https://example.com"
        if let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           pasted.count < 300,
           pasted.contains("."),
           !pasted.contains(" ") {
            field.stringValue = pasted
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            model.addLink(field.stringValue)
        }
    }

    private static func cycleAppearance(_ model: AppModel) {
        let all = AppSettings.Appearance.allCases
        let index = all.firstIndex(of: model.settings.appearance) ?? 0
        let next = all[(index + 1) % all.count]
        model.settings.appearance = next
        model.showToast("Appearance: \(next.displayName)", systemImage: "circle.lefthalf.filled")
    }
}

// MARK: - Row

private struct PaletteRow: View {
    let content: PaletteRowContent
    let isSelected: Bool
    let index: Int
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(isSelected ? Color.sunroomAccent.opacity(0.22) : Color.primary.opacity(0.055))
                    Image(systemName: content.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.primary : content.tint)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(content.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Text(content.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let shortcut = content.shortcut {
                    KeyCap(shortcut)
                } else if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.sunroomAccent.opacity(0.16)
                            : (isHovered ? Color.primary.opacity(0.055) : Color.clear)
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.sunroomAccent.opacity(0.45), lineWidth: 0.8)
                        }
                    }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.sunroomAccent)
                        .frame(width: 2, height: 22)
                        .padding(.leading, 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: isHovered)
    }
}
