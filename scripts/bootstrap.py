"""Pinned Linux x86_64 toolchain; downloads are verified before extraction."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
    raise SystemExit('Pinned tool binaries require Linux x86_64 (use WSL or a Linux container).')
cache = ROOT / '.tools/downloads'
cache.mkdir(parents=True, exist_ok=True)
for dep in json.loads((ROOT / 'scripts/dependencies.json').read_text()):
    archive = cache / dep['archive']
    if not archive.exists():
        temporary = archive.with_suffix('.partial')
        subprocess.run(['curl', '-L', '--fail', '--retry', '3', '-o', str(temporary), dep['url']], check=True)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != dep['sha256']:
        raise SystemExit(f"Checksum mismatch: {archive}; remove it and bootstrap again")
    dest = ROOT / dep['dest']
    dest.mkdir(parents=True, exist_ok=True)
    if archive.suffix == '.zip':
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
    else:
        with tarfile.open(archive) as t:
            for member in t.getmembers():
                if dep['strip']:
                    member.name = '/'.join(member.name.split('/')[1:])
                if member.name:
                    t.extract(member, dest, filter='data')
    print(f"Verified {dep['name']}: {dep['sha256']}", flush=True)
(ROOT / '.tools/stylua/stylua').chmod(0o755)
subprocess.run(['make', '-C', '.tools/lua', 'generic'], check=True)
subprocess.run(['.tools/lua/src/lua', '-v'], check=True)
subprocess.run(['.tools/stylua/stylua', '--version'], check=True)
subprocess.run(['.tools/luals/bin/lua-language-server', '--version'], check=True)
