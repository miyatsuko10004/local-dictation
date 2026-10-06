# 入力機器とヘッドセット連携（2026-10-06）
ユーザーは精度向上を劣後にし、マイク選択と既存headset-typeless対応を指示。既存の実機許可は維持。

## 受け入れ条件
1. 設定画面でシステム標準または利用可能な入力機器を選び、UIDを保存・復元する。
2. 指定UIDが不在なら別マイクへ無言で切り替えず録音開始を拒否。録音中の変更は無効。
3. CoreAudio入力AudioUnitを選択機器へ設定し、設定結果と録音を別々に確認。
4. headset-typeless --target local-dictation が専用DistributedNotificationを送信し、Local Dictationの明示オン設定でのみ録音をトグル。フォーカス移動、Return送信、キーボードイベント送信は行わない。
5. 既存bridgeの無指定Typelessモードを維持。UUID重複と1秒以内のイベントを除外し、処理中は既存ワークフローで新録音を拒否。
6. LaunchAgent対象切替は一つの既存ラベルで行う。物理ヘッドセット動作と接続復帰は実機検証が必要。

## 検証
swift test / scripts/build.sh、headset-typeless build.sh / test-log-parser.sh、専用通知の隔離受信テスト、GUI機器選択の保存・復元、本人の物理ボタンと指定マイクで録音。

- [x] マイク選択とUIDルーティング
- [x] 専用通知とbridge対象指定
- [x] テスト・レビュー・ビルド
- [x] 実機録音とボタン確認

実機補足: OpenMove選択の保存と再起動後復元、AU読戻し後の録音開始を確認。初回形式変更で停止する問題を修正し、同UIDで復旧後22秒継続を確認。物理ボタンの開始（PAUSE）・停止（HFP log）の専用通知、発話「ヘッドセットのマイクで入力しています」の認識とTextEdit入力を確認。本人も「いけた！」と成功を確認。37 Swift tests、bridge 6＋7 assertions、隔離IPC、release build、read-onlyレビュー承認。

完了ゲート: VERIFIED（今回要求のマイク選択・専用headset連携）。Bluetooth再接続・スリープ復帰の長期安定性は未検証。精度比較の親目標はユーザー指示で劣後、完了扱いにしない。
