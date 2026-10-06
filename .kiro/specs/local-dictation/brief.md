# Brief: local-dictation
## Problem
Typeless相当の日本語音声入力をM2 Mac mini・16GBで端末内処理に置き換える。
## Current State
独立した新規プロジェクト。OllamaとXcodeはインストール済み、Ollamaモデルはなし。headset-typelessは既存Typelessへのボタンブリッジ。
## Desired Outcome
ショートカットで録音、ローカル認識、意味を変えない整形、元の入力欄への貼り付け。
## Approach
SwiftUIメニューバーアプリ、比較結果に基づくwhisper.cpp large-v3-turbo q5、localhost Ollama。WhisperKitは隔離診断用に残す。初回モデル取得のみインターネットを利用。
## Scope
- In: 日本語・英語の固有名詞、開始停止、取消、文字起こし原文と結果表示、コピー、状態・エラー表示、ローカルモデル準備。
- Out: ヘッドセット操作、クラウドAPI、配布・公証、常時録音、画面取得。
## Boundary Candidates
UI・録音・モデル認識・整形・貼り付け。
## Out of Boundary
既存headset-typelessの変更。
## Upstream / Downstream
Upstream: macOS音声・アクセシビリティ権限。Downstream: 将来のヘッドセット連携。
## Existing Spec Touchpoints
なし。
## Constraints
16GB、同時処理禁止、入力先の変更時は自動貼り付けを中止。人の発話による最終検証は本人操作が必要。
