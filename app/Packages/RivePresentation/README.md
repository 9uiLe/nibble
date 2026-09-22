# RivePresentation

RivePresentationは、iOS 26.0以上のSwiftUIアプリでローカルの `.riv` を表示するSwift Packageである。ファイルの読込、アセットの接続契約、表示ごとに独立した再生状態、画面の寿命に応じた停止と描画を扱う。

利用側のアプリをホストと呼ぶ。ホストはアセット、Sessionの保持期間、配色、可視性、再生方針、読込失敗からの回復、説明文とアクセシビリティを管理する。パッケージはnibble固有の型やパスに依存しない。

## 再生を構成する三つの単位

| 単位 | 保持するもの | 寿命と再利用 |
| --- | --- | --- |
| Resource | 読み込んだFile。Fileは処理を実行するWorkerを保持する | 同じファイルから複数のSessionを生成できる。保持期間と共有範囲はホストが決める |
| Session | 描画面であるArtboard、演出を進めるState Machine、型付きデータを持つView Model instanceを接続したRive | 一つの表示が所有する可変状態。同時に複数のCanvasへ渡さない |
| Canvas | Sessionを描画するSwiftUI Viewと内部のRiveUIView | Sessionを保持したまま表示用Viewを取り外し、再び表示できる |

Resourceを共有しても、Sessionごとの再生位置とData Binding値は独立する。SessionのRiveもFileを保持するため、Sessionが生存している間はResourceの変数を破棄してもFileとWorkerを利用できる。表示を閉じるときは、不要になったSessionとResourceへの参照をホストが解放する。

## 公開APIと接続契約

| API | 入力と結果 |
| --- | --- |
| `RiveResource.load(named:in:)` | リソース名とBundleを受け取り、Fileを読み込んだResourceを返す |
| `RiveContract` | Artboard、State Machine、View Modelの名前と、必須のroot property名・型を宣言する |
| `RiveResource.makeSession(_:)` | 実ファイルを契約と照合し、独立したArtboard・State Machine・View Modelのdefault instanceを接続したSessionを返す |
| `RiveSession` | 描画・再生設定の `rive` と、Data Bindingを操作する `data` を公開する |
| `RiveCanvas(session:paused:renderingRevision:)` | Sessionを表示し、停止要求とView・sceneの状態をフレーム進行へ反映する |

root propertyはView Model直下のプロパティである。必須名の欠落や型の不一致は `RiveContractError.property(viewModel:name:)` になる。ファイルの読込と各オブジェクトの生成に失敗した場合はruntimeのエラーを呼出元へ返す。

契約検査の範囲は必須プロパティの名前と型である。値域、初期値、追加プロパティ、演出の遷移はホスト側で検証する。型付きプロパティの読み書きにはruntimeのData Binding APIを直接使う。値やtriggerの書込みは演出への要求であり、読み戻した演出状態を保存・通信・コピーなどの業務処理の成功判定に使わない。

## 読込と結果の採用

ResourceとSessionの生成・操作はMainActorで行う。生成APIはasyncで、開始時と非同期の各生成・照合処理の後にキャンセルを確認する。呼出元のタスクがキャンセルされた場合は、生成したオブジェクトを結果として返さない。パッケージ自身はタスクの所有者やキャッシュを持たない。

ホストは次の順序で表示を準備する。

1. アセットの接続名と型を `RiveContract` に宣言する。
2. 画面や機能が所有する `.task` から、読込とSession生成を直接awaitする。
3. キャンセルと要求の有効性を確認し、Sessionを画面や機能の状態へ保持する。
4. 表示時点の配色・動作設定をData Bindingへ渡してから、SessionをCanvasへ渡す。
5. 外観や表示条件の変更を、保持しているSessionとCanvasへ反映する。

同じ表示の再描画ではResourceやSessionを生成し直さない。ホストがSessionを保持している期間は、再生位置とData Binding値が残る。Sessionを破棄して再訪時に生成すれば、独立した初期状態からの開始となる。

ホストは、取消や別の要求に置き換わった処理の結果を採用しない責任を持つ。再試行、代替表示、エラー文言、出力の購読が必要な場合のタスク所有もホストが定義する。

## 比較と停止・再描画

Canvasは「ホスト入力の反映」「周期的なフレーム進行」「設定変更の単発描画」を別の制御として扱う。

### ホスト入力の反映

Canvasと内部の表示用Viewは `@Equatable` を宣言する。Session参照は不変の `let` として保持し、`@SkipEquatable` で比較から除外する。新しいView値を生成するたびにprivateな `inputRevision` を作り、ホスト入力の更新を比較で取りこぼさないようにする。View値のコピーは同じUUIDを持つ。

`inputRevision` は比較だけに使う。表示用Viewの識別子やSessionの生成条件には使わない。SwiftUIから更新を受けた表示用Viewは、Rive参照と停止状態に変更がある場合にそれぞれを反映する。

### 停止条件の合成

Canvasの停止状態は次のORで決まる。

| 条件 | 情報の所有者 |
| --- | --- |
| `paused == true` | ホスト。可視性、選択タブ、別画面による遮蔽などをまとめて渡す |
| CanvasのViewが表示されていない | Canvasの表示・離脱通知 |
| `scenePhase != .active` | Canvasが所属するsceneの環境値 |

すべての停止理由が解除されるまで周期的なフレーム進行を止める。復帰時は時間差0で最初のフレームを評価し、同じSessionの再生位置から進む。停止していた実時間を演出へ加算しない。

スクロールで画面外になってもViewは生存し得るため、可視性はホストから停止要求として渡す。可視性の初回通知前の扱いや判定閾値もホストが決める。所属sceneの状態はCanvasが取得するため、ホストによるアプリ全体の通知監視は不要である。

表示用Viewを取り外す `dismantleUIView` は、同期的にpauseを設定してRive参照を外す。Viewが一時的に保持されても、再生時計とFileを保持し続けないためである。再生の時計はruntimeが所有し、パッケージは独自の時計やフレーム購読を持たない。

### 停止中の描画更新

`renderingRevision` は、ホストが渡す描画更新番号である。rive-ios 6.27.0では停止中のData Binding変更だけでは再描画されないため、番号の変更によって表示用Viewを再生成する。同じSessionを時間差0で描き、再生位置とData Binding値を保持する。

| 変更 | 表示用Viewの扱い |
| --- | --- |
| ホスト入力の通常更新、停止、復帰 | 同じ表示用Viewへ入力を反映する。`renderingRevision` は変えない |
| 停止中の配色など、Data Binding値の描画反映 | 必要な値変更時に `renderingRevision` を進め、表示用Viewを一度再生成する |
| 寸法 | 同じ表示用Viewへ反映する。runtimeが時間差0で単発描画する |

初回や設定変更の単発描画は、停止中でも行われる。周期的なフレーム進行の再開とは区別する。`renderingRevision` はFileやSessionの再生成、演出のリセット、フレームごとの更新には使わない。

## ホストへの導入

ホストは、アセット契約、Sessionの保持期間、読込と再試行、表示時の配色、可視性、再生方針、説明文と読み上げを定義する。Canvasは演出の意味やレイアウトを決めない。fitなどの描画設定は `session.rive` へ指定し、操作可能なアセットでは表示範囲とタッチ座標を照合する。Reduce Motionへの追従方針もホストがアセット固有のData Bindingへ渡す。

[Package.swift](Package.swift)はSwift tools 6.0とswift-app-macrosのexact指定を持つ。RiveRuntimeは6.27.0へ描画先取得の修正を適用し、[固定ソースからのビルド](../../../docs/architecture/presentation.md#描画先の取得)が生成するローカルPackageを参照する。AppMacrosのコンパイルにはSwift 6.3対応ツールチェーンを使用し、利用アプリはPackage.resolvedを共有する。接続にはApple runtime APIのWorker、File、Rive、ViewModelInstanceとData Bindingを使う。

別のアプリやリポジトリへ導入するときは、次の接続を用意する。

1. 修正済みRiveRuntimeを同じ固定入力から生成し、Package.swiftのローカル依存先を接続する。Packageのproductを追加し、制作ソースと生成済み `.riv` を製品側で管理する。
2. `.riv` を指定Bundleへ同梱し、契約、所有者、ホストViewを実装する。
3. RiveRuntimeのFramework同梱と探索経路を設定し、通常のアプリ起動で確認する。
4. 依存lockとライセンスを管理し、実バイナリの契約、独立状態、停止・復帰、設定変更、失敗回復を検証する。

nibbleでの接続例は[AboutIllustration](../../Nibble/Presentation/AboutIllustration.swift)、入力仕様は[アセット契約](../../Animations/README.md#接続契約)、製品の保持期間と再生方針は[演出設計](../../../docs/architecture/presentation.md)にある。
