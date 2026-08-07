import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPILER_PATH = ROOT / "compiler" / "odrl_compiler.py"
EXAMPLES = ROOT / "compiler" / "examples"

SPEC = importlib.util.spec_from_file_location("odrl_compiler", COMPILER_PATH)
COMPILER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(COMPILER)


class CompilerTests(unittest.TestCase):
    def load(self, name):
        with (EXAMPLES / name).open(encoding="utf-8") as handle:
            return json.load(handle)

    def test_entitlement_matches_reference(self):
        policy = self.load("User_Group1.json")
        actual = COMPILER.compile_entitlement(policy, "hardware")
        self.assertEqual(actual, self.load("User_Group1.onchain.json"))

    def test_asset_policy_matches_reference(self):
        policy = self.load("H9_Policy.json")
        actual = COMPILER.compile_asset_policy(
            policy,
            "hardware",
            "ipfs://replace-with-real-cid",
            0,
            0,
        )
        self.assertEqual(actual, self.load("H9_Policy.onchain.json"))

    def test_object_key_order_does_not_change_hash(self):
        first = {"b": 2, "a": 1}
        second = {"a": 1, "b": 2}
        self.assertEqual(
            COMPILER.canonical_json_bytes(first),
            COMPILER.canonical_json_bytes(second),
        )

    def test_unknown_action_is_rejected(self):
        with self.assertRaises(COMPILER.PolicyCompileError):
            COMPILER.parse_action("unsupported-action")

    def test_cli_writes_requested_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "compiled.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(COMPILER_PATH),
                    str(EXAMPLES / "User_Group1.json"),
                    "--kind",
                    "entitlement",
                    "--asset-type",
                    "hardware",
                    "--output",
                    str(output),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                json.loads(output.read_text(encoding="utf-8")),
                self.load("User_Group1.onchain.json"),
            )


if __name__ == "__main__":
    unittest.main()
