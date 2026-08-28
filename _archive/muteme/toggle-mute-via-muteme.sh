#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Togge Mute via MuteMe
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🎙️

#!/bin/bash

# エラーが発生したらスクリプトを終了する
# set -e
# --- 1. メインディスプレイの横幅を取得 --- system_profilerの結果から解像度の行を抽出し、awkで2列目（横幅）を取り出し、head -n 1で最初のディスプレイの幅だけを取得
display_width=$(system_profiler SPDisplaysDataType | grep "Resolution:" | awk '{ print $2 }' | head -n 1)

# --- 2. メインディスプレイがRetinaか否かを確認 --- system_profilerの結果の最初の解像度行に"Retina"が含まれるかチェック grep -q は結果を表示せず、一致したかどうかを終了ステータスで示す (0なら一致)
system_profiler SPDisplaysDataType | grep "Resolution:" | head -n 1 | grep -q "Retina"
is_retina=$? # 直前のコマンドの終了ステータスを取得 (0ならRetina)

calculated_width=0

if [ "$is_retina" -eq 0 ]; then
    # --- Retinaの場合: 横幅を1/2にする --- 取得した幅を整数として計算
    calculated_width=$((display_width * 1440 / 2560))
    echo "Retinaディスプレイを検出しました。計算上の幅: $calculated_width (元の $display_width を1440/2560にしました)"
else
    # --- Retinaでない場合: 横幅はそのまま ---
    calculated_width=$display_width
    echo "非Retinaディスプレイのようです。計算上の幅: $calculated_width (元の幅そのままです)"
fi

# --- 3. その数から180を引く ---
x=$((calculated_width - 180))

echo "最終的な x の値: $x"

# --- 4. cliclick コマンドを実行 --- cliclick -r はカーソル位置からの相対座標 cliclick dc:x,y はディスプレイ中央からの相対座標 (こちらの方が固定しやすいかも) ご要望に合わせて dc:x,10 を実行します (ディスプレイ中央から右にx、下に10ピクセルの位置)
echo "cliclick dc:$x,10 を実行します..."

# cliclickコマンドが存在するかチェック (任意だが推奨)
if command -v cliclick > /dev/null; then
    cliclick dc:$x,12
    echo "cliclick コマンドを実行しました。"
else
    echo "エラー: cliclick コマンドが見つかりません。インストールしてください。" >&2
    exit 1 # エラー終了
fi

exit 0 # 正常終了