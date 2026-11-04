"""Validate exact paths and package only the transitive runtime manifest."""
from pathlib import Path, PurePosixPath
import re
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT
DEV_DIRS = {'.git', '.github', '.tools', '.reports', 'dist', 'tests', 'types', 'reference', 'scripts', 'docs'}

def validate():
    if (ROOT / 'Phase1Probe.lua').exists() or 'Phase1Probe.lua' in (ROOT / 'Guardian.toc').read_text():
        raise ValueError('Development probe staged; run python3 scripts/phase1_probe.py remove before checking/packaging')
    if (ROOT / 'Phase2Simulator.lua').exists() or 'Phase2Simulator.lua' in (ROOT / 'Guardian.toc').read_text():
        raise ValueError('Development simulator staged; run python3 scripts/phase2_simulator.py remove before checking/packaging')
    seen = set()
    files = ['Guardian.toc']
    def include(raw, parent):
        raw = raw.replace('\\', '/')
        rel = parent / PurePosixPath(raw)
        if rel.is_absolute() or '..' in rel.parts or rel.suffix.lower() not in ('.lua', '.xml'):
            raise ValueError(f'Invalid runtime path: {rel}')
        if rel.parts[0] in DEV_DIRS:
            raise ValueError(f'Development file in runtime manifest: {rel}')
        key = str(rel).casefold()
        if key in seen:
            raise ValueError(f'Duplicate runtime entry: {rel}')
        seen.add(key)
        current = ADDON
        for part in rel.parts:
            if not current.is_dir() or part not in [p.name for p in current.iterdir()]:
                raise ValueError(f'Missing file or wrong casing: {rel}')
            current = current / part
            if current.is_symlink():
                raise ValueError(f'Symlink forbidden: {rel}')
        if not current.is_file():
            raise ValueError(f'Not a file: {rel}')
        files.append(str(rel))
        if rel.suffix.lower() == '.xml':
            for element in ET.parse(current).iter():
                if element.tag.rsplit('}', 1)[-1] in ('Include', 'Script') and 'file' in element.attrib:
                    include(element.attrib['file'], rel.parent)
    toc = (ADDON / 'Guardian.toc').read_text()
    for key, value in [('Interface', '16001, 120105'), ('SavedVariables', 'GuardianDB')]:
        if re.findall(r'^## ' + key + r':\s*(.+)$', toc, re.M) != [value]:
            raise ValueError(f'Expected one {key}: {value}')
    for line in toc.splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            include(line, PurePosixPath())
    actual = set()
    for directory, dirs, names in os.walk(ADDON):
        if Path(directory) == ADDON:
            dirs[:] = [name for name in dirs if name not in DEV_DIRS]
        for name in names:
            path = Path(directory) / name
            if path.suffix.lower() in ('.lua', '.xml', '.toc'):
                actual.add(str(path.relative_to(ADDON)))
    if actual != set(files):
        raise ValueError(f'Unmanifested runtime files: {sorted(actual - set(files))}')
    return files

if __name__ == '__main__':
    try:
        files = validate()
        print(f'Manifest valid: {len(files)} runtime files')
        if '--package' in sys.argv:
            version = re.search(r'^## Version: ([\w.-]+)$', (ADDON / 'Guardian.toc').read_text(), re.M).group(1)
            target = ROOT / 'dist' / f'Guardian-{version}.zip'
            target.parent.mkdir(exist_ok=True)
            with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
                for name in files:
                    info = zipfile.ZipInfo('Guardian/' + name, date_time=(2026, 1, 1, 0, 0, 0))
                    info.external_attr = 0o100644 << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    z.writestr(info, (ADDON / name).read_bytes())
            with zipfile.ZipFile(target) as z:
                assert z.namelist() == ['Guardian/' + f for f in files]
                assert z.testzip() is None
            print(target.relative_to(ROOT))
    except (ValueError, OSError, ET.ParseError) as exc:
        raise SystemExit(f'Manifest validation failed: {exc}')
