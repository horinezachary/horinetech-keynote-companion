import XCTest

@testable import KeynoteCompanionCore

final class TriggerEngineTests: XCTestCase {
    private func snap(
        _ slide: Int, playing: Bool = true, notes: String = "", document: String = "Deck"
    ) -> KeynoteSnapshot {
        KeynoteSnapshot(
            keynoteRunning: true, playing: playing, document: document, slide: slide,
            slideCount: 10, notes: notes)
    }

    func testFirstReadingNeverFires() {
        var e = TriggerEngine()
        let u = e.ingest(snap(3, notes: "[CAM1]"))
        XCTAssertNotNil(u.state)
        XCTAssertEqual(u.triggers, [])
    }

    func testForwardFiresAllLabelsInOrder() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1))
        let u = e.ingest(snap(2, notes: "[CAM1] hello [LIGHTS]"))
        XCTAssertEqual(
            u.triggers,
            [
                Trigger(label: "CAM1", slide: 2, index: 0, count: 2, direction: .forward),
                Trigger(label: "LIGHTS", slide: 2, index: 1, count: 2, direction: .forward),
            ])
        XCTAssertEqual(u.state?.labels, ["CAM1", "LIGHTS"])
        XCTAssertEqual(u.state?.notesPlain, "hello")
    }

    func testSameSlideDoesNotRefire() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1))
        _ = e.ingest(snap(2, notes: "[CAM1]"))
        let u = e.ingest(snap(2, notes: "[CAM1]"))
        XCTAssertNil(u.state)
        XCTAssertEqual(u.triggers, [])
    }

    func testEditingNotesUpdatesStateWithoutFiring() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1))
        _ = e.ingest(snap(2, notes: "[CAM1]"))
        let u = e.ingest(snap(2, notes: "[CAM1] [CAM2]"))
        XCTAssertEqual(u.state?.labels, ["CAM1", "CAM2"])
        XCTAssertEqual(u.triggers, [])
    }

    func testBackwardIsOffByDefault() {
        var e = TriggerEngine()
        _ = e.ingest(snap(3))
        XCTAssertEqual(e.ingest(snap(2, notes: "[CAM1]")).triggers, [])
    }

    func testBackwardWhenEnabled() {
        var e = TriggerEngine(options: TriggerOptions(fireOnBackward: true))
        _ = e.ingest(snap(3))
        let t = e.ingest(snap(2, notes: "[CAM1]")).triggers
        XCTAssertEqual(t.map(\.direction), [.backward])
    }

    func testNotPresentingIsOffByDefault() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1, playing: false))
        XCTAssertEqual(e.ingest(snap(2, playing: false, notes: "[CAM1]")).triggers, [])
    }

    func testNotPresentingWhenEnabled() {
        var e = TriggerEngine(options: TriggerOptions(fireWhenNotPresenting: true))
        _ = e.ingest(snap(1, playing: false))
        XCTAssertEqual(e.ingest(snap(2, playing: false, notes: "[CAM1]")).triggers.count, 1)
    }

    func testStartingSlideshowFiresCurrentSlide() {
        var e = TriggerEngine()
        _ = e.ingest(snap(4, playing: false, notes: "[CAM1]"))
        let t = e.ingest(snap(4, playing: true, notes: "[CAM1]")).triggers
        XCTAssertEqual(t, [Trigger(label: "CAM1", slide: 4, index: 0, count: 1, direction: .forward)])
    }

    func testStartingSlideshowOnEarlierSlideCountsAsForward() {
        var e = TriggerEngine()
        _ = e.ingest(snap(7, playing: false))
        let t = e.ingest(snap(1, playing: true, notes: "[INTRO]")).triggers
        XCTAssertEqual(t.map(\.direction), [.forward])
    }

    func testStoppingSlideshowDoesNotFire() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1))
        _ = e.ingest(snap(2, notes: "[CAM1]"))
        XCTAssertEqual(e.ingest(snap(2, playing: false, notes: "[CAM1]")).triggers, [])
    }

    func testDocumentChangeCountsAsForward() {
        var e = TriggerEngine()
        _ = e.ingest(snap(5, document: "A"))
        let t = e.ingest(snap(1, notes: "[CAM1]", document: "B")).triggers
        XCTAssertEqual(t.map(\.direction), [.forward])
    }

    func testKeynoteLaunchDoesNotFire() {
        var e = TriggerEngine()
        _ = e.ingest(.notRunning)
        XCTAssertEqual(e.ingest(snap(1, notes: "[CAM1]")).triggers, [])
    }

    func testResetMakesNextReadingSilent() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1))
        e.reset()
        XCTAssertEqual(e.ingest(snap(2, notes: "[CAM1]")).triggers, [])
    }

    func testSlideWithoutLabelsFiresNothing() {
        var e = TriggerEngine()
        _ = e.ingest(snap(1))
        let u = e.ingest(snap(2, notes: "no tags"))
        XCTAssertNotNil(u.state)
        XCTAssertEqual(u.triggers, [])
    }
}
