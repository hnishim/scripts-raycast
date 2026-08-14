#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Copy prompt for minutes
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 📔
# @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "required": true, "data": [ { "title": "日本語", "value": "ja" }, { "title": "英語", "value": "en" }] }

# Documentation:
# @raycast.description Copy the prompt stored in a local md file for creating a minute into the clipboard

export LANG=ja_JP.UTF-8

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
md_file_path="${SCRIPT_DIR}/../../prompts/gemini-gems/NotebookLM_create-minutes.md"

before_string="日本語 英語"
if [ "$1" = "en" ]; then
  after_string="英語"
else
  after_string="日本語"
fi

sed "s/$before_string/$after_string/g" "$md_file_path" | pbcopy

osascript -e '
  tell application "System Events"
    keystroke "v" using command down
  end tell
'
