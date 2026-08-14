#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Title Case (Chicago)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔤

# Documentation:
# @raycast.description 選択中の英語タイトルをChicagoスタイルに変換して置換

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="/usr/bin/python3"

if [ ! -x "$PYTHON_BIN" ]; then
    echo "システムのPython 3が見つかりません。" >&2
    exit 1
fi

# RaycastのScript Commandには getSelectedText() がないため、前面アプリの
# 選択範囲をコピーして読み取る。Raycastが閉じて対象アプリへ戻るまで少し待つ。
osascript -e 'tell application "System Events" to keystroke "c" using command down' >/dev/null
sleep 0.15

INPUT_FILE="$(mktemp)"
OUTPUT_FILE="$(mktemp)"
cleanup() {
    rm -f "$INPUT_FILE" "$OUTPUT_FILE"
}
trap cleanup EXIT

pbpaste >"$INPUT_FILE"
if [ ! -s "$INPUT_FILE" ]; then
    echo "テキストが選択されていません。" >&2
    exit 1
fi

"$PYTHON_BIN" "$SCRIPT_DIR/title-case-chicago.py" <"$INPUT_FILE" >"$OUTPUT_FILE"
pbcopy <"$OUTPUT_FILE"

# 変換結果を選択範囲へ貼り付ける。変換後の文字列はクリップボードにも残す。
osascript -e 'tell application "System Events" to keystroke "v" using command down' >/dev/null
