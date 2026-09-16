# TestFlight配布の検証記録

## 対象と状態

2026-09-16、製品ソース`76ebf8256441fc434b1c07f7e27aaef4fb1e2903`に対して署名なし実機archiveを作成した。配布ツールの実装は`codex/testflight-distribution`の変更に含む。製品のSwift・entitlements・Xcode project・SPM lockには差分がない。

| 確認 | 結果 |
| --- | --- |
| 実機向けRelease archive | 成功。Xcode 26.5（17F42）、iPhoneOS 26.5（23F73）、arm64、macOS 26.2（25C56） |
| archiveのメタデータ | 本体`dev.nibble.app`、共有拡張`dev.nibble.app.share`、両方0.1.0 (1)、最低iOS 26.0 |
| 配布用アイコン | 1024×1024、alphaなし。ビルド後のアイコン設定を確認 |
| 配布ツールの回帰検査 | 16件成功。使い捨てのテスト鍵のみで暗号処理を検査。Appleの実際の秘密情報は使用しない |
| Python isolated mode | Nix環境の`python3 -I`で`cryptography`をimport可能 |
| 専用ユーザーの実際の権限・ACL | 未実施。本人によるアカウント作成とセットアップが必要 |
| App ID・App Group・Teamの登録照合 | 未実施。Apple側のCapability設定が必要 |
| 実際のApple API・署名・アップロード | 未実施。API鍵や署名情報へアクセスしていない |
| TestFlightの処理完了・内部グループ・実機インストール | 未実施。配布完了として報告しない |

## アーカイブの条件

`app/Nibble.xcodeproj` / `Nibble` / Release / `generic/platform=iOS`で実行した。`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空の`CODE_SIGN_IDENTITY`と`DEVELOPMENT_TEAM`、`ENABLE_TESTABILITY=NO`を指定した。provisioning更新を許可せず、環境変数はHOME・標準PATH・TMPDIR・LANG・指定されたDEVELOPER_DIRだけを引き継いだ。

共有`Package.resolved`のバージョンのみを使用し、自動解決・更新を無効にした。依存のsource cacheはSPM更新時に取得したローカルcheckoutを再利用した。

- archive：`artifacts/testflight/Nibble-unsigned.xcarchive`
- ビルドログ：`artifacts/testflight/unsigned-archive.log`
- メタデータ検査：`artifacts/testflight/archive-check.json`
- ツール検査ログ：`artifacts/testflight/boundary-tests.log`

Xcodeの結果は`ARCHIVE SUCCEEDED`。本体と共有拡張に対して、AppIntents.frameworkへの依存がないためメタデータ抽出をskipする警告が出た。ビルド失敗ではなく、App Intentsの動作確認済みという意味でもない。

## 配布境界の自動検査

回帰検査は、許可外の操作・任意URL/パス、別UID、広いfile permission、symlink/hard link、書換可能なarchive、異なるbundle ID、versionの不一致、Simulator用成果物、Privacy Manifestの欠落を拒否する。

別UIDの依頼はサービス処理前に拒否し、ネイティブのpeer UID取得も実際のローカルsocket pairで確認した。例外・HTTPエラー本文・未知のAPI属性が応答へ流れないこと、JWTの署名・2分の有効期限・GET scopeを検査した。アップロードのApple CLIはmockで、private snapshotと承認hashの一致、環境変数の限定、標準出力の抑制、timeout後の自動再送拒否を検査した。

これらは別OSユーザーでサービスが稼働した証拠や、Appleがarchiveを受理した証拠ではない。実際のセットアップ後、[初回手順](testflight.md)の順に照会、送信、処理状態、本人の内部グループ、iOS 26.5端末での起動・共有保存を確認する。

## 変更の影響範囲

製品コードとUIは変更していないため、この配布ツール変更に対する画面・動画の追加は対象外。既存の製品操作の確認は[SPM構成の検証](spm-validation.md)に対象ソースと条件を記録している。今回のarchiveで操作や性能を再測定したとは扱わない。

## 共通検査

2026-09-16、`nix flake check --no-update-lock-file --print-build-logs`の全5 checkが成功した。Python回帰テスト81件（配布境界16件を含む）、Swiftソース29件、文書・workflow・Nix書式を確認した。ログは`artifacts/testflight/nix-check.log`。クラウドCIでiOSの署名や実機配布が確認できるとは扱わない。

## 配布手順の参照実装

num-pathの`bcab35964391d104c93ba33c85a40d5615b2ffd9`にある`docs/testflight.md`、`scripts/deploy-testflight.sh`、`.claude/settings.json`のpermissionsを確認した。認証設定・秘密鍵・署名情報の実体は参照していない。

参照実装は、リポジトリ外の認証設定、ClaudeのRead/Bash deny、`xcodebuild archive`と`-exportArchive`による配布を組み合わせる。文書は、同一OSユーザーのため完全な技術的遮断ではないことと、DeveloperロールのAPI鍵にはローカルの配布証明書・profileの事前準備が必要なことを明記している。

nibbleは署名資産の事前準備を手順に取り込み、鍵を持つ処理のOSユーザー分離を維持する。参照実装の`-skipMacroValidation`や認証用shell fileの`source`、生ログ末尾の返却は採用しない。実際の署名準備・API接続は未実施であり、参照実装の成功をnibbleの配布実績として扱わない。
