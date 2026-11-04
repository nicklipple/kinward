# Guardian architecture

Guardian targets WoW: Forever, not Classic Era. The source baseline is Gethe's
`forever` branch at `17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c`, whose
`version.txt` reads **1.60.1.70755**. On 2026-11-03 the locally installed Forever
executable's version strings and Battle.net's `wowf` build record both matched
that build. The working directory itself was a Retail client installation; this
repository lives in `_retail_/Interface/AddOns/Guardian/`, as requested for
development until Forever releases. `Guardian.toc`, `Settings.lua` and `Core.lua`
are at the repository root, so this checkout is directly discoverable by the
client. The installation root `.git` was empty/read-only; Guardian has its own
repository. Other addons and client files are untouched. This location does not
change the Forever API baseline or establish Retail compatibility.

The shared manifest declares **16001, 120105**. Forever **16001** is corroborated by installed Forever manifests
(`EnhanceQoLCooldownPulse_Camelot.toc`, `AtlasBIStooltips.toc` and
`SpokenAll.toc`). The user reported Retail build **70783** and interface **120105** from
`GetBuildInfo()` on 2026-11-03. This supplies the Retail development loading number;
it does not verify runtime behavior or replace the Forever source baseline.
Forever's running-client interface return and loading behavior remain unverified. Confirm with `/dump GetBuildInfo()` in Forever; the fourth
return must be 16001. Do not infer it from Mainline's version number.

## Pinned development baseline and provenance

Inspected upstream documentation and GitHub branch listings on 2026-11-03:

- [Gethe README](https://github.com/Gethe/wow-ui-source): branches track each
  client. The available branches included `forever`, `live`, `beta`, `ptr`,
  `ptr2`, and several Classic branches. Explicitly selected `forever`.
- [Forever commit](https://github.com/Gethe/wow-ui-source/tree/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c)
  is extracted only into ignored `reference/blizzard-ui/` for searching.
- [Ketho README](https://github.com/Ketho/vscode-wow-api) and
  [setup documentation](https://github.com/Ketho/vscode-wow-api/blob/d0b5b51fac4c52c493371b9b18e66ce604ea4326/setup/README.md):
  pre-generated annotations are available; regeneration is unnecessary.
  Branches included `master`, `esbuild`, and dependency update branches, with
  no Forever flavor branch. Selected `master` commit
  `d0b5b51fac4c52c493371b9b18e66ce604ea4326` as an **analysis aid**.
- Its `.gitmodules` requires `Annotations/FrameXML`. The pinned gitlink is
  NumyAddon/FramexmlAnnotations `2ffc9177b0e55a8a3f51baf47c2cfb0f54f685ee`.
  Bootstrap extracts that exact submodule revision, not its moving branch.
- LuaLS **3.19.2**, StyLua **2.6.0**, and stock Lua **5.1.5** are pinned.
  `scripts/dependencies.json` records immutable URLs and SHA-256 digests for all
  archives. Binary tools target Linux x86_64; Lua is compiled locally.

LuaLS loads Ketho Core's WoW Lua environment, widgets, types, Mainline generated
API annotations and supporting definitions. `Data/Classic.lua` is excluded.
Only the FrameXML slash registry is selected from the submodule. The full UI
reference is never used as a definition library. New Forever corrections belong
in `types/forever/` with symbol/path evidence; the Phase 1 filter namespace correction is recorded in
`types/forever/ChatFrameUtil.lua` against the pinned filter implementation.
Annotations may contain APIs unavailable in Forever: every new runtime API must
be independently verified against the pinned Forever source or actual client.

## Loading, ownership and boundaries

The TOC explicitly loads `Policy.lua`, `Profile.lua`, `Session.lua`,
`Protocol.lua`, `Family.lua`, `Settings.lua`, then `Core.lua`, using WoW's private chunk namespace. The first
five modules expose pure functions; Profile calls Policy's character-key helper
only during normalization, after all modules have loaded. Settings records the
schema version. See [docs/PROFILE_SCHEMA.md](docs/PROFILE_SCHEMA.md) for migration,
recovery behavior, identity and expiry contracts. No live session/identity/chat
adapter is installed in Phase 2.

`Core.lua` owns the narrow WoW boundary: an anonymous frame, `ADDON_LOADED`,
`C_AddOns.GetAddOnMetadata`, the slash registry and chat output via `print`.
It does not read saved variables until its own `ADDON_LOADED`, ignores other
addons' events, then normalizes `GuardianDB`, records namespace settings and
initialization state, and unregisters the event. `/guardian` reports TOC version
and initialization state. `enabled` is a sample persisted preference; it does
not disable this diagnostic slash command.

Only `GuardianDB` (account-wide saved settings) and `SLASH_GUARDIAN1` are new
globals. The callback occupies `SlashCmdList.GUARDIAN`; no namespace global or
runtime framework is introduced. Addon-owned types live in `types/addon.lua`.

Evidence in the pinned Forever reference (relative to `reference/blizzard-ui/`):

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua`:
  `GetAddOnMetadata` and `ADDON_LOADED`/`addOnName`.
- `Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommandsRegistry.lua`:
  global slash registry and `SLASH_...1` convention; its TOC loads the registry.
- `Interface/AddOns/Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua`:
  frame construction and event integration in the shared UI.
- `Interface/AddOns/Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua`:
  registering and handling `ADDON_LOADED`.
- `Interface/AddOns/Blizzard_TutorialManager/Blizzard_TutorialBase.lua`:
  `print(string.format(...))` output.
- `Interface/AddOns/Blizzard_BattlefieldMap/Mainline/Blizzard_BattlefieldMap.lua`:
  registration, addon-name filtering and unregistration of `ADDON_LOADED`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/BuildDocumentation.lua`:
  `GetBuildInfo` return order, including `interfaceVersion`.

## What checks establish

`make check` verifies Lua 5.1 formatting, LuaLS diagnostics for runtime source,
manifest paths/casing/uniqueness/completeness, and strict Lua 5.1 initialization, policy and simulator tests.
Tests execute the actual TOC's Lua order and loading arguments, mocking only
used WoW calls. Unknown global/API reads fail. Tests are checked by execution
rather than loading standalone Lua facilities into the WoW analysis environment.
All diagnostics, including warnings and hints, fail lint. Every run recreates
`.reports/luals/`, requires a valid JSON report, and checks the tool exit code.
The pinned LuaLS emits an empty JSON array and exits 0 for success; nonempty
results map file URIs to diagnostics. Probes confirmed it exits 1 for an
undefined API and for an unused-local warning. The runner also enforces the
report policy independently. Logs in `.reports/guardrails/` record rejection of
undefined APIs, warnings, accidental globals, invalid fields, incorrect argument
types and missing TOC files; all temporary changes were restored.

`make package` runs checks and builds a deterministic zip from validated runtime
files only. XML Script/Include dependencies are recursively validated if added;
unlisted runtime files and symlinks are rejected. Known development directories
are excluded from runtime discovery and forbidden in the TOC. `.pkgmeta` also
excludes development files for CurseForge packaging. The archive contains only `Guardian/`.

These checks establish scaffold logic and static consistency, not actual client
loading, saved-variable persistence across sessions or UI behavior. Secret
values, protected actions, taint and combat lockdown require real-client tests
when future functionality touches those systems. No in-game verification has
been performed.

## Phase 1 development probes

See `docs/CAPABILITIES.md` for source evidence and unsupported/inaccessible
filter states. `scripts/phase1_probe.py` explicitly stages a marker-only probe
and temporary TOC entry; it is inactive until `/guardianprobe start`. The
manifest rejects staged probes, and `.pkgmeta` excludes probes and docs. Checks
include strict Lua 5.1 probe boundary/lifecycle tests and isolated staging tests.
These test developer tooling, not live enforcement. All runtime/client and
two-account gates remain unverified in `docs/PHASE1_RESULTS.md`.


## Phase 2 simulator

`scripts/probes/Phase2Simulator.lua` shares the production pure modules but owns
four independent fixture profiles and a bounded in-memory transport. Explicit
staging adds `/guardiansim`; all state is closure-local and never accesses live
SavedVariables or live messaging. Fault controls and usage are documented in
[docs/PHASE2_SIMULATOR.md](docs/PHASE2_SIMULATOR.md). Staged harnesses are rejected
by the manifest and excluded by `.pkgmeta`. Lua tests reject unexpected global
reads/writes, verify state isolation, and exercise the actual slash commands.
All existing runtime globals remain intentional; the extra development-only
`SLASH_GUARDIANSIM1` is typed alongside the probe slash global.


## Shared-client manifest

`Guardian.toc` uses the supported comma-delimited interface list `16001, 120105`
to load the same files on Forever and the user's Retail development client.
Manifest checks pin both exact values and preserve runtime completeness; both
local zip and CurseForge packages retain this single manifest. The TOC list is
loading metadata, not proof of working chat enforcement or cross-client API
coverage. Future adapters still need separate client evidence.

Primary tool-author reference: [TOC Interface Updater multi-client support](https://github.com/p3lim/toc-interface-updater#flavor).
CurseForge's [flavor-tagging instructions](https://support.curseforge.com/support/solutions/articles/9000209856)
explain that uploaded releases also need version tags; TOC metadata alone does
not set the website's advertised supported versions. No upload was performed.


## Phase 3 family authorization

`Protocol.lua` provides bounded versioned wire decoding; `Family.lua` owns pure
pairing/membership operations, confirmed reset, persisted replay protection and
correlated replies. Membership changes rotate a fresh injected relationship
generation. Profile schema 1 gains additive bounded replay, sender-sequence and
per-child guardian records; malformed authority state enters recovery. No new
WoW globals/APIs or live transport have been added. All peer identity, friendship,
clock, randomness and generation uniqueness guarantees must come from a verified
adapter. [Protocol contracts and simulator commands](docs/PHASE3_PROTOCOL.md)
describe these boundaries and remaining client gates. The existing staged
harness can start unpaired endpoints with `family-reset`. History authorization
is tested; capture and record delivery remain Phase 7. No Phase 3 live-client
verification is claimed.


## Phase 4 transport and dashboard

The explicit runtime order now places `Transport.lua`, `WoWTransport.lua` and
`Dashboard.lua` after `Family.lua`, before Settings/Core. These modules declare
functions without making WoW calls at load. Core retains its original diagnostic
slash output; `/guardian ui` lazily constructs a visual dashboard with child selection, permission controls and family actions
from the normalized live profile. No live transport is installed on ADDON_LOADED.
New widget APIs and the candidate Battle.net route are evidenced against the
pinned Forever source in [docs/PHASE4_TRANSPORT.md](docs/PHASE4_TRANSPORT.md).
No new globals, libraries or services are introduced.

Transport's clock, friendship, routing and send boundary is injected. Production
policy operations carry absolute delivery deadlines, receipts and correlated
application revisions. Child revisions/replay entries persist; work, reassembly,
contacts and partially collected snapshots are transient. Guardian caches are
bounded and validated during normalization. The staged Phase 2 harness adds a
separate Phase 4 network model using the production transport, including reply
loss/delay, receipts, independent dashboards and clock control. It never obtains
live settings, identity, transport or SavedVariables.

`NewWoWTransport` returns before any API call unless recorded routing acceptance
is provided. The candidate enumerates trusted Battle.net friendships and freshly
resolved same-project game handles, discards ambiguous/inaccessible identity,
handles numeric send failures and polls known children. The precise event sender
mapping, local identity bootstrap and fresh tokens remain Phase 1 gates. This
adapter is deliberately not reachable from a slash override. Twenty-three strict
Phase 4 tests cover the shared flow and mocked adapter/widget boundaries. They do
not establish live delivery, actual widgets, lockdown, taint or chat enforcement.


The visual dashboard keeps one frame per model and captures exact targets for
confirmation. Button actions pass separate arguments to production logic,
including spaced realm names. Read/send states and delivery states are separate;
whisper grants remain bidirectional. Slash commands remain diagnostic tooling.
The explicitly staged harness supplies `/guardian demo`, endpoint switching,
automatic fixture-clock advancement and outage controls. Its frame driver is
created only on explicit demo activation and never obtains live SavedVariables
or messaging. Additional widget APIs are pinned in PHASE4_TRANSPORT.md. No actual
in-game rendering or protected-state verification is claimed by mock tests.
