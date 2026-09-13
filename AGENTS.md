# エージェント向け開発ルール

作業前に [CONTRIBUTING.md](CONTRIBUTING.md) を読み、実装・検証・PR作成に適用する。規約の詳細は開発ガイドを正とする。

## プロダクトと変更範囲

- nibbleはiOS 26.0以上向けのスニペットツール。使いやすさ、シンプルさ、描画・応答性能を優先する。
- 1 PRを小さく単一の目的に保ち、無関係なリファクタリングや依存更新を含めない。
- アプリとextensionのdeployment targetは `26.0` にそろえる。最低対応OSの変更は、影響と理由を明記した独立の意思決定にする。
- 技術はOS/API制約、性能、保守・運用、移行容易性を比較して選ぶ。研究資料の候補を採用済みとして扱わない。

## 開発環境と検証

- 補助ツールは `flake.nix` に宣言し、`flake.lock` で固定する。ローカルとCIは同じlockを使い、Homebrew・pip等の別管理を前提にしない。
- 共通検査は `nix flake check --no-update-lock-file --print-build-logs`。
- iOSの実行検証は **26.5のみ** を対象とする。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認する。
- Xcode・iOS SDK・SimulatorはローカルのApple配布物を使用する。ビルド・テスト・実行管理・撮影はApple CLI、Simulatorの画面読取・操作はNixの `sim-use` を使う。
- Simulatorの対象UDIDを明示し、生成物はGit管理対象外の `artifacts/` に保存する。実行手順は [ローカル iOS 検証](docs/ios-verification.md) に従う。
- GitHub Actionsの各ジョブは `runs-on: ubuntu-24.04` を直接指定する。macOS runnerはself-hosted・再利用workflow・別ジョブ起動による迂回を含めて禁止する。
- iOSのビルド・テスト・UI/UX・性能確認はローカルMacが担当する。クラウドの静的検査をiOSの検証結果に置き換えない。

## 検証対象と設計資料

`validation/VerificationApp.xcodeproj` とshared scheme `VerificationApp` は、検証基盤を試験するfixture（検証用アプリ）。入力・操作・テスト・撮影の成立を確認する。製品本体のUI・保存・呼び出し方式は [研究と検証計画](research/README.md) で評価する。

製品のprojectとschemeを登録するときは、利用可能な検証設定と手順を用意する。基盤の構成と対象範囲は [設計文書](docs/decisions/0001-local-ios-verification.md) を参照する。

## レビューと証跡

- UI/UXを変更したらスクリーンショットで確認し、操作・遷移・応答の変更は画面録画でも確認する。画像・動画はPRに添付する。
- 証跡には対象コミット、端末・OS、操作手順を記載する。レビュー担当者が閲覧できる添付先を使い、ローカルパスだけで完了にしない。
- 実行していない検証や取得していない証跡を実施済みとしない。環境がない場合は未実施項目と理由を明記し、レビュー可能な変更まで進める。
- PRには目的・背景、アウトカム、全コミットのハッシュと説明の表、画像・動画、検証結果を記載する。対象外の欄も残し、理由を書く。
