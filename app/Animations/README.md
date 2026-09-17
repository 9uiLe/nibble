# 説明アニメーションの制作と配布

編集の正本は`about/scene.rml`と`about/rive.yaml`。外部の画像・フォント・スクリプトは使わない。配布する[about-story.riv](../Nibble/Animations/about-story.riv)は、正本から生成したバイナリである。

## 制作と検査

Apple Silicon Macでリポジトリルートから実行する。Rive CLI 1.0.4はNixで固定され、Riveアカウントへのログインを必要としない。

```sh
nix develop --command python3 scripts/rive_assets.py build
nix develop --command python3 scripts/rive_assets.py check
nix develop --command rive app/Animations/about
```

`build`は版・契約を確認してverifyとunsigned出力を実行し、配布先と[assets.json](assets.json)のハッシュを更新する。`check`はApple環境なしで入力・生成物・名前と型の対応を照合する。未生成、生成後の変更、初期インスタンスの欠落、旧inputsやスクリプトの混入は失敗する。終了コード0は視覚品質やiOS互換性の保証ではない。

生成後はCLIのinspect、時刻別画像、データ読み戻しと、iOS上の表示・Data Bindingの検証を行う。キャプチャとログは`artifacts/`へ保存する。ライブプレビューを閉じても正本と配布物を残し、Editorや`.rev`の手作業を要件にしない。

## 接続契約

Artboard **About**（400×208）、State Machine **Presentation**、View Model **AboutStory**、初期インスタンス **Default**。

| プロパティ | 型・初期値 | 更新方向と意味 |
| --- | --- | --- |
| motionAllowed | Boolean、true | ホスト→Rive。falseでは完成図へ直ちに移り、trueへ戻しても自動再生しない |
| replay | Trigger | ホスト→Rive。完成後の再生要求。演出中とmotionAllowed=falseでは無視する |
| active | Boolean、false | Rive→ホスト。タイムラインの実行状態。一時停止中もtrue。業務状態ではない |
| paper | Color、FFFFFDF8 | ホスト→Rive。カードと入力面 |
| ink | Color、FF514238 | ホスト→Rive。内容を表す線 |
| accent | Color、FFA33D14 | ホスト→Rive。収束時の確認記号 |
| muted | Color、FFEADCCC | ホスト→Rive。輪郭・経路・接地面 |

色は32-bit ARGB。初期値はライト用で、ホストが外観とコントラストに合わせて更新する。全ての状態で文字説明が成立するため、Riveの意味上の操作・通知をアクセシビリティツリーへ重複して追加しない。

## 状態と時間

通常の初回入場で4秒のChooseCopyPasteを一度再生し、Overviewで静止する。元のカードを残し、複製だけが入力面へ移動する。入力の線は移動より遅れて現れ、確認記号は小さくオーバーシュートして収束する。

| 条件 | 振る舞い |
| --- | --- |
| motionAllowed=falseで入場・再生中に変更 | 完成図で静止する。位置を途中で凍結しない |
| motionAllowed=trueへ変更 | 完成図を維持する |
| 完成図でreplay | 初めから一度再生する |
| 演出中のreplay・連打 | 進行中の動きを維持する |
| 一時停止・画面外・バックグラウンド | ホストがフレーム進行を止め、復帰で同じ位置から続ける |
| 画面破棄後の再入場 | 新しいsessionで初期状態から開始する |

演出は実際のクリップボード、入力先アプリ、保存データに接続しない。完成の意味は説明図の収束である。
