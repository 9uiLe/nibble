# UI設計検査の性能と保証範囲

この記録は、共通の設計照合とnibbleの文書検査について、実装の責務・正当性・性能を確認した結果を示す。構成・操作・失敗条件の契約は[共通ツールキット](../tools/ui-design/README.md)、nibbleへの適用は[UI設計](design/README.md)に定義する。

## 対象と測定条件

| 項目 | 条件 |
| --- | --- |
| 評価日 | 2026-09-17 |
| 比較元 | `33eaf956ff145ce3a9f15922fa0c9b8376f64ef9` |
| 比較先 | `580840e2128e0d2afc9c328393fa4c784e3cf774` |
| 環境 | macOS 26.2、arm64、Python 3.13.15。両実装に同じ`flake.lock`のNix環境を使用 |
| 共通照合 | [measure.py](../tools/ui-design/benchmarks/measure.py)の公開`check`呼出しと、新しいprocessでのCLI実行 |
| 文書検査 | [benchmark_docs.py](../scripts/benchmark_docs.py)。両実装に比較元の同一50文書・522リンク・2 Swift例を入力 |
| 回数 | 各条件7回、直列に実行。中央値を記載。APIは1回のウォームアップ後、GCを各測定の前に実行 |
| メモリ | 時間とは別に1回実行し、`tracemalloc`でPython割当のピークを取得。process全体のRSSではない |
| 生データ | [全サンプルと実装・環境情報](measurements/ui-design-2026-09-17.json) |

CLI時間はPython起動・import・検査・JSON出力・process終了を含む。API時間はimportとfixture生成を含まない。ファイルキャッシュが温まった同一Mac上の比較であり、別端末や初回ディスク読取への一般化はしない。

## 時間とメモリ

| 条件 | API中央値：比較元 → 比較先 | CLI中央値：比較元 → 比較先 | Pythonピーク：比較元 → 比較先 |
| --- | --- | --- | --- |
| 小規模：16ソース・40部品 | 4.21 → 3.07 ms | 74.96 → 73.98 ms | 0.252 → 0.258 MiB |
| 台帳：256ソース・1,500部品 | 124.50 → 69.00 ms | 195.80 → 135.39 ms | 8.965 → 9.054 MiB |
| アセット：小規模＋32 MiBファイル | 22.77 → 19.58 ms | 96.85 → 84.11 ms | 32.014 → 0.265 MiB |
| nibbleの文書検査 | 585.26 → 144.45 ms | 未測定 | 8.426 → 0.800 MiB |

台帳のAPI時間は約45%、文書検査は約75%短縮した。32 MiBアセットでは一括読込を分割ハッシュへ変え、入力サイズに比例した一時領域を減らした。小規模と台帳のPythonピークはわずかに増えており、全条件でのメモリ削減は主張しない。小規模CLIの差は小さく、起動時間の改善を主な成果とは扱わない。

文書検査は、リンクごとに対象文書を再解析する処理を除き、本文から得た見出し・参照・記載例を1回の検査内で共有する。構文木は保持せず、文書の配置に固有の規約は各配置で適用する。

## サイズと実行方式

| 対象 | 比較元 | 比較先 |
| --- | --- | --- |
| `ui_design/*.py`の実行ソース | 13,909 bytes | 17,482 bytes |
| `tools/ui-design/`全体のGit管理ファイル | 47,548 bytes / 15ファイル | 61,207 bytes / 19ファイル |

明示的な設定の型、責務の分離、回帰テスト、測定手順によりソースとツールキットのサイズは増えた。外部依存とNix lockは同じである。上表は圧縮前のソースサイズであり、インストール済みPython環境や配布バイナリのサイズではない。

内部の走査・解析は直列である。同じprocessからの独立した並行呼出しは4 worker・12呼出しで結果の一致を確認した。内部並列化によるスループット比較は未測定。共有parserや呼出しをまたぐ可変キャッシュを設けず、保持量と実行時間は[ツールの測定条件](../tools/ui-design/README.md#テストと測定)に従って評価する。

## 保証範囲

[公開Interfaceの回帰テスト](../tools/ui-design/tests/test_engine.py)は、入力内容の変更検出、独立した返却値と並行呼出し、不正入力の拒否を検査する。製品の描画・応答や、設計理由の妥当性をこの測定で評価しない。検査中の外部書込を防ぐ全体ロックはない。

## 再現手順

比較先のcheckoutで実行する。比較元を独立したディレクトリへ展開し、同じ測定プログラムへ両実装を渡す。

```sh
mkdir -p artifacts/design-benchmark/before
nix develop --command sh -c 'git archive 33eaf956ff145ce3a9f15922fa0c9b8376f64ef9 | tar -x -C artifacts/design-benchmark/before'

nix develop --command python3 tools/ui-design/benchmarks/measure.py \
  --toolkit artifacts/design-benchmark/before/tools/ui-design --samples 7
nix develop --command python3 tools/ui-design/benchmarks/measure.py \
  --toolkit tools/ui-design --samples 7

nix develop --command python3 scripts/benchmark_docs.py \
  --scripts artifacts/design-benchmark/before/scripts \
  --root artifacts/design-benchmark/before --samples 7
nix develop --command python3 scripts/benchmark_docs.py \
  --scripts scripts --root artifacts/design-benchmark/before --samples 7
```

別の変更を加えたcheckoutで再実行した場合は、その対象コミットと条件を別の観測として記録する。記載した時間をCIの固定閾値にせず、読取回数・副作用・参照の整合は回帰テストで確認する。
