#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Mic Mute Via MuteMe
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎙️

# Documentation:
# @raycast.description メニューバーに表示されたMuteMeのアイコンを使用してマイクのミュートをトグル

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "${SCRIPT_DIR}/.venv/bin/python3" ] || ! command -v cliclick >/dev/null 2>&1; then
    osascript -e 'display notification "MuteMe用の実行環境がありません。" with title "MuteMeエラー" sound name "Basso"'
    exit 1
fi

x=$("${SCRIPT_DIR}/.venv/bin/python3" "${SCRIPT_DIR}/define_width.py") || exit 1
cliclick -r "dc:${x},12"
