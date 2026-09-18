# hamio導入の検証

対象はhamioを利用する開発スクリプト。処理と表示の契約は[設計と手順](script-tooling.md)を参照する。製品のSwift・Xcode構成・アセットは変更しない。

## 対象と環境

- 基準: `a6becc5`（PR #23を含むmain）。作業ブランチ: `codex/hamio-scripts`。
- 2026-09-18、macOS arm64、hamio 0.1.0 / API v1。
- Nix定義: `dd8c86c6923f692ef183152958147bf095e85daa`。製品の公開資産・展開後binaryのhashは上流の`nix/release.json`で固定。
- nibbleの既存nixpkgs・sim-use・Rive入力は採用revisionを維持。hamio側のnixpkgsを独立したlock入力として追加。

## 確認状況

Python回帰テスト118件が成功。実hamioを使ったJSON・人向け表示、業務失敗の非ゼロ終了、iOSコマンドのログと終了コード、隔離したarchive-check、表示障害と環境の制限を含む。配布テストは一時ディレクトリの偽認証情報だけを使用する。

Apple Silicon MacでNix全検査7件が成功。UI設計Moduleの独立テスト35件も含む。アプリと共通UI設計Moduleのソース差分はなく、UI設計照合の入力差分はhamioを追加したflake.lockだけだった。

全systemの評価では、Linux arm64 / x86_64のchecksを評価できた。Intel Macは既存のtree-sitter-language-pack 1.4.1のplatform制約で評価に失敗した。導入前の`e65d2d9`でも同じ失敗を確認した。非対応を無視する設定は使用しない。Linuxの実行とIntel Macの全検査は未実施。

ローカルSimulatorの共通driverは検証中。

## 表示コスト

macOS 26.2 arm64、Nix Python 3.13.15、hamio 0.1.0、JSON形式、出力先StringIOで測定した。業務処理を含まない1工程の開始・終了を、従来のprint 2回とAdapterのstepで比較した。2回のwarmup後、交互に7回ずつ測った。

| 表示方式 | 中央値 | 範囲 |
| --- | ---: | ---: |
| print 2回 | 0.007 ms | 0.006–0.011 ms |
| hamio render 2回 | 41.594 ms | 40.650–42.229 ms |

プロセス起動を含む表示時間は増える。工程境界だけへ適用し、測定対象の処理中やView更新の頻度では呼ばない。共通driverはこの表示時間をネイティブコマンドの所要時間へ含めないが、実行全体の経過時間には含まれる。CPU・メモリ・Linuxの表示時間やアプリ性能の改善は評価していない。

再測定は、同じ固定環境で`print(..., flush=True)`を2回実行する関数と、処理が空の`with Reporter().step('fixture'):`を用意し、`time.perf_counter()`で同じ条件・回数を測る。生成ログは`artifacts/hamio-display-timing.json`、測定コードは`artifacts/measure-hamio.py`に保存した。

## 検証範囲

表示の成功と業務の成功、fixtureと製品の動作、ローカルMacとLinuxの結果を区別する。実認証設定・API秘密鍵・Keychain・認証ログをエージェントから参照しない。実際の署名・送信は本変更の検証に含めない。
