# Keynote Companion wire protocol, version 1

The contract between the **Keynote Companion** Mac app and its Bitfocus Companion module.
Both repositories carry the same copy of this file.

- App: <https://github.com/horinezachary/horinetech-keynote-companion>
- Module: <https://github.com/horinezachary/companion-module-horinetech-keynote>

## Transport

- TCP. The Mac app **listens** (default port **7878**); the Companion module **connects**.
- UTF-8 text, **one JSON object per line**, each line ending in `\n`. A `\r\n` ending is tolerated.
- JSON escapes line breaks inside strings, so a message never contains a raw newline.
- A line longer than 1 MiB is discarded.
- Unknown message types and unknown commands are ignored, so either side can add to the
  protocol without breaking the other.

You can try it by hand:

```
$ nc 127.0.0.1 7878
{"app":"KeynoteCompanion","protocol":1,"type":"hello","version":"0.1.0"}
{"document":"My Deck","keynoteRunning":true,"labels":["CAM1"], ... "type":"state"}
{"type":"cmd","cmd":"next"}
```

## Handshake and authorisation

1. The client opens the socket and sends `hello`. The module always does this.
2. If the app has **no token** configured it greets every connection straight away, so a
   hand-typed `nc` session works without a `hello`.
3. If the app **has a token**, it waits for a client `hello` carrying the same token. A wrong or
   missing token gets an `error` with code `auth`, and the connection is closed. A client that
   sends no `hello` within 5 seconds is closed the same way.
4. Once authorised, the app sends its own `hello`, then a full `state`.
5. Commands from a client that is not authorised are ignored.

Client hello:

```json
{ "type": "hello", "protocol": 1, "token": "optional shared secret" }
```

## Keep-alive

The app sends `{"type":"hb"}` to every authorised client every **2 seconds**. The module treats
**8 seconds of silence** as a dead connection, closes it, and reconnects with backoff
(1 s, doubling up to 10 s). A client that connects but gets no `hello` within 3 seconds gives up
on that connection the same way.

## App to module

### `hello`

```json
{ "type": "hello", "protocol": 1, "app": "KeynoteCompanion", "version": "0.1.0" }
```

### `state`

Sent after `hello`, whenever any field changes, and in reply to a `refresh` command.

```json
{
	"type": "state",
	"keynoteRunning": true,
	"playing": true,
	"document": "Keynote Deck",
	"slide": 5,
	"slideCount": 40,
	"notes": "Welcome everyone [CAM1]",
	"notesPlain": "Welcome everyone",
	"labels": ["CAM1"]
}
```

| Field            | Meaning                                                                                        |
| ---------------- | ---------------------------------------------------------------------------------------------- |
| `keynoteRunning` | Keynote is open.                                                                               |
| `playing`        | A slideshow is playing.                                                                        |
| `document`       | Name of the front document, `""` if none.                                                      |
| `slide`          | Current slide number as Keynote numbers it (skipped slides are not counted). `0` when unknown. |
| `slideCount`     | Number of slides, skipped slides not counted.                                                  |
| `notes`          | Presenter notes of the current slide, newlines normalised to `\n`, tags included.              |
| `notesPlain`     | The same notes with every `[...]` tag removed and whitespace tidied.                           |
| `labels`         | Trigger labels found in the notes, in order, duplicates removed.                               |

### `trigger`

One message per label, in the order the labels appear in the notes. The app sends the new
`state` first, so the module already knows the slide's labels when the triggers arrive.

```json
{ "type": "trigger", "label": "CAM1", "slide": 5, "index": 0, "count": 2, "direction": "forward" }
```

`index` is the label's position (from 0) among the `count` labels fired for this slide change.
`direction` is `forward` or `backward`.

### `hb`

```json
{ "type": "hb" }
```

### `error`

```json
{ "type": "error", "code": "auth", "message": "Wrong or missing token" }
```

## Module to app

### `cmd`

```json
{ "type": "cmd", "cmd": "next" }
```

| `cmd`      | Extra fields                                                                        | Effect                                                                 |
| ---------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `next`     |                                                                                     | Advance (Keynote's `show next`).                                       |
| `previous` |                                                                                     | Go back (Keynote's `show previous`).                                   |
| `first`    |                                                                                     | Go to the first slide.                                                 |
| `last`     |                                                                                     | Go to the last slide.                                                  |
| `goto`     | `slide` (integer, 1 or more; a numeric string is accepted)                          | Go to that slide number. A number past the end goes to the last slide. |
| `start`    | `from`: `beginning` (default), `current` or `slide`; `slide` when `from` is `slide` | Start the slideshow.                                                   |
| `stop`     |                                                                                     | Stop the slideshow.                                                    |
| `refresh`  |                                                                                     | Reply with a fresh `state` to this client.                             |

`first`, `last` and `goto` jump within a playing slideshow, or move the editor's selection when
no slideshow is playing.

## Trigger labels

A label is any text between square brackets on a single line of the presenter notes:

```
Welcome everyone. [CAM1] [LIGHTS WARM]
```

- Labels are trimmed and runs of spaces inside them collapse to one. Empty `[]` is ignored.
- Matching is case-insensitive. A label repeated on one slide fires once, spelled as it first
  appears.
- Labels fire in order when you **arrive on a slide while presenting**, and also when the
  slideshow starts.
- Going **backwards** onto a slide does not fire its labels unless the app's
  _Fire labels when going back a slide_ option is on (`direction` is then `backward`).
- Moving around the deck **outside a slideshow** does not fire anything unless the app's
  _Fire labels when not presenting_ option is on.
- The first reading after the app starts, or after Keynote launches, never fires, so launching
  mid-show does not repeat the current slide's cues.
- Editing a slide's notes while on it sends a new `state` but does not fire.
- The app polls Keynote about 7 times a second. Slides that go by faster than that may not fire
  their labels.

## Not in version 1

Build counts ("builds left") are deliberately left out for now. Keynote's scripting interface
does not report them, and this is tabled until there is a reliable way to detect them.
