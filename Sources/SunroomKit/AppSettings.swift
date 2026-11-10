import Foundation
import SunroomCore

/// Persisted, human-facing preferences. Kept separate from the document so a
/// canvas opens the same way on any machine.
public struct AppSettings: Codable, Hashable, Sendable {
    public var appearance: Appearance
    public var accent: ColorToken
    public var showMinimap: Bool
    public var showGrid: Bool
    public var gridStyle: GridStyle
    public var snapEnabled: Bool
    public var snapToGrid: Bool
    public var capturePreviews: Bool
    public var captureInterval: Double
    public var restoreLastCanvas: Bool
    public var reduceMotion: Bool
    public var showWindowCardsInMenuBar: Bool
    public var sidebarWidth: Double
    public var inspectorVisible: Bool
    public var hotKey: HotKeyCenter.Combo

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark

        public var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    public init(
        appearance: Appearance = .system,
        accent: ColorToken = .sunflower,
        showMinimap: Bool = true,
        showGrid: Bool = true,
        gridStyle: GridStyle = .dots,
        snapEnabled: Bool = true,
        snapToGrid: Bool = false,
        capturePreviews: Bool = true,
        captureInterval: Double = 1.0,
        restoreLastCanvas: Bool = true,
        reduceMotion: Bool = false,
        showWindowCardsInMenuBar: Bool = true,
        sidebarWidth: Double = 248,
        inspectorVisible: Bool = false,
        hotKey: HotKeyCenter.Combo = .optionSpace
    ) {
        self.appearance = appearance
        self.accent = accent
        self.showMinimap = showMinimap
        self.showGrid = showGrid
        self.gridStyle = gridStyle
        self.snapEnabled = snapEnabled
        self.snapToGrid = snapToGrid
        self.capturePreviews = capturePreviews
        self.captureInterval = captureInterval
        self.restoreLastCanvas = restoreLastCanvas
        self.reduceMotion = reduceMotion
        self.showWindowCardsInMenuBar = showWindowCardsInMenuBar
        self.sidebarWidth = sidebarWidth
        self.inspectorVisible = inspectorVisible
        self.hotKey = hotKey
    }

    public static let `default` = AppSettings()
}

/// Reads/writes `settings.json` next to the canvases.
public final class SettingsStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(location: StorageLocation = .applicationSupport()) {
        self.url = location.settingsURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public func save(_ settings: AppSettings) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(settings)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Sunroom: could not save settings: \(error.localizedDescription)")
        }
    }
}
