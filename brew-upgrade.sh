#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Brew upgrade
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🍺

# Documentation:
# @raycast.description Homebrewのもろもろ更新作業を一括処理

brew -v
brew outdated
brew update && brew upgrade && brew cleanup && brew autoremove
brew upgrade --cask --greedy

mas upgrade