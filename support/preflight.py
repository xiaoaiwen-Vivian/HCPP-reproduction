"""Xiaoai: verify external inputs and Python versions before starting the build."""
from pathlib import Path
import hashlib, importlib.metadata, json, re, sys

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def main():
    package,run=map(Path,sys.argv[1:3])
    configured=dict(line.split('\t',1) for line in (run/'input_paths.tsv').read_text().splitlines())
    manifest=json.loads((package/'verification/INPUT_MANIFEST.json').read_text())
    versions={name:importlib.metadata.version(name) for name in ['numpy','pandas','openpyxl']}
    required=dict(line.split('==') for line in (package/'requirements.txt').read_text().splitlines() if line)
    records=[];errors=[]
    manifest_path=package/'MANIFEST_SHA256.json'
    if manifest_path.is_file():
        release=json.loads(manifest_path.read_text())
        for relative,wanted in release['files'].items():
            path=package/relative
            if not path.is_file() or digest(path)!=wanted:
                errors.append('Missing or modified release file: '+relative)

    for item in manifest:
        path=Path(re.sub(r'\$(\w+)',lambda m:configured[m[1]],item['configured_path']))
        got=digest(path) if path.is_file() else None
        ok=got==item['sha256']
        records.append({'input':item['configured_path'],'resolved':str(path),'sha256':got,'matches_reference':ok})
        if not ok:errors.append(f"Missing or changed source: {item['configured_path']}")
    if versions!=required:errors.append(f'Python dependencies differ: {versions}; expected {required}')
    report={'maintainer':'Xiaoai','passed':not errors,'python':sys.version,'versions':versions,'inputs':records,'errors':errors}
    (run/'preflight.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    if errors:raise SystemExit('\n'.join(errors)+'\nSee preflight.json. No old dataset is substituted.')
    (run/'preflight_passed.ok').write_text('External input hashes and Python dependencies verified.\n')
    print(f'Preflight passed: {len(records)} raw/source files. Output directory is new.')

if __name__=='__main__':main()
