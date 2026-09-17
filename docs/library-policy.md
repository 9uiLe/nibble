# 非同期処理・アニメーション・View比較の実装規約

nibbleは、操作の完了、タスクの寿命、表示の更新条件をコードから読み取れる構成にする。この規約は本体・共有拡張・テスト・研究用アプリ・検証用Swiftへ適用する。製品の機能とデータの契約は[製品設計](decisions/0002-mvp-app.md)、実行手順は[MVP手順](mvp.md)、対象ソースごとの観測は[検証結果](mvp-validation.md)に定義する。

## 責務と用語

モデルは処理と状態を持ち、UIは処理を開始するタイミングとタスクの寿命を管理する。表示専用のViewは値を受け取り、必要な箇所で等価比較を表示更新の条件にする。アニメーションは変化させる表示部分へ適用する。

| 用語 | 意味 | 実装する場所 |
| --- | --- | --- |
| 操作API | 処理と結果反映を完了まで待てる`async`メソッド | モデル・保存層 |
| タスク所有者 | タスクの開始、重複判定、終了時のキャンセルを管理するUI側の型 | View・UIViewController・専用の`*TaskOwner` |
| 比較境界 | 入力値の等価比較で表示更新を制御するViewの範囲 | 値だけを受け取る表示用View |
| アニメーションscope | 値の変化または明示的な操作にアニメーションを付ける範囲 | `AnimationScope`で囲む表示部分 |
| barrier | 親から届くアニメーションを取り除く境界 | `animationBarrier()`を付ける表示部分 |
| snapshot | ある時点の下書きを固定した値。処理待ちの間に画面の入力が進んでも変化しない | 編集画面からモデルへ渡す`Draft` |

## 依存とビルド

### 採用するパッケージ

| パッケージ | exact version | 使用するproductと役割 | パッケージの対応条件 |
| --- | --- | --- | --- |
| [swift-tasking](https://github.com/9uiLe/swift-tasking/tree/0.3.0) | 0.3.0 | `Tasking`の`ViewTaskStore`と`TaskingCore`の`TaskSlot`でタスクを所有する | Swift tools 6.0、iOS 13以上 |
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.2) | 0.2.2 | `ScopedAnimation`でscope・barrier・Debug診断を定義する | Swift tools 6.2、iOS 17以上 |
| [swift-app-macros](https://github.com/9uiLe/swift-app-macros/tree/0.3.0) | 0.3.0 | `AppMacros`の`@Equatable`と`EquatableBodyView`で表示値の比較を定義する | Swift tools 6.3、iOS / macOS 26以上 |
| [rive-ios](https://github.com/rive-app/rive-ios/tree/6.27.0) | 6.27.0 | RivePresentation経由で新Apple APIとData Bindingの説明イラストを表示 | Swift tools 5.10、iOS 14以上。本体のみ |
| [swift-syntax](https://github.com/swiftlang/swift-syntax/tree/603.0.2) | 603.0.2 | AppMacrosのマクロコンパイラを構築する間接依存 | [AppMacrosのPackage.swift](https://github.com/9uiLe/swift-app-macros/blob/0.3.0/Package.swift)がexact指定 |

exact versionは特定のバージョンだけを依存解決に許可する指定である。[Xcode project](../app/Nibble.xcodeproj/project.pbxproj)と[RivePresentationのPackage.swift](../app/Packages/RivePresentation/Package.swift)に直接依存の要求を宣言し、[共有Package.resolved](../app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)に全依存のバージョンとGit revisionを固定する。

本体と共有拡張は同じTasking・ScopedAnimationをリンクする。AppMacrosは比較Viewを持つ本体とそのテストで使う。swift-syntaxはMacで実行するマクロのビルドに使い、iOSアプリの実行時ライブラリとしてリンクしない。Tasking・ScopedAnimationに追加の外部パッケージ依存はない。

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

### 実装例

`ExampleModel.refresh()`は読込と状態反映を完了まで待つ操作を表す。`ExampleView`はボタンからタスクを開始し、画面終了時にキャンセルを要求する。

```swift
import SwiftUI
import Tasking

@MainActor
struct ExampleView: View {
    @State private var tasks = ViewTaskStore()
    let model: ExampleModel

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

操作別の設定は[製品設計](decisions/0002-mvp-app.md#操作の寿命と整合性)に定義する。一覧読込・コピー・項目更新はsceneBoundの有限処理とし、一覧Viewの`onDisappear`ではキャンセルしない。background化では`LibraryTaskOwner.endScreen()`で編集開始を止め、同期APIの`clearNotice()`で通知を消す。

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

通知のID・本文・取り消し対象は1つの値として保持する。コピー等の操作完了に表示期間を含めず、`.task(id: notice?.id)`から`expireNotice(id:)`をawaitする。

業務上の失敗はモデルの表示状態へ変換する。編集失敗には説明と回復可能な操作を持たせ、入力を残す。非同期の書込結果はsnapshotの入力番号と編集状態を確認し、新しい入力や終了結果へ古いエラーを反映しない。

Taskingのstoreへ流出した非キャンセルエラーはDebug assertionの対象になる。空のcatchで失敗を消さず、キャンセルを正常な終了として扱うcatchと区別する。

## Viewの比較境界

値の比較で表示更新を制御するViewは`@Equatable`を付けたstructとし、`@MainActor EquatableBodyView`へ直接準拠する。MainActorはUIの処理を実行するactorであり、準拠と生成される等価比較を同じactorに限定する。比較はViewの表示入力を対象とする。

内容は同じstructの`equatableBody`に書く。ライブラリが提供する`body`に比較の適用を任せ、呼出元は通常のViewとして配置する。

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

製品の`SnippetRowContent`はタイトル・本文プレビュー・ピン状態を`let`で受け取り、3つすべてを比較する。Button、アクセシビリティの操作ラベル、コピー・編集・削除等のclosureは`LibraryScreen`が保持する。表示値が等しい場合も、操作は現在のモデル・項目を参照する。

| 対象 | 契約 |
| --- | --- |
| 比較Viewの入力 | wrapperや所有修飾子を持たない値型の`let`。表示を決める全入力を比較 |
| 状態・注入・操作 | `@State`・`@Binding`・`@Bindable`・`@Environment`等と操作closureは呼出元の通常のViewに保持 |
| 表示の依存 | 独自の参照モデルやglobal状態を比較境界から読まない。標準部品の外観・文字サイズはSwiftUIのenvironmentで更新 |
| 比較を使わない表示 | 状態や入力を持つ画面、参照依存がある表示、比較が高価な表示は通常のViewで構成 |
| データの等価比較 | 値型・enumの標準Equatable合成とgenericなEquatable制約を許可 |

AppMacrosが比較から除外できる入力でも、closureやDynamicPropertyをnibbleの比較Viewへ渡さない。`@SkipEquatable`、直接の`.equatable()`・`EquatableView`・`equatableBody`参照、手書き`==`は使用しない。

入力の変更・復元と、入力が等しい状態での外観・文字サイズの追従をマウント済みViewで検査する。比較による描画回数や応答時間への効果は、同条件の測定で判断する。

## アニメーションの境界

表示変化の範囲を名前付き`AnimationScope`で囲み、valueによる変更検知またはproxyの`scope.animate`を使う。複数triggerのfactoryは`AnimationTrigger.animation`と型名を明記する。入力など親のアニメーションを受けない領域には`animationBarrier()`を置く。

製品の通知scopeは`Library.Notice`とし、通知の有無をvalueで検知する。表示・消去は0.16秒のopacity遷移、Reduce Motion有効時はduration 0秒とする。通知本文の更新と表示の有無を区別し、scopeを通知部分に限定する。

`LibraryView`と`SnippetEditor`の外側の`animationBarrier(warnsOnLeaks: false)`は、OSのシートtransactionが内容へ伝わるのを防ぐ。内側の`detectAnimationLeaks()`と編集入力領域の警告付きbarrierは、アプリ内部の伝播をDebug実行時に診断する。標準シート・メニュー・キーボードの遷移はOS部品が管理する。

診断の対象はmodifierの位置へ届くtransactionであり、子孫の全表示変化やUIKitの動作は検査しない。同じ状態更新による変化をscopeが自動分離するわけではない。Reduce Motion、入力・スクロール・遷移は実際の画面で確認する。

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
| 直接の比較と比較除外 | `.equatable`、`EquatableView`、`.equatableBody`、`@SkipEquatable`、手書き`==` | AppMacrosの比較View、データの標準Equatable合成 |

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

開始境界は`startTask`、Buttonのaction、`onAppear`・`onDisappear`・`onChange`・`onOpenURL`、sheet/fullScreenCoverの`onDismiss`、UIViewControllerのoverride `viewDidLoad`・`viewDidAppear`・`viewWillAppear`、`@Test`の本体とする。Buttonのlabelやsheetのcontentなど、表示を構築するclosureは含めない。

通常の同期/asyncメソッド、initializer、getter・setter・observer、任意のclosure、SwiftUI `.task`、Taskingのoperationからの開始を拒否する。ViewTaskStore.startをasyncで包む形も許可しない。予約名以外の任意の`.replace`はこの規則の対象外である。

### View比較境界の制限

[scripts/swift_equatable_policy.py](../scripts/swift_equatable_policy.py)は同じ構文木から次の形を検査する。

| 検査対象 | 許可する形 |
| --- | --- |
| 比較Viewの宣言 | `@Equatable`と`EquatableBodyView`をstructへ直接宣言。MainActor付きの準拠も検査対象。`View`・`Equatable`の重複準拠は不可 |
| 表示本体 | 同じstructの`equatableBody`。独自`body`による既定実装の上書きは不可 |
| 格納する入力 | 1つ以上の通常の`let`。可変入力、wrapper、所有修飾子、構文上の関数型・closureは不可 |
| 準拠の可視性 | `View`・`Equatable`・`EquatableBodyView`のtypealias、Viewの派生protocol、EquatableBodyViewの派生protocol・extension準拠は不可 |
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
| AppMacros | 全表示値の比較を生成し、View定義側に比較境界を置ける | 値入力とMainActor準拠の設計、マクロソースの確認、ビルド時間とツールチェーン要件の管理 |

依存の組み合わせを変更するときは、exact version・共有lock・ソース・ライセンス・対応OSを照合する。iOS 26.5で、操作の直接await、重複・キャンセル、入力直後の保存・閉じる、共有元への復帰、通知の伝播、比較入力・外観・文字サイズの表示反映を確認する。

保守停止、OS・ツールチェーンとの不適合、実測した応答・描画の悪化、必要な表現への不適合を採用の見直し条件とする。検証結果には対象ソースと環境を記録する。各手段の実施状況は[検証結果の索引](mvp-validation.md)、固定した依存構成の確認結果は[Swift Package構成の検証](spm-validation.md)から参照する。

## Riveの表示境界

RivePresentationは新Apple APIのみを使うローカルSwift Packageである。[演出設計](decisions/0004-rive-presentation.md)にファイルと再生状態の寿命、Data Binding、読み込みの失敗とキャンセル、Reduce Motionの責務を定義する。SwiftUIの遷移はScopedAnimation、Riveキャンバス内はRMLのタイムラインが担当する。Riveの制御に独自のTimer・DisplayLink・生Taskを追加しない。

演出の入力値とtriggerは表示への要求であり、保存・コピー等の操作APIとは分ける。Riveの`active`や完了通知を業務の成功として扱わない。新APIの実行条件はMainActorで、ロードとインスタンス作成はasyncを直接awaitする。購読はViewの`.task`で所有する。
