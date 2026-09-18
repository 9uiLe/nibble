# RivePresentation

iOS 26.0以上のSwiftUIアプリで、ローカルの`.riv`を読み込み、一つの表示ごとに独立した再生状態を持たせるSwift Package。ファイルの再利用、接続契約の検査、画面の寿命に合わせたフレーム停止を担当する。アセット、配色、文章、演出の意味は利用側のアプリ（ホスト）が管理する。

## 依存とAPI世代

[Package.swift](Package.swift)はSwift tools 6.0、rive-ios 6.27.0、swift-app-macros 0.3.0のexact指定を持つ。AppMacrosのコンパイルにはSwift 6.3対応ツールチェーンが必要である。利用アプリは解決済みの依存をPackage.resolvedで共有する。

使用するのはApple runtime APIの`Worker`、`File`、`Rive`、`ViewModelInstance`とData Bindingである。Legacy APIやState Machineの旧inputsへの接続は提供しない。Data Bindingの型付きプロパティ操作はランタイムのAPIを直接使い、このパッケージで重複実装しない。

## 公開API

| API | 入力と結果 |
| --- | --- |
| `RiveResource.load(named:in:)` | リソース名とBundleからFileを読み込み、FileとそのWorkerを保持するResourceを返す |
| `RiveContract` | Artboard、State Machine、View Modelの名前と、必須のroot property名・型を宣言する |
| `RiveResource.makeSession(_:)` | 実ファイルを契約と照合し、独立したArtboard・State Machine・View Modelのdefault instanceを生成して接続する |
| `RiveSession` | 再生・表示設定の`rive`と、Data Bindingの`data`を公開する。一つの表示が所有する |
| `RiveCanvas(session:paused:renderingRevision:)` | SessionをSwiftUIへ表示し、停止要求・Viewの寿命・アプリの状態に従ってフレーム進行を制御する |

root propertyはView Model直下のプロパティを指す。契約検査は必須名と型を照合する。追加プロパティ、値域、初期値、演出の遷移は検査範囲に含まれず、ホスト側のテストで確認する。

必須プロパティの欠落・型不一致は`RiveContractError.property(viewModel:name:)`になる。ファイル、Artboard、State Machine、View Modelの作成失敗はランタイムのエラーを呼出元へ返す。失敗時の表示と再試行はホストが決める。

## 所有関係

| 対象 | 所有と再利用 |
| --- | --- |
| File / Worker | ResourceがFileを保持し、FileがWorkerを保持する。同じファイルを使う機能内でResourceを再利用できる |
| Artboard / State Machine / View Model instance | `makeSession`ごとに生成する。表示間で可変状態を共有しない |
| Session | 画面または機能の所有者が保持する。生存中は再生位置とData Binding値を保持する |
| Canvasの表示用View | 一つのSessionを描画する。一つのSessionを二つのCanvasへ同時に渡さない |
| 読込・購読タスク | ホストが開始、キャンセル、結果の採用を管理する |

ロードは呼出しごとに行われるため、共有するResourceは呼出元で保持する。画面の再描画を理由にResourceやSessionを作り直さない。画面を離れても位置を残す場合は、その期間を含む所有者にSessionを置く。Sessionを破棄して再生成すると初期状態からの開始になる。

## 接続の順序と実行条件

ResourceとSessionの生成・操作はMainActorで行う。生成APIはasyncで、開始時と結果を返す前にキャンセルを確認する。パッケージは独自のタスクや再生時計を起動しない。

1. ホストがアセットの名前・型を`RiveContract`へ宣言する。
2. 画面や機能が所有する`.task`から、ロードとSession生成を直接awaitする。
3. 外観や動作設定をData Bindingへ渡し、キャンセルされていない結果を`@State`等へ保持する。
4. 同じSessionをCanvasへ渡し、所有者の寿命にわたって再利用する。
5. 出力を必要とする場合だけ、所有するタスクから購読し、キャンセル時に終了する。

入力値やtriggerの書込みは演出への要求である。読み戻しは演出の状態を示し、保存・通信・コピーなどの業務処理の成功を判定するものではない。非同期処理の失敗、キャンセル後の結果を採用しない処理、再試行の条件はホストの責務とする。

## 比較と停止・再描画

Canvasは`@Equatable`を宣言し、privateな`inputRevision`でホストが渡し直したSessionと設定を反映する。Sessionは比較から除外する不変の参照であり、同じView値のコピーだけが同じrevisionを持つ。このrevisionは表示のidentityやSessionの寿命に使わない。

Canvasは次のいずれかが成立するとフレーム進行を止める。

- ホストの`paused`がtrue。
- CanvasのViewが離脱している。
- `scenePhase`がactive以外である。

すべて解除されると同じSessionの位置から進む。スクロールで見えなくてもViewは生存し得るため、ホストが可視性を判定して`paused`へ渡す。再生の方針はホストがアセット固有のData Bindingへ渡し、フレーム停止とは分けて扱う。OSのReduce Motionに追従する製品はホストで接続できる。nibbleはmotionAllowedをtrueに固定する。

`renderingRevision`は、停止中の配色変更などを反映する描画更新番号である。rive-ios 6.27.0では停止中のData Binding変更だけでは再描画されない。番号が変わると表示用Viewを作り直し、同じSessionを時間差0で描画する。FileやSessionの再生成、演出のリセットには使わない。必要な値変更時だけ更新し、フレームごとや通常のbody評価では変えない。

## ホストの設計事項

| 領域 | ホストが定義すること |
| --- | --- |
| アセット | 接続名、初期値、値域、更新方向、状態遷移、業務状態との関係 |
| 寿命と回復 | 読込中・失敗時の表示、再試行、Sessionの保持期間、購読の終了 |
| 表示環境 | 配色、自動再生と静止表示の方針、スクロール可視性 |
| レイアウト | サイズ、縦横比、fit、クリッピング、タッチの可否と座標の一致 |
| 利用可能性 | 説明文、読み上げ、操作ボタン、Dynamic Type |

Canvasはアセットのサイズや意味を強制しない。fitなどのランタイム設定は`session.rive`から行う。インタラクティブなアセットでは、表示範囲とタッチ座標が一致することを対象環境で確認する。

## アプリへの導入と別リポジトリへの移設

このディレクトリのPackage.swiftとSourcesはnibble固有のパスや型に依存しない。利用先では次の接続を用意する。

1. Packageのproductをアプリへ追加し、制作ソースと生成済み`.riv`を製品側で管理する。
2. `.riv`を指定Bundleへ同梱し、契約、所有者、表示用Viewを実装する。
3. RiveRuntimeのFramework同梱と探索経路を設定し、テストhostだけでなく通常アプリ起動を確認する。
4. 依存lockとライセンスを管理し、実バイナリの契約、独立状態、停止・復帰、設定変更、失敗時の表示を検証する。

接続例は[AboutIllustration](../../Nibble/AboutIllustration.swift)、演出の入力仕様は[アセット契約](../../Animations/README.md#接続契約)にある。採用理由と依存更新の基準は[演出設計](../../../docs/decisions/0004-rive-presentation.md)、実行済みの条件と限界は[検証記録](../../../docs/rive-validation.md)を参照する。
