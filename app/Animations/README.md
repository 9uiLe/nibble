# 説明アニメーションの制作と配布

Aboutの図は、保存した言葉を選び、複製を入力先へ運ぶ流れを表す。元のカードを残し、コピーしても保存内容が消えないことを示す。説明文と再生操作はiOSのホストが表示し、Riveは図形、動き、演出内の状態遷移を管理する。

## 正本と生成物

| ファイル | 役割 |
| --- | --- |
| [about/scene.rml](about/scene.rml) | 編集の正本。図形、タイムライン、State Machine、View Model、Data Bindingを定義する |
| [about/rive.yaml](about/rive.yaml) | CLIプロジェクト名と主Artboardの指定 |
| [assets.json](assets.json) | 検査対象の制作ディレクトリ、配布先、接続契約、CLI版、ソースと出力のハッシュ |
| [about-story.riv](../Nibble/Animations/about-story.riv) | アプリへ同梱する生成済みバイナリ |

外部画像、フォント、Luauスクリプト、シェーダーは使用しない。制作・プレビュー・生成はRive CLIで完結し、Rive Editorや`.rev`の手作業を工程に含めない。`.riv`だけを直接修正せず、正本を編集して生成する。

## 再生成とレビュー

Apple Silicon Macで[セットアップ](../../README.md#セットアップ)を完了し、リポジトリルートから実行する。CLI 1.0.4はNixで固定され、生成にRiveアカウントへのログインやRiveの署名は必要ない。

```sh
nix develop --command python3 scripts/rive_assets.py build
nix develop --command python3 scripts/rive_assets.py check
nix develop --command rive app/Animations/about
```

`build`はCLI版とRMLの構造を照合し、`--verify`、`--once`によるunsigned生成を実行する。エラーや警告があれば失敗する。成功時は配布先の`.riv`とassets.jsonのハッシュを更新する。最後のコマンドはライブプレビューである。

`check`はCLIやApple SDKなしで、宣言済みプロジェクトの入力・出力ハッシュとRMLの契約を検査する。ArtboardからState Machine・View Modelへの参照、default instanceのexport、必須プロパティの型と初期値定義の存在、ID重複、旧inputs・スクリプト・シェーダーの混入を確認する。初期値の意味、描画結果、バイナリの互換性は別途検証する。

生成後はRML、生成物、manifestを一緒にレビューする。CLIのinspect、時刻別画像、入力とデータ読み戻しで構造と挙動を確認し、画像を実際に開いて形・配色・構図を評価する。主要な動きは開始、持ち上げ、移動、最大変形、収束で確認し、タイミングと割り込みは再生でも確認する。iOSでは同じ`.riv`の表示と外部制御を検証する。結果と媒体は`artifacts/`へ保存し、[証跡の手順](../../docs/review-evidence.md)で対象ソースと対応付ける。

## Aboutの接続契約

Artboard **About**（400×208）、State Machine **Presentation**、View Model **AboutStory**、exportするdefault instance **Default**を使用する。プロパティは全てView Modelのrootに置く。

| プロパティ | 型・初期値・値域 | 更新方向と意味 |
| --- | --- | --- |
| motionAllowed | Boolean、true、true/false | ホスト→Rive。falseで完成図へ移り、trueへ戻しても自動再生しない |
| replay | Trigger、初期は未発火（RML値0）、イベントとして発火 | ホスト→Rive。完成後の一回再生要求。演出中とmotionAllowed=falseでは無視する |
| active | Boolean、false、true/false | Rive→ホスト。演出の進行状態。一時停止中もtrue。完了またはReduce Motion向けの静止状態ではfalse |
| paper | Color、FFFFFDF8、32-bit ARGB | ホスト→Rive。カードと入力面 |
| ink | Color、FF514238、32-bit ARGB | ホスト→Rive。内容を表す線 |
| accent | Color、FFA33D14、32-bit ARGB | ホスト→Rive。収束時の確認記号 |
| muted | Color、FFEADCCC、32-bit ARGB | ホスト→Rive。輪郭・経路・接地面 |

色の初期値はライト用の制作値である。ホストは表示時に外観とコントラストに合わせた配色を設定する。`active`とtriggerは演出専用で、実際のコピー、保存、入力先アプリの状態を表さない。ホスト実装の名前・型は[AboutIllustration](../Nibble/AboutIllustration.swift)に定義する。

## 状態と時間

通常の初回入場で**ChooseCopyPaste**を4秒間、一度だけ再生し、**Overview**で静止する。複製を持ち上げて入力面へ運ぶ動きを主役にし、入力先の線は少し遅れて現れる。確認記号は小さくオーバーシュートして収束する。完成図でも複製元と入力先の関係を読み取れる構図にする。

| 条件 | 振る舞い |
| --- | --- |
| motionAllowed=trueで初回入場 | ChooseCopyPasteを一度再生し、Overviewへ移る |
| motionAllowed=falseで入場、または演出中にfalseへ変更 | フレーム評価でOverviewへ移り、active=falseになる |
| motionAllowedをtrueへ変更 | Overviewを維持し、replayを待つ |
| Overviewでreplay | motionAllowed=trueなら先頭から一度再生する |
| 演出中のreplay・連打 | 進行中の動きを維持する |
| 一時停止・画面外・バックグラウンド | ホストがフレーム進行を止める。Sessionとactiveは保持する |
| 停止条件の解除 | 同じSessionの位置から進む。手動停止が残る場合は停止を維持する |
| Session破棄後の再入場 | 新しいSessionで初期状態から開始し、現在のmotionAllowedを適用する |

ホストは停止中の配色更新にCanvasの`renderingRevision`を用いる。表示と再生位置を分けて管理する契約は[RivePresentation](../Packages/RivePresentation/README.md)に定義する。読み上げと文字拡大はホストの説明文が担当し、図の意味をアクセシビリティツリーへ重複して追加しない。

## アセットの追加・契約変更

1. 制作ディレクトリにRMLとrive.yamlを置き、名前、型、初期値、更新方向、状態遷移を定義する。
2. assets.jsonに制作ディレクトリ、配布先、接続契約を登録する。検査はこの宣言を対象とし、未登録のディレクトリを自動発見しない。
3. ホストの`RiveContract`と操作を実装し、生成物をアプリのBundleへ同梱する。
4. `build`と`check`を実行し、実バイナリの契約・状態・表示をiOSで確認する。
5. 制作ソース、生成物、manifest、ホスト、設計資料、検証記録を同じ変更としてレビューする。

採用版のCLI help・schemaとApple runtime APIで、制作可能性と実行可能性を別々に確認する。機能や依存の変更は[演出設計](../../docs/decisions/0004-rive-presentation.md)の制約に従い、終了コードやハッシュ照合だけで表現・動作を合格にしない。
