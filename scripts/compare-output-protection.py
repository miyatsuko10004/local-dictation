#!/usr/bin/env python3
"""Fixed candidate acceptance using real guards/normalizers, not model output rates."""
import json,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
VK=ROOT/'.benchmark/voicekun/voicekun/AI/LocalPolishEngine.swift'
LT=ROOT/'.benchmark/localTypeless/LocalTypeless/Services'
text=VK.read_text()
# Copy both exact upstream functions; access stays private inside the wrapper.
start=text.index('    private static func stripReasoningBlocks(')
end=text.index('    private static func cleanChatOutput(',start)
functions=text[start:end]
wrapper='import Foundation\nenum VoiceKunOutputHarness {\n'+functions+'''
 static func finish(_ output: String) -> String? {
  let cleaned = clean(output)
  // Exact post-clean validation in LocalPolishEngine.polish, Qwen branch.
  guard !cleaned.isEmpty, !cleaned.contains("<|im_start|>"), !cleaned.contains("<|im_end|>") else { return nil }
  return cleaned
 }
}
'''
main='''import Foundation
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String:Any]]
var rows: [[String:Any]] = []
for item in cases {
 let a=item["original"] as! String, b=item["candidate"] as! String
 let vk=VoiceKunOutputHarness.finish(b)
 let lt=TranscriptTextNormalizer.finalOutput(b,transcript:Transcript(text:a,language:"ja",segments:[]))
 rows.append(["id":item["id"]!,"expected":item["safe"]!,
  "localDictation":CleanupPolicy.choose(original:a,candidate:b)==b,
  "localVoiceGuards":EditGuard.check(input:a,output:b).accepted && IntegrityValidator.validate(rawText:a,candidateText:b).isValid,
  "voiceKunOutputAccepted":vk != nil,
  "localTypelessOutputAccepted":true,
  "voiceKunOutput":vk ?? "", "localTypelessOutput":lt])
}
print(String(decoding:try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
'''
with tempfile.TemporaryDirectory(prefix='dictation-output-') as tmp:
 tmp=pathlib.Path(tmp);(tmp/'VoiceKunOutput.swift').write_text(wrapper)
 (tmp/'AudioStub.swift').write_text('final class AudioBuffer: @unchecked Sendable {}\n')
 (tmp/'main.swift').write_text(main)
 exe=tmp/'compare'
 sources=[ROOT/'Sources/DictationCore/Core.swift',ROOT/'Sources/DictationCore/Quality.swift']
 sources += [ROOT/'.benchmark/LocalVoice/Sources/Core/Processing'/x for x in ('EditGuard.swift','IntegrityValidator.swift')]
 sources += [LT/'ASRService.swift',LT/'TranscriptTextNormalizer.swift',tmp/'AudioStub.swift',tmp/'VoiceKunOutput.swift',tmp/'main.swift']
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(ROOT/'.build/guard-cache'),*[str(x) for x in sources],'-o',str(exe)],check=True)
 rows=json.loads(subprocess.check_output([str(exe),str(ROOT/'benchmarks/guard-cases.json')]))
 engines=['localDictation','localVoiceGuards','voiceKunOutputAccepted','localTypelessOutputAccepted']
 report={'type':'fixed candidate component acceptance; no model generation or whole-app accuracy measured',
 'limitations':['VoiceKun: actual output-cleaning functions with exact post-clean Qwen checks; dictionary substitutions disabled.',
 'localTypeless: actual transcript language heuristic and finalOutput; successful polish path always returns normalized candidate.',
 'No network, speech recognizer or LLM generation in this harness. All candidates fixed before comparisons.'],
 'baseline_sha':{n:subprocess.check_output(['git','-C',str(ROOT/'.benchmark'/n),'rev-parse','HEAD'],text=True).strip() for n in ['LocalVoice','voicekun','localTypeless']},'rows':rows}
 for engine in engines:
  report[engine]={'dangerousAccepted':sum(x[engine] and not x['expected'] for x in rows),'legitimateRejected':sum(not x[engine] and x['expected'] for x in rows)}
 (ROOT/'benchmarks/output-protection-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:report[k] for k in engines},ensure_ascii=False,indent=2))
 if report['localDictation'] != {'dangerousAccepted':0,'legitimateRejected':0}:raise SystemExit(1)
