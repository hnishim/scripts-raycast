#!/bin/bash
set -euo pipefail
# Hammerspoon is launched as a GUI process and may not inherit a UTF-8
# locale. pbcopy/pbpaste use the locale to encode and decode text.
export LC_ALL="${GEMINI_RUNNER_LOCALE:-en_US.UTF-8}"
usage() { echo "使い方: $0 --prompt-file PATH --model MODEL_ID --output display|display-copy|replace-selection --input-source stdin|selection" >&2; }
PROMPT_FILE=""; MODEL=""; OUTPUT=""; INPUT_SOURCE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prompt-file) [ "$#" -ge 2 ] || { usage; exit 2; }; PROMPT_FILE="$2"; shift 2 ;;
        --model) [ "$#" -ge 2 ] || { usage; exit 2; }; MODEL="$2"; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage; exit 2; }; OUTPUT="$2"; shift 2 ;;
        --input-source) [ "$#" -ge 2 ] || { usage; exit 2; }; INPUT_SOURCE="$2"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
case "$OUTPUT" in display|display-copy|replace-selection) ;; *) echo "出力方式が不正です。" >&2; exit 2 ;; esac
case "$INPUT_SOURCE" in stdin|selection) ;; *) echo "入力元が不正です。" >&2; exit 2 ;; esac
[ -n "$MODEL" ] || { echo "モデルが指定されていません。" >&2; exit 2; }
case "$MODEL" in *[!A-Za-z0-9._-]*) echo "モデル指定が不正です。" >&2; exit 2 ;; esac
[ -f "$PROMPT_FILE" ] || { echo "プロンプトファイルが見つかりません。" >&2; exit 2; }
if [ "$OUTPUT" = replace-selection ] && [ "$INPUT_SOURCE" != selection ]; then
    echo "replace-selectionはselection入力専用です。" >&2; exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${GEMINI_RUNNER_PYTHON:-/usr/bin/python3}"
PBPASTE_BIN="${GEMINI_RUNNER_PBPASTE:-/usr/bin/pbpaste}"
PBCOPY_BIN="${GEMINI_RUNNER_PBCOPY:-/usr/bin/pbcopy}"
OSASCRIPT_BIN="${GEMINI_RUNNER_OSASCRIPT:-/usr/bin/osascript}"
SLEEP_BIN="${GEMINI_RUNNER_SLEEP:-/bin/sleep}"
PASTEBOARD_COMMAND="${GEMINI_RUNNER_PASTEBOARD_COMMAND:-/usr/bin/swift}"
PASTEBOARD_HELPER="${GEMINI_RUNNER_PASTEBOARD_HELPER:-$SCRIPT_DIR/pasteboard_helper.swift}"
RM_BIN="${GEMINI_RUNNER_RM:-/bin/rm}"
require_executable() {
    local executable="$1"
    local label="$2"
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "必要な${label}を実行できません。" >&2
        exit 1
    fi
}
require_executable "$PYTHON_BIN" "Python"
require_executable "$RM_BIN" "一時ファイル削除"
if [ "$INPUT_SOURCE" = selection ]; then
    require_executable "$PBPASTE_BIN" "pbpaste"
    require_executable "$PBCOPY_BIN" "pbcopy"
    require_executable "$OSASCRIPT_BIN" "osascript"
    require_executable "$SLEEP_BIN" "sleep"
    require_executable "$PASTEBOARD_COMMAND" "クリップボード復元ヘルパー"
    if [ ! -f "$PASTEBOARD_HELPER" ]; then
        echo "クリップボード復元ヘルパーが見つかりません。" >&2
        exit 1
    fi
fi
TMP_DIR="$(mktemp -d)"
SUCCESS=0
CHILD_PID=""
cleanup() {
    local exit_code=$?
    if [ "$INPUT_SOURCE" = selection ] && { [ "$OUTPUT" = display ] || [ "$SUCCESS" -eq 0 ]; } && [ -d "$TMP_DIR/pasteboard" ]; then
        if ! "$PASTEBOARD_COMMAND" "$PASTEBOARD_HELPER" restore "$TMP_DIR/pasteboard"; then
            echo "クリップボードの復元に失敗しました。元の内容を確認してください。" >&2
            exit_code=1
        fi
    fi
    if ! "$RM_BIN" -rf "$TMP_DIR"; then
        echo "一時ファイルの削除に失敗しました。" >&2
        exit_code=1
    fi
    if [ "$exit_code" -ne 0 ]; then
        exit "$exit_code"
    fi
}
trap cleanup EXIT
handle_signal() {
    local signal_number="$1"
    # Ignore a repeated signal while forwarding and reaping the child.  The
    # EXIT trap remains the single owner of clipboard restoration and removal.
    trap '' INT HUP TERM
    if [ -n "$CHILD_PID" ]; then
        kill -"$signal_number" "$CHILD_PID" 2>/dev/null || true
        # A shell child may be waiting on one of its own descendants and defer
        # the forwarded signal.  TERM is the bounded termination fallback.
        kill -TERM "$CHILD_PID" 2>/dev/null || true
        wait "$CHILD_PID" 2>/dev/null || true
        CHILD_PID=""
    fi
    exit $((128 + signal_number))
}
trap 'handle_signal 2' INT
trap 'handle_signal 1' HUP
trap 'handle_signal 15' TERM
copy_to_clipboard() {
    if ! "$PBCOPY_BIN"; then
        echo "クリップボードへのコピーに失敗しました。" >&2
        return 1
    fi
}
if [ "$INPUT_SOURCE" = selection ]; then
    mkdir -m 700 "$TMP_DIR/pasteboard"
    "$PASTEBOARD_COMMAND" "$PASTEBOARD_HELPER" snapshot "$TMP_DIR/pasteboard" || { echo "クリップボードを退避できません。" >&2; exit 1; }
    if ! "$PBPASTE_BIN" >"$TMP_DIR/original-clipboard"; then
        echo "元のクリップボードを取得できません。" >&2
        exit 1
    fi
    if ! copy_to_clipboard <<<"__RAYCAST_GEMINI_SELECTION_SENTINEL__"; then
        exit 1
    fi
    if ! "$OSASCRIPT_BIN" -e 'tell application "System Events" to get name of first process whose frontmost is true' >"$TMP_DIR/frontmost-app"; then
        echo "起動元アプリを確認できません。" >&2
        exit 1
    fi
    # Let the modifier keys from the global Hammerspoon hotkey be released
    # before sending the synthetic Command+C to the frontmost application.
    "$SLEEP_BIN" 0.25
    if ! "$OSASCRIPT_BIN" -e 'tell application "System Events" to keystroke "c" using command down' >/dev/null; then
        echo "選択範囲のコピーに失敗しました。" >&2
        exit 1
    fi
    copied_selection=0
    for _ in 1 2 3 4 5; do
        "$SLEEP_BIN" 0.2
        if "$PBPASTE_BIN" >"$TMP_DIR/clipboard" \
            && [ -s "$TMP_DIR/clipboard" ] \
            && ! grep -Fxq '__RAYCAST_GEMINI_SELECTION_SENTINEL__' "$TMP_DIR/clipboard"; then
            copied_selection=1
            break
        fi
    done
    if [ "$copied_selection" -ne 1 ]; then
        frontmost_application="$(cat "$TMP_DIR/frontmost-app" 2>/dev/null || true)"
        echo "テキストの選択範囲を取得できませんでした（前面アプリ: ${frontmost_application:-不明}）。" >&2
        exit 1
    fi
else
    cat >"$TMP_DIR/input"
    [ -s "$TMP_DIR/input" ] || { echo "入力テキストが空です。" >&2; exit 1; }
fi
"$PYTHON_BIN" "$SCRIPT_DIR/gemini_runner.py" "$PROMPT_FILE" "$MODEL" "$INPUT_SOURCE" "$TMP_DIR" &
CHILD_PID=$!
if wait "$CHILD_PID"; then
    CHILD_PID=""
else
    code=$?
    CHILD_PID=""
    exit "$code"
fi
case "$OUTPUT" in
    display)
        if ! cat "$TMP_DIR/response"; then
            echo "応答の表示に失敗しました。" >&2
            exit 1
        fi
        ;;
    display-copy)
        if ! cat "$TMP_DIR/response"; then
            echo "応答の表示に失敗しました。" >&2
            exit 1
        fi
        if ! copy_to_clipboard <"$TMP_DIR/response"; then exit 1; fi
        ;;
    replace-selection)
        if ! copy_to_clipboard <"$TMP_DIR/response"; then exit 1; fi
        FRONTMOST_APP="$(cat "$TMP_DIR/frontmost-app")"
        if ! "$OSASCRIPT_BIN" - "$FRONTMOST_APP" <<'APPLESCRIPT' >/dev/null
on run argv
    tell application "System Events" to set frontmost of process (item 1 of argv) to true
end run
APPLESCRIPT
        then
            echo "起動元アプリの再表示に失敗しました。" >&2
            exit 1
        fi
        if ! "$OSASCRIPT_BIN" -e 'tell application "System Events" to keystroke "v" using command down' >/dev/null; then
            echo "選択範囲への貼り付けに失敗しました。" >&2
            exit 1
        fi
        ;;
esac
SUCCESS=1
