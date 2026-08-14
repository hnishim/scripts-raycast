#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open dotfiles folderin Cursor
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🛠️

# Documentation:
# @raycast.author hnishim
# @raycast.authorURL https://raycast.com/hnishim

cursor --reuse-window \
  "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Dev/dotfiles"
