# 説明イラストの制作規約

このRive CLIプロジェクトはAboutとキーボード利用案内の説明イラストを生成する。図形・時間・状態はRML、設定はrive.yamlが所有する。生成・接続・確認・完了条件は[アセット手順](../README.md)に従う。

Nixで固定したCLIを使い、型とプロパティは`rive schema <Type>` / `rive schema --search <text>`、機能の手順は`rive docs --list` / `rive docs <topic>`で確認する。CLIとiOS runtimeの対応を別々に確認する。

編集中はこのディレクトリで`rive . --verify`と`rive inspect . --summary`を使う。`rive . --screenshot --advance=1`の画像は開始後の1条件にすぎず、時間を変える変更では複数段階と周期境界も確認する。viewport・fitはCLI helpで確認し、出力画像の実寸を照合する。

配布する.rivを直接修正せず、リポジトリルートの`rive_assets.py build`で再生成する。制作ソース・.riv・manifestを一組でレビューし、hashの更新だけで生成や目視の代用にしない。文書だけの編集に再生成は不要。
