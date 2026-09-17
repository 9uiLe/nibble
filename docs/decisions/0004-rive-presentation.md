# Riveによる説明イラスト

判断日：2026-09-17。採用。対象はiOS 26.0以上の本体アプリ。

## 目的と採用構成

nibbleの「保存した言葉を選び、コピーし、入力先で使う」という関係を、文章と短い動きで伝える。Aboutの説明文は読み上げ・文字拡大・検索可能なネイティブの文字として保持する。演出は説明の補助であり、クリップボードや保存データを操作しない。

RMLとRive CLIで制作し、Rive iOSの新Apple APIとData Bindingで表示する。2Dの図形、タイムライン、State Machineを使い、スクリプト・外部素材・外部通信・署名サービスを必要としない。Editorと`.rev`は工程に含めない。

| 層 | 所有する責務 |
| --- | --- |
| [RivePresentation](../../app/Packages/RivePresentation/README.md) | ローカルファイルの非同期読込、契約検査、再生インスタンスの生成、画面・アプリの寿命に応じた停止 |
| [AboutIllustration](../../app/Nibble/AboutIllustration.swift) | 説明の意味、配色、Reduce Motion、再生操作、読み上げ、読込失敗の回復 |
| [制作ソース](../../app/Animations/README.md) | 図形、時間、状態遷移、初期値、ホストとのData Binding契約 |
| [生成検査](../../scripts/rive_assets.py) | 制作入力と配布用ファイルのハッシュ、必要な名前・型・参照、固定CLI版 |

パッケージは製品名・色・リソース名・画面構成を持たない。他製品へ移す場合はパッケージディレクトリを移し、ホストが自身のアセットと契約を渡す。Riveの新APIを公開する薄い境界とし、プロパティの各型やレンダラーを独自APIへ重複実装しない。

## 所有と副作用

`RiveResource.load`はWorkerとFileの生成を待つ。FileがWorkerを保持する。共有できるのは読み込んだファイルであり、`makeSession`は毎回Artboard・State Machine・View Modelを生成する。一つのsessionは一つの表示だけが使用する。可変のData Binding値を画面間で共有しない。

呼出元は`.task`からロードを待ち、キャンセル後の結果を表示しない。Aboutのsessionは`@State`で画面の寿命に保持するため、SwiftUIのbody評価や配色変更で再読込・再入場しない。画面を破棄すると資源と購読も解放される。全アプリ常駐のWorkerや無制限のキャッシュを作らない。複数表示を持つ機能は、その機能の所有者でResourceを共有できる。

新Apple APIの呼出しはMainActorで行う。描画用のフレーム進行とランタイム内部のWorkerはRiveが管理し、アプリは独自のTimer・DisplayLink・生Taskを追加しない。値の設定や再生要求はData Bindingへ渡し、値の読み戻しを待つ検証と区別する。`active`は演出状態だけを表し、業務処理の成否に用いない。

SwiftUIの遷移は引き続きScopedAnimationが担当する。Riveのキャンバス内の動きはRMLのタイムラインが担当し、親Viewへアニメーションを伝播させない。

## 体験とアクセシビリティ

演出は4秒で一度だけ流れ、完成図で静止する。選択したカードの元を残すことで、データを移動・削除していないことを表現する。複製が少し持ち上がり、入力先へ移り、行が遅れて現れて収束する。待機中のループ、光の点滅、粒子は使わない。

一時停止・再生・もう一度見るは標準Buttonで操作する。実際のコピーやペーストではないため、キャンバスは操作対象とせず、読み上げは隣接する日本語の説明を使う。画像内にフォントを埋め込まず、文字拡大で説明が欠けないようにする。

Reduce Motionでは最初から完成図を表示し、再生ボタンを隠す。途中で有効にしても完成図へ進み、無効に戻しても自動再開しない。スクロールで見えない間、画面離脱、非アクティブ・バックグラウンドでは停止する。復帰は同じ再生位置を保つ。ロード中・失敗時にも図記号と説明文を示し、失敗時は再読み込みできる。

### 停止中の外観変更

rive-ios 6.27.0のViewは一時停止中のData Binding変更を描画しない。ホストは配色の更新後にCanvasの`renderingRevision`を増やし、表示用Viewの初回描画（時間差0）を要求する。File・Artboard・State Machine・View Modelは同じsessionを保持するため、再ロードや演出の先頭への移動は行わない。配色変更時だけ表示用Viewを再生成するコストを許容し、通常のSwiftUI更新では同じViewを使う。ランタイム更新時は、この制約と停止中の画像を再確認する。

## 選択肢と負担

| 案 | 評価 |
| --- | --- |
| 文字とSF Symbolsのみ | 実装とサイズの負担が小さい。複製の動きと二次動作の調整を再利用可能な制作ソースに持てない |
| SwiftUIで全て制作 | 単純な動きに向く。複数の図形・タイミング・状態の制作と画面コードが結びつく |
| 動画 | 再生は容易。配色・Reduce Motion・状態の制御、解像度とファイル量の調整が別途必要 |
| Rive | ベクターの小さな制作物とData Bindingを共有できる。ランタイムのサイズ、GPU資源、外部API更新への対応が必要 |

演出の強さや理解しやすさは製品判断であり、利用者調査による効果測定は未実施。導入に伴うアプリサイズと読み込みの負担を[検証記録](../rive-validation.md)に分けて記録する。

## バージョン、配布、見直し

CLI 1.0.4をNixの配布物ハッシュで、rive-ios 6.27.0をPackage.swiftのexact指定と共有Package.resolvedで固定する。これは本構成の採用版であり、将来の最新版を意味しない。制作CLIは公式配布のApple Silicon macOS版を使用する。Ubuntu CIはCLIやApple SDKを起動せず、生成契約とソースの規約を検査する。

RiveRuntimeは本体だけがリンクする。共有拡張には追加しない。MITライセンスと同梱ライセンスを配布物で保持する。スクリプトを採用する変更は、対象プラットフォームの署名・公開条件を再評価する独立した判断とする。認証情報をこの制作基盤へ持ち込まない。

更新時はCLIによる作成可能性、新APIとData Bindingの互換性、iOS 26.0の条件、実行検証26.5、サイズと描画コストを再確認する。SDKの非同期実装や破棄時の内部動作は外部依存としてレビューする。生成失敗・ロード失敗時も説明文を利用できることを維持する。

## 根拠

2026-09-17に公式資料と6.27.0の公開ソース、CLI 1.0.4のhelp・schemaを確認した。

- [CLIの役割](https://rive.app/docs/cli/overview)：制作、ローカル出力、画像とデータ検証。
- [Apple runtime](https://rive.app/docs/runtimes/apple/apple)：新API、WorkerとFileの寿命、MainActorの条件。
- [Data Binding](https://rive.app/docs/runtimes/apple/data-binding)：ホストとView Modelの型付き接続。
- [6.27.0公開版](https://github.com/rive-app/rive-ios/releases/tag/6.27.0)：採用バージョン。
- [パフォーマンスの指針](https://rive.app/docs/getting-started/best-practices)：資源再利用と画面外での停止。具体的な性能値は対象環境で測る。
