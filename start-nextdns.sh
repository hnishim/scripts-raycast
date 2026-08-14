#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start NextDNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🛡️

set -euo pipefail

# NextDNS開始スクリプト
# NextDNSが起動してない場合には起動させる、起動している場合は再起動

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

# 起動/再起動を状態に応じて実施
reconcile_nextdns() {
    case "$(get_nextdns_state)" in
        running)
            sudo nextdns restart >/dev/null 2>&1 || {
                echo "[ERROR] NextDNSの再起動に失敗しました" >&2
                return 1
            }
            ;;
        stopped)
            sudo nextdns start >/dev/null 2>&1 || {
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
