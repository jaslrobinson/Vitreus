#!/usr/bin/env python3
"""The Equalizer's Boost, against the real PipeWire: a second EQ sink (vitreus_eq_test, never the default output) is started with
the helper's own functions, and what the running filter holds is read back from pw-dump.

    python3 dev/eq-boost-test.py          prints PASS, or FAIL and what went wrong (needs lsp-plugins-lv2 for the limiter checks)"""
import importlib.machinery
import importlib.util
import json
import math
import os
import subprocess
import sys
import struct
import tempfile
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["VITREUS_EQ_NAME"] = "vitreus_eq_test"
sys.argv = ["vitreus-eq", tempfile.mkdtemp()]
ld = importlib.machinery.SourceFileLoader("eq", os.path.join(HERE, "..", "bin", "vitreus-eq"))
eq = importlib.util.module_from_spec(importlib.util.spec_from_loader("eq", ld))
ld.exec_module(eq)


def fail(msg):
    print("FAIL:", msg)
    eq.stop_chain(None)
    sys.exit(1)


def params():
    """The running filter's control values, from pw-dump: {"pre:Mult": 1.0, "lim:g_in": 2.0, ...}."""
    for o in json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True).stdout or "[]"):
        if o.get("info", {}).get("props", {}).get("node.name") == eq.SINK:
            got = {}
            for p in o["info"].get("params", {}).get("Props", []):         # (several lists: PipeWire's own, then the filter's)
                ps = p.get("params")
                if isinstance(ps, list):
                    got.update(zip(ps[0::2], ps[1::2]))
            return got
    return {}


def loudness(play_to, sink, tone):
    """The RMS (dBFS) of `tone` played into `play_to`, as heard on `sink`'s monitor (a silent dummy output: nothing plays aloud)."""
    rec = subprocess.Popen(["parec", "-d", sink + ".monitor", "--format=s16le", "--channels=1", "--rate=48000", "--raw"], stdout=subprocess.PIPE)
    time.sleep(0.4)
    subprocess.run(["pw-play", "--target", play_to, tone], capture_output=True)
    time.sleep(0.3)
    rec.terminate()
    data = rec.stdout.read()
    n = len(data) // 2
    rms = math.sqrt(sum(x * x for x in struct.unpack("<%dh" % n, data[:n * 2])) / max(n, 1)) / 32768 if n else 0
    return 20 * math.log10(rms) if rms > 0 else -120


def thd(x, f0):
    import numpy as np
    x = np.asarray(x, dtype=float)
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / 48000)
    band = lambda c: spec[(f > c - 5) & (f < c + 5)].max()
    return math.sqrt(sum(band(f0 * k) ** 2 for k in range(2, 20))) / band(f0)


def check_boost_is_clean():
    """A loud 100 Hz tone (-3 dBFS, as a mastered song's bass) at Boost +12 comes out with under 2 % distortion (the first
    chain, a limiter alone with a 5 ms release, gave 9 %: heard as crackling)."""
    tmp = tempfile.mkdtemp()
    tone = tmp + "/bass.wav"
    with wave.open(tone, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(48000)
        w.writeframes(b"".join(struct.pack("<hh", v, v) for v in (int(0.708 * 32767 * math.sin(2 * math.pi * 100 * i / 48000)) for i in range(48000 * 2))))
    mod = subprocess.run(["pactl", "load-module", "module-null-sink", "sink_name=eqtest_null"], capture_output=True, text=True).stdout.strip()
    try:
        eq.gains = [0.0] * 10
        eq.boost = 12.0
        if not eq.start_chain("eqtest_null"):
            fail("the filter did not start on the dummy output: %s" % eq.error)
        eq.push_params()
        time.sleep(0.5)
        rec = subprocess.Popen(["parec", "-d", "eqtest_null.monitor", "--format=s16le", "--channels=1", "--rate=48000", "--raw"], stdout=subprocess.PIPE)
        time.sleep(0.4)
        subprocess.run(["pw-play", "--target", eq.SINK, tone], capture_output=True)
        time.sleep(0.3)
        rec.terminate()
        data = rec.stdout.read()
        eq.stop_chain(None)
        n = len(data) // 2
        x = [v / 32768 for v in struct.unpack("<%dh" % n, data[:n * 2]) if abs(v) > 3]
        x = x[len(x) // 4: len(x) * 3 // 4]
        d = thd(x, 100)
        if d > 0.02:
            fail("Boost +12 distorts a loud bass tone by %.1f %%" % (100 * d))
    finally:
        subprocess.run(["pactl", "unload-module", mod], capture_output=True)


def check_boost_is_heard():
    """The Boost raises what comes out: a -12 dBFS tone is 6 dB louder at +6 (the limiter must not take it back: its automatic
    level regulation did, so +6 gave 3 dB and +12 nothing more)."""
    tmp = tempfile.mkdtemp()
    tone = tmp + "/tone.wav"
    with wave.open(tone, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(48000)
        w.writeframes(b"".join(struct.pack("<hh", v, v) for v in (int(0.25 * 32767 * math.sin(2 * math.pi * 1000 * i / 48000)) for i in range(48000 * 2))))
    mod = subprocess.run(["pactl", "load-module", "module-null-sink", "sink_name=eqtest_null"], capture_output=True, text=True).stdout.strip()
    try:
        eq.gains = [0.0] * 10
        eq.boost = 0.0
        if not eq.start_chain("eqtest_null"):
            fail("the filter did not start on the dummy output: %s" % eq.error)
        eq.push_params()
        time.sleep(0.5)
        flat = loudness(eq.SINK, "eqtest_null", tone)
        eq.boost = 6.0
        eq.push_params()
        time.sleep(0.5)
        up = loudness(eq.SINK, "eqtest_null", tone)
        eq.stop_chain(None)
        if up - flat < 5.0:
            fail("Boost +6 dB raised the tone by only %.1f dB (%.1f -> %.1f dBFS)" % (up - flat, flat, up))
    finally:
        subprocess.run(["pactl", "unload-module", mod], capture_output=True)


def main():
    if not eq.limiter_available():
        fail("lsp-plugins-lv2 (limiter_mono) not found: install it to test the Boost")
    target = eq.real_default() or eq.default_sink()
    before = eq.default_sink()
    eq.gains = [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]
    eq.boost = 6.0
    if not eq.start_chain(target):
        fail("the filter did not start: %s" % eq.error)
    eq.push_params()
    time.sleep(0.5)
    p = params()
    if not eq.maximizer_available():
        fail("zam-plugins-lv2 (ZaMaximX2) not found: install it to test the Boost")
    if "lim:th" not in p:
        fail("no limiter in the running filter; it holds %s" % sorted(p)[:12])
    if not math.isclose(p.get("maxi:gain", -99), 6.0, abs_tol=0.05):
        fail("the maximizer's gain is %s, not +6 dB" % p.get("maxi:gain"))
    if not math.isclose(p.get("pre:Mult", 0), 1.0, rel_tol=1e-3):
        fail("with the limiter there is no head-room cut, but pre:Mult is %s" % p.get("pre:Mult"))
    eq.boost = 0.0                                       # a change reaches the running filter
    eq.push_params()
    time.sleep(0.5)
    if not math.isclose(params().get("maxi:gain", -99), 0.0, abs_tol=0.05):
        fail("Boost 0 did not reach the running filter: %s" % params().get("maxi:gain"))
    eq.stop_chain(None)
    time.sleep(0.5)
    check_boost_is_heard()
    time.sleep(0.5)
    check_boost_is_clean()
    if eq.default_sink() != before:
        fail("the test changed the default output")
    print("PASS")


if __name__ == "__main__":
    main()
