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

TEXTLINT_NPM_PACKAGES=(
    "textlint"
    "@textlint-ja/textlint-rule-no-dropping-i"
    "@textlint-ja/textlint-rule-no-filler"
    "@textlint-ja/textlint-rule-no-insert-dropping-sa"
    "@textlint-ja/textlint-rule-no-insert-re"
    "@textlint-ja/textlint-rule-no-synonyms"
    "@textlint-ja/textlint-rule-preset-ai-writing"
    "@textlint-rule/textlint-rule-no-unmatched-pair"
    "textlint-rule-abbr-within-parentheses"
    "textlint-rule-alive-link"
    "textlint-rule-common-misspellings"
    "textlint-rule-date-weekday-mismatch"
    "textlint-rule-doubled-spaces"
    "textlint-rule-en-capitalization"
    "textlint-rule-en-max-word-count"
    "textlint-rule-ja-hiragana-fukushi"
    "textlint-rule-ja-hiragana-hojodoushi"
    "textlint-rule-ja-hiragana-keishikimeishi"
    "textlint-rule-ja-no-abusage"
    "textlint-rule-ja-no-inappropriate-words"
    "textlint-rule-ja-no-orthographic-variants"
    "textlint-rule-ja-no-redundant-expression"
    "textlint-rule-ja-no-successive-word"
    "textlint-rule-ja-overlooked-typo"
    "textlint-rule-ja-unnatural-alphabet"
    "textlint-rule-no-dead-link"
    "textlint-rule-no-double-negative-ja"
    "textlint-rule-no-doubled-conjunction"
    "textlint-rule-no-doubled-conjunctive-particle-ga"
    "textlint-rule-no-doubled-joshi"
    "textlint-rule-no-dropping-the-ra"
    "textlint-rule-no-empty-element"
    "textlint-rule-no-empty-section"
    "textlint-rule-no-hankaku-kana"
    "textlint-rule-no-kangxi-radicals"
    "textlint-rule-no-mix-dearu-desumasu"
    "textlint-rule-no-nfd"
    "textlint-rule-no-start-duplicated-conjunction"
    "textlint-rule-no-todo"
    "textlint-rule-no-zero-width-spaces"
    "textlint-rule-period-in-header"
    "textlint-rule-period-in-list-item"
    "textlint-rule-prefer-tari-tari"
    "textlint-rule-preset-ja-spacing"
    "textlint-rule-preset-ja-technical-writing"
    "textlint-rule-preset-japanese"
    "textlint-rule-preset-jtf-style"
    "textlint-rule-prh"
    "textlint-rule-sentence-length"
    "textlint-rule-spelling"
    "textlint-rule-terminology"
)

echo "textlint本体と関連ルールを最新版へ更新します..."
TEXTLINT_NPM_PACKAGE_SPECS=()
for package_name in "${TEXTLINT_NPM_PACKAGES[@]}"; do
    TEXTLINT_NPM_PACKAGE_SPECS+=("${package_name}@latest")
done

if ! npm install --global --no-audit --no-fund "${TEXTLINT_NPM_PACKAGE_SPECS[@]}"; then
    echo "textlint関連npmパッケージの更新に失敗しました。" >&2
    exit 1
fi
