# 開発スクリプトの設計

nibbleの開発スクリプトは、検査、ビルド、Simulator操作、観測データの加工、アセット生成、配布を実行する。人と自動処理が同じコマンドを使えるよう、CLIが入力を受け取り、結果データ・表示・実行記録を用途に応じて出力する。

処理中の工程や成否を表示するため、ターミナル表示ツールのhamioを使う。Python側の接続層である[表示Adapter](../scripts/script_ui.py)が、公開可能な文言をhamioのAPIへ渡す。入力の解析、処理順序、成否の判定、再試行、権限、結果データの出力と保存は各スクリプトが担当する。

この文書は構成と実装契約を定義する。コマンドの入口は[開発ガイド](../CONTRIBUTING.md)を参照する。

## 構成と責務

| 構成 | 責務 | 実装 |
| --- | --- | --- |
| 解析・照合・変換処理 | 入力を検査し、違反・差分・集計値・派生データを返す | Swift構文規約、文書解析、証跡・PR照合、画面要素の要約、画像変換、Rive契約、UI設計Module |
| CLI・実行driver | 引数、処理順序、端末の排他制御、ログ、結果ファイル、終了コードを管理する | `verify.py`、`ios.py`、`inspect_ui.py`、対象別driver、`benchmark_verification.py`、`scripts/check_*.py`、`testflight.py`など |
| 表示Adapter | 表示内容を組み立て、形式の選択、応答の検査、表示障害への対処を行う | `scripts/script_ui.py`の`Reporter`と共有インスタンス`ui` |
| 表示プロセス | 表示定義を検査し、人向けの整形またはJSON応答を返す | Nixで固定したhamioの`render`コマンド |

CLIは処理結果から終了コードを決め、必要なデータを保存し、表示Adapterへ要約を渡す。解析・照合・変換処理は表示プロセスを起動しない。再利用可能な`tools/ui-design/`は独自のCLIと出力契約を持ち、nibble側の`check_ui_design.py`が表示を接続する。

複数工程を実行するCLIは、個別コマンドの結果と自身の実行範囲を対応付けて保存する。iOS検証では`verify.py`が計画と工程結果、`ios.py`が個別run、測定CLIがサイクルと集計値を所有する。相互の参照と保証範囲は[検証基盤の設計](architecture/verification.md)に従う。

表示の単位は、利用者が進行を追う工程の開始・終了と検査結果とする。内部の高頻度処理は記録を保存し、外側の工程で要約する。iOS driverのPID照合は操作前後に実行してログと成否を残し、進捗表示を対応するUI工程へまとめる。表示粒度によってクラッシュ判定や失敗の扱いを変えない。

単発の`render`を使うため、表示用の常駐プロセス、更新キュー、入力待ちの管理は不要である。高頻度の計測ループやアプリのView更新から表示Adapterを呼ばない。

## Simulator操作の共通境界

端末の排他は`ios.simulator_lock`、runのログ・媒体・ソース照合と成否は`ios.Run`、OSの編集メニューを経由した入力の確定は`Run.paste_text`、本体・共有エディターのフォーカス・表示切替・置換は`product_ui.ProductRun`が所有する。UI driverは到達したい状態のpredicateを`Run.wait_ui`へ渡す。空の遷移状態とsim-useが画面切替中に返すAX変換不可の結果だけを有限回待つ。後者は結果JSONから専用の例外に分類し、各試行の失敗をrunへ記録する。ほかのツールの失敗や対象processの終了はその場で失敗にする。置換は長押しで開いたOSの「すべてを選択」と「カット」を観測して操作し、ペースト後の入力値を確認する。検証用の入力例は短文で、長押しできる行末の空間を持つ。フォーカスによるスクロール後は欄と固定操作の矩形を再取得し、可視領域を使う。

`ProductRun.workspace()`は設定階層から作業画面へ戻り、必要な場合だけ検索語を消す。`open_settings()`は作業画面の設定入口から階層移動する。driverは作業画面の検索欄を直接観測して入力する。保存する画面要素の原本へ識別子を補わない。

Markdownの表示切替は、観測した`editor.mode`のTabGroup、または「入力」「プレビュー」のRadioButtonへ対応付ける。原本には補助の識別子を書き込まない。画面ごとの期待値と保存後の全バイト比較はscenarioが所有する。

`Run.finish`はerrorがNoneの場合だけ成功にできる。メッセージの空の例外や中断も失敗として記録し、媒体・終了時ソース・失敗工程を残す。測定も中断前のサンプルを保存する。失敗runを上書きせず、追加実行には別の出力先を使う。

## 入力とコマンドの案内

CLIは引数で対象・操作・出力先を受け取り、指定された設定やデータファイルを読み込む。入力形式と有効値を検査してから業務処理を開始する。Python CLIの引数解析にはargparseを使い、`--help`は標準出力、引数の構文エラーは標準エラー出力へargparseが直接表示する。この段階ではhamioを呼ばない。処理開始後の診断は表示Adapterへ渡す。

`verify.py`は計画保存の`plan`、実行の`run`、結果の読取の`status`をsubcommandとして定義する。各操作が受け付ける引数だけを公開し、比較元のコミットと保存済み結果は排他的に指定する。計画・実行は新しい出力ディレクトリを所有し、状態確認はファイルを書き換えない。引数と結果の項目は[検証手順](ios-verification.md#変更から検証を実行する)に定義する。

`inspect_ui.py`の入力は、`tree`では保存済みのsim-use JSON、`image`ではPNGと出力ディレクトリである。対象の選択や表示量は引数で指定し、対話入力を要求しない。CLIは`ui_observation`の解析と`ui_preview`の画像加工を呼ぶ。取得元と加工結果の関係は[画面の観測設計](architecture/verification.md#画面の観測と閲覧用データ)、データ形式は[CLI仕様](simulator-inspection.md)に定義する。

## 出力と成否の契約

業務処理の標準出力（stdout）は呼び出し元が受け取る結果データ、標準エラー出力（stderr）は進捗と診断に使う。JSONの項目、Markdown表、生成物、実行記録の形式は、それぞれのCLIが定義する。

| 出力 | 内容 | 利用方法 |
| --- | --- | --- |
| stdout | 結果JSON、PRコミット表、作成した端末の識別子など | 対象CLIの形式に従って読み取る |
| stderr | 公開可能な工程名、結果の要約、違反の説明、表示障害の警告 | 実行状況の把握に使う |
| 終了コード | 呼び出したスクリプトの成功・失敗 | 自動処理の分岐に使う |
| 結果ファイル・ログ | コマンド、所要時間、対象ソース、成否、生成物など | 検証・調査・再現の根拠に使う |

hamioの応答はAdapterが捕捉し、表示分だけを親プロセスのstderrへ書き出す。hamio自身のstdoutが、スクリプトの結果データに混ざることはない。

`inspect_ui.py`は結果JSONをstdoutへ直接出力し、処理成功を`ui.result()`、処理中に検出したエラーを`ui.message()`で表示する。画像生成では`sips`のstdoutとstderrを加工記録へ保存し、CLIのstdoutには原本・派生画像・変換条件・記録先を返す。成功の終了コードは0、処理失敗は1、argparseの引数エラーは2となる。

hamioの終了コード0と`status: ok`は「表示定義を処理できた」という意味である。検査の不合格も正常に表示できるため、業務の成否はスクリプトの終了コードと結果データで判断する。`Reporter.result()`が送る`result`部品の`success`には、呼び出し元が判定した成否を設定する。

### 表示形式

| 設定・条件 | 形式 |
| --- | --- |
| `NIBBLE_UI_FORMAT=human` | 人向けの表示 |
| `NIBBLE_UI_FORMAT=json` | hamioのJSON応答をstderrへ1件ずつ出力 |
| 指定なし、stderrが端末（TTY）、`CI`が未設定または空 | 人向けの表示 |
| 指定なし、非TTYまたは空でない`CI` | JSON |

エージェントとCIは`NIBBLE_UI_FORMAT=json`を指定する。Nixの検査定義もこの値を持つため、builderが呼び出し元の環境変数を引き継がなくてもJSONになる。人向け表示の色は、stderrがTTYで、`TERM`が`dumb`以外、`NO_COLOR`が未設定または空の場合だけ有効にする。

```sh
nix develop
mkdir -p artifacts
NIBBLE_UI_FORMAT=json python3 scripts/check_docs.py \
  > artifacts/docs-result.json 2> artifacts/docs-display.log
NIBBLE_UI_FORMAT=human python3 scripts/check_swift_policy.py
sh scripts/check_swift_style.sh
```

この例はNixシェル内でPythonを実行し、Nix自体の診断とスクリプトの出力を分ける。`docs-result.json`は文書検査の結果、`docs-display.log`は表示の記録である。stderrには表示障害時のテキスト警告も含むため、常にJSONだけで構成されるとは限らない。

## 表示APIと障害時の動作

通常のCLIは共有インスタンス`ui`を利用する。その寿命はPythonプロセスに対応する。

| API | 呼び出し元の責務 | 表示する内容 |
| --- | --- | --- |
| `message(text, level)` | 公開可能な文言と重要度を選ぶ | 通知・診断 |
| `result(success, text)` | 処理の成否を判定する | 成否と要約 |
| `check(title, errors, summary)` | 違反一覧を作り、終了コードを決める | 検査結果と個々の違反 |
| `step(label)` | context内で処理を実行し、失敗を例外として伝える | 開始、正常終了時の成功、例外時の未完了 |

`step`は例外の内容を表示せず、そのまま呼び出し元へ返す。戻り値や外部コマンドの終了コードを自動判定しないため、呼び出し元は成功条件を満たした時点でcontextを抜ける。録画では停止・ファイル確定・媒体検査までを工程に含める。

AdapterはAPI・成否・形式・要求と応答の一致を検査し、Unicodeを失わずに文字列上限へ収める。表示待ちには期限を設ける。具体値は[実装](../scripts/script_ui.py)と回帰テストで管理する。

| 状態 | 処理 |
| --- | --- |
| hamioがない、応答が不正、表示に失敗、タイムアウト、表示形式の設定が不正 | 固定文の警告を一度出し、その`Reporter`を代替出力へ切り替える |
| 代替出力中 | hamioを起動せず、`display: fallback`と表示部品を持つJSONをstderrへ書く |
| stderrへの書き込み失敗 | 表示を配送できなくても、処理側の例外・終了コードに影響させない |

代替出力はUnicodeと端末制御文字をJSONでエスケープする。hamioの生のエラーや例外内容は転送しない。表示障害に対して業務処理を再試行しないため、署名・アップロードなどの実行済み操作が重複しない。端末を失った実行の成否は、呼び出し元の終了状態と保存した記録から確認する。

## 秘密情報の扱い

表示Adapterに渡す文字列は、呼び出し元が公開可能と判断したものに限る。Adapterは秘密情報を自動検出・除去しない。認証付きコマンドの引数、環境変数の辞書、認証設定、配布の生ログや例外全体は表示へ渡さない。

hamioへ渡す環境変数は`PATH`、`LANG`、`LC_ALL`、`TERM`、`NO_COLOR`に限定する。配布スクリプトは`python3 -I`で起動し、自身に隣接するレビュー済みのAdapterを絶対パスから読み込む。作業ディレクトリや`PYTHONPATH`をimport先に使わない。

認証処理と保護されたログは配布スクリプトが管理する。この境界は同一ユーザー内の運用・コード契約であり、OSの読取権限を分離するものではない。エージェントによる直接参照の禁止と実行手順は[TestFlightの秘密情報規約](testflight.md)に従う。

## 依存と保守

hamioは開発用の依存であり、アプリには組み込まない。`flake.nix`がパッケージを選択し、`flake.lock`が依存のrevisionを固定する。hamio側のnixpkgsは提供元のlockで独立して固定し、nibbleのツール環境へ依存を合わせる`follows`は使用しない。

提供版・対応環境は`flake.nix`と`flake.lock`で確定する。MITと同梱部品の告知はNix storeの`share/hamio/`へ保持する。Intel Macではhamioに加えtree-sitter-language-packも非対応のため、Adapter単体のfallbackを開発環境全体の対応と扱わない。aarch64-darwinで実行確認し、Linux arm64は構成評価のみで実行は未確認。

依存の更新はNixで行う。hamio本体の版とNix定義のrevisionを照合し、API、対応OS・CPU、固定hash、ライセンス、lock差分をレビューする。

```sh
nix flake update hamio
nix develop --command hamio --version
nix develop --command hamio capabilities
nix flake check --no-update-lock-file --print-build-logs
```

`.hamio-version`や独立インストーラーによる別管理は行わない。取り消しは、レビュー済みの依存宣言とlockを一組として戻す。

## 変更時の検証

表示に関係する変更では、[表示の回帰テスト](../scripts/tests/test_script_ui.py)で正常表示、処理の失敗、表示障害、stdoutの結果、終了コード、文字列上限、子プロセスの環境を確認する。hamioを提供する環境のNix検査では実バイナリを必須にし、代替出力だけで合格しない。

CLIの接続を変更した場合は、その呼び出し元も検証する。iOSの実行管理・撮影はVerificationAppのテストと`fixture-smoke`で確認する。配布の秘密情報境界は、一時ディレクトリの偽認証情報で検査する。実際の署名や送信の成立には、配布用の検証が別に必要となる。

表示のコストは同じ環境・出力先・回数で測り、処理本体の時間と分けて記録する。処理本体の性能指標へ表示時間を混ぜない。

## 参照する上流契約

確認日：2026-09-18。対象：hamio 0.1.0 / API v1、下記URLで固定するNix定義revision。

- [hamioのAPI契約](https://github.com/9uiLe/hamio/blob/dd8c86c6923f692ef183152958147bf095e85daa/docs/api.md)
- [hamioのNix導入手順](https://github.com/9uiLe/hamio/blob/dd8c86c6923f692ef183152958147bf095e85daa/docs/distribution.md#nix-で導入する)
- [公開資産とhashの固定情報](https://github.com/9uiLe/hamio/blob/dd8c86c6923f692ef183152958147bf095e85daa/nix/release.json)
