"""Checks for bin/omabar-ask with stand-in desktop commands. From the
repository root:

    python3 -m unittest discover -s tests
"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HELPER = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin", "omabar-ask")

STUBS = {
    # Logs each call; the focused window's title comes from $STUB/title.
    "omarchy-launch-browser": 'echo "open $*" >> "$STUB/log"',
    "hyprctl": 'printf \'{"title":"%s"}\' "$(cat "$STUB/title" 2>/dev/null)"',
    "wtype": 'echo "wtype $*" >> "$STUB/log"',
    "wl-copy": 'echo "copy $(cat)" >> "$STUB/log"',
    "wl-paste": 'if [[ $1 == --list-types ]]; then echo text/plain; else printf "old clip"; fi',
    "omarchy-notification-send": 'echo "notify $*" >> "$STUB/log"',
    "omarchy-cmd-missing": "exit 1",
}


@unittest.skipUnless(shutil.which("jq"), "jq is not installed")
class AskHelperTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        bindir = os.path.join(self.dir, "bin")
        os.mkdir(bindir)
        for name, body in STUBS.items():
            path = os.path.join(bindir, name)
            with open(path, "w") as f:
                f.write("#!/bin/bash\n" + body + "\n")
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
        self.env = dict(os.environ, STUB=self.dir, OMABAR_ASK_WAIT_TICKS="3", PATH=bindir + ":" + os.environ["PATH"])

    def tearDown(self):
        shutil.rmtree(self.dir)

    def run_helper(self, mode, title_now, expect="Gemini"):
        with open(os.path.join(self.dir, "title"), "w") as f:
            f.write(title_now)
        subprocess.run([HELPER, mode, "https://gemini.google.com/app", expect, "Gemini", "why is the sky blue?", "0"],
                       env=self.env, check=True, timeout=30)
        with open(os.path.join(self.dir, "log")) as f:
            return f.read().splitlines()

    def test_pastes_and_sends_then_restores_clipboard(self):
        log = self.run_helper("paste", "Google Gemini - Brave")
        self.assertEqual(log, [
            "open https://gemini.google.com/app",
            "copy why is the sky blue?",
            "wtype -M ctrl -k v -m ctrl",
            "wtype -k Return",
            "copy old clip",
        ])

    def test_never_types_into_another_window(self):
        # The site never becomes the focused window: nothing is typed, and the
        # question is left on the clipboard with a notice.
        log = self.run_helper("paste", "Terminal - nvim")
        self.assertFalse(any(line.startswith("wtype") for line in log))
        self.assertIn("copy why is the sky blue?", log)
        self.assertTrue(any(line.startswith("notify") for line in log))

    def test_link_mode_only_opens(self):
        self.assertEqual(self.run_helper("link", "Terminal"), ["open https://gemini.google.com/app"])

    def test_enter_mode_presses_enter_only(self):
        self.assertEqual(self.run_helper("enter", "Claude - Brave", "Claude"),
                         ["open https://gemini.google.com/app", "wtype -k Return"])


if __name__ == "__main__":
    unittest.main()
