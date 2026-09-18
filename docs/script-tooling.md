# 開発スクリプトの処理と表示

開発スクリプトは検査・ビルド・操作・配布を実行し、hamioは進捗と結果を表示する。処理の成否、再試行、権限、実行記録は呼出元が管理する。共通の[表示Adapter](../scripts/script_ui.py)がPythonとhamio API v1を接続する。

## 責務と依存方向

| 層 | 担当するもの | 入口 |
| --- | --- | --- |
| 純粋な検査・照合 | 違反、差分、集計値を返す。表示プロセスを起動しない | Swiftの構文規約、文書解析、証跡・PR照合、Rive契約 |
| CLI・実行driver | 引数、処理順序、端末lock、ログ、結果ファイル、終了コード | `scripts/check_*.py`、`ios.py`、`testflight.py` |
| 表示Adapter | 公開可能なメッセージをhamioの表示部品へ変換し、形式・タイムアウト・障害を扱う | `scripts/script_ui.py`の`Reporter` |
| ターミナル表示 | JSON契約の検査、人向けの整形、機械向けの応答 | Nixで固定したhamio |

`message`は通知、`result`は呼出元が判定した結果、`check`は検査結果と違反一覧、`step`は開始と終了を表示する。`step`の例外はそのまま呼出元へ戻し、表示には渡さない。表示処理から業務関数を呼び出すAPIや自動再試行は設けない。

### スクリプトごとの適用範囲

| 対象 | 表示とデータ |
| --- | --- |
| `check_docs.py`、`check_ui_design.py` | 結果・snapshotのJSONはstdout、要約は共通表示。共通UI設計Moduleはhamioに依存しない |
| `check_swift_policy.py`、`check_workflows.py`、`check_pr.py` | 結果と診断は共通表示。`check_pr.py commits`のMarkdown表はstdout |
| `check_evidence.py` | 照合結果JSONはstdout、記入欄作成と検査の要約は共通表示 |
| `rive_assets.py` | 生成工程と契約検査の結果を共通表示。正本・生成物・manifestはファイルへ保存 |
| `ios.py` | 各コマンドと録画の開始・終了、runの結果と保存先を共通表示。doctor/devices/uiはJSON、createはUDIDをstdoutへ返す。内部の画面観測はrun内のJSONに記録 |
| `check-mvp-ui.py`、`check-interface-ui.py`、`check-about-ui.py`、`validation/check-research-ui.py` | 共通の`Run`を通じて工程表示と証跡を利用する |
| `testflight.py` / `deploy-testflight.sh` | 固定した工程名・公開メタデータ・安全な診断だけを共通表示。archive-checkのJSONはstdout |
| `benchmark-store.py`、`validation/check-research-sdk.py` | 測定後の進捗・コンパイル結果を共通表示。測定値・コマンド詳細は結果ファイルへ保存 |
| `benchmark_docs.py`、`validation/check-research-processes.py`、`video_frames.swift` | 測定JSON・保存先・媒体を返す。計測中に表示Adapterを呼ばない |
| `swift_task_boundary.py`、`swift_equatable_policy.py`、`verification_evidence.py`、`tools/ui-design/` | 再利用する解析・照合処理と独立CLI。製品固有の表示依存を追加しない |

## stdout・stderr・成否

stdoutは呼出元が受け取るデータ専用とする。hamioの応答も一度Adapterで捕捉し、進捗・結果・診断はstderrへ送る。既存の結果JSON、PRコミット表、生成物とmanifestの形式は各CLIが所有する。人向けの成功文や診断をstdoutから読む処理は、終了コードと結果JSONを使用する。

| 条件 | 表示形式 |
| --- | --- |
| stderrがTTY、`CI`が未設定または空 | hamioの人向け表示 |
| 非TTYまたはCI | hamioのJSON応答をstderrへ1件ずつ出力 |
| `NIBBLE_UI_FORMAT=human` / `json` | 指定した形式を優先 |
| hamio未導入・失敗・不正応答・3秒の期限超過 | 警告を1回出し、そのPythonプロセスでは`display: fallback`を持つJSONをstderrへ出力 |

エージェントとCIは`NIBBLE_UI_FORMAT=json`を指定する。対話入力を待つフォームは使わない。`NO_COLOR`と`TERM=dumb`では色を付けない。fallbackは端末制御文字をJSONでエスケープし、hamioからの生のエラー出力は転送しない。

hamioの終了コード0と`status: ok`は表示の成功を意味する。業務上の失敗は`result.success: false`と元のスクリプトの非ゼロ終了で表す。表示障害で、完了済みの署名やアップロードを再実行しない。端末の切断でも処理を再試行せず、呼出元のmanifestと終了状態を保つ。

工程の境界で`render`を使う。高頻度の進捗更新や入力待ちがないため、常駐するstreamプロセスの所有・排他・後始末を増やさない。各表示は3秒以内で終了し、長い診断はUTF-8の上限を満たす部品へ分割する。表示の起動時間はコマンドの実測時間に含めず、エンドツーエンドの待ち時間には含まれる。

```sh
nix develop
mkdir -p artifacts
NIBBLE_UI_FORMAT=json python3 scripts/check_docs.py \
  > artifacts/docs-result.json 2> artifacts/docs-display.jsonl

NIBBLE_UI_FORMAT=human python3 scripts/check_swift_policy.py
```

Nix自体の診断を表示JSONと混ぜないよう、上の例ではshellに入ってからPythonを実行する。表示形式の指定は、結果JSONのschemaや検査の成否を変更しない。

## 秘密情報の境界

Adapterに渡してよいのは公開可能な文言だけである。任意の文字列から秘密を判別して除去する機能は持たない。認証を伴うコマンド引数、環境変数の辞書、認証設定、配布のネイティブログ・例外全体を渡さない。

配布スクリプトは認証処理と保護されたログを所有する。hamio子プロセスへ継承する環境は`PATH`、`LANG`、`LC_ALL`、`TERM`、`NO_COLOR`だけとし、認証関連の環境変数やHOMEを渡さない。`python3 -I`による起動を維持し、配布スクリプトは自身に隣接するレビュー済みのAdapterを絶対位置から読み込む。cwdやPYTHONPATHをimport先に追加しない。

この境界は同一ユーザー内の運用・コード契約であり、OSによる秘密情報の読取権限分離ではない。[TestFlightの秘密情報規約](testflight.md)を合わせて適用する。

## Nixでの導入と保守

`flake.nix`のhamio inputと`flake.lock`で製品と配布定義を固定する。hamioのNix定義は公開バイナリ・checksum・SBOM・noticesのhashを照合し、展開した実行ファイルのhashも検査する。hamio側のnixpkgsは提供元のlockを維持し、nibble側のnixpkgsへ`follows`させない。

採用版はhamio 0.1.0 / API v1。パッケージ定義は`dd8c86c6923f692ef183152958147bf095e85daa`に固定する。製品の版とNix定義のrevisionは別であり、更新時には両方を確認する。Nix利用では`.hamio-version`や独立インストーラーによる二重管理を行わない。

hamioの提供対象はmacOS arm64、Linux arm64 / x86_64。Intel Macのシステム宣言は維持し、AdapterはJSON fallbackを利用する。ただし現在のtree-sitter-language-packはIntel Mac非対応であり、同環境のNix検査全体は成立していない。対応環境のNix回帰テストは実hamioがない場合に失敗し、fallbackだけの成功で導入を検証済みにしない。

```sh
nix flake update hamio
nix develop --command hamio --version
nix develop --command hamio capabilities
nix flake check --no-update-lock-file --print-build-logs
```

更新時は製品版、API、対象OS・CPU、固定hash、同梱ライセンス、lock差分、成功・業務失敗・表示障害・秘密情報境界を確認する。取り消す場合はレビュー済みのlockへ戻す。hamio本体のMITと同梱部品のnoticesはNix store内の`share/hamio/`へ保持される。これは開発ツールの依存であり、Swift Package構成や製品アセットの構成は変更しない。

## 検査の保証範囲

[表示のテスト](../scripts/tests/test_script_ui.py)はAPI応答、stdoutの純粋性、元の終了コード、文字列上限、表示障害、環境の制限、隔離import、実hamioによるCLI接続を検査する。配布の回帰テストは一時ディレクトリの偽認証情報だけを使う。実際の署名・送信成功は、このテストから推定しない。

表示を変更しても、iOSの端末lock、コマンド詳細・所要時間、ソース・媒体hash、証跡の照合条件は[検証基盤の契約](decisions/0001-local-ios-verification.md)に従う。確認した実行環境と未実施条件は[導入検証](hamio-validation.md)に記録する。

## 一次資料

2026-09-18に、固定したNix定義と公開版0.1.0の実行で確認した。

- [hamioのAPI契約](https://github.com/9uiLe/hamio/blob/dd8c86c6923f692ef183152958147bf095e85daa/docs/api.md)
- [hamioのNix導入手順](https://github.com/9uiLe/hamio/blob/dd8c86c6923f692ef183152958147bf095e85daa/docs/distribution.md#nix-で導入する)
- [固定した公開資産とhash](https://github.com/9uiLe/hamio/blob/dd8c86c6923f692ef183152958147bf095e85daa/nix/release.json)
