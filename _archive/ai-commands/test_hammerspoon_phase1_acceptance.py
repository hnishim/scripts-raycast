"""HIR-67 minimal test-only gate for the Hammerspoon command contract."""

import pathlib
import subprocess
import unittest


HAMMERSPOON = pathlib.Path(
    "/Users/hnishim/Library/Mobile Documents/com~apple~CloudDocs/Dev/scripts/hammerspoon"
)
FIXTURE = pathlib.Path(__file__).with_name("hammerspoon_phase1_harness.lua")
LUA = pathlib.Path("/opt/homebrew/bin/lua")
CLASSIFICATION = {}


def fail_unexpected(scenario, message):
    CLASSIFICATION[scenario] = "UNEXPECTED_FAIL"
    raise AssertionError(message)


def run_scenario(scenario):
    try:
        result = subprocess.run(
            [str(LUA), str(FIXTURE), scenario, str(HAMMERSPOON / "ai_command.lua"),
             str(HAMMERSPOON / "init.lua")],
            text=True, capture_output=True, timeout=12,
        )
    except Exception as exc:
        fail_unexpected(scenario, "standalone Lua invocation failed: %s" % exc)

    output = result.stdout + result.stderr
    if "HIR67_FIXTURE_TEARDOWN PASS" not in output:
        fail_unexpected(scenario, "fixture teardown did not pass:\n%s" % output)

    expected = [line for line in output.splitlines() if line.startswith("HIR67_EXPECTED_LEGACY ")]
    unexpected = [line for line in output.splitlines() if line.startswith("HIR67_UNEXPECTED_FAIL ")]
    marker = "HIR67_HARNESS_PASS " + scenario
    if unexpected:
        fail_unexpected(scenario, "unexpected harness findings:\n%s" % "\n".join(unexpected))
    if expected:
        if result.returncode == 0 or marker in output:
            fail_unexpected(scenario, "legacy findings were reported as a successful harness run:\n%s" %
                            "\n".join(expected))
        CLASSIFICATION[scenario] = "EXPECTED_FAIL"
        print("EXPECTED_FAIL %s: %s" % (scenario, "; ".join(expected)))
        return
    if result.returncode != 0:
        fail_unexpected(scenario, "standalone Lua harness failed (rc=%s):\n%s" %
                        (result.returncode, output))
    if marker not in output:
        fail_unexpected(scenario, "missing PASS marker %s:\n%s" % (marker, output))
    CLASSIFICATION[scenario] = "PASS"
    print("PASS %s" % scenario)


class HammerspoonPhase1AcceptanceTests(unittest.TestCase):
    def test_registration_and_legacy_cleanup(self):
        run_scenario("registration_and_legacy_cleanup")
        legacy_prompt = (HAMMERSPOON / "prompts" / "translate-to-korean.txt").exists()
        if legacy_prompt:
            if CLASSIFICATION.get("registration_and_legacy_cleanup") == "EXPECTED_FAIL":
                print("EXPECTED_FAIL registration_and_legacy_cleanup: legacy translate prompt remains")
            else:
                fail_unexpected("registration_and_legacy_cleanup",
                                "legacy translate prompt remains after a non-legacy result")

    def test_runner_contract(self):
        run_scenario("runner_contract")

    @classmethod
    def tearDownClass(cls):
        counts = {name: sum(value == name for value in CLASSIFICATION.values())
                  for name in ("EXPECTED_FAIL", "UNEXPECTED_FAIL", "PASS")}
        print("HIR67_CLASSIFICATION EXPECTED_FAIL=%d UNEXPECTED_FAIL=%d PASS=%d" %
              (counts["EXPECTED_FAIL"], counts["UNEXPECTED_FAIL"], counts["PASS"]))


if __name__ == "__main__":
    unittest.main()
