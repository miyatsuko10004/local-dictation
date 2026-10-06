import XCTest
@testable import DictationCore
final class QualityTests: XCTestCase {
 func testMeaningGuard() {
  let pairs = [("保存しません","保存します"),("成功なら送る","成功で送る"),("10万円です","10円です"),("今日は行く","今日は行かない"),("明日は行かない","明日は行く"),("全員に送る","送る"),("秘密を送らない","秘密を送る"),("許可があれば送る","許可がなくても送る"),("少なくとも10件","10件"),("最大10件","10件"),("多分明日","明日"),("まだ完了していません","完了しました"),("赤と青","赤"),("A_Bを呼ぶ","ABを呼ぶ"),("https://a.com/x?a=1","https://a.com/x?a=2"),("100円","100万円"),("必要です","不要です"),("公開は禁止","公開は可能"),("必ず確認","確認"),("送る前に確認","送って確認"),("月曜に行く","火曜に行く"),("1.5万円","15万円"),("1,000円","1000円"),("「確認、送信」","「確認送信」")]
  for (a,b) in pairs { XCTAssertEqual(CleanupPolicy.choose(original:a,candidate:b),a,"\(a) -> \(b)") }
 }
 func testRuleBaseline() {
  XCTAssertEqual(CleanupPolicy.choose(original:"えー、送信しません",candidate:"送信します"),"送信しません")
 }
}
extension QualityTests {
 func testCorrectionsPreservePrefixAndUnit() {
  XCTAssertEqual(TextRules.clean("打合せは月曜日、いや火曜日です"),"打合せは火曜日です")
  XCTAssertEqual(TextRules.clean("予算は10万円、ではなくて20万円です"),"予算は20万円です")
  XCTAssertEqual(TextRules.clean("予算は10万円、いや20円です"),"予算は10万円、いや20円です")
  XCTAssertEqual(TextRules.clean("「月曜、いや火曜」と `10円、いや20円`"),"「月曜、いや火曜」と `10円、いや20円`")
  XCTAssertEqual(TextRules.clean("'月曜、いや火曜'"), "'月曜、いや火曜'")
  XCTAssertEqual(TextRules.clean("'10円、いや20円' と月曜、いや火曜"), "'10円、いや20円' と火曜")
  XCTAssertEqual(DictionaryStore.normalize("'クロードコード'", entries: DictionaryStore.defaults), "'クロードコード'")
  XCTAssertEqual(CleanupPolicy.choose(original: "'送信はしません'", candidate: "'送信します'"), "'送信はしません'")
  XCTAssertEqual(TextRules.clean("えーっと、明日"),"明日")
  XCTAssertEqual(TextRules.clean("あの「引用」"),"あの「引用」")
  XCTAssertEqual(TextRules.clean("-10円、いや20円"),"-10円、いや20円")
  XCTAssertEqual(TextRules.clean("考えーる、えー、明日"),"考えーる、明日")
  XCTAssertEqual(CleanupPolicy.choose(original:"予定は月曜、いや火曜です",candidate:"予定は火曜です。"),"予定は火曜です。")
  XCTAssertEqual(CleanupPolicy.choose(original:"https://a.com/x?a=1",candidate:"https://a.com/x?a = 1"),"https://a.com/x?a=1")
 }
 func testDictionaryLongestBoundariesAndPersistence() throws {
  let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:base) }
  let store = DictionaryStore(base:base)
  store.entries = [.init(word:"Claude Code",readings:["クロードコード"]),.init(word:"Claude",readings:["クロード"]),.init(word:"Codex",readings:["codex"])]
  XCTAssertEqual(DictionaryStore.normalize("クロードコードとクロード codex codex_helper 「クロード」",entries:store.entries),"Claude CodeとClaude Codex codex_helper 「クロード」")
  try store.save()
  XCTAssertEqual(DictionaryStore(base:base).entries,store.entries)
  store.entries.removeFirst(); try store.save()
  XCTAssertEqual(DictionaryStore(base:base).entries,store.entries)
  XCTAssertLessThanOrEqual(DictionaryStore.prompt(entries:(0..<100).map{.init(word:"長い単語\($0)",readings:[])}).count,150)
 }
 func testPreferencesRoundTripValidation() throws {
  let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:base) }
  let store = PreferencesStore(base:base)
  XCTAssertEqual(store.preferences.maxRecordingSeconds,600)
  store.preferences.maxRecordingSeconds = 9999; store.preferences.idleUnloadSeconds = -1
  store.preferences.cleanupModel = "remote-cloud"; store.preferences.cleanupEnabled = true
  try store.save()
  let saved = PreferencesStore(base:base).preferences
  XCTAssertEqual(saved.maxRecordingSeconds,600); XCTAssertEqual(saved.idleUnloadSeconds,1)
  XCTAssertEqual(saved.cleanupModel,LocalModelDefaults.cleanup); XCTAssertTrue(saved.cleanupEnabled)
 }
}
extension QualityTests {
 func testUnitSuffixMustMatch() {
  XCTAssertEqual(TextRules.clean("10日間、いや20日間です"),"20日間です")
  for text in ["10日、いや20日間です", "10年、いや20年間です", "10月、いや20月間です", "10時、いや20時間です"] {
   XCTAssertEqual(TextRules.clean(text), text)
  }
 }
 func testBarePrintableHotkeyFallsBack() {
  var preferences = Preferences()
  preferences.hotKeyModifiers = 0
  XCTAssertEqual(preferences.validated().hotKeyModifiers, 2304)
  preferences.hotKeyModifiers = 512
  XCTAssertEqual(preferences.validated().hotKeyModifiers, 2304)
  preferences.hotKeyCode = 122; preferences.hotKeyModifiers = 0
  XCTAssertEqual(preferences.validated().hotKeyModifiers, 0)
  preferences.hotKeyCode = 60; preferences.hotKeyModifiers = 0
  XCTAssertEqual(preferences.validated().hotKeyModifiers, 0)
  preferences.hotKeyCode = 49
  preferences.hotKeyModifiers = 4096
  XCTAssertEqual(preferences.validated().hotKeyModifiers, 4096)
 }
 func testKanaDictionaryDoesNotRewriteVersionsOrIdentifiers() {
  for text in ["コーデックス2", "コーデックス２", "コーデックス_helper", "コーデックスA"] {
   XCTAssertEqual(DictionaryStore.normalize(text, entries: DictionaryStore.defaults),text)
  }
 }
}
extension QualityTests {
 func testNumericTokenBoundariesAreSemantic() {
  for original in ["番号は1 2 3です", "番号は1\n2\n3です", "番号は１ ２ ３です"] {
   let merged = original.contains("１") ? "番号は１２３です" : "番号は123です"
   XCTAssertEqual(CleanupPolicy.choose(original: original, candidate: merged), original)
   XCTAssertEqual(CleanupPolicy.choose(original: original, candidate: original + "。"), original + "。")
  }
  XCTAssertEqual(CleanupPolicy.choose(original:"番号は123です",candidate:"番号は1 2 3です"),"番号は123です")
  XCTAssertEqual(CleanupPolicy.choose(original:"予算は10円、いや20円です",candidate:"予算は20円です。"),"予算は20円です。")
 }
}
extension QualityTests {
 func testDefaultDictionaryCommonProductSpellings() {
  let pairs = [("チャットGPT", "ChatGPT"), ("Chat GPT", "ChatGPT"), ("クロード・コード", "Claude Code"), ("Claudeコード", "Claude Code"), ("Claude code", "Claude Code"), ("ノートブックLM", "NotebookLM"), ("Notebook LM", "NotebookLM"), ("Googleワークスペース", "Google Workspace"), ("GoogleWorkspace", "Google Workspace"), ("アンティグラビティ", "Antigravity"), ("AntiGravity", "Antigravity")]
  for (reading,word) in pairs {
   XCTAssertEqual(DictionaryStore.normalize(reading + "を使う",entries:DictionaryStore.defaults),word + "を使う",reading)
  }
  XCTAssertEqual(DictionaryStore.normalize("三森さん",entries:DictionaryStore.defaults),"三森さん")
 }
}
extension QualityTests {
 func testMixedDictionaryAliasesRespectBothBoundaries() {
  for text in ["チャットGPT２", "ノートブックLM２", "スーパーチャットGPT"] {
   XCTAssertEqual(DictionaryStore.normalize(text,entries:DictionaryStore.defaults),text)
  }
  XCTAssertEqual(DictionaryStore.normalize("チャットGPTを使う",entries:DictionaryStore.defaults),"ChatGPTを使う")
  XCTAssertEqual(DictionaryStore.normalize("ノートブックLMで調べる",entries:DictionaryStore.defaults),"NotebookLMで調べる")
 }
}

final class RightShiftShortcutTests: XCTestCase {
 func testDeviceSpecificShiftState() {
  XCTAssertTrue(RightShiftShortcut.isPressed(keyCode: 60, flags: 0x20004))
  XCTAssertFalse(RightShiftShortcut.isPressed(keyCode: 60, flags: 0x20002))
  XCTAssertFalse(RightShiftShortcut.isPressed(keyCode: 56, flags: 0x20006))
  XCTAssertFalse(RightShiftShortcut.isPressed(keyCode: 60, flags: 0))
 }
}
