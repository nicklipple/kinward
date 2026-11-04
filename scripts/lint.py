"""LuaLS exit codes alone do not enforce our zero-diagnostic policy."""
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
report = ROOT / '.reports/luals'
if report.exists():
    shutil.rmtree(report)
report.mkdir(parents=True)
command = [str(ROOT / '.tools/luals/bin/lua-language-server'), '--check=' + str(ROOT),
           '--configpath=' + str(ROOT / '.luarc.json'), '--checklevel=Hint',
           '--check_format=json', '--check_out_path=' + str(report / 'check.json'), '--logpath=' + str(report / 'logs')]
with (report / 'stdout.log').open('w') as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
print(f'LuaLS process exit: {result.returncode}')
path = report / 'check.json'
if not path.is_file():
    raise SystemExit('LuaLS did not produce a fresh check.json; see .reports/luals/stdout.log')
try:
    data = json.loads(path.read_text())
except (ValueError, OSError) as exc:
    raise SystemExit(f'Invalid LuaLS report: {exc}')
if data == []:
    data = {}
if not isinstance(data, dict) or any(not isinstance(v, list) for v in data.values()):
    raise SystemExit('Unexpected LuaLS report schema')
count = 0
for file, diagnostics in data.items():
    for diagnostic in diagnostics:
        count += 1
        print(f"{file}: {diagnostic.get('code')}: {diagnostic.get('message')}")
if result.returncode or count:
    raise SystemExit(f'LuaLS failed: {count} diagnostics (policy: zero, including hints)')
print('LuaLS: zero diagnostics')
