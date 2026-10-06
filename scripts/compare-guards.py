#!/usr/bin/env python3
"""Run real LocalVoice guard sources against fixed candidates, not model generation."""
import json, pathlib, subprocess, tempfile, os
ROOT=pathlib.Path(__file__).resolve().parents[1]
source='''import Foundation
let cases = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String:Any]]
var rows: [[String:Any]] = []
for item in cases {
 let a=item["original"] as! String, b=item["candidate"] as! String
 let local=CleanupPolicy.choose(original:a,candidate:b)==b
 let baseline=EditGuard.check(input:a,output:b).accepted && IntegrityValidator.validate(rawText:a,candidateText:b).isValid
 rows.append(["id":item["id"]!,"expected":item["safe"]!,"localDictation":local,"localVoiceGuards":baseline])
}
let data=try! JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
print(String(decoding:data,as:UTF8.self))
'''
with tempfile.TemporaryDirectory(prefix='dictation-guards-') as tmp:
 main=pathlib.Path(tmp)/'main.swift';main.write_text(source)
 exe=pathlib.Path(tmp)/'compare'
 sources=[ROOT/'Sources/DictationCore/Core.swift',ROOT/'Sources/DictationCore/Quality.swift']
 sources += [ROOT/'.benchmark/LocalVoice/Sources/Core/Processing'/x for x in ('EditGuard.swift','IntegrityValidator.swift')]
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(ROOT/'.build/guard-cache'),*[str(x) for x in sources],str(main),'-o',str(exe)],check=True)
 rows=json.loads(subprocess.check_output([str(exe),str(ROOT/'benchmarks/guard-cases.json')]))
 out={'type':'fixed candidate guard comparison; not LLM generation','cases':len(rows),'baseline_sha':subprocess.check_output(['git','-C',str(ROOT/'.benchmark/LocalVoice'),'rev-parse','HEAD'],text=True).strip(),'rows':rows}
 for engine in ['localDictation','localVoiceGuards']:
  out[engine]={'dangerousAccepted':sum(x[engine] and not x['expected'] for x in rows),'legitimateRejected':sum(not x[engine] and x['expected'] for x in rows),'errors':sum(x[engine]!=x['expected'] for x in rows)}
 (ROOT/'benchmarks/guard-results.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:v for k,v in out.items() if k!='rows'},ensure_ascii=False,indent=2))
 if out['localDictation']['errors']:raise SystemExit(1)
