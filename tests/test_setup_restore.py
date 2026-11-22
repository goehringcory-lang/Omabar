"""Checks that bin/omabar-setup --restore and --uninstall put back only the
bar and leave the rest of shell.json and other backups alone. They run the
real script against a throwaway home with stand-ins for the omarchy
commands. From the repository root:

    python3 -m unittest discover -s tests
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..")
SETUP = os.path.join(ROOT, "bin", "omabar-setup")
PLUGIN_ID = "goehringcory.omabar"
CLONE_ID = "omarchy.elsewhen-copy"

# `omarchy plugin remove <id>` the way Omarchy does it for a clone: move the
# folder to a dated backup. Everything else the scripts call does nothing.
FAKE_OMARCHY = """#!/bin/bash
echo "$*" >>"$HOME/omarchy-calls"
if [[ $1 == plugin && $2 == remove ]]; then
  dir="$HOME/.config/omarchy/plugins/$3"
  [[ -d $dir ]] && mv "$dir" "$HOME/.config/omarchy/plugins/.$3.bak.20261122-999999"
fi
exit 0
"""


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class SetupRestoreTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home)
        self.config_dir = os.path.join(self.home, ".config", "omarchy")
        self.plugins = os.path.join(self.config_dir, "plugins")
        os.makedirs(self.plugins)
        self.bin = os.path.join(self.home, "fakebin")
        os.makedirs(self.bin)
        for name, body in (("omarchy", FAKE_OMARCHY), ("omarchy-shell", "#!/bin/bash\nexit 0\n")):
            path = os.path.join(self.bin, name)
            with open(path, "w") as handle:
                handle.write(body)
            os.chmod(path, 0o755)
        self.config = os.path.join(self.config_dir, "shell.json")
        self.backup = self.config + ".before-omabar"

    def write(self, path, data):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            json.dump(data, handle)

    def read(self, path):
        with open(path) as handle:
            return json.load(handle)

    def run_setup(self, *args, script=SETUP):
        env = dict(os.environ, HOME=self.home, PATH=self.bin + os.pathsep + os.environ["PATH"],
                   XDG_CONFIG_HOME=os.path.join(self.home, ".config"),
                   XDG_CACHE_HOME=os.path.join(self.home, ".cache"))
        return subprocess.run([script, *args], env=env, capture_output=True, text=True, timeout=30)

    def omabar_config(self, **extra):
        return {"version": 1, "bar": {"id": PLUGIN_ID, "layout": {"left": [{"id": "omabar-menu"}]}}, **extra}

    def test_restore_keeps_settings_changed_after_setup(self):
        self.write(self.backup, {"bar": {"id": "omarchy.bar", "position": "bottom"}, "theme": "old"})
        self.write(self.config, self.omabar_config(theme="new", notifications={"dnd": True}))
        result = self.run_setup("--restore")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read(self.config), {"version": 1, "bar": {"id": "omarchy.bar", "position": "bottom"},
                                                  "theme": "new", "notifications": {"dnd": True}})
        self.assertFalse(os.path.exists(self.backup))

    def test_restore_leaves_a_bar_you_picked_yourself(self):
        mine = {"bar": {"id": "someone.else"}, "theme": "new"}
        self.write(self.backup, {"bar": {"id": "omarchy.bar"}})
        self.write(self.config, mine)
        self.assertEqual(self.run_setup("--restore").returncode, 0)
        self.assertEqual(self.read(self.config), mine)

    def test_restore_without_a_bar_in_the_backup_uses_the_default_bar(self):
        self.write(self.backup, {"theme": "old"})
        self.write(self.config, self.omabar_config(theme="new"))
        self.assertEqual(self.run_setup("--restore").returncode, 0)
        self.assertEqual(self.read(self.config), {"version": 1, "theme": "new"})

    def test_unreadable_backup_changes_nothing(self):
        with open(self.backup, "w") as handle:
            handle.write("{ not json")
        live = self.omabar_config(theme="new")
        self.write(self.config, live)
        self.assertNotEqual(self.run_setup("--restore").returncode, 0)
        self.assertEqual(self.read(self.config), live)

    def test_uninstall_drops_only_the_world_clock_backup_it_made(self):
        self.write(os.path.join(self.plugins, CLONE_ID, "manifest.json"),
                   {"id": CLONE_ID, "omarchy": {"clonedFrom": "omarchy.elsewhen"}})
        older = os.path.join(self.plugins, f".{CLONE_ID}.bak.20260101-000000")
        os.makedirs(older)
        os.makedirs(os.path.join(self.home, ".config", "omabar"))
        with open(os.path.join(self.home, ".config", "omabar", "elsewhen-clone"), "w") as handle:
            handle.write(CLONE_ID + "\n")
        self.write(self.backup, {"bar": {"id": "omarchy.bar"}})
        self.write(self.config, self.omabar_config(theme="new"))
        result = self.run_setup("--uninstall")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.isdir(older), "an older backup Omabar didn't make was deleted")
        self.assertFalse(os.path.exists(os.path.join(self.plugins, f".{CLONE_ID}.bak.20261122-999999")))
        self.assertEqual(self.read(self.config), {"version": 1, "bar": {"id": "omarchy.bar"}, "theme": "new"})

    def test_update_hook_keeps_later_settings_when_omabar_was_removed(self):
        # Write the hook the way setup does by running the heredoc section alone.
        text = open(SETUP, encoding="utf-8").read()
        start = text.index('RESTORE_BAR_JQ=')
        jq_line = text[start:text.index("\n", start)]
        hook_start = text.index('cat >"$HOOK_FILE" <<HOOK')
        hook_end = text.index("\nHOOK\n", hook_start) + len("\nHOOK\n")
        hook_file = os.path.join(self.home, "hook")
        maker = os.path.join(self.home, "make-hook")
        with open(maker, "w") as handle:
            handle.write(f'#!/bin/bash\nPLUGIN_ID="{PLUGIN_ID}"\nHOOK_FILE="{hook_file}"\n{jq_line}\n'
                         + text[hook_start:hook_end])
        os.chmod(maker, 0o755)
        self.assertEqual(self.run_setup(script=maker).returncode, 0)
        os.chmod(hook_file, 0o755)
        self.write(self.backup, {"bar": {"id": "omarchy.bar"}})
        self.write(self.config, self.omabar_config(theme="new"))
        result = self.run_setup(script=hook_file)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read(self.config), {"version": 1, "bar": {"id": "omarchy.bar"}, "theme": "new"})
        self.assertFalse(os.path.exists(hook_file))


if __name__ == "__main__":
    unittest.main()
