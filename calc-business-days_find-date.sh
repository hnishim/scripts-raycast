#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Calc Business Days: Find Date
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ↔️
# @raycast.argument1 { "type": "text", "placeholder": "start date" }
# @raycast.argument2 { "type": "text", "placeholder": "business days" }

# Documentation:
# @raycast.description N営業日後の日付を計算

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/calcBusinessDays/run.sh" find_date --start "$1" --days "$2"
