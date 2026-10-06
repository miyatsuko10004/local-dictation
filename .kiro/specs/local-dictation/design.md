# 設計の履歴

以下は初版の設計メモ。現在の実装はwhisper.cpp large-v3-turbo q5、AVAudioEngineチャンク録音、Core Audio UID選択、専用ヘッドセット通知へ更新済み。現行構成はREADMEとinput-devices.mdを参照。

# Design
1. Core: 純粋な状態遷移・テキスト保護判定・Ollamaクライアント。HTTPは固定loopback、ephemeral session、redirect禁止、timeout、stream false。
2. Speech: WhisperKit 1.1.0、多言語smallを初版、モデルとtokenizerはApplication Supportに保存。明示prepareでdownload、通常loadはdownload false。CLIとGUIで共有。
3. App: SwiftUI Window+MenuBarExtra、Carbon RegisterEventHotKey、AVAudioRecorder、AX focus identity、CGEvent Command+V、NSPasteboard変更数を確認して復元。cancelはgeneration tokenを無効化。
4. CLI: prepare / transcribe / cleanup / smoke。録音権限を必要としない合成音声のend-to-end検証を提供。
5. Privacy: 自動履歴保存なし、ログに本文なし。初回取得と実行時処理を区別。整形は意味変更を完全保証できないため原文と比較可能。
6. Core拡張: DictionaryEntry/DictionaryStore（編集・JSON atomic保存・長い読み優先・ラテン/カタカナ語境界・defaultEntries・prompt150文字）、TextRules（安全なフィラー除去と狭い訂正）、CleanupPolicy（TextRules後に単語列を完全保存する文字列照合）、Preferences（Codable設定）。
7. Compare: ベンチマークチェックアウトは.benchmarkに隔離、ソースを移植しない。固定語彙テストと合成音声を共有して比較。モデルは多言語WhisperKit turbo632MBへ変更、標準日本語・語彙hint。LLMは明示的推敲以外で任意書換を拒否。低メモリ時skip、推論の順序とidle解放。

## 8. 実測に基づくASR選択
M2で26同一音声を共通ヒントと辞書で比較し、WhisperKit圧縮turboと947MB variantはwhisper.cpp turbo q5より精度が劣った。アドバイザー相談の推奨Bに従い、常用ASRは固定whisper.cpp v1.9.1（f049fff95a089aa9969deb009cdd4892b3e74916）とq5モデルへ変更。直接Processを実行し、同時stdout/stderr排出、120秒期限、取消、子の回収、排他実行を実装。helperはstaticリンク・Metal埋め込みでアプリに同梱し、本番でHomebrewやbenchmark checkoutを参照しない。CoreMLは隔離ディレクトリの評価経路だけに残す。モデル取得は明示準備のみ、SHA256固定。
