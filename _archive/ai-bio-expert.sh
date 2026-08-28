#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title AI Bio Expert
# @raycast.mode fullOutput
# @raycast.argument1 { "type": "text", "placeholder": "Word/Phrase or Question (optional)", "optional": true }
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT="$(cd "$DIR/../../prompts" && pwd)/raycast/ai-commands/bio-ai_expert.md"
if [ -n "${1:-}" ]; then printf '%s' "$1" | exec "$DIR/ai-commands/gemini_runner.sh" --prompt-file "$PROMPT" --model gemini-flash-latest --output display --input-source stdin; else exec "$DIR/ai-commands/gemini_runner.sh" --prompt-file "$PROMPT" --model gemini-flash-latest --output display --input-source selection; fi
