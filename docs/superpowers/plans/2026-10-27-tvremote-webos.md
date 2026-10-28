# TV Remote for LG webOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The TV Remote add-on also finds, pairs with and controls LG webOS TVs: basics, HDMI inputs, LG apps and typing.

**Architecture:** `bin/vitreus-tvremote` gets a `WebSocket` client, a `WebOS` backend beside `Remote`, `wake()` (Wake-on-LAN) and a
two-question mDNS scan. The panel logic keeps `kind`/`mac` per TV and routes commands. The panel relabels the app row for an LG and
gains a paged list sheet (Inputs, Apps). A stand-in LG (`dev/tvremote-webos-test.py`) tests the helper offline.

**Tech Stack:** Python 3 standard library (ssl, socket, json, threading), pleamar 0.4.31 scene + Luau logic.

**Spec:** `docs/superpowers/specs/2026-10-27-tvremote-webos-design.md`

## Global Constraints

- Python standard library only in the helper (plus openssl, already used). No pip packages.
- LG ports: wss 3001 first, then ws 3000. They can be overridden for tests with `VITREUS_TVREMOTE_WEBOS_PORTS="<wss>,<ws>"`.
- Key file `DATA/webos-<host>.key`, mode 600. Stages: `needs_pairing`, `pair_wait_accept` (new), `paired`, `ready`, `pairing_failed`, `error`.
- New helper commands: `inputs`, `input {id}`, `apps`, `launch {id}`, `wake`. New events: `inputs {list}`, `apps {list}`, `kind {host, kind}`.
  `connect`, `reconnect`, `pair` and `unpair` take `kind` ("atv" default) and `mac`.
- Registration uses the UNSIGNED manifest aiowebostv sends (its `handshake.py`, permissions list verbatim). The spec's "LG-signed
  manifest" is not needed.
- **Deviation from the spec:** the list sheet PAGES (8 rows plus "More…") instead of scrolling. That's how the panel's other lists work (fixed rows).
- Run `pleamar --check addons/tvremote/tvremote.plm` after every scene edit. The logic is only tested by running it (`pleamar --say tvremote …`).
- The Google TV path must keep working: run the live `scan` and a connect to the onn box after each helper task.
- Commit on `fx`. Never stage `vitreus.plm` (its runtime `screens:` edit is uncommitted on purpose).
- Restart the add-on after editing: `pleamar --say tvremote quit` (its keeper relaunches it).

---

### Task 1: WebSocket client, WebOS backend and stand-in LG

**Files:**
- Modify: `bin/vitreus-tvremote` (imports, a new section before `# ── finding TVs`, `main()`)
- Create: `dev/tvremote-webos-test.py`

**Interfaces:**
- Produces:
  - `class WebSocket(url, timeout=8)` with `.send(text|bytes, opcode=1)`, `.recv() -> str`, `.close()`, `.sock`;
  - `class WebOS(host, mac="")` with `.run()`, `.close()`, `.key(name)`, `.text(t)`, `.inputs()`, `.input(id)`, `.apps()`, `.launch(id)`, `.alive`, `.stale`, `.state`, `.host`;
  - `wake(host, mac) -> bool`, `webos_key_file(host)`.

- [ ] **Step 1: Write the stand-in LG and the test** (`dev/tvremote-webos-test.py`). A threaded WebSocket server answers like an LG
  (TLS on one port with a throwaway openssl certificate, plain on the other) and logs every message. The test drives the helper over
  its stdin/stdout:

```python
#!/usr/bin/env python3
"""Offline test of the TV Remote helper's LG webOS backend, against a stand-in LG on 127.0.0.1 (no TV needed).

    python3 dev/tvremote-webos-test.py          prints PASS, or FAIL and what went wrong

The stand-in answers on WSS and WS ports like an LG: registration (a prompt first, then a key), requests and subscriptions, and the
pointer-input socket for buttons. Everything the helper sends is kept in LOG for the checks."""
import base64, hashlib, json, os, queue, socket, ssl, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "..", "bin", "vitreus-tvremote")
WSS, WS = 13001, 13000
KEY = "k-123"
LOG = []
GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def ws_read(conn):
    """One text message from a client (masked frames)."""
    def exact(n):
        b = b""
        while len(b) < n:
            c = conn.recv(n - len(b))
            if not c:
                raise ConnectionError
            b += c
        return b
    b0, b1 = exact(2)
    n = b1 & 0x7F
    if n == 126:
        n = int.from_bytes(exact(2), "big")
    elif n == 127:
        n = int.from_bytes(exact(8), "big")
    mask = exact(4) if b1 & 0x80 else b"\0\0\0\0"
    data = bytes(x ^ mask[i % 4] for i, x in enumerate(exact(n)))
    if b0 & 0x0F == 8:
        raise ConnectionError
    return b0 & 0x0F, data


def ws_send(conn, text):
    data = text.encode()
    n = len(data)
    head = bytes([0x81]) + (bytes([n]) if n < 126 else bytes([126]) + n.to_bytes(2, "big"))
    conn.sendall(head + data)


REPLIES = {
    "ssap://system/getSystemInfo": {"modelName": "FAKE65CX"},
    "ssap://audio/getVolume": {"volumeStatus": {"volume": 12, "muteStatus": False, "maxVolume": 100}},
    "ssap://com.webos.applicationManager/getForegroundAppInfo": {"appId": "com.webos.app.hdmi2"},
    "ssap://com.webos.service.networkinput/getPointerInputSocket": {"socketPath": "ws://127.0.0.1:%d/resources/fake/netinput.pointer.sock" % WS},
    "ssap://tv/getExternalInputList": {"devices": [{"id": "HDMI_1", "label": "HDMI 1", "appId": "com.webos.app.hdmi1"},
                                                   {"id": "HDMI_2", "label": "onn", "appId": "com.webos.app.hdmi2"}]},
    "ssap://com.webos.applicationManager/listLaunchPoints": {"launchPoints": [{"id": "youtube.leanback.v4", "title": "YouTube"},
                                                                               {"id": "netflix", "title": "Netflix"}]},
}


def serve_client(conn):
    try:
        req = b""
        while b"\r\n\r\n" not in req:
            c = conn.recv(1024)
            if not c:
                return
            req += c
        lines = req.decode().split("\r\n")
        path = lines[0].split(" ")[1]
        key = [l.split(":", 1)[1].strip() for l in lines if l.lower().startswith("sec-websocket-key:")][0]
        acc = base64.b64encode(hashlib.sha1(key.encode() + GUID).digest()).decode()
        conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % acc).encode())
        while True:
            op, data = ws_read(conn)
            if op == 9:
                continue
            if path.startswith("/resources/"):
                LOG.append({"button": data.decode()})
                continue
            m = json.loads(data)
            LOG.append(m)
            if m.get("type") == "register":
                if m["payload"].get("client-key") != KEY:
                    ws_send(conn, json.dumps({"type": "response", "id": m["id"], "payload": {"pairingType": "PROMPT"}}))
                    time.sleep(0.3)
                ws_send(conn, json.dumps({"type": "registered", "id": m["id"], "payload": {"client-key": KEY}}))
            else:
                ws_send(conn, json.dumps({"type": "response", "id": m["id"], "payload": REPLIES.get(m.get("uri"), {"returnValue": True})}))
    except (ConnectionError, OSError, ValueError, IndexError):
        pass
    finally:
        conn.close()


def listen(port, tls_ctx=None):
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(8)

    def loop():
        while True:
            c, _ = srv.accept()
            if tls_ctx:
                try:
                    c = tls_ctx.wrap_socket(c, server_side=True)
                except ssl.SSLError:
                    c.close()
                    continue
            threading.Thread(target=serve_client, args=(c,), daemon=True).start()
    threading.Thread(target=loop, daemon=True).start()
    return srv


class Helper:
    def __init__(self, data, ports):
        env = dict(os.environ, VITREUS_TVREMOTE_WEBOS_PORTS=ports)
        self.p = subprocess.Popen([sys.executable, HELPER, data], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
        self.q = queue.Queue()
        threading.Thread(target=lambda: [self.q.put(json.loads(l)) for l in self.p.stdout], daemon=True).start()

    def send(self, **c):
        self.p.stdin.write(json.dumps(c) + "\n")
        self.p.stdin.flush()

    def wait(self, pred, what, t=6):
        end = time.time() + t
        seen = []
        while time.time() < end:
            try:
                ev = self.q.get(timeout=0.2)
            except queue.Empty:
                continue
            seen.append(ev)
            if pred(ev):
                return ev
        fail("no %s; saw %s" % (what, seen[-6:]))

    def stop(self):
        self.send(cmd="stop")
        self.p.wait(timeout=5)


def fail(msg):
    print("FAIL:", msg)
    sys.exit(1)


def sent(pred, what, t=3):
    end = time.time() + t
    while time.time() < end:
        if any(pred(m) for m in list(LOG)):
            return
        time.sleep(0.05)
    fail("the TV never got %s; it got %s" % (what, [m.get("uri", m) for m in LOG[-8:]]))


def stage(s):
    return lambda e: e.get("ev") == "state" and e.get("stage") == s


def main():
    tmp = tempfile.mkdtemp()
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=fake",
                    "-keyout", tmp + "/k.pem", "-out", tmp + "/c.pem"], check=True, capture_output=True)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(tmp + "/c.pem", tmp + "/k.pem")
    listen(WSS, ctx)
    listen(WS)
    data = tmp + "/data"
    os.makedirs(data)
    h = Helper(data, "%d,%d" % (WSS, WS))
    h.wait(lambda e: e.get("ev") == "hello", "hello")
    # 1. no key yet: asks to pair, connects nowhere
    h.send(cmd="connect", host="127.0.0.1", kind="webos")
    h.wait(stage("needs_pairing"), "needs_pairing")
    # 2. pairing: the prompt, the key saved (600), then ready with what the TV said
    h.send(cmd="pair", host="127.0.0.1", kind="webos")
    h.wait(stage("pair_wait_accept"), "pair_wait_accept")
    h.wait(stage("paired"), "paired")
    ev = h.wait(lambda e: stage("ready")(e) and e.get("model") == "FAKE65CX" and e.get("vol") == 12, "ready with model and volume")
    kf = os.path.join(data, "webos-127.0.0.1.key")
    if open(kf).read().strip() != KEY or os.stat(kf).st_mode & 0o077:
        fail("key file wrong or readable by others")
    # 3. keys: buttons through the pointer socket, volume / mute / play through requests
    h.send(cmd="key", key="UP")
    sent(lambda m: m.get("button") == "type:button\nname:UP\n\n", "button UP")
    h.send(cmd="key", key="OK")
    sent(lambda m: m.get("button") == "type:button\nname:ENTER\n\n", "button ENTER for OK")
    h.send(cmd="key", key="VOL_UP")
    sent(lambda m: m.get("uri") == "ssap://audio/volumeUp", "volumeUp")
    h.send(cmd="key", key="MUTE")
    sent(lambda m: m.get("uri") == "ssap://audio/setMute" and m.get("payload") == {"mute": True}, "setMute true")
    h.send(cmd="key", key="PLAY_PAUSE")
    sent(lambda m: m.get("uri") == "ssap://media.controls/play", "play")
    h.send(cmd="key", key="PLAY_PAUSE")
    sent(lambda m: m.get("uri") == "ssap://media.controls/pause", "pause")
    # 4. inputs and apps
    h.send(cmd="inputs")
    ev = h.wait(lambda e: e.get("ev") == "inputs", "inputs")
    if [(i["id"], i["label"], i["on"]) for i in ev["list"]] != [("HDMI_1", "HDMI 1", False), ("HDMI_2", "onn", True)]:
        fail("inputs: %s" % ev["list"])
    h.send(cmd="input", id="HDMI_1")
    sent(lambda m: m.get("uri") == "ssap://tv/switchInput" and m.get("payload") == {"inputId": "HDMI_1"}, "switchInput HDMI_1")
    h.send(cmd="apps")
    ev = h.wait(lambda e: e.get("ev") == "apps", "apps")
    if [a["label"] for a in ev["list"]] != ["Netflix", "YouTube"]:
        fail("apps not sorted by title: %s" % ev["list"])
    h.send(cmd="launch", id="netflix")
    sent(lambda m: m.get("uri") == "ssap://system.launcher/launch" and m.get("payload") == {"id": "netflix"}, "launch netflix")
    # 5. typing, power
    h.send(cmd="text", text="hi")
    sent(lambda m: m.get("uri") == "ssap://com.webos.service.ime/insertText" and m.get("payload") == {"text": "hi", "replace": 0}, "insertText")
    sent(lambda m: m.get("uri") == "ssap://com.webos.service.ime/sendEnterKey", "sendEnterKey")
    h.send(cmd="key", key="POWER")
    sent(lambda m: m.get("uri") == "ssap://system/turnOff", "turnOff")
    # 6. a reconnect with the saved key: no prompt this time
    n = len(LOG)
    h.send(cmd="reconnect", host="127.0.0.1", kind="webos")
    h.wait(stage("ready"), "ready after reconnect")
    regs = [m for m in LOG[n:] if m.get("type") == "register"]
    if not regs or regs[-1]["payload"].get("client-key") != KEY:
        fail("reconnect did not register with the saved key")
    h.stop()
    # 7. a TV with only the plain port (old firmware): falls back to it
    h = Helper(data, "%d,%d" % (WSS + 10, WS))
    h.wait(lambda e: e.get("ev") == "hello", "hello")
    h.send(cmd="connect", host="127.0.0.1", kind="webos")
    h.wait(stage("ready"), "ready over the plain port")
    h.stop()
    print("PASS")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it and check it fails**

Run: `python3 dev/tvremote-webos-test.py`. Expected: `FAIL: no needs_pairing; …` (the helper doesn't know `kind`).

- [ ] **Step 3: Add the backend.** In the imports add `import base64` and `import re`, in alphabetical order. Before
  `# ── finding TVs`, add:

```python
# ── LG webOS TVs: the second-screen API (requests as JSON over a WebSocket, 3001 with TLS or 3000) ───────────────────────────
WEBOS_PORTS = tuple(int(p) for p in os.environ.get("VITREUS_TVREMOTE_WEBOS_PORTS", "3001,3000").split(","))     # wss, ws
WEBOS_PERMS = [                                     # aiowebostv's (handshake.py): the TV asks once, on its screen, for all of them
    "APP_TO_APP", "CLOSE", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_PLAYBACK",
    "CONTROL_INPUT_MEDIA_RECORDING", "CONTROL_INPUT_TEXT", "CONTROL_INPUT_TV", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_POWER",
    "CONTROL_TV_SCREEN", "LAUNCH", "LAUNCH_WEBAPP", "READ_APP_STATUS", "READ_COUNTRY_INFO", "READ_CURRENT_CHANNEL",
    "READ_INPUT_DEVICE_LIST", "READ_INSTALLED_APPS", "READ_LGE_SDX", "READ_LGE_TV_INPUT_EVENTS", "READ_NETWORK_STATE",
    "READ_NOTIFICATIONS", "READ_POWER_STATE", "READ_RUNNING_APPS", "READ_SETTINGS", "READ_TV_CHANNEL_LIST", "READ_TV_CURRENT_TIME",
    "READ_UPDATE_INFO", "SEARCH", "TEST_OPEN", "TEST_PROTECTED", "TEST_SECURE", "UPDATE_FROM_REMOTE_APP", "WRITE_NOTIFICATION_ALERT",
    "WRITE_NOTIFICATION_TOAST", "WRITE_SETTINGS",
]
WEBOS_BUTTONS = {"UP": "UP", "DOWN": "DOWN", "LEFT": "LEFT", "RIGHT": "RIGHT", "OK": "ENTER", "BACK": "BACK", "HOME": "HOME", "SETTINGS": "MENU"}
WS_MAX = 1 << 20                                    # a message larger than this ends the connection (the app list is ~16 KiB)


def webos_key_file(host):
    """The key the TV gave when its prompt was accepted: with it, it lets us in without asking again."""
    return os.path.join(DATA, "webos-" + host + ".key")


class PairRefused(Exception):
    pass


class WebSocket:
    """A small RFC 6455 client: masked frames out, text / ping / close in."""

    def __init__(self, url, timeout=8):
        scheme, rest = url.split("://", 1)
        hostport, _, path = rest.partition("/")
        host, _, port = hostport.partition(":")
        port = int(port or (443 if scheme == "wss" else 80))
        sock = socket.create_connection((host, port), timeout=timeout)
        if scheme == "wss":
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE                     # the TV's certificate is its own, signed by nobody
            sock = ctx.wrap_socket(sock, server_hostname=host)
        key = base64.b64encode(os.urandom(16)).decode()
        sock.sendall(("GET /%s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, host, port, key)).encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = sock.recv(4096)
            if not chunk or len(head) > 16384:
                raise ConnectionError("the handshake ended early")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise ConnectionError("refused: " + head.split(b"\r\n", 1)[0].decode(errors="replace"))
        self.buf = head.split(b"\r\n\r\n", 1)[1]
        self.sock = sock
        self.lock = threading.Lock()

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, data, opcode=1):
        data = data.encode() if isinstance(data, str) else data
        n = len(data)
        head = bytes([0x80 | opcode]) + (bytes([0x80 | n]) if n < 126 else bytes([0xFE]) + n.to_bytes(2, "big") if n < 65536
                                         else bytes([0xFF]) + n.to_bytes(8, "big"))
        mask = os.urandom(4)
        with self.lock:
            self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def recv(self):
        """The next text message; answers pings; ConnectionError when the TV closes."""
        parts = b""
        while True:
            b0, b1 = self._read(2)
            op, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = int.from_bytes(self._read(2), "big")
            elif n == 127:
                n = int.from_bytes(self._read(8), "big")
            if n + len(parts) > WS_MAX:
                raise ConnectionError("a message too large")
            mask = self._read(4) if b1 & 0x80 else None
            data = self._read(n)
            if mask:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if op == 8:
                raise ConnectionError("closed by the TV")
            if op == 9:
                self.send(data, 10)
                continue
            if op == 10:
                continue
            parts += data
            if b0 & 0x80:
                return parts.decode(errors="replace")

    def close(self):
        for f in (lambda: self.sock.shutdown(socket.SHUT_RDWR), self.sock.close):
            try:
                f()
            except OSError:
                pass


def wake(host, mac):
    """Wake-on-LAN: the TV must allow it ("Turn on via Wi-Fi" / "Mobile TV On"). The MAC comes from the scan, else the ARP cache."""
    if not mac:
        try:
            out = subprocess.run(["ip", "neigh", "show", host], capture_output=True, text=True, timeout=3).stdout
        except (OSError, subprocess.SubprocessError):
            out = ""
        m = re.search(r"lladdr ([0-9a-fA-F:]{17})", out)
        mac = m.group(1) if m else ""
    if not mac:
        return False
    packet = b"\xff" * 6 + bytes.fromhex(mac.replace(":", "")) * 16
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    for dst in ("255.255.255.255", host.rsplit(".", 1)[0] + ".255"):
        try:
            s.sendto(packet, (dst, 9))
        except OSError:
            pass
    s.close()
    return True


class WebOS:
    """An LG webOS TV: requests and subscriptions on one WebSocket, the d-pad's buttons on a second one the TV hands out."""

    def __init__(self, host, mac=""):
        self.host, self.mac = host, mac
        self.ws = None
        self.buttons = None
        self.pending = None                         # a button pressed while the button socket was (re)opening
        self.alive = False
        self.stale = False
        self.state = None
        self.n = 0
        self.waiting = {}                           # request id -> (callback, kept for a subscription)
        self.lock = threading.Lock()
        self.playing = False                        # webOS has no play/pause toggle: alternate

    def close(self):
        self.stale = True
        for w in (self.ws, self.buttons):
            if w is not None:
                w.close()

    def request(self, uri, payload=None, kind="request", on_reply=None):
        if self.ws is None:
            raise ConnectionError("not connected")
        with self.lock:
            self.n += 1
            rid = "r%d" % self.n
            if on_reply:
                self.waiting[rid] = (on_reply, kind == "subscribe")
        msg = {"type": kind, "id": rid, "uri": "ssap://" + uri}
        if payload is not None:
            msg["payload"] = payload
        self.ws.send(json.dumps(msg))

    def open(self):
        last = None
        for scheme, port in (("wss", WEBOS_PORTS[0]), ("ws", WEBOS_PORTS[1])):
            try:
                return WebSocket("%s://%s:%d/" % (scheme, self.host, port))
            except (OSError, ConnectionError) as e:
                last = e
        raise ConnectionError("no answer on %d or %d: %s" % (WEBOS_PORTS[0], WEBOS_PORTS[1], last))

    def register(self, ws, key):
        """Register with the saved key, or by the prompt on the TV (60 s to accept); returns the key the TV gave."""
        payload = {"forcePairing": False, "pairingType": "PROMPT",
                   "manifest": {"manifestVersion": 1, "appVersion": "1.1", "permissions": WEBOS_PERMS}}
        if key:
            payload["client-key"] = key
        ws.send(json.dumps({"type": "register", "id": "register_0", "payload": payload}))
        ws.sock.settimeout(60)
        while True:
            m = json.loads(ws.recv())
            if m.get("id") != "register_0":
                continue
            if m.get("type") == "registered":
                return (m.get("payload") or {}).get("client-key") or key
            if m.get("type") == "response" and (m.get("payload") or {}).get("pairingType") == "PROMPT":
                emit(ev="state", stage="pair_wait_accept")
                continue
            if m.get("type") == "error":
                raise PairRefused(m.get("error") or "refused")

    def run(self):
        ws = self.open()
        self.ws = ws
        st = {"model": "", "vendor": "LG", "on": True, "app": "", "vol": -1, "max": 100, "muted": False}
        try:
            key = None
            try:
                with open(webos_key_file(self.host)) as f:
                    key = f.read().strip() or None
            except OSError:
                pass
            got = self.register(ws, key)
            if got and got != key:
                fd = os.open(webos_key_file(self.host), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w") as f:
                    f.write(got)
                emit(ev="state", stage="paired")
            ws.sock.settimeout(20)
            self.alive = True
            self.state = st

            def info(p):
                st["model"] = p.get("modelName") or st["model"]
                emit(ev="state", stage="ready", **st)

            def vol(p):
                v = p.get("volumeStatus", p)
                if isinstance(v.get("volume"), int):
                    st["vol"] = v["volume"]
                if v.get("maxVolume"):
                    st["max"] = v["maxVolume"]
                m = v.get("muteStatus", v.get("muted", p.get("mute")))
                if m is not None:
                    st["muted"] = bool(m)
                emit(ev="state", stage="ready", **st)

            def app(p):
                if p.get("appId"):
                    st["app"] = p["appId"]
                    emit(ev="state", stage="ready", **st)
            self.request("system/getSystemInfo", on_reply=info)
            self.request("audio/getVolume", kind="subscribe", on_reply=vol)
            self.request("com.webos.applicationManager/getForegroundAppInfo", kind="subscribe", on_reply=app)
            self.request("com.webos.service.networkinput/getPointerInputSocket", on_reply=self.open_buttons)
            emit(ev="state", stage="ready", **st)
            missed = False
            while True:
                try:
                    text = ws.recv()
                    missed = False
                except socket.timeout:
                    if missed:
                        raise ConnectionError("the TV stopped answering")
                    missed = True
                    ws.send(b"", 9)
                    continue
                if self.stale:
                    return
                try:
                    m = json.loads(text)
                except ValueError:
                    continue
                if m.get("type") == "error":
                    emit(ev="log", msg="webOS %s: %s" % (m.get("id"), m.get("error")))
                    with self.lock:
                        self.waiting.pop(m.get("id"), None)
                    continue
                with self.lock:
                    cb = self.waiting.get(m.get("id"))
                    if cb and not cb[1]:
                        self.waiting.pop(m.get("id"), None)
                if cb:
                    cb[0](m.get("payload") or {})
        finally:
            self.alive = False
            self.close_quietly()

    def close_quietly(self):
        for w in (self.ws, self.buttons):
            if w is not None:
                w.close()
        self.ws = self.buttons = None

    def open_buttons(self, p):
        path = p.get("socketPath", "")

        def go():
            try:
                w = WebSocket(path)
            except (OSError, ConnectionError, ValueError) as e:
                emit(ev="log", msg="webOS button socket: %s" % e)
                return
            w.sock.settimeout(None)
            self.buttons = w
            if self.pending:
                name, self.pending = self.pending, None
                self.button(name)
            try:
                while not self.stale:
                    w.recv()                        # (answers the TV's pings)
            except (OSError, ConnectionError):
                pass
            if self.buttons is w:
                self.buttons = None
        threading.Thread(target=go, daemon=True).start()

    def button(self, name):
        w = self.buttons
        if w is not None:
            try:
                w.send("type:button\nname:%s\n\n" % name)
                return
            except (OSError, ConnectionError):
                self.buttons = None
        self.pending = name
        self.request("com.webos.service.networkinput/getPointerInputSocket", on_reply=self.open_buttons)

    def key(self, k):
        if k == "VOL_UP" or k == "VOL_DOWN":
            self.request("audio/volumeUp" if k == "VOL_UP" else "audio/volumeDown")
        elif k == "MUTE":
            self.request("audio/setMute", {"mute": not (self.state or {}).get("muted", False)})
        elif k == "PLAY_PAUSE":
            self.playing = not self.playing
            self.request("media.controls/play" if self.playing else "media.controls/pause")
        elif k == "POWER":
            self.request("system/turnOff")
        elif k in WEBOS_BUTTONS:
            self.button(WEBOS_BUTTONS[k])

    def text(self, t):
        self.request("com.webos.service.ime/insertText", {"text": t, "replace": 0})
        self.request("com.webos.service.ime/sendEnterKey")

    def inputs(self):
        def got(p):
            cur = (self.state or {}).get("app", "")
            emit(ev="inputs", list=[{"id": d.get("id", ""), "label": d.get("label") or d.get("id", ""), "on": d.get("appId") == cur}
                                    for d in p.get("devices", [])])
        self.request("tv/getExternalInputList", on_reply=got)

    def input(self, iid):
        self.request("tv/switchInput", {"inputId": iid})

    def apps(self):
        def got(p):
            cur = (self.state or {}).get("app", "")
            pts = sorted(p.get("launchPoints", []), key=lambda a: (a.get("title") or "").lower())
            emit(ev="apps", list=[{"id": a.get("id", ""), "label": a.get("title") or a.get("id", ""), "on": a.get("id") == cur} for a in pts])
        self.request("com.webos.applicationManager/listLaunchPoints", on_reply=got)

    def launch(self, aid):
        self.request("system.launcher/launch", {"id": aid})
```

- [ ] **Step 4: Route `main()` by kind.** Replace `start_remote(h)` and the command handlers so the backend follows `kind`:

  - `def start_remote(h, kind="atv", mac="")`. The "already connected" check also needs `isinstance(remote, WebOS) == (kind == "webos")`.
    Build `WebOS(h, mac)` or `Remote(h)`. In `loop(r)`, add `except PairRefused as e: emit(ev="state", stage="pairing_failed", msg=str(e)); return`
    before the generic `except`. (`ssl.SSLError` → `needs_pairing` stays for the Google TV.)
  - `connect` / `reconnect`: read `kind = c.get("kind", "atv")` and `mac = c.get("mac", "")`. For webos, "paired" means
    `os.path.exists(webos_key_file(host))`. Call `start_remote(host, kind, mac)`.
  - `pair` with kind webos: remove any key file (ignore errors), `want["on"] = True`, `start_remote(host, "webos", mac)`, and `continue`
    (the prompt comes from `register`).
  - `unpair` with kind webos: remove `webos_key_file(host)`.
  - `key`: `if isinstance(remote, WebOS): remote.key(k)`, else the existing code.
  - `text`: `remote.text(...)` for WebOS, else the existing per-character code.
  - New: `inputs`, `input` (`c.get("id","")`), `apps`, `launch` (`c.get("id","")`), each only `if isinstance(remote, WebOS) and remote.alive`.
  - New `wake`: `ok = wake(c.get("host", host), c.get("mac", ""))`, then `emit(ev="log", msg="wake-on-lan sent" if ok else "no MAC address for wake-on-lan")`.
  - The `except` around commands also catches `PairRefused`.

- [ ] **Step 5: Run the test.** Run: `python3 dev/tvremote-webos-test.py`. Expected: `PASS`.
- [ ] **Step 6: The Google TV still works.** Run `echo '{"cmd":"scan"}' | timeout 8 python3 bin/vitreus-tvremote /tmp/x | tail -1`; it must list
  Living Room TV. Restart the add-on and check its panel still controls the box (ask the user).
- [ ] **Step 7: Commit.** `git add bin/vitreus-tvremote dev/tvremote-webos-test.py && git commit -m "TV Remote: an LG webOS backend in the helper (WebSocket, pairing by the TV's prompt, keys, volume, inputs, apps, typing, Wake-on-LAN), tested against a stand-in LG"`

---

### Task 2: Finding LG TVs

**Files:**
- Modify: `bin/vitreus-tvremote` (`scan()` and a new `parse_mdns()`)
- Create: `dev/fixtures/lg-display-mdns.bin` (the LG's real answer, captured once)
- Modify: `dev/tvremote-webos-test.py` (a parse check)

**Interfaces:** Produces `parse_mdns(data, ip, found)`. `found` maps `(ip, kind)` to `{"host","name","kind","mac"?}`. `scan()` returns that list sorted by host.

- [ ] **Step 1: Capture the LG's answer.** Send the two-question query below from a socket bound to 5353 (as in the probe from #32),
  and save the first response from 10.0.0.4 that contains `_display` to `dev/fixtures/lg-display-mdns.bin`. If the LG doesn't answer
  a `_display` question, record that and keep only the typed-address path (Task 3's `kind` probe).
- [ ] **Step 2: Add the failing check** to `main()` in the test, before the helper part:

```python
    import importlib.machinery, importlib.util
    ld = importlib.machinery.SourceFileLoader("tvr", HELPER)
    tvr = importlib.util.module_from_spec(importlib.util.spec_from_loader("tvr", ld))
    ld.exec_module(tvr)
    found = {}
    tvr.parse_mdns(open(os.path.join(HERE, "fixtures", "lg-display-mdns.bin"), "rb").read(), "10.0.0.4", found)
    got = list(found.values())
    if not got or got[0]["kind"] != "webos" or not got[0].get("mac") or "OLED" not in got[0]["name"]:
        fail("the LG's mDNS answer parsed as %s" % got)
```

(The helper's `main()` only runs under `if __name__ == "__main__"`, so loading it as a module is safe. `DATA` is read from argv,
which falls back to the default.)

- [ ] **Step 3: Implement.** Split `scan()`'s record loop into `parse_mdns(data, ip, found)`:
  - PTR records: instances under `_androidtvremote2` become `kind atv`. Instances under `_display._tcp` whose name starts with `[LG]` become
    `kind webos`, named by the instance name minus the `[LG] ` prefix.
  - TXT records (type 16) on an `[LG]` owner: read the length-prefixed strings and keep `mac=` on that ip's webos entry.
  - Ask both questions in one packet: qdcount 2, each `PTR` with the unicast-reply bit.
  - `scan()` returns `[v for _, v in sorted(found.items())]`.
- [ ] **Step 4: Test offline and live.** `python3 dev/tvremote-webos-test.py` must PASS. The live scan must list both: Living Room TV (atv,
  10.0.0.3) and the OLED (webos, 10.0.0.4, with a mac).
- [ ] **Step 5: Commit.** `git add bin/vitreus-tvremote dev/tvremote-webos-test.py dev/fixtures/lg-display-mdns.bin && git commit -m "TV Remote: the scan also finds LG webOS TVs (_display._tcp, [LG] names) with their MAC for Wake-on-LAN"`

---

### Task 3: The panel logic knows two kinds

**Files:** Modify `addons/tvremote/tvremote.luau`, and add an `inputs`/`apps` page model (Task 4 draws it).

**Interfaces:**
- Consumes the helper events `inputs`, `apps`, `kind` and `state stage=pair_wait_accept`.
- Produces the facts `tv_kind` (0 atv, 1 webos), `sheet_open`, `sheet_cnt`, `sheet_cur`, the texts `sheet_t`, `sheet_0..sheet_8`, and the event `tv_sheet(k)`.

- [ ] **Step 1: Kind and MAC in the saved TVs.**
  - Loading: `{ host, name, kind = (tv.kind == "webos") and "webos" or "atv", mac = type(tv.mac) == "string" and tv.mac or "" }`.
  - `cur_kind()` / `cur_mac()`, the same as `cur_host()`.
  - `add_tv(host, name, kind, mac)` stores them. `tv_pick` passes `tv.kind, tv.mac`, and a typed address passes `"atv", ""`.
  - Every `send({cmd="connect"|"reconnect"|"pair"|"unpair", …})` adds `kind = …, mac = …` for that TV.
  - `refresh_menu()` sets `fact.tv_kind = cur_kind() == "webos" and 1 or 0`.
- [ ] **Step 2: Stages.**
  - `needs_pairing` for webos: `set_stage(3, "Pair with your TV", "Your TV will ask whether to allow Vitreus: answer with its own remote.", "Pair with TV")`.
  - New `pair_wait_accept`: `set_stage(0, "Accept on your TV", "Use the TV's own remote to allow Vitreus. The question is on its screen now.")`.
  - `error` for webos: the button reads `"Wake TV"`. Pressing it (`tv_act 40` with `fail_kind == "conn"`) sends `{cmd="wake", host, mac}` and then `reconnect`.
  - `ev kind`: find the saved host, set `kind = "webos"`, `save_cfg()`, `refresh_menu()`, then `set_stage(0, "Asking the TV…", "Accept the prompt on the TV.")` and `send({cmd="pair", host, kind="webos", mac=""})`.
- [ ] **Step 3: Actions.** For webos: `[17]` sends `{cmd="inputs"}`, `[18]` `{cmd="apps"}`, `[19]` `{cmd="launch", id="youtube.leanback.v4"}`, `[20]` `{cmd="launch", id="netflix"}`. Google TV keeps `LINK`.
- [ ] **Step 4: The sheet.** Keep `sheet = { kind = "inputs"|"apps", list = {...}, page = 0 }`.
  - `show_sheet()` writes `text.sheet_t` ("Inputs", or "Apps · page/pages") and `text["sheet_" .. k]` for k = 0..7 from
    `list[page * 8 + k + 1].label`. With more than 8 items, row 8 is "More…". It sets `fact.sheet_cnt` and `fact.sheet_cur` (the index of the
    `on` row on this page, or -1), then `fact.sheet_open = true`.
  - `on("tv_sheet", k)`: row 8 with "More…" turns the page and wraps. Otherwise send `{cmd="input", id}` (inputs) or
    `{cmd="launch", id}` (apps), then `fact.sheet_open = false`.
  - `use(i)` and `add_stage()` also set `fact.sheet_open = false`.
- [ ] **Step 5: App names.** Add `["youtube.leanback.v4"] = "YouTube"`, `["netflix"] = "Netflix"`, `["amazon"] = "Prime Video"`,
  `["com.webos.app.livetv"] = "Live TV"` and `["com.webos.app.home"] = "Home"`. `app_label` maps `com%.webos%.app%.hdmi(%d)` to `"HDMI " .. n`.
- [ ] **Step 6: Check against the stand-in.** Not possible without the scene facts (Task 4). Check the logic loads: restart the
  add-on, look for `tvremote` errors in its log, and confirm `pleamar --say tvremote "get tv_kind"` answers 0 with the onn box picked.
- [ ] **Step 7: Commit.** `git add addons/tvremote/tvremote.luau && git commit -m "TV Remote: the panel's logic keeps each TV's kind (Google TV or LG) and MAC, pairs an LG by its prompt, and fills a page of inputs or apps"`

---

### Task 4: The panel shows the LG's buttons and the list sheet

**Files:** Modify `addons/tvremote/tvremote.plm`.

- [ ] **Step 1: Facts.** Beside the switcher's facts add:
  - `fact tv_kind = 0`, `fact sheet_open = false`, `fact sheet_cnt = 0`, `fact sheet_cur = -1`;
  - `text sheet_t = ""` and `text sheet_0` … `text sheet_8`;
  - `event tv_sheet ->`.

  In the header comment's action list, note "17..20 apps (an LG: inputs, apps, YouTube, Netflix)".
- [ ] **Step 2: Overlays.**
  - Replace `follow mo = if(menu_open and st != 2, 1, 0)` with `follow mo = if((menu_open or sheet_open) and st != 2, 1, 0)`.
  - Add `prop mn = 0 ~calm`, `follow mn = if(menu_open and st != 2, 1, 0)`, `prop so = 0 ~calm`, `follow so = if(sheet_open and st == 1, 1, 0)`.
  - The switcher group's `opacity` becomes `en2 * mn`, and its zones' `active` use `mn > 0.5`.
  - The header chevron's `mo` becomes `mn`.
  - `on press nm_z { toggle menu_open; sheet_open = false }`.
- [ ] **Step 3: Labels.** In the button table, the existing label `text pick(k, …)` gets `opacity: shown * (1 - lg)`, where
  `let lg = if(tv_kind == 1 and k >= 7, 1, 0)`. A second `text pick(k, "", "", "", "", "", "", "", "Inputs", "Apps", "YouTube", "Netflix")`
  with the same placement and style gets `opacity: shown * lg`. The zone label stays the same.
- [ ] **Step 4: The sheet.** After the switcher group:

```
        //  ── a list from an LG: its inputs, or its apps, eight to a page (the ninth row turns the page) ──
        group {
            opacity: en2 * so
            move: 0, (1 - en2) * 12
            text sheet_t { at: cx, top + 112 * u; anchor: center; size: 12 * u; weight: 700; width: W0 - 2 * m - 40 * u; lines: 1; align: center; color: faint; opacity: shown; family: "Space Grotesk" }
            text "×" { at: left + W0 - m - 12 * u, top + 112 * u; anchor: center; size: 18 * u; weight: 600; color: mix(faint, alert, sx.hover); opacity: shown; family: "Space Grotesk" }
            zone ellipse sx { at: left + W0 - m - 12 * u, top + 112 * u; radius: 11 * u; cursor: pointer; label: "Close the list"; active: shown > 0.5 and so > 0.5 }
            on press sx { sheet_open = false }
            repeat k in 0..9 {
                let ry = top + (140 + k * 32) * u
                let on = if(sheet_cnt > k, 1, 0)
                let cur = if(sheet_cur == k, 1, 0)
                let hv = srow.$k.hover
                let fl = if(cur > 0.5, 24%, 8% + 10% * hv + 10% * srow.$k.pressed)
                box { at: cx, ry; size: W0 - 2 * m, 26 * u; corner: 13 * u; color: if(cur > 0.5, mint, ink); opacity: fl * shown * on }
                TvPill(cx: cx, cy: ry, w: W0 - 2 * m, h: 26 * u, r: 13 * u, hot: hv, o: clamp(3 * fl, 0, 1) * shown * on, ku: u)
                text pick(k, sheet_0, sheet_1, sheet_2, sheet_3, sheet_4, sheet_5, sheet_6, sheet_7, sheet_8) { at: floor(left + m + 16 * u), floor(ry + 0.5); anchor: left center; size: 13 * u; weight: 600; width: W0 - 2 * m - 32 * u; lines: 1; color: if(cur > 0.5, mint, ink); opacity: shown * on; family: "Space Grotesk" }
                zone box srow.$k { at: cx, ry; size: W0 - 2 * m, 28 * u; corner: 14 * u; cursor: pointer; label: pick(k, sheet_0, sheet_1, sheet_2, sheet_3, sheet_4, sheet_5, sheet_6, sheet_7, sheet_8); active: shown > 0.5 and so > 0.5 and on > 0.5 }
                on press srow.$k { emit tv_sheet(k) }
            }
        }
```

- [ ] **Step 5: Check.** Run `pleamar --check addons/tvremote/tvremote.plm` and fix any syntax error against `pleamar --docs reference`
  (never guess a keyword). Restart the add-on. Check with the onn box: the labels are unchanged, and the switcher opens and shuts.
- [ ] **Step 6: Commit.** `git add addons/tvremote/tvremote.plm && git commit -m "TV Remote: an LG's app row reads Inputs, Apps, YouTube, Netflix, and its inputs and apps open as a list"`

---

### Task 5: Live with the OLED, then the pull request

- [ ] **Step 1: Pair.** In the panel, Add a TV and pick the OLED (or type 10.0.0.4). Press Pair and **ask the user to accept the prompt on the TV**.
  Check that the stage becomes ready with "OLED65CX…" and the volume.
- [ ] **Step 2: Each feature, with the user watching the TV:**
  - the d-pad, OK, Back and Home;
  - volume up and down, and mute;
  - Inputs → the onn's HDMI;
  - Apps → Netflix;
  - typing into YouTube search;
  - Power off;
  - then "Wake TV" (only if the TV allows wake over Wi-Fi: ask the user to check the TV setting if it stays off).

  Fix what fails as its own commit, with a check added to the stand-in test where possible.
- [ ] **Step 3: Both kinds in one switcher.** Switch to the onn box and back. Both connect, and each shows its own labels.
- [ ] **Step 4: Branch for the pull request.**
  - Run `git switch -c tvremote-webos origin/main`.
  - Cherry-pick 818ba1d (#32), unless upstream has fixed it already, plus Tasks 1 to 4's commits. Leave out the docs commits.
  - Run `pleamar --check addons/tvremote/tvremote.plm` and `python3 dev/tvremote-webos-test.py`, then `git switch fx`.
  - The user pushes the branch to the fork and opens the PR (the auto-mode classifier blocks outside writes). The PR text has the
    feature list, how it was tested, refers to #32, and says an AI assistant helped.
- [ ] **Step 5: Memory.** Add a paragraph on the local commits, the PR, and the key-file and test-port conventions to `vitreus_pleamar_shell_cyber_theme.md`.
