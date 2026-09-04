#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Launch apps
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🚀
# @raycast.argument1 { "type": "text", "placeholder": "Placeholder" }

echo "Launching $1..."
open -a "$1"