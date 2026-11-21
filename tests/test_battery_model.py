"""Checks for modules/OmabarBatteryModel.js (run through node). From the
repository root:

    python3 -m unittest discover -s tests
"""
import json
import os
import shutil
import subprocess
import unittest

MODEL = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "modules", "OmabarBatteryModel.js")
NODE = shutil.which("node")


def call(fn, *args):
    script = "const m = require(%s); process.stdout.write(JSON.stringify(m[%s](...%s)))" % (
        json.dumps(MODEL), json.dumps(fn), json.dumps(list(args)))
    out = subprocess.run([NODE, "-e", script], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out else None


def bat(name, percent, state="discharging", energy=None, capacity=None):
    b = {"name": name, "percent": percent, "state": state}
    if capacity is not None:
        b["capacity"] = capacity
        b["energy"] = energy if energy is not None else capacity * percent / 100
    return b


@unittest.skipUnless(NODE, "node is not installed")
class BatteryModelTest(unittest.TestCase):
    def pair(self, *batteries, external="BAT1"):
        return call("split", list(batteries), external)

    def test_t480_split(self):
        p = self.pair(bat("BAT1", 80), bat("BAT0", 5))
        self.assertEqual(p["external"]["name"], "BAT1")
        self.assertEqual(p["internal"]["name"], "BAT0")

    def test_only_internal_when_pack_removed(self):
        p = self.pair(bat("BAT0", 60))
        self.assertIsNone(p["external"])
        self.assertEqual(p["internal"]["name"], "BAT0")
        self.assertEqual(call("focus", p, True), "internal")

    def test_unnamed_pair_takes_second_as_external(self):
        p = self.pair(bat("battery_a", 50), bat("battery_b", 40))
        self.assertEqual(p["external"]["name"], "battery_b")
        self.assertEqual(p["internal"]["name"], "battery_a")

    def test_external_leads_while_it_has_charge(self):
        p = self.pair(bat("BAT1", 42, "discharging"), bat("BAT0", 5, "unknown"))
        self.assertEqual(call("focus", p, True), "external")

    def test_internal_after_external_is_spent(self):
        p = self.pair(bat("BAT1", 0, "empty"), bat("BAT0", 95, "discharging"))
        self.assertEqual(call("focus", p, True), "internal")

    def test_hand_over_when_firmware_stops_pack_early(self):
        # Firmware moved to the internal pack while the external still reads 3%.
        p = self.pair(bat("BAT1", 3, "unknown"), bat("BAT0", 90, "discharging"))
        self.assertEqual(call("focus", p, True), "internal")

    def test_on_ac_shows_external_until_empty(self):
        p = self.pair(bat("BAT1", 30, "unknown"), bat("BAT0", 70, "charging"))
        self.assertEqual(call("focus", p, False), "external")
        p = self.pair(bat("BAT1", 0, "unknown"), bat("BAT0", 70, "charging"))
        self.assertEqual(call("focus", p, False), "internal")

    def test_total_is_energy_weighted(self):
        # T480: 24 Wh internal, 72 Wh external.
        p = self.pair(bat("BAT1", 50, capacity=72), bat("BAT0", 100, capacity=24))
        self.assertEqual(call("totalPercent", p), 63)

    def test_total_falls_back_to_average(self):
        p = self.pair(bat("BAT1", 50), bat("BAT0", 10))
        self.assertEqual(call("totalPercent", p), 30)

    def test_no_batteries(self):
        p = self.pair()
        self.assertEqual(call("focus", p, True), "")
        self.assertEqual(call("totalPercent", p), -1)

    def test_icons_and_time(self):
        self.assertEqual(call("icon", 100, False), "\U000F0079")
        self.assertEqual(call("icon", 5, True), "\U000F089C")
        self.assertEqual(call("formatMinutes", 5400), "1 h 30 min")
        self.assertEqual(call("formatMinutes", 0), "")

    def test_state_labels(self):
        self.assertEqual(call("stateLabel", None, False), "Not inserted")
        self.assertEqual(call("stateLabel", bat("BAT1", 40, "discharging"), True), "In use")
        self.assertEqual(call("stateLabel", bat("BAT0", 40, "unknown"), False), "Standby")


if __name__ == "__main__":
    unittest.main()
