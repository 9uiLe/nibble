# Swift実装の責務と境界

nibbleのSwift実装は、依存の所有者、外部状態への作用、操作の完了、タスクの寿命、表示の更新条件をコードから読み取れる構成にする。この規約は本体・共有拡張・テスト・研究用アプリ・検証用Swiftへ適用する。製品の機能とデータの契約は[製品設計](decisions/0002-mvp-app.md)、実行手順は[MVP手順](mvp.md)、対象ソースごとの観測は[検証結果](mvp-validation.md)に定義する。

## 責務と用語

モデルは処理と状態を持ち、UIは処理を開始するタイミングとタスクの寿命を管理する。すべての自作Viewに比較を宣言し、表示値、親からの入力、Viewが所有する状態に応じて更新条件を定める。アニメーションは変化させる表示部分へ適用する。

| 用語 | 意味 | 実装する場所 |
| --- | --- | --- |
| 操作API | 処理と結果反映を完了まで待てる`async`メソッド | モデル・保存層 |
| タスク所有者 | タスクの開始、重複判定、終了時のキャンセルを管理するUI側の型 | View・UIViewController・専用の`*TaskOwner` |
| 比較境界 | 入力値の等価比較で表示更新を制御するViewの範囲 | 値だけを受け取る表示用View |
| 親入力 | 親Viewが渡す表示値、Binding、操作closure、モデル参照、子のcontent | 受け取るViewの格納プロパティ |
| `inputRevision` | View値の生成ごとに作る比較用UUID。同じ表示値でも接続先が異なり得る親入力を区別する | 親入力を持つ通常のView |
| Viewのidentity | SwiftUIが同じ表示とその状態寿命を対応付ける識別。Viewの構造と明示的なIDで決まる | View階層、`ForEach`、必要な箇所の`.id()` |
| アニメーションscope | 値の変化または明示的な操作にアニメーションを付ける範囲 | `AnimationScope`で囲む表示部分 |
| barrier | 親から届くアニメーションを取り除く境界 | `animationBarrier()`を付ける表示部分 |
| snapshot | ある時点の下書きを固定した値。処理待ちの間に画面の入力が進んでも変化しない | 編集画面からモデルへ渡す`Draft` |

## 依存の構成と副作用

本体の入口は`NibbleApp`、共有拡張の入口は`ShareViewController`である。入口が`SnippetStorage.sharedContainer()`で保存層を作り、画面とモデルへinitializerで渡す。本体の一覧・検索・削除一覧は同じ保存層を使い、表示状態は各モデルが独立して保持する。拡張は自身の保存層を共通編集へ渡す。

| 境界 | 実装する契約 |
| --- | --- |
| 保存先 | `SnippetStorage`がApp Groupを解決する。最初の操作時に解決し、取得失敗を回復可能なエラーとして返す |
| 永続化 | モデルは`LibraryStorage`・`DraftEditing`を参照する。`SnippetStore`が接続を所有・直列化し、`SnippetQueries`・`DraftQueries`・`SnippetCommands`が同期SQLを実行する。トランザクション中は中断しない |
| 同期OS操作 | `LibraryModel`は`LibraryEffects`を参照する。`SystemLibraryEffects`がMainActor上でコピー・読み上げ通知を実行し、処理の終了前に戻らない |
| UIイベント | 行は表示値と意味のある操作意図を受け渡す。親画面が意図をモデルの操作へ接続し、タスクを所有する |
| 一時的な表示 | `LibraryNotice`が通知と期限、`LibraryResultFeedback`が成功の触覚を観測する。通知期限はSwiftUIのタスク、復元操作は親画面の所有者へ接続する |

モデルのテストには一時URLの保存層と記録用の`LibraryEffects`を注入する。OSの状態を使う統合テストは、実装を明示して直列に実行する。業務上の状態とOS作用の順序をテストできること、画面から保存先やグローバルな保存層を探索しないことをレビューする。

## 依存とビルド

### 採用するパッケージ

| パッケージ | exact version | 使用するproductと役割 | パッケージの対応条件 |
| --- | --- | --- | --- |
| [swift-tasking](https://github.com/9uiLe/swift-tasking/tree/0.3.0) | 0.3.0 | `Tasking`の`ViewTaskStore`と`TaskingCore`の`TaskSlot`でタスクを所有する | Swift tools 6.0、iOS 13以上 |
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.2) | 0.2.2 | `ScopedAnimation`でscope・barrier・Debug診断を定義する | Swift tools 6.2、iOS 17以上 |
| [swift-app-macros](https://github.com/9uiLe/swift-app-macros/tree/0.3.0) | 0.3.0 | `AppMacros`の`@Equatable`でViewの比較を生成し、`EquatableBodyView`で値表示の比較境界を定義する | Swift tools 6.3、iOS / macOS 26以上 |
| [rive-ios](https://github.com/rive-app/rive-ios/tree/6.27.0) | 6.27.0 | RivePresentation経由でApple runtime API（Worker・File・Rive・ViewModelInstance）とData Bindingを使用 | Swift tools 5.10、iOS 14以上。本体のみ |
| [swift-syntax](https://github.com/swiftlang/swift-syntax/tree/603.0.2) | 603.0.2 | AppMacrosのマクロコンパイラを構築する間接依存 | [AppMacrosのPackage.swift](https://github.com/9uiLe/swift-app-macros/blob/0.3.0/Package.swift)がexact指定 |

exact versionは特定のバージョンだけを依存解決に許可する指定である。[Xcode project](../app/Nibble.xcodeproj/project.pbxproj)と[RivePresentationのPackage.swift](../app/Packages/RivePresentation/Package.swift)に直接依存の要求を宣言し、[共有Package.resolved](../app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)に全依存のバージョンとGit revisionを固定する。

本体と共有拡張はTasking・ScopedAnimation・AppMacrosを使う。ローカルPackageのRivePresentationもAppMacrosへ直接依存し、自身のViewに比較を宣言する。本体のテストは生成された比較と画面への反映を検査する。swift-syntaxはMacで実行するマクロのビルドに使い、iOSアプリの実行時ライブラリとしてリンクしない。Tasking・ScopedAnimationに追加の外部パッケージ依存はない。

swift-syntaxの版はAppMacrosの要求を満たす必要がある。AppMacrosと独立したバージョン選択は行わない。検証する依存の組み合わせは、直接依存の要求と共有lockの両方で定義する。

### ツールチェーンと実行条件

| 設定 | 値と目的 |
| --- | --- |
| 製品の最低対応OS | iOS 26.0。本体・共有拡張に同じdeployment targetを設定 |
| ローカルの検証環境 | Xcode 26.5 / Swift 6.3.2、iOS 26.5 Simulator |
| Swift language mode | 6 |
| Strict concurrency | complete。actor間のデータアクセスをcompilerで検査 |
| Default actor isolation | nonisolated。UIの処理と準拠には必要なMainActor指定を置く |
| マクロの実行環境 | macOS 26以上、Swift 6.3以上。AppMacrosのマクロをビルド時に実行 |
| 補助ツール | Nixの`flake.nix`と`flake.lock`で固定。Xcode・SDK・SimulatorはローカルのApple配布物を使う |

ネットワーク接続のあるMacで、リポジトリルートから依存を解決する。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

通常のセットアップでは共有lockの内容を使う。マクロを承認するときは、取得したソースとlockを照合する。対象はswift-app-macros 0.3.0の`AppMacrosMacros`、revision `9b6d5d699b44990029cdfa61cddf35cec46d1520`。Xcodeで対象マクロを有効にする手順は[README](../README.md#3-xcodeとswift-packageを準備する)に定義する。全マクロの検証を無効にする設定は使用しない。

直接依存はMITライセンスで提供される。RiveRuntimeは本体だけがリンクし、SDKの同梱ライセンスを保持する。本体と共有拡張のbundleへ[ThirdPartyNotices.txt](../app/Shared/ThirdPartyNotices.txt)を含める。swift-syntaxはApache-2.0とRuntime Library Exceptionで提供される。

### Releaseとテストの構成

Releaseは`-Osize`・whole-moduleでコードを生成し、`ENABLE_TESTABILITY=NO`を使う。`ios.py test`はテスト時に`ENABLE_TESTABILITY=YES`を指定し、内部APIを`@testable`で検査する。UI操作用buildと配布archiveは製品のRelease設定で評価する。

容量は本体・共有拡張・runtime・アセットを含む成果物で測り、テストやビルドcacheを含めない。最適化の採否は、同じデータと環境における応答・メモリ・容量を併せて判断する。[保存と容量の契約](decisions/0002-mvp-app.md#技術選定と配布容量)と[測定記録](product-architecture-validation.md)を参照する。

## 操作APIと開始API

### 操作の完了

モデルの操作APIは`async`とし、受理した処理と結果反映を待ってから戻る。呼出元は、そのAPIをawaitした直後に表示状態や永続化結果を検査できる。APIごとに成功・失敗・キャンセル・受け付けない条件を定義する。

同期メソッド、initializer、setter、observerは同期的な状態の初期化・更新を行う。内部から非同期処理を開始しない。`async`メソッドも、非構造化タスクを開始して操作の完了前に戻る形にしない。

### タスクの開始

`startTask`はUI所有者の開始入口である。開始の受理と操作の完了は別の結果として扱う。所有者はTaskingへ渡すoperationの中でモデルを直接awaitする。モデルはTaskingのstoreや開始用closureを受け取らず、呼出元のタスクで処理する。

| 呼出元 | 実装方法 | 終了の責務 |
| --- | --- | --- |
| 既存のasync処理 | モデルの操作APIを直接await | 呼出元が完了・エラー・キャンセルを扱う |
| 親処理の範囲で並行する子処理 | `async let`、task group | 親処理が子処理の完了を待つ |
| Viewや状態IDに結び付く処理 | SwiftUI `.task` / `.task(id:)`から直接await | SwiftUIがView終了やID変更でキャンセルを要求 |
| 同期UIイベント | `startTask`と`ViewTaskStore.start` | UI所有者がID・寿命・重複方針・終了イベントを定義 |
| 単一処理を置換する専用所有者 | `@MainActor *TaskOwner`の`TaskSlot`と`startTask` | 所有者が終了待ちを提供。製品MVPでは未使用 |

actor、checked continuation、`CancellationError`を利用できる。既存タスク内での待機・協調には`Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority`を使える。

`SnippetRow.perform`と`LibraryNotice.restore`は、Buttonから直接呼ばれる同期のUIイベントである。これらのコールバックで、親画面が`startTask`を呼ぶ。行は表示値と操作意図のコールバックだけを受け取る。通知はモデルの通知を観測して期限を待つが、復元タスクの開始と所有は親画面が担当する。タブの触覚は常設のLibraryResultFeedback、シートの触覚はシートが観測し、通知Viewの出現を成功イベントの代用にしない。どちらの部品にもタスク所有者を渡さない。

Lintはコンストラクタの`perform:`・`restore:`という明示ラベル付きのclosureだけを開始境界として許可し、未登録のコンストラクタ、表示用closure、別名化された開始関数を拒否する。

### 実装例

`ExampleModel.refresh()`は読込と状態反映を完了まで待つ操作を表す。`ExampleView`はボタンからタスクを開始し、画面終了時にキャンセルを要求する。

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

この終了条件は、画面が消えたら停止を求める操作に使う。シートの開閉をまたいで完了させる一覧操作には、sceneに対応する寿命と終了条件を設ける。

## 所有者と重複方針

`ViewTaskStore`を保持できる型は`View`、`UIViewController`、専用の`@MainActor *TaskOwner`とする。`*Model`と`@Observable`型はタスク所有者にしない。

製品では`LibraryView`が一覧・検索のモデルをそれぞれ`@State`で保持し、各`LibraryScreen`が`LibraryTaskOwner`を所有する。URLからの編集開始と削除シート終了後の更新は`LibraryView`の所有者が扱う。`SnippetEditor`は編集モデルと終了操作のstore、`ShareViewController`は共有データを読み込むstoreを持つ。

| 設定・API | 意味と規則 |
| --- | --- |
| `ActionID` | 重複判定の単位。項目ごとに独立させる操作には、操作種別とUUIDを含める |
| `cancelExisting` | 同じIDの実行へキャンセルを要求して次を開始する。結果反映時にも要求の有効性を確認 |
| `ignoreNew` | 同じIDの実行中は次の開始要求を受け付けない |
| `allowConcurrent` | 同時実行の整合性を定義できる操作に使用 |
| `ActionLifetime` | キャンセル対象を分類する値。Viewやsceneのイベントは所有者が接続 |
| `waitForIdle`等 | 所有者の終了待ち。所有・重複・キャンセルのテストに使用 |

操作別の設定は[製品設計](decisions/0002-mvp-app.md#操作の寿命と整合性)に定義する。一覧読込・コピー・項目更新はsceneBoundの有限処理とし、一覧Viewの`onDisappear`ではキャンセルしない。background化では`LibraryTaskOwner.endScreen()`で編集開始を止める。通知はタブ離脱・シート表示・sceneの非active化で`setNoticePresentation(false)`を呼び、滞在と表示を終了する。

編集終了は`SnippetEditor.onDisappear`、共有データ読込は`ShareViewController.viewDidDisappear`でscreenBoundをキャンセルする。所有者が保持するモデル・画面・完了通知の解放条件も確認する。

## 完了・キャンセル・永続化

キャンセルは協調的な停止要求であり、確定済みのDB変更を巻き戻さない。操作の入口と結果反映には次の条件を設ける。

| 操作 | 条件 |
| --- | --- |
| 一覧取得 | 読込後にキャンセル、要求識別子、検索条件を照合して結果を反映 |
| コピー | DB読込の前後でキャンセルを確認。本文のクリップボード書込と通知設定で完了 |
| 編集開始・項目更新 | 開始時のキャンセル・重複条件を確認し、受理したDB処理を完了 |
| 自動保存 | 編集中の同じ下書きへのsnapshotだけを受理。DBの入力番号で書込の適用を判断 |
| 編集終了 | キャンセルされておらず`phase == .editing`の場合だけ受理。永続化成功後はキャンセルが届いていてもUIへ成功を返す |
| 共有データ読込 | 取得の前後でキャンセルを確認。キャンセルは入力エラーとして表示しない |
| 通知期限 | 待機後にキャンセルと通知IDを確認し、その通知だけを消す |

### 下書きと終了操作

`Draft`は入力のUTF-8が変化すると入力番号`sequence`を増やす。画面はsnapshotを作り、`.task(id: snapshot.sequence)`から`persist(snapshot)`を直接awaitする。SwiftUIによる入力更新の集約を許容し、全キーストロークの個別保存は保証しない。

`finish(_:)`は保存・別項目への保存・閉じる・破棄の入口とする。入力を固定して`editing → finishing`へ遷移し、成功時は`finished`、失敗時は入力を保持して`editing`へ戻る。終了処理中と終了後は入力変更も終了の再実行も受け付けない。

保存と閉じるは自動保存の開始に依存せず、固定した入力を保存層へ渡す。保存層はトランザクション内で下書きのUUID・対象項目・更新番号・入力番号を照合する。同じ入力番号の原文比較にはUTF-8を使う。別項目への保存では、置き換え条件に合わない下書きを保持する。[入力の保存と編集の終了](decisions/0002-mvp-app.md#入力の保存と編集の終了)に照合条件を定義する。

### 通知とエラー

通知のID・発生元・本文・対象名・取り消し対象は1つの値として保持する。画面の滞在を識別するcontextを操作受理時に固定し、終了した滞在の遅延結果を再表示しない。コピー等の操作完了に表示期間を含めず、`.task(id: notice?.id)`から`expireNotice(id:)`をawaitする。最初の表示からの期限を保持し、再マウントで延長しない。取り消しは表示中の通知IDを照合し、対象UUIDごとの重複実行を防ぐ。詳細は[通知の設計](design/decisions/0004-result-notices.md)に従う。

業務上の失敗はモデルの表示状態へ変換する。編集失敗には説明と回復可能な操作を持たせ、入力を残す。非同期の書込結果はsnapshotの入力番号と編集状態を確認し、新しい入力や終了結果へ古いエラーを反映しない。

Taskingのstoreへ流出した非キャンセルエラーはDebug assertionの対象になる。空のcatchで失敗を消さず、キャンセルを正常な終了として扱うcatchと区別する。

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

`SnippetRowContent`はタイトル・本文プレビュー・ピン状態、`AboutURL`は見出しとURLを比較する。操作closure、DynamicProperty、参照モデル、globalな可変状態はこの境界の外に置く。比較対象の値だけで表示内容を判断できることをレビューし、値型に含まれる参照や独自の等価比較にも注意する。標準部品の外観・文字サイズはSwiftUIのenvironmentで更新する。

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

検査するのは、全Viewの比較宣言、表示値の変更・復元、同じ現在値を持つ別Bindingへの差し替え、操作先の更新、同じ入力での環境更新である。構文Lintとcompilerで宣言を検査し、マウント済みViewのテストと実操作で反映を確認する。実行条件と結果は[View比較の検証](view-comparison-validation.md)に記録する。

`inputRevision`を持つViewは、親が構築し直した入力に対する比較による更新省略を行わない。この方式は接続先の整合性を優先する。描画・応答性能は比較宣言の数から判断せず、同条件の計測で評価する。フレームワークの比較と寿命の前提は、[Appleの比較API](https://developer.apple.com/documentation/swiftui/view/equatable())と[identity・寿命・依存関係](https://developer.apple.com/videos/play/wwdc2021/10022/)を参照する。

## アニメーションの境界

表示変化の範囲を名前付き`AnimationScope`で囲み、valueによる変更検知またはproxyの`scope.animate`を使う。複数triggerのfactoryは`AnimationTrigger.animation`と型名を明記する。入力など親のアニメーションを受けない領域には`animationBarrier()`を置く。

シート内通知のscopeは`Library.Notice`とし、通知の有無をvalueで検知する。シート内の表示・消去はReduce Motionの設定にかかわらず0.16秒のopacity遷移とする。上部の通知ウィンドウは独自の表示・消去アニメーションを持たず、元画面のレイアウトやアニメーションを変更しない。通知本文の更新と表示の有無を区別し、scopeを通知部分に限定する。

`LibraryScreen`と`SnippetEditor`の外側の`animationBarrier(warnsOnLeaks: false)`は、OSのシートtransactionが内容へ伝わるのを防ぐ。内側の`detectAnimationLeaks()`と編集入力領域の警告付きbarrierは、アプリ内部の伝播をDebug実行時に診断する。標準シート・メニュー・キーボードの遷移はOS部品が管理する。

診断の対象はmodifierの位置へ届くtransactionであり、子孫の全表示変化やUIKitの動作は検査しない。同じ状態更新による変化をscopeが自動分離するわけではない。Reduce Motion、入力・スクロール・遷移は実際の画面で確認する。

## Riveの表示境界

[RivePresentation](../app/Packages/RivePresentation/README.md)は、rive-iosのApple runtime API（`Worker`、`File`、`Rive`、`ViewModelInstance`）とData Bindingでローカルの`.riv`を表示するSwift Packageである。このAPI世代で接続を統一する。読み込んだファイルは機能内で再利用でき、可変の再生状態は表示ごとのSessionが所有する。一つのSessionを複数の表示へ同時に渡さない。

| 境界 | 契約 |
| --- | --- |
| 実行と寿命 | MainActorでロードとSession生成を直接awaitする。ホストの`.task`がロード・購読を所有し、キャンセルされた結果を表示へ採用しない |
| 演出と業務 | 入力値とtriggerは表示への要求とする。`active`や演出完了を、保存・コピー等の成功判定に使わない |
| 描画 | SwiftUIの独自アニメーションはScopedAnimation、キャンバス内はRMLのタイムラインが担当する。独自のTimer・DisplayLink・生Taskでフレームを進めない |
| ホストの責務 | 説明、外観、再生方針、スクロール可視性、アクセシビリティ、読込失敗と再試行を決める |

所有関係、停止中の外観更新、依存の採用・更新条件は[演出設計](decisions/0004-rive-presentation.md)、アセットと検査の契約は[制作手順](../app/Animations/README.md)を正とする。Legacy APIの入口はSwift規約で検出し、実バイナリの接続と動作はiOSテスト・画面検証で確認する。

## Lintと禁止する直接使用

`swift-library-policy`は字句解析とSwift構文木を使い、APIの使用箇所・タスク開始・View比較の規約を検査する。ローカルとUbuntu CIは同じNixのPython環境とtree-sitter-language-pack 1.4.1を使う。違反時はファイル・行・列を表示し、終了コード1で失敗する。

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

| 選定 | 判断理由 | 製品側が負う責務 |
| --- | --- | --- |
| Tasking | タスク所有・寿命・重複方針を共通APIで宣言できる | 操作ごとのID、終了イベント、キャンセル後の結果反映を定義 |
| ScopedAnimation | アニメーションの適用範囲と伝播の遮断をView構造で表せる | OS遷移との境界、診断位置、Reduce Motionを検証 |
| AppMacros | View定義側に比較を宣言し、値表示の更新条件と親入力の差し替え方針を明示できる | 比較入力、状態寿命、MainActor準拠の設計、マクロソースの確認、ビルド時間とツールチェーン要件の管理 |

依存の組み合わせを変更するときは、exact version・共有lock・ソース・ライセンス・対応OSを照合する。iOS 26.5で、操作の直接await、重複・キャンセル、入力直後の保存・閉じる、共有元への復帰、通知の伝播、比較入力・外観・文字サイズの表示反映を確認する。

保守停止、OS・ツールチェーンとの不適合、実測した応答・描画の悪化、必要な表現への不適合を採用の見直し条件とする。検証結果には対象ソースと環境を記録する。各手段の実施状況は[検証結果の索引](mvp-validation.md)、固定した依存構成の確認結果は[Swift Package構成の検証](spm-validation.md)から参照する。
