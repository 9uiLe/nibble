# エージェント向け開発ルール

作業前に [CONTRIBUTING.md](CONTRIBUTING.md) を読み、実装・検証・PR作成に適用する。規約の詳細は開発ガイドを正とする。

## プロダクトと変更範囲

- nibbleはiOS 26.0以上向けのスニペットツール。使いやすさ、シンプルさ、描画・応答性能を優先する。
- 1 PRを小さく単一の目的に保ち、無関係なリファクタリングや依存更新を含めない。
- アプリとextensionのdeployment targetは `26.0` にそろえる。最低対応OSの変更は、影響と理由を明記した独立の意思決定にする。
- 技術はOS/API制約、性能、保守・運用、移行容易性を比較して選ぶ。研究資料の候補を採用済みとして扱わない。

## 非同期処理・アニメーション・View比較

- 非同期の操作APIは受理した処理と結果反映を完了まで待つ`async`にする。同期メソッド・setterの隠れた開始と、操作APIがタスクを開始して完了前に戻る形は禁止。モデルは処理・状態、UIの`startTask`・イベント境界は開始・所有・寿命を担う。操作テストはAPIを直接awaitし、所有者のテストで重複・キャンセルを検査する。
- 非構造化タスクはswift-tasking（`ViewTaskStore` / `TaskSlot`）、アニメーションはswift-scoped-animation（`AnimationScope` / `animationBarrier`）を使う。所有者・寿命・重複方針を明示する。
- 生の`Task`生成、別scheduler、直接の`withAnimation`・`.animation`・transaction操作は禁止。構造化されたasync/await・task group・SwiftUI `.task`と協調用のTask APIは許可する。詳しくは[実装規約](docs/library-policy.md)に従う。
- 表示値の比較で更新を制御するViewはswift-app-macrosの`@Equatable`＋`EquatableBodyView`とし、通常の`let`の値型入力をすべて比較する。状態・操作は呼出元のViewに保持する。直接ゲート・`equatableBody`参照・手書き`==`・比較除外は禁止。通常のViewと値型・enumの標準Equatable合成は許可する。
- 本体・拡張・テスト・研究・基盤用Swiftを`swift-library-policy`で検査する。構文Lint、Swift compiler、操作・所有者・表示のテストを併用する。抑制コメントを使わず、依存はexact versionと共有`Package.resolved`で固定する。

## 開発環境と検証

- 補助ツールは `flake.nix` に宣言し、`flake.lock` で固定する。ローカルとCIは同じlockを使い、Homebrew・pip等の別管理を前提にしない。
- 共通検査は `nix flake check --no-update-lock-file --print-build-logs`。
- iOSの実行検証は **26.5のみ** を対象とする。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認する。
- Xcode・iOS SDK・SimulatorはローカルのApple配布物を使用する。ビルド・テスト・実行管理・撮影はApple CLI、Simulatorの画面読取・操作はNixの `sim-use` を使う。
- Simulatorの対象UDIDを明示し、生成物はGit管理対象外の `artifacts/` に保存する。実行手順は [ローカル iOS 検証](docs/ios-verification.md) に従う。
- GitHub Actionsの各ジョブは `runs-on: ubuntu-24.04` を直接指定する。macOS runnerはself-hosted・再利用workflow・別ジョブ起動による迂回を含めて禁止する。
- iOSのビルド・テスト・UI/UX・性能確認はローカルMacが担当する。クラウドの静的検査をiOSの検証結果に置き換えない。

## 検証対象と設計資料

| 検証対象 | 責務 | 設定・手順 |
| --- | --- | --- |
| `Nibble` / `NibbleShare` | 製品MVP。本体と共有拡張のデータ・画面・操作 | `app/project.json`、[MVP手順](docs/mvp.md) |
| `VerificationApp` | 基盤用fixture。入力・操作・テスト・撮影の成立を試験する | `validation/project.json`、[共通手順](docs/ios-verification.md) |
| `ResearchProbe` | 製品技術の比較用アプリ。保存・検索・復旧・UI・OS連携を評価する | `validation/research-project.json`、[研究用の設計と手順](validation/RESEARCH.md) |

製品は`app/Nibble.xcodeproj`・shared scheme `Nibble`。比較・基盤用projectは各々`validation/<名前>.xcodeproj`、shared schemeは対象名と同じ。`scripts/ios.py smoke`はVerificationApp専用、ResearchProbeの画面操作は`validation/check-research-ui.py`を使う。

MVPの採用構成は[ADR 0002](docs/decisions/0002-mvp-app.md)、追加の製品判断は[研究と検証計画](research/README.md)に基づく。比較用の構成を採用済みの製品設計と扱わない。製品のtargetには設定・手順・期待結果を用意する。共通基盤の責務は[設計文書](docs/decisions/0001-local-ios-verification.md)を参照する。

## レビューと証跡

- UI/UXを変更したらスクリーンショットで確認し、操作・遷移・応答の変更は画面録画でも確認する。画像・動画はPRに添付する。
- 証跡には対象コミット、端末・OS、操作手順を記載する。レビュー担当者が閲覧できる添付先を使い、ローカルパスだけで完了にしない。
- 実行していない検証や取得していない証跡を実施済みとしない。環境がない場合は未実施項目と理由を明記し、レビュー可能な変更まで進める。
- PRには目的・背景、アウトカム、全コミットのハッシュと説明の表、画像・動画、検証結果を記載する。対象外の欄も残し、理由を書く。
