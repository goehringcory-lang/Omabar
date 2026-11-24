"""Checks for modules/OmabarMoonModel.js (run through node). From the
repository root:

    python3 -m unittest discover -s tests
"""
import json
import os
import shutil
import subprocess
import unittest
from datetime import datetime, timezone

MODEL = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "modules", "OmabarMoonModel.js")
NODE = shutil.which("node")


def call(fn, *args):
    script = "const m = require(%s); process.stdout.write(JSON.stringify(m[%s](...%s)))" % (
        json.dumps(MODEL), json.dumps(fn), json.dumps(list(args)))
    out = subprocess.run([NODE, "-e", script], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out else None


def ms(text):
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc).timestamp() * 1000


DAY = 86400000

# Published moments (UTC) of new and full moon.
NEW = ["2024-01-11T11:57", "2025-01-29T12:36", "2026-11-09T07:02"]
FULL = ["2024-01-25T17:54", "2025-03-14T06:55", "2026-11-24T14:53"]


@unittest.skipUnless(NODE, "node is not installed")
class MoonModelTest(unittest.TestCase):
    def assertNear(self, found, expected, minutes):
        self.assertLess(abs(found - expected) / 60000, minutes)

    def test_new_and_full_moments(self):
        for when in NEW:
            self.assertNear(call("nextReach", ms(when) - 3 * DAY, 0), ms(when), 40)
        for when in FULL:
            self.assertNear(call("nextReach", ms(when) - 3 * DAY, 180), ms(when), 40)

    def test_illumination_at_new_and_full(self):
        for when in NEW:
            self.assertLess(call("illumination", call("elongation", ms(when))), 0.002)
        for when in FULL:
            self.assertGreater(call("illumination", call("elongation", ms(when))), 0.998)

    def test_quarters_are_half_lit(self):
        # First quarter 2024-01-18 03:52, last quarter 2024-02-02 23:18 (UTC).
        first = call("elongation", ms("2024-01-18T03:52"))
        last = call("elongation", ms("2024-02-02T23:18"))
        self.assertAlmostEqual(first, 90, delta=1)
        self.assertAlmostEqual(last, 270, delta=1)
        self.assertEqual(call("phaseName", first), "First quarter")
        self.assertEqual(call("phaseName", last), "Last quarter")

    def test_phase_names_through_a_month(self):
        start = ms(NEW[0])
        names = [call("phaseName", call("elongation", start + d * DAY)) for d in (0, 4, 7, 11, 14, 18, 22, 26)]
        self.assertEqual(names, ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
                                 "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"])

    def test_shape_sides(self):
        crescent = call("shape", 45, False)
        self.assertTrue(crescent["litRight"])
        self.assertTrue(crescent["bulgeOut"])
        gibbous = call("shape", 135, False)
        self.assertTrue(gibbous["litRight"])
        self.assertFalse(gibbous["bulgeOut"])
        waning = call("shape", 300, False)
        self.assertFalse(waning["litRight"])
        self.assertTrue(waning["bulgeOut"])
        # South of the equator the moon is mirrored.
        self.assertFalse(call("shape", 45, True)["litRight"])
        self.assertAlmostEqual(call("shape", 90, False)["terminatorRx"], 0, places=6)


if __name__ == "__main__":
    unittest.main()
