#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Create a minute by Gemini
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝
# @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "required": true, "data": [ { "title": "日本語", "value": "ja" }, { "title": "英語", "value": "en" }] }
# @raycast.argument2 { "type": "text", "placeholder": "mp3 location" }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MINUTES_DIR="${SCRIPT_DIR}/../finder/context-menu/create-minute-by-Gemini/python"

if [ -z "${GEMINI_API_KEY_FOR_MINUTES:-}" ]; then
    GEMINI_API_KEY_FOR_MINUTES="$(/bin/zsh -lc 'printf %s "$GEMINI_API_KEY_FOR_MINUTES"')"
fi
export GEMINI_API_KEY_FOR_MINUTES

if [ -z "${GEMINI_API_KEY_FOR_MINUTES}" ]; then
    osascript -e 'display notification "GEMINI_API_KEY_FOR_MINUTESが設定されていません。" with title "議事録作成エラー" sound name "Basso"'
    exit 1
fi

if "${MINUTES_DIR}/run.sh" "$1" "$2"; then
    osascript -e 'display notification "議事録作成処理が正常に完了しました。" with title "議事録作成"'
else
    osascript -e 'display notification "議事録作成処理中にエラーが発生しました。" with title "議事録作成エラー" sound name "Basso"'
    exit 1
fi
