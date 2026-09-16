# Swift Package更新の検証

確認日：2026-09-16。アプリで使用する直接依存の安定版と、その互換性を確認する。

## 採用バージョン

| 依存 | 更新前 | 採用版 | 根拠 |
| --- | --- | --- | --- |
| swift-tasking | 0.3.0 | 0.3.0 | [最新の安定版](https://github.com/9uiLe/swift-tasking/releases/tag/0.3.0)を使用済み |
| swift-scoped-animation | 0.2.1 | 0.2.2 | [安定版リリース](https://github.com/9uiLe/swift-scoped-animation/releases/tag/v0.2.2)。トリガー比較・履歴・Debug診断の内部実装を更新 |
| swift-app-macros | 0.2.0 | 0.3.0 | [安定版リリース](https://github.com/9uiLe/swift-app-macros/releases/tag/0.3.0)。Viewの等価比較と準拠をMainActorに隔離 |
| swift-syntax（間接依存） | 603.0.2 | 603.0.2 | 604.0.0は公開済みだが、[AppMacrosのmanifest](https://github.com/9uiLe/swift-app-macros/blob/0.3.0/Package.swift)が603.0.2をexact指定 |

Xcode projectのexact versionと共有`Package.resolved`をそろえ、Xcodeの依存解決で次のrevisionを確認した。

- ScopedAnimation：`78b1e6981cd89c313b4d6906f74deb2d02ffff4c`
- AppMacros：`9b6d5d699b44990029cdfa61cddf35cec46d1520`

AppMacrosの[導入手順](https://github.com/9uiLe/swift-app-macros/blob/0.3.0/docs/adoption.md)に従い、`SnippetRowContent`を`@MainActor EquatableBodyView`へ準拠させる。表示値3つを比較する契約を維持する。MainActor付きの準拠でも、可変入力・クロージャ・独自body・マクロ欠落・extension準拠をLintが拒否する回帰テストを追加した。

両ライブラリのMITライセンスと著作権表記を確認し、bundleへ含める通知のバージョンを更新した。最低対応OSはiOS 26.0、Swift language mode 6、strict concurrency complete、default isolation nonisolatedを使用する。

## 実行結果

環境はmacOS 26.2 arm64、Xcode 26.5（17F42）、Swift 6.3.2。iOSの実行対象は専用iPhone 17 Pro Simulator、iOS 26.5（23F77）、UDID `D099A849-386F-4EAE-AE12-02D8DC623AF2`。

| 検証 | 結果 |
| --- | --- |
| `xcodebuild -resolvePackageDependencies` | 採用版とrevisionの解決に成功 |
| `nix flake check --no-update-lock-file --print-build-logs` | ローカルの5 check成功。Python回帰テスト65件、Swiftソース29件の規約検査を含む |
| Releaseビルド・製品テスト | 未完了。run `20260916T015640Z-test-a1ce49`は、更新したAppMacrosMacrosのXcode承認が必要という診断でビルドが中止された。テストは実行されていない |
| UI操作・画像・録画 | 更新後のビルドをまだ実行できていないため未実施 |
| GitHub Actions | 未実施 |

マクロの固定revision・展開ソース・依存を確認済み。Macの画面ロックによりXcodeの対象マクロ承認操作ができず、ビルド以降の検証を保留している。マクロ検証を一括で無効にする設定は使用していない。失敗runのmanifest・ログ・xcresultは`artifacts/ios/`に保存している。

## 残る検証

画面ロック解除と対象マクロの有効化後、Releaseの製品テスト、標準UI driver、Debugの通知表示・消去とReduce Motion、診断ログを確認する。画像と録画を確認・添付し、対象コミットと証跡を照合するまでiOS検証済みとして扱わない。

性能：ScopedAnimationの内部処理の変更をソースで確認したが、更新前後の描画・応答時間の定量比較は未実施。性能改善や非劣化は主張しない。実機・署名配布はMVPの受け入れ範囲外。
