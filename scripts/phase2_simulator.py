"""Explicitly stage/remove the development simulator in this live addon only."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'scripts/probes/Phase2Simulator.lua'
STAGED = ROOT / 'Phase2Simulator.lua'
TOC = ROOT / 'Kinward.toc'
ENTRY = '\n# Kinward phase 2 development simulator (do not release)\nPhase2Simulator.lua\n'


def toggle(action):
    toc = TOC.read_text()
    if action == 'install':
        if STAGED.exists() or ENTRY in toc or 'Phase2Simulator.lua' in toc:
            raise ValueError('Simulator already staged or conflicting TOC entry; remove it first')
        STAGED.write_bytes(SOURCE.read_bytes())
        try:
            TOC.write_text(toc + ENTRY)
        except OSError:
            STAGED.unlink()
            raise
        print('Simulator staged, inactive. Reload client; then /kinward demo for visual testing, or /kinwardsim reset.')
    elif action == 'remove':
        if ENTRY not in toc:
            raise ValueError('Exact simulator TOC marker missing; refusing to alter files')
        if STAGED.exists() and STAGED.read_bytes() != SOURCE.read_bytes():
            raise ValueError('Staged simulator has edits; preserve them before removal')
        TOC.write_text(toc.replace(ENTRY, '', 1))
        STAGED.unlink(missing_ok=True)
        print('Simulator removed. Reload client to remove hooks, slash command and taint.')
    else:
        raise ValueError('Usage: python3 scripts/phase2_simulator.py install|remove')


if __name__ == '__main__':
    try:
        toggle(sys.argv[1] if len(sys.argv) == 2 else '')
    except (ValueError, OSError) as exc:
        raise SystemExit(str(exc))
