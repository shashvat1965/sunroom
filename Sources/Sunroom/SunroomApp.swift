import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

@main
struct SunroomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Sunroom", id: "sunroom.main") {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 600)
                .background(WindowConfigurator())
                .onAppear {
                    appDelegate.model = model
                    MenuActionRouter.model = model
                    WindowRegistry.mainWindow = NSApp.windows.first { $0.identifier?.rawValue == "sunroom.main" }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            SunroomCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 580, height: 470)
        }

        MenuBarExtra("Sunroom", systemImage: "sun.max.fill") {
            MenuBarContent(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Window configuration

/// Applies the AppKit window attributes SwiftUI does not expose: a fully
/// transparent title bar, a clear background (so the canvas bleeds to the
/// corners) and a stable identifier for global hot-key summoning.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
            window.identifier = NSUserInterfaceItemIdentifier("sunroom.main")
            window.minSize = NSSize(width: 860, height: 600)
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.tabbingMode = .disallowed
            window.setFrameAutosaveName("SunroomMainWindow")
            // Traffic lights need a little breathing room over the sidebar.
            window.standardWindowButton(.zoomButton)?.isHidden = false
            WindowRegistry.mainWindow = window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
enum WindowRegistry {
    static weak var mainWindow: NSWindow?
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let model {
            model.startCapture()
            if ProcessInfo.processInfo.arguments.contains("--canvas-mode") {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    model.toggleCanvasMode()
                }
            }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--canvas-shot"),
               ProcessInfo.processInfo.arguments.count > index + 1 {
                let directory = ProcessInfo.processInfo.arguments[index + 1]
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await SnapshotMode.captureCanvasMode(model: model, directory: directory)
                    if ProcessInfo.processInfo.arguments.contains("--quit-after-snapshot") {
                        NSApp.terminate(nil)
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--request-permissions") {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    model.requestPermission(.accessibility)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    model.requestPermission(.screenRecording)
                }
            }
            if model.launchOptions.snapshotDirectory != nil {
                Task { @MainActor in
                    // The main window is created by SwiftUI shortly after this.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    let window = WindowRegistry.mainWindow
                        ?? NSApp.windows.first { $0.identifier?.rawValue == "sunroom.main" }
                    await SnapshotMode.runIfRequested(model: model, window: window)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            model?.shutdown()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowRegistry.mainWindow?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(model.canvasMode.phase == .off ? "Put Windows on a Canvas  ⌃⌥Space" : "Leave Canvas Mode  ⌃⌥Space") {
            model.toggleCanvasMode()
        }
        Button("Open Sunroom") {
            NSApp.activate(ignoringOtherApps: true)
            WindowRegistry.mainWindow?.makeKeyAndOrderFront(nil)
        }
        .keyboardShortcut("o", modifiers: [])

        Divider()

        Button("New Note") { model.addNote() }
        Button("New Canvas") { model.newCanvas() }

        Divider()

        if model.summaries.isEmpty {
            Text("No canvases yet")
        } else {
            ForEach(model.summaries.prefix(8)) { summary in
                Button(summary.name) {
                    NSApp.activate(ignoringOtherApps: true)
                    WindowRegistry.mainWindow?.makeKeyAndOrderFront(nil)
                    model.openCanvas(id: summary.id)
                }
            }
        }

        Divider()

        Button("Capture Desktop Windows") { model.captureDesktop() }
            .disabled(!model.hasAccessibility)
        Button("Apply Layout to Desktop") { model.applyLayoutToDesktop() }
            .disabled(!model.hasAccessibility)

        Divider()

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Sunroom") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - Commands

struct SunroomCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Canvas") { model.newCanvas() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Note") { model.addNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Text Card") { model.addText() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("New Frame") { model.addFrame() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Add Image…") { pickImage() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Import Canvas…") { model.importDocument() }
            Button("Export as PNG…") { model.exportPNG() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Save Now") { model.persist(force: true) }
                .keyboardShortcut("s", modifiers: .command)
            Button("Keyboard Shortcuts") { model.isShortcutSheetPresented = true }
                .keyboardShortcut("/", modifiers: .command)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(model.undoLabel.map { "Undo \($0)" } ?? "Undo") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button(model.redoLabel.map { "Redo \($0)" } ?? "Redo") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { model.copySelection(); model.deleteSelection() }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { model.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
            Button("Duplicate") { model.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
            Divider()
            Button("Select All") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("Deselect All") { model.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        CommandMenu("Canvas") {
            Button(model.canvasMode.phase == .off ? "Put Windows on a Canvas" : "Leave Canvas Mode") {
                model.toggleCanvasMode()
            }
            .keyboardShortcut(" ", modifiers: [.control, .option])
            Button("Back to Canvas") { model.canvasMode.surface() }
                .keyboardShortcut(" ", modifiers: [.control, .option, .shift])
                .disabled(!model.canvasMode.isFocused)
            Button("Fit All Windows") { model.canvasMode.fitAll() }
                .disabled(model.canvasMode.phase != .canvas)
            Divider()
            Button("Command Palette…") { model.isPalettePresented = true }
                .keyboardShortcut("k", modifiers: .command)
            Button("Search Canvas…") { model.isPalettePresented = true }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { model.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Fit Everything") { model.fitAll() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Fit Selection") { model.fitSelection() }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            Button("Toggle Grid") {
                model.settings.showGrid.toggle()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Toggle Minimap") {
                model.settings.showMinimap.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Toggle Inspector") {
                model.isInspectorPresented.toggle()
                model.settings.inspectorVisible = model.isInspectorPresented
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Menu("Align") {
                ForEach(CanvasDocument.Alignment.allCases, id: \.self) { alignment in
                    Button(alignment.displayName) { model.align(alignment) }
                }
            }
            Button("Distribute Horizontally") { model.distribute(horizontally: true) }
            Button("Distribute Vertically") { model.distribute(horizontally: false) }
            Divider()
            Button("Group") { model.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
            Button("Ungroup") { model.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Tidy Up") { model.arrangeAll(.grid) }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }

        CommandMenu("Windows") {
            Button("Windows on this Mac…") { model.isWindowLibraryPresented = true }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Capture Desktop Windows") { model.captureDesktop() }
                .keyboardShortcut("c", modifiers: [.control, .option])
                .disabled(!model.hasAccessibility)
            Button("Apply Layout to Desktop") { model.applyLayoutToDesktop() }
                .disabled(!model.hasAccessibility)
            Divider()
            Button("Refresh Window List") { model.refreshWindows() }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Sunroom Help") {
                if let url = URL(string: "https://github.com/shashvat1965/sunroom#readme") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.addImage(from: url)
        }
    }
}
