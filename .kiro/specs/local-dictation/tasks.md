# Tasks
- [x] 1.1 Coreの状態遷移・保護判定・ローカル整形とテスト。_Boundary: Sources/DictationCore, Tests_ _Depends: none_
- [x] 2.1 SpeechとCLI、モデル取得と合成音声検証。_Boundary: Sources/DictationSpeech, Sources/DictationCheck_ _Depends: 1.1_
- [ ] 3.1 Mac UI、録音、ホットキー、取消、フォーカス安全な貼り付け。_Boundary: Sources/LocalDictation_ _Depends: 2.1_
- [ ] 4.1 ビルドスクリプト、独立レビュー、最終検証、README。_Boundary: scripts, README_ _Depends: 3.1_
- [ ] 4.2 人の発話・本人操作による入力欄検証。_Boundary: manual acceptance_ _Depends: 4.1_
- [x] 5.1 Coreに辞書、保存設定、意味保存と安全な訂正ルール、比較テストを追加。_Boundary: Sources/DictationCore, Tests/DictationCoreTests_ _Depends: 1.1_
- [ ] 5.2 日本語turbo・語彙hint・idle解放・録音中の順次認識。_Boundary: Sources/DictationSpeech, Sources/LocalDictation_ _Depends: 5.1_
- [ ] 5.3 辞書設定UI・キー変更・自動起動・明示推敲プレビュー。_Boundary: Sources/LocalDictation_ _Depends: 5.1_
- [ ] 5.4 三対象比較と優位性レポート、最終検証。_Boundary: scripts, benchmarks, README_ _Depends: 5.2,5.3_
