import XCTest

@testable import KeynoteCompanionCore

final class NotesParserTests: XCTestCase {
    func testExtractsLabelsInOrder() {
        let p = NotesParser.parse("Welcome everyone. [CAM1] [LIGHTS WARM]")
        XCTAssertEqual(p.labels, ["CAM1", "LIGHTS WARM"])
        XCTAssertEqual(p.plain, "Welcome everyone.")
    }

    func testTrimsAndCollapsesWhitespaceInLabels() {
        XCTAssertEqual(NotesParser.parse("[  CAM   2 ]").labels, ["CAM 2"])
    }

    func testDropsDuplicatesIgnoringCase() {
        XCTAssertEqual(NotesParser.parse("[cam1] text [CAM1] [Cam1] [CAM2]").labels, ["cam1", "CAM2"])
    }

    func testIgnoresEmptyAndMultilineBrackets() {
        let p = NotesParser.parse("[] [   ] [open\nclose] [OK]")
        XCTAssertEqual(p.labels, ["OK"])
    }

    func testNestedBracketsUseInnermost() {
        XCTAssertEqual(NotesParser.parse("[[CAM1]]").labels, ["CAM1"])
    }

    func testNoTags() {
        let p = NotesParser.parse("Just talk.")
        XCTAssertEqual(p.labels, [])
        XCTAssertEqual(p.plain, "Just talk.")
    }

    func testNormalisesNewlines() {
        let p = NotesParser.parse("one\r\ntwo\rthree\u{2028}four")
        XCTAssertEqual(p.notes, "one\ntwo\nthree\nfour")
    }

    func testPlainTidiesWhitespace() {
        let p = NotesParser.parse("  [CAM1]  Hello   there  \n\n\n\n [MUSIC]\nSecond   line ")
        XCTAssertEqual(p.plain, "Hello there\n\nSecond line")
        XCTAssertEqual(p.labels, ["CAM1", "MUSIC"])
    }

    func testOnlyTags() {
        XCTAssertEqual(NotesParser.parse("[CAM1]\n[CAM2]").plain, "")
    }
}
