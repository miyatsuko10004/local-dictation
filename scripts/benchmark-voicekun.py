#!/usr/bin/env python3
"""Prepare/review VoiceKun SFSpeech component harness; never launch or request permission."""
import argparse, hashlib, importlib.util, json, pathlib, plistlib, platform, statistics, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
WORK = ROOT / '.benchmark/voicekun-harness'
SHA = 'aff0f71d709341cffb8b34a9cae0969e55a09a6c'

def prepare():
    actual = subprocess.check_output(['git','-C',str(ROOT/'.benchmark/voicekun'),'rev-parse','HEAD'],text=True).strip()
    if actual != SHA: raise RuntimeError('VoiceKun checkout SHA mismatch')
    fixtures = []
    for name,report in [('fixtures.json','asr-results.json'),('fixtures-acceptance.json','asr-cpp-acceptance-results.json')]:
        ff = json.loads((ROOT/'.benchmark'/name).read_text())
        rr = json.loads((ROOT/'benchmarks'/report).read_text())['rows']
        byid = {r['id']:r for r in rr}
        for f in ff:
            digest = hashlib.sha256(pathlib.Path(f['audio']).read_bytes()).hexdigest()
            if digest != byid[f['id']]['audioSHA256']: raise RuntimeError('Audio SHA mismatch')
            fixtures.append({k:f[k] for k in ['id','audio','expected','voice','split']} | {'audioSHA256':digest})
    if len(fixtures) != 46: raise RuntimeError('Expected 46 fixtures')
    (WORK/'fixtures.json').write_text(json.dumps(fixtures,ensure_ascii=False,indent=2))
    app = WORK/'VoiceKun Benchmark.app'
    contents = app/'Contents'
    (contents/'MacOS').mkdir(parents=True,exist_ok=True)
    plist = {'CFBundleExecutable':'VoiceKunBenchmark','CFBundleIdentifier':'local.manyo.VoiceKunBenchmark','CFBundleName':'VoiceKun Benchmark','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','NSSpeechRecognitionUsageDescription':'公開の合成音声46件をこのMac内だけで認識し、VoiceKunの音声認識成分を比較します。マイクは使用しません。','BenchmarkRoot':str(ROOT)}
    (contents/'Info.plist').write_bytes(plistlib.dumps(plist))
    subprocess.run(['swiftc','-parse-as-library','-swift-version','5','-module-cache-path',str(ROOT/'.build/voicekun-module-cache'),str(WORK/'Main.swift'),'-o',str(contents/'MacOS/VoiceKunBenchmark'),'-framework','SwiftUI','-framework','Speech','-framework','AVFoundation'],check=True)
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    diagnostic = {'status':'prepared-awaiting-parent-review-and-user-speech-authorization','baselineSHA':SHA,'fixtures':46,'app':str(app),'kind':'SFSpeech request component adaptation, not whole VoiceKun app','request':{'locale':'ja-JP','requiresOnDeviceRecognition':True,'shouldReportPartialResults':True,'taskHint':'dictation','addsPunctuation':True,'contextualStrings':[]},'differences':['WAV buffer replay at original sample rate in real time replaces AVAudioEngine microphone tap.','No VoiceKun silence restart, UI, input routing, AI polish, or personal dictionary/history.','Start-to-final includes real-time audio replay; postEndAudioSeconds measures completion latency.']}
    (ROOT/'benchmarks/voicekun-asr-results.json').write_text(json.dumps(diagnostic,ensure_ascii=False,indent=2))
    print(app)

def summarize_rows(rows, metadata, evaluator):
    # Preserve partial/error evidence; only successful final callbacks receive accuracy scores.
    scored = []
    for original in rows:
        r = dict(original)
        accepted = r.get('final') is True and not r.get('error')
        r['acceptedFinal'] = accepted
        r['rawCER'] = evaluator.cer(r['fixture']['expected'],r['raw']) if accepted else None
        r['commonNormalizedText'] = evaluator.fix_vocabulary(r['raw'].strip()) if accepted else None
        r['commonNormalizedCER'] = evaluator.cer(r['fixture']['expected'],r['commonNormalizedText']) if accepted else None
        scored.append(r)
    delays = [r['postEndAudioSeconds'] for r in scored if r['acceptedFinal'] and r.get('postEndAudioSeconds') is not None]
    failures = sum(not r['acceptedFinal'] for r in scored)
    report = dict(metadata)
    report['memoryMeasurement'] = 'Helper process cumulative peak RSS only; excludes Apple Speech service processes.'
    report['accuracyMeasurement'] = 'Only successful final callbacks scored. Partial/error rows retain evidence with null CER. Raw and same public vocabulary-normalized CER separately; fresh-install contextualStrings empty.'
    expected_count = report.get('fixtures',46)
    status = 'partial' if len(scored) != expected_count else 'completed-with-failures' if failures else 'completed'
    report.update(status=status,rows=scored,host=platform.platform(),python=platform.python_version(),finalCount=sum(r['acceptedFinal'] for r in scored),failureCount=failures,medianPostEndAudioSeconds=statistics.median(delays) if delays else None)
    return report

def summarize():
    rows = json.loads((WORK/'raw-results.json').read_text())
    spec = importlib.util.spec_from_file_location('public_eval',ROOT/'.benchmark/LocalVoice/scripts/eval_asr.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    metadata = json.loads((ROOT/'benchmarks/voicekun-asr-results.json').read_text())
    report = summarize_rows(rows,metadata,module)
    (ROOT/'benchmarks/voicekun-asr-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(f"{len(rows)} rows summarized; {report['failureCount']} failures")

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--summarize',action='store_true'); args=p.parse_args()
    summarize() if args.summarize else prepare()
