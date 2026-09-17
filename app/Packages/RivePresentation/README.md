# RivePresentation

iOS 26.0以上のSwiftUIアプリで、ローカルの`.riv`を読み込み、独立した再生状態を表示するSwift Package。Rive iOSの新Apple runtime APIとData Bindingを使用する。製品固有のアセット、配色、文章、演出の状態はホストアプリが管理する。

Swift tools 6.0、rive-ios 6.27.0のexact指定を[Package.swift](Package.swift)に定義する。アプリは解決済みの依存を`Package.resolved`で共有する。Legacy APIやState Machineの旧inputsへの接続は提供しない。

## 公開APIと契約

| API | 入力と結果 |
| --- | --- |
| `RiveResource.load(named:in:)` | リソース名とBundleを受け取り、FileとそのWorkerを保持するResourceを非同期に返す。呼出しごとに読み込むため、再利用するResourceは呼出元で保持する |
| `RiveContract` | Artboard、State Machine、View Modelの名前と、必須のroot property名・型を宣言する |
| `RiveResource.makeSession(_:)` | 実ファイルの必須プロパティを検査し、指定したArtboard、State Machine、View Modelのdefault instanceからSessionを生成する |
| `RiveSession` | 新APIの`rive`とData Bindingの`data`を公開する。一つのSessionは一つの表示だけが使用する |
| `RiveCanvas(session:paused:renderingRevision:)` | SessionをSwiftUIに表示し、ホストの停止要求と画面・アプリの状態に従ってフレーム進行を止める |

root propertyはView Model直下のプロパティを指す。契約検査はその必須名と型を確認する。追加プロパティを拒否する厳密なスキーマ検証や、値域・初期値・遷移の正しさの検証は行わない。アセットとホストの振る舞いは利用側のテストで確認する。

必須プロパティの欠落・型不一致は`RiveContractError.property(viewModel:name:)`になる。ファイル、Artboard、State Machine、View Modelの作成失敗はランタイムのエラーを呼出元へ返す。別のアセットやAPIへ自動で切り替えない。

## 所有関係と接続の順序

ResourceとSessionの生成・操作はMainActorで行う。ロードと生成はasync APIで、開始時と結果を返す前にキャンセルを確認する。基盤は独自のタスクや再生時計を起動しない。

1. ホストがアセットの名前・型を`RiveContract`として宣言する。
2. 画面または機能の所有する`.task`からResourceのロードとSessionの生成をawaitする。
3. 外観や動作設定をData Bindingへ渡し、キャンセルされていない結果を`@State`等へ保持する。
4. 同じSessionをCanvasへ渡す。bodyの再評価を理由にロード・Session生成を繰り返さない。
5. 必要なプロパティを画面所有のタスクで購読し、キャンセル時に購読を終了する。

| 資源・状態 | 所有と再利用 |
| --- | --- |
| File / Worker | ResourceがFileを保持し、FileがWorkerを保持する。同じファイルを使う機能内で共有できる |
| Artboard / State Machine / View Model instance | `makeSession`ごとに生成する。表示間で可変状態を共有しない |
| Session | 表示の所有者が保持する。生存中は再生位置とData Binding値を保持する |
| Canvasの表示用View | Sessionを描画する。一つのSessionを二つのCanvasへ同時に渡さない |
| 読込・購読タスク | ホストが開始、キャンセル、失敗時の表示を管理する |

入力値とtriggerの書込みは演出への要求であり、処理結果の読み戻しとは区別する。演出の完了通知を保存・通信・コピーなどの業務状態の成功判定に用いない。

## 停止、復帰、再描画

Canvasは`paused`がtrue、Viewが離脱中、または`scenePhase`がactive以外のときに停止する。全条件が解除されると同じSessionの位置から進む。スクロールで見えなくなっただけではViewが破棄されないため、ホストが可視性を判定して`paused`へ渡す。

Sessionの破棄と新規生成は、初期状態からの開始を意味する。画面を離れても位置を保持したい場合は、その寿命を含む所有者にSessionを置く。

`renderingRevision`は、配色などの変更を停止中にも反映するための描画更新番号である。rive-ios 6.27.0では一時停止中のData Binding変更だけでは再描画されない。番号が変わると表示用Viewだけを作り直し、同じSessionを時間差0で描画する。ファイルの再ロードや演出のリセットには使用せず、外観変更など必要な場合だけ更新する。

## ホストが決めること

- 読込中・失敗時の表示、再試行、キャンセル後の結果を採用しない処理。
- アセット固有の名前、初期値、値域、更新方向、状態遷移。
- Reduce Motionに適した静止状態と切替方法、スクロール時の可視性。
- 表示サイズ、比率、fit、クリッピング、タッチを受けるかどうか。
- 説明文、読み上げ、操作ボタン、Dynamic Typeへの対応。

Canvasはサイズやアセットの意味を強制しない。fitなどのランタイム設定は`session.rive`が公開する新APIで行う。インタラクティブなアセットでは、描画範囲とタッチ座標の一致を対象環境で検証する。

## 導入と移設

このディレクトリのPackage.swiftとSourcesは、nibble固有のパスや型に依存しない。別リポジトリへ移す場合も、製品側で次の接続を用意する。

1. Packageのproductをアプリへ追加し、再生成可能な制作ソースと`.riv`を製品側で管理する。
2. `.riv`を指定Bundleへ同梱し、契約とホストの所有者を実装する。
3. 通常のアプリ起動でRiveRuntimeを解決できるよう、Frameworkの同梱とrunpathを確認する。
4. 依存lockとライセンスを管理し、実バイナリの契約、独立状態、停止・復帰、失敗時の表示をテストする。

本リポジトリの接続例は[AboutIllustration](../../Nibble/AboutIllustration.swift)、実行評価は[Rive検証](../../../docs/rive-validation.md)を参照する。設計理由と更新時の判断基準は[演出設計](../../../docs/decisions/0004-rive-presentation.md)に定義する。
