"""pytest path setup: make `regspec` importable from regspec/tests/."""

import os
import sys

REGSPEC = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REGSPEC not in sys.path:
    sys.path.insert(0, REGSPEC)
