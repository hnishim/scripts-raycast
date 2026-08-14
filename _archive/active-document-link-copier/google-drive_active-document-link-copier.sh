#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Copy Active Document Google Drive Link
# @raycast.mode silent
# @raycast.packageName Google Drive

set -uo pipefail

MOUNT="$HOME/mnt/gdrive"
REMOTE="AllDrives:"
RCLONE="/opt/homebrew/bin/rclone"

notify() {
  osascript -e "display notification \"$1\" with title \"Copy Active Document Google Drive Link\""
}

# パスを物理パスへ正規化し、firmlink 接頭辞を除去（マウント判定のずれを防ぐ）
canon() {
  local p="$1" d b
  d=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || return 1
  b=$(basename "$p")
  p="$d/$b"
  printf '%s' "${p#/System/Volumes/Data}"
}

# 最前面アプリの bundle ID を取得
bundle_id=$(osascript -e '
  tell application "System Events"
    return bundle identifier of first application process whose frontmost is true
  end tell
' 2>/dev/null)

# Office はアプリ固有 API、その他は最前面ウィンドウの AXDocument を使う
case "$bundle_id" in
  com.microsoft.Excel)
    file_path=$(osascript -e '
      tell application "Microsoft Excel"
        if not (exists active workbook) then error "開いているブックがありません"
        return POSIX path of (full name of active workbook as alias)
      end tell
    ' 2>/dev/null)
    ;;
  com.microsoft.Word)
    file_path=$(osascript -e '
      tell application "Microsoft Word"
        if not (exists active document) then error "開いている文書がありません"
        return POSIX path of (full name of active document as alias)
      end tell
    ' 2>/dev/null)
    ;;
  com.microsoft.Powerpoint)
    file_path=$(osascript -e '
      tell application "Microsoft PowerPoint"
        if not (exists active presentation) then error "開いているプレゼンテーションがありません"
        return POSIX path of (full name of active presentation as alias)
      end tell
    ' 2>/dev/null)
    ;;
  *)
    document_url=$(osascript -l JavaScript <<'JXA' 2>/dev/null
const se = Application("System Events");
const proc = se.processes.whose({ frontmost: true })()[0];
const win = proc.attributes.byName("AXFocusedWindow").value();
const doc = win.attributes.byName("AXDocument").value();
if (doc) console.log(doc);
JXA
    )

    # file:// URL を外し、%XX を純シェルでデコード（python3 依存を排除）
    case "$document_url" in
      file://*)
        path_enc="${document_url#file://}"
        file_path=$(printf '%b' "${path_enc//%/\\x}")
        ;;
      *)
        file_path=""
        ;;
    esac
    ;;
esac

if [ -z "${file_path:-}" ] || [ ! -e "$file_path" ]; then
  notify "最前面ウィンドウから保存済みファイルを取得できません"
  exit 1
fi

# rclone mount と対象ファイルを正規化してから相対パスへ変換
mount_real=$(canon "$MOUNT") || { notify "マウント先を解決できません"; exit 1; }
file_real=$(canon "$file_path") || { notify "ファイルパスを解決できません"; exit 1; }

rel="${file_real#"$mount_real"/}"
if [ "$rel" = "$file_real" ]; then
  notify "ファイルは rclone マウント外です"
  exit 1
fi

dir=$(dirname "$rel")
base=$(basename "$rel")

# まず対象パスを直接 stat して Drive ID を取得（フォルダ全列挙を避ける）
id=$("$RCLONE" lsjson --stat --no-modtime --no-mimetype "$REMOTE$rel" 2>/dev/null \
  | awk -F'"' '/"ID":/{print $4; exit}')

# フォールバック：親フォルダ内でファイル名に一致する ID を取得
if [ -z "$id" ]; then
  search_dir="$dir"
  [ "$search_dir" = "." ] && search_dir=""
  id=$("$RCLONE" lsf --format "pi" --files-only --separator $'\t' "$REMOTE$search_dir" 2>/dev/null \
    | awk -F'\t' -v b="$base" '$1 == b { print $2; exit }')
fi

if [ -z "$id" ]; then
  notify "Drive上のファイルIDを取得できません"
  exit 1
fi

url="https://drive.google.com/file/d/$id/view"
printf '%s' "$url" | pbcopy
notify "Google Driveリンクをコピーしました"