import XCTest

@testable import KeynoteCompanionCore

final class SourcePickerTests: XCTestCase {
    private func running(_ app: PresentationApp, playing: Bool = false) -> KeynoteSnapshot {
        KeynoteSnapshot(app: app, keynoteRunning: true, playing: playing, document: "Deck", slide: 1, slideCount: 3)
    }

    private func pick(
        _ readings: [PresentationApp: KeynoteSnapshot], front: PresentationApp? = nil,
        current: PresentationApp = .keynote, choice: AppChoice = .automatic
    ) -> PresentationApp {
        SourcePicker.pick(choice, readings: readings, lastFrontmost: front, current: current)
    }

    func testFixedChoiceWins() {
        XCTAssertEqual(pick([.keynote: running(.keynote, playing: true)], choice: .powerpoint), .powerpoint)
        XCTAssertEqual(pick([.powerpoint: running(.powerpoint, playing: true)], choice: .keynote), .keynote)
    }

    func testPresentingAppWins() {
        let r: [PresentationApp: KeynoteSnapshot] = [.keynote: running(.keynote), .powerpoint: running(.powerpoint, playing: true)]
        XCTAssertEqual(pick(r, front: .keynote, current: .keynote), .powerpoint)
    }

    func testBothPresentingStaysPut() {
        let r: [PresentationApp: KeynoteSnapshot] = [.keynote: running(.keynote, playing: true), .powerpoint: running(.powerpoint, playing: true)]
        XCTAssertEqual(pick(r, front: .powerpoint, current: .keynote), .keynote)
    }

    func testNeitherPresentingFollowsFrontmost() {
        let r: [PresentationApp: KeynoteSnapshot] = [.keynote: running(.keynote), .powerpoint: running(.powerpoint)]
        XCTAssertEqual(pick(r, front: .powerpoint, current: .keynote), .powerpoint)
        XCTAssertEqual(pick(r, front: nil, current: .powerpoint), .powerpoint)
    }

    func testFrontmostIgnoredWhenNotRunning() {
        let r: [PresentationApp: KeynoteSnapshot] = [
            .keynote: running(.keynote), .powerpoint: KeynoteSnapshot(app: .powerpoint),
        ]
        XCTAssertEqual(pick(r, front: .powerpoint, current: .powerpoint), .keynote)
    }

    func testNothingRunningKeepsCurrent() {
        let r: [PresentationApp: KeynoteSnapshot] = [
            .keynote: KeynoteSnapshot(app: .keynote), .powerpoint: KeynoteSnapshot(app: .powerpoint),
        ]
        XCTAssertEqual(pick(r, current: .powerpoint), .powerpoint)
    }

    func testBundleIDLookup() {
        XCTAssertEqual(PresentationApp(bundleID: "com.microsoft.Powerpoint"), .powerpoint)
        XCTAssertEqual(PresentationApp(bundleID: "com.apple.iWork.Keynote"), .keynote)
        XCTAssertNil(PresentationApp(bundleID: "com.apple.Safari"))
    }
}
