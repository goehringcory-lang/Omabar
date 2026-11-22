"""Checks for the calendar colors in bin/omabar-gcal. Run from the repository root:

    python3 -m unittest discover -s tests
"""
import importlib.machinery
import importlib.util
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.realpath(__file__))
SCRIPT = os.path.join(HERE, "..", "bin", "omabar-gcal")


def load():
    loader = importlib.machinery.SourceFileLoader("omabar_gcal", SCRIPT)
    spec = importlib.util.spec_from_loader("omabar_gcal", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Colors(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.gcal = load()
        self.gcal.CONFIG_DIR = self.dir.name
        self.gcal.CACHE_DIR = os.path.join(self.dir.name, "cache")
        self.gcal.PREFS_FILE = os.path.join(self.dir.name, "calendars.json")
        self.gcal.ICAL_FILE = os.path.join(self.dir.name, "ical-calendars.json")
        self.gcal.TOKEN_FILE = os.path.join(self.dir.name, "none.json")
        with open(self.gcal.ICAL_FILE, "w") as handle:
            json.dump([
                {"id": "ical-a", "url": "https://x.invalid/a", "name": "Personal", "color": "#039be5"},
                {"id": "ical-b", "url": "https://x.invalid/b", "name": "Work Shifts", "color": "#33b679"},
            ], handle)

    def tearDown(self):
        self.dir.cleanup()

    def colors(self):
        return {c["name"]: c["color"] for c in self.gcal.all_calendars()}

    def test_names_and_hex(self):
        self.assertEqual(self.gcal.parse_color("Orange"), "#ff8c00")
        self.assertEqual(self.gcal.parse_color("#ABCDEF"), "#abcdef")
        self.assertEqual(self.gcal.parse_color("abcdef"), "#abcdef")
        self.assertEqual(self.gcal.parse_color("default"), "")
        self.assertIsNone(self.gcal.parse_color("purple"))

    def test_picked_color_wins_and_resets(self):
        self.assertEqual(self.gcal.cmd_color(["work", "orange"]), 0)
        self.assertEqual(self.colors(), {"Personal": "#039be5", "Work Shifts": "#ff8c00"})
        self.assertEqual(self.gcal.cmd_color(["Work Shifts", "default"]), 0)
        self.assertEqual(self.colors()["Work Shifts"], "#33b679")

    def test_choice_lives_beside_shown_calendars(self):
        self.gcal.cmd_toggle("ical-a")
        self.gcal.cmd_color(["ical-a", "grape"])
        with open(self.gcal.PREFS_FILE) as handle:
            data = json.load(handle)
        self.assertEqual(data, {"shown": {"ical-a": False}, "colors": {"ical-a": "#8e24aa"}})

    def test_unknown_calendar_or_color(self):
        self.assertEqual(self.gcal.cmd_color(["nope", "orange"]), 1)
        self.assertEqual(self.gcal.cmd_color(["Personal", "purple"]), 1)
        self.assertFalse(os.path.exists(self.gcal.PREFS_FILE))

    def test_unreadable_settings_are_never_replaced(self):
        with open(self.gcal.PREFS_FILE, "w") as handle:
            handle.write('{"colors": {"ical-a": "#8e24aa"')   # cut off mid-write
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.gcal.cmd_toggle("ical-a"), 1)
        with self.assertRaises(self.gcal.PrefsUnreadable):
            self.gcal.set_color("ical-a", "#ff8c00")
        with open(self.gcal.PREFS_FILE) as handle:
            self.assertEqual(handle.read(), '{"colors": {"ical-a": "#8e24aa"')

    def test_overlapping_saves_keep_both_colors(self):
        import threading
        start = threading.Barrier(8)

        def pick(i):
            start.wait()
            self.gcal.set_color(f"cal-{i}", f"#00000{i}")
        threads = [threading.Thread(target=pick, args=(i,)) for i in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        with open(self.gcal.PREFS_FILE) as handle:
            self.assertEqual(len(json.load(handle)["colors"]), 8)


if __name__ == "__main__":
    unittest.main()
