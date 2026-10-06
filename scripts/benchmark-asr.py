#!/usr/bin/env python3
"""Same-file comparison; public LocalVoice fixtures; no personal dictionary/history."""
import importlib.util,json,os,pathlib,subprocess,time,statistics,array,math,hashlib
ROOT=pathlib.Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('reference',ROOT/'.benchmark/LocalVoice/scripts/eval_asr.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
acceptance=os.environ.get('LOCAL_DICTATION_BENCHMARK_ACCEPTANCE')=='1'
audio=ROOT/('.benchmark/audio/acceptance' if acceptance else '.benchmark/audio/comparison');audio.mkdir(parents=True,exist_ok=True)
fixtures=[]
holdout = [
 ("ファイルは削除しません。共有も送信も許可していません。", "ファイルは削除しません。共有も送信も許可していません。", []),
 ("予算は12500円、締め切りは11月15日です。", "予算は12500円、締め切りは11月15日です。", []),
 ("佐藤さんと高橋さんに確認してから、報告書を提出します。", "佐藤さんと高橋さんに確認してから、報告書を提出します。", []),
 ("見積書の修正箇所を確認しました。追加の契約はしません。", "見積書の修正箇所を確認しました。追加の契約はしません。", []),
 ("クロードコードで修正し、コーデックスで確認します。公開はまだしません。", "Claude Codeで修正し、Codexで確認します。公開はまだしません。", ["Claude Code", "Codex"]),
 ("録音を停止してから、文章を確認します。誤りがあれば自分で修正します。", "録音を停止してから、文章を確認します。誤りがあれば自分で修正します。", [])
]

cases=json.loads((ROOT/'benchmarks/acceptance-cases.json').read_text()) if acceptance else ref.CASES + holdout
for vi,voice in enumerate(['Kyoko (Japanese (Japan))','Eddy (Japanese (Japan))']):
    for ci,(spoken,expected,terms) in enumerate(cases):
        path=audio/f'{vi}-{ci}.wav'
        subprocess.run(['say','-v',voice,'--file-format=WAVE','--data-format=LEI16@16000','-o',str(path),spoken],check=True)
        import wave
        with wave.open(str(path)) as wav:
            if wav.getnframes()/wav.getframerate() < 2: raise RuntimeError(f'Invalid generated Japanese audio: {voice} {path}')
            samples=array.array('h',wav.readframes(wav.getnframes()))
            rms=math.sqrt(sum(x*x for x in samples)/len(samples))/32768
            if rms < 0.001: raise RuntimeError(f'Silent generated audio: {voice} {path}')
        fixtures.append(dict(id=f'{vi}-{ci}',audio=str(path),expected=expected,terms=terms,voice=voice,prompt=ref.PROMPT,split="acceptance" if acceptance else "reference" if ci<7 else "holdout"))
f=ROOT/('.benchmark/fixtures-acceptance.json' if acceptance else '.benchmark/fixtures.json');f.write_text(json.dumps(fixtures,ensure_ascii=False))
variant=os.environ.get('LOCAL_DICTATION_BENCHMARK_MODEL')
data_root=ROOT/'.benchmark/benchmark-large' if variant else ROOT/'.local-data'
env=dict(os.environ,LOCAL_DICTATION_DATA=str(data_root))
start=time.monotonic()
local=subprocess.run([str(ROOT/'.build/release/dictation-check'),'batch',str(f)],stdout=subprocess.PIPE,text=True,env=env,timeout=900,check=True)
# CoreML warnings may precede JSON on stdout.
localjson=json.loads(local.stdout[local.stdout.index('{'):])
rows=[]
for fixture,own in zip(fixtures,localjson['rows']):
    start=time.monotonic()
    p=subprocess.run([str(ROOT/'.benchmark/whisper.cpp/build/bin/whisper-cli'),'-m',str(ROOT/'.benchmark/LocalVoice/Models/ggml-large-v3-turbo-q5_0.bin'),'-f',fixture['audio'],'-l','ja','-t','4','-nt','--prompt',ref.PROMPT],capture_output=True,text=True,timeout=120,check=True)
    baseline=ref.fix_vocabulary(p.stdout.strip())
    own["productionText"]=own["text"]
    own["text"]=ref.fix_vocabulary(own["raw"].strip())
    rows.append(dict(audioSHA256=hashlib.sha256(pathlib.Path(fixture["audio"]).read_bytes()).hexdigest(),voice=fixture["voice"],split=fixture["split"],id=fixture['id'],expected=fixture['expected'],own=own,baseline=dict(text=baseline,seconds=time.monotonic()-start),ownCER=ref.cer(fixture['expected'],own['text']),baselineCER=ref.cer(fixture['expected'],baseline),terms=fixture['terms']))
    print(fixture['id'],round(rows[-1]['ownCER']*100,2),round(rows[-1]['baselineCER']*100,2),flush=True)
report=dict(model=localjson['model'],hardware='Apple M2 / 16GiB / macOS27.2',baselineSHA='9ddd67d663eefa424997250097e4216963c6de07',kind='TTS fixture comparison, one run per fixture; CoreML batch cold first row, whisper.cpp per-utterance CLI cold loads',rows=rows)
for key in ['own','baseline']:
    report[key]=dict(meanCER=sum(r[key+'CER'] for r in rows)/len(rows),medianSeconds=statistics.median(r[key]['seconds'] for r in rows),termHits=sum(t in r[key]['text'] for r in rows for t in r['terms']),termTotal=sum(len(r['terms']) for r in rows))
for split in sorted(set(r['split'] for r in rows)):
    selected=[r for r in rows if r['split']==split]
    report[split]={}
    for key in ['own', 'baseline']:
        total=sum(len(ref.norm(r['expected'])) for r in selected)
        edits=sum(round(r[key+'CER']*len(ref.norm(r['expected']))) for r in selected)
        report[split][key]=dict(corpusCER=edits/total,edits=edits,characters=total,medianSeconds=statistics.median(r[key]['seconds'] for r in selected))
report['normalization']='Same public LocalVoice prompt and spelling normalizer on both raw outputs; productionText retains Local Dictation own cleanup.'
(ROOT/('benchmarks/asr-cpp-acceptance-results.json' if acceptance else 'benchmarks/asr-large-results.json' if variant else 'benchmarks/asr-results.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:report[k] for k in ['own','baseline']},indent=2))
