# Keynote Companion

A small macOS menu-bar app that watches **Keynote** or **Microsoft PowerPoint** and lets
**Bitfocus Companion** work with your slides.

- Reads the **slide number**, **slide count** and **presenter notes** for the slide on screen.
- Turns **`[LABEL]` tags in the presenter notes** into TCP messages that fire when you arrive on
  a slide, so a slide can cue cameras, lights, audio or anything else Companion drives.
- Lets Companion **control the slideshow**: next, previous, first, last, go to slide, start and stop.

The Companion side lives in
[companion-module-horinetech-keynote](https://github.com/horinezachary/companion-module-horinetech-keynote).
The two talk over a line-based JSON protocol described in [PROTOCOL.md](PROTOCOL.md).

## Status

Version 0.1. The notes parser, wire protocol and trigger rules are covered by unit tests, and
CI builds and tests the app on a macOS runner. The Keynote scripting and the menu-bar UI need a
first run on a real Mac; the things most worth checking are under [Known unknowns](#known-unknowns).

Build counts ("builds left") are tabled for now.

## Requirements

- macOS 13 (Ventura) or newer
- Keynote, or Microsoft PowerPoint for Mac
- Xcode or the Xcode command line tools (Swift 5.9 or newer)

## Build and run

```sh
swift test                    # unit tests
scripts/build-app.sh          # builds "build/Keynote Companion.app"
open "build/Keynote Companion.app"
```

An icon appears in the menu bar (no Dock icon). It shows the slide number while Keynote or
PowerPoint has a deck open.

The first time it talks to Keynote or PowerPoint, macOS asks whether *Keynote Companion* may
control that app. Allow it. If you said no, turn it on in
**System Settings > Privacy & Security > Automation**.

## Keynote or PowerPoint

**Settings > Follow** picks the app whose slides Companion sees and controls:

- **Automatic** (default): the app that is presenting. If both or neither are presenting, the
  one you used last. The menu shows which app it is following.
- **Keynote** or **PowerPoint**: always that app.

Everything else works the same for both: slide number and count, presenter notes, `[LABEL]`
triggers, and slide control. Switching from one app to the other never fires labels by itself.
In PowerPoint, hidden slides are counted and numbered, as PowerPoint numbers them; in Keynote,
skipped slides are left out.

macOS remembers that permission per code signature, and the default ad-hoc signature changes
with each build, so it may ask again after a rebuild. Signing with your own identity avoids that:

```sh
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh
```

`swift run KeynoteCompanion` also works for development, but without an app bundle the
permission prompt is attributed to your terminal and *Open at login* is unavailable.


## Releasing

Pushing a tag such as `v0.1.0` runs `.github/workflows/release.yml`. It tests the app, builds it
for Apple silicon and Intel, signs it with your Developer ID, notarizes and staples it, and
publishes a GitHub release with `Keynote-Companion-v0.1.0.zip` attached.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

It needs these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application certificate and key exported as .p12, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The .p12 export password |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_KEY_P8` | App Store Connect API key (.p8), base64-encoded |
| `NOTARY_KEY_ID` | That key's Key ID |
| `NOTARY_ISSUER_ID` | The App Store Connect Issuer ID |

## Connecting Companion

1. Open the menu-bar icon. Under **Companion** it lists this Mac's addresses and port, for example `192.168.1.20:7878`.
2. In Companion, add the **Keynote Companion** connection and enter that address and port. Use `127.0.0.1` if Companion runs on the same Mac.
3. The connection turns green and the menu shows `Connected: 1 client`.

Settings, under **Settings** in the menu:

| Setting | What it does |
| --- | --- |
| Follow | Automatic, Keynote or PowerPoint. See [Keynote or PowerPoint](#keynote-or-powerpoint). |
| Port | TCP port to listen on. Default 7878. Press Apply to restart the listener. |
| Allow other computers to connect | Off listens on this Mac only. On (default) lets Companion on another machine connect. |
| Shared token | If set, Companion must be configured with the same token. Slide control is otherwise open to anything that can reach the port, so set one on a shared network. |
| Fire labels when going back a slide | Off by default. |
| Fire labels when not presenting | Off by default, so clicking around the editor does not fire cues. |
| Open at login | Starts the app when you log in. |

## Labels in the presenter notes

Put tags in square brackets anywhere in a slide's presenter notes:

```
Welcome everyone and introduce the panel. [CAM1] [LIGHTS WARM]
```

When you arrive on that slide during a slideshow, the app sends one `trigger` message per label,
in order. The menu lists the most recent labels fired. The full rules are in
[PROTOCOL.md](PROTOCOL.md#trigger-labels).

## Known unknowns

These depend on how Keynote and PowerPoint behave and could not be checked while writing the app.

Keynote:

1. **Current slide while presenting.** The app reads `current slide` of the front document. If it does not follow the slideshow, slide numbers and labels will lag.
2. **Control without focus.** `show next` and `show previous` are sent without bringing Keynote to the front. If Keynote only responds when frontmost, the app needs an `activate` first.
3. **Jumping during a show.** `goto`, `first` and `last` use `start <document> from <slide>` while a slideshow is playing. Check that this jumps rather than restarting the show.
4. **Skipped slides.** Slide numbers and the count leave out skipped slides, and `goto` uses the same numbering.

PowerPoint (written against its AppleScript dictionary, not yet run on a real Mac):

5. **Current slide.** Read from `slide of slide show view of slide show window 1` while presenting, and from `slide of view of document window 1` in the editor. Check both follow along, including in Presenter View.
6. **Notes.** Read from placeholder 2 of the slide's notes page, the usual body placeholder. A custom notes master could put them elsewhere.
7. **Starting the show.** `start` runs the slideshow with the deck's own slide show settings, then jumps to the requested slide. If the deck is set to show only a range of slides, the jump may not land.
8. **Polling cost.** In Automatic mode the app reads both apps about 7 times a second. If PowerPoint's scripting is slow, slide changes may show up late; choosing PowerPoint explicitly reads only PowerPoint.

## Layout

```
Sources/KeynoteCompanionCore   notes parser, wire protocol, trigger rules, app picker (pure Foundation)
Sources/KeynoteCompanion       menu-bar app: AppleScript bridge (Keynote, PowerPoint), TCP server, SwiftUI
Tests/KeynoteCompanionCoreTests
Resources/                     Info.plist (incl. Automation usage text), entitlements
scripts/build-app.sh
```
