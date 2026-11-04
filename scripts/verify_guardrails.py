"""Deliberate temporary failures; always restore source, even on failure."""
from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
reports = ROOT / '.reports/guardrails'
reports.mkdir(parents=True, exist_ok=True)

def probe(name, path, extra, command, expected):
    original = path.read_bytes()
    try:
        path.write_bytes(original + extra.encode())
        result = subprocess.run(command, capture_output=True, text=True)
        (reports / (name + '.log')).write_text(result.stdout + result.stderr)
        assert result.returncode != 0, f'{name}: broken input unexpectedly passed'
        assert expected in result.stdout + result.stderr, f'{name}: failure did not identify {expected}'
        if command[-1] == 'scripts/lint.py':
            shutil.copyfile('.reports/luals/check.json', reports / (name + '.json'))
        print(f'{name}: correctly failed (exit {result.returncode})')
    finally:
        path.write_bytes(original)

probe('undefined-api', ROOT / 'Core.lua', '\nKinwardDefinitelyMissingAPI()\n',
      ['python3', 'scripts/lint.py'], 'undefined-global')
probe('unused-local-warning', ROOT / 'Core.lua', '\nlocal unusedKinwardProbe = 1\n',
      ['python3', 'scripts/lint.py'], 'unused-local')
probe('accidental-global', ROOT / 'Core.lua', '\nKinwardAccidentalGlobal = true\n',
      ['python3', 'scripts/lint.py'], 'global-element')
probe('invalid-field', ROOT / 'Core.lua', '\nprint(ns.missingKinwardField)\n',
      ['python3', 'scripts/lint.py'], 'undefined-field')
probe('incorrect-argument', ROOT / 'Core.lua', '\nC_AddOns.GetAddOnMetadata(true, \"Version\")\n',
      ['python3', 'scripts/lint.py'], 'param-type-mismatch')
probe('missing-toc-file', ROOT / 'Kinward.toc', 'Missing.lua\n',
      ['python3', 'scripts/manifest.py'], 'Missing.lua')
subprocess.run(['make', 'check'], check=True)
