import XCTest
@testable import SunroomCore

final class DocumentStoreTests: XCTestCase {

    private var root: URL!
    private var location: StorageLocation!
    private var store: DocumentFileStore!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("SunroomTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        location = StorageLocation(root: root)
        store = DocumentFileStore(location: location)
        try store.prepare()
    }

    override func tearDownWithError() throws {
        if let root {
            try? fileManager.removeItem(at: root)
        }
        root = nil
        location = nil
        store = nil
        try super.tearDownWithError()
    }

    private func sampleDocument(name: String = "Saved Canvas") -> CanvasDocument {
        makeDocument(
            name: name,
            nodes: [
                makeNode(kind: .note, frame: rect(0, 0, 100, 80), title: "Note", text: "Hello"),
                makeNode(kind: .window, frame: rect(200, 0, 300, 200), title: "Window", windowReference: windowReference()),
            ],
            transform: CanvasTransform(translation: pt(10, 20), zoom: 1.5),
            background: .paper,
            gridStyle: .lines,
            gridSpacing: 24,
            notes: "Stored notes"
        )
    }

    private func files(in directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    // MARK: Lifecycle & paths

    func testPrepareCreatesDirectories() throws {
        for directory in [
            location.canvasesDirectory,
            location.assetsDirectory,
            location.backupsDirectory,
            location.quarantineDirectory,
        ] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testFileURLsUseExpectedLayout() {
        let id = UUID()
        XCTAssertEqual(
            store.fileURL(for: id),
            location.canvasesDirectory.appendingPathComponent("\(id.uuidString).json")
        )
        XCTAssertTrue(store.assetURL(for: "a.png").path.hasPrefix(location.assetsDirectory.path))
    }

    // MARK: Save / load

    func testSaveAndLoadRoundTrip() throws {
        let document = sampleDocument()
        try store.save(document)

        XCTAssertTrue(fileManager.fileExists(atPath: store.fileURL(for: document.id).path))
        let loaded = try store.loadCanvas(id: document.id)

        XCTAssertEqual(loaded, document)
        XCTAssertEqual(loaded.name, "Saved Canvas")
        XCTAssertEqual(loaded.nodes.count, 2)
        XCTAssertEqual(loaded.transform, document.transform)
        XCTAssertEqual(loaded.createdAt, document.createdAt)
        XCTAssertEqual(loaded.updatedAt, document.updatedAt)
        XCTAssertEqual(loaded.background, .paper)
        XCTAssertEqual(loaded.gridStyle, .lines)
        XCTAssertEqual(loaded.gridSpacing, 24)
        XCTAssertEqual(loaded.notes, "Stored notes")
    }

    func testLoadMissingCanvasThrowsCanvasNotFound() {
        let id = UUID()
        XCTAssertThrowsError(try store.loadCanvas(id: id)) { error in
            guard case DocumentStoreError.canvasNotFound(let missingID) = error else {
                return XCTFail("Expected canvasNotFound, got \(error)")
            }
            XCTAssertEqual(missingID, id)
        }
    }

    func testOverwriteReplacesContentsAtomically() throws {
        var document = sampleDocument(name: "First")
        try store.save(document)

        document.name = "Second"
        document.nodes = [makeNode(title: "Only")]
        try store.save(document)

        let loaded = try store.loadCanvas(id: document.id)
        XCTAssertEqual(loaded.name, "Second")
        XCTAssertEqual(loaded.nodes.count, 1)

        let canvasFiles = files(in: location.canvasesDirectory).filter { $0.pathExtension == "json" }
        XCTAssertEqual(canvasFiles.count, 1, "Atomic write must not leave temp files")
    }

    func testSaveCreatesBackupOnOverwrite() throws {
        let document = sampleDocument()
        try store.save(document)
        XCTAssertTrue(files(in: location.backupsDirectory).isEmpty, "First save has nothing to back up")

        try store.save(document)
        let backups = files(in: location.backupsDirectory)
            .filter { $0.lastPathComponent.hasPrefix(document.id.uuidString) }
        XCTAssertEqual(backups.count, 1)
    }

    func testBackupsArePrunedToFiveMostRecent() throws {
        let document = sampleDocument()
        try store.save(document)

        // Seed seven older backups with distinct modification dates.
        for index in 0..<7 {
            let url = location.backupsDirectory
                .appendingPathComponent("\(document.id.uuidString)-old-\(index).json")
            try Data("{}".utf8).write(to: url)
            try fileManager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000 + Double(index))],
                ofItemAtPath: url.path
            )
        }
        XCTAssertEqual(files(in: location.backupsDirectory).count, 7)

        try store.save(document)

        let remaining = files(in: location.backupsDirectory)
            .filter { $0.lastPathComponent.hasPrefix(document.id.uuidString) }
        XCTAssertEqual(remaining.count, 5)

        let names = Set(remaining.map(\.lastPathComponent))
        XCTAssertTrue(names.contains { $0.contains("old-6") }, "Newest old backup is kept")
        XCTAssertFalse(names.contains { $0.contains("old-0") }, "Oldest backup is pruned")
        XCTAssertFalse(names.contains { $0.contains("old-1") })
    }

    // MARK: Corruption & recovery

    func testCorruptCanvasIsQuarantinedAndRemovedFromCanvases() throws {
        let id = UUID()
        let url = store.fileURL(for: id)
        try Data("{ this is not valid json".utf8).write(to: url)

        XCTAssertThrowsError(try store.loadCanvas(id: id)) { error in
            guard case DocumentStoreError.unreadable = error else {
                return XCTFail("Expected unreadable, got \(error)")
            }
        }

        XCTAssertFalse(fileManager.fileExists(atPath: url.path), "Corrupt file is moved out of Canvases")

        let recovered = files(in: location.quarantineDirectory)
        XCTAssertEqual(recovered.count, 1)
        XCTAssertTrue(recovered[0].lastPathComponent.hasSuffix(".broken.json"))
        XCTAssertTrue(recovered[0].lastPathComponent.hasPrefix(id.uuidString))
    }

    func testLoadAllSkipsAndQuarantinesCorruptFiles() throws {
        let first = sampleDocument(name: "First")
        let second = sampleDocument(name: "Second")
        try store.save(first)
        try store.save(second)

        let corrupt = location.canvasesDirectory.appendingPathComponent("corrupt.json")
        try Data("not json at all".utf8).write(to: corrupt)

        let loaded = store.loadAll()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(Set(loaded.map(\.name)), ["First", "Second"])
        XCTAssertFalse(fileManager.fileExists(atPath: corrupt.path))
        XCTAssertEqual(files(in: location.quarantineDirectory).count, 1)
    }

    func testLoadAllOnMissingDirectoryReturnsEmpty() {
        try? fileManager.removeItem(at: location.canvasesDirectory)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testLoadAllSortsNewestUpdatedAtFirst() throws {
        var older = sampleDocument(name: "Older")
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        var newer = sampleDocument(name: "Newer")
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        try store.save(older)
        try store.save(newer)

        XCTAssertEqual(store.loadAll().map(\.name), ["Newer", "Older"])
    }

    func testLoadSummaries() throws {
        let document = sampleDocument(name: "Summarized")
        try store.save(document)

        let summaries = store.loadSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].name, "Summarized")
        XCTAssertEqual(summaries[0].nodeCount, 2)
        XCTAssertEqual(summaries[0].previewBounds, rect(0, 0, 500, 200))
    }

    func testLoadMigratesInvalidDocumentValues() throws {
        var document = sampleDocument()
        document.schemaVersion = 0
        document.gridSpacing = 2
        document.transform.zoom = 100
        document.nodes[0].frame = CanvasRect(origin: pt(10, 10), size: sz(-40, -20))
        document.nodes[0].style.opacity = 0
        try store.save(document)

        let loaded = try store.loadCanvas(id: document.id)

        XCTAssertEqual(loaded.schemaVersion, CanvasDocument.currentSchemaVersion)
        XCTAssertEqual(loaded.gridSpacing, 16) // clamped to the minimum at decode time
        XCTAssertEqual(loaded.transform.zoom, 1)
        XCTAssertEqual(loaded.nodes[0].frame, rect(-30, -10, 40, 20))
        XCTAssertEqual(loaded.nodes[0].style.opacity, 1)
    }

    // MARK: Import / export

    func testExportThenImportAssignsFreshID() throws {
        let document = sampleDocument(name: "Exported")
        let exportURL = root.appendingPathComponent("export.json")
        try store.exportJSON(document, to: exportURL)
        XCTAssertTrue(fileManager.fileExists(atPath: exportURL.path))

        let imported = try store.importJSON(from: exportURL)

        XCTAssertNotEqual(imported.id, document.id)
        XCTAssertEqual(imported.name, "Exported")
        XCTAssertEqual(imported.nodes.count, document.nodes.count)
        XCTAssertEqual(imported.nodes.map(\.title), document.nodes.map(\.title))
        XCTAssertEqual(imported.transform, document.transform)
    }

    func testImportEmptyNameGetsFallback() throws {
        var document = sampleDocument()
        document.name = ""
        let exportURL = root.appendingPathComponent("unnamed.json")
        try store.exportJSON(document, to: exportURL)

        let imported = try store.importJSON(from: exportURL)
        XCTAssertEqual(imported.name, "Imported Canvas")
    }

    func testImportJSONFromMissingFileThrows() {
        XCTAssertThrowsError(try store.importJSON(from: root.appendingPathComponent("missing.json")))
    }

    // MARK: Assets

    func testImportAssetFromURL() throws {
        let source = root.appendingPathComponent("source.txt")
        let payload = Data("asset bytes".utf8)
        try payload.write(to: source)

        let name = try store.importAsset(from: source)

        XCTAssertTrue(name.hasSuffix(".txt"))
        let destination = store.assetURL(for: name)
        XCTAssertTrue(fileManager.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }

    func testImportAssetUsesDefaultExtensionWhenMissing() throws {
        let source = root.appendingPathComponent("no-extension")
        try Data("bytes".utf8).write(to: source)

        let name = try store.importAsset(from: source)
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertTrue(fileManager.fileExists(atPath: store.assetURL(for: name).path))
    }

    func testImportAssetFromData() throws {
        let payload = Data([0x01, 0x02, 0x03])
        let name = try store.importAsset(data: payload, preferredExtension: "png")

        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertEqual(try Data(contentsOf: store.assetURL(for: name)), payload)
    }

    // MARK: Delete

    func testDeleteRemovesCanvasFile() throws {
        let document = sampleDocument()
        try store.save(document)
        let url = store.fileURL(for: document.id)
        XCTAssertTrue(fileManager.fileExists(atPath: url.path))

        try store.delete(id: document.id)
        XCTAssertFalse(fileManager.fileExists(atPath: url.path))
    }

    func testDeleteMissingCanvasIsNoOp() {
        XCTAssertNoThrow(try store.delete(id: UUID()))
    }

    // MARK: Autosave

    func testAutosaveFlushInvokesOperationImmediatelyAndCancelsPendingWork() {
        var saved: [String] = []
        let controller = AutosaveController(delay: 60, queue: .main) { document in
            saved.append(document.name)
        }
        controller.schedule(makeDocument(name: "Scheduled"))
        controller.flush(makeDocument(name: "Flushed"))

        XCTAssertEqual(saved, ["Flushed"])
        controller.cancel()
    }
}
