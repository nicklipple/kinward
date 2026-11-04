"""Check staging rollback/exclusion using a disposable addon, never the live TOC."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load('phase1_probe', 'scripts/phase1_probe.py')
manifest = load('guardian_manifest', 'scripts/manifest.py')
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    toc = (ROOT / 'Kinward.toc').read_bytes()
    for name in ('KinwardIcon.tga', 'Kinward.toc', 'Core.lua', 'Minimap.lua', 'Settings.lua', 'Policy.lua', 'Profile.lua', 'Session.lua', 'Requests.lua', 'History.lua', 'HistoryCapture.lua', 'Protocol.lua', 'Family.lua', 'Pairing.lua', 'Transport.lua', 'WoWTransport.lua', 'Activity.lua', 'PairingPanel.lua', 'PlayerMenu.lua', 'Dashboard.lua', 'Chat.lua', 'WoWChat.lua', 'LiveTest.lua'):
        (root / name).write_bytes((ROOT / name).read_bytes())
    tool.TOC, tool.STAGED = root / 'Kinward.toc', root / 'Phase1Probe.lua'
    manifest.ROOT = manifest.ADDON = root
    manifest.validate()
    tool.toggle('install')
    try:
        manifest.validate()
    except ValueError as exc:
        assert 'Development probe staged' in str(exc)
    else:
        raise AssertionError('Staged developer probe accepted for release')
    try:
        tool.toggle('install')
    except ValueError:
        pass
    else:
        raise AssertionError('Duplicate installation accepted')
    tool.STAGED.write_text('-- local edits')
    try:
        tool.toggle('remove')
    except ValueError:
        pass
    else:
        raise AssertionError('Local probe edits discarded')
    tool.STAGED.write_bytes(tool.SOURCE.read_bytes())
    tool.toggle('remove')
    assert tool.TOC.read_bytes() == toc and not tool.STAGED.exists()
    manifest.validate()
print('ok - probe staging, conflict preservation, exact TOC restoration and package rejection')
