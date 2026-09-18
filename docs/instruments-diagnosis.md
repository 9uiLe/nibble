# Instrumentsの診断記録

## 評価対象と結論

本書は、2026-09-18に実施したiOS 26.5 SimulatorのInstruments接続試験を記録する。目的は、記録を開始できない原因を製品コードと計測環境に切り分けることである。計測の構成、成立条件、再確認コマンドは[性能検証の手順](performance-verification.md)に定義する。

Simulatorの`DTServiceHub`がCPU計測サービスを生成できず、`xctrace`が記録開始を待ち続けることを確認した。`DTServiceHub`はInstrumentsと計測対象を接続する補助プロセスである。Nibbleを含まない最小Cプログラムでも同じ停止を再現したため、製品のSwiftUI・Rive・保存処理に依存しない。

接続失敗の内部原因は未特定である。専用サービスと専用Simulatorの再起動では復旧せず、有効なSimulator用traceは未取得。ホストOS・Xcode・runtimeのどの実装や設定が接続失敗を起こすかは、この結果から確定できない。

## 環境と測定方法

| 項目 | 条件 |
| --- | --- |
| リポジトリ | `14926299284d4c424283c6660122c6721968ab8e`。製品ファイルは`f14c5008008b44ea6ca25c67ceeb685775ec0522`と同一 |
| ホスト | Apple Silicon、macOS 26.2（25C56） |
| Xcode | 26.5（17F42）、`/Applications/Xcode-26.5.0.app` |
| Instruments / xctrace | アプリ26.5（64576.12）/ CLI表記16.0（17F42）。同じXcode配下のツール |
| runtime | iOS 26.5（23F77） |
| 専用iPhone 17 Pro | `D099A849-386F-4EAE-AE12-02D8DC623AF2` |
| 専用iPhone SE（第3世代） | `517ADFEE-F4CE-462A-987E-4040701A80C4` |
| 製品 | bundle ID `nibble.9uiLe.com`。実行前にPID・起動時刻・パスを照合 |
| 実行 | Apple CLIをエージェントのファイルシステムsandbox外で実行 |

記録時間は5秒。診断driverは実行開始から45秒でSIGINTを送り、5秒待っても終了しなければSIGTERM、その後も終了しなければSIGKILLを送る。約50秒の失敗結果はdriverによる打ち切り時間である。自然にエラーが返るまでの時間や記録時間として扱わない。

`DevToolsSecurity -status`はenabled、`xcodebuild -checkFirstLaunchStatus`は成功、ホスト側`dtsecurity.xpc`の署名検査も成功した。これらは実行時の全権限・接続の正常性を保証するものではない。

[Xcode 26.5の公式リリースノート](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_5-release-notes)が示す最低ホストOSはmacOS 26.2で、評価環境は条件を満たす。同資料では、この停止に対応すると特定できる既知問題・修正を確認できなかった。

## 停止箇所の根拠

Simulatorのサービスログでは、次の接続失敗に続いてCPU計測サービスの生成失敗が記録された。

```text
xpc connection invalid: com.apple.dt.instruments.dtsecurity.xpc
Could not create service named com.apple.instruments.server.services.coreprofilesessiontap
```

同じ時刻のホスト側には次の記録がある。

```text
Device disconnected while trying to set tap configuration
Device disconnected while trying to start tap
```

`xctrace`のメインスレッドは`Runner.runRecording`内のrun loopで待機していた。Nibbleの終了は観測していない。「Device disconnected」は計測経路のログとして扱い、アプリやSimulatorの終了と同一視しない。

`--time-limit 5s`では開始待ち・保存待ちを含む実行全体を打ち切れなかった。30秒記録を要求した`artifacts/performance/baseline-trace.log`の実行でも開始待ちが続き、SIGINTに応答せず約4分で当該プロセスを終了している。これらのtraceから性能値を採用しない。

## 比較試験の結果

| 条件 | 観測 | 判断 |
| --- | --- | --- |
| iPhone 17 ProのNibble、Time Profiler | 新しいPIDでも開始待ち。スタック取得を伴う再試験も同じ | 古いPIDを指定したことだけでは説明できない |
| 専用端末のInstrumentsサービスだけを再起動 | 同じサービス生成エラーと開始待ち | 当該サービスの再起動では復旧しない |
| iPhone SEのNibble | 同じエラーと開始待ち | 1台だけの状態に依存しない |
| Time Profiler単体、CPU Profiler、Sampler単体 | いずれも開始待ちで打ち切り | 標準Time Profilerテンプレート内の別計測器だけが原因ではない |
| Activity Monitor | 2.623秒で終了コード2。`Activity monitoring service not available on this device.` | この条件では代替として利用できない |
| Simulator用の最小Cプログラム | CPUループと短いsleepだけでも同じ開始待ち | Nibbleのコードに依存しない |
| 専用Simulatorをshutdown / bootして同じNibbleを起動 | サービス生成エラーと開始待ちが継続 | データを消さない端末再起動では復旧しない |
| Mac用の最小Cプログラム、`host-fixture` | 記録は開始し5秒後に停止へ進むが、保存完了を待って打ち切り | Simulatorの開始失敗とは異なる段階。この保存待ちの原因は未特定 |
| Mac用プログラム、デバッグ接続用entitlement付き | 正常終了14.347秒、Time Profilerのサンプル行2,663件 | ホスト側で有効なtraceを取得できる |
| Mac用プログラム、追加entitlementなしの元のバイナリを再試験 | 正常終了13.456秒、サンプル行2,851件 | entitlement追加を復旧原因とする仮説は支持されない |
| 再起動後のNibbleへ`/usr/bin/sample`を2秒実行 | 終了コード0、PIDに対応するcall graphを取得 | 通常のスタック取得は可能。Instruments traceの代替評価にはしない |

Mac用プログラムはClangが付けるad-hoc署名を持つ。「追加entitlementなし」は無署名という意味ではない。成功したMacのtraceはXMLへexportし、`time-profile`テーブルの実データ行が存在することまで確認した。CPU負荷用fixtureの結果であり、Nibbleの性能値には使わない。

端末指定を省略してSimulatorのPIDを渡す試験は「該当PIDがない」と即時終了した。ホスト側のプロセス選択とは一致しないため、回避策にも権限の比較にも使わない。

## 証跡の所在と再現範囲

ローカル証跡は`artifacts/performance/instruments-diagnosis/`に保存した。Git管理対象外のため、新しいcheckoutには含まれない。

| 証跡 | 内容 |
| --- | --- |
| `probe.py`、最小Cソース | 時間制限とexport判定を行う診断driver、製品に依存しないCPU負荷プログラム |
| 各試験の`result.json`・`record.log`・trace | コマンド、PIDの識別情報、開始時刻、終了コード、打ち切り、所要時間 |
| `simulator-service.log` / `simulator-se-service.log` | 2台の接続・サービス生成失敗 |
| `after-reboot-service.log` | 専用Simulator再起動後の同じ失敗 |
| `host-fixture-debug/` / `host-fixture-unsigned-repeat/` | 正常終了・保存・XML export・実データの確認に成功したMacの対照試験 |
| `nibble.sample.txt` | 同じNibbleプロセスに対する通常サンプリングのcall graph |

比較試験はPython driverで実行した。[性能検証の手順](performance-verification.md)のGNU timeoutを使うコマンドとは区別する。GNU coreutils 9.11の存在と`xctrace`のrecord / exportの仕様は導入済み環境で確認したが、そのコマンドを成功したSimulator計測として記録していない。

## 未確定事項と再評価条件

- 接続失敗の内部原因と回復手段は未特定。Mac側の保存待ちも一度発生したが、再試験は成功しており、その回復理由を署名へ帰属できない。
- Instruments本体は起動した。ネイティブUI接続がタイムアウトし、画面上の警告・権限ダイアログは未確認。認証待ちを原因とする証拠は得ていない。
- GUIで同じ最小プログラムを記録し、CLIとの差を確認する余地がある。再現が続く場合は、同じiOS runtimeでホストOSまたはXcodeを一つずつ変えて比較する。
- Mac全体の再起動、別バージョンの導入、端末のeraseは未実施。更新・再インストールによる復旧は確認していない。

製品ソース・製品の署名設定・システムのセキュリティ設定は変更していない。秘密情報、Keychain、配布用認証設定、認証ログは参照していない。

この結果が保証するのは計測障害の切り分けである。[SwiftUIの評価記録](swiftui-investigation.md)で未取得とするbody時間、hitch、GPU・合成時間は未評価のままとする。
