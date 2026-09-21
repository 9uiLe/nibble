# 説明アニメーションの制作と配布

nibbleは、文章のコピーと保存を説明する`about-story`と、保存済み本文の入力を説明する`keyboard-story`を本体アプリへ同梱する。図形・時間・演出状態はRML、説明文・外観・表示中の寿命はSwiftUIのホストが管理する。

本書は制作ファイル、接続契約、再生成、検証の手順を定める。構図と時間の採用理由は[演出設計](../../docs/architecture/presentation.md)、iOSの汎用APIは[RivePresentation](../Packages/RivePresentation/README.md)を参照する。

## アセットと制作環境

| 用途 | 制作ソース | Bundleへ同梱する生成物 | ホスト |
| --- | --- | --- | --- |
| コピーと保存 | [about/scene.rml](about/scene.rml)・[about/rive.yaml](about/rive.yaml) | [about-story.riv](../Nibble/Animations/about-story.riv) | AboutIllustration |
| キーボードからの入力 | [keyboard/scene.rml](keyboard/scene.rml)・[keyboard/rive.yaml](keyboard/rive.yaml) | [keyboard-story.riv](../Nibble/Animations/keyboard-story.riv) | KeyboardIllustration |

`scene.rml`は図形、タイムライン、状態遷移、Data Bindingの編集の正本である。`rive.yaml`はCLIプロジェクト名と主Artboardを指定する。[assets.json](assets.json)には制作ディレクトリ、配布先、接続契約、CLI版、入力と出力のハッシュを登録する。各制作ディレクトリの`build/`はGit管理外の生成作業領域とする。

制作・プレビュー・生成には、Apple Silicon Mac上でNixの固定版Rive CLIを使う。表示には共有lockで固定したrive-iosのApple runtime APIとData Bindingを使う。CLIのhelp・schemaとruntimeの対応を確認してから機能を採用する。

図中のラベルはRML内のベクター輪郭で、外部画像・フォントファイルを必要としない。Luauスクリプトとシェーダーは使用しない。制作はCLIで完結し、Rive Editor、`.rev`、ログイン、Riveの署名を必要としない。`.riv`の変更は必ずRMLからの再生成で行う。両アセットの配布先は本体Bundleとし、キーボード拡張へは同梱しない。

## 接続契約

Artboardは描画面、State Machineは演出の状態と遷移、View Modelは外部と受け渡す型付きデータを定義する。ホストは次の接続名を検査し、表示ごとにView Modelのdefault instanceからSessionを生成する。

| アセット | Artboard | State Machine | View Model | default instance | ループのタイムライン |
| --- | --- | --- | --- | --- | --- |
| about-story | About | Presentation | AboutStory | Default | CopyAndSave |
| keyboard-story | Keyboard | Presentation | KeyboardStory | Default | SwitchAndInsert |

接続名・型の正本は[assets.json](assets.json)、初期値の正本は各RMLのdefault instanceとする。生成物、manifest、ホストの`RiveContract`を照合する。

| プロパティ | 型・初期値 | 更新方向と意味 |
| --- | --- | --- |
| motionAllowed | Boolean・true | ホスト→Rive。ループ演出と完成静止図の選択 |
| active | Boolean・false | Rive→ホスト。演出の状態。実際の保存・コピー・挿入の成否には使わない |
| paper・ink・accent・muted | Color・ライト色 | ホスト→Rive。背景、文字・輪郭、操作の強調、補助表現の色 |
| action（keyboard-story） | Color・ライトの青 | ホスト→Rive。選択行、入力カーソル、挿入結果の色 |

## ホストと再生状態

アセットはData Bindingの`motionAllowed`でループ演出と完成静止図を選び、`active`で演出状態を伝える。ホストがフレーム進行を一時停止する操作とは別の契約である。

| Data Binding入力 | 演出と再生位置 |
| --- | --- |
| motionAllowed=trueで開始 | 各ループの先頭から開始し、active=trueになる |
| motionAllowed=falseで開始、または途中でfalseへ変更 | Overviewの完成図へ移り、active=falseになる |
| motionAllowedをfalseからtrueへ変更 | ループの先頭から開始する |

`CopyAndSave`は文章選択→コピー→複製の移動→保存→完了表示、`SwitchAndInsert`は地球儀長押し→nibble選択→行タップ→本文挿入→結果保持を繰り返す。各アセットの図形値と時間はRMLで管理する。

nibbleで適用する再生方針は[演出設計](../../docs/architecture/presentation.md)を正本とする。[読込と画面の寿命](../../docs/architecture/presentation.md#読込と画面の寿命)、[停止と復帰](../../docs/architecture/presentation.md#停止と復帰)、[配色と寸法](../../docs/architecture/presentation.md#配色と寸法)に従ってホストへ接続する。汎用APIの停止と再描画は[Canvasの契約](../Packages/RivePresentation/README.md#比較と停止再描画)で定義する。

## 編集と再生成

[セットアップ](../../README.md#セットアップ)後、リポジトリルートのNix環境で実行する。エージェントは`NIBBLE_UI_FORMAT=json`を指定する。

```sh
nix develop --command rive app/Animations/about
nix develop --command rive app/Animations/keyboard
nix develop --command python3 scripts/rive_assets.py build
nix develop --command python3 scripts/rive_assets.py check
```

用途に合うriveコマンドでライブプレビューを開き、RMLの編集結果を確認する。プレビューを終了して`build`を実行すると、登録済みアセットのCLI版とRML構造を照合し、`--verify`と`--once`によるunsigned生成を行う。エラー・警告があれば失敗し、成功時は配布用`.riv`とmanifestのハッシュを更新する。

`check`はCLIやApple SDKを使わず、登録済みアセットを次の範囲で検査する。

| 検査対象 | 確認する契約 |
| --- | --- |
| 入力・出力のハッシュ | 保存したソースと生成物の対応 |
| Artboardからの参照 | State Machine、View Model、exportしたdefault instanceの接続 |
| プロパティ | 必須の名前・型・初期値定義の存在 |
| 制作要素 | ID重複、State Machine inputs、スクリプト、シェーダーの混入がないこと |

制作ソース、生成物、manifestを一組でレビューする。ハッシュの更新だけで再生成を代用しない。静的検査に加え、初期値の意味、状態遷移、実際の描画を次の手順で確認する。

## 表現と実行の検証

1. CLI inspectと実バイナリのiOSテストで、接続名・型・独立したSessionを確認する。
2. 開始、選択、主動作、結果保持、周期境界の画像を開き、輪郭・配色・重なり・構図を確認する。keyboard-storyでは切替候補、行タップ、入力先と保存元の本文を含める。
3. 複数周期で操作と結果の順序、周期境界を確認する。motionAllowedの初期値と途中変更を試し、activeを読み戻す。
4. 同じ生成物を本体アプリで動かし、小画面、ライト／ダーク、停止・復帰・再入場、固定文字・演出、読込失敗と再試行を確認する。
5. 同条件で容量と負荷を比較し、CLI、Simulator、実機それぞれの測定範囲を記録する。

CLIの画像出力はviewportとfitを指定し、実際の寸法と内容で適用を確かめる。記録は`artifacts/`へ保存し、[証跡手順](../../docs/review-evidence.md)で対象ソースと照合する。動画の抽出確認、全編再生、公開後の閲覧確認は別々に記録する。

## アセットの追加・契約変更

1. 制作ディレクトリへRMLとrive.yamlを置き、表現の目的、接続名・型・初期値・更新方向、状態遷移を定義する。
2. assets.jsonへ制作ディレクトリ、配布先、接続契約を登録する。
3. ホストのRiveContract、Session所有者、表示条件を定め、生成物を対象Bundleへ同梱する。
4. buildとcheck、影響範囲の表現・実行検証を行う。
5. アセット、ホスト、設計資料、検証記録を一組でレビューする。

機能や依存を変更するときは、[演出設計の保守条件](../../docs/architecture/presentation.md#保守と受け入れ)を適用する。
