import io
import json
import os
import sys
import unittest
import urllib.error
import pathlib
import subprocess
import tempfile
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))
import gemini_client


class Response:
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return json.dumps({"candidates": [{"content": {"parts": [{"text": "A"}, {"text": "\nB"}]}}]}).encode()


class GeminiTests(unittest.TestCase):
    def test_wrapper_metadata_is_json_and_optional(self):
        root = pathlib.Path(__file__).parents[1]
        for name in ("ai-review-text.sh", "ai-translate.sh", "ai-bio-expert.sh"):
            line = next(line for line in (root / name).read_text().splitlines() if "@raycast.argument1" in line)
            metadata = line.split(" ", 2)[2]
            self.assertTrue(json.loads(metadata)["optional"])

    def test_render_unicode_markdown_and_argument(self):
        value = gemini_client.render_prompt('引用「{selection}」\n{argument name="Word/Phrase or Question"}', '日本語\n**引用**')
        self.assertIn('日本語\n**引用**', value)

    def test_unresolved_placeholder_rejected(self):
        with self.assertRaises(gemini_client.GeminiError):
            gemini_client.render_prompt('{argument name=unknown}', 'x')

    def test_empty_selection_rejected_by_runner_contract(self):
        self.assertEqual(gemini_client.render_prompt('{selection}', ''), '')

    def test_response_multiple_parts(self):
        self.assertEqual(gemini_client.response_text(json.loads(Response().read())), 'A\nB')

    def test_empty_candidates_and_empty_text(self):
        with self.assertRaises(gemini_client.GeminiError):
            gemini_client.response_text({"candidates": []})
        with self.assertRaises(gemini_client.GeminiError):
            gemini_client.response_text({"candidates": [{"content": {"parts": [{"text": ""}]}}]})

    def test_http_error_is_safe(self):
        def opener(*args, **kwargs):
            raise urllib.error.HTTPError('url', 403, 'bad', {}, io.BytesIO(b'SECRET'))
        with patch.object(gemini_client, 'keychain_key', return_value='SECRET'):
            with self.assertRaisesRegex(gemini_client.GeminiError, 'HTTP 403') as raised:
                gemini_client.generate_content('prompt', 'model', opener=opener)
        self.assertNotIn('SECRET', str(raised.exception))

    def test_key_is_header_only_and_not_error(self):
        seen = {}
        def opener(request, timeout):
            seen['header'] = request.get_header('X-goog-api-key')
            return Response()
        with patch.object(gemini_client, 'keychain_key', return_value='SECRET'):
            self.assertEqual(gemini_client.generate_content('prompt', 'model', opener=opener), 'A\nB')
        self.assertEqual(seen['header'], 'SECRET')

    def test_literal_placeholder_in_input_is_not_reinterpreted(self):
        value = gemini_client.render_prompt("prefix {selection}", "literal {selection} {argument name=\"x\"}")
        self.assertEqual(value, "prefix literal {selection} {argument name=\"x\"}")

    def test_safety_blocks_are_specific(self):
        with self.assertRaisesRegex(gemini_client.GeminiError, "入力をブロック"):
            gemini_client.response_text({"promptFeedback": {"blockReason": "SAFETY"}})
        with self.assertRaisesRegex(gemini_client.GeminiError, "応答をブロック"):
            gemini_client.response_text({"candidates": [{"finishReason": "SAFETY", "content": {"parts": []}}]})

    def test_response_shape_validation(self):
        invalid = [[], {"promptFeedback": []}, {"candidates": {}}, {"candidates": ["x"]},
                   {"candidates": [{"content": []}]},
                   {"candidates": [{"content": {"parts": "x"}}]},
                   {"candidates": [{"content": {"parts": [{"text": 1}]}}]}]
        for payload in invalid:
            with self.assertRaises(gemini_client.GeminiError):
                gemini_client.response_text(payload)

    def test_shell_output_contracts_and_selection_failures(self):
        runner = pathlib.Path(__file__).with_name("gemini_runner.sh")
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            prompt = temp / "prompt.md"
            prompt.write_text("{selection}")
            state = temp / "clipboard"
            state.write_text("ORIGINAL")
            fake_python = temp / "python"
            fake_python.write_text("#!/bin/sh\n[ \"$FAKE_API_FAIL\" = yes ] && exit 1\nprintf response > \"$5/response\"\n")
            fake_python.chmod(0o755)
            fake_pbpaste = temp / "pbpaste"
            fake_pbpaste.write_text("#!/bin/sh\ncat \"$STATE\"\n")
            fake_pbpaste.chmod(0o755)
            fake_pbcopy = temp / "pbcopy"
            fake_pbcopy.write_text("#!/bin/sh\ncat > \"$STATE\"\n")
            fake_pbcopy.chmod(0o755)
            fake_osascript = temp / "osascript"
            fake_osascript.write_text("#!/bin/sh\nif echo \"$*\" | grep -q 'get name'; then echo App; elif echo \"$*\" | grep -q 'keystroke \\\"c\\\"'; then [ \"$FAKE_COPY\" = yes ] && printf SELECTED > \"$STATE\"; elif echo \"$*\" | grep -q 'keystroke \\\"v\\\"' && [ \"$FAKE_PASTE_FAIL\" = yes ]; then exit 1; fi\nexit 0\n")
            fake_osascript.chmod(0o755)
            fake_sleep = temp / "sleep"
            fake_sleep.write_text("#!/bin/sh\nexit 0\n")
            fake_sleep.chmod(0o755)
            fake_helper = temp / "pasteboard"
            fake_helper.write_text("#!/bin/sh\nif [ \"$2\" = snapshot ]; then mkdir -p \"$3\"; touch \"$3/manifest.json\"; else printf ORIGINAL > \"$STATE\"; fi\n")
            fake_helper.chmod(0o755)
            env = {**os.environ, "STATE": str(state), "FAKE_COPY": "yes", "FAKE_API_FAIL": "no", "FAKE_PASTE_FAIL": "no", "GEMINI_RUNNER_PASTEBOARD_COMMAND": str(fake_helper), "GEMINI_RUNNER_PYTHON": str(fake_python),
                   "GEMINI_RUNNER_PBPASTE": str(fake_pbpaste), "GEMINI_RUNNER_PBCOPY": str(fake_pbcopy),
                   "GEMINI_RUNNER_OSASCRIPT": str(fake_osascript), "GEMINI_RUNNER_SLEEP": str(fake_sleep)}
            def run(output, source):
                return subprocess.run([str(runner), "--prompt-file", str(prompt), "--model", "model",
                                       "--output", output, "--input-source", source], input="INPUT", text=True,
                                      capture_output=True, env=env)
            for output in ("display", "display-copy"):
                state.write_text("ORIGINAL")
                result = run(output, "stdin")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state.read_text(), "ORIGINAL" if output == "display" else "response")
                state.write_text("ORIGINAL")
                result = run(output, "selection")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state.read_text(), "ORIGINAL" if output == "display" else "response")
            state.write_text("ORIGINAL")
            result = run("replace-selection", "selection")
            self.assertEqual(result.returncode, 0)
            self.assertEqual(state.read_text(), "response")
            state.write_text("ORIGINAL")
            env["FAKE_COPY"] = "no"
            result = run("display", "selection")
            self.assertEqual(result.returncode, 1)
            self.assertIn("選択範囲", result.stderr)
            self.assertEqual(state.read_text(), "ORIGINAL")
            env["FAKE_COPY"] = "yes"
            env["FAKE_API_FAIL"] = "yes"
            state.write_text("ORIGINAL")
            self.assertEqual(run("display-copy", "selection").returncode, 1)
            self.assertEqual(state.read_text(), "ORIGINAL")
            env["FAKE_API_FAIL"] = "no"
            env["FAKE_PASTE_FAIL"] = "yes"
            state.write_text("ORIGINAL")
            self.assertEqual(run("replace-selection", "selection").returncode, 1)
            self.assertEqual(state.read_text(), "ORIGINAL")


if __name__ == '__main__':
    unittest.main()
