# 比較・検証結果

2026-10-06 / Apple M2 / 16GiB / macOS27.2。常用の右Shift録音とTextEdit自動入力は本人操作・実画面で確認済み。三対象全体への優位性の判定は、認識部品の追加比較が完了するまで保留する。

## 検証済みの機能

- 右Shiftで開始・停止。TextEditへの自動入力。停止後2.3秒の実測。
- 実アプリで中止後に入力が発生しないこと、一時録音フォルダ残存0。
- ローカルAI推敲の完了と、確認用文章の数字・否定・製品名保持。採用前のプレビューは自動入力しない。
- 単体テスト Core24＋Speech13＝37件／失敗0、releaseビルド・内外署名検証、独立レビューAPPROVED。
- `scripts/setup.sh --with-ai --no-open` 成功。既存モデルを保持し、明示的な非思考モデルを追加する。

個人用の実音声比較記録は端末内に保持し、Gitの対象から除外する。合成音声の一致だけでは、任意の人の発話で誤認識が解決したとは判定しない。

## 固定対象と比較範囲

|対象|固定SHA|確認範囲|
|---|---|---|
|LocalVoice|9ddd67d663eefa424997250097e4216963c6de07|実ガード、公開ASRケース・同モデルCLI比較|
|VoiceKun|aff0f71d709341cffb8b34a9cae0969e55a09a6c|実出力清掃部品、端末内Speech比較はOS日本語資産待ち|
|localTypeless|d0a82ba3f2ed678d477f1748fc75b6b1803d8026|実最終出力部品、実ASRサービスの隔離比較結果を保存（評価は劣後）|

参照: [LocalVoice紹介](https://note.com/len_ai_channel/n/n35ef4662199f)、[VoiceKun紹介](https://www.seeds-std.co.jp/blog/pr/9069/)、[localTypeless](https://github.com/tao1587/localTypeless)。紹介記事の別機種の速度を本機の勝利判定に流用しない。

## 意味保存の固定候補比較

危険24件・正当10件を結果を見る前に固定し、同じ候補を各実ソースのガード／最終出力部品へ通した。

|部品|危険候補の採用|正当候補の拒否|
|---|---:|---:|
|Local Dictation意味保存ガード|0/24|0/10|
|LocalVoice EditGuard＋IntegrityValidator|12/24|2/10|
|VoiceKun clean＋Qwen後段検査|24/24|0/10|
|localTypeless TranscriptLanguage＋finalOutput|24/24|0/10|

VoiceKunは実clean関数2つと実Qwen後段検査を隔離し、辞書置換を無効にした。localTypelessは実プロトコル・言語推定・最終出力関数を使用した。これは生成済み候補を拒否する保護の比較で、モデルが危険候補を生成する頻度、音声認識精度、アプリ全体の性能ではない。Local Dictationがこの固定候補セットで明確に改善したことは確認できる。

再現: `python3 scripts/compare-output-protection.py`。全候補・出力・コピー範囲・制約: [output-protection-results.json](output-protection-results.json)、[guard-cases.json](guard-cases.json)。LocalVoiceだけの既存再現は`compare-guards.py`。

## LocalVoiceとの同じ音声による認識比較

同じM2、同じlarge-v3-turbo q5、同じ固定WAV、共通ヒント・公開語彙正規化を使用。常用エンジンは公式whisper.cpp v1.9.1の固定SHA f049fff95a089aa9969deb009cdd4892b3e74916。

|集合|音声数|自作CER|参照CER|正規化後一致|
|---|---:|---:|---:|---:|
|公開7文×2声|14|0.58%|0.58%|14/14|
|追加6文×2声|12|0.62%|0.62%|12/12|
|別固定10文×2声|20|0%|0%|20/20|

最初の26件では製品名一致21/22が両方同じ。中央値は自作2.01秒・参照2.01秒で、速度優位は主張しない。追加20件の中央値は自作2.03秒・参照1.91秒。全46件で非劣性を確認したが、同じ認識モデルで精度が上回ったとは言えない。参照CLIと製品helperはどちらも録音単位でプロセスを起動する。

結果: [asr-results.json](asr-results.json)、[asr-cpp-acceptance-results.json](asr-cpp-acceptance-results.json)。WAVごとのSHA、入力文、各出力、時刻、編集距離を保存。合成音声は人の多様な発話精度の保証ではない。

## 任意のAI整形

汎用`qwen3:4b`の取得digestがThinking-2507版と一致し、`think:false`、`/no_think`、閉じた思考タグでも英文分析が上限まで続いた。アドバイザーへの追加相談を踏まえて、テンプレート修正案を撤回し、明示的な非思考Instruct版を別モデルとして追加した。元モデルは変更していない。

選択モデル: `qwen3:4b-instruct-2507-q4_K_M`。検証digest: `0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0`。

固定10文すべて処理完了。候補採用7件、そのうち3件でAI句読点変更。残る3候補はガードが拒否し原文／決定的清書を保持。初回3.33秒、残る9件0.61〜1.05秒。全件原文フォールバックではないことを確認した。モデル自体に任意の文章の意味保存を保証しない。

結果: [cleanup-instruct-results.json](cleanup-instruct-results.json)、[cleanup-model-metadata.json](cleanup-model-metadata.json)。入力は4096文脈に収まる保守的なUTF-8上限1600バイトで検査し、超過時はAIへ送らず原文を保持する。任意のカスタムテンプレートまでの文脈サイズ保証ではない。

## 残る比較ゲート（入力機器の整備を優先し、現在は劣後）

localTypelessは宣言されたWhisperKit依存範囲から新規解決した0.18.0と実ASRサービスを隔離し、無量子化turbo・自動言語・ヒントなしで同じ46WAVを測定する。配布済みアプリの過去の依存解決版は記録がなく確定できない。

VoiceKunは実request設定を再現する端末内Speechヘルパーを用意し、同じ46WAVをリアルタイムで供給する。マイクは使わない。Apple Speech権限は許可済みだが、実GUIで `supportsOnDeviceRecognition=false`、macOS設定も日本語の端末内モデル取得待ちと表示したため未開始。精度・速度は未測定で、利用不可を勝利判定に数えない。詳細は [voicekun-asr-results.json](voicekun-asr-results.json)。実アプリ全体の操作・無音時再開始・AI整形はこのヘルパーの測定対象ではない。

比較部品の同条件精度・冷間／温間・メモリを測定し、未測定項目を優位と数えない。本人入力ゲートと合成コーパス比較は別の証拠として扱う。

## 過去の候補と無効な測定

旧632MB CoreML方式は公開例CER9.30%、追加6文0.93%で参照に劣った。947MB CoreML候補は1.55%／0.93%、中央値5.70秒で未採用。常用方式を同じ検証済みwhisper.cppモデルへ変更した。947MBは圧縮CoreML候補であり完全な無圧縮large-v3ではない。

最初にEddyの日本語音声名を誤指定した測定は[asr-invalid-voice-results.json](asr-invalid-voice-results.json)で無効と明記し、受入判定から除外した。不要な旧CoreML比較モデルと重複モデルを空き容量確保のため整理し、常用モデル・参照音声・評価結果を保持した。旧候補を再実行する場合は再取得が必要。
