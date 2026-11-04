"""Explicitly stage/remove the development probe in this live addon only."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'scripts/probes/Phase1Probe.lua'
STAGED = ROOT / 'Phase1Probe.lua'
TOC = ROOT / 'Kinward.toc'
ENTRY = '\n# Kinward phase 1 development probe (do not release)\nPhase1Probe.lua\n'


def toggle(action):
    toc = TOC.read_text()
    if action == 'install':
        if STAGED.exists() or ENTRY in toc or 'Phase1Probe.lua' in toc:
            raise ValueError('Probe already staged or conflicting TOC entry; remove it first')
        STAGED.write_bytes(SOURCE.read_bytes())
        try:
            TOC.write_text(toc + ENTRY)
        except OSError:
            STAGED.unlink()
            raise
        print('Probe staged, inactive. Reload client; then /kinwardprobe start.')
    elif action == 'remove':
        if ENTRY not in toc:
            raise ValueError('Exact probe TOC marker missing; refusing to alter files')
        if STAGED.exists() and STAGED.read_bytes() != SOURCE.read_bytes():
            raise ValueError('Staged probe has edits; preserve them before removal')
        TOC.write_text(toc.replace(ENTRY, '', 1))
        STAGED.unlink(missing_ok=True)
        print('Probe removed. Reload client to remove hooks, slash command and taint.')
    else:
        raise ValueError('Usage: python3 scripts/phase1_probe.py install|remove')


if __name__ == '__main__':
    try:
        toggle(sys.argv[1] if len(sys.argv) == 2 else '')
    except (ValueError, OSError) as exc:
        raise SystemExit(str(exc))
