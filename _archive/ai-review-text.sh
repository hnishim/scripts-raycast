#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title AI Review Text
# @raycast.mode fullOutput
# @raycast.argument1 { "type": "text", "placeholder": "Text (optional)", "optional": true }
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT="$(cd "$DIR/../../prompts" && pwd)/raycast/ai-commands/review-text_compact.md"
if [ -n "${1:-}" ]; then printf '%s' "$1" | exec "$DIR/ai-commands/gemini_runner.sh" --prompt-file "$PROMPT" --model gemini-flash-latest --output display-copy --input-source stdin; else exec "$DIR/ai-commands/gemini_runner.sh" --prompt-file "$PROMPT" --model gemini-flash-latest --output display-copy --input-source selection; fi
