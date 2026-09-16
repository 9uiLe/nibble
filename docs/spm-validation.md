# Swift Package構成の検証

確認日：2026-09-16。対象はnibbleの本体・共有拡張で使うSwift Package構成と、一覧行の比較を行う`SnippetRowContent`。対象ソースは`bd53d99e792241966834f0be2eb711ef0f2868e0`である。採用理由・実装上の契約・ビルド条件は[実装規約](library-policy.md)、製品全体の観測は[検証結果の索引](mvp-validation.md)を参照する。

## 対象の依存構成

Xcode projectのexact version、共有`Package.resolved`、取得したパッケージのソースを照合した。

| パッケージ | バージョン | Git revision |
| --- | --- | --- |
| swift-tasking | 0.3.0 | `4a3eeeedf37e291a7effeba08cad0cd24224d50c` |
| swift-scoped-animation | 0.2.2 | `78b1e6981cd89c313b4d6906f74deb2d02ffff4c` |
| swift-app-macros | 0.3.0 | `9b6d5d699b44990029cdfa61cddf35cec46d1520` |
| swift-syntax | 603.0.2 | `79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` |

直接依存3件の安定版リリースと、AppMacrosのmanifestによるswift-syntaxのexact指定を確認した。ScopedAnimation・AppMacrosのMITライセンスと著作権表記は、製品に含める`ThirdPartyNotices.txt`と整合している。

ソース上の`SnippetRowContent`は`@Equatable`と`@MainActor EquatableBodyView`を宣言し、タイトル・本文プレビュー・ピン状態を通常の`let`入力として持つ。MainActor付きの準拠について、Lintは可変入力・closure・独自body・マクロ欠落・extension準拠を拒否した。型適合と描画の検証状況は下表に示す。

## 環境と結果

| 実行条件 | 値 |
| --- | --- |
| ホスト | macOS 26.2、arm64 |
| Xcode / Swift | Xcode 26.5（17F42）、Swift 6.3.2 |
| Simulator | 専用iPhone 17 Pro、iOS 26.5（23F77） |
| UDID | `D099A849-386F-4EAE-AE12-02D8DC623AF2` |
| ビルド指定 | scheme `Nibble`、Release、ad hoc署名 |
| 製品設定 | deployment target 26.0、Swift language mode 6、strict concurrency complete、default isolation nonisolated |

| 検証 | 結果 | 記録 |
| --- | --- | --- |
| パッケージ解決 | 表の4件のバージョン・revisionを解決 | `artifacts/package-resolution.log` |
| Nix共通検査 | ローカル5 check成功。Python回帰テスト65件、Swiftソース29件の規約検査を含む | `artifacts/nix-check-final.log` |
| Releaseビルド・製品テスト | ビルド失敗。`AppMacrosMacros`のXcode承認が必要という診断で中止。製品テストの実行なし | run `20260916T015640Z-test-a1ce49` |
| UI操作・画像・録画 | 未実施。対象構成の実行バイナリを取得できていない | 証跡なし |
| 描画・応答時間 | 未測定 | 性能改善・非劣化の判断なし |
| GitHub Actions | 未実施 | この構成に対するCI結果なし |

runは1回の検証実行を指す。上記runのmanifest・ログ・xcresultは、Git管理対象外の`artifacts/ios/20260916T015640Z-test-a1ce49/`へ保存している。コミット前のソースを実行しており、manifestには開始・終了時のファイルhashを記録している。

Xcodeの診断は「Macro “AppMacrosMacros” from package “swift-app-macros” was changed since a previous approval and must be enabled before it can be used」。ビルドホストの画面ロックにより対象マクロを有効にするXcode操作を実施できなかった。マクロの固定revision・展開ソース・依存は確認済みで、全マクロの検証を無効にする設定は使用していない。この結果は、製品コードのコンパイル成功やiOS上の互換性を示さない。

## 再現手順と受け入れ条件

リポジトリルートで次を実行する。パッケージの取得とXcodeによる対象マクロの有効化は[セットアップ](../README.md#3-xcodeとswift-packageを準備する)に従う。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
nix flake check --no-update-lock-file --print-build-logs
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
nix develop --command python3 scripts/check-mvp-ui.py \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
```

別のMacでは、端末一覧から選んだ専用iOS 26.5 SimulatorのUDIDを指定する。

製品テストでは表示入力の等価比較、マウント済みViewの変更・復元、同じ入力での外観・文字サイズへの追従を確認する。UI driverでは作成・下書き再開・保存・検索・編集・コピー・ピン留め・削除取り消し・下書き破棄を確認する。

[MVP手順](mvp.md#タスクの寿命とアニメーション)に従い、Debugで通知の表示・消去、Reduce Motion、アニメーション診断を確認する。対象の画像・録画を確認・添付し、[証跡検査](review-evidence.md)でソースと媒体を照合する。これらの実行結果と閲覧可能な証跡がそろうことをiOS検証の受け入れ条件とする。実機・署名配布はMVPの受け入れ範囲外である。
