# Raycast scripts

Raycast commands and their local helper scripts are managed from this directory.

## Gemini AI commands

`ai-review-text.sh`、`ai-translate.sh`、`ai-bio-expert.sh` は、`ai-commands/` の共通ランナーから Gemini API を呼び出します。プロンプトは隣接する `prompts` リポジトリのファイルを相対参照します。入力はRaycastのテキスト引数、または起動前アプリの選択範囲です。

初回だけ、Terminalで次を実行してKeychainへ登録してください。キーは引数やログに渡しません。

```sh
./ai-commands/register-gemini-key.sh
```

Keychainのserviceは `com.hnishim.raycast-gemini`、accountはmacOSユーザー名です。Google AI StudioのAuth keyを推奨します。Standard keyを使う場合は、Google Cloud側のAPI有効化・課金・権限設定を確認してください。

共通ランナーは `--prompt-file PATH`、`--model MODEL_ID`、`--output display|display-copy|replace-selection`、`--input-source stdin|selection` を受け付けます。`display` はstdoutのみ（selection入力時は元クリップボードを全type・全itemで復元）、`display-copy` はstdoutと応答のクリップボード設定、`replace-selection` は成功時に応答をクリップボードへ入れて元アプリへ貼り付けます。selection処理の失敗時は元クリップボードを復元します。`replace-selection` はselection入力専用です。現在の3コマンドは置換を行わず、review/translateはdisplay-copy、bio-expertはdisplayです。追加ラッパーは、直下にRaycastメタデータと相対プロンプト解決だけを置き、共通ランナーを呼び出してください。

実行中は、入力・プロンプト・応答などを平文の一時ファイルに保存して処理します。これらは正常終了時と処理可能なエラー終了時に削除し、永続的なログや保存済みの出力は作成しません。SIGKILL、電源断、OSの異常終了などでは一時ファイルが残る可能性があります。異常終了後に残留が疑われる場合は、まず実行時刻とプロセスを確認し、このランナーが作成したことを確認できる一時ディレクトリだけを内容確認後に手動削除してください。`/var/folders` などの親ディレクトリをまとめて削除しないでください。Gemini APIへ送信されるデータの利用条件・保持方針は、利用するGoogle API契約を確認してください。

APIキー未登録、HTTP/APIエラー、モデル不正、候補なし、安全性ブロック、空応答、接続失敗は日本語で表示します。API実行、Keychain登録、Raycastからの選択取得・貼り付け、Swiftによるクリップボード復元はこのリポジトリの静的テストでは確認していません。macOSのアクセシビリティ権限、Keychain/APIの実接続、Raycastの実行経路、対象アプリの状態、実クリップボードの復元は実機で確認してください。
