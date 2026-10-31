import Foundation

/// Wire protocol version. See PROTOCOL.md.
public let protocolVersion = 1
public let defaultPort: UInt16 = 7878
/// Lines longer than this are discarded.
public let maxLineBytes = 1 << 20

/// What the app last read from Keynote.
public struct KeynoteSnapshot: Equatable, Sendable {
    public var keynoteRunning: Bool
    public var playing: Bool
    public var document: String
    /// Slide number as Keynote numbers it (skipped slides not counted). 0 when unknown.
    public var slide: Int
    public var slideCount: Int
    public var notes: String

    public init(
        keynoteRunning: Bool = false, playing: Bool = false, document: String = "",
        slide: Int = 0, slideCount: Int = 0, notes: String = ""
    ) {
        self.keynoteRunning = keynoteRunning
        self.playing = playing
        self.document = document
        self.slide = slide
        self.slideCount = slideCount
        self.notes = notes
    }

    public static let notRunning = KeynoteSnapshot()
}

/// The `state` message.
public struct SlideState: Equatable, Codable, Sendable {
    public var type = "state"
    public var keynoteRunning: Bool
    public var playing: Bool
    public var document: String
    public var slide: Int
    public var slideCount: Int
    public var notes: String
    public var notesPlain: String
    public var labels: [String]

    public init(snapshot: KeynoteSnapshot) {
        let parsed = NotesParser.parse(snapshot.notes)
        keynoteRunning = snapshot.keynoteRunning
        playing = snapshot.playing
        document = snapshot.document
        slide = snapshot.slide
        slideCount = snapshot.slideCount
        notes = parsed.notes
        notesPlain = parsed.plain
        labels = parsed.labels
    }
}

public enum Direction: String, Codable, Sendable {
    case forward, backward
}

/// The `trigger` message: one per label when a slide is arrived on.
public struct Trigger: Equatable, Codable, Sendable {
    public var type = "trigger"
    public var label: String
    public var slide: Int
    public var index: Int
    public var count: Int
    public var direction: Direction

    public init(label: String, slide: Int, index: Int, count: Int, direction: Direction) {
        self.label = label
        self.slide = slide
        self.index = index
        self.count = count
        self.direction = direction
    }
}

public struct HelloMessage: Codable, Equatable, Sendable {
    public var type = "hello"
    public var `protocol` = protocolVersion
    public var app = "KeynoteCompanion"
    public var version: String

    public init(version: String) { self.version = version }
}

public struct HeartbeatMessage: Codable, Equatable, Sendable {
    public var type = "hb"
    public init() {}
}

public struct ErrorMessage: Codable, Equatable, Sendable {
    public var type = "error"
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum StartFrom: Equatable, Sendable {
    case beginning
    case current
    case slide(Int)
}

/// Commands a client can send.
public enum Command: Equatable, Sendable {
    case next
    case previous
    case first
    case last
    case goto(Int)
    case start(StartFrom)
    case stop
    case refresh
}

/// A message received from a client.
public enum ClientMessage: Equatable, Sendable {
    case hello(token: String?)
    case command(Command)
    /// Anything we do not understand. Ignored, so the protocol can grow.
    case unknown
}

public enum WireCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Encodes a message as one line, ending in `\n`.
    public static func line<T: Encodable>(_ message: T) -> Data {
        var data = (try? encoder.encode(message)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    public static func decode(_ line: Data) -> ClientMessage {
        guard
            let obj = try? JSONSerialization.jsonObject(with: line),
            let dict = obj as? [String: Any],
            let type = dict["type"] as? String
        else { return .unknown }

        switch type {
        case "hello":
            return .hello(token: dict["token"] as? String)
        case "cmd":
            guard let cmd = dict["cmd"] as? String else { return .unknown }
            return decodeCommand(cmd, dict).map(ClientMessage.command) ?? .unknown
        default:
            return .unknown
        }
    }

    private static func decodeCommand(_ cmd: String, _ dict: [String: Any]) -> Command? {
        switch cmd {
        case "next": return .next
        case "previous": return .previous
        case "first": return .first
        case "last": return .last
        case "stop": return .stop
        case "refresh": return .refresh
        case "goto":
            guard let n = positiveInt(dict["slide"]) else { return nil }
            return .goto(n)
        case "start":
            switch dict["from"] as? String ?? "beginning" {
            case "beginning": return .start(.beginning)
            case "current": return .start(.current)
            case "slide":
                guard let n = positiveInt(dict["slide"]) else { return nil }
                return .start(.slide(n))
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Accepts JSON numbers and numeric strings, since Companion variables are often strings.
    private static func positiveInt(_ value: Any?) -> Int? {
        let n: Int?
        switch value {
        case let s as String: n = Int(s.trimmingCharacters(in: .whitespaces))
        case let num as NSNumber:
            let d = num.doubleValue
            n = d.rounded() == d ? Int(exactly: d) : nil
        default: n = nil
        }
        guard let n, n >= 1 else { return nil }
        return n
    }
}

/// Splits a byte stream into lines. Tolerates `\r\n` and drops over-long lines.
public struct LineBuffer: Sendable {
    private var buffer = Data()
    private var discarding = false
    public let maxBytes: Int

    public init(maxBytes: Int = maxLineBytes) { self.maxBytes = maxBytes }

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            var line = buffer[buffer.startIndex..<nl]
            buffer = Data(buffer[buffer.index(after: nl)...])
            if discarding {
                discarding = false
                continue
            }
            if line.last == 0x0D { line = line.dropLast() }
            if !line.isEmpty && line.count <= maxBytes { lines.append(Data(line)) }
        }
        if buffer.count > maxBytes {
            buffer.removeAll(keepingCapacity: false)
            discarding = true
        }
        return lines
    }
}
