#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop NextDNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ⛔

set -euo pipefail

# NextDNS停止スクリプト
# 状態を確認し、稼働中なら停止して停止完了を検証

ensure_nextdns_exists() {
    if command -v nextdns >/dev/null 2>&1; then
        return 0
    else
        echo "[ERROR] NextDNSがインストールされていません" >&2
        return 1
    fi
}

# 現在の状態を返す: running | stopped | unknown
get_nextdns_state() {
    local out
    if ! out=$(sudo nextdns status 2>&1); then
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

# 状態に応じて停止処理
reconcile_stop() {
    case "$(get_nextdns_state)" in
        running)
            sudo nextdns stop >/dev/null 2>&1 || {
                echo "[ERROR] NextDNSの停止に失敗しました" >&2
                return 1
            }
            ;;
        stopped)
            echo "[INFO] NextDNSはすでに停止しています"
            return 0
            ;;
        *)
            echo "[ERROR] 予期しないステータスです" >&2
            return 1
            ;;
    esac
}

# 停止状態になるまで短ポーリングで待機（最大1秒）
wait_until_stopped() {
    for _ in $(seq 1 10); do
        if [ "$(get_nextdns_state)" = "stopped" ]; then
            echo "[INFO] NextDNSは停止しています"
            return 0
        fi
        sleep 0.1
    done
    echo "[ERROR] NextDNSが停止していません" >&2
    return 1
}

ensure_nextdns_exists
if [ "$(get_nextdns_state)" = "running" ]; then
    reconcile_stop
    wait_until_stopped
else
    # running以外: reconcile_stopがメッセージを出力する
    reconcile_stop
fi
