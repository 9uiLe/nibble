# 証跡・PR検査の検証

検査の契約と実行手順は[証跡とPRの検査](review-evidence.md)に定義する。検証日は2026-09-16（JST）、実装ソースは`d79fc1485b521d4ca5044837120e2dc928206ab7`。製品・fixtureの画面実装は変更していない。

## 静的検査と失敗条件

ローカルApple Silicon Macで`nix flake check --no-update-lock-file --print-build-logs`を実行し、workflow-policy・nix-format・swift-library-policy・ios-tooling・documentationの5項目が成功した。Python回帰テストは58件。Nixのlockは更新していない。

| 検査 | 正常系と拒否する条件 |
| --- | --- |
| 文書 | 参照形式リンク、空白を含むパス、日本語・重複見出しを解決。存在しないリンク・見出し、Skillの不正frontmatter、実装規約のSwift違反例を拒否 |
| ソース | 開始・終了・指定revisionの入力を照合。文書のみのコミットを許可し、製品・driver・ツールの追加・変更・削除を拒否 |
| 実行 | 実行中のソース変更を失敗として記録し、manifestを保存。26.5以外のruntime、失敗run、欠けたログ、結果assertionがない処理済みエラーを拒否 |
| 媒体と申告 | hash不一致、空の観測、ローカル・一時署名URL、HEADのみの閲覧申告、動画範囲外の抽出時刻を拒否。単独撮影や別schemeのビルドでソースを保証しない |
| PR | コミットの不足・余分・重複・短縮SHA、空欄・コメントだけの本文、古いhead、未完了チェック、失敗CI、UI対象外の誤った申告を拒否。GitHubの取得件数不足・取得中のpushも拒否 |

共有Skillはskill-creatorの`quick_validate.py`でも検査し、成功した。検証ログはGit管理対象外の`artifacts/knowledge-nix.log`に保存する。

## Apple CLIとsim-useによるfixture検証

macOS 26.2、Xcode 26.5、iOS 26.5（23F77）、iPhone 17 Pro、UDID `853E861F-6244-4F97-8072-A959309107BD`で次を実行した。

```sh
nix develop --command python3 scripts/ios.py smoke \
  --device 853E861F-6244-4F97-8072-A959309107BD --configuration Release
```

runは`20260915T162454Z-smoke-8e07cb`。VerificationAppのReleaseビルド、install・launch、sim-useによる入力、出力の原文一致、静止画、録画の確定とデコードが成功した。開始・終了の入力hash、媒体hashとコマンド結果をmanifestへ保存した。

`check_evidence.py --ref d79fc1485b521d4ca5044837120e2dc928206ab7 --integrity-only`が成功した。run実行時は未コミットの入力を含むため、実行時のHEAD名ではなく、コミット後のファイルhashとの一致でソースを照合している。

`after.png`で日本語・絵文字・改行を含む入力と反映結果を確認し、動画の4.7617秒の抽出フレームで入力欄のフォーカスとキーボードを確認した。動画原本は9.0033秒。動画全編の連続再生、製品MVPの再検証、性能測定は行っていない。fixtureによる基盤の動作確認であり、製品の画面・性能の評価ではない。PRへの媒体アップロードと閲覧確認は未実施で、`review.json`の該当欄を空欄のまま保持する。

## GitHubの読取と必須チェック

`check_pr.py remote --repo 9uiLe/nibble --number 8 --check-ci`で実際のPRの全5コミット・本文・添付欄と、そのheadのcheck runを取得して検査した。既存PRに残っている性能比較の未完了チェックは完了へ変更していない。この読取確認では`--complete`を指定していない。

mainへruleset `main-required-verification`（ID `23468018`）を適用した。GitHub Actionsの`workflow-policy`（integration ID `15368`）を必須化し、baseへの追従を要求する。適用後のAPIで実効ルールを確認し、管理者も含め`current_user_can_bypass: never`であることを確認した。公開状態・投稿制限・他の権限は変更していない。

新しい本文検査を含むUbuntu CIの実行は、このブランチのPR作成後に確認する。ローカルNix検査と、既存PRのCI結果の読取を、新しいUbuntuジョブの実行結果とは扱わない。JSON・申告を偽っていないこと、画像の内容、レビュー担当者の実際のアクセスは機械検査の保証範囲外である。
