"""Checks that bin/omabar-setup --help lists every option and that --doctor
prints every section even when the shell log has nothing to match (grep
finding nothing used to stop it halfway). Runs the real script against a
throwaway home with stand-ins for the omarchy commands. From the repository
root:

    python3 -m unittest discover -s tests
"""
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), ".."))
SETUP = os.path.join(ROOT, "bin", "omabar-setup")
PLUGIN_ID = "goehringcory.omabar"

STANDINS = {
    "omarchy": "#!/bin/bash\necho '[]'\nexit 0\n",
    "omarchy-shell": "#!/bin/bash\nexit 0\n",
    # A log with nothing about Omabar in it.
    "journalctl": "#!/bin/bash\necho 'unrelated line'\n",
}


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class SetupDoctorTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home)
        plugins = os.path.join(self.home, ".config", "omarchy", "plugins")
        os.makedirs(plugins)
        os.symlink(ROOT, os.path.join(plugins, PLUGIN_ID))
        with open(os.path.join(self.home, ".config", "omarchy", "shell.json"), "w") as handle:
            handle.write('{"bar": {"id": "%s", "layout": {"left": [{"id": "omabar-menu"}]}}}' % PLUGIN_ID)
        self.bin = os.path.join(self.home, "fakebin")
        os.makedirs(self.bin)
        for name, body in STANDINS.items():
            path = os.path.join(self.bin, name)
            with open(path, "w") as handle:
                handle.write(body)
            os.chmod(path, 0o755)

    def run_setup(self, *args):
        env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"],
                   XDG_CONFIG_HOME=os.path.join(self.home, ".config"),
                   XDG_CACHE_HOME=os.path.join(self.home, ".cache"),
                   OMARCHY_PATH=os.path.join(self.home, "no-omarchy"))
        return subprocess.run([SETUP, *args], env=env, capture_output=True, text=True, timeout=60)

    def test_help_lists_every_option(self):
        result = self.run_setup("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in ("--restore", "--uninstall", "--rebuild", "--doctor", "--world-clock"):
            self.assertIn(option, result.stdout)

    def test_doctor_reaches_the_end(self):
        result = self.run_setup("--doctor")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for section in ("== Omarchy", "== Omabar", "== shell.json", "== world clock",
                        "== helpers", "== plugins", "== shell log"):
            self.assertIn(section, result.stdout)


if __name__ == "__main__":
    unittest.main()
