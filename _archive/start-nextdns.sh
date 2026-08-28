#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start NextDNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🛡️

set -euo pipefail

# RaycastのScript CommandにはTTYがないため、sudoのパスワード入力を行えない。
# 非rootで起動された場合は、macOSの管理者権限ダイアログでこのスクリプト全体を
# rootとして1回だけ再実行する。これにより、状態確認ごとの追加認証を避ける。
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
if [ "$(id -u)" -ne 0 ]; then
    exec /usr/bin/osascript - "$SCRIPT_PATH" <<'APPLESCRIPT'
on run argv
    set scriptPath to quoted form of (item 1 of argv)
    do shell script ("/bin/bash " & scriptPath) with administrator privileges
end run
APPLESCRIPT
fi

if [ -x "/opt/homebrew/bin/nextdns" ]; then
    NEXTDNS_BIN="/opt/homebrew/bin/nextdns"
elif [ -x "/usr/local/bin/nextdns" ]; then
    NEXTDNS_BIN="/usr/local/bin/nextdns"
else
    NEXTDNS_BIN=""
fi

# NextDNS開始スクリプト
# NextDNSが起動してない場合には起動させる、起動している場合は再起動

ensure_nextdns_exists() {
    if [ -n "$NEXTDNS_BIN" ]; then
        return 0
    else
        echo "[ERROR] NextDNSがインストールされていません" >&2
        return 1
    fi
}

# 現在の状態を返す: running | stopped | unknown
get_nextdns_state() {
    local out
    if ! out=$("$NEXTDNS_BIN" status 2>&1); then
        echo "unknown"
        return 0
    fi

    if echo "$out" | grep -Eiq '^\s*running\b'; then
        echo "running"
    elif echo "$out" | grep -Eiq '^\s*stopped\b'; then
        echo "stopped"
    else
        echo "unknown"
    fi
}

# 起動/再起動を状態に応じて実施
reconcile_nextdns() {
    case "$(get_nextdns_state)" in
        running)
            "$NEXTDNS_BIN" restart >/dev/null 2>&1 || {
                echo "[ERROR] NextDNSの再起動に失敗しました" >&2
                return 1
            }
            ;;
        stopped)
            "$NEXTDNS_BIN" start >/dev/null 2>&1 || {
                echo "[ERROR] NextDNSの起動に失敗しました" >&2
                return 1
            }
            ;;
        *)
            echo "[ERROR] 予期しないステータスです" >&2
            return 1
            ;;
    esac
}

# 稼働状態になるまで短ポーリングで待機（最大1秒）
wait_until_running() {
    for _ in $(seq 1 10); do
        if [ "$(get_nextdns_state)" = "running" ]; then
        echo "[INFO] NextDNSが正常に起動され、動作しています"
            return 0
        fi
        sleep 0.1
    done
    echo "[ERROR] NextDNSが正常に動作していません" >&2
    return 1
}

ensure_nextdns_exists
reconcile_nextdns
wait_until_running
