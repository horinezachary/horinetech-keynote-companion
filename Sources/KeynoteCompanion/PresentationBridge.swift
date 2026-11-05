import AppKit
import Foundation
import KeynoteCompanionCore

/// Talks to Keynote and PowerPoint through AppleScript. All scripting runs on one serial queue,
/// off the main thread.
final class PresentationBridge {
    struct ScriptError: Error, LocalizedError {
        var app: PresentationApp
        var number: Int
        var message: String
        var errorDescription: String? {
            switch number {
            case -1743:
                return "Not allowed to control \(app.displayName). Turn it on in System Settings > Privacy & Security > Automation."
            case -600:
                return "\(app.displayName) is not running."
            default:
                return "\(app.displayName): \(message) (\(number))"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.horinetech.keynote-companion.bridge", qos: .userInitiated)
    /// Compiled read scripts, one per app, built on the bridge queue the first time they are needed.
    private var readScripts: [PresentationApp: NSAppleScript] = [:]

    static func isRunning(_ app: PresentationApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Reads each of `apps` in turn. An app that is not running reads as not running, and an app
    /// whose script fails is reported in `errors`. Calls back on the main queue.
    func read(
        _ apps: [PresentationApp],
        completion: @escaping ([PresentationApp: KeynoteSnapshot], [PresentationApp: Error]) -> Void
    ) {
        queue.async {
            var readings: [PresentationApp: KeynoteSnapshot] = [:]
            var errors: [PresentationApp: Error] = [:]
            for app in apps {
                switch self.readNow(app) {
                case .success(let snapshot): readings[app] = snapshot
                case .failure(let error): errors[app] = error
                }
            }
            DispatchQueue.main.async { completion(readings, errors) }
        }
    }

    /// Runs a slide-control command against `app`. Calls back on the main queue.
    func perform(
        _ command: Command, on app: PresentationApp, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async {
            let result: Result<Void, Error>
            if let source = Self.source(for: command, app: app) {
                if Self.isRunning(app) {
                    result = Self.run(NSAppleScript(source: source), app: app).map { _ in () }
                } else {
                    result = .failure(ScriptError(app: app, number: -600, message: "Not running"))
                }
            } else {
                result = .success(())
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func readNow(_ app: PresentationApp) -> Result<KeynoteSnapshot, Error> {
        // Check first, so polling never launches the app.
        guard Self.isRunning(app) else { return .success(KeynoteSnapshot(app: app)) }
        if readScripts[app] == nil {
            readScripts[app] = NSAppleScript(source: Self.readSource(app))
        }
        return Self.run(readScripts[app], app: app).map { list in
            KeynoteSnapshot(
                app: app,
                keynoteRunning: true,
                playing: list.atIndex(1)?.booleanValue ?? false,
                document: list.atIndex(2)?.stringValue ?? "",
                slide: Int(list.atIndex(3)?.int32Value ?? 0),
                slideCount: Int(list.atIndex(4)?.int32Value ?? 0),
                notes: list.atIndex(5)?.stringValue ?? "")
        }
    }

    private static func run(_ script: NSAppleScript?, app: PresentationApp) -> Result<NSAppleEventDescriptor, Error> {
        guard let script else {
            return .failure(ScriptError(app: app, number: 0, message: "Could not build the AppleScript"))
        }
        var info: NSDictionary?
        let output = script.executeAndReturnError(&info)
        if let info {
            return .failure(
                ScriptError(
                    app: app,
                    number: info[NSAppleScript.errorNumber] as? Int ?? 0,
                    message: info[NSAppleScript.errorMessage] as? String ?? "AppleScript error"))
        }
        return .success(output)
    }

    // MARK: - Scripts

    /// Every read script returns {playing, document name, slide number, slide count, presenter notes}.
    static func readSource(_ app: PresentationApp) -> String {
        switch app {
        case .keynote: return KeynoteScripts.read
        case .powerpoint: return PowerPointScripts.read
        }
    }

    static func source(for command: Command, app: PresentationApp) -> String? {
        switch app {
        case .keynote: return KeynoteScripts.source(for: command)
        case .powerpoint: return PowerPointScripts.source(for: command)
        }
    }
}
