import XCTest

@testable import KeynoteCompanionCore

final class ProtocolTests: XCTestCase {
    private func decode(_ s: String) -> ClientMessage { WireCodec.decode(Data(s.utf8)) }

    private func json(_ data: Data) throws -> [String: Any] {
        XCTAssertEqual(data.last, 0x0A)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any])
    }

    func testDecodesHello() {
        XCTAssertEqual(decode(#"{"type":"hello","protocol":1,"token":"abc"}"#), .hello(token: "abc"))
        XCTAssertEqual(decode(#"{"type":"hello","protocol":1}"#), .hello(token: nil))
    }

    func testDecodesSimpleCommands() {
        let cases: [(String, Command)] = [
            ("next", .next), ("previous", .previous), ("first", .first), ("last", .last),
            ("stop", .stop), ("refresh", .refresh),
        ]
        for (name, cmd) in cases {
            XCTAssertEqual(decode(#"{"type":"cmd","cmd":"\#(name)"}"#), .command(cmd))
        }
    }

    func testDecodesGoto() {
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"goto","slide":5}"#), .command(.goto(5)))
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"goto","slide":" 12 "}"#), .command(.goto(12)))
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"goto","slide":0}"#), .unknown)
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"goto","slide":2.5}"#), .unknown)
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"goto"}"#), .unknown)
    }

    func testDecodesStart() {
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"start"}"#), .command(.start(.beginning)))
        XCTAssertEqual(
            decode(#"{"type":"cmd","cmd":"start","from":"current"}"#), .command(.start(.current)))
        XCTAssertEqual(
            decode(#"{"type":"cmd","cmd":"start","from":"slide","slide":3}"#),
            .command(.start(.slide(3))))
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"start","from":"slide"}"#), .unknown)
    }

    func testUnknownAndGarbageAreIgnored() {
        XCTAssertEqual(decode(#"{"type":"cmd","cmd":"explode"}"#), .unknown)
        XCTAssertEqual(decode(#"{"type":"future"}"#), .unknown)
        XCTAssertEqual(decode("not json"), .unknown)
        XCTAssertEqual(decode("[1,2]"), .unknown)
    }

    func testEncodesStateWithoutBuildFields() throws {
        let state = SlideState(
            snapshot: KeynoteSnapshot(
                keynoteRunning: true, playing: true, document: "Deck", slide: 5, slideCount: 40,
                notes: "Welcome [CAM1]"))
        let obj = try json(WireCodec.line(state))
        XCTAssertEqual(obj["type"] as? String, "state")
        XCTAssertEqual(obj["slide"] as? Int, 5)
        XCTAssertEqual(obj["slideCount"] as? Int, 40)
        XCTAssertEqual(obj["notesPlain"] as? String, "Welcome")
        XCTAssertEqual(obj["labels"] as? [String], ["CAM1"])
        XCTAssertNil(obj["buildsLeft"])
    }

    func testEncodesNewlinesEscaped() {
        let state = SlideState(snapshot: KeynoteSnapshot(keynoteRunning: true, notes: "a\nb"))
        let line = WireCodec.line(state)
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1)
    }

    func testEncodesTriggerAndHello() throws {
        let t = try json(
            WireCodec.line(Trigger(label: "CAM1", slide: 2, index: 0, count: 1, direction: .forward)))
        XCTAssertEqual(t["type"] as? String, "trigger")
        XCTAssertEqual(t["direction"] as? String, "forward")
        let h = try json(WireCodec.line(HelloMessage(version: "1.0.0")))
        XCTAssertEqual(h["protocol"] as? Int, 1)
        XCTAssertEqual(h["app"] as? String, "KeynoteCompanion")
    }

    func testLineBufferSplitsAcrossChunks() {
        var b = LineBuffer()
        XCTAssertEqual(b.append(Data("{\"a\":".utf8)), [])
        XCTAssertEqual(b.append(Data("1}\r\n{\"b\":2}\n\n{\"c\"".utf8)), [Data("{\"a\":1}".utf8), Data("{\"b\":2}".utf8)])
        XCTAssertEqual(b.append(Data(":3}\n".utf8)), [Data("{\"c\":3}".utf8)])
    }

    func testLineBufferDropsOverlongLine() {
        var b = LineBuffer(maxBytes: 8)
        XCTAssertEqual(b.append(Data("0123456789".utf8)), [])
        XCTAssertEqual(b.append(Data("abc\nok\n".utf8)), [Data("ok".utf8)])
    }
}
