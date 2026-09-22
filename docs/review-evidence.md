# 証跡とPRの検査

この手順は、実行したソース・結果・画像・録画を照合し、レビュー記録とPRを作成するためのもの。検査の設計と保証範囲は[検証とレビュー基盤](architecture/verification.md)、ビルド・操作・撮影は[ローカルiOS検証](ios-verification.md)に定義する。

## 前提と記録の役割

[セットアップ](../README.md#セットアップ)を完了し、リポジトリルートでコマンドを実行する。補助ツールはNixのGit・GitHub CLI・Pythonを使う。iOSの操作には、対象projectの設定と明示したiOS 26.5のUDIDが必要になる。

個別のiOSコマンドの実行記録をrunと呼ぶ。run IDは`<UTC日時>-<コマンド>-<ID>`で、結果はGit管理対象外の`artifacts/ios/<run ID>/`に保存する。`verify.py`による一連の検証実行は、計画・工程結果と複数runへの参照を`result.json`に持つ。結果から対象runを選び、以下の手順でレビュー対象と照合する。

| ファイル | 内容 | 記録する主体 |
| --- | --- | --- |
| `manifest.json` | 対象ソース・端末・ツール・成否・終了コード・ファイルhash | 実行driver |
| ログ・xcresult・結果JSON | 実行と期待結果の照合の根拠 | 各コマンドとdriver |
| PNG・MP4・`video-frames/` | 画面、時間経過、抽出フレームと実際の時刻 | Apple CLIとSwift |
| `review.json` | 確認した媒体、観測、確認方法、未実施条件、添付・閲覧の情報 | 確認者 |
| `REVIEW.md` | 実行情報とレビュー記録を人が読める形で表示 | driverが記入欄を作り、証跡検査が申告から再生成 |

検証結果、目視、動画再生、アップロード、閲覧確認はそれぞれ独立した確認になる。ファイルの生成やデコードの成功を理由に、目視・閲覧を完了へ変更しない。

## runのソースと結果

### 1. ビルドと期待結果を含むrunを取得する

[検証計画の実行結果](ios-verification.md#変更から検証を実行する)から、対象工程の`steps[].runs`を確認する。個別に実行する場合は、製品の`app/project.json`、fixtureの`validation/project.json`を[対象別手順](ios-verification.md#検証対象の切り替え)で選ぶ。画面の期待結果は各対象のUI driverで判定する。

ソース照合には、同じrun内で対象scheme・UDIDへのビルド成功が必要になる。単独の`screenshot`・`record`は、install済みアプリのソースとの対応を持たない補助的な撮影記録として扱う。

実行中は検証入力を編集しない。共通driverは開始・終了時の入力とrun確定時の媒体hashを保存し、入力が変化したrunを失敗にする。失敗ログと媒体は保存する。

### 2. 対象コミットと照合する

```sh
export NIBBLE_RUN='artifacts/ios/対象run'
nix develop --command python3 scripts/check_evidence.py \
  --run "$NIBBLE_RUN" --ref HEAD --integrity-only
```

`--ref`は照合するGit revisionで、省略時はHEAD。未コミットのソースを実行した場合は、その内容をコミットしてから照合する。実行時のコミット名と照合先が異なっても、検証入力のファイル内容が一致すれば使用できる。

| 検査 | 合格条件 |
| --- | --- |
| 証跡形式 | `evidence_version: 1`と、開始・終了・媒体のhashを持つ |
| runの結果 | `status: passed`、対象UDID、iOS 26.5とOS build、実行コマンドとログを持つ |
| ソース | `files_sha256`・`files_sha256_end`・指定revisionの検証入力が一致 |
| ビルド | 同じrunの対象scheme・UDIDへの`xcodebuild build/test`が成功 |
| テスト結果 | `test`またはtest summaryを持つrunは、成功したテストが1件以上あり、失敗がない |
| 媒体 | run確定時の`media_sha256`と、保存された媒体の追加・削除・内容に相違がない |

検証入力は、projectを含む対象ルート（`app/`、`validation/`）全体、共有`scripts/`、描画基盤の`runtime/`、`flake.nix`、`flake.lock`。Markdownを除き、ソース・テスト・Xcode設定・共有lock・driver・ツールの追加・変更・削除を照合する。CLIから検査範囲を狭めることはできない。

文書のみの変更で入力が一致する場合はrunを再利用できる。必要な形式やhashが欠けた記録はソース照合に使用できない。事後にhashを推定して実行時の記録に加えない。

コマンドの終了コードは0を要求する。driverが既知の終了コード1を処理する場合に限り、`handled_error`の理由とassertion名、対応するassertionの`true`、run全体の成功を確認する。タイムアウトや他の終了コードは認めない。日本語編集メニューのfallbackは、編集後にコピーした本文の完全一致と対応付ける。

`--integrity-only`の成功は、ソース・実行記録・媒体が整合することを示す。目視や添付の完了を示すものではない。

## 画像・動画のレビュー記録

レビューでは、対象の画面・状態・設計IDと確認項目を決め、媒体を開いて観測した内容を記録する。実行時のPNG・MP4を原本として扱い、閲覧用に縮小・切出しした画像を使う場合も、確認範囲を原本へ対応付ける。操作先や入力値の照合には[画面要素の要約と差分](ios-verification.md#画面要素の要約と差分)を使う。

### 1. 記入用ファイルを作る

```sh
nix develop --command python3 scripts/check_evidence.py \
  --run "$NIBBLE_RUN" --init-review
```

`review.json`に記入欄を作成する。既存ファイルは上書きしない。確認・添付する原本を選び、対象外の媒体の行は削除する。画像を1点以上選び、録画を含むrunでは動画も選ぶ。記入欄の生成は、媒体の確認や合格判定を行わない。

### 2. 媒体を確認する

確認項目に対応する状態を選び、画像は全体の配置から必要な細部へ、録画は対象の時刻と遷移へ進む。同じ原本hash・確認範囲・確認項目について観測済みなら、その記録を参照できる。別状態や別の確認項目、見落としの懸念がある場合は該当箇所を開く。

#### 画像の全体と細部の確認

AIが読む画像には、原本から作る閲覧用画像（preview）を使える。まず対象状態の全体像で配置・欠落・大きな重なりを確認し、小さい日本語、余白、境界、アイコン、文字切れなどは必要な領域の原寸画像で確認する。各画面・状態に必要な確認を行い、縮小で判断できない項目は細部の確認へ進める。

閲覧用画像は[`inspect_ui.py image`](simulator-inspection.md#閲覧用画像の作成)で作る。長辺上限の既定は960px。原寸で確認する領域には、その長辺以上の上限を指定する。出力JSONの`preview.path`を画像ツールで開く。

原本と派生画像のhash・寸法・切出し範囲・倍率は、`record`が示す`preview.json`で確認する。画像生成の成功と目視の実施は別に記録する。画像内のpixel座標とSimulatorのpoint座標は異なるため、previewの座標をtapへ直接渡さない。

#### 録画の時刻と遷移の確認

抽出フレームの実際の時刻は`video-frames/video.json`で確認する。抽出PNGにも`inspect_ui.py image`を使えるが、フレームの確認はその時刻の表示だけを対象とする。代表3フレームで確認できない遷移には追加時刻を選び、ちらつき・滑らかさ・一時的な欠落は連続再生で確認する。性能の数値評価には[性能手順](performance-verification.md)を使う。

全編を確認した場合に限り`continuous`を記載する。抽出時刻を確認した場合は`sampled`とし、実際に見た原本の時刻を残す。原本とブラウザーで再生時間が異なる場合は、それぞれの観測として記録する。

### 3. 観測を記録する

`review.json`に、確認した媒体、方法、観測、未確認条件を記載する。

| フィールド | 記載内容 |
| --- | --- |
| `reviewer` / `scope` / `limitations` | 確認者、確認範囲、未実施条件と限界 |
| `media[].file` / `sha256` | run直下にある原本PNG・MP4の名前と生成されたhash |
| `method` | PNGは`image`。動画は抽出確認の`sampled`、または全編確認の`continuous` |
| `seconds` / `observations` | `sampled`では原本の実際の確認時刻。観測した表示・操作・問題 |
| `url` | 原本のアップロード先を示す安定したHTTPS URL |
| `access` | 公開先の閲覧方法・結果・時刻・ログイン状態などの条件 |

previewを使った場合は、`observations`に`preview.json`の記録先、表示寸法、切出し範囲と観測を記す。未確認領域や縮小で判断できない項目は`limitations`へ残す。媒体の照合・添付・公開には原本を使う。

### 4. アップロード先の閲覧を確認する

ダミーデータの媒体をPRへ添付するか、レビュー担当者が閲覧できる保存先へアップロードする。ブラウザーで画像の読込サイズと動画プレーヤーの読込を確認し、`access`に次を記録する。

- `method: browser`
- 読込を確認した場合の`result: loaded`
- タイムゾーン付きの`checked_at`
- ログイン状態や閲覧者などの`scope`

未認証のHEADとブラウザーでの閲覧は別の確認になる。HEADの403だけで添付失敗を判定しない。ログイン中に閲覧できた結果から、未認証ユーザーのアクセスを推定しない。`url`にはブラウザー用の一時署名URL、ローカルパスを使わない。

### 5. 記録を照合する

```sh
nix develop --command python3 scripts/check_evidence.py --run "$NIBBLE_RUN" --ref HEAD
```

runの整合性に加え、媒体hash、確認方法、動画の確認時刻、観測と閲覧の申告形式を検査し、`review.json`から`REVIEW.md`を生成する。実行結果やコマンドは変更しない。未記入欄があれば未完了として扱い、検査を通すために実施していない確認を記入しない。

## PR本文の作成と照合

### 1. 全コミットの表と本文を用意する

```sh
git fetch origin
mkdir -p artifacts
nix develop --command python3 scripts/check_pr.py commits --base origin/main \
  > artifacts/pr-commits.md
```

[PRテンプレート](../.github/pull_request_template.md)へ表を入れ、各コミットの説明を記載する。本文は`artifacts/pr-body.md`などのファイルへ保存する。必須欄は目的・背景、アウトカム、変更内容、スクリーンショット・画面録画、検証結果、レビュー前の確認。コメントやコード例だけで欄を埋めない。

| 条件 | 必要な記載 |
| --- | --- |
| 全PR | 全コミットの40桁SHAと説明、実行した検証、性能、未実施項目・残る制約、チェックリスト |
| UI対象 | 変更前後の画像2点以上、「画面録画：」以降の動画リンク、対象コミット、端末とiOS 26.5、操作手順 |
| 新規画面 | 画像1点以上と「変更前：対象外（新規画面のため）」、動画と対象条件 |
| UI対象外 | 「対象外：文書のみ」などの理由。証跡欄は残す |

画像はMarkdownの画像リンク、録画はMarkdownのHTTPSリンクを使用する。自動判定は`app/`、`validation/VerificationApp/`とfixtureのXcode projectをUI対象とし、Markdown、名前が`Tests`で終わるディレクトリ、`TestSupport`ディレクトリを除く。この判定に含まれない変更でも、UIへ影響する場合は証跡を付ける。

### 2. コミット済みの差分と照合する

```sh
nix develop --command python3 scripts/check_pr.py local \
  --base origin/main --body-file artifacts/pr-body.md --complete
```

作業ツリーに未コミット変更がある場合は拒否する。本文の表には、base以降の全コミットを重複なく記載する。`--complete`は未完了チェック項目も拒否する。必要な検証が未完了のPRは、マージ前にその条件を解決する。

### 3. PRを作成・更新する

GitHubへの作成・更新は`gh pr create/edit --body-file`で行う。作成時はbaseとhead、更新時は対象PRを明示する。`nix develop --command gh pr create --help`で`--attach`の対応を確認し、対応する場合は媒体の原本を添付する。CLIが添付に対応しない場合はGitHubのブラウザー添付を使う。

アップロード後はGitHubから本文を取得し、その内容を編集元にする。ローカルパスの本文で上書きすると添付URLが失われるため、公開済みのURLを保持する。

### 4. GitHubの現在の状態を照合する

```sh
export NIBBLE_PR='対象PR番号'
nix develop --command python3 scripts/check_pr.py remote \
  --repo 9uiLe/nibble --number "$NIBBLE_PR" --complete --check-ci \
  --snapshot-out artifacts/pr-check.json
```

全コミットと変更ファイルをGitHub APIからページングして取得し、件数不足や取得中のhead・本文変更を拒否する。`--check-ci`は取得したheadのcheck runが1件以上あり、すべて成功していることを確認する。検査コマンドはGitHubを読み取るだけで、PRを作成・編集・マージしない。

GitHub ActionsはUbuntuでNixの共通検査を実行し、PRイベントでは本文を`--complete`で検査する。PR作成、push、再開、本文編集、draft解除で再実行する。実行中のCIから自身の完了を待つ`--check-ci`は呼ばない。共通検査そのものはGitHub認証やPRを必要としない。初回のNix依存取得にはネットワークが必要になる。

## GitHubの必須チェック

mainには[rulesetの宣言](../.github/main-ruleset.json)に対応する[main-required-verification](https://github.com/9uiLe/nibble/rules/23468018)を適用する。GitHub Actions（integration ID `15368`）の`workflow-policy`成功とbaseへの追従を要求し、管理者を含むバイパスを設けない。

宣言JSONをマージするだけではGitHubの設定は更新されない。設定変更時は既存rulesetのIDと条件を確認して更新し、実効ルールを読み取って宣言と照合する。ジョブ名を変更する場合も両方をそろえる。

```sh
nix develop --command gh api repos/9uiLe/nibble/rules/branches/main
```

## 検査結果の扱い

自動検査はソース・実行記録・媒体の整合性と、申告の形式を確認する。記録の真実性、目視やブラウザー確認の実施、画像の内容、UX品質、URLの永続性は証明しない。PR検査はGit管理対象外のローカルrunを取得しないため、証跡照合の結果もPRへ明記する。

レビューでは、影響する導線を検証したか、対象コミットと媒体が対応するか、閲覧可能か、未実施条件が残るかを判断する。CI成功の確認は、最終headに対して行う。
