# Swift実装の責務と境界

この規約は本体・拡張・Package・テスト・研究・検証基盤のSwiftへ適用する。モデルの操作完了、UIのタスク所有、表示の比較を宣言から判断できる構成にする。製品固有の状態遷移は[製品設計](decisions/0002-mvp-app.md)が所有する。

## 依存とビルド

| 役割 | 採用する入口 |
| --- | --- |
| UIタスクの所有・寿命・重複 | TaskingのViewTaskStore / TaskingCoreのTaskSlot |
| SwiftUIの表示変化と伝播遮断 | ScopedAnimationのAnimationScope / animationBarrier |
| View比較の生成 | AppMacrosの@Equatable / EquatableBodyView |
| RMLの表示 | ローカルPackageのRivePresentation経由でrive-iosのApple runtime API |

直接依存はexact version、全依存は[共有lock](../app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)で固定する。AppMacrosが要求するswift-syntaxを独立に選び直さない。swift-syntaxはMacのmacroビルド用で、iOS runtimeではない。

製品はSwift 6、strict concurrency complete、default isolation nonisolatedを使う。UIに必要なMainActorを明示する。AppMacrosの実行にはmacOS 26以上・Swift 6.3以上が必要で、取得したsource/revisionを確認して[個別にmacroを承認](../README.md#3-xcodeとswift-packageを準備する)。一括で検証を無効化しない。

Releaseは-Osize・whole-module・ENABLE_TESTABILITY=NO。ios.py testだけがテスト可能性を有効にする。ライセンスは[同梱告知](../app/Shared/ThirdPartyNotices.txt)と各依存の条件を維持する。

## 操作APIと開始API

モデルの操作はasyncとし、受理した処理と結果反映を完了まで待つ。呼出元は直接awaitした直後に状態・永続化を検査できなければならない。同期メソッド・initializer・setter・observerの内部や、完了前に戻るasync操作から隠れたタスクを開始しない。

既存async処理は直接awaitし、親と寿命を共有する並行処理はasync let/task group、View/入力IDに結び付く処理はSwiftUI taskを使う。同期UIイベントだけが所有者のstartTaskを通して開始する。モデルへstoreや開始closureを渡さない。

ViewTaskStoreを持てるのはView・UIViewController・MainActorの専用TaskOwner。Model/Observable型は所有者にしない。操作ID、寿命、重複方針、取消を要求する画面/sceneイベント、終了待ちを定義する。cancelExistingは停止要求であり、結果反映時の有効性確認を省略できない。

### 実装例

ExampleModel.refreshは読込と反映を完了まで待つ操作である。画面終了で停止を求める操作は次のように所有する。シートをまたいで完了する処理にはsceneの終了条件を使う。

```swift
import AppMacros
import SwiftUI
import Tasking

@MainActor
@Equatable
struct ExampleView: View {
    private let inputRevision = UUID()
    @State private var tasks = ViewTaskStore()
    @SkipEquatable let model: ExampleModel

    var body: some View {
        Button("更新") { startTask() }
            .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask() {
        tasks.start(id: "example.refresh", lifetime: .screenBound, policy: .cancelExisting) { cancellation in
            try cancellation.check()
            await model.refresh()
        }
    }
}
```

## 完了・キャンセル・永続化

取消は協調的な停止要求であり、確定したDBを巻き戻さない。読取結果は取消・要求ID・対象状態を確認して採用する。受理した書込は確定を待ち、永続化成功を取消エラーへ変えない。操作の業務エラーは入力を保持した回復可能な表示へ変換する。

同じ要求でも実行を識別し、遅れた成功・失敗・後始末で別の処理を変えない。所有者の重複/取消は所有者を通すテスト、モデルの完了は直接awaitするテストで確認する。空catchで失敗を消さず、正常な取消と分ける。非取消エラーをTaskingへ流すとDebug assertionになる。

## Viewの比較境界

比較の目的は、表示値が等しい場合に省略できる更新を明示し、入力や操作先が変わった場合はその変更を画面へ反映することである。View値の比較、動的な状態の観測、状態の寿命はそれぞれ独立して設計する。

### 適用範囲と方式の選択

自作のSwiftUI Viewはstructへ`@Equatable`を直接宣言する。本体、共有拡張、ローカルPackage、UIKit接続用のrepresentableを対象とする。`App`、`ViewModifier`、UIKitのクラス、外部パッケージの実装は対象外である。比較はMainActorへ隔離し、representableには`@Equatable(.mainActor)`を指定する。

| Viewが持つ入力 | 宣言と表示本体 | 比較と更新の方針 |
| --- | --- | --- |
| 値型の表示入力だけ | `@Equatable`、`@MainActor EquatableBodyView`、`equatableBody` | 全入力を比較し、等しい場合は入力比較による更新を省略できる |
| Binding・操作・参照などの親入力 | `@Equatable`、`View`、`body` | `inputRevision`を比較し、新しく構築されたViewの入力を反映する |
| 所有するState・Environment等だけ、または格納入力なし | `@Equatable`、`View`またはrepresentable | 動的な依存の更新をSwiftUIに任せる。親入力を区別するUUIDは持たない |

### 値だけを受け取る表示

表示を決める全入力を通常の値型`let`で保持し、同じstructの`equatableBody`に内容を書く。`EquatableBodyView`が提供する`body`が比較を適用する。呼出元はそのViewを通常どおり配置する。

```swift
import AppMacros
import SwiftUI

@Equatable
struct CaptionContent: @MainActor EquatableBodyView {
    let text: String

    var equatableBody: some View {
        Text(text)
    }
}
```

操作closure、DynamicProperty、参照モデル、globalな可変状態はこの境界の外に置く。比較対象の値だけで表示内容を判断できることをレビューし、値型に含まれる参照や独自の等価比較にも注意する。標準部品の外観・文字サイズはSwiftUIのenvironmentで更新する。

### 親入力を受け取る表示と操作

Bindingの現在値が同じでも、その書込先は異なり得る。操作closureも、表示値を変えずに異なる項目やモデルを参照できる。AppMacrosはDynamicPropertyと直接記載されたclosureを比較から除外するため、これらの接続先の違いを表示値の比較だけでは判定できない。

親入力を持つ通常のViewは、最初の格納プロパティに`private let inputRevision = UUID()`を置く。UUIDはView値の生成時に作り、生成された等価比較に含める。View値をコピーするとUUIDも引き継ぎ、新しく構築すると別のUUIDになる。親が渡し直したBinding・操作・参照・contentを、以前の接続と同じものとして省略しないための契約である。

比較できないモデル参照やgenericなcontentは、不変の`let`に限り`@SkipEquatable`で除外できる。除外した入力を持つViewには、同じstruct内で比較される`inputRevision`が必須である。`let`が固定するのは格納された参照や値であり、参照先モデルの内部状態が不変になるわけではない。

| 入力 | 更新の責務 |
| --- | --- |
| Binding / Bindable / ObservedObject、FocusStateのBinding | 書込先・観測先を親が決める。Viewは新しい接続を受け取る |
| 操作closure | 親が操作対象と処理を接続する。Viewは現在のclosureを呼ぶ |
| モデル・Store・Session | 親が参照の寿命を持つ。内容の変化はObservationや各ランタイムの更新経路で反映する |
| genericなcontent | 親が子の構成を渡す。受け取るViewは値比較で同一性を推測しない |

### 状態の所有と寿命

State、StateObject、Environment、AppStorage等の更新はSwiftUIの依存関係で扱う。通常の格納入力を持たないViewには`inputRevision`を置かない。initializerでStateの初期値を受け取る場合は、その初期値と、表示中も差し替わる親入力を区別する。Stateの保持期間はViewのidentityに従う。

`inputRevision`は比較専用であり、`.id()`、`ForEach`、永続データのIDには使わない。入力の差し替えのために、編集内容、フォーカス、タスク所有者、RiveのSessionを作り直さない。RiveCanvasの描画更新番号`renderingRevision`は別の役割を持ち、[RivePresentationの契約](../app/Packages/RivePresentation/README.md#比較と停止再描画)に従う。

### 実装上の制約と受入条件

比較はAppMacrosで生成し、手書き`==`、直接の`.equatable()`・`EquatableView`・`equatableBody`参照を使わない。データ型ではSwiftの標準Equatable合成とgenericなEquatable制約を使用できる。

検査するのは、全Viewの比較宣言、表示値の変更・復元、同じ現在値を持つ別Bindingへの差し替え、操作先の更新、同じ入力での環境更新である。構文Lintとcompilerで宣言を検査し、マウント済みViewのテストと実操作で反映を確認する。各表示入力は一つずつ変更して元へ戻す。複数入力を同時に変えると、一方の比較漏れを他方が隠す。callbackの直接呼出しだけを、マウント済みViewの接続保証にしない。

`inputRevision`を持つViewは、親が構築し直した入力に対する比較による更新省略を行わない。この方式は接続先の整合性を優先する。描画・応答性能は比較宣言の数から判断せず、同条件の計測で評価する。フレームワークの比較と寿命の前提は、[Appleの比較API](https://developer.apple.com/documentation/swiftui/view/equatable())と[identity・寿命・依存関係](https://developer.apple.com/videos/play/wwdc2021/10022/)を参照する。


## アニメーションの境界

独自の表示変化は名前付きAnimationScopeへ限定し、valueまたはproxyのscope.animateを使う。複数triggerのfactoryはAnimationTrigger.animationと型名を明記する。入力等にはanimationBarrierを置く。

OSのsheet transactionとアプリ内部の変化は境界を分ける。Debug診断はmodifierへ届くtransactionを扱い、子孫の全表示やUIKitを保証しない。入力・スクロール・画面遷移は実行確認する。製品の表示設定は[固定方針](design/decisions/0002-fixed-interface.md)に従う。

## Riveの表示境界

RivePresentationのApple runtime APIとData Bindingを使い、Legacy API、Timer、DisplayLink、生Taskでフレームを進めない。ホストのtaskからロードとSession生成を直接awaitし、取消済みの結果を採用しない。業務状態と演出は独立させる。所有と停止中描画は[Package契約](../app/Packages/RivePresentation/README.md)、制作は[アセット手順](../app/Animations/README.md)に従う。

## Lintと禁止する直接使用

`swift-library-policy`は字句解析とSwift構文木を使い、APIの使用箇所・タスク開始・View比較の規約を検査する。ローカルとUbuntu CIは同じNixのPython環境とlockに固定したSwift grammarを使う。違反時はファイル・行・列を表示し、終了コード1で失敗する。

```sh
nix develop --command python3 scripts/check_swift_policy.py
nix flake check --no-update-lock-file --print-build-logs
```

### 直接APIの制限

| 禁止するもの | 代表例 | 使用する入口 |
| --- | --- | --- |
| 生のTaskの生成・保持・別名・関数参照 | `Task {}`、`Task.detached`、`Task<…>.init`、Task型handle | Tasking、構造化された処理 |
| 別scheduler | `DispatchQueue`、`DispatchWorkItem`、`DispatchSource`、`OperationQueue`、`BlockOperation`、`Thread`、`Timer` | Taskingによる所有、協調的なsleep |
| SwiftUIの直接アニメーション | `withAnimation`、`withTransaction`、`Transaction`、`.animation`、`.transaction`、`.phaseAnimator`、`.keyframeAnimator` | scope・proxy・barrier |
| UIKit / Core Animationの直接アニメーション | `UIView.animate`・`transition`等、`UIViewPropertyAnimator`、CAAnimation系、`CATransaction`等 | ScopedAnimation |
| 直接の比較 | `.equatable`、`EquatableView`、`.equatableBody`、手書き`==` | AppMacros、データの標準Equatable合成 |

対象名は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)に定義する。予約名は別用途にも使わない。SQLiteのhelperには`readTransaction`・`writeTransaction`を使い、共通の確定・rollbackをprivateな`performTransaction`へ閉じ込める。

字句解析はコメント・通常/raw/複数行文字列・regexの本文を読み飛ばし、実行される補間を検査する。改行・コメントを挟む呼出し、修飾名、backtick、型aliasも対象とする。

### タスク開始境界の制限

[scripts/swift_task_boundary.py](../scripts/swift_task_boundary.py)は次の構文を検査する。

| 検査対象 | 許可する形 |
| --- | --- |
| storeの構築 | 所有者のprivateプロパティへ`ViewTaskStore()`を`tasks`、`TaskSlot()`を`taskSlot`として直接代入 |
| 所有する型 | `View`・`UIViewController`・`@MainActor *TaskOwner`。`*Model`・`@Observable`は不可 |
| storeの参照 | 予約したプロパティへの対応メソッドの直接呼出し。型alias・生成関数・引数注入・返却・再代入・capture・メソッド参照は不可 |
| 開始メソッド | 所有者の`startTask`。ViewTaskStoreの開始は同期。TaskSlotのactor呼出しが必要な専用所有者には`async startTask`を許可 |
| 開始メソッドの使用 | 許可した開始境界からの直接呼出し。通常メソッドによるラップ、関数参照、別名化は不可 |
| 所有者のテスト | `@Test`の本体でローカルstoreの直接構築と開始を許可。operation内の再開始やaliasは不可 |

開始境界は`startTask`、Buttonのaction、`SnippetRow.perform`・`LibraryNotice.restore`の同期イベント、`onAppear`・`onDisappear`・`onChange`・`onOpenURL`、sheet/fullScreenCoverの`onDismiss`、UIViewControllerのoverride `viewDidLoad`・`viewDidAppear`・`viewWillAppear`、`@Test`の本体とする。Buttonのlabelやsheetのcontentなど、表示を構築するclosureは含めない。

通常の同期/asyncメソッド、initializer、getter・setter・observer、任意のclosure、SwiftUI `.task`、Taskingのoperationからの開始を拒否する。ViewTaskStore.startをasyncで包む形も許可しない。予約名以外の任意の`.replace`はこの規則の対象外である。

### View比較境界の制限

[scripts/swift_equatable_policy.py](../scripts/swift_equatable_policy.py)は同じ構文木から次の形を検査する。

| 検査対象 | 許可する形 |
| --- | --- |
| 全Viewの宣言 | `View`・representable・`EquatableBodyView`のstructへ`@Equatable`を直接宣言 |
| 値比較の境界 | `@MainActor EquatableBodyView`と同じstructの`equatableBody`。1つ以上の通常の値型`let`入力を比較。wrapper、可変入力、closure、比較除外、独自bodyは不可 |
| 通常のView | `body`を実装する。所有するDynamicProperty以外の格納入力には`private let inputRevision = UUID()`が必要 |
| 比較除外 | revisionを持つ通常のViewの不変`let`に限り`@SkipEquatable`を許可。revision自身の除外・可変化・外部注入は不可 |
| 準拠の可視性 | View・representable・Equatableのtypealias、Viewの派生protocol、EquatableBodyViewの派生protocol・extension準拠は不可 |
| 宣言の配置 | `body`・`equatableBody`・Equatable準拠をextensionへ移さない |

これらは比較境界を宣言から読み取るためのリポジトリ規約である。MainActorへの隔離と生成される比較の型適合はAppMacrosの診断とSwift compilerで確認する。Lintだけで型と隔離の正しさを判定しない。

### 検査対象と保証範囲

所有するSwiftソースを再帰的に探索する。`artifacts`・`.build`・`DerivedData`等の生成物は除外する。依存コードは`artifacts`以下に取得し、その内部実装は対象に含めない。Swift sourceとsource directoryのsymlink、読めない入力、対象0件はエラーとする。

抑制コメント・ファイル単位の例外は設けない。未対応・壊れた構文も失敗させる。grammarが未対応の`isolated deinit`は`isolated`だけを同じbyte長の空白へ置換して解析し、本体の検査と元ソースの診断位置を保つ。

| 確認手段 | 担当する契約 |
| --- | --- |
| 構文Lintとその回帰テスト | 禁止API・タスク開始・比較境界の構文、違反例の拒否、診断位置 |
| Swift compilerとマクロ診断 | 型適合、actor隔離、生成される比較の適合 |
| 製品テスト | APIをawaitした時点の結果、所有者の重複・キャンセル、表示入力と環境変更の反映 |
| コードレビュー | 値だけで表示が決まること、外部APIの副作用、closureや参照型の意味 |
| Simulator操作・画像・録画 | 入力、通知、遷移、共有、表示設定による実際の挙動 |
| 同条件の性能測定 | 描画回数、応答時間、メモリへの影響 |

Lintは型解決・マクロ展開・全プログラムの副作用解析を行わない。独自macroや外部APIの内部動作、callback登録、操作完了、alias越しの入力の意味は保証範囲外である。許可する入口や構文を変更する場合は、規則・回帰テスト・製品テストをそろえる。


## 採用理由と更新条件

Taskingは所有と重複、ScopedAnimationは適用範囲、AppMacrosは値比較と親入力更新を宣言できるため使う。製品側は終了イベント、伝播、比較入力と状態寿命を設計し、compiler・テスト・画面・性能で確認する。

依存の更新はexact要求・lock・ソース・ライセンス・対応OSを照合する。保守停止、OS/toolchain不適合、実測悪化、表現上の制約を見直し条件とする。判断と実施範囲は[製品の検証範囲](mvp-validation.md)に対応させる。

## ツールチェーン上の注意

Swift 6.3.2ではKeyboardのBindingへsetterのメソッド参照を渡す構成でIR生成が終了し、明示的なsetter closureでビルドが成立する条件を確認している。該当箇所を簡略化する場合は製品targetのビルドで確認する。コンパイラー内部の原因と新しい版での解消は未確認。
