#!/bin/bash
set -euo pipefail
if [ ! -t 0 ]; then echo "このスクリプトはTerminalから実行してください。" >&2; exit 2; fi
read -r -s -p "Gemini APIキー: " GEMINI_API_KEY
printf '\n' >&2
[ -n "$GEMINI_API_KEY" ] || { echo "APIキーが空です。" >&2; exit 2; }
ACCOUNT="$(/usr/bin/id -un)"
printf '%s' "$GEMINI_API_KEY" | /usr/bin/security add-generic-password -U -s com.hnishim.raycast-gemini -a "$ACCOUNT" -w
unset GEMINI_API_KEY ACCOUNT
echo "Keychainへ登録しました。"
