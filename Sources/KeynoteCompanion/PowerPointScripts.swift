import KeynoteCompanionCore

/// AppleScript for Microsoft PowerPoint for Mac.
///
/// PowerPoint numbers every slide, hidden ones included, so slide numbers and the count here do
/// too. The presenter notes are the text of the notes page's body placeholder (placeholder 2).
enum PowerPointScripts {
    private static let tell = "tell application id \"\(PresentationApp.powerpoint.bundleID)\""

    /// The slideshow's view, for the go-to commands.
    private static let showView = "(slide show view of slide show window 1)"
    /// The editor's view of the front presentation.
    private static let editView = "(view of document window 1)"

    static let read = """
        \(tell)
        	if (count of presentations) is 0 then return {false, "", 0, 0, ""}
        	set isPlaying to (count of slide show windows) > 0
        	set p to active presentation
        	set n to 0
        	if isPlaying then
        		try
        			set p to presentation of slide show window 1
        		end try
        		try
        			set n to slide index of (slide of \(showView))
        		on error
        			try
        				set n to current show position of \(showView)
        			end try
        		end try
        	else
        		try
        			set n to slide index of (slide of \(editView))
        		on error
        			try
        				set n to slide index of (slide range of selection of document window 1)
        			end try
        		end try
        	end if
        	set docName to name of p
        	set slideTotal to count of slides of p
        	set nt to ""
        	if n > 0 and n ≤ slideTotal then
        		try
        			set nt to content of text range of text frame of place holder 2 of notes page of slide n of p
        		end try
        	end if
        	return {isPlaying, docName, n, slideTotal, nt}
        end tell
        """

    /// Waits up to two seconds for a slideshow window to appear after `run slide show`.
    private static let waitForShow = """
        repeat 40 times
        		if (count of slide show windows) > 0 then exit repeat
        		delay 0.05
        	end repeat
        """

    /// Goes to slide `n` (clamped to the deck) in the playing slideshow, or in the editor when no
    /// slideshow is playing.
    private static func go(_ n: Int) -> String {
        """
        \(tell)
        	if (count of presentations) is 0 then return
        	set n to \(n)
        	set total to count of slides of active presentation
        	if n > total then set n to total
        	if n < 1 then return
        	if (count of slide show windows) > 0 then
        		go to slide \(showView) number n
        	else
        		go to slide \(editView) number n
        	end if
        end tell
        """
    }

    /// Moves one slide forward or back. In the editor this moves the selection.
    private static func step(_ delta: Int) -> String {
        let showCommand = delta > 0 ? "go to next slide" : "go to previous slide"
        return """
            \(tell)
            	if (count of presentations) is 0 then return
            	if (count of slide show windows) > 0 then
            		\(showCommand) \(showView)
            	else
            		set n to (slide index of (slide of \(editView))) + (\(delta))
            		if n ≥ 1 and n ≤ (count of slides of active presentation) then
            			go to slide \(editView) number n
            		end if
            	end if
            end tell
            """
    }

    /// Starts the slideshow, then jumps to the slide `target` evaluates to (an AppleScript
    /// expression evaluated before the show starts).
    private static func start(at target: String) -> String {
        """
        \(tell)
        	if (count of presentations) is 0 then return
        	set p to active presentation
        	set n to 1
        	try
        		set n to \(target)
        	end try
        	set total to count of slides of p
        	if n > total then set n to total
        	if n < 1 then set n to 1
        	if (count of slide show windows) is 0 then
        		run slide show (slide show settings of p)
        		\(waitForShow)
        	end if
        	if (count of slide show windows) > 0 then go to slide \(showView) number n
        end tell
        """
    }

    static func source(for command: Command) -> String? {
        switch command {
        case .next:
            return step(1)
        case .previous:
            return step(-1)
        case .first:
            return go(1)
        case .last:
            return go(Int(Int32.max))
        case .goto(let n):
            return go(n)
        case .start(.beginning):
            return start(at: "1")
        case .start(.slide(let n)):
            return start(at: String(n))
        case .start(.current):
            return start(at: "slide index of (slide of \(editView))")
        case .stop:
            return """
                \(tell)
                	if (count of slide show windows) > 0 then exit slide show \(showView)
                end tell
                """
        case .refresh:
            return nil
        }
    }
}
