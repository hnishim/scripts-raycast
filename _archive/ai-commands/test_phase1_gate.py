import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gemini_client


ROOT = pathlib.Path(__file__).parents[1]


class Phase1GateTests(unittest.TestCase):
    def test_wrappers_use_required_prompt_model_and_output_contract(self):
        expected = {
            "ai-review-text.sh": ("review-text_compact.md", "display-copy"),
            "ai-translate.sh": ("translate.md", "display-copy"),
            "ai-bio-expert.sh": ("bio-ai_expert.md", "display"),
        }
        for filename, (prompt, output) in expected.items():
            source = (ROOT / filename).read_text()
            self.assertRegex(source, r"--model [A-Za-z0-9._-]+")
            self.assertIn("PROMPT=", source)
            self.assertIn(prompt, source)
            argument_line = next(line for line in source.splitlines() if "@raycast.argument1" in line)
            self.assertTrue(json.loads(argument_line.split(" ", 2)[2])["optional"])
            branches = re.search(r"if \[ -n .*? then (.*?) else (.*?) fi", source, re.DOTALL)
            self.assertIsNotNone(branches)
            stdin_branch, selection_branch = branches.groups()
            for branch, input_source in ((stdin_branch, "stdin"), (selection_branch, "selection")):
                self.assertIn('ai-commands/gemini_runner.sh', branch)
                self.assertIn("--model ", branch)
                self.assertIn("--output " + output, branch)
                self.assertIn("--input-source " + input_source, branch)
            self.assertIn('printf \'%s\' "$1" | exec', stdin_branch)
            self.assertIn('exec "$DIR/ai-commands/gemini_runner.sh"', selection_branch)

    def test_wrappers_execute_against_shared_runner_double_for_both_branches(self):
        expected = {
            "ai-review-text.sh": ("review-text_compact.md", "display-copy"),
            "ai-translate.sh": ("translate.md", "display-copy"),
            "ai-bio-expert.sh": ("bio-ai_expert.md", "display"),
        }
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            scripts = temp / "scripts" / "raycast"
            runner_dir = scripts / "ai-commands"
            runner_dir.mkdir(parents=True)
            prompt_dir = temp / "prompts" / "raycast" / "ai-commands"
            prompt_dir.mkdir(parents=True)
            capture = temp / "capture"
            input_capture = temp / "input"
            fake_runner = runner_dir / "gemini_runner.sh"
            fake_runner.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CAPTURE\"\ncat > \"$INPUT_CAPTURE\"\nprintf runner-ok\n"
            )
            fake_runner.chmod(0o755)
            env = {**os.environ, "CAPTURE": str(capture), "INPUT_CAPTURE": str(input_capture)}
            for filename, (prompt_name, output) in expected.items():
                wrapper = scripts / filename
                shutil.copy2(ROOT / filename, wrapper)
                prompt = prompt_dir / prompt_name
                prompt.write_text("fixture")
                for argument, expected_input in (("argument-value", "argument-value"), (None, "")):
                    result = subprocess.run(
                        [str(wrapper)] + ([] if argument is None else [argument]),
                        input="", text=True, capture_output=True, env=env,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    values = capture.read_text().splitlines()
                    self.assertEqual(values[values.index("--prompt-file") + 1], str(prompt))
                    self.assertRegex(values[values.index("--model") + 1], r"^[A-Za-z0-9._-]+$")
                    self.assertEqual(values[values.index("--output") + 1], output)
                    self.assertEqual(values[values.index("--input-source") + 1], "stdin" if argument else "selection")
                    self.assertEqual(input_capture.read_text(), expected_input)

    def test_key_registration_script_contract_without_invoking_keychain(self):
        source = (ROOT / "ai-commands" / "register-gemini-key.sh").read_text()
        self.assertIn("read -r -s", source)
        self.assertIn("printf '%s' \"$GEMINI_API_KEY\" | /usr/bin/security add-generic-password -U", source)
        self.assertIn("-s com.hnishim.raycast-gemini", source)
        self.assertIn("-a \"$ACCOUNT\" -w", source)
        self.assertIn("[ ! -t 0 ]", source)
        self.assertNotRegex(source, r"security .*\$1|security .*\$2")

    def test_prompt_files_exist_at_wrapper_targets(self):
        prompt_root = ROOT.parent.parent / "prompts" / "raycast" / "ai-commands"
        for filename in ("review-text_compact.md", "translate.md", "bio-ai_expert.md"):
            self.assertTrue((prompt_root / filename).is_file(), filename)

    def test_keychain_lookup_uses_current_user_and_never_exposes_missing_key(self):
        calls = []

        def check_output(command, **kwargs):
            calls.append(command)
            return "current-user\n" if len(calls) == 1 else "secret-key\n"

        with patch.object(gemini_client.subprocess, "check_output", side_effect=check_output):
            self.assertEqual(gemini_client.keychain_key(), "secret-key")
        self.assertEqual(calls[0], ["/usr/bin/id", "-un"])
        self.assertEqual(calls[1], ["/usr/bin/security", "find-generic-password", "-s",
                                    "com.hnishim.raycast-gemini", "-a", "current-user", "-w"])

    def test_keychain_missing_is_safe(self):
        with patch.object(gemini_client.subprocess, "check_output", side_effect=subprocess.CalledProcessError(44, "security")):
            with self.assertRaisesRegex(gemini_client.GeminiError, "Keychain") as raised:
                gemini_client.keychain_key()
        self.assertNotIn("security", str(raised.exception))

    def test_timeout_and_http_errors_are_normalized_without_secret(self):
        with patch.object(gemini_client, "keychain_key", return_value="TOP_SECRET"):
            with self.assertRaisesRegex(gemini_client.GeminiError, "タイムアウト") as raised:
                gemini_client.generate_content("入力", "model", opener=lambda *args, **kwargs: (_ for _ in ()).throw(TimeoutError()))
        self.assertNotIn("TOP_SECRET", str(raised.exception))

        def http_error(*args, **kwargs):
            raise urllib.error.HTTPError("url", 400, "bad", {}, None)

        with patch.object(gemini_client, "keychain_key", return_value="TOP_SECRET"):
            with self.assertRaisesRegex(gemini_client.GeminiError, "HTTP 400"):
                gemini_client.generate_content("入力", "model", opener=http_error)

    def test_generate_content_uses_google_endpoint_and_api_key_header(self):
        observed = {}

        class OkResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return b'{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}'

        def opener(request, timeout):
            observed["url"] = request.full_url
            observed["key"] = request.get_header("X-goog-api-key")
            observed["body"] = json.loads(request.data.decode())
            return OkResponse()

        with patch.object(gemini_client, "keychain_key", return_value="TOP_SECRET"):
            self.assertEqual(gemini_client.generate_content("日本語", "gemini-test", opener=opener), "ok")
        self.assertEqual(observed["url"], "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent")
        self.assertEqual(observed["key"], "TOP_SECRET")
        self.assertEqual(observed["body"]["contents"][0]["parts"][0]["text"], "日本語")

    def test_prompt_files_render_without_unresolved_placeholders(self):
        prompt_root = ROOT.parent.parent / "prompts" / "raycast" / "ai-commands"
        for filename in ("review-text_compact.md", "translate.md", "bio-ai_expert.md"):
            rendered = gemini_client.render_prompt((prompt_root / filename).read_text(), "テスト入力")
            self.assertNotIn("{selection}", rendered)
            self.assertNotIn('{argument name="', rendered)

    def test_input_and_key_are_not_written_to_persistent_log_paths(self):
        source = "\n".join((ROOT / "ai-commands" / name).read_text() for name in ("gemini_client.py", "gemini_runner.py", "gemini_runner.sh"))
        for forbidden in ("logger", "tee", "print(prompt)", "print(key)", "echo \"$prompt\""):
            self.assertNotIn(forbidden, source)
        self.assertIn("mktemp", source)

    def test_runner_removes_temp_directory_on_success_and_client_failure(self):
        runner = ROOT / "ai-commands" / "gemini_runner.sh"
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            fake_root = temp / "fake-root"
            fake_root.mkdir()
            fake_mktemp = fake_root / "mktemp"
            controlled = temp / "runner-temp"
            fake_mktemp.write_text("#!/bin/sh\nmkdir -p \"$FAKE_RUNNER_TEMP\"\nprintf '%s\\n' \"$FAKE_RUNNER_TEMP\"\n")
            fake_mktemp.chmod(0o755)
            fake_python = temp / "python"
            fake_python.write_text("#!/bin/sh\n[ \"$FAKE_RUNNER_FAIL\" = yes ] && exit 1\nprintf response > \"$5/response\"\n")
            fake_python.chmod(0o755)
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            env = {**os.environ, "PATH": str(fake_root) + os.pathsep + os.environ["PATH"],
                   "FAKE_RUNNER_TEMP": str(controlled), "FAKE_RUNNER_FAIL": "no",
                   "GEMINI_RUNNER_PYTHON": str(fake_python)}

            def run():
                return subprocess.run(
                    [str(runner), "--prompt-file", str(prompt), "--model", "model",
                     "--output", "display", "--input-source", "stdin"],
                    input="input", text=True, capture_output=True, env=env,
                )

            self.assertEqual(run().returncode, 0)
            self.assertFalse(controlled.exists())
            env["FAKE_RUNNER_FAIL"] = "yes"
            self.assertEqual(run().returncode, 1)
            self.assertFalse(controlled.exists())

    def _runner_failure_fixture(self, temp, *, api_fail="no", copy_fail="no", paste_fail="no",
                                snapshot_fail="no", restore_fail="no", dependency=True):
        fake_root = temp / "fake-root"
        fake_root.mkdir()
        controlled = temp / "runner-temp"
        (fake_root / "mktemp").write_text(
            "#!/bin/sh\nmkdir -p \"$FAKE_RUNNER_TEMP\"\nprintf '%s\\n' \"$FAKE_RUNNER_TEMP\"\n"
        )
        (fake_root / "mktemp").chmod(0o755)
        fake_python = temp / "python"
        fake_python.write_text(
            "#!/bin/sh\n[ \"$FAKE_API_FAIL\" = yes ] && { echo API失敗 >&2; exit 1; }\nprintf response > \"$5/response\"\n"
        )
        fake_python.chmod(0o755)
        (fake_root / "pbpaste").write_text("#!/bin/sh\ncat \"$STATE\"\n")
        (fake_root / "pbcopy").write_text(
            "#!/bin/sh\n[ \"$FAKE_COPY_FAIL\" = yes ] && exit 1\ncat > \"$STATE\"\n"
        )
        (fake_root / "osascript").write_text(
            "#!/bin/sh\nif echo \"$*\" | grep -q 'get name'; then echo App; elif echo \"$*\" | grep -q 'keystroke \\\"c\\\"'; then printf SELECTED > \"$STATE\"; elif echo \"$*\" | grep -q 'keystroke \\\"v\\\"' && [ \"$FAKE_PASTE_FAIL\" = yes ]; then exit 1; fi\nexit 0\n"
        )
        (fake_root / "sleep").write_text("#!/bin/sh\nexit 0\n")
        for name in ("pbpaste", "pbcopy", "osascript", "sleep"):
            (fake_root / name).chmod(0o755)
        helper = temp / "pasteboard-helper"
        helper.write_text(
            "#!/bin/sh\nif [ \"$2\" = snapshot ]; then [ \"$FAKE_SNAPSHOT_FAIL\" = yes ] && exit 1; mkdir -p \"$3\"; touch \"$3/manifest.json\"; else touch \"$RESTORE_MARKER\"; [ \"$FAKE_RESTORE_FAIL\" = yes ] && exit 1; printf ORIGINAL > \"$STATE\"; fi\n"
        )
        helper.chmod(0o755)
        env = {**os.environ, "PATH": str(fake_root) + os.pathsep + os.environ["PATH"],
               "STATE": str(temp / "clipboard"), "FAKE_RUNNER_TEMP": str(controlled),
               "FAKE_API_FAIL": api_fail, "FAKE_COPY_FAIL": copy_fail, "FAKE_PASTE_FAIL": paste_fail,
               "FAKE_SNAPSHOT_FAIL": snapshot_fail, "FAKE_RESTORE_FAIL": restore_fail,
               "RESTORE_MARKER": str(temp / "restore-called"), "GEMINI_RUNNER_PYTHON": str(fake_python),
               "GEMINI_RUNNER_PASTEBOARD_COMMAND": str(helper),
               "GEMINI_RUNNER_PBPASTE": str(fake_root / "pbpaste"),
               "GEMINI_RUNNER_PBCOPY": str(fake_root / "pbcopy"),
               "GEMINI_RUNNER_OSASCRIPT": str(fake_root / "osascript"),
               "GEMINI_RUNNER_SLEEP": str(fake_root / "sleep")}
        if not dependency:
            env["GEMINI_RUNNER_PASTEBOARD_COMMAND"] = str(temp / "missing-helper")
        return env, controlled, pathlib.Path(env["STATE"]), pathlib.Path(env["RESTORE_MARKER"])

    def _run_selection_fixture(self, env, prompt, output="display-copy"):
        return subprocess.run(
            [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
             "--model", "model", "--output", output, "--input-source", "selection"],
            input="", text=True, capture_output=True, env=env,
        )

    def test_runner_api_failure_restores_clipboard_and_cleans_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, controlled, state, _ = self._runner_failure_fixture(temp, api_fail="yes")
            state.write_text("ORIGINAL")
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            result = self._run_selection_fixture(env, prompt)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("API失敗", result.stderr)
            self.assertEqual(state.read_text(), "ORIGINAL")
            self.assertFalse(controlled.exists())

    def test_runner_copy_failure_is_independent_and_restores_clipboard(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, controlled, state, _ = self._runner_failure_fixture(temp, copy_fail="yes")
            state.write_text("ORIGINAL")
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            result = self._run_selection_fixture(env, prompt)
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"[ぁ-んァ-ン一-龥]")
            self.assertEqual(state.read_text(), "ORIGINAL")
            self.assertFalse(controlled.exists())

    def test_runner_paste_failure_is_independent_and_restores_clipboard(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, controlled, state, _ = self._runner_failure_fixture(temp, paste_fail="yes")
            state.write_text("ORIGINAL")
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            result = self._run_selection_fixture(env, prompt, output="replace-selection")
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"[ぁ-んァ-ン一-龥]")
            self.assertEqual(state.read_text(), "ORIGINAL")
            self.assertFalse(controlled.exists())

    def test_runner_snapshot_failure_rejects_before_api_and_cleans_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, controlled, state, restore_marker = self._runner_failure_fixture(temp, snapshot_fail="yes")
            state.write_text("ORIGINAL")
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            result = self._run_selection_fixture(env, prompt)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("退避", result.stderr)
            self.assertTrue(restore_marker.exists())
            self.assertFalse(controlled.exists())

    def test_runner_restore_failure_is_independent_and_temp_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, controlled, state, restore_marker = self._runner_failure_fixture(temp, restore_fail="yes")
            state.write_text("ORIGINAL")
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            result = self._run_selection_fixture(env, prompt, output="display")
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"[ぁ-んァ-ン一-龥]")
            self.assertTrue(restore_marker.exists())
            self.assertNotEqual(state.read_text(), "ORIGINAL")
            self.assertFalse(controlled.exists())

    def test_runner_missing_dependency_rejects_before_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            env, controlled, state, restore_marker = self._runner_failure_fixture(temp, dependency=False)
            state.write_text("ORIGINAL")
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            result = self._run_selection_fixture(env, prompt)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ヘルパー", result.stderr)
            self.assertFalse(restore_marker.exists())
            self.assertFalse(controlled.exists())

    def test_client_malformed_json_transport_is_safe(self):
        with patch.object(gemini_client, "keychain_key", return_value="TOP_SECRET"):
            with self.assertRaisesRegex(gemini_client.GeminiError, "応答を解釈"):
                gemini_client.generate_content("入力", "model", opener=lambda *args, **kwargs: type("R", (), {"__enter__": lambda s: s, "__exit__": lambda *a: False, "read": lambda s: b"not-json"})())

    def test_readme_describes_safe_manual_acceptance_boundary(self):
        readme = (ROOT / "README.md").read_text()
        for term in ("Keychain", "display-copy", "replace-selection", "実機", "API"):
            self.assertIn(term, readme)

    def test_empty_stdin_is_rejected_before_client(self):
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as stream:
            stream.write("{selection}")
            prompt = pathlib.Path(stream.name)
        try:
            result = subprocess.run(
                [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
                 "--model", "model", "--output", "display", "--input-source", "stdin"],
                input="", text=True, capture_output=True,
            )
        finally:
            prompt.unlink()
        self.assertEqual(result.returncode, 1)
        self.assertIn("空", result.stderr)

    def test_replace_selection_rejects_stdin_before_any_api_or_clipboard(self):
        prompt = ROOT / "README.md"
        result = subprocess.run(
            [str(ROOT / "ai-commands" / "gemini_runner.sh"), "--prompt-file", str(prompt),
             "--model", "model", "--output", "replace-selection", "--input-source", "stdin"],
            input="input", text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("selection入力専用", result.stderr)


if __name__ == "__main__":
    unittest.main()
