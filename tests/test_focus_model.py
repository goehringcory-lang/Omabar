"""Checks for Focus mode: modules/OmabarFocusModel.js (run through node) and
bin/omabar-focus, which must agree on the schedule. From the repository root:

    python3 -m unittest discover -s tests
"""
import importlib.machinery
import importlib.util
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..")
MODEL = os.path.join(ROOT, "modules", "OmabarFocusModel.js")
CLI = os.path.join(ROOT, "bin", "omabar-focus")
NODE = shutil.which("node")
MIN = 60000


def load_cli():
    loader = importlib.machinery.SourceFileLoader("omabar_focus", CLI)
    spec = importlib.util.spec_from_loader("omabar_focus", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


focus_cli = load_cli()


def js(fn, *args):
    script = "const m = require(%s); process.stdout.write(JSON.stringify(m[%s](...%s)))" % (
        json.dumps(MODEL), json.dumps(fn), json.dumps(list(args)))
    out = subprocess.run([NODE, "-e", script], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out else None


def started(**extra):
    state = {"active": True, "startedAt": 1_000_000, "pausedAt": None, "pausedMs": 0}
    state.update(extra)
    return state


@unittest.skipUnless(NODE, "node is not installed")
class ModelTest(unittest.TestCase):
    def at(self, state, minutes):
        return js("at", state, state["startedAt"] + minutes * MIN)

    def test_first_round(self):
        info = self.at(started(), 10)
        self.assertEqual((info["phase"], info["round"], info["rounds"]), ("focus", 1, 4))
        self.assertEqual(info["remainingMs"], 15 * MIN)
        self.assertAlmostEqual(info["progress"], 0.4)

    def test_breaks(self):
        self.assertEqual(self.at(started(), 26)["phase"], "break")
        self.assertFalse(self.at(started(), 26)["long"])
        self.assertEqual(self.at(started(), 31)["round"], 2)
        # 4 x 25 focus + 3 x 5 break = 115 minutes, then the long break.
        info = self.at(started(), 116)
        self.assertTrue(info["long"])
        self.assertEqual(info["remainingMs"], 14 * MIN)

    def test_ends_after_long_break(self):
        self.assertFalse(self.at(started(), 129)["finished"])
        self.assertTrue(self.at(started(), 130)["finished"])
        self.assertTrue(self.at(started(), 400)["finished"])

    def test_repeat_starts_over(self):
        info = self.at(started(repeat=True), 135)
        self.assertFalse(info["finished"])
        self.assertEqual((info["phase"], info["round"]), ("focus", 1))
        self.assertEqual(info["cycleIndex"], 8)

    def test_pause_holds_time(self):
        state = started(pausedAt=1_000_000 + 10 * MIN)
        self.assertEqual(self.at(state, 50)["remainingMs"], 15 * MIN)
        self.assertTrue(self.at(state, 50)["paused"])
        state = started(pausedMs=5 * MIN)
        self.assertEqual(self.at(state, 10)["remainingMs"], 20 * MIN)

    def test_custom_lengths(self):
        info = self.at(started(focus=50, shortBreak=10, rounds=2), 55)
        self.assertEqual((info["phase"], info["remainingMs"]), ("break", 5 * MIN))

    def test_bad_values_fall_back(self):
        info = self.at(started(focus="x", rounds=0), 0)
        self.assertEqual((info["lengthMs"], info["rounds"]), (25 * MIN, 4))

    def test_off(self):
        self.assertFalse(js("at", {}, 0)["active"])
        self.assertFalse(js("at", {"active": False, "startedAt": 5}, 10)["active"])

    def test_agrees_with_cli(self):
        states = [started(), started(repeat=True), started(focus=50, shortBreak=10, longBreak=30, rounds=3),
                  started(pausedAt=1_000_000 + 33 * MIN, pausedMs=-4 * MIN), started(focus=1, shortBreak=1, rounds=1)]
        for state in states:
            for minutes in (0, 0.5, 24.99, 25, 29, 30, 77.3, 116, 129.9, 130, 131, 260, 1000):
                now = state["startedAt"] + int(minutes * MIN)
                a = js("at", state, now)
                b = focus_cli.at(state, now)
                for key in ("active", "paused", "finished", "phase", "round", "rounds", "long",
                            "lengthMs", "remainingMs", "cycleIndex"):
                    self.assertEqual(a[key], b[key], f"{key} at {minutes} min for {state}")
                self.assertAlmostEqual(a["progress"], b["progress"])

    def test_text(self):
        info = self.at(started(), 10)
        self.assertEqual(js("summary", info), "Focus 1 of 4 · 15 min left")
        self.assertEqual(js("clock", 15 * MIN - 1500), "14:59")
        self.assertEqual(js("timeLeft", 30000), "30 s")
        self.assertEqual(js("summary", self.at(started(), 116)), "Long break · 14 min left")

    def test_ticks_follow_the_ring(self):
        info = self.at(started(), 0)
        # A 25 minute round on a 100 px ring: a pixel every 15 s.
        self.assertEqual(js("nextTick", info, 100, 1), 15000)
        near_end = self.at(started(), 24.99)
        self.assertGreaterEqual(js("nextTick", near_end, 100, 1), 1000)
        self.assertEqual(js("nextTick", {"active": False}, 100, 1), 60000)


@unittest.skipUnless(NODE, "node is not installed")
class OutlineTest(unittest.TestCase):
    def test_starts_top_middle_and_closes(self):
        pts = js("outline", 0, 0, 28, 28, 10, 1, 1.5)
        self.assertEqual(pts[0], {"x": 14, "y": 0})
        self.assertAlmostEqual(pts[-1]["x"], 14)
        self.assertAlmostEqual(pts[-1]["y"], 0)

    def test_quarter_is_right_edge_middle(self):
        pts = js("outline", 0, 0, 28, 28, 10, 0.25, 1.5)
        self.assertAlmostEqual(pts[-1]["x"], 28)
        self.assertAlmostEqual(pts[-1]["y"], 14)

    def test_points_stay_on_the_outline(self):
        r = 9
        for p in js("outline", 0, 0, 28, 28, r, 0.83, 1):
            x, y = p["x"], p["y"]
            # Distance to the rounded square's outline is zero.
            dx = max(abs(x - 14) - (14 - r), 0)
            dy = max(abs(y - 14) - (14 - r), 0)
            inner = math.hypot(dx, dy)
            on_edge = abs(inner - r) < 1e-6 if (dx > 0 and dy > 0) else (abs(abs(x - 14) - 14) < 1e-6 or abs(abs(y - 14) - 14) < 1e-6)
            self.assertTrue(on_edge, p)

    def test_range_runs_from_the_hand_to_the_top(self):
        pts = js("outlineRange", 0, 0, 28, 28, 0, 0.25, 1, 1)
        self.assertAlmostEqual(pts[0]["x"], 28)
        self.assertAlmostEqual(pts[0]["y"], 14)
        self.assertAlmostEqual(pts[-1]["x"], 14)
        self.assertAlmostEqual(pts[-1]["y"], 0)
        self.assertEqual(js("outlineRange", 0, 0, 28, 28, 6, 0, 0.5, 1), js("outline", 0, 0, 28, 28, 6, 0.5, 1))

    def test_length(self):
        self.assertAlmostEqual(js("outlineLength", 28, 28, 0), 112)
        self.assertAlmostEqual(js("outlineLength", 20, 20, 10), math.pi * 20)

    def test_empty(self):
        self.assertEqual(js("outline", 0, 0, 28, 28, 10, 0, 1), [{"x": 14, "y": 0}])


class CliTest(unittest.TestCase):
    """bin/omabar-focus with stand-ins for omarchy-shell and busctl."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        self.log = os.path.join(self.tmp, "log")
        self.dnd_file = os.path.join(self.tmp, "dnd")
        self.playing_file = os.path.join(self.tmp, "playing")
        self.other_file = os.path.join(self.tmp, "other-player")
        self.write("omarchy-shell", f"""#!/bin/sh
echo "omarchy-shell $*" >> {self.log}
# Like the real one, -q runs the call but prints nothing.
quiet=0
[ "$1" = "-q" ] && quiet=1 && shift
case "$2" in
  isDnd) out=$(cat {self.dnd_file}) ;;
  setDnd) echo "$3" > {self.dnd_file}; out="$3" ;;
esac
[ $quiet = 1 ] || echo "$out"
""")
        self.write("busctl", f"""#!/bin/sh
echo "busctl $*" >> {self.log}
case "$*" in
  *" list"*) [ -f {self.other_file} ] && echo "org.mpris.MediaPlayer2.mpv 123 mpv user :1.9 - - -"; exit 0 ;;
  *MediaPlayer2.mpv*PlaybackStatus*) echo 's "Playing"' ;;
  *PlaybackStatus*) [ -f {self.playing_file} ] && echo "s \\"$(cat {self.playing_file})\\"" || exit 1 ;;
esac
""")
        # Spotify itself: the helper is replaced by one that only logs.
        self.plugin = os.path.join(self.tmp, "plugin", "bin")
        os.makedirs(self.plugin)
        shutil.copy(CLI, self.plugin)
        with open(os.path.join(self.plugin, "omabar-spotify"), "w") as handle:
            handle.write(f"import sys\nopen({self.log!r}, 'a').write('spotify ' + ' '.join(sys.argv[1:]) + '\\n')\n")
        self.env = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"],
                        XDG_CONFIG_HOME=os.path.join(self.tmp, "config"),
                        XDG_STATE_HOME=os.path.join(self.tmp, "state"))
        self.state_file = os.path.join(self.tmp, "state", "omabar", "focus.json")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, name, text):
        path = os.path.join(self.bin, name)
        with open(path, "w") as handle:
            handle.write(text)
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

    def set_dnd(self, value):
        with open(self.dnd_file, "w") as handle:
            handle.write(value)

    def dnd(self):
        with open(self.dnd_file) as handle:
            return handle.read().strip()

    def run_cli(self, *args):
        result = subprocess.run([os.path.join(self.plugin, "omabar-focus"), *args], env=self.env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def state(self):
        with open(self.state_file) as handle:
            return json.load(handle)

    def logged(self):
        try:
            with open(self.log) as handle:
                return handle.read()
        except OSError:
            return ""

    def wait_for(self, text):
        for _ in range(50):
            if text in self.logged():
                return True
            subprocess.run(["sleep", "0.1"])
        return False

    def test_start_and_stop_restore_everything(self):
        self.set_dnd("off")
        self.run_cli("start")
        state = self.state()
        self.assertTrue(state["active"])
        self.assertTrue(state["dndSet"])
        self.assertTrue(state["ownsMusic"])
        self.assertEqual(self.dnd(), "on")
        self.assertTrue(self.wait_for("spotify play spotify:playlist:0vvXsWCC9xrXsKd4FyS8kM"))
        with open(self.playing_file, "w") as handle:
            handle.write("Playing")
        self.run_cli("stop")
        self.assertFalse(self.state()["active"])
        self.assertEqual(self.dnd(), "off")
        self.assertIn("Pause", self.logged())

    def test_leaves_dnd_and_music_it_did_not_start(self):
        self.set_dnd("on")
        with open(self.playing_file, "w") as handle:
            handle.write("Playing")
        self.run_cli("start")
        state = self.state()
        self.assertFalse(state["dndSet"])
        self.assertFalse(state["ownsMusic"])
        self.run_cli("stop")
        self.assertEqual(self.dnd(), "on")
        self.assertNotIn("Pause", self.logged())
        self.assertNotIn("spotify play", self.logged())

    def test_other_player_playing_keeps_lofi_off(self):
        self.set_dnd("off")
        open(self.other_file, "w").close()
        self.run_cli("start")
        self.assertFalse(self.state()["ownsMusic"])
        self.assertNotIn("spotify play", self.logged())

    def test_dnd_turned_off_by_hand_stays_off(self):
        self.set_dnd("off")
        self.run_cli("start")
        self.set_dnd("off")
        before = self.logged().count("setDnd")
        self.run_cli("stop")
        self.assertEqual(self.logged().count("setDnd"), before)

    def test_toggle_pause_resume_skip(self):
        self.set_dnd("off")
        self.run_cli("toggle")
        self.assertTrue(self.state()["active"])
        self.run_cli("pause")
        self.assertTrue(self.state()["pausedAt"])
        self.assertTrue(json.loads(self.run_cli("status"))["paused"])
        self.run_cli("resume")
        self.assertIsNone(self.state()["pausedAt"])
        self.run_cli("skip")
        status = json.loads(self.run_cli("status"))
        self.assertEqual(status["phase"], "break")
        self.run_cli("toggle")
        self.assertFalse(self.state()["active"])

    def test_pause_at_a_moment(self):
        self.set_dnd("off")
        self.run_cli("start")
        start = self.state()["startedAt"]
        # Never before the start, and never in the future.
        self.run_cli("pause", "--at", str(start - 99999))
        self.assertEqual(self.state()["pausedAt"], start)
        self.run_cli("resume")
        self.run_cli("pause", "--at", str(start + 10**9))
        self.assertLess(self.state()["pausedAt"], start + 10**8)

    def test_skipping_the_last_break_ends_focus(self):
        self.set_dnd("off")
        self.run_cli("set", "rounds", "1")
        self.run_cli("start")
        self.run_cli("skip")
        self.run_cli("skip")
        self.assertFalse(self.state()["active"])
        self.assertEqual(self.dnd(), "off")

    def test_settings(self):
        self.run_cli("set", "focus", "50")
        self.run_cli("set", "music", "false")
        self.set_dnd("off")
        self.run_cli("start")
        self.assertEqual(self.state()["focus"], 50)
        self.assertFalse(self.state()["ownsMusic"])
        bad = subprocess.run([os.path.join(self.plugin, "omabar-focus"), "set", "focus", "0"], env=self.env,
                             capture_output=True, text=True)
        self.assertEqual(bad.returncode, 2)

    def test_shell_not_answering(self):
        os.remove(os.path.join(self.bin, "omarchy-shell"))
        self.run_cli("start")
        self.assertFalse(self.state()["dndSet"])
        self.run_cli("stop")


if __name__ == "__main__":
    unittest.main()
