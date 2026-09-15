# 証跡とPRの検査

ソース、実行結果、画像・動画、PR本文を対応付け、取り違えと更新漏れを検出する。補助ツールはNixで固定する。ローカルの記録は`artifacts/`へ保存し、GitHubへ公開する情報は必要な説明とダミーデータの証跡に限定する。

## 自動検査とレビューの分担

| 条件 | 自動検査 | レビューが判断すること |
| --- | --- | --- |
| 実行対象 | 共通iOS CLIが明示UDIDとruntime 26.5を要求。最低対応OSのチェックと分離 | 対象端末・導線が変更の影響をカバーするか |
| 実行ソース | run開始・終了のSHA-256と指定Git revisionを照合。追加・削除も検出 | 仕様と期待結果の妥当性 |
| 画像・録画 | run確定時のSHA-256と媒体、レビュー申告のhashを照合 | 見た目・操作・遷移・応答の品質 |
| コマンド失敗 | runの成否、終了コード、ログ、test summaryを照合 | 失敗原因の切り分けと復旧方法 |
| 閲覧可能性 | 安定したHTTPS URL、ブラウザー読込結果・時刻・閲覧範囲の申告を要求 | 実際の閲覧、個人情報の有無、レビュー担当者のアクセス |
| PR | 必須欄、全コミット表、UI対象ファイルの添付欄、未完了チェック、現在headのCI結果 | 単一目的か、説明が正確か、検証が十分か |
| 文書 | Markdownの相対リンク・見出し、Skill frontmatter、実装規約のSwift記載例 | 新規参加者が背景の会話なしに理解できるか |

機械検査は記録の整合性と申告の形式を検査する。目視やブラウザー操作の実施、測定値の意味、外部URLの永続性を証明しない。申告を自動で「確認済み」に変換しない。

## runのソースと結果

[scripts/ios.py](../scripts/ios.py)を使うrunは、`manifest.json`に`evidence_version: 1`、`files_sha256`、`files_sha256_end`、`media_sha256`を保存する。開始と終了の間で検証入力が変わるとrunを失敗にする。失敗ログと媒体も保存する。

照合範囲はprojectを含む`app/`または`validation/`全体、共有`scripts/`、`flake.nix`、`flake.lock`。Markdownは対象から除く。製品のテスト、Xcode設定、共有lock、driverを含め、CLIから範囲を狭める指定は用意しない。比較対象を変える必要がある場合は、検査と回帰テストの変更としてレビューする。

文書だけのコミットなら、記録した入力と一致する限りiOS実行を再利用できる。開始・終了・媒体hashがない旧形式のrunは、当時の検証記録として保持する。新しい証跡形式で合格させるために、後からhashを付けて当時の一致を推定しない。

```sh
export NIBBLE_RUN='artifacts/ios/対象run'
nix develop --command python3 scripts/check_evidence.py \
  --run "$NIBBLE_RUN" --ref HEAD --integrity-only
```

`--ref`は照合するコミットを指定する。未コミットのソースで実行したrunも、その内容をコミットした後にファイル単位で照合できる。`--integrity-only`は目視・添付の完了を意味しない。

ソースの照合には同じrun内で対象scheme・UDIDへのビルド成功が必要になる。単独の`screenshot`・`record`は撮影した媒体の補助記録であり、既にinstallされたアプリのソースを保証しない。ソースに対応する証跡はビルドを含む`smoke`や製品・研究driverで取得する。

非ゼロ終了を処理するdriverは、該当コマンドの`handled_error`に理由と結果を検証するassertion名を記録する。検査は終了コード1、対応assertionが`true`、run全体が成功した場合に限り、その処理済みエラーを認める。タイムアウトや別の終了コードは認めない。製品の日本語編集メニューfallbackは編集後本文の完全一致に対応付ける。

## 画像・動画のレビュー記録

```sh
nix develop --command python3 scripts/check_evidence.py \
  --run "$NIBBLE_RUN" --init-review
```

`review.json`を新規作成する。既存のファイルを上書きしない。実際に確認・添付する媒体を選び、未確認の媒体は行を除いて`limitations`に記載する。録画を含むrunでは画像と動画の両方を選ぶ。

| フィールド | 記録する内容 |
| --- | --- |
| `reviewer` / `scope` / `limitations` | 確認者、確認範囲、未実施条件・限界 |
| `media[].file` / `sha256` | run内の媒体と自動生成されたhash。別の媒体へ差し替えない |
| `method` | PNGは`image`。動画は抽出フレームの`sampled`または全編を確認した`continuous` |
| `seconds` / `observations` | `sampled`では実際に確認した原本の時刻。観測した表示・操作と問題 |
| `url` | アップロード後の安定したHTTPS URL。署名付きの一時URL・ローカルパスを使わない |
| `access` | `method: browser`、読込を確認した場合の`result: loaded`、タイムゾーン付き`checked_at`、ログイン状態などの`scope` |

ブラウザーでは画像の読込サイズと動画プレーヤーの読込を確認する。HEADの失敗とブラウザーの閲覧結果は別々に記録する。ブラウザーで読み込めても、第三者や未認証ユーザーが閲覧できたとは限らない。

```sh
nix develop --command python3 scripts/check_evidence.py --run "$NIBBLE_RUN" --ref HEAD
```

整合性と申告の形式が通ると`REVIEW.md`を生成する。検証結果やコマンドを改変せず、記入済みの`review.json`を正としてレビュー記録を再生成する。失敗したチェックを通すためにrunの成否や媒体hashを書き換えない。

## PR本文の作成と照合

全コミットの表は取得済みのbase refから生成する。

```sh
git fetch origin
nix develop --command python3 scripts/check_pr.py commits --base origin/main \
  > artifacts/pr-commits.md
```

[PRテンプレート](../.github/pull_request_template.md)の本文へ表を入れ、各コミットの説明を記載する。UI/UXに影響するファイルは、`app/`と基盤・研究アプリのソース・Xcode projectから保守的に判定する。Markdownと`*Tests`ディレクトリは自動判定から除くが、それ以外の変更でもUIへ影響するなら証跡を付ける。

- UI対象は異なる変更前後の画像2点以上と、「画面録画：」以降の動画リンクを必要とする。新規画面は画像1点と「変更前：対象外（新規画面のため）」を記載できる。
- UI対象では対象コミット、端末とiOS 26.5、操作手順を記載する。媒体の内容やコミットへの対応はローカルの証跡チェックとレビューで確認する。
- UI対象外は「対象外：文書のみ」など理由を記載する。性能と未実施項目の欄も残す。

```sh
nix develop --command python3 scripts/check_pr.py local \
  --base origin/main --body-file artifacts/pr-body.md --complete
```

このコマンドはコミット済みの差分を確認し、未コミット変更があれば拒否する。作業ツリーをコミットした後、本文に実際のハッシュを反映して実行する。`--complete`は未完了チェック項目を拒否する。未実施の検証があるPRは作成できるが、マージ前に解決する。

PR作成・更新には`gh pr create/edit --body-file`を使い、アップロード後にGitHubから取得した本文を次の編集元にする。添付APIの可否はNix内の`gh --help`で確認する。

```sh
export NIBBLE_PR='対象PR番号'
nix develop --command python3 scripts/check_pr.py remote \
  --repo 9uiLe/nibble --number "$NIBBLE_PR" --complete --check-ci \
  --snapshot-out artifacts/pr-check.json
```

GitHub APIは読み取りのみ。全コミットと変更ファイルをページングし、不完全な一覧や取得中のhead・本文変更を拒否する。`--check-ci`は現在headのcheck runを検査するため、実行中のCI自身では使わない。添付先の読み込みはブラウザーで別途確認する。

GitHub ActionsはUbuntuで共通検査を実行し、PRでは本文と全コミットの検査も実施する。`opened`・`synchronize`・`reopened`・`edited`・`ready_for_review`で起動し、本文だけの編集でも再検査する。通常のpushと`nix flake check`はネットワークやPRを必要としない。

## GitHubの必須チェック

mainには[rulesetの宣言](../.github/main-ruleset.json)に対応する[main-required-verification](https://github.com/9uiLe/nibble/rules/23468018)を適用する。GitHub Actions（integration ID 15368）の`workflow-policy`成功とbaseへの追従を要求し、管理者を含めてバイパス対象を設けない。ジョブ名を変更する場合はrulesetとの整合も維持する。

JSONは設定の宣言であり、ファイルをマージするだけではGitHubへ再適用されない。設定変更時は既存rulesetのIDを確認し、他の条件を保持して更新する。更新後はAPIで実効ルールを読み取って照合する。

```sh
nix develop --command gh api repos/9uiLe/nibble/rules/branches/main
```

実施した検査と適用状態は[検証記録](review-tooling-validation.md)を参照する。
