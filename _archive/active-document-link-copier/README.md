# Active Document GDrive Link Copier

最前面アプリで開いている保存済みファイルが rclone マウント上にある場合、その Google Drive URL をクリップボードにコピーする Raycast Script Command。Excel・Word・PowerPoint はアプリ固有の AppleScript を使い、それ以外の対応エディタは macOS Accessibility の `AXDocument` 属性からファイルパスを取得する。

## 前提

- rclone で全共有ドライブを `AllDrives:`（combine remote）として `~/mnt/gdrive` にマウント済み
- rclone は Google Drive への読み取り権限を持つ OAuth 認証で設定済み
- Raycast の Script Commands に上記スクリプトを `.sh` ファイルとして配置済み

## 初回設定

1. **システム設定 → プライバシーとセキュリティ → アクセシビリティ**で Raycast を許可する
2. **システム設定 → プライバシーとセキュリティ → オートメーション**で Raycast から `System Events` と各 Microsoft Office アプリの操作を許可する

## 仕組み

1. 最前面アプリの bundle ID を確認する
2. Excel・Word・PowerPoint は、各アプリの active workbook / document / presentation から保存パスを取得する
3. その他のアプリは、最前面ウィンドウ（`AXFocusedWindow`）の `AXDocument` 属性（`file://` URL）をローカルパスへ変換する
4. 実体パスを正規化して `~/mnt/gdrive` からの相対パスを求め、`AllDrives:` 上で `rclone lsjson --stat` から実ファイル ID を取得する（取得できない場合は親フォルダ内の名前一致で補完）
5. `https://drive.google.com/file/d/<ID>/view` をクリップボードへコピーする

## 対応範囲・注意

- Office のほか、`AXDocument` を公開する VS Code、CotEditor、BBEdit などの保存済みファイルで動作する
- 未保存ファイル、Webアプリ、ターミナルなどファイル実体を持たない最前面ウィンドウは対象外
- `~/mnt/gdrive` 外のローカルコピーを開いている場合はリンクを取得しない
- 実体パスを正規化して判定するため、firmlink（`/System/Volumes/Data`）やシンボリックリンク経由のパスでも誤判定しない
- 同一 Drive フォルダに同名ファイルが複数ある場合、名前だけでは一意に識別できない
- **リンク生成だけで共有権限は変更しない**。リンク先を開けるかは Google Drive の共有設定に依存する

## 関連スクリプト

- Finder で選択したファイル／フォルダ用：**GDrive Link Copier**
- Finder で選択したファイル／フォルダをブラウザで開く版：**GDrive Opener**