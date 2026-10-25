"""Exercise Lua behavior and preserve the original device-tested player's identity."""

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("bundle", ROOT / "tools/bundle.py")
BUNDLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLER)


class PlayerTests(unittest.TestCase):
    def test_original_fixture_hash(self):
        source = (ROOT / "tests/fixtures/original-main.lua").read_bytes()
        self.assertEqual(hashlib.sha256(source).hexdigest(),
                         "129a339ac537f3f536f8d723805c2bc13d2a0902e65aa2d2e514d54d0db475cd")

    def test_bundler_rejects_missing_or_duplicate_import(self):
        for entry in ("", BUNDLER.IMPORT + "\n" + BUNDLER.IMPORT):
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                BUNDLER.bundle(entry, "return {}")

    def test_lua_runtime_and_bundled_entry(self):
        runtime = os.environ.get("LUA", "lua")
        self.assertIsNotNone(shutil.which(runtime), f"Lua runtime not found: {runtime}")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "main.lua"
            subprocess.run([sys.executable, str(ROOT / "tools/bundle.py"), "--output", str(output)],
                           check=True, capture_output=True, text=True)
            source = output.read_text(encoding="utf-8")
            self.assertNotIn(BUNDLER.IMPORT, source)
            result = subprocess.run([runtime, str(ROOT / "tests/runtime.lua"), str(ROOT), str(output)],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("13 runtime scenarios passed", result.stdout)
            print(result.stdout, end="")


if __name__ == "__main__":
    unittest.main(verbosity=2)
