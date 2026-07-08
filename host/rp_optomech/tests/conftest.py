"""pytest path setup: make `rp_optomech` and the generated register modules importable."""

import os
import sys

# repo/host  -> so `import rp_optomech...` works
HOST = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# repo/host/rp_optomech -> so `import registers_core` (generated module) works
PKG = os.path.join(HOST, "rp_optomech")
# this dir -> so `import fake_daemon` (test helper) works
HERE = os.path.dirname(__file__)
for p in (HOST, PKG, HERE):
    if p not in sys.path:
        sys.path.insert(0, p)
