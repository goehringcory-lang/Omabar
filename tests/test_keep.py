"""Checks bin/omabar-keep: status and cached answers without an account, the
keyring lookup, a sync through the Keep library's Python (faked here), the
token going over stdin rather than the command line, private cache files,
and how a pinned note or list is shaped for the card. From the repository
root:

    python3 -m unittest discover -s tests
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..")
HELPER = os.path.join(ROOT, "bin", "omabar-keep")

NOTES = [{"id": "a", "kind": "list", "title": "Groceries", "color": "YELLOW", "url": "https://keep.google.com/#LIST/a",
          "labels": [], "items": [{"text": "Milk", "checked": False, "indented": False}], "unchecked": 1, "checked": 0}]


def load_helper():
    loader = importlib.machinery.SourceFileLoader("omabar_keep", HELPER)
    spec = importlib.util.spec_from_loader("omabar_keep", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class KeepHelperTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home)
        self.bin = os.path.join(self.home, "bin")
        os.makedirs(self.bin)
        self.venv = os.path.join(self.home, "venv")
        os.makedirs(os.path.join(self.venv, "bin"))
        self.log = os.path.join(self.home, "worker.log")

    def script(self, path, body):
        with open(path, "w") as handle:
            handle.write(body)
        os.chmod(path, 0o755)

    def fake_keyring(self, token):
        # secret-tool lookup prints the token; anything else succeeds quietly.
        self.script(os.path.join(self.bin, "secret-tool"), textwrap.dedent(f"""\
            #!/bin/sh
            [ "$1" = lookup ] && printf '%s' '{token}'
            exit 0
            """))

    def fake_library(self, answer):
        # Stands in for the venv's Python: the import probe passes, and the
        # worker logs its arguments and stdin, then answers.
        self.script(os.path.join(self.venv, "bin", "python"), textwrap.dedent(f"""\
            #!/bin/sh
            [ "$2" = "-c" ] && exit 0
            echo "ARGS $*" >> '{self.log}'
            echo "STDIN $(cat)" >> '{self.log}'
            echo '{json.dumps(answer)}'
            """))

    def account(self, email="me@gmail.com"):
        folder = os.path.join(self.home, ".config", "omabar")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "keep.json"), "w") as handle:
            json.dump({"email": email, "device": "0123456789abcdef"}, handle)

    def run_helper(self, *args):
        env = dict(os.environ, HOME=self.home, PATH=self.bin + ":/usr/bin:/bin", OMABAR_KEEP_VENV=self.venv)
        for name in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"):
            env.pop(name, None)
        result = subprocess.run([sys.executable, HELPER, *args], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_help(self):
        self.assertIn("omabar-keep connect", self.run_helper("help"))

    def test_nothing_connected(self):
        self.assertEqual(json.loads(self.run_helper("status")), {"connected": False, "email": ""})
        self.assertFalse(json.loads(self.run_helper("cached"))["connected"])
        self.assertEqual(json.loads(self.run_helper("pinned")), {"connected": False, "notes": []})

    def test_token_missing_from_keyring(self):
        self.account()
        self.fake_keyring("")
        data = json.loads(self.run_helper("pinned"))
        self.assertFalse(data["connected"])
        self.assertIn("omabar-keep connect", data["error"])

    def test_sync_and_cache(self):
        self.account()
        self.fake_keyring("aas_et/secret-token")
        self.fake_library({"notes": NOTES})
        data = json.loads(self.run_helper("pinned"))
        self.assertTrue(data["connected"])
        self.assertEqual(data["notes"], NOTES)
        self.assertNotIn("error", data)

        with open(self.log) as handle:
            log = handle.read()
        args = [line for line in log.splitlines() if line.startswith("ARGS")][0]
        self.assertIn("_worker sync", args)
        self.assertNotIn("secret-token", args)          # never on the command line
        self.assertIn("aas_et/secret-token", log)       # it went in on stdin

        cache = os.path.join(self.home, ".cache", "omabar", "keep-pinned.json")
        self.assertEqual(stat.S_IMODE(os.stat(cache).st_mode), 0o600)
        with open(cache) as handle:
            self.assertNotIn("secret-token", handle.read())

        cached = json.loads(self.run_helper("cached"))
        self.assertTrue(cached["cached"])
        self.assertEqual(cached["notes"], NOTES)

    def test_failed_sync_keeps_last_notes(self):
        self.account()
        self.fake_keyring("aas_et/secret-token")
        self.fake_library({"notes": NOTES})
        self.run_helper("pinned")
        # Past the 10 second "just synced" window.
        cache = os.path.join(self.home, ".cache", "omabar", "keep-pinned.json")
        with open(cache) as handle:
            saved = json.load(handle)
        saved["synced"] -= 60
        with open(cache, "w") as handle:
            json.dump(saved, handle)
        self.fake_library({"error": "Google signed Omabar out of Keep.", "signedOut": True})
        data = json.loads(self.run_helper("pinned"))
        self.assertFalse(data["connected"])
        self.assertEqual(data["notes"], NOTES)
        self.assertIn("signed Omabar out", data["error"])

    def test_disconnect(self):
        self.account()
        self.fake_keyring("aas_et/secret-token")
        self.fake_library({"notes": NOTES})
        self.run_helper("pinned")
        self.assertIn("disconnected", self.run_helper("disconnect"))
        self.assertFalse(os.path.exists(os.path.join(self.home, ".config", "omabar", "keep.json")))
        self.assertFalse(os.path.exists(os.path.join(self.home, ".cache", "omabar", "keep-pinned.json")))

    def test_open_only_keep_links(self):
        env = dict(os.environ, HOME=self.home, PATH=self.bin)
        result = subprocess.run([sys.executable, HELPER, "open", "https://example.com/"], env=env,
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)


class ShapeNoteTest(unittest.TestCase):
    """Runs only where gkeepapi is installed (pip install gkeepapi)."""

    def setUp(self):
        try:
            import gkeepapi  # noqa: F401
        except ImportError:
            self.skipTest("gkeepapi not installed")
        self.gkeepapi = gkeepapi
        self.helper = load_helper()

    def test_pinned_lists_and_notes(self):
        keep = self.gkeepapi.Keep()
        groceries = keep.createList("Groceries", [("Milk", False), ("Eggs", True), ("Bread", False)])
        groceries.pinned = True
        groceries.color = self.gkeepapi.node.ColorValue.Yellow
        idea = keep.createNote("Idea", "x" * 2000)
        idea.pinned = True
        keep.createNote("Not pinned", "")

        notes = self.helper.pinned_notes(keep)
        self.assertEqual({note["title"] for note in notes}, {"Groceries", "Idea"})
        shaped = {note["title"]: note for note in notes}
        self.assertEqual(shaped["Groceries"]["kind"], "list")
        self.assertEqual(shaped["Groceries"]["color"], "YELLOW")
        self.assertEqual(shaped["Groceries"]["unchecked"], 2)
        self.assertEqual(shaped["Groceries"]["checked"], 1)
        # Open items first, checked ones after.
        self.assertEqual([item["checked"] for item in shaped["Groceries"]["items"]], [False, False, True])
        self.assertTrue(shaped["Groceries"]["url"].startswith("https://keep.google.com/#LIST/"))
        self.assertEqual(shaped["Idea"]["kind"], "note")
        self.assertLessEqual(len(shaped["Idea"]["text"]), self.helper.MAX_TEXT + 1)


class BrowserSigninTest(unittest.TestCase):
    """The one-click sign-in: picking Google's code out of the browser's
    cookies, and (where a Chromium is around) the whole DevTools round trip
    against a stand-in sign-in page."""

    def setUp(self):
        self.helper = load_helper()

    def test_signin_cookie(self):
        cookies = [{"name": "SID", "value": "x", "domain": ".google.com"},
                   {"name": "oauth_token", "value": "oauth2_4/abc", "domain": "accounts.google.com"}]
        self.assertEqual(self.helper.signin_cookie(cookies, "accounts.google.com"), "oauth2_4/abc")
        # Another site's cookie of the same name doesn't count.
        self.assertEqual(self.helper.signin_cookie([{"name": "oauth_token", "value": "x", "domain": "evil.example"}],
                                                   "accounts.google.com"), "")
        self.assertEqual(self.helper.signin_cookie([], "accounts.google.com"), "")

    def test_round_trip(self):
        chrome = os.environ.get("OMABAR_TEST_CHROMIUM") or shutil.which("chromium") or shutil.which("google-chrome")
        if not chrome:
            self.skipTest("no Chromium (set OMABAR_TEST_CHROMIUM to one)")
        import http.server
        import threading

        class Page(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                if self.path.startswith("/ListAccounts"):
                    body = b'["gaia.l.a.r",[["gaia.l.a",1,"Me","me@gmail.com","",1]]]'
                else:
                    body = (b"<script>setTimeout(function(){document.cookie="
                            b"'oauth_token=oauth2_4/test; path=/'},1500)</script>")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

        server = http.server.HTTPServer(("127.0.0.1", 0), Page)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        helper = self.helper
        old = (helper.SETUP_URL, os.environ.get("OMABAR_KEEP_BROWSER"), os.environ.get("OMABAR_KEEP_BROWSER_FLAGS"))
        helper.SETUP_URL = f"http://127.0.0.1:{server.server_port}/EmbeddedSetup"
        os.environ["OMABAR_KEEP_BROWSER"] = chrome
        os.environ["OMABAR_KEEP_BROWSER_FLAGS"] = "--headless=new --no-sandbox"
        try:
            code, email, why = helper.browser_signin(say=lambda *_: None, timeout=60)
        finally:
            helper.SETUP_URL = old[0]
            for name, value in zip(("OMABAR_KEEP_BROWSER", "OMABAR_KEEP_BROWSER_FLAGS"), old[1:]):
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value
        self.assertEqual((code, email, why), ("oauth2_4/test", "me@gmail.com", ""))


if __name__ == "__main__":
    unittest.main()
