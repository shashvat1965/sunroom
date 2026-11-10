import Foundation

/// Where canvases live on disk.
public struct StorageLocation: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var canvasesDirectory: URL { root.appendingPathComponent("Canvases", isDirectory: true) }
    public var assetsDirectory: URL { root.appendingPathComponent("Assets", isDirectory: true) }
    public var backupsDirectory: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    public var quarantineDirectory: URL { root.appendingPathComponent("Recovered", isDirectory: true) }
    public var indexURL: URL { root.appendingPathComponent("index.json") }
    public var settingsURL: URL { root.appendingPathComponent("settings.json") }

    /// `~/Library/Application Support/Sunroom`
    public static func applicationSupport() -> StorageLocation {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return StorageLocation(root: base.appendingPathComponent("Sunroom", isDirectory: true))
    }

    /// A throwaway location for tests and previews.
    public static func temporary(name: String = UUID().uuidString) -> StorageLocation {
        StorageLocation(root: FileManager.default.temporaryDirectory.appendingPathComponent("Sunroom-\(name)", isDirectory: true))
    }

    public func prepare() throws {
        for directory in [canvasesDirectory, assetsDirectory, backupsDirectory, quarantineDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

public enum DocumentStoreError: Error, LocalizedError {
    case canvasNotFound(UUID)
    case unreadable(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .canvasNotFound(let id): return "Canvas \(id.uuidString) could not be found."
        case .unreadable(let detail): return "The canvas file could not be read: \(detail)"
        case .writeFailed(let detail): return "The canvas could not be saved: \(detail)"
        }
    }
}

/// Reads and writes canvas documents as pretty-printed JSON.
///
/// Writes are atomic, previous versions are rotated into `Backups/`, and an
/// unreadable file is quarantined rather than deleted so a user never loses
/// work to a bad parse.
public final class DocumentFileStore {
    public let location: StorageLocation
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager = FileManager.default
    private let maxBackupsPerCanvas = 5

    /// The app-wide store, used by image loading caches.
    public static let defaultStore = DocumentFileStore()

    public init(location: StorageLocation = .applicationSupport()) {
        self.location = location
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: Paths

    public func fileURL(for id: UUID) -> URL {
        location.canvasesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    public func assetURL(for name: String) -> URL {
        location.assetsDirectory.appendingPathComponent(name)
    }

    // MARK: Lifecycle

    public func prepare() throws {
        try location.prepare()
    }

    // MARK: Load

    public func loadCanvas(id: UUID) throws -> CanvasDocument {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DocumentStoreError.canvasNotFound(id)
        }
        do {
            let data = try Data(contentsOf: url)
            var document = try decoder.decode(CanvasDocument.self, from: data)
            document.migrateIfNeeded()
            return document
        } catch {
            quarantine(url)
            throw DocumentStoreError.unreadable(error.localizedDescription)
        }
    }

    /// Loads every canvas file. Corrupt files are quarantined and skipped so one
    /// bad file cannot block the app from launching.
    public func loadAll() -> [CanvasDocument] {
        guard let urls = try? fileManager.contentsOfDirectory(at: location.canvasesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        var documents: [CanvasDocument] = []
        for url in urls where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                var document = try decoder.decode(CanvasDocument.self, from: data)
                document.migrateIfNeeded()
                documents.append(document)
            } catch {
                quarantine(url)
            }
        }
        return documents.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func loadSummaries() -> [CanvasSummary] {
        loadAll().map(\.canvasSummary).sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Save

    public func save(_ document: CanvasDocument) throws {
        try location.prepare()
        let url = fileURL(for: document.id)
        if fileManager.fileExists(atPath: url.path) {
            backup(url, canvasID: document.id)
        }
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw DocumentStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Copies a file into Assets and returns its asset name.
    public func importAsset(from sourceURL: URL) throws -> String {
        try location.prepare()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        let destination = assetURL(for: name)
        try fileManager.copyItem(at: sourceURL, to: destination)
        return name
    }

    public func importAsset(data: Data, preferredExtension: String) throws -> String {
        try location.prepare()
        let name = "\(UUID().uuidString).\(preferredExtension)"
        try data.write(to: assetURL(for: name), options: [.atomic])
        return name
    }

    // MARK: Backups

    private func backup(_ url: URL, canvasID: UUID) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = location.backupsDirectory.appendingPathComponent("\(canvasID.uuidString)-\(stamp).json")
        try? fileManager.copyItem(at: url, to: destination)
        pruneBackups(for: canvasID)
    }

    private func pruneBackups(for canvasID: UUID) {
        guard let urls = try? fileManager.contentsOfDirectory(at: location.backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        let backups = urls
            .filter { $0.lastPathComponent.hasPrefix(canvasID.uuidString) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
        for stale in backups.dropFirst(maxBackupsPerCanvas) {
            try? fileManager.removeItem(at: stale)
        }
    }

    // MARK: Recovery

    private func quarantine(_ url: URL) {
        try? location.prepare()
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = location.quarantineDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(stamp).broken.json")
        try? fileManager.moveItem(at: url, to: destination)
    }

    // MARK: Export

    public func exportJSON(_ document: CanvasDocument, to url: URL) throws {
        let data = try encoder.encode(document)
        try data.write(to: url, options: [.atomic])
    }

    public func importJSON(from url: URL) throws -> CanvasDocument {
        let data = try Data(contentsOf: url)
        var document = try decoder.decode(CanvasDocument.self, from: data)
        document.migrateIfNeeded()
        // Give an imported document a fresh identity so it never overwrites an
        // existing canvas with a colliding id.
        document.id = UUID()
        document.name = document.name.isEmpty ? "Imported Canvas" : document.name
        document.updatedAt = Date()
        return document
    }
}

// MARK: - Autosave

/// Debounces saves so a typing burst or a drag results in one disk write.
public final class AutosaveController {
    private var pendingWorkItem: DispatchWorkItem?
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let operation: (CanvasDocument) -> Void

    public init(delay: TimeInterval = 0.75, queue: DispatchQueue = .global(qos: .utility), operation: @escaping (CanvasDocument) -> Void) {
        self.delay = delay
        self.queue = queue
        self.operation = operation
    }

    public func schedule(_ document: CanvasDocument) {
        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [operation] in
            operation(document)
        }
        pendingWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Saves immediately, cancelling any pending debounce. Call on quit.
    public func flush(_ document: CanvasDocument) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        operation(document)
    }

    public func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
