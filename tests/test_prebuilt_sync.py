"""Checks that prebuilt/OmabarEngine.qml carries every edit in
tools/omabar-patch.py, so a patch change is never shipped without
rebuilding the fallback engine. From the repository root:

    python3 -m unittest discover -s tests
"""
import importlib.util
import os
import sys
import unittest

ROOT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..")


def load_patch_tool():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("omabar_patch", os.path.join(ROOT, "tools", "omabar-patch.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrebuiltSyncTest(unittest.TestCase):
    def test_every_patch_is_in_the_prebuilt_engine(self):
        patches = load_patch_tool().PATCHES
        with open(os.path.join(ROOT, "prebuilt", "OmabarEngine.qml")) as handle:
            engine = handle.read()
        self.assertTrue(patches)
        for patch in patches:
            name, replacement = patch[0], patch[2]
            with self.subTest(patch=name):
                self.assertIn(replacement, engine)


if __name__ == "__main__":
    unittest.main()
