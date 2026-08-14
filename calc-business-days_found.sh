#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Calc Business Days: Count
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ➡️
# @raycast.argument1 { "type": "text", "placeholder": "start date" }
# @raycast.argument2 { "type": "text", "placeholder": "end date" }

# Documentation:
# @raycast.description 期間内の営業日数を計算

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/calcBusinessDays/run.sh" count --start "$1" --end "$2"
