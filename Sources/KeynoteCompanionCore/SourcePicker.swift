import Foundation

/// Which presentation app to follow, as chosen in Settings.
public enum AppChoice: String, CaseIterable, Sendable {
    case automatic
    case keynote
    case powerpoint

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .keynote: return "Keynote"
        case .powerpoint: return "PowerPoint"
        }
    }

    /// The fixed app, or nil for automatic.
    public var fixed: PresentationApp? {
        switch self {
        case .automatic: return nil
        case .keynote: return .keynote
        case .powerpoint: return .powerpoint
        }
    }
}

/// Decides which app to follow when the choice is automatic.
public enum SourcePicker {
    /// - Parameters:
    ///   - readings: the latest reading of each app that was read.
    ///   - lastFrontmost: whichever of the apps was most recently brought to the front.
    ///   - current: the app followed so far.
    ///
    /// Rules, in order: an app that is presenting wins over one that is not; if both or neither
    /// are presenting, the one most recently in front wins if it is running; otherwise stay on the
    /// current app while it runs; otherwise any running app; otherwise the current app.
    public static func pick(
        _ choice: AppChoice,
        readings: [PresentationApp: KeynoteSnapshot],
        lastFrontmost: PresentationApp?,
        current: PresentationApp
    ) -> PresentationApp {
        if let fixed = choice.fixed { return fixed }

        let running = PresentationApp.allCases.filter { readings[$0]?.keynoteRunning == true }
        let playing = running.filter { readings[$0]?.playing == true }

        if playing.count == 1 { return playing[0] }
        if playing.count > 1, playing.contains(current) { return current }
        if let front = lastFrontmost, running.contains(front) { return front }
        if running.contains(current) { return current }
        return running.first ?? current
    }
}
