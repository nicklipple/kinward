# Working on Guardian

- Target WoW: Forever. Verify every newly introduced WoW API against the pinned
  Forever source in `reference/blizzard-ui/` or recorded client evidence.
  Mainline annotations are analysis aids, not API availability evidence.
- Read ARCHITECTURE.md for baseline pins, source evidence and loading behavior.
  Do not substitute a Retail or Classic source baseline.
- Keep explicit TOC dependency order and use the private namespace passed through
  WoW chunk arguments. Initialize saved variables only on this addon's
  ADDON_LOADED; keep ordinary data logic independent from WoW API calls.
- Keep new globals intentional and typed. Do not suppress diagnostics, broaden
  globals or add permissive definitions just to force checks to pass.
  Evidence-backed Forever corrections go under types/forever/.
- Run `make check` before completing changes. Run `make package` for distribution
  changes. Keep runtime files at the repository root and development assets in their
  designated directories; exclude them from release archives.
- Identify behavior that still requires in-game verification. Never claim the
  game client was tested unless it actually was. Consider secret values,
  protected actions, taint and combat lockdown when relevant.
- The user has authorized development in `_retail_/Interface/AddOns/Guardian/`
  until Forever releases. This checkout is the live development addon; keep
  edits scoped to Guardian. The target API baseline remains Forever. Do not
  modify other addons or client files.
