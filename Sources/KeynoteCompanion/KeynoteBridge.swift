import AppKit
import Foundation
import KeynoteCompanionCore

/// Talks to Keynote through AppleScript. All scripting runs on one serial queue, off the main thread.
final class KeynoteBridge {
    static let bundleID = "com.apple.iWork.Keynote"

    struct ScriptError: Error, LocalizedError {
        var number: Int
        var message: String
        var errorDescription: String? {
            switch number {
            case -1743:
                return "Not allowed to control Keynote. Turn it on in System Settings > Privacy & Security > Automation."
            case -600:
                return "Keynote is not running."
            default:
                return "\(message) (\(number))"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.horinetech.keynote-companion.bridge", qos: .userInitiated)
    private lazy var readScript: NSAppleScript? = NSAppleScript(source: Self.readSource)

    /// Reads the front document's current slide. Calls back on the main queue.
    func read(completion: @escaping (Result<KeynoteSnapshot, Error>) -> Void) {
        queue.async {
            let result = self.readNow()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Runs a slide-control command. Calls back on the main queue.
    func perform(_ command: Command, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result: Result<Void, Error>
            if let source = Self.source(for: command) {
                if Self.isRunning {
                    result = Self.run(NSAppleScript(source: source)).map { _ in () }
                } else {
                    result = .failure(ScriptError(number: -600, message: "Keynote is not running"))
                }
            } else {
                result = .success(())
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func readNow() -> Result<KeynoteSnapshot, Error> {
        // Check first, so polling never launches Keynote.
        guard Self.isRunning else { return .success(.notRunning) }
        return Self.run(readScript).map { list in
            KeynoteSnapshot(
                keynoteRunning: true,
                playing: list.atIndex(1)?.booleanValue ?? false,
                document: list.atIndex(2)?.stringValue ?? "",
                slide: Int(list.atIndex(3)?.int32Value ?? 0),
                slideCount: Int(list.atIndex(4)?.int32Value ?? 0),
                notes: list.atIndex(5)?.stringValue ?? "")
        }
    }

    private static func run(_ script: NSAppleScript?) -> Result<NSAppleEventDescriptor, Error> {
        guard let script else {
            return .failure(ScriptError(number: 0, message: "Could not build the AppleScript"))
        }
        var info: NSDictionary?
        let output = script.executeAndReturnError(&info)
        if let info {
            return .failure(
                ScriptError(
                    number: info[NSAppleScript.errorNumber] as? Int ?? 0,
                    message: info[NSAppleScript.errorMessage] as? String ?? "AppleScript error"))
        }
        return .success(output)
    }

    // MARK: - Scripts

    private static let tellKeynote = "tell application id \"\(bundleID)\""

    /// Returns {playing, document name, slide number, slide count, presenter notes}.
    /// Slide numbers and the count leave out skipped slides, as Keynote does.
    static let readSource = """
        \(tellKeynote)
        	set isPlaying to playing
        	if (count of documents) is 0 then return {isPlaying, "", 0, 0, ""}
        	set d to front document
        	set docName to name of d
        	set slideTotal to count of (slides of d whose skipped is false)
        	try
        		set s to current slide of d
        		set n to slide number of s
        		set nt to (presenter notes of s) as text
        	on error
        		set n to 0
        		set nt to ""
        	end try
        	return {isPlaying, docName, n, slideTotal, nt}
        end tell
        """

    /// Picks slide `n` (clamped) among the slides that are not skipped and either jumps to it
    /// in the running slideshow, moves the editor to it, or starts the slideshow from it.
    private static func goSource(_ n: Int, start: Bool) -> String {
        let action =
            start
            ? "start d from dest"
            : """
            if playing then
            			start d from dest
            		else
            			set current slide of d to dest
            		end if
            """
        return """
            \(tellKeynote)
            	if (count of documents) is 0 then return
            	set d to front document
            	set shownSlides to (slides of d whose skipped is false)
            	set n to \(n)
            	if n > (count of shownSlides) then set n to (count of shownSlides)
            	if n < 1 then return
            	set dest to item n of shownSlides
            	\(action)
            end tell
            """
    }

    static func source(for command: Command) -> String? {
        switch command {
        case .next:
            return "\(tellKeynote) to show next"
        case .previous:
            return "\(tellKeynote) to show previous"
        case .first:
            return goSource(1, start: false)
        case .last:
            return goSource(Int(Int32.max), start: false)
        case .goto(let n):
            return goSource(n, start: false)
        case .start(.beginning):
            return goSource(1, start: true)
        case .start(.slide(let n)):
            return goSource(n, start: true)
        case .start(.current):
            return """
                \(tellKeynote)
                	if (count of documents) is 0 then return
                	set d to front document
                	start d from (current slide of d)
                end tell
                """
        case .stop:
            return """
                \(tellKeynote)
                	if playing and (count of documents) > 0 then stop front document
                end tell
                """
        case .refresh:
            return nil
        }
    }
}
