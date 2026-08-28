#!/usr/bin/python3
"""Small, dependency-free Gemini client used by Raycast commands."""
import json
import subprocess
import sys
import urllib.error
import urllib.request

SERVICE = "com.hnishim.raycast-gemini"


class GeminiError(Exception):
    pass


def keychain_key():
    try:
        account = subprocess.check_output(["/usr/bin/id", "-un"], text=True, stderr=subprocess.DEVNULL).strip()
        if not account:
            raise GeminiError("macOSユーザー名を取得できません。")
        return subprocess.check_output(
            ["/usr/bin/security", "find-generic-password", "-s", SERVICE, "-a", account, "-w"],
            text=True, stderr=subprocess.DEVNULL).rstrip("\r\n")
    except (OSError, subprocess.CalledProcessError):
        raise GeminiError("Gemini APIキーがKeychainに登録されていません。")


def render_prompt(template, selection):
    import re
    token_pattern = re.compile(r'\{(?:selection|argument)[^}]*\}')
    valid_pattern = re.compile(r'\{selection\}|\{argument name="[^"]+"\}')
    for token in token_pattern.findall(template):
        if not valid_pattern.fullmatch(token):
            raise GeminiError("プロンプトに未解決または不正なプレースホルダーがあります。")
    if "{selection" in template and "{selection}" not in template:
        raise GeminiError("プロンプトに未解決のプレースホルダーがあります。")
    rendered = re.sub(r'\{selection\}|\{argument name="[^"]+"\}', lambda _match: selection, template)
    return rendered


def response_text(payload):
    if not isinstance(payload, dict):
        raise GeminiError("Geminiの応答形式を解釈できません。")
    feedback = payload.get("promptFeedback", {})
    if not isinstance(feedback, dict):
        raise GeminiError("Geminiの応答形式を解釈できません。")
    if feedback.get("blockReason"):
        raise GeminiError("Geminiが安全性ポリシーにより入力をブロックしました。")
    try:
        candidates = payload["candidates"]
        if not isinstance(candidates, list):
            raise GeminiError("Geminiの応答形式を解釈できません。")
        if not candidates:
            raise GeminiError("Geminiから候補が返されませんでした（安全性ブロックの可能性があります）。")
        candidate = candidates[0]
        if not isinstance(candidate, dict):
            raise GeminiError("Geminiの応答形式を解釈できません。")
        if candidate.get("finishReason") == "SAFETY":
            raise GeminiError("Geminiが安全性ポリシーにより応答をブロックしました。")
        content = candidate.get("content")
        if not isinstance(content, dict):
            raise GeminiError("Geminiの応答形式を解釈できません。")
        parts = content.get("parts")
        if not isinstance(parts, list):
            raise GeminiError("Geminiの応答形式を解釈できません。")
    except (KeyError, TypeError):
        raise GeminiError("Geminiの応答形式を解釈できません。")
    if any(not isinstance(part, dict) for part in parts):
        raise GeminiError("Geminiの応答形式を解釈できません。")
    texts = [part.get("text") for part in parts]
    if any(text is not None and not isinstance(text, str) for text in texts):
        raise GeminiError("Geminiの応答形式を解釈できません。")
    text = "".join(text for text in texts if text is not None)
    if not text:
        raise GeminiError("Geminiから空の応答が返されました（安全性ブロックの可能性があります）。")
    return text


def generate_content(prompt, model, timeout=60, opener=urllib.request.urlopen):
    key = keychain_key()
    url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent".format(model)
    body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode("utf-8")
    request = urllib.request.Request(url, data=body,
                                     headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with opener(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise GeminiError("Gemini APIエラー（HTTP {}）です。APIキー、モデル、入力を確認してください。".format(error.code))
    except (urllib.error.URLError, TimeoutError, OSError):
        raise GeminiError("Gemini APIへの接続がタイムアウトまたは失敗しました。")
    except (ValueError, UnicodeDecodeError):
        raise GeminiError("Gemini APIの応答を解釈できません。")
    return response_text(payload)


def main():
    if len(sys.argv) != 2:
        print("モデル指定が必要です。", file=sys.stderr)
        return 2
    try:
        print(generate_content(sys.stdin.read(), sys.argv[1]))
        return 0
    except GeminiError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
