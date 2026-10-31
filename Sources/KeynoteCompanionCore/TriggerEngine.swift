import Foundation

public struct TriggerOptions: Equatable, Sendable {
    /// Fire a slide's labels when arriving on it by going back.
    public var fireOnBackward: Bool
    /// Fire labels when moving around the deck outside a slideshow.
    public var fireWhenNotPresenting: Bool

    public init(fireOnBackward: Bool = false, fireWhenNotPresenting: Bool = false) {
        self.fireOnBackward = fireOnBackward
        self.fireWhenNotPresenting = fireWhenNotPresenting
    }
}

/// Turns successive Keynote readings into `state` updates and `trigger` messages.
public struct TriggerEngine: Sendable {
    public var options: TriggerOptions
    public private(set) var state: SlideState?
    private var last: KeynoteSnapshot?

    public init(options: TriggerOptions = TriggerOptions()) {
        self.options = options
    }

    public struct Update: Equatable, Sendable {
        /// The new state, or nil if nothing a client sees has changed.
        public var state: SlideState?
        /// Triggers to send after the state, in order.
        public var triggers: [Trigger]
    }

    /// Feeds one reading. The first reading never fires, so launching the app mid-show
    /// does not repeat the current slide's cues.
    public mutating func ingest(_ snapshot: KeynoteSnapshot) -> Update {
        let newState = SlideState(snapshot: snapshot)
        let changed = newState != state
        let previous = last
        last = snapshot
        state = newState

        var triggers: [Trigger] = []
        if let previous, let direction = arrival(from: previous, to: snapshot) {
            let allowed =
                (snapshot.playing || options.fireWhenNotPresenting)
                && (direction == .forward || options.fireOnBackward)
            if allowed {
                let labels = newState.labels
                triggers = labels.enumerated().map { i, label in
                    Trigger(
                        label: label, slide: snapshot.slide, index: i, count: labels.count,
                        direction: direction)
                }
            }
        }
        return Update(state: changed ? newState : nil, triggers: triggers)
    }

    /// Forgets the previous reading, e.g. after Keynote quits, so the next one does not fire.
    public mutating func reset() {
        last = nil
        state = nil
    }

    /// Whether `next` counts as arriving on a slide, and from which direction.
    func arrival(from old: KeynoteSnapshot, to new: KeynoteSnapshot) -> Direction? {
        guard new.keynoteRunning, new.slide > 0 else { return nil }
        if !old.keynoteRunning || old.slide == 0 { return nil }
        if new.document != old.document { return .forward }
        if new.playing && !old.playing { return .forward }  // slideshow started
        if new.slide > old.slide { return .forward }
        if new.slide < old.slide { return .backward }
        return nil
    }
}
