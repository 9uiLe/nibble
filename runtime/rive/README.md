# Rive描画基盤

nibbleはRiveの状態機械・描画エンジンを使い、Metal描画先の取得を専用キューへ分離する。画面にアニメーションが見えている間も、スクロールを処理するメインスレッドを描画先の空き待ちで止めないための基盤である。

## 構成と責務

| 定義 | 責務 |
| --- | --- |
| `build.json` | Riveの版、Premakeの版、iOSとSimulatorのビルド対象 |
| `drawable-acquisition.patch` | Apple runtimeの描画先取得・フレーム要求・寿命管理 |
| `dependency.lua` | Nixで固定したcore依存だけを解決する |
| `Package.swift` | 生成するXCFrameworkのSwift Package定義 |
| [flake.nix](../../flake.nix) / [flake.lock](../../flake.lock) | Apple runtime 6.27.0・core・間接依存・ビルドツールの固定 |
| [rive_runtime.py](../../scripts/rive_runtime.py) | 入力照合、ソース展開、unsigned archive、XCFramework生成、成果物照合 |

画面側の公開APIと可視性・テーマ・再生寿命は[RivePresentation](../../app/Packages/RivePresentation/README.md)が受け持つ。描画基盤は画面名や製品モデルに依存しない。

## フレームの契約

Viewとlayerの設定、状態機械の更新、rendererの呼出し、描画オブジェクトの最終解放はメインスレッドで行う。`CAMetalLayer.nextDrawable()`とtexture取得は専用serial queueで行う。取得要求は同時に一つとし、取得待ちやGPU処理中に状態機械を重複して進めない。

メインスレッドへ戻った時点で、再生世代・View・controller・サイズ・可視性を照合する。一致しない結果は描画に使わず、必要な初回描画を再予約する。表示終了後に取得が完了しても、終了した再生を再開しない。clockを維持することで、描画待ちの時間を不要なフレーム更新の蓄積へ変えない。

## 開発

リポジトリルートのローカルMacで実行する。XcodeとiOS 26.5 Simulatorの準備は[開発手順](../../CONTRIBUTING.md)を参照する。

```sh
nix develop --command env NIBBLE_UI_FORMAT=json python3 scripts/rive_runtime.py prepare
nix develop --command env NIBBLE_UI_FORMAT=json python3 scripts/rive_runtime.py check
```

`prepare`は一致する成果物を再利用し、不足・変更があれば生成する。`check`は生成せず照合だけを行う。iOS検証とTestFlightのビルドも同じ`prepare`を呼ぶ。Xcodeでプロジェクトを開く前に初回の生成を済ませる。

成果物は`artifacts/RiveRuntime/`、工程・ソース・unsigned archive・ログは`artifacts/rive-runtime/`に置く。いずれもGit管理外である。入力の全実行定義、固定ソース、ビルダー、Xcode、Premakeと、生成パッケージの全ファイルhashがキャッシュの成立条件となる。失敗runを残し、成功した生成物だけをパッケージ位置へ移す。

## 検証

Python回帰テストは入力変更・欠損・追加・改変によるキャッシュ拒否と証跡の入力範囲を検証する。製品テストのRive描画テストは取得待ちの状態機械進行回数と終了後の再開防止を検証する。AboutとキーボードガイドのUI検証は画面内外・タブ・fullScreenCover・アプリ状態に応じた停止再開を扱う。

描画基盤を更新するときは、固定したソースへのpatch適用、iOSとSimulatorのビルド、描画と寿命の回帰テストを実行する。スレッドサンプル数は処理時間・FPS・hitch率ではない。性能の評価方法は[性能検証](../../docs/performance-verification.md)に定める。
