import AppKit
import SunroomCore
import SunroomKit

/// Right-click menus for the canvas and its objects.
@MainActor
enum ContextMenuBuilder {

    static func menu(for node: CanvasNode, model: AppModel?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: node.displayLabel, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        switch node.kind {
        case .note, .text:
            menu.addItem(item("Edit Text", #selector(MenuActions.editSelected), model: model, key: "e"))
        case .window:
            menu.addItem(item("Focus Window", #selector(MenuActions.focusWindowNode), model: model))
            menu.addItem(item("Move Window Here", #selector(MenuActions.moveWindowNode), model: model))
            menu.addItem(item("Center Window", #selector(MenuActions.centerWindowNode), model: model))
            menu.addItem(item("Full Screen", #selector(MenuActions.fullScreenWindowNode), model: model))
            menu.addItem(item("Minimize Window", #selector(MenuActions.minimizeWindowNode), model: model))
            menu.addItem(item("Close Window", #selector(MenuActions.closeWindowNode), model: model))
            menu.addItem(.separator())
            menu.addItem(item("Refresh Preview", #selector(MenuActions.refreshPreview), model: model))
        case .link:
            menu.addItem(item("Open Link", #selector(MenuActions.openLink), model: model))
        case .image:
            menu.addItem(item("Reveal Image in Finder", #selector(MenuActions.revealImage), model: model))
        case .group:
            menu.addItem(item("Ungroup", #selector(MenuActions.ungroupSelection), model: model))
        case .shape:
            break
        }

        menu.addItem(.separator())
        menu.addItem(item("Duplicate", #selector(MenuActions.duplicateSelection), model: model, key: "d"))
        menu.addItem(item("Copy", #selector(MenuActions.copySelection), model: model, key: "c"))
        menu.addItem(.separator())
        menu.addItem(item("Bring to Front", #selector(MenuActions.bringToFront), model: model))
        menu.addItem(item("Send to Back", #selector(MenuActions.sendToBack), model: model))
        menu.addItem(.separator())

        let colors = NSMenu(title: "Color")
        for token in ColorToken.allCases {
            let colorItem = item(token.displayName, #selector(MenuActions.setAccentColor(_:)), model: model)
            colorItem.representedObject = token.rawValue
            colors.addItem(colorItem)
        }
        let colorHolder = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorHolder.submenu = colors
        menu.addItem(colorHolder)

        let arrange = NSMenu(title: "Arrange")
        for mode in LayoutEngine.Arrangement.allCases {
            let arrangeItem = item(mode.displayName, #selector(MenuActions.arrangeSelectionMode(_:)), model: model)
            arrangeItem.representedObject = mode.rawValue
            arrange.addItem(arrangeItem)
        }
        let arrangeHolder = NSMenuItem(title: "Arrange Selection", action: nil, keyEquivalent: "")
        arrangeHolder.submenu = arrange
        menu.addItem(arrangeHolder)

        menu.addItem(item(node.isLocked ? "Unlock" : "Lock", #selector(MenuActions.toggleLock), model: model))
        menu.addItem(.separator())
        menu.addItem(item("Delete", #selector(MenuActions.deleteSelection), model: model, key: "\u{8}"))
        return menu
    }

    static func canvasMenu(model: AppModel?, at point: CanvasPoint) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let noteItem = item("New Note Here", #selector(MenuActions.addNoteAtPoint(_:)), model: model)
        noteItem.representedObject = "\(point.x),\(point.y)"
        menu.addItem(noteItem)

        let textItem = item("New Text Here", #selector(MenuActions.addTextAtPoint(_:)), model: model)
        textItem.representedObject = "\(point.x),\(point.y)"
        menu.addItem(textItem)

        let frameItem = item("New Frame Here", #selector(MenuActions.addFrameAtPoint(_:)), model: model)
        frameItem.representedObject = "\(point.x),\(point.y)"
        menu.addItem(frameItem)

        menu.addItem(.separator())
        menu.addItem(item("Paste", #selector(MenuActions.paste), model: model, key: "v"))
        menu.addItem(item("Select All", #selector(MenuActions.selectAll), model: model, key: "a"))
        menu.addItem(.separator())
        menu.addItem(item("Fit Everything", #selector(MenuActions.fitAll), model: model))
        menu.addItem(item("Reset Zoom", #selector(MenuActions.resetZoom), model: model))
        menu.addItem(.separator())
        menu.addItem(item("Capture Desktop Windows", #selector(MenuActions.captureDesktop), model: model))
        menu.addItem(item("Apply Layout to Desktop", #selector(MenuActions.applyLayout), model: model))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, model: AppModel?, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = MenuActions.shared
        menuItem.isEnabled = model != nil
        return menuItem
    }
}

/// ObjC-visible target for menu actions so AppKit can dispatch them.
@MainActor
final class MenuActions: NSObject {
    static let shared = MenuActions()

    private var model: AppModel? { MenuActionRouter.model }
    private func point(from sender: NSMenuItem) -> CanvasPoint? {
        guard let raw = sender.representedObject as? String else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CanvasPoint(x: parts[0], y: parts[1])
    }

    @objc func editSelected() {
        guard let model, let id = model.selection.first, let node = model.document.node(withID: id) else { return }
        model.editingNodeID = node.id
    }

    @objc func focusWindowNode() { selectedNode().flatMap { model?.focusWindow(for: $0) } }
    @objc func moveWindowNode() { selectedNode().flatMap { model?.sendWindowToCanvasPosition($0) } }
    @objc func centerWindowNode() { selectedNode().flatMap { model?.centerWindow($0) } }
    @objc func fullScreenWindowNode() { selectedNode().flatMap { model?.toggleFullScreenWindow($0) } }
    @objc func minimizeWindowNode() { selectedNode().flatMap { model?.minimizeWindow($0) } }
    @objc func closeWindowNode() { selectedNode().flatMap { model?.closeWindow($0) } }

    @objc func refreshPreview() {
        guard let ref = selectedNode()?.windowReference else { return }
        model?.capture.requestSnapshot(windowNumber: ref.windowNumber, force: true)
    }

    @objc func openLink() {
        guard let raw = selectedNode()?.linkURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func revealImage() {
        guard let name = selectedNode()?.imageAssetName, let model else { return }
        NSWorkspace.shared.activateFileViewerSelecting([model.store.assetURL(for: name)])
    }

    @objc func duplicateSelection() { model?.duplicateSelection() }
    @objc func copySelection() { model?.copySelection() }
    @objc func paste() { model?.paste() }
    @objc func deleteSelection() { model?.deleteSelection() }
    @objc func selectAll() { model?.selectAll() }
    @objc func bringToFront() { model?.bringToFront() }
    @objc func sendToBack() { model?.sendToBack() }
    @objc func toggleLock() { model?.toggleLock() }
    @objc func ungroupSelection() { model?.ungroupSelection() }
    @objc func fitAll() { model?.fitAll() }
    @objc func resetZoom() { model?.resetZoom() }
    @objc func captureDesktop() { model?.captureDesktop() }
    @objc func applyLayout() { model?.applyLayoutToDesktop() }

    @objc func setAccentColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let token = ColorToken(rawValue: raw) else { return }
        model?.setAccent(token)
    }

    @objc func arrangeSelectionMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = LayoutEngine.Arrangement(rawValue: raw) else { return }
        model?.arrangeSelection(mode)
    }

    @objc func addNoteAtPoint(_ sender: NSMenuItem) {
        model?.addNote(at: point(from: sender))
    }

    @objc func addTextAtPoint(_ sender: NSMenuItem) {
        model?.addText(at: point(from: sender))
    }

    @objc func addFrameAtPoint(_ sender: NSMenuItem) {
        model?.addFrame(at: point(from: sender))
    }

    private func selectedNode() -> CanvasNode? {
        guard let model, let id = model.selection.first else { return nil }
        return model.document.node(withID: id)
    }
}

/// Keeps a weak reference to the model for menu actions without making every
/// menu item hold a strong graph.
@MainActor
enum MenuActionRouter {
    static weak var model: AppModel?
}
