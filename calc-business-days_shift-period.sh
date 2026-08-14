#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Calc Business Days: Shift Period
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🔁
# @raycast.argument1 { "type": "text", "placeholder": "Original Start Date" }
# @raycast.argument2 { "type": "text", "placeholder": "Original End Date" }
# @raycast.argument3 { "type": "text", "placeholder": "New Start Date" }

# Documentation:
# @raycast.description 期間をシフトして新しい終了日を計算

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/calcBusinessDays/run.sh" shift_period --original-start "$1" --original-end "$2" --new-start "$3"
