#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title AI Translate
# @raycast.mode fullOutput
# @raycast.argument1 { "type": "text", "placeholder": "Text (optional)", "optional": true }

echo "start"

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT="$(cd "$DIR/../../prompts" && pwd)/raycast/ai-commands/translate.md"
if [ -n "${1:-}" ]; then printf '%s' "$1" | exec "$DIR/ai-commands/gemini_runner.sh" --prompt-file "$PROMPT" --model gemini-flash-lite-latest --output display-copy --input-source selection; else exec "$DIR/ai-commands/gemini_runner.sh" --prompt-file "$PROMPT" --model gemini-flash-lite-latest --output display-copy --input-source selection; fi

echo "end"