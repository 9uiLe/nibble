# 検証とレビュー基盤の設計

検証基盤は、実行したソースと結果を一つのrunにまとめ、レビューするコミット・画像・録画へ対応付ける。静的な構造の検査と、Apple SDKでの実行、実際の観測を分けることで、CI成功を製品動作の保証と取り違えないようにする。

## 全体構成

| 層 | 責務 |
| --- | --- |
| 対象config | project、scheme、bundle、検証入力を選ぶ |
| ios.py・対象別driver | Apple CLIのbuild/test/install/launch/撮影とsim-useの操作を制御し、期待結果を判定する |
| manifest | 開始/終了ソース、端末、コマンド、成否、媒体hashを記録する |
| check_evidence.py | runと指定revision、媒体、レビュー申告を照合する |
| check_pr.py | 本文と全コミット、変更範囲、最終headのcheck runを照合する |
| Ubuntu CI | Nixで固定した共通検査とPR本文を検査する |

検証対象と必要な検査は[開発ガイド](../../CONTRIBUTING.md#実行と検査)、実行は[iOS手順](../ios-verification.md)、媒体とPRは[証跡手順](../review-evidence.md)を正本とする。

## 依存と実行環境

補助ツールはflakeとlock、製品依存は共有Package.resolvedで固定する。Xcode・SDK・SimulatorはAppleの配布物をローカルMacで管理する。NixのC toolchainでApple compilerを置き換えない。実行するOSとbuildをmanifestに記す。

## 実行の契約

明示したiOS 26.5の専用UDIDだけを操作する。同じUDIDの共通driverは排他制御し、直接sim-useや研究driverも端末単位で直列化する。既存端末の消去・削除は行わない。DerivedDataはcacheであり、実行ソースの証明に使わない。

テストはxcodebuild終了コードとxcresult summaryで判定し、成功1件以上・失敗なしを要求する。0件・全skip・timeoutを成功にしない。driverが既知の終了コード1を扱う場合だけ、理由と対応assertionのtrueを記録する。失敗runは独立して保存し、成功で上書きしない。

画面取得と入力は対象を照合してから行う。遷移中の空AXは、最終的な期待状態を判定する有限待機の内部でのみ許す。任意の操作失敗や空画面を正常化しない。文字列はOS経路で入力/コピーして原文を比較し、テスト用DBやclipboardの書換えで成功を作らない。

## 証跡のデータと照合

runは開始/終了の検証入力、確定時の媒体hashを持つ。実行中に入力が変われば失敗とする。ソースを証明するrunには同じscheme/UDIDのbuild成功が必要で、単独撮影は補助資料に限る。

revision名が違っても入力ファイルが一致するrunは再利用できる。記録のないhashを事後推定して追加しない。レビュー者は実際の画像・抽出時刻・全編再生・公開閲覧を区別し、未確認条件を残す。形式と操作は証跡手順に定める。

## 共通検査とマージ条件

共通検査はApple SDK・Simulator・GitHub認証を必要としない。全CI jobはubuntu-24.04を直接指定し、macOS runnerの間接起動も許可しない。iOS実行・性能・媒体の内容はローカルの責務である。

PRのマージには検証、本文と全コミット、閲覧できる媒体、最終headのCI、baseへの追従を要求する。ruleset宣言と実効GitHub設定は別物として[確認](../review-evidence.md#githubの必須チェック)する。

## 保証範囲と保守方針

構文検査は型と実行を、hash照合は観測の真実性を、Simulatorは実機条件を証明しない。判定可能な不変条件は検査と違反例の回帰へ組み込み、画面・性能・人の判断に属する条件は明示して実行する。
