#!/bin/bash

# @tuna.name Cal
# @tuna.subtitle Nヶ月先までのカレンダーを表示
# @tuna.icon symbol:calendar
# @tuna.mode inline
# @tuna.input arguments
# @tuna.output text

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Cal
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 📅
# @raycast.argument1 { "type": "text", "placeholder": "Months" }

# Documentation:
# @raycast.description Nヶ月先までのカレンダーを表示

cal -A $1