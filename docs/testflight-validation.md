# TestFlight配布の検証記録

## 対象と状態

2026-09-16、製品ソース`76ebf8256441fc434b1c07f7e27aaef4fb1e2903`に対して署名なし実機archiveを作成した。配布ツールの実装は`codex/testflight-distribution`の変更に含む。製品のSwift・entitlements・Xcode project・SPM lockには差分がない。

| 確認 | 結果 |
| --- | --- |
| 実機向けRelease archive | 成功。Xcode 26.5（17F42）、iPhoneOS 26.5（23F73）、arm64、macOS 26.2（25C56） |
| archiveのメタデータ | 本体`dev.nibble.app`、共有拡張`dev.nibble.app.share`、両方0.1.0 (1)、最低iOS 26.0 |
| 配布用アイコン | 1024×1024、alphaなし。ビルド後のアイコン設定を確認 |
| 配布ツールの回帰検査 | 16件成功。使い捨てのダミー設定・鍵ファイルとApple CLIのmockを使用。実際の秘密情報は使用しない |
| 認証設定の利用可否 | `scripts/deploy-testflight.sh --check-config`は終了コード1。「認証設定は利用できません」の固定メッセージ。値・鍵の内容・詳細な原因は参照していない |
| App ID・App Group・Teamの登録照合 | 未実施。Apple側のCapability設定が必要 |
| 実際のApple API・署名・アップロード | 未実施。Appleへの認証・API接続は行っていない |
| TestFlightの処理完了・内部グループ・実機インストール | 未実施。配布完了として報告しない |

## アーカイブの条件

`app/Nibble.xcodeproj` / `Nibble` / Release / `generic/platform=iOS`で実行した。`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空の`CODE_SIGN_IDENTITY`と`DEVELOPMENT_TEAM`、`ENABLE_TESTABILITY=NO`を指定した。provisioning更新を許可せず、環境変数はHOME・標準PATH・TMPDIR・LANG・指定されたDEVELOPER_DIRだけを引き継いだ。

共有`Package.resolved`のバージョンのみを使用し、自動解決・更新を無効にした。依存のsource cacheはSPM更新時に取得したローカルcheckoutを再利用した。

- archive：`artifacts/testflight/Nibble-unsigned.xcarchive`
- ビルドログ：`artifacts/testflight/unsigned-archive.log`
- メタデータ検査：`artifacts/testflight/archive-check.json`。現在の配布スクリプトでの再検査も成功し、`artifacts/testflight/archive-check-same-user.json`へ保存した。

Xcodeの結果は`ARCHIVE SUCCEEDED`。本体と共有拡張に対して、AppIntents.frameworkへの依存がないためメタデータ抽出をskipする警告が出た。ビルド失敗ではなく、App Intentsの動作確認済みという意味でもない。

## 配布スクリプトの自動検査

回帰検査は、設定の重複・未知の項目・shell式・指定外の鍵パス・広いfile permission・symlinkを拒否し、設定読取時に秘密鍵の内容を開かないことを確認する。設定確認の出力に認証設定の値や例外詳細が含まれないことも検査する。

archiveについて、別のbundle ID、versionの不一致、Simulator用成果物、Privacy Manifestの欠落を検査する。配布について、未commitの変更・Git管理された署名ファイル・同じbuild番号での再実行・同時実行・実行中のソース変更を拒否する。

Apple CLIはmockを使用し、dry-runとuploadの区別、内部専用export設定、IPAがない場合の失敗、固定SPM lock、macro検証の維持、子プロセスの環境変数、失敗・timeout時に生ログを出力しないことを確認する。実際に署名したIPAを生成した証拠や、Appleに受理された証拠ではない。

- 配布テストのログ：`artifacts/testflight/nix-check-same-user.log`
- 現在の配布テスト：`nix develop --command python3 -m unittest discover -s scripts/tests -p test_testflight.py -v`
- 旧ログ`boundary-tests.log`は別ユーザーサービスの実験記録であり、現在の配布スクリプトの検証結果には使用しない。

## 変更の影響範囲

製品コードとUIは変更していないため、この配布ツール変更に対する画面・動画の追加は対象外。既存の製品操作の確認は[SPM構成の検証](spm-validation.md)に対象ソースと条件を記録している。今回のarchiveで操作や性能を再測定したとは扱わない。

## 共通検査

2026-09-16、`nix flake check --no-update-lock-file --print-build-logs`の全5 checkが成功した。Python回帰テスト81件（現在の配布スクリプト16件を含む）、Swiftソース29件、文書・workflow・Nix書式を確認した。ログは`artifacts/testflight/nix-check-same-user.log`。配布launcherのShellCheckを含む最終検査も成功し、`artifacts/testflight/nix-check-same-user-final.log`に保存した。クラウドCIでiOSの署名や実機配布が確認できるとは扱わない。

## 配布手順の参照実装

num-pathの`bcab35964391d104c93ba33c85a40d5615b2ffd9`にある`docs/testflight.md`、`scripts/deploy-testflight.sh`、`.claude/settings.json`のpermissionsを確認した。認証設定・秘密鍵・署名情報の実体は参照していない。

参照実装は、リポジトリ外の認証設定、ClaudeのRead/Bash deny、`xcodebuild archive`と`-exportArchive`による配布を組み合わせる。文書は、同一OSユーザーのため完全な技術的遮断ではないことと、DeveloperロールのAPI鍵にはローカルの配布証明書・profileの事前準備が必要なことを明記している。

nibbleは同じユーザーでの配布、外部の認証設定、直接参照の禁止、署名資産の事前準備を採用する。設定は固定した4項目として解釈し、`source`しない。`-skipMacroValidation`と生ログ末尾の返却は採用しない。実際の署名準備・API接続は未実施であり、参照実装の成功をnibbleの配布実績として扱わない。
