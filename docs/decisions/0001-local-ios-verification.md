# 0001：Apple CLI と sim-use によるローカル iOS 検証

- 状態：採用（開発・検証基盤）
- 決定日：2026-09-13
- 対象：iOS 26.0 以上、ローカル Mac。製品本体の UI・保存・呼び出し方式は対象外。

## 課題と期待する体験

文献調査で残った仮説を確かめるには、実在する scheme でビルド・テストし、Simulator で操作して結果と証跡を残せる必要がある。コマンドの実行と、内容が正しいこと・人が画面を確認したことを区別する。

## 選択

| 候補 | 判断 |
| --- | --- |
| Apple `xcodebuild` / `simctl` / `xcresulttool` | ビルド・実行管理・記録・結果取得に採用。Xcode と一緒に提供されるCLIを直接呼び、結果 bundle と生ログを保持する |
| `sim-use` | 利用者の指定により Simulator の画面読取・操作に採用。実機の機能がSimulatorと同じとは仮定しない |
| 専用の大規模なビルド自動化フレームワーク | 現状の操作範囲では不要。既存の Python と標準ライブラリで引数・結果・録画終了処理をまとめる |
| GUI だけで行う検証 | 自動化基盤の代わりにはしない。画像・動画のレビューや利用者の操作評価には併用する |

検証用アプリは標準 UIKit の入力欄・ボタン・表示で構成する。Swift Testing でホストの識別と原文保持を検査し、画面の操作は sim-use で実施する。この小さな fixture の採用は nibble 本体の UIKit 採用決定ではない。SwiftUI、保存方式、App Intents / extension はそれぞれの試作で判断する。

## 固定と運用

`sim-use` は upstream の **v0.14.0 release binary** と resource bundle を Nix から取得する。`flake.nix` のURLと `flake.lock` の内容 hash で固定し、Homebrew のインストール状態に依存しない。公開アーカイブの SHA-256 は取得時に GitHub release の digest と照合した：`67e2ee29a7246272de8646e46664a93d9cebcace134094cfd3d07dfb82bda3e6`。lock の `narHash` は Nix のファイル表現に対する hash なので、このアーカイブ hash とは種類が異なる。

配布 binary に arm64 / x86_64 の両 slice があることを `lipo -info` で確認した。実行確認は Apple Silicon。ライセンスは Apache-2.0 で、upstream が idb・AXe 等の通知を管理している。自前の再署名やバイナリ加工を行わず、resource bundle を実行ファイルと同じ場所に保持する。

ソースからの構築は idb の XCFramework と XcodeGen 等の追加工程が必要なため、今回は公開された固定アーカイブを使用する。OS / Xcode 更新で不整合が起きた場合は、同じ検証手順で新しい release またはソースビルドを比較する。依存更新はURLと lock を一緒に変更して戻せるようにする。

Xcode / SDK / runtime は Apple 配布物を利用し、`DEVELOPER_DIR` または `xcode-select` の選択を記録する。今回の確認環境は Xcode 26.5。ほかの Xcode 26.x での動作を、この結果だけから保証しない。

## 信頼性と証跡

- UDID は明示指定。既存の端末を自動選択・消去・削除しない。専用 Simulator の作成は明示コマンドで行う。
- ビルド・テスト・操作は非ゼロ終了を失敗として保存し、テスト0件も成功としない。操作結果はUIの観測値で確認する。
- `recordVideo` の開始通知を待って操作し、途中の失敗でも SIGINT で動画を確定させる。動画の代表フレームをデコードし、破損や空の出力を検知する。
- 実行ごとの別ディレクトリへ、コミット、未コミット状態、ファイル hash、OS・端末・ツール、ログ・画像・動画を保存する。画面を確認したこととPRへの添付先は手動で記録する。
- 生成物は `artifacts/` にまとめて ignore する。公開する証跡にはダミーデータを使う。sim-use の開発用機能・内部 framework は配布アプリにリンクしない。

## 性能と費用

Xcode の DerivedData を UDID ごとに再利用する。iOS のビルド・実行はローカルで行い、CI は Ubuntu の軽量な静的検査と driver テストだけにする。毎コマンドの環境確認には追加時間がかかるが、検証条件が追跡できることを優先する。計測された基盤の実行時間をプロダクトの応答性能とみなさない。

## 見直す条件

実アプリと extension の構成が決まったとき、実機署名・配布・性能検証を導入するとき、sim-use の互換性や保守状況が変わったときに見直す。Apple CLI の呼び出しと成果物を残しているため、driver や操作ツールは置き換えられる。

## 根拠と検証

- [sim-use v0.14.0](https://github.com/lycorp-jp/sim-use/releases/tag/v0.14.0)、[upstream README](https://github.com/lycorp-jp/sim-use/tree/v0.14.0)、同梱 `sim-use init --print` の操作仕様。
- 選択した Xcode の `xcrun simctl help io`、`xcresulttool help get test-results summary`、`xcresulttool get test-results summary --schema`、`xcresulttool help export attachments` を実際に確認。
- 再現手順・対応範囲は [ローカル iOS 検証](../ios-verification.md)。実行結果は各 run の `manifest.json` / `REVIEW.md` とレビュー時の証跡に記録する。
