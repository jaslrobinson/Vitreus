# TV Remote: LG webOS TVs as well as Google TVs

2026-10-27 · status: design approved, not built · local doc (not part of the upstream pull request)

## Why

The TV Remote add-on (`addons/tvremote/`, helper `bin/vitreus-tvremote`, author natepayn3) speaks only the Google TV / Android TV remote
protocol. The user's living room has an LG OLED65CX (webOS) with an onn Google TV box on one of its HDMI inputs. The box already works
(after the discovery fix, issue #32, local fx 818ba1d). The LG itself can't be reached, so its inputs, its own apps, and power-on when
the box is off are out of reach. The LG answers on 3000 (ws) and 3001 (wss, TLS 1.2), and its mDNS record (`_display._tcp`,
"[LG] webOS TV OLED65CXPUA") carries its MAC.

## Decisions

- **Inside TV Remote**, not a separate add-on: one panel, one switcher listing both kinds. It changes the author's add-on, so it goes
  upstream as a **pull request** from the user's fork (jaslrobinson/Vitreus), referencing #32.
- First version: **basics** (power off, Wake-on-LAN power on, volume, mute, d-pad, OK, back, home, play/pause), **HDMI inputs**, **LG
  apps** and **typing**.
- **Each device stays separate**: whatever the switcher has picked gets every button. No linking of the box to the LG (CEC already
  passes power and volume through the box).
- Python standard library only, as the helper is now (plus openssl, already used). No `websockets` or `aiowebostv`.

## The helper: `bin/vitreus-tvremote`

### A second backend

`class WebOS` beside `Remote`, the same shape: `run()` (connects, then blocks reading until closed, raising `OSError` on loss), `close()`,
`alive`, `stale`, `state`, `host`. `start_remote(h, kind)` picks the class. The reconnect loop (backoff 2 to 20 s) stays shared.

**Connection.** `wss://host:3001/` (TLS, the TV's self-signed certificate is not verified, as with the Google TV), falling back to
`ws://host:3000/` if 3001 refuses. A minimal RFC 6455 client: the HTTP upgrade with a random `Sec-WebSocket-Key`, masked client
text frames, reading text and close frames, answering ping with pong, and frames up to 1 MiB (the app list can pass 16 KiB).

**Pairing (register).** Send `{"type":"register","id":"register_0","payload":{"forcePairing":false,"pairingType":"PROMPT","manifest":M,
"client-key":K?}}`, where M is the **LG-signed manifest every open-source client sends** (the `signed` block with its `signatures`; copied
verbatim from LGWebOSRemote / aiowebostv, with a source note). Its permissions cover:
- LAUNCH, CONTROL_AUDIO, CONTROL_POWER
- CONTROL_INPUT_TEXT, CONTROL_MOUSE_AND_KEYBOARD, CONTROL_INPUT_MEDIA_PLAYBACK
- READ_INSTALLED_APPS, READ_INPUT_DEVICE_LIST, READ_RUNNING_APPS, READ_CURRENT_CHANNEL, READ_POWER_STATE

The handshake runs like this:
- With no saved key, the TV shows "Allow this device?", answers `{"type":"response","payload":{"pairingType":"PROMPT"}}` and the helper
  emits `state stage=pair_wait_accept`.
- When it's accepted, `{"type":"registered","payload":{"client-key":"…"}}` arrives. The key is saved to `DATA/webos-<host>.key`
  (mode 600) and the helper emits `state stage=paired`, then connects.
- A refusal or a 60 s timeout emits `pairing_failed`.
- A saved key that the TV rejects (it was reset) makes the helper delete the key and emit `needs_pairing`.

**Requests** are `{"type":"request","id":"<n>","uri":"ssap://…","payload":{…}}`, and the answer carries the same id. A subscription is
`"type":"subscribe"`, and each change comes back under that id.

| Panel command | webOS |
|---|---|
| `key` UP/DOWN/LEFT/RIGHT/OK/BACK/HOME/SETTINGS | the **button socket**: `ssap://com.webos.service.networkinput/getPointerInputSocket` returns `socketPath`. A second WebSocket gets `type:button\nname:<NAME>\n\n` with UP DOWN LEFT RIGHT ENTER BACK HOME MENU |
| `key` VOL_UP / VOL_DOWN / MUTE | `ssap://audio/volumeUp`, `volumeDown`, `setMute {"mute": !muted}` |
| `key` PLAY_PAUSE | `ssap://media.controls/play` or `/pause`, alternating from the last one sent (webOS has no toggle) |
| `key` POWER | when on: `ssap://system/turnOff`. When unreachable: Wake-on-LAN (below) |
| `text` | `ssap://com.webos.service.ime/insertText {"text": t, "replace": 0}`, then `sendEnterKey` |
| `inputs` (new) | `ssap://tv/getExternalInputList` → `devices[{id, label}]` → `ev inputs` |
| `input {id}` (new) | `ssap://tv/switchInput {"inputId": id}` |
| `apps` (new) | `ssap://com.webos.applicationManager/listLaunchPoints` → `launchPoints[{id, title}]` → `ev apps` (sorted by title) |
| `launch {id}` (new) | `ssap://system.launcher/launch {"id": id}` |

**State** goes out as the existing `state stage=ready` event:
- `model` from `ssap://system/getSystemInfo` (`modelName`);
- `vol`, `max` (100) and `muted` from a subscription to `ssap://audio/getVolume` (both reply shapes: `volumeStatus{volume, muteStatus}` and the older `{volume, muted}`);
- `app` from a subscription to `ssap://com.webos.applicationManager/getForegroundAppInfo` (`appId`);
- `on = true` while connected.

**Wake-on-LAN.** A magic packet (6×FF + 16×MAC) to UDP 9 at the subnet broadcast and to 255.255.255.255. The MAC comes from the mDNS
record's `mac=` TXT entry at scan time and is saved with the TV, falling back to `ip neigh` for the host. It's sent on POWER while the
TV is unreachable, and the helper then retries the connection. It needs "Turn on via Wi-Fi" / "Mobile TV On" enabled on the TV.

### Discovery

`scan()` asks one query with two PTR questions: `_androidtvremote2._tcp.local` and `_display._tcp.local`. A `_display` instance whose name
starts with `[LG]` is kept as `kind: "webos"`, with its `mac` from TXT and a name from the rest of the instance name (e.g. "webOS TV
OLED65CXPUA"). Other `_display` devices are ignored. `found` entries gain `kind` (and `mac` for LG). It listens on 5353 as in the #32 fix.
SSDP isn't used: its unicast replies would be dropped by ufw the same way.

## The panel logic: `tvremote.luau`

- Saved TVs gain `kind` ("atv" default, so old configs keep working) and `mac` (LG). `connect`, `reconnect` and `pair` carry
  `kind`, and `unpair` deletes the right file (`paired-<host>` or `webos-<host>.key`).
- A typed address is first tried as "atv". The helper answers a refused 6466/6467 with an extra probe of 3001 and, if it answers,
  `ev kind {host, kind:"webos"}`, and the logic re-saves the TV as webOS. (This covers TVs not found by the scan.)
- New stage text for webOS pairing: "Accept on your TV" / "Use the TV's own remote to allow Vitreus." with no code field (stage 0 with
  the field off).
- `ev inputs` / `ev apps` fill a list for the sheet (below). `fact tv_kind` tells the scene which labels to draw.
- Actions: 17..20 stay YouTube, Netflix, Prime, Disney+ for atv. For webOS, 17 = Inputs (opens the sheet with the inputs), 18 = Apps
  (the sheet with the apps), 19 = YouTube (`youtube.leanback.v4`), 20 = Netflix (`netflix`). A sheet row press is `tv_sheet(k)`.

## The panel: `tvremote.plm`

- The app buttons' labels and accessible names follow `tv_kind`. For webOS they read "Inputs", "Apps", "YouTube", "Netflix".
- **A list sheet** in the switcher's style (same pencil rows, same position under the header), up to 24 rows, scrolling when longer
  than the panel. It's filled from `model sheet_rows max 24 { label: text; sub: text; on: bool }` (`on` marks the current input or
  app), shut by a press outside it or by picking a row. The style follows `addons/_template_drawer/STYLE.md`.
- The Google TV layout is otherwise unchanged.

## Failure behaviour

| Situation | Result |
|---|---|
| TV off, and Wake-on-LAN disabled on it | "Can't reach the TV" (existing screen). POWER sends the magic packet anyway and says "Sent a wake-up; turn on 'Turn on via Wi-Fi' on the TV if it stays off" |
| prompt refused or ignored | "Pairing did not work" with "Pair again" (existing screen) |
| saved key rejected (TV reset) | key deleted, back to "Pair with your TV" |
| 3001 refuses (old firmware) | falls back to 3000 |
| button socket fails | the d-pad shows nothing (a log line); volume, inputs, apps and power still work |
| a frame larger than 1 MiB | the connection is dropped and retried (logged) |

## Testing

- **Helper, offline:** `dev/tvremote-fakewebos.py` is a standard-library stand-in webOS TV on localhost (TLS with a throwaway cert, and
  plain). It checks:
  - registration with and without a key, the key saved at mode 600, and a rejected key going back to pairing;
  - each command's URI and payload;
  - the button socket's frames, and a subscription's state reaching the `ready` event;
  - the 3001 → 3000 fallback.
  Driven by `dev/tvremote-test-webos.sh`.
- **Discovery:** a recorded mDNS answer (the LG's real `_display._tcp` reply) fed to the parser gives `kind webos` with the right
  MAC and name. Running `scan` live on the user's network lists both the onn box and the LG.
- **Panel:** in `dev/rig` with the fake TV, check the LG labels, the Inputs and Apps sheets, and that the atv layout is unchanged.
- **Live, with the user:** pairing prompt accepted on the OLED; volume, inputs (switch to the onn's HDMI), Apps → Netflix, typing into
  YouTube search, power off, then power on by Wake-on-LAN.

## Delivery

Small commits on local `fx` (helper backend, discovery, logic, panel, tests), each passing `pleamar --check` and the offline test.
Then a branch on the fork from upstream main with just those commits (and #32's fix, if upstream hasn't taken it), and a pull request.
The PR text says an AI assistant helped (BUNDLING.md asks for that). This spec stays local.
