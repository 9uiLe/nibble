# 説明イラストの制作規約

このディレクトリは、nibbleの「nibbleについて」に表示する説明イラストのRive CLIプロジェクトである。RMLが図形・時間・演出状態、`rive.yaml`がプロジェクト設定を定義する。制作ソース、生成済み`.riv`、manifest、iOSへの接続は[アセット手順](../README.md)に従って管理する。

## 制作環境とAPIの確認

Nixで固定したRive CLIを使う。リポジトリルートで`nix develop`を起動し、このディレクトリへ移動して次のコマンドを実行する。

| 調べる内容 | コマンド |
| --- | --- |
| 型とプロパティ | `rive schema <Type>`、`rive schema --search <text>`。機械可読の出力には`--json` |
| 機能別の手順 | `rive docs --list`で対象トピックを選び、`rive docs <topic>`で読む |

RMLの型・プロパティ名はschemaで確認する。CLIとiOS runtimeの対応はそれぞれ確認し、採用している版で利用できる機能を使う。

## 構造と生成物の検証

RMLまたは`rive.yaml`のまとまった変更ごとに、対象プロジェクトを確認する。

- `rive . --verify`でコンパイルの成立を確認する。機械可読の結果には`--format=json`を指定する。
- `rive inspect . --summary`で構造と問題を確認する。解決済みのツリー全体には`--json`を指定する。

配布物はリポジトリルートから生成し、照合する。

```sh
nix develop --command python3 scripts/rive_assets.py build
nix develop --command python3 scripts/rive_assets.py check
```

ソース・`.riv`・manifestを一組の成果物とし、ハッシュだけを書き換えて再生成の代用にしない。文書だけの変更には文書検査を適用し、アセット再生成は必要ない。

## 表現の確認と完了条件

構造検査に加えて、依頼された図形・状態・時間の表現を確認する。`rive . --screenshot --advance=1`で状態機械の開始後のフレームを`build/<name>.png`へ出力する。画像を開いて輪郭・配色・重なりを確認し、時間経過のある変更はアセット手順に従って各段階のフレームと複数周期を確認する。

確認用の媒体はリポジトリの`artifacts/`へ保存する。画像を閲覧する手段がない場合は、その条件を未確認として記録し、独立した検査を進める。検査の成功だけで見た目・動作を確認済みとせず、成果物、観測、未実施条件を報告する。失敗を修正した場合は影響する検査を再実行する。
