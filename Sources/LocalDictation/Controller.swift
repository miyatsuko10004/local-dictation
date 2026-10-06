import AppKit
import AVFoundation
import DictationCore
import DictationSpeech
import SwiftUI
import ServiceManagement

@MainActor final class DictationController: ObservableObject {
    @Published var status = "ショートカットで話しかけてください"
    @Published var detail = "初回は音声モデルを準備してください。"
    @Published var rawText = ""
    @Published var resultText = ""
    @Published var previewText = ""
    @Published var microphones: [MicrophoneDevice] = []
    @Published var microphoneListError = ""
    @Published var headsetStatus = "連携オフ"
    @Published var recording = false
    @Published var busy = false
    @Published var preparing = false
    @Published var inserting = false
    @Published var prepared = SpeechService.isPrepared()
    @Published var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var level: Float = 0
    @Published var seconds = 0
    @Published var preferences: Preferences
    @Published var dictionary: [DictionaryEntry]
    @Published var processingSeconds: Double = 0
    @Published var shortcutName = "⌘ ⌥ Space"
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    private var workflow = Workflow()
    private var activeID: UUID?
    private var capture: StreamingCapture?
    private var audioDirectory: URL?
    private var timer: Timer?
    private var started: Date?
    private var target: FocusSnapshot?
    private var workTask: Task<Void, Never>?
    private var chunkTask: Task<String, Error>?
    private var chunkTasks: [Task<String, Error>] = []
    private var queued = Set<Int>()
    private var pendingChunks: [Int: AudioChunk] = [:]
    private var nextChunkIndex = 0
    private var keyIsDown = false
    private var idleTask: Task<Void, Never>?
    private let memoryMonitor = MemoryMonitor()
    private let speech = SpeechService()
    private let ollama = OllamaClient()
    private let hotKey = GlobalHotKey()
    private var headsetObserver: NSObjectProtocol?
    private var headsetGate = HeadsetEventGate()
    private let preferencesStore = PreferencesStore()
    private let dictionaryStore = DictionaryStore()
    private lazy var hud = RecordingHUD(controller: self)

    init() {
        preferences = preferencesStore.preferences; dictionary = dictionaryStore.entries
        hotKey.action = { [weak self] pressed in
            guard let self else { return }
            self.keyIsDown = pressed
            if self.preferences.pushToTalk {
                if pressed && !self.recording { self.toggle(fromHotKey: true) }
                else if !pressed && self.recording { self.toggle(fromHotKey: true) }
            } else if pressed { self.toggle(fromHotKey: true) }
        }
        registerShortcut()
        refreshMicrophones()
        headsetObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(HeadsetIntegration.notificationName), object: nil, queue: .main) { [weak self] notification in
            guard let identifier = notification.object as? String else { return }
            Task { @MainActor in self?.receiveHeadset(identifier) }
        }
        updateHeadsetStatus()
    }
    func saveSettings() {
        guard !recording, !busy else { return }
        do {
            preferencesStore.preferences = preferences.validated(); try preferencesStore.save()
            preferences = preferencesStore.preferences
            dictionary = dictionary.filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            dictionaryStore.entries = dictionary; try dictionaryStore.save()
            registerShortcut()
            updateHeadsetStatus()
            detail = "設定を保存しました。辞書と設定はこのMacだけに保存します。"
        } catch { status = "保存に失敗"; detail = error.localizedDescription }
    }
    func refreshMicrophones() {
        do { microphones = try MicrophoneDevices.available(); microphoneListError = "" }
        catch { microphoneListError = error.localizedDescription }
    }
    private func updateHeadsetStatus() {
        headsetStatus = preferences.headsetEnabled ? "ボタン通知を待っています" : "連携オフ"
    }
    private func receiveHeadset(_ identifier: String) {
        guard preferences.headsetEnabled, headsetGate.accept(identifier, now: ProcessInfo.processInfo.systemUptime) else { return }
        headsetStatus = busy && !recording ? "処理中のためボタン操作を見送りました" : "ボタン通知を受信しました"
        toggle()
    }
    private func registerShortcut() {
        if !hotKey.register(code: preferences.hotKeyCode, modifiers: preferences.hotKeyModifiers) {
            detail = "ショートカットを登録できません。他のアプリとの競合を確認してください。"
        }
        shortcutName = GlobalHotKey.display(code: preferences.hotKeyCode, modifiers: preferences.hotKeyModifiers)
    }
    func setShortcut(code: UInt32, modifiers: UInt32) {
        preferences.hotKeyCode = code; preferences.hotKeyModifiers = modifiers; saveSettings()
    }
    func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary); refreshPermissions()
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            detail = SMAppService.mainApp.status == .requiresApproval ? "システム設定のログイン項目で許可してください。" : "自動起動の設定を更新しました。"
        } catch { detail = "自動起動を変更できませんでした。" + error.localizedDescription }
    }
    func prepare() {
        guard !busy, !recording else { return }
        idleTask?.cancel(); busy = true; preparing = true
        status = "音声モデルを準備中"
        detail = "初回のみモデルを取得します。取得・Mac用の最適化には数分かかることがあります。"
        workTask = Task {
            defer { busy = false; preparing = false; workTask = nil; scheduleUnload() }
            do {
                try await speech.prepare()
                prepared = true; status = "準備できました"
                detail = "音声認識は端末内で処理します。ショートカットで録音できます。"
            } catch { status = "モデル準備に失敗"; detail = error.localizedDescription }
        }
    }
    func toggle(fromHotKey: Bool = false) {
        if recording { stop(); return }
        guard !busy, workTask == nil else { return }
        guard prepared else { status = "音声モデルが未準備です"; return }
        let requireHeld = fromHotKey && preferences.pushToTalk
        idleTask?.cancel(); target = FocusSnapshot.capture(); busy = true
        workTask = Task {
            defer { busy = false; workTask = nil }
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
            default: allowed = false
            }
            refreshPermissions()
            guard !Task.isCancelled else { status = "中止しました"; return }
            guard !requireHeld || keyIsDown else { status = "録音を中止しました"; return }
            guard allowed else {
                status = "マイクの許可が必要です"
                detail = "システム設定でLocal Dictationのマイクを許可してください。"; return
            }
            do { try startRecording() }
            catch { status = "録音に失敗"; detail = error.localizedDescription; removeAudio() }
        }
    }
    private func startRecording() throws {
        guard let id = workflow.begin() else { return }
        activeID = id; chunkTask = nil; chunkTasks = []; queued = []; pendingChunks = [:]; nextChunkIndex = 0
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LocalDictation-" + UUID().uuidString, isDirectory: true)
        audioDirectory = folder
        let capture = try StreamingCapture(directory: folder)
        capture.writer.onChunk = { [weak self] chunk in
            Task { @MainActor in self?.enqueue(chunk, id: id) }
        }
        capture.onRecovery = { [weak self] in
            Task { @MainActor in
                guard let self, self.recording, self.activeID == id else { return }
                self.detail = "マイクの音声形式変更から復旧しました。切り替え中の音声に短い抜けが生じた可能性があります。"
            }
        }
        capture.onInterruption = { [weak self] in
            Task { @MainActor in
                guard let self, self.recording, self.activeID == id else { return }
                self.stop()
                self.detail = "マイクの接続または音声形式が変わったため、録音を停止しました。"
            }
        }
        try capture.start(microphoneUID: preferences.microphoneUID); self.capture = capture
        hud.show()
        started = Date(); seconds = 0; recording = true; rawText = ""; resultText = ""; previewText = ""
        status = "聴き取り中"; detail = "マイク: \(capture.microphoneName)。もう一度ショートカットまたはヘッドセットのボタンで停止。"
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.meter() }
        }
    }
    private func meter() {
        guard recording, let capture, let started else { return }
        level = capture.level; seconds = Int(Date().timeIntervalSince(started))
        if seconds >= preferences.maxRecordingSeconds { stop() }
    }
    private func enqueue(_ chunk: AudioChunk, id: UUID) {
        guard activeID == id, !queued.contains(chunk.index) else { return }
        pendingChunks[chunk.index] = chunk
        while let next = pendingChunks.removeValue(forKey: nextChunkIndex) {
            nextChunkIndex += 1
            queued.insert(next.index)
            processChunk(next, id: id)
        }
    }
    private func processChunk(_ chunk: AudioChunk, id: UUID) {
        guard chunk.voiced else { return }
        let previous = chunkTask, prompt = DictionaryStore.prompt(entries: dictionary)
        let task = Task<String, Error> {
            let prior = try await previous?.value ?? ""
            try Task.checkCancellation()
            let text = try await speech.transcribe(file: chunk.url, prompt: prompt)
            try Task.checkCancellation()
            let merged = TranscriptMerger.join(prior, text)
            if activeID == id { rawText = merged }
            return merged
        }
        chunkTasks.append(task); chunkTask = task
    }
    private func stop() {
        guard recording, let id = activeID, let capture else { return }
        timer?.invalidate(); timer = nil; recording = false; level = 0
        do {
            let chunks = try capture.stop(); self.capture = nil
            guard capture.writer.totalSamples >= 6400, capture.writer.hasVoice, workflow.stop(id) else {
                workflow.cancel(); removeAudio(); status = "入力できる音声がありません"; scheduleUnload(); return
            }
            for chunk in chunks { enqueue(chunk, id: id) }
        } catch {
            self.capture = nil; workflow.cancel(); status = "録音に失敗"; detail = error.localizedDescription
            cancelPendingChunksAndRemoveAudio(); return
        }
        busy = true; status = "最後の音声を文字にしています"
        let useCleanup = preferences.cleanupEnabled, usePaste = preferences.autoPaste, destination = target
        let currentDictionary = dictionary, model = preferences.cleanupModel, pending = chunkTask
        workTask = Task {
            defer { busy = false; workTask = nil; removeAudio(); scheduleUnload() }
            let start = Date()
            do {
                let raw = (try await pending?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard workflow.accepts(id), !Task.isCancelled else { status = "中止しました"; return }
                guard !raw.isEmpty else { _ = workflow.finish(id); status = "音声を認識できませんでした"; return }
                rawText = raw
                let corrected = DictionaryStore.normalize(raw, entries: currentDictionary)
                var output = TextRules.clean(corrected), note = ""
                if useCleanup && memoryMonitor.shouldSkipOptionalLLM {
                    note = "メモリに余裕がないため、AIを省いて安全な清書を使用しました。"
                } else if useCleanup {
                    await speech.unload()
                    status = "句読点を整えています"
                    do {
                        let cleaned = try await ollama.cleanup(output, model: model)
                        output = cleaned.text
                        if cleaned.rejected { note = "AI候補の意味変更を検出し、安全な清書を使用しました。" }
                    } catch { note = "AIを使用できなかったためルールで清書しました。" + error.localizedDescription }
                }
                guard workflow.accepts(id), !Task.isCancelled else { status = "中止しました"; return }
                resultText = output; processingSeconds = Date().timeIntervalSince(start)
                if usePaste {
                    inserting = true
                    status = "入力先を確認しています"
                    let dispatched = await TextInsertion.paste(output, into: destination)
                    inserting = false
                    status = dispatched ? "入力操作を送りました" : "コピーして入力してください"
                    detail = dispatched ? "入力先で結果を確認してください。" : "入力先の変更または権限不足のため自動入力を止めました。"
                    if !note.isEmpty { detail += " " + note }
                } else { status = "文字起こし完了"; detail = note.isEmpty ? "結果をコピーして使えます。" : note }
                _ = workflow.finish(id)
            } catch {
                workflow.cancel(); status = Task.isCancelled ? "中止しました" : "処理に失敗"
                detail = Task.isCancelled ? "入力操作は行いませんでした。" : error.localizedDescription
            }
        }
    }
    func cancel() {
        guard !preparing, !inserting else { return }
        if let capture { _ = try? capture.stop() }; capture = nil
        timer?.invalidate(); timer = nil; recording = false; level = 0; workflow.cancel()
        chunkTasks.forEach { $0.cancel() }; workTask?.cancel()
        if workTask == nil { cancelPendingChunksAndRemoveAudio() }
        status = busy ? "中止処理中" : "中止しました"
        detail = "現在の処理が終了してから録音を削除します。入力操作は行いません。"
    }
    private func cancelPendingChunksAndRemoveAudio() {
        busy = true
        let pending = chunkTasks
        pending.forEach { $0.cancel() }
        workTask = Task {
            for task in pending { _ = try? await task.value }
            removeAudio(); workTask = nil; busy = false; status = "中止しました"; scheduleUnload()
        }
    }
    private func removeAudio() {
        hud.hide()
        if let url = audioDirectory { try? FileManager.default.removeItem(at: url) }
        audioDirectory = nil; activeID = nil; queued = []; pendingChunks = [:]; chunkTasks = []; chunkTask = nil
        if !recording { workflow.cancel() }
    }
    private func scheduleUnload() {
        idleTask?.cancel()
        let seconds = preferences.idleUnloadSeconds
        idleTask = Task {
            do { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) } catch { return }
            guard !recording, !busy else { return }
            await speech.unload()
        }
    }
    func addDictionaryEntry() { dictionary.append(DictionaryEntry(word: "", readings: [])) }
    func makePreview() {
        guard !busy, !recording, !resultText.isEmpty else { return }
        guard !memoryMonitor.shouldSkipOptionalLLM else { status = "メモリに余裕がありません"; detail = "文章は保持しています。ほかのアプリを閉じてから再試行してください。"; return }
        busy = true; status = "推敲プレビューを作成中"
        let text = resultText, model = preferences.cleanupModel
        workTask = Task {
            defer { busy = false; workTask = nil }
            do {
                await speech.unload()
                let candidate = try await ollama.preview(text, model: model)
                guard !Task.isCancelled else { return }
                previewText = candidate; status = "推敲プレビューを確認してください"
                detail = "推敲は表現を変えます。原文と比較してから採用してください。自動入力は行いません。"
            } catch { status = "推敲できませんでした"; detail = error.localizedDescription }
        }
    }
    func adoptPreview() {
        guard !previewText.isEmpty, !busy else { return }
        resultText = previewText; previewText = ""; status = "推敲を採用しました"; detail = "コピーして使えます。"
    }
    func copyResult() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(resultText, forType: .string)
        status = "コピーしました"
    }
    func shutdown() {
        if let headsetObserver { DistributedNotificationCenter.default().removeObserver(headsetObserver); self.headsetObserver = nil }
        if let capture { _ = try? capture.stop() }; capture = nil
        timer?.invalidate(); workTask?.cancel(); chunkTasks.forEach { $0.cancel() }; idleTask?.cancel()
        removeAudio()
    }
}
