#!/usr/bin/env python3
"""Measure pinned localTypeless ASR component against existing public synthetic WAVs.
No GUI, microphone, history, personal dictionary, or app end-to-end speed claims.
"""
import hashlib, importlib.util, json, os, pathlib, re, statistics, subprocess, sys, time, unicodedata, urllib.request
ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / '.benchmark/localtypeless-harness'
DATA = HARNESS / 'benchmark-model-data'
VARIANT = 'openai_whisper-large-v3-v20240930_turbo'
REPO = 'argmaxinc/whisperkit-coreml'
def norm(text):
    return re.sub(r'[\s、。,.!?！？「」・]', '', unicodedata.normalize('NFKC', text).lower())
def edits(reference, hypothesis):
    r, h = norm(reference), norm(hypothesis)
    previous = list(range(len(h) + 1))
    for i, char in enumerate(r, 1):
        current = [i] + [0] * len(h)
        for j, other in enumerate(h, 1):
            current[j] = min(previous[j] + 1, current[j-1] + 1, previous[j-1] + (char != other))
        previous = current
    return previous[-1]
def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''): result.update(chunk)
    return result.hexdigest()
def add_public_normalizer_sensitivity(result):
    """Supplement raw component scores; never read private dictionary/history."""
    reference_path = ROOT / '.benchmark/LocalVoice/scripts/eval_asr.py'
    spec = importlib.util.spec_from_file_location('public_reference_normalizer', reference_path)
    reference = importlib.util.module_from_spec(spec)
    saved_args = sys.argv
    try:
        sys.argv = [str(reference_path)]  # explicitly prevent the optional --personal branch
        spec.loader.exec_module(reference)
    finally:
        sys.argv = saved_args
    previous = {}
    for prefix, filename in [('comparison-', 'asr-results.json'), ('acceptance-', 'asr-cpp-acceptance-results.json')]:
        for row in json.loads((ROOT / 'benchmarks' / filename).read_text())['rows']:
            previous[prefix + row['id']] = row
    for row in result['rows']:
        row['publicNormalizedText'] = reference.fix_vocabulary(row['text'])
        row['publicNormalizedEdits'] = edits(row['expected'], row['publicNormalizedText'])
        row['publicNormalizedCER'] = row['publicNormalizedEdits'] / max(1, row['characters'])
        own = previous[row['id']]['own']
        row['previousLocalDictationPublicNormalizedText'] = reference.fix_vocabulary(own['raw'].strip())
        row['previousLocalDictationPublicNormalizedEdits'] = edits(row['expected'], row['previousLocalDictationPublicNormalizedText'])
    result['publicNormalizerSensitivity'] = {'sourceSHA256':digest(reference_path), 'privateDictionaryIncluded':False,
        'limits':'Identical public spelling normalizer on raw outputs; localTypeless still auto language/no prompt, own/LocalVoice retained their public prompt. This is supplemental sensitivity, not baseline app behavior.', 'splits':{}}
    for split in ['all'] + sorted(set(row['split'] for row in result['rows'])):
        rows = result['rows'] if split == 'all' else [row for row in result['rows'] if row['split'] == split]
        chars = sum(row['characters'] for row in rows)
        result['publicNormalizerSensitivity']['splits'][split] = {'count':len(rows),'characters':chars,
            'localTypelessCER':sum(row['publicNormalizedEdits'] for row in rows)/chars,
            'previousLocalDictationCER':sum(row['previousLocalDictationPublicNormalizedEdits'] for row in rows)/chars,
            'previousLocalVoiceCER':sum(row['previousLocalVoiceEdits'] for row in rows)/chars}
    return result

def main():
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(HARNESS / '.build/clang-cache'), SWIFTPM_MODULECACHE_OVERRIDE=str(HARNESS / '.build/swift-cache'))
    build = ['swift', 'build', '--package-path', str(HARNESS), '--disable-sandbox', '--cache-path', str(HARNESS / '.build/cache'), '-c', 'release']
    binary = HARNESS / 'bin/LocalTypelessHarness'
    if not binary.exists():
        subprocess.run(build, check=True, env=env)
        binary = HARNESS / '.build/release/LocalTypelessHarness'
    resolved = json.loads((HARNESS / 'Package.resolved').read_text())
    pin = next(p for p in resolved['pins'] if p['identity'] == 'whisperkit')
    for name, path in [('ASRService.swift','Services/ASRService.swift'), ('WhisperKitASRService.swift','Services/WhisperKitASRService.swift')]:
        if digest(HARNESS / 'Sources/LocalTypelessHarness' / name) != digest(ROOT / '.benchmark/localTypeless/LocalTypeless' / path):
            raise RuntimeError('Actual upstream service source changed: ' + name)
    # Fetch revision and LFS SHA-256 metadata from the official model API before downloading.
    api = 'https://huggingface.co/api/models/' + REPO
    with urllib.request.urlopen(api, timeout=60) as response: model_info = json.load(response)
    revision = model_info['sha']
    tree_url = api + '/tree/' + revision + '/' + VARIANT + '?recursive=true&expand=false'
    with urllib.request.urlopen(tree_url, timeout=60) as response: metadata = json.load(response)
    (HARNESS / 'model-metadata.json').write_text(json.dumps({'revision':revision,'url':tree_url,'files':metadata},indent=2))
    subprocess.run([str(binary), 'prepare', str(DATA)], check=True, env=env, timeout=3600)
    model_folder = DATA / 'models' / REPO / VARIANT
    checksums = []
    for item in metadata:
        if item.get('type') != 'file': continue
        relative = pathlib.Path(item['path']).relative_to(VARIANT)
        local = model_folder / relative
        actual = digest(local)
        expected = item.get('lfs',{}).get('oid')
        if expected and actual != expected: raise RuntimeError('Model LFS checksum mismatch: ' + str(relative))
        if not expected and item.get('oid'):
            blob = local.read_bytes()
            git_oid = hashlib.sha1(('blob ' + str(len(blob)) + '\0').encode() + blob).hexdigest()
            if git_oid != item['oid']: raise RuntimeError('Model Git blob checksum mismatch: ' + str(relative))
        checksums.append({'file':str(relative),'bytes':local.stat().st_size,'sha256':actual,'officialLFSsha256':expected,'officialGitBlobSHA1':item.get('oid')})
    fixtures = []
    comparisons = {}
    for manifest_name, result_name in [('fixtures.json','asr-results.json'),('fixtures-acceptance.json','asr-cpp-acceptance-results.json')]:
        fixture_set = json.loads((ROOT / '.benchmark' / manifest_name).read_text())
        previous = json.loads((ROOT / 'benchmarks' / result_name).read_text())
        previous_by_id = {row['id']:row for row in previous['rows']}
        for fixture in fixture_set:
            key = ('acceptance-' if manifest_name.startswith('fixtures-acceptance') else 'comparison-') + fixture['id']
            baseline = previous_by_id[fixture['id']]
            if digest(pathlib.Path(fixture['audio'])) != baseline['audioSHA256']: raise RuntimeError('WAV hash changed: ' + key)
            fixtures.append({**fixture,'id':key})
            comparisons[key] = baseline
    fixture_path = HARNESS / 'fixtures-46.json'
    fixture_path.write_text(json.dumps(fixtures,ensure_ascii=False,indent=2))
    started = time.monotonic()
    run = subprocess.run([str(binary),'batch',str(DATA),str(fixture_path)], check=False,env=env,capture_output=True,text=True,timeout=3600)
    (HARNESS / 'batch-stdout.log').write_text(run.stdout)
    (HARNESS / 'batch-stderr.log').write_text(run.stderr)
    run.check_returncode()
    # Framework diagnostics can precede JSON, whose final line is emitted by the harness.
    report = json.loads(next(line for line in reversed(run.stdout.splitlines()) if line.startswith('{') and '"rows"' in line))
    measured = {row['id']:row for row in report['rows']}
    rows = []
    for fixture in fixtures:
        row = measured[fixture['id']]; prior = comparisons[fixture['id']]
        characters = len(norm(fixture['expected']))
        error_count = edits(fixture['expected'],row['text'])
        rows.append({**row,'voice':fixture['voice'],'expected':fixture['expected'],'audioSHA256':prior['audioSHA256'],'edits':error_count,'characters':characters,'CER':error_count/max(1,characters),'terms':fixture['terms'],
            'previousLocalDictationProductionText':prior['own']['productionText'],'previousLocalDictationEdits':edits(fixture['expected'],prior['own']['productionText']),
            'previousLocalVoiceNormalizedText':prior['baseline']['text'],'previousLocalVoiceEdits':edits(fixture['expected'],prior['baseline']['text'])})
    summaries = {}
    for split in ['all'] + sorted(set(row['split'] for row in rows)):
        selected = rows if split == 'all' else [row for row in rows if row['split']==split]
        chars = sum(row['characters'] for row in selected)
        summaries[split] = {'count':len(selected),'characters':chars,'corpusCER':sum(row['edits'] for row in selected)/chars,'warmMedianSeconds':statistics.median(row['seconds'] for row in selected),
            'previousLocalDictationProductionCER':sum(row['previousLocalDictationEdits'] for row in selected)/chars,
            'previousLocalVoiceNormalizedCER':sum(row['previousLocalVoiceEdits'] for row in selected)/chars}
    result = {'kind':'actual upstream ASR service component; minimal storage/status/audio collaborators; not whole app',
        'baselineSHA':subprocess.check_output(['git','-C',str(ROOT/'.benchmark/localTypeless'),'rev-parse','HEAD'],text=True).strip(),
        'whisperKitResolved':pin,'modelVariant':VARIANT,'officialModelRevision':revision,'modelFiles':checksums,
        'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),
        'memoryBytes':int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True).strip()),
        'macOSVersion':subprocess.check_output(['sw_vers','-productVersion'],text=True).strip(),
        'modelLoadSeconds':report['loadSeconds'],'firstInferenceSeconds':report['rows'][0]['seconds'],'coldLoadPlusFirstInferenceSeconds':report['loadSeconds']+report['rows'][0]['seconds'],'processPeakRSSBytes':report['processPeakRSSBytes'],'batchWallSeconds':time.monotonic()-started,
        'decodeOptions':{'language':None,'temperature':0,'usePrefillPrompt':True,'withoutTimestamps':False,'vocabularyPrompt':None},
        'limits':['Synthetic public TTS only; human microphone acceptance remains separate.','Historical dependency version unknown: upstream has from0.13.0 and no resolved lock; measured fresh resolution recorded exactly.','Cold time means model load/prewarm in a new process, not machine reboot or cleared OS cache.','Warm times are ASR service calls after load; prior CLI times include different load boundaries and cannot establish app speed superiority.','RSS is cumulative process peak, not isolated per inference allocation.','Previous LocalVoice normalized outputs include public prompt/spelling normalizer; LocalTypeless uses its own default no-prompt options.','LLM polish, dictionary/history, injection, UI and capture are excluded.'],
        'summaries':summaries,'rows':rows}
    result = add_public_normalizer_sensitivity(result)
    output = ROOT / 'benchmarks/localtypeless-asr-results.json'
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps(summaries,ensure_ascii=False,indent=2))
if __name__ == '__main__': main()
