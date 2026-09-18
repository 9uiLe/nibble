# hamio導入の検証

対象はhamioを利用する開発スクリプト。処理と表示の契約は[設計と手順](script-tooling.md)を参照する。製品のSwift・Xcode構成・アセットは変更しない。

## 対象と環境

- 基準: `a6becc5318579ee9d94a18c0be1379931c60920a`（PR #23を含むmain）。作業ブランチ: `codex/hamio-scripts`。
- 2026-09-18、macOS arm64、hamio 0.1.0 / API v1。
- Nix定義: `dd8c86c6923f692ef183152958147bf095e85daa`。製品の公開資産・展開後binaryのhashは上流の`nix/release.json`で固定。
- nibbleの既存nixpkgs・sim-use・Rive入力は採用revisionを維持。hamio側のnixpkgsを独立したlock入力として追加。

## 確認状況

Python回帰テスト120件が成功。実hamioを使ったJSON・人向け表示、業務失敗の非ゼロ終了、iOSコマンドのログと終了コード、隔離したarchive-check、表示障害と環境の制限を含む。配布テストは一時ディレクトリの偽認証情報だけを使用する。

Apple Silicon MacでNix全検査7件が成功。UI設計Moduleの独立テスト35件も含む。アプリと共通UI設計Moduleのソース差分はなく、UI設計照合の入力差分はhamioを追加したflake.lockだけだった。

全systemの評価では、Linux arm64 / x86_64のchecksを評価できた。Intel Macは既存のtree-sitter-language-pack 1.4.1のplatform制約で評価に失敗した。導入前の`e65d2d9`でも同じ失敗を確認した。Apple Silicon Mac・Linux 2種の開発shellも構成評価できた。非対応を無視する設定は使用しない。Linuxの実行とIntel Macの全検査は未実施。

## ローカルiOS検証

実行ソースは`7d3edf309c8b7ca4c26a0baff8b415dcb74e6dfa`。Xcode 26.5（17F42）、Swift 6.3.2、sim-use 0.14.0、Release構成、iPhone 17 Pro / iOS 26.5（23F77）の専用Simulator（`D099A849-386F-4EAE-AE12-02D8DC623AF2`）で実行した。

| run | 結果 |
| --- | --- |
| `20260918T093743Z-test-6a0732` | VerificationAppのビルド・テスト2件成功、失敗・skipなし |
| `20260918T093754Z-smoke-9543ad` | ビルド・起動・リセット・入力・反映・PNG/MP4生成成功。49コマンドの記録と`fixture_output_exact: true`を確認 |

runは`artifacts/ios/`に保存し、`check_evidence.py --integrity-only`で開始・終了の入力、対象コミット、終了コード、媒体hashを照合した。検証記録を追記する文書の変更は、同検査の入力から除外される。

before/afterのPNGを開き、空の入力と「未実行」から、日本語・絵文字・改行を含む入力と反映結果へ変わったことを確認した。録画9.747秒のうち5.118秒・7.860秒の抽出フレームを開き、入力時のキーボード・拡大鏡と、反映済み表示・キーボードが閉じる途中の状態を確認した。全編再生は行っていない。これらは共通driverのfixtureの証跡であり、製品アプリのUI回帰検証を意味しない。

`ios.py ui`は実画面の13要素を有効なJSONとしてstdoutへ返した（`b2c4b1a121701c63a5c418156760506d2fd41e3e`で確認。後続変更はNix check内部の表示形式だけ）。内部観測のデータはrun内のJSONに残り、明示的なUI取得以外のstdoutへ混ざらない。

Nix checkのログでもhamioのJSON応答を確認した。workflowの環境変数に加え、Nixの各検査定義で`NIBBLE_UI_FORMAT=json`を指定している。通常のターミナル表示は人向け形式を使う。


## 表示コスト

対象は`7d3edf309c8b7ca4c26a0baff8b415dcb74e6dfa`の表示Adapter。macOS 26.2 arm64、Nix Python 3.13.15、hamio 0.1.0、JSON形式、出力先StringIOで測定した。業務処理を含まない1工程の開始・終了を、従来のprint 2回とAdapterのstepで比較した。2回のwarmup後、交互に7回ずつ測った。

| 表示方式 | 中央値 | 範囲 |
| --- | ---: | ---: |
| print 2回 | 0.008 ms | 0.007–0.012 ms |
| hamio render 2回 | 39.761 ms | 39.421–42.055 ms |

プロセス起動を含む表示時間は増える。工程境界だけへ適用し、測定対象の処理中やView更新の頻度では呼ばない。共通driverはこの表示時間をネイティブコマンドの所要時間へ含めないが、実行全体の経過時間には含まれる。CPU・メモリ・Linuxの表示時間やアプリ性能の改善は評価していない。

再測定は、同じ固定環境で`print(..., flush=True)`を2回実行する関数と、処理が空の`with Reporter().step('fixture'):`を用意し、`time.perf_counter()`で同じ条件・回数を測る。生成ログは`artifacts/hamio-display-timing.json`、測定コードは`artifacts/measure-hamio.py`に保存した。

## 再実行手順

```sh
nix flake check --no-update-lock-file --print-build-logs
NIBBLE_UI_FORMAT=json nix develop --command python3 scripts/ios.py test \
  --project-config validation/project.json --configuration Release \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
NIBBLE_UI_FORMAT=json nix develop --command python3 scripts/ios.py smoke \
  --project-config validation/project.json --configuration Release \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
```

このUDIDは上記環境の専用端末。別のMacではiOS 26.5の検証専用端末を明示する。各実行のrunを`check_evidence.py --run <run directory> --ref <commit> --integrity-only`で照合する。

## 検証範囲

表示の成功と業務の成功、fixtureと製品の動作、ローカルMacとLinuxの結果を区別する。実認証設定・API秘密鍵・Keychain・認証ログをエージェントから参照しない。実際の署名・送信、製品の全操作の再実行、Linuxでの実行、Intel Macでの全検査は未実施。証跡の外部公開とブラウザーでの閲覧確認も未実施。
