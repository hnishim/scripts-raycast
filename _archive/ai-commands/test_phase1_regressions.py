import os
import pathlib
import subprocess
import tempfile
import unittest

import sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gemini_client


ROOT = pathlib.Path(__file__).parents[1]


class Phase1RegressionTests(unittest.TestCase):
    def test_safety_finish_reason_without_content_is_safety_error(self):
        with self.assertRaisesRegex(gemini_client.GeminiError, "安全性"):
            gemini_client.response_text({"candidates": [{"finishReason": "SAFETY"}]})

    def test_stdin_missing_python_is_safe_dependency_error_and_cleans_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            controlled = temp / "runner-temp"
            mktemp = fake_bin / "mktemp"
            mktemp.write_text("#!/bin/sh\nmkdir -p \"$CONTROLLED\"\nprintf '%s\\n' \"$CONTROLLED\"\n")
            mktemp.chmod(0o755)
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                   "CONTROLLED": str(controlled), "GEMINI_RUNNER_PYTHON": str(temp / "missing-python")}
            result = subprocess.run(
                [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
                 "--model", "model", "--output", "display", "--input-source", "stdin"],
                input="input", text=True, capture_output=True, env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"依存|Python|実行")
            self.assertFalse(controlled.exists())

    def test_selection_missing_pbpaste_is_safe_dependency_error_and_cleans_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            controlled = temp / "runner-temp"
            state = temp / "clipboard"
            state.write_text("ORIGINAL")
            mktemp = fake_bin / "mktemp"
            mktemp.write_text("#!/bin/sh\nmkdir -p \"$CONTROLLED\"\nprintf '%s\\n' \"$CONTROLLED\"\n")
            mktemp.chmod(0o755)
            helper = temp / "helper"
            helper.write_text("#!/bin/sh\nexit 0\n")
            helper.chmod(0o755)
            copy = fake_bin / "pbcopy"
            copy.write_text("#!/bin/sh\ncat > \"$STATE\"\n")
            copy.chmod(0o755)
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                   "CONTROLLED": str(controlled), "STATE": str(state),
                   "GEMINI_RUNNER_PASTEBOARD_COMMAND": str(helper),
                   "GEMINI_RUNNER_PBPASTE": str(temp / "missing-pbpaste"),
                   "GEMINI_RUNNER_PBCOPY": str(copy)}
            result = subprocess.run(
                [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
                 "--model", "model", "--output", "display", "--input-source", "selection"],
                text=True, capture_output=True, env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"[ぁ-んァ-ン一-龥]")
            self.assertEqual(state.read_text(), "ORIGINAL")
            self.assertFalse(controlled.exists())

    def test_runner_python_rejects_invalid_utf8_without_traceback_or_path(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            input_file = temp / "input"
            input_file.write_bytes(b"\xff")
            prompt = temp / "prompt.md"
            prompt.write_text("prompt")
            result = subprocess.run(
                ["/usr/bin/python3", str(ROOT / "ai-commands" / "gemini_runner.py"),
                 str(prompt), "model", "stdin", str(temp)],
                text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("読み込めません", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertNotIn(str(input_file), result.stderr)

    def _selection_error_fixture(self, temp, mode):
        fake_bin = temp / "bin"
        fake_bin.mkdir()
        controlled = temp / "runner-temp"
        state = temp / "clipboard"
        state.write_text("ORIGINAL")
        mktemp = fake_bin / "mktemp"
        mktemp.write_text("#!/bin/sh\nmkdir -p \"$CONTROLLED\"\nprintf '%s\\n' \"$CONTROLLED\"\n")
        mktemp.chmod(0o755)
        (fake_bin / "pbpaste").write_text(
            "#!/bin/sh\n[ \"$FAIL_MODE\" = pbpaste ] && exit 1\ncat \"$STATE\"\n"
        )
        (fake_bin / "pbcopy").write_text(
            "#!/bin/sh\nif [ \"$FAIL_MODE\" = display-write ] && [ -f \"$COPY_COUNT\" ]; then exit 1; fi\n[ \"$FAIL_MODE\" = display-write ] && touch \"$COPY_COUNT\"\ncat > \"$STATE\"\n"
        )
        (fake_bin / "osascript").write_text(
            "#!/bin/sh\nif echo \"$*\" | grep -q 'get name'; then [ \"$FAIL_MODE\" = frontmost ] && exit 1; echo App; elif echo \"$*\" | grep -q 'keystroke \\\"c\\\"'; then [ \"$FAIL_MODE\" = copy ] && exit 1; printf SELECTED > \"$STATE\"; elif [ \"$1\" = - ] && [ \"$FAIL_MODE\" = activation ]; then exit 1; fi\nexit 0\n"
        )
        (fake_bin / "sleep").write_text("#!/bin/sh\nexit 0\n")
        for name in ("pbpaste", "pbcopy", "osascript", "sleep"):
            (fake_bin / name).chmod(0o755)
        helper = temp / "helper"
        helper.write_text("#!/bin/sh\nif [ \"$2\" = restore ]; then printf ORIGINAL > \"$STATE\"; else mkdir -p \"$3\"; touch \"$3/manifest.json\"; fi\n")
        helper.chmod(0o755)
        python = temp / "python"
        python.write_text("#!/bin/sh\nprintf response > \"$5/response\"\n")
        python.chmod(0o755)
        env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
               "CONTROLLED": str(controlled), "STATE": str(state), "FAIL_MODE": mode,
               "COPY_COUNT": str(temp / "copy-count"), "GEMINI_RUNNER_PYTHON": str(python),
               "GEMINI_RUNNER_PASTEBOARD_COMMAND": str(helper),
               "GEMINI_RUNNER_PBPASTE": str(fake_bin / "pbpaste"),
               "GEMINI_RUNNER_PBCOPY": str(fake_bin / "pbcopy"),
               "GEMINI_RUNNER_OSASCRIPT": str(fake_bin / "osascript"),
               "GEMINI_RUNNER_SLEEP": str(fake_bin / "sleep")}
        return env, controlled, state

    def test_runner_selection_frontmost_copy_pbpaste_activation_and_display_write_failures(self):
        cases = (("frontmost", "display"), ("copy", "display"), ("pbpaste", "display"),
                 ("activation", "replace-selection"), ("display-write", "display-copy"))
        for mode, output in cases:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                temp = pathlib.Path(directory)
                env, controlled, state = self._selection_error_fixture(temp, mode)
                prompt = temp / "prompt.md"
                prompt.write_text("{selection}")
                result = subprocess.run(
                    [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
                     "--model", "model", "--output", output, "--input-source", "selection"],
                    text=True, capture_output=True, env=env,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertRegex(result.stderr, r"[ぁ-んァ-ン一-龥]")
                self.assertEqual(state.read_text(), "ORIGINAL")
                self.assertFalse(controlled.exists())

    def test_runner_cleanup_failure_is_diagnosed_and_nonzero(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            controlled = temp / "runner-temp"
            (fake_bin / "mktemp").write_text("#!/bin/sh\nmkdir -p \"$CONTROLLED\"\nprintf '%s\\n' \"$CONTROLLED\"\n")
            (fake_bin / "rm").write_text("#!/bin/sh\nexit 1\n")
            for name in ("mktemp", "rm"):
                (fake_bin / name).chmod(0o755)
            python = temp / "python"
            python.write_text("#!/bin/sh\nprintf response > \"$5/response\"\n")
            python.chmod(0o755)
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                   "CONTROLLED": str(controlled), "GEMINI_RUNNER_PYTHON": str(python),
                   "GEMINI_RUNNER_RM": str(fake_bin / "rm")}
            result = subprocess.run(
                [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
                 "--model", "model", "--output", "display", "--input-source", "stdin"],
                input="input", text=True, capture_output=True, env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("一時ファイル", result.stderr)
            self.assertTrue(controlled.exists())


if __name__ == "__main__":
    unittest.main()
