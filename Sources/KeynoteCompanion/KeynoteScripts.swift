import KeynoteCompanionCore

/// AppleScript for Keynote. Slide numbers and the count leave out skipped slides, as Keynote does.
enum KeynoteScripts {
    private static let tell = "tell application id \"\(PresentationApp.keynote.bundleID)\""

    static let read = """
        \(tell)
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
    private static func go(_ n: Int, start: Bool) -> String {
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
            \(tell)
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
            return "\(tell) to show next"
        case .previous:
            return "\(tell) to show previous"
        case .first:
            return go(1, start: false)
        case .last:
            return go(Int(Int32.max), start: false)
        case .goto(let n):
            return go(n, start: false)
        case .start(.beginning):
            return go(1, start: true)
        case .start(.slide(let n)):
            return go(n, start: true)
        case .start(.current):
            return """
                \(tell)
                	if (count of documents) is 0 then return
                	set d to front document
                	start d from (current slide of d)
                end tell
                """
        case .stop:
            return """
                \(tell)
                	if playing and (count of documents) > 0 then stop front document
                end tell
                """
        case .refresh:
            return nil
        }
    }
}
