#!/bin/bash

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