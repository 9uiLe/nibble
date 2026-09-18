# 開発スクリプト基盤の検証記録

対象は、hamioを使う表示Adapterと、検査・iOS検証・アセット生成・配布スクリプトの接続である。[設計](script-tooling.md)で定義した出力、成否、障害時の動作、秘密情報の境界を評価する。VerificationAppは共通driverを試すための小さなiOSアプリであり、製品Nibbleの動作確認とは別に扱う。

## 対象ソースと環境

確認日：2026-09-18。

| 対象 | ソース・条件 |
| --- | --- |
| 共通検査・iOS実行・表示コストの実装 | `7d3edf309c8b7ca4c26a0baff8b415dcb74e6dfa` |
| Ubuntu CIのソース | `106d5b9bd9bbd6302a3da53d8c19ee9212542b72`。上記との差分は検証文書 |
| 差分の比較基準 | `a6becc5318579ee9d94a18c0be1379931c60920a` |
| ローカル環境 | macOS 26.2 arm64、Nix Python 3.13.15 |
| 表示ツール | hamio 0.1.0 / API v1 |
| hamioのNix定義 | `dd8c86c6923f692ef183152958147bf095e85daa`。公開資産と展開後バイナリのhashを上流の`nix/release.json`で固定 |
| iOSツールチェーン | Xcode 26.5（17F42）、Swift 6.3.2、sim-use 0.14.0 |
| iOS実行条件 | Release、iPhone 17 Pro Simulator、iOS 26.5（23F77）、専用UDID `D099A849-386F-4EAE-AE12-02D8DC623AF2` |

比較基準からの製品Swift・Xcode構成・アセット・共通UI設計Moduleの実装差分はない。UI設計照合が検出した入力差分はflake.lockだけである。nibble側のnixpkgs・sim-use・Riveは比較基準と同じrevisionを使い、hamio側のnixpkgsは独立したlock入力を持つ。

## 共通検査と環境別の結果

| 確認項目 | 結果・根拠 |
| --- | --- |
| Apple Silicon MacのNix検査 | 7件成功。`nix flake check --no-update-lock-file --print-build-logs` |
| Python回帰テスト | 120件成功。実hamioのJSON・人向け表示、業務失敗時の終了コード、ネイティブログ、表示障害、子プロセスの環境制限、配布の隔離importを含む |
| UI設計Moduleの独立テスト | 35件成功 |
| 配布スクリプトの境界 | 一時ディレクトリの偽認証情報で検査。実認証設定・秘密鍵・Keychain・認証ログは参照していない |
| Nix内の表示形式 | 検査ログでhamioのJSON応答を確認。workflowと各検査定義が`NIBBLE_UI_FORMAT=json`を指定 |
| Linux x86_64 | Ubuntu 24.04の[CI run](https://github.com/9uiLe/nibble/actions/runs/35331585895)で共通検査とPR本文・全コミット照合が成功 |
| Linux arm64 | checksと開発シェルの構成評価は成功。実行は未実施 |
| Intel Mac | tree-sitter-language-pack 1.4.1のplatform制約で評価失敗。全検査は実行できていない |

Intel Macの評価失敗は、hamioを含まないソース`e65d2d9`でも再現した。非対応platformを無視する設定は使用していない。hamioの有無だけでは、この環境のNix検査を実行可能にできない。

ローカルのログは`artifacts/hamio-nix-complete.log`、環境別の評価は`artifacts/hamio-nix-evaluation.log`と`artifacts/hamio-supported-evaluation.json`に保存した。これらのパスは検証したMac上の記録であり、GitHubへ添付した媒体ではない。

## iOSの実行管理と撮影

| run | 実行内容 | 結果 |
| --- | --- | --- |
| `20260918T093743Z-test-6a0732` | VerificationAppのReleaseビルド・テスト | 2件成功、失敗・skipなし |
| `20260918T093754Z-smoke-9543ad` | ビルド・起動・リセット・入力・反映・撮影 | 49コマンド成功、`fixture_output_exact: true`、PNG・MP4生成成功 |

runは`artifacts/ios/`に保存した。`check_evidence.py --integrity-only`で、開始・終了の入力、対象コミット、終了コード、媒体hashを照合し、両runとも成功した。`106d5b9bd9bbd6302a3da53d8c19ee9212542b72`との入力一致も確認した。文書編集後に再利用する場合も、対象revisionとの照合が必要となる。

### 媒体で確認した範囲

- 入力前後のPNGを開き、空の入力と「未実行」から、日本語・絵文字・改行を含む入力と反映結果へ変わることを確認した。
- 9.747秒の録画から5.118秒・7.860秒の抽出フレームを開いた。入力時のキーボード・拡大鏡と、反映済み表示・キーボードが閉じる途中の状態を確認した。
- 全編再生、媒体の外部公開、ブラウザーでの閲覧確認は行っていない。

これらの結果は、共通driverによる検証用アプリの操作・撮影・記録が成立することを示す。製品のUI、アクセシビリティ、実機性能は評価範囲に含めない。

### 明示的な画面情報の取得

`ios.py ui`は実画面の13要素を有効なJSONとしてstdoutへ返した。実行ソースは`b2c4b1a121701c63a5c418156760506d2fd41e3e`、結果は`artifacts/hamio-ui-snapshot.json`に保存した。このコマンドの実装は上記のiOS実行ソースと同一であり、2つのrevision間の実行設定の差分はNix検査の表示形式指定である。内部観測のデータはrun内のJSONに記録され、明示的な画面取得以外のstdoutへ混ざらなかった。

## 表示コスト

表示Adapterの1工程について、開始と終了の表示時間を測った。処理本体を空にし、同じmacOS・Python環境、JSON形式、StringIO出力で、`print(..., flush=True)`を2回実行する関数と`with Reporter().step('fixture'):`を比較した。各方式を2回warmupし、交互に7回ずつ`time.perf_counter()`で測定した。

| 表示方式 | 中央値 | 範囲 |
| --- | ---: | ---: |
| print 2回 | 0.008 ms | 0.007–0.012 ms |
| hamio render 2回 | 39.761 ms | 39.421–42.055 ms |

hamioのプロセス起動を含む表示時間は、直接printする方式より長かった。工程境界での利用に対する測定であり、高頻度更新、端末への実出力、Linux、CPU・メモリ、アプリ性能を評価した値ではない。共通driverでは表示時間をネイティブコマンドの所要時間へ含めず、実行全体の経過時間へ含める。

測定コードは`artifacts/measure-hamio.py`、結果は`artifacts/hamio-display-timing.json`に保存した。再測定では、上記2つの関数、環境、出力先、warmupと測定回数をそろえる。

## 再実行手順

リポジトリルートで固定したNix環境を使う。iOSのコマンドに記載したUDIDは、上記のMacにある検証専用端末である。別の環境では、iOS 26.5の専用Simulatorを指定する。

```sh
nix flake check --no-update-lock-file --print-build-logs
NIBBLE_UI_FORMAT=json nix develop --command python3 scripts/ios.py test \
  --project-config validation/project.json --configuration Release \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
NIBBLE_UI_FORMAT=json nix develop --command python3 scripts/ios.py smoke \
  --project-config validation/project.json --configuration Release \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
```

作成した各runを`check_evidence.py --run <run directory> --ref <commit> --integrity-only`で照合する。実行条件、媒体の確認方法、未実施項目を[証跡の手順](review-evidence.md)に従って記録する。

## 未確認事項と制約

- 実認証情報による署名・App Store Connectへの送信。
- 製品Nibbleの全テスト・全操作、実機での動作。
- Linux arm64での実行、Intel Macでの全検査。
- CPU・メモリ、Linuxの表示コスト、アプリの性能。
- 検証用アプリの録画の全編再生と、媒体の外部公開・閲覧確認。

表示の回帰テスト、検証用アプリの操作、各OSでの共通検査は、それぞれ上記の対象と条件に限定した結果である。配布・製品UI・実機での受け入れには、対象の手順による検証が必要となる。
