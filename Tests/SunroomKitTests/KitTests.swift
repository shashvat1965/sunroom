import XCTest
@testable import SunroomKit
import SunroomCore
import AppKit

final class DesktopPlaneMapperTests: XCTestCase {

    func testCanvasRectMapsDesktopGeometry() {
        let mapper = DesktopPlaneMapper(scale: 0.5, origin: CanvasPoint(x: 100, y: 200))
        let rect = mapper.canvasRect(forDesktopTopLeft: CGRect(x: 20, y: 40, width: 400, height: 300))
        XCTAssertEqual(rect.minX, 110)
        XCTAssertEqual(rect.minY, 220)
        XCTAssertEqual(rect.width, 200)
        XCTAssertEqual(rect.height, 150)
    }

    func testRoundTripThroughCanvasSpace() {
        let mapper = DesktopPlaneMapper(scale: 0.375, origin: CanvasPoint(x: -80, y: 44))
        let original = CGRect(x: 12, y: 30, width: 640, height: 480)
        let canvas = mapper.canvasRect(forDesktopTopLeft: original)
        let back = mapper.desktopTopLeftRect(forCanvas: canvas)
        XCTAssertEqual(back.origin.x, original.origin.x, accuracy: 1e-9)
        XCTAssertEqual(back.origin.y, original.origin.y, accuracy: 1e-9)
        XCTAssertEqual(back.width, original.width, accuracy: 1e-9)
        XCTAssertEqual(back.height, original.height, accuracy: 1e-9)
    }

    func testScaleIsClampedAwayFromZero() {
        let mapper = DesktopPlaneMapper(scale: 0)
        XCTAssertGreaterThan(mapper.scale, 0)
    }

    func testFittingCentersTheScreensInsideTheTarget() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        ]
        let target = CanvasRect(x: 0, y: 0, width: 1200, height: 800)
        let mapper = DesktopPlaneMapper.fitting(screens: screens, target: target, padding: 50)
        let union = screens.reduce(CGRect.null) { $0.union($1) }
        let mappedUnion = mapper.canvasRect(forDesktopTopLeft: union)
        XCTAssertGreaterThan(mappedUnion.width, 0)
        XCTAssertLessThanOrEqual(mappedUnion.width, target.width - 100 + 0.001)
        // Horizontally centred within the padding box.
        let leftGap = mappedUnion.minX - target.minX
        let rightGap = target.maxX - mappedUnion.maxX
        XCTAssertEqual(leftGap, rightGap, accuracy: 0.5)
    }

    func testFittingWithEmptyScreensReturnsIdentityishMapper() {
        let mapper = DesktopPlaneMapper.fitting(screens: [], target: CanvasRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(mapper.scale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mapper.origin, .zero)
    }

    func testAppKitFrameClampsIntoTheUsableScreen() {
        let mapper = DesktopPlaneMapper(scale: 1, origin: .zero)
        let usable = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // A card far off the left of the desktop coordinate space.
        let target = mapper.appKitFrame(forCanvas: CanvasRect(x: -4000, y: -4000, width: 600, height: 400), usableScreen: usable)
        XCTAssertGreaterThanOrEqual(target.minX, usable.minX)
        XCTAssertGreaterThanOrEqual(target.minY, usable.minY)
        XCTAssertLessThanOrEqual(target.maxX, usable.maxX + 0.001)
        XCTAssertLessThanOrEqual(target.maxY, usable.maxY + 0.001)
    }

    func testAppKitFrameEnforcesAMinimumSize() {
        let mapper = DesktopPlaneMapper(scale: 0.1, origin: .zero)
        let usable = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = mapper.appKitFrame(forCanvas: CanvasRect(x: 100, y: 100, width: 100, height: 100), usableScreen: usable)
        XCTAssertGreaterThanOrEqual(target.width, 240)
        XCTAssertGreaterThanOrEqual(target.height, 160)
    }
}

final class ScreenGeometryTests: XCTestCase {

    func testTopLeftAndAppKitConversionsRoundTrip() {
        let rect = CGRect(x: 120, y: 60, width: 800, height: 600)
        let flipped = ScreenGeometry.topLeftRect(fromAppKit: rect)
        let back = ScreenGeometry.appKitRect(fromTopLeft: flipped)
        XCTAssertEqual(back.origin.x, rect.origin.x, accuracy: 1e-9)
        XCTAssertEqual(back.origin.y, rect.origin.y, accuracy: 1e-9)
        XCTAssertEqual(back.width, rect.width, accuracy: 1e-9)
        XCTAssertEqual(back.height, rect.height, accuracy: 1e-9)
    }

    func testConversionIsVerticallySymmetricAroundThePrimaryDisplay() {
        let full = CGRect(x: 0, y: 0, width: 100, height: 200)
        let topLeft = ScreenGeometry.topLeftRect(fromAppKit: full)
        XCTAssertEqual(topLeft.origin.y, ScreenGeometry.primaryHeight - 200, accuracy: 1e-6)
    }
}

final class AppSettingsTests: XCTestCase {

    func testDefaultsAreSensible() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.capturePreviews)
        XCTAssertTrue(settings.snapEnabled)
        XCTAssertFalse(settings.snapToGrid)
        XCTAssertGreaterThan(settings.captureInterval, 0)
        XCTAssertGreaterThan(settings.sidebarWidth, 200)
    }

    func testCodableRoundTrip() throws {
        var settings = AppSettings.default
        settings.appearance = .dark
        settings.accent = .rose
        settings.showMinimap = false
        settings.captureInterval = 2.5
        settings.hotKey = .controlOptionSpace

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testStoreRoundTripsThroughDisk() throws {
        let location = StorageLocation.temporary(name: "settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: location.root) }
        let store = SettingsStore(location: location)

        var settings = AppSettings.default
        settings.showGrid = false
        settings.accent = .mint
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.showGrid, false)
        XCTAssertEqual(loaded.accent, .mint)
    }

    func testStoreReturnsDefaultsForMissingOrCorruptFile() throws {
        let location = StorageLocation.temporary(name: "settings-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: location.root) }
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: location.settingsURL)

        XCTAssertEqual(SettingsStore(location: location).load(), .default)
    }

    func testHotKeyDisplayString() {
        XCTAssertEqual(HotKeyCenter.Combo.optionSpace.displayString, "⌥Space")
        XCTAssertEqual(HotKeyCenter.Combo.controlOptionSpace.displayString, "⌃⌥Space")
        XCTAssertTrue(HotKeyCenter.Combo.optionGrave.displayString.hasSuffix("`"))
    }
}

final class DocumentStoreKitTests: XCTestCase {

    func testStorePreparationCreatesDirectories() throws {
        let location = StorageLocation.temporary(name: "prepare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: location.root) }
        let store = DocumentFileStore(location: location)
        try store.prepare()

        for directory in [location.canvasesDirectory, location.assetsDirectory, location.backupsDirectory, location.quarantineDirectory] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testAssetImportProducesAUniqueName() throws {
        let location = StorageLocation.temporary(name: "asset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: location.root) }
        let store = DocumentFileStore(location: location)
        try store.prepare()

        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let first = try store.importAsset(data: data, preferredExtension: "png")
        let second = try store.importAsset(data: data, preferredExtension: "png")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(for: first).path))
    }
}
