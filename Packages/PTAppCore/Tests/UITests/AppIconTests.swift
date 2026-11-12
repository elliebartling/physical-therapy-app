import XCTest
@testable import UI

@MainActor
private final class FakeApp: AppIconSetting {
    var supportsAlternateIcons = true
    var alternateIconName: String?
    var failure: Error?
    private(set) var setCalls: [String?] = []

    func setAlternateIconName(_ alternateIconName: String?) async throws {
        setCalls.append(alternateIconName)
        if let failure { throw failure }
        self.alternateIconName = alternateIconName
    }
}

@MainActor
final class AppIconTests: XCTestCase {
    // MARK: Names

    func test_iconName_followsTheAccent_orStaysSignal() {
        XCTAssertNil(AppIconStyle.iconName(style: .rangeOfMotion, accent: .signal, matchesAccent: true),
                     "Range of motion in Signal is the primary icon")
        XCTAssertEqual(AppIconStyle.iconName(style: .week, accent: .sky, matchesAccent: true), "Icon-week-sky")
        XCTAssertEqual(AppIconStyle.iconName(style: .rangeOfMotion, accent: .lilac, matchesAccent: true),
                       "Icon-rangeOfMotion-lilac")
        XCTAssertNil(AppIconStyle.iconName(style: .rangeOfMotion, accent: .lilac, matchesAccent: false))
        XCTAssertEqual(AppIconStyle.iconName(style: .week, accent: .mint, matchesAccent: false), "Icon-week-signal")
    }

    func test_everyStyleAndAccent_hasAnAlternateExceptThePrimary() {
        let names = AppIconStyle.alternateIconNames
        XCTAssertEqual(names.count, AppIconStyle.allCases.count * AccentChoice.allCases.count - 1)
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// Every icon the app can ask for must exist in the asset catalog and be declared
    /// in project.yml, or iOS refuses the switch at runtime.
    func test_everyAlternateIcon_isInTheCatalogAndDeclared() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // UITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PTAppCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo
        let catalog = repo.appendingPathComponent("App/PTApp/Assets.xcassets")
        let projectYML = try String(contentsOf: repo.appendingPathComponent("App/project.yml"), encoding: .utf8)
        let declared = try XCTUnwrap(
            projectYML.split(separator: "\n")
                .first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") }
                .map { line in
                    line.split(separator: ":", maxSplits: 1).last.map {
                        Set($0.replacingOccurrences(of: "\"", with: "").split(separator: " ").map(String.init))
                    } ?? []
                }
        )

        XCTAssertEqual(declared, Set(AppIconStyle.alternateIconNames))
        for name in AppIconStyle.alternateIconNames + ["AppIcon"] {
            for appearance in ["light", "dark", "tinted"] {
                let png = catalog.appendingPathComponent("\(name).appiconset/\(appearance).png")
                XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "missing \(png.lastPathComponent) in \(name)")
            }
        }
    }

    // MARK: Switching

    func test_apply_switchesOnlyWhenTheIconDiffers() async {
        let app = FakeApp()
        let controller = AppIconController(app: { app })

        await controller.apply(style: .week, accent: .sky, matchesAccent: true)
        await controller.apply(style: .week, accent: .sky, matchesAccent: true)

        XCTAssertEqual(app.setCalls, ["Icon-week-sky"], "no second switch, so no second system alert")
        XCTAssertEqual(app.alternateIconName, "Icon-week-sky")
    }

    func test_apply_backToThePrimary_clearsTheAlternate() async {
        let app = FakeApp()
        app.alternateIconName = "Icon-week-sky"
        let controller = AppIconController(app: { app })

        await controller.apply(style: .rangeOfMotion, accent: .signal, matchesAccent: true)

        XCTAssertEqual(app.setCalls, [nil])
    }

    func test_apply_withoutAlternateIconSupport_doesNothing() async {
        let app = FakeApp()
        app.supportsAlternateIcons = false
        let message = await AppIconController(app: { app }).apply(style: .week, accent: .sun, matchesAccent: true)
        XCTAssertNil(message)
        XCTAssertTrue(app.setCalls.isEmpty)
    }

    func test_apply_failure_explains() async {
        struct Refused: Error {}
        let app = FakeApp()
        app.failure = Refused()

        let message = await AppIconController(app: { app }).apply(style: .week, accent: .sun, matchesAccent: true)

        XCTAssertNotNil(message)
        XCTAssertNil(app.alternateIconName)
    }

    func test_settings_surfacesASwitchFailure() async {
        struct Refused: Error {}
        let app = FakeApp()
        app.failure = Refused()
        let name = "AppIconTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsViewModel(defaults: defaults, appIcons: AppIconController(app: { app }))

        await settings.applyAppIcon(style: .week, accent: .mint, matchesAccent: true)

        XCTAssertNotNil(settings.appIconMessage)
    }
}
