# 検証とレビュー基盤の検証記録

[基盤設計](decisions/0001-local-ios-verification.md)と[証跡・PR検査の契約](review-evidence.md)に対する実施結果を記録する。判定日と対象ソースを固定した記録であり、以後のすべてのrevisionの検証済みを意味しない。

## 対象と環境

| 項目 | 条件 |
| --- | --- |
| 検証日 | 2026-09-16（JST） |
| 検査実装のソース | `d79fc1485b521d4ca5044837120e2dc928206ab7` |
| 運用文書・共有Skillのソース | `e0b97481234129c53c5af25c5a920e9c76ee71d7` |
| 対象 | 文書・Swift規約・実行driver・証跡・PRの自動検査、VerificationAppの操作と撮影、GitHubの読取と必須チェック設定 |
| Mac | Apple Silicon、macOS 26.2、Xcode 26.5 |
| Simulator | iPhone 17 Pro、iOS 26.5（23F77） |
| UDID | `853E861F-6244-4F97-8072-A959309107BD` |
| ツール | 対象ソースの`flake.nix`と`flake.lock`、Apple CLI、sim-use 0.14.0 |

製品MVPのUI/UX・性能の評価は、この検証の対象に含めない。製品の実施条件と結果は[MVPの検証記録](mvp-validation.md)を参照する。

## 共通検査と拒否条件

ローカルMacで`nix flake check --no-update-lock-file --print-build-logs`を実行し、workflow-policy・nix-format・swift-library-policy・ios-tooling・documentationの5項目が成功した。Python回帰テストは58件。

| 検査 | 確認した条件 |
| --- | --- |
| 文書 | 参照形式リンク、空白を含むパス、日本語・重複見出しを解決。存在しないリンク・見出し、Skillの不正frontmatter、実装規約のSwift違反例を拒否 |
| ソース | 開始・終了・指定revisionの入力を照合。文書のみのコミットを許可し、製品・driver・ツールの追加・変更・削除を拒否 |
| 実行 | 実行中のソース変更を失敗として記録し、manifestを保存。26.5以外のruntime、失敗run、欠けたログ、結果assertionがない処理済みエラーを拒否 |
| 媒体と申告 | hash不一致、空の観測、ローカル・一時署名URL、HEADのみの閲覧申告、動画範囲外の抽出時刻を拒否。単独撮影や別schemeのビルドではソース照合を不合格にする |
| PR | コミットの不足・余分・重複・短縮SHA、空欄・コメントだけの本文、古いhead、未完了チェック、失敗CI、UI対象外の誤った申告を拒否。GitHubの取得件数不足・取得中のpushも拒否 |

共通検査に含まれる`documentation`が共有Skillのメタデータと参照先を検査する。補助的に、作業環境のskill-creatorの`quick_validate.py`でも検査し、成功した。この補助ツールの導入はリポジトリの検査手順の前提にしない。

ローカルログはGit管理対象外の`artifacts/knowledge-nix.log`に保存した。回帰テストはfixtureと模擬応答で拒否条件を確認するものであり、GitHub実環境で各失敗条件を発生させた記録ではない。

## Apple CLIとsim-useによるfixture検証

対象はVerificationAppのRelease構成。上記のSimulatorで次を実行した。

```sh
nix develop --command python3 scripts/ios.py smoke \
  --device 853E861F-6244-4F97-8072-A959309107BD --configuration Release
```

run IDは`20260915T162454Z-smoke-8e07cb`。ビルド、install・launch、sim-useによる入力、出力の原文一致、静止画、録画の確定とデコードが成功した。開始・終了の入力hash、媒体hash、コマンド結果を`manifest.json`へ保存した。

```sh
nix develop --command python3 scripts/check_evidence.py \
  --run artifacts/ios/20260915T162454Z-smoke-8e07cb \
  --ref d79fc1485b521d4ca5044837120e2dc928206ab7 --integrity-only
```

照合は成功した。run実行時は未コミットの入力を含むため、実行時のHEAD名ではなく、指定コミットのファイルhashとの一致を確認した。

| 確認 | 観測・結果 |
| --- | --- |
| `after.png`の目視 | 日本語・絵文字・改行を含む入力と反映結果を確認 |
| 録画の抽出フレーム | 4.7617秒で入力欄のフォーカスとキーボードを確認 |
| 動画原本 | 9.0033秒。デコード成功 |
| 全編の連続再生 | 未実施 |
| PRへの媒体アップロードとブラウザー閲覧 | 未実施。`review.json`の該当欄は空欄 |

このrunは基盤の操作・撮影の検証であり、製品の画面、IME変換、アクセシビリティ、性能を評価していない。`--integrity-only`の成功を媒体レビュー全体の完了として扱わない。

## GitHubの読取と必須チェック

### PR本文とcheck runの取得

[PR #8](https://github.com/9uiLe/nibble/pull/8)を対象に、次の読取検査を実行した。

```sh
nix develop --command python3 scripts/check_pr.py remote \
  --repo 9uiLe/nibble --number 8 --check-ci
```

全5コミット・本文・添付欄と、そのheadのcheck runを取得して検査が成功した。PR #8には定量的な性能比較の未完了チェックがあるため、この確認では`--complete`を指定していない。本文やチェック状態の編集は行っていない。

この結果はPR #8の状態を取得・検査できたことを示す。検査実装ソース`d79fc1485b521d4ca5044837120e2dc928206ab7`を含むUbuntu CIの実行は未実施であり、ローカルNix検査やPR #8のCI結果から推定しない。

### mainのマージ条件

2026-09-16（JST）にmainへruleset `main-required-verification`（ID `23468018`）を適用し、APIで実効ルールを確認した。

| 設定 | 確認結果 |
| --- | --- |
| 対象と状態 | `refs/heads/main`、active |
| 必須チェック | GitHub Actionsの`workflow-policy`、integration ID `15368` |
| baseへの追従 | 必須 |
| bypass | 空。`current_user_can_bypass: never` |

宣言は[main-ruleset.json](../.github/main-ruleset.json)、設定の確認手順は[GitHubの必須チェック](review-evidence.md#githubの必須チェック)に記載する。この適用確認は、リポジトリの公開状態・投稿制限など他の権限を評価するものではない。

## 保証範囲

回帰テスト、ローカルNix、fixtureの実行、媒体の部分確認、GitHub読取、rulesetの適用は別々の結果である。JSONや申告の真実性、画像の内容、レビュー担当者の実際のアクセスは機械検査の保証範囲外とする。対象ソースや条件が異なる場合は、必要な検査と観測を改めて行う。
