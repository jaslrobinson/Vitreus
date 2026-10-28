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
import tempfile
import time

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
    if "lim:g_in" not in p:
        fail("no limiter in the running filter; it holds %s" % sorted(p)[:12])
    if not math.isclose(p["lim:g_in"], 10 ** (6 / 20), rel_tol=1e-3):
        fail("lim:g_in is %s, not +6 dB (%.4f)" % (p["lim:g_in"], 10 ** (6 / 20)))
    if not math.isclose(p.get("pre:Mult", 0), 1.0, rel_tol=1e-3):
        fail("with the limiter there is no head-room cut, but pre:Mult is %s" % p.get("pre:Mult"))
    eq.boost = 0.0                                       # a change reaches the running filter
    eq.push_params()
    time.sleep(0.5)
    if not math.isclose(params().get("lim:g_in", 0), 1.0, rel_tol=1e-3):
        fail("Boost 0 did not reach the running filter: %s" % params().get("lim:g_in"))
    eq.stop_chain(None)
    if eq.default_sink() != before:
        fail("the test changed the default output")
    print("PASS")


if __name__ == "__main__":
    main()
