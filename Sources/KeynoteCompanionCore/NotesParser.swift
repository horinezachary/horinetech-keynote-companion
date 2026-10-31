import Foundation

/// Presenter notes split into the trigger labels they carry and the text without tags.
public struct ParsedNotes: Equatable, Sendable {
    /// Notes with newlines normalised to `\n`, tags included.
    public var notes: String
    /// Notes with every `[...]` tag removed and whitespace tidied.
    public var plain: String
    /// Labels in the order they appear, trimmed, duplicates (ignoring case) removed.
    public var labels: [String]

    public init(notes: String, plain: String, labels: [String]) {
        self.notes = notes
        self.plain = plain
        self.labels = labels
    }
}

public enum NotesParser {
    // A tag is `[` ... `]` on one line, with no nested brackets.
    private static let tagPattern = try! NSRegularExpression(pattern: "\\[([^\\[\\]\\n]*)\\]")
    private static let spacesPattern = try! NSRegularExpression(pattern: "[ \\t]+")
    private static let blankLinesPattern = try! NSRegularExpression(pattern: "\\n{3,}")

    public static func parse(_ raw: String) -> ParsedNotes {
        let notes = normaliseNewlines(raw)
        let ns = notes as NSString
        let matches = tagPattern.matches(in: notes, range: NSRange(location: 0, length: ns.length))

        var labels: [String] = []
        var seen = Set<String>()
        for match in matches {
            let label = collapseSpaces(ns.substring(with: match.range(at: 1)))
                .trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            let key = label.uppercased()
            if seen.insert(key).inserted {
                labels.append(label)
            }
        }

        let stripped = tagPattern.stringByReplacingMatches(
            in: notes, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        let lines = stripped
            .components(separatedBy: "\n")
            .map { collapseSpaces($0).trimmingCharacters(in: .whitespaces) }
        let joined = lines.joined(separator: "\n")
        let plain = blankLinesPattern.stringByReplacingMatches(
            in: joined, range: NSRange(location: 0, length: (joined as NSString).length),
            withTemplate: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedNotes(notes: notes, plain: plain, labels: labels)
    }

    static func normaliseNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    private static func collapseSpaces(_ s: String) -> String {
        spacesPattern.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
    }
}
