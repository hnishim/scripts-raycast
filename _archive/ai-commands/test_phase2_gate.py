"""Tests for abnormal termination and persistence documentation.

These tests deliberately exercise the public runner contract through command
doubles.  The signal cases are expected to fail until the runner terminates
and reaps an in-flight child as part of its cleanup contract.
"""

import os
import pathlib
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = pathlib.Path(__file__).parents[1]
RUNNER = ROOT / "ai-commands" / "gemini_runner.sh"
README = ROOT / "README.md"


def _write_executable(path: pathlib.Path, body: str) -> None:
    path.write_text(body)
    path.chmod(0o755)


class Phase2GateTests(unittest.TestCase):
    def test_readme_does_not_contain_known_stale_persistence_statement(self):
        """Guard only the specific stale sentence; prose meaning is manual-review scope."""
        self.assertNotIn(
            "入力・プロンプト・応答はローカル保存やログ出力を行いません。",
            README.read_text(),
        )

    def _selection_signal_fixture(self, temp: pathlib.Path):
        fake_bin = temp / "bin"
        fake_bin.mkdir()
        state = temp / "clipboard"
        state.write_text("ORIGINAL")
        controlled = temp / "runner-temp"
        restore_count = temp / "restore-count"
        child_pid = temp / "child.pid"
        child_terminated = temp / "child-terminated"
        events = temp / "events.log"
        _write_executable(
            fake_bin / "mktemp",
            '#!/bin/sh\nmkdir -p "$FAKE_RUNNER_TEMP"\nprintf "%s\\n" "$FAKE_RUNNER_TEMP"\n',
        )
        _write_executable(fake_bin / "pbpaste", '#!/bin/sh\ncat "$STATE"\n')
        _write_executable(fake_bin / "pbcopy", '#!/bin/sh\ncat > "$STATE"\n')
        _write_executable(
            fake_bin / "osascript",
            '#!/bin/sh\n'
            'case "$*" in\n'
            '  *"get name"*) echo TextEdit ;;\n'
            '  *"keystroke \\"c\\""*) printf SELECTED > "$STATE" ;;\n'
            'esac\n',
        )
        _write_executable(fake_bin / "sleep", '#!/bin/sh\nexit 0\n')
        helper = temp / "pasteboard-helper"
        _write_executable(
            helper,
            '#!/bin/sh\n'
            'if [ "$2" = snapshot ]; then\n'
            '  mkdir -p "$3"\n'
            '  cat "$STATE" > "$3/content"\n'
            '  printf "snapshot=%s\\n" "$3" > "$3/manifest.json"\n'
            '  exit 0\n'
            'fi\n'
            '[ -f "$3/manifest.json" ] && [ -f "$3/content" ] || exit 41\n'
            'grep -F "snapshot=$3" "$3/manifest.json" >/dev/null || exit 42\n'
            '[ -f "$CHILD_TERMINATED" ] || exit 43\n'
            'child_pid=$(cat "$CHILD_PID_FILE" 2>/dev/null) || exit 44\n'
            'case "$child_pid" in ""|*[!0-9]*) exit 45 ;; esac\n'
            'if /bin/kill -0 "$child_pid" 2>/dev/null; then exit 46; fi\n'
            'count=0; [ -f "$RESTORE_COUNT" ] && count=$(cat "$RESTORE_COUNT")\n'
            'count=$((count + 1)); printf "%s" "$count" > "$RESTORE_COUNT"\n'
            'printf "restore\\n" >> "$EVENTS"\n'
            'cat "$3/content" > "$STATE"\n',
        )
        _write_executable(
            fake_bin / "rm",
            '#!/bin/sh\nprintf "rm\\n" >> "$EVENTS"\nexec /bin/rm "$@"\n',
        )
        fake_python = temp / "python"
        _write_executable(
            fake_python,
            '#!/bin/sh\n'
            'trap "printf terminated > \\"$CHILD_TERMINATED\\"; printf \\"child-terminated\\n\\" >> \\"$EVENTS\\"; exit 143" INT HUP TERM\n'
            'printf "%s" "$$" > "$CHILD_PID_FILE"\n'
            'printf "ready\\n" >> "$EVENTS"\n'
            'while :; do sleep 1; done\n',
        )
        prompt = temp / "prompt.md"
        prompt.write_text("{selection}")
        env = {
            **os.environ,
            "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
            "STATE": str(state),
            "FAKE_RUNNER_TEMP": str(controlled),
            "RESTORE_COUNT": str(restore_count),
            "CHILD_PID_FILE": str(child_pid),
            "CHILD_TERMINATED": str(child_terminated),
            "EVENTS": str(events),
            "GEMINI_RUNNER_PYTHON": str(fake_python),
            "GEMINI_RUNNER_PASTEBOARD_COMMAND": str(helper),
            "GEMINI_RUNNER_PBPASTE": str(fake_bin / "pbpaste"),
            "GEMINI_RUNNER_PBCOPY": str(fake_bin / "pbcopy"),
            "GEMINI_RUNNER_OSASCRIPT": str(fake_bin / "osascript"),
            "GEMINI_RUNNER_SLEEP": str(fake_bin / "sleep"),
            "GEMINI_RUNNER_RM": str(fake_bin / "rm"),
        }
        return env, prompt, state, controlled, restore_count, child_pid, child_terminated, events

    def _assert_signal_cleanup(self, signum):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, prompt, state, controlled, restore_count, child_pid, child_terminated, events = self._selection_signal_fixture(temp)
            process = subprocess.Popen(
                [str(RUNNER), "--prompt-file", str(prompt), "--model", "model",
                 "--output", "display", "--input-source", "selection"],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, env=env, start_new_session=True,
            )
            deadline = time.monotonic() + 3
            while (not child_pid.exists() or not events.exists() or "ready" not in events.read_text()) and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(child_pid.exists(), "controlled child did not start")
            self.assertIn("ready", events.read_text(), "child published readiness before installing traps")
            os.kill(process.pid, signum)
            try:
                stdout, stderr = process.communicate(timeout=3)
            except subprocess.TimeoutExpired as exc:
                # Keep an intentionally failing test from leaking its controlled
                # child into subsequent signal cases.
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate()
                self.fail(f"runner did not finish after {signum.name}: {exc}; stderr={stderr!r}")
            self.assertIn(process.returncode, (-signum, 128 + signum), stderr)
            self.assertEqual(state.read_text(), "ORIGINAL")
            self.assertEqual(restore_count.read_text(), "1")
            self.assertTrue(child_terminated.exists(), "in-flight child was not terminated/reaped")
            self.assertFalse(controlled.exists(), "temporary directory remains after signal")
            event_lines = events.read_text().splitlines()
            self.assertEqual(event_lines.count("restore"), 1)
            self.assertEqual(event_lines.count("rm"), 1)
            self.assertLess(event_lines.index("child-terminated"), event_lines.index("restore"))
            self.assertLess(event_lines.index("restore"), event_lines.index("rm"))
            self.assertEqual(stdout, "")

    def test_int_restores_clipboard_reaps_child_and_cleans_once(self):
        self._assert_signal_cleanup(signal.SIGINT)

    def test_hup_restores_clipboard_reaps_child_and_cleans_once(self):
        self._assert_signal_cleanup(signal.SIGHUP)

    def test_term_restores_clipboard_reaps_child_and_cleans_once(self):
        self._assert_signal_cleanup(signal.SIGTERM)

if __name__ == "__main__":
    unittest.main()
