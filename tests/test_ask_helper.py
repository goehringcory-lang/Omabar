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
IMAGE_HELPER = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin", "omabar-ask-image")

STUBS = {
    # Logs each call; the focused window's title comes from $STUB/title.
    "omarchy-launch-browser": 'echo "open $*" >> "$STUB/log"',
    "hyprctl": 'printf \'{"title":"%s"}\' "$(cat "$STUB/title" 2>/dev/null)"',
    "wtype": 'echo "wtype $*" >> "$STUB/log"',
    "wl-copy": 'if [[ $1 == --type ]]; then echo "copy-$2 $(cat)"; else echo "copy $(cat)"; fi >> "$STUB/log"',
    # What's on the clipboard comes from $STUB/types and $STUB/clip.
    "wl-paste": 'if [[ $1 == --list-types ]]; then cat "$STUB/types" 2>/dev/null || echo text/plain; '
                'else cat "$STUB/clip" 2>/dev/null || printf "old clip"; fi',
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
        self.pics = os.path.join(self.dir, "pics")
        self.env = dict(os.environ, STUB=self.dir, OMABAR_ASK_WAIT_TICKS="3", OMABAR_ASK_IMAGES=self.pics,
                        PATH=bindir + ":" + os.environ["PATH"])

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, name, text):
        with open(os.path.join(self.dir, name), "w") as f:
            f.write(text)

    def picture(self, name, data="PNGDATA"):
        os.makedirs(self.pics, exist_ok=True)
        path = os.path.join(self.pics, name)
        with open(path, "w") as f:
            f.write(data)
        return path

    def run_helper(self, mode, title_now, expect="Gemini", question="why is the sky blue?", pictures=()):
        self.write("title", title_now)
        subprocess.run([HELPER, mode, "https://gemini.google.com/app", expect, "Gemini", question, "0", "0", *pictures],
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

    def test_pictures_go_in_before_the_question(self):
        a = self.picture("paste-a.png", "AAA")
        b = self.picture("paste-b.jpg", "BBB")
        # Even in link mode: a picture can only be pasted in.
        log = self.run_helper("link", "Google Gemini - Brave", pictures=(a, b))
        self.assertEqual(log, [
            "open https://gemini.google.com/app",
            "copy-image/png AAA",
            "wtype -M ctrl -k v -m ctrl",
            "copy-image/jpeg BBB",
            "wtype -M ctrl -k v -m ctrl",
            "copy why is the sky blue?",
            "wtype -M ctrl -k v -m ctrl",
            "wtype -k Return",
            "copy old clip",
        ])
        # Asked, so the saved pictures are gone.
        self.assertFalse(os.path.exists(a) or os.path.exists(b))

    def test_picture_alone_and_image_clipboard_restored(self):
        a = self.picture("paste-a.png", "AAA")
        self.write("types", "image/png\n")
        self.write("clip", "SHOT")
        log = self.run_helper("paste", "Gemini", question="", pictures=(a,))
        self.assertEqual(log, [
            "open https://gemini.google.com/app",
            "copy-image/png AAA",
            "wtype -M ctrl -k v -m ctrl",
            "wtype -k Return",
            "copy-image/png SHOT",
        ])

    def test_pictures_kept_when_site_never_opens(self):
        a = self.picture("paste-a.png")
        log = self.run_helper("paste", "Terminal", pictures=(a,))
        self.assertFalse(any(line.startswith("wtype") for line in log))
        self.assertIn("copy why is the sky blue?", log)
        self.assertTrue(os.path.exists(a))


@unittest.skipUnless(shutil.which("bash"), "bash is not installed")
class AskImageTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        bindir = os.path.join(self.dir, "bin")
        os.mkdir(bindir)
        path = os.path.join(bindir, "wl-paste")
        with open(path, "w") as f:
            f.write("#!/bin/bash\n" + STUBS["wl-paste"].replace("|| printf \"old clip\"", "") + "\n")
        os.chmod(path, 0o755)
        self.pics = os.path.join(self.dir, "pics")
        self.env = dict(os.environ, STUB=self.dir, OMABAR_ASK_IMAGES=self.pics, PATH=bindir + ":" + os.environ["PATH"])

    def tearDown(self):
        shutil.rmtree(self.dir)

    def clipboard(self, types, data):
        with open(os.path.join(self.dir, "types"), "w") as f:
            f.write(types)
        with open(os.path.join(self.dir, "clip"), "w") as f:
            f.write(data)

    def grab(self):
        return subprocess.run([IMAGE_HELPER, "grab"], env=self.env, capture_output=True, text=True, timeout=10)

    def test_grabs_a_screenshot(self):
        self.clipboard("text/html\nimage/png\n", "PNGDATA")
        out = self.grab()
        self.assertEqual(out.returncode, 0)
        path = out.stdout.strip()
        self.assertTrue(path.startswith(self.pics + "/paste-") and path.endswith(".png"))
        with open(path) as f:
            self.assertEqual(f.read(), "PNGDATA")
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)

    def test_text_is_not_a_picture(self):
        self.clipboard("text/plain\n", "hello")
        out = self.grab()
        self.assertEqual(out.returncode, 1)
        self.assertEqual(out.stdout, "")

    def test_grabs_a_copied_photo_file(self):
        photo = os.path.join(self.dir, "My Photo.JPG")
        with open(photo, "w") as f:
            f.write("JPEGDATA")
        self.clipboard("text/uri-list\n", "file://" + photo.replace(" ", "%20") + "\r\n")
        path = self.grab().stdout.strip()
        self.assertTrue(path.endswith(".jpg"))
        with open(path) as f:
            self.assertEqual(f.read(), "JPEGDATA")

    def test_drop_only_removes_its_own(self):
        self.clipboard("image/png\n", "PNGDATA")
        path = self.grab().stdout.strip()
        outside = os.path.join(self.dir, "keep.png")
        open(outside, "w").close()
        subprocess.run([IMAGE_HELPER, "drop", outside], env=self.env, timeout=10)
        subprocess.run([IMAGE_HELPER, "drop", self.pics + "/../keep.png"], env=self.env, timeout=10)
        self.assertTrue(os.path.exists(outside))
        subprocess.run([IMAGE_HELPER, "drop", path], env=self.env, check=True, timeout=10)
        self.assertFalse(os.path.exists(path))


if __name__ == "__main__":
    unittest.main()
