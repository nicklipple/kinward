# Kinward architecture

Kinward targets WoW: Forever, not Classic Era. The source baseline is Gethe's
`forever` branch at `17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c`, whose
`version.txt` reads **1.60.1.70755**. On 2026-11-03 the locally installed Forever
executable's version strings and Battle.net's `wowf` build record both matched
that build. The working directory itself was a Retail client installation; this
repository lives in `_retail_/Interface/AddOns/Kinward/`, as requested for
development until Forever releases. `Kinward.toc`, `Settings.lua` and `Core.lua`
are at the repository root, so this checkout is directly discoverable by the
client. The installation root `.git` was empty/read-only; Kinward has its own
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
addons' events, then normalizes `KinwardDB`, records namespace settings and
initialization state, and unregisters the event. `/kinward` reports TOC version
and initialization state. `enabled` is a sample persisted preference; it does
not disable this diagnostic slash command.

Only `KinwardDB` (account-wide saved settings) and `SLASH_KINWARD1` are new
globals. The callback occupies `SlashCmdList.KINWARD`; no namespace global or
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
excludes development files for CurseForge packaging. The archive contains only `Kinward/`.

These checks establish scaffold logic and static consistency, not actual client
loading, saved-variable persistence across sessions or UI behavior. Secret
values, protected actions, taint and combat lockdown require real-client tests
when future functionality touches those systems. No in-game verification has
been performed.

## Phase 1 development probes

See `docs/CAPABILITIES.md` for source evidence and unsupported/inaccessible
filter states. `scripts/phase1_probe.py` explicitly stages a marker-only probe
and temporary TOC entry; it is inactive until `/kinwardprobe start`. The
manifest rejects staged probes, and `.pkgmeta` excludes probes and docs. Checks
include strict Lua 5.1 probe boundary/lifecycle tests and isolated staging tests.
These test developer tooling, not live enforcement. All runtime/client and
two-account gates remain unverified in `docs/PHASE1_RESULTS.md`.


## Phase 2 simulator

`scripts/probes/Phase2Simulator.lua` shares the production pure modules but owns
four independent fixture profiles and a bounded in-memory transport. Explicit
staging adds `/kinwardsim`; all state is closure-local and never accesses live
SavedVariables or live messaging. Fault controls and usage are documented in
[docs/PHASE2_SIMULATOR.md](docs/PHASE2_SIMULATOR.md). Staged harnesses are rejected
by the manifest and excluded by `.pkgmeta`. Lua tests reject unexpected global
reads/writes, verify state isolation, and exercise the actual slash commands.
All existing runtime globals remain intentional; the extra development-only
`SLASH_KINWARDSIM1` is typed alongside the probe slash global.


## Shared-client manifest

`Kinward.toc` uses the supported comma-delimited interface list `16001, 120105`
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
slash output; `/kinward ui` lazily constructs a visual dashboard with child selection, permission controls and family actions
from the normalized live profile. No live transport is installed on ADDON_LOADED.
New widget APIs and the candidate Battle.net route are evidenced against the
pinned Forever source in [docs/PHASE4_TRANSPORT.md](docs/PHASE4_TRANSPORT.md).
No new globals, libraries or services are introduced.

Transport's clock, friendship, routing and send boundary is injected. Production
policy operations carry absolute delivery deadlines, receipts and correlated
application revisions. Child revisions/replay entries persist; work, reassembly,
contacts and partially collected snapshots are transient. Kinward caches are
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
The explicitly staged harness supplies `/kinward demo`, endpoint switching,
automatic fixture-clock advancement and outage controls. Its frame driver is
created only on explicit demo activation and never obtains live SavedVariables
or messaging. Additional widget APIs are pinned in PHASE4_TRANSPORT.md. No actual
in-game rendering or protected-state verification is claimed by mock tests.


## Phase 5 candidate chat boundaries

The TOC loads `Chat.lua` and `WoWChat.lua` after Dashboard, before Settings/Core.
Chat is pure metadata-only policy/deduplication logic. WoWChat declares a gated
factory and current friend resolver; neither is called at load or by Core.
A future verified bootstrap must install after own-ADDON_LOADED normalization,
before supported chat, with accepted boundary/identity/lifecycle inputs. No live
send wrapper or filter is active in this checkout. Candidate filters cover
ordinary whispers/party; candidate outgoing interception covers current ordinary
WHISPER/PARTY send calls. Reload/session logic fails closed for unresolved
session grants, while clocks, mappings and current policy are reevaluated.

The staged network harness gives each independent endpoint a Chat instance;
commands never obtain live SavedVariables or chat APIs. Strict adapter tests use
sentinel secret values and actual TOC initialization tests ensure loading remains
inert. New APIs are evidenced in [Phase 5 contracts](docs/PHASE5_CHAT.md), along
with bounded caches, attempt/output distinctions and pending client checklists.
No new globals, libraries or profile schema version are introduced. The known
secret-filter bypass, cached/engine sends, taint and other surfaces prevent a
claim of global enforcement. Client and two-account acceptance remain open.


## Phase 6 requests and approvals

`Requests.lua` loads after Session and before Protocol. It declares pure request
validation, bounded persistence, expiry/cancellation, inbox page handling and
sender-only prompt logic. Profile normalization calls its validators only after
all modules load, on own ADDON_LOADED as before. Family gates request operations
by current verified guardian/generation and durable replay. Approvals delegate to
the existing policy mutation/revision path; duration begins on child application,
while session/base-revision/freshness/deadline checks reject stale decisions.

The dashboard adds Requests for both roles and retains Connection for diagnostic
traffic. Its optional Chat argument binds fixture/live prompt metadata explicitly;
no simulator model obtains `ns.settings` or live chat. The candidate WoW filter
reports only accessible sender identity, with a default safe notification or an
injected prompt callback for a future verified bootstrap. No new WoW APIs,
globals, runtime libraries or profile schema version are introduced. Existing
widget API evidence applies; real rendering/privacy, taint, actual transport and
session/chat enforcement remain client gates. [Phase 6 contracts](docs/PHASE6_REQUESTS.md)
document wire fields, persistent/transient state, polls, UI and acceptance.


## Phase 7 history and Activity

`History.lua` and `HistoryCapture.lua` load after Requests, before Protocol;
`Activity.lua` loads before Dashboard. They declare pure storage/capture/delivery
helpers and a lazy widget factory. Profile normalization validates optional
source and per-child cache history; Core prunes age-limited data only after its
own ADDON_LOADED. No live adapter activation was added. Candidate WoWChat capture
checks accessibility before forwarding text to pure logic, and explicitly
requires verified local identity for party self-echo classification. Source gaps,
retention/count loss, send attempts and observed output remain distinct.

Current guardians fetch bounded cursor batches through the existing authenticated
transport. History jobs have reserved bounds and run after control/request work;
queued replies recheck authorization before every fragment. Kinward cursors and
received data persist; pending correlations/watchers/delivery are transient.
Membership generation changes reset guardian views; stop/re-pair clears source
history. The Activity viewer is guardian-only and never feeds child/debug widgets.
Its separate closure stays within Lua 5.1's sixty-upvalue limit. The new date
formatter has pinned Forever source evidence in [Phase 7 contracts](docs/PHASE7_HISTORY.md).
All actual client capture/privacy/taint/delivery coverage remains unverified.


## Name-based guardianship requests

`Pairing.lua` loads after Family and before Transport; `PairingPanel.lua` loads
before Dashboard. Their functions are inert until explicitly called. Children
request a resolved verified friend and guardians accept/decline a token-bound
inbox card. First acceptance reuses atomic closed-default Family confirmation;
additional guardians require the existing authorized add operation with a fetched
candidate, then automatic sync. The short-code engine remains for old fixtures,
while its manual code/operation inputs have been removed from the normal UI.

The candidate adapter resolves current verified friend aliases and rejects
ambiguity/incomplete records. New inbound requests notify/focus Family only for
the verified live profile, reusing its existing dashboard; no simulator profile
can open a live pairing window. The UI previews the resolved account and checks
it again at the request click. No new WoW API, global or randomness source was
added. The existing token supplier's live guarantees and P1-ID/P1-ROUTE bootstrap
remain unverified. A validated optional receipt persists a successful acceptance
for retry/reload; pending proposals/inboxes remain transient and bounded. See
[handshake contracts](docs/PAIRING.md).


## Minimap launcher

`Minimap.lua` loads before Core and declares an idempotent installer. Own
ADDON_LOADED initializes settings, then creates one anonymous shield button
parented to the existing Minimap; if the map is not available yet, Core retries
on PLAYER_LOGIN. The button's left click and `/kinward ui` share OpenDashboard,
reusing the same live local model without selecting or creating simulator state.
Hover shows a simple tooltip. The launcher adds no globals, saved fields or
runtime dependencies and does not activate chat or transport.

Evidence is in the pinned Forever source (Gethe
17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c), relative to
reference/blizzard-ui/Interface/AddOns/:

- Blizzard_Minimap/Blizzard_Minimap.toc and Mainline/Minimap.xml declare the
  Minimap and tooltip dependency; Camelot/Minimap.lua uses frame levels.
- Blizzard_APIDocumentationGenerated/SimpleButtonAPIDocumentation.lua declares
  RegisterForClicks, SetNormalTexture and SetHighlightTexture;
  SimpleFrameAPIDocumentation.lua declares GetFrameLevel/SetFrameLevel. Existing
  frame/texture sizing, anchoring, creation and script methods retain Phase 4 evidence.
- Blizzard_Minimap/Shared/ExternalEventURLMinimapButton.xml supplies RingBorder;
  Mainline/Minimap.xml supplies UI-Minimap-ZoomButton-Highlight.
  Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua uses
  Interface/AchievementFrame/UI-Achievement-TinyShield.
- Blizzard_Minimap/Shared/ExternalEventURLMinimapButton.lua uses GameTooltip
  SetOwner/SetText/Show; tooltip Hide uses the existing frame API.
  PLAYER_LOGIN has the earlier SystemDocumentation.lua lifecycle evidence.

Strict initialization tests cover delayed minimap creation, own-addon isolation,
launcher idempotence, tooltip callbacks and shared dashboard identity with the
slash command. Checks/package pass; actual placement, rendering and alternative
minimap UI compatibility still need in-game observation. No game client was run.


## Custom minimap icon and dragging

The launcher uses the packaged root texture `KinwardIcon.tga` (64 × 64 RGBA,
uncompressed). Generation provenance and source art live in `docs/art/` and are
excluded from releases. The package manifest explicitly validates/includes the
texture without treating it as executable TOC content.

Holding the left button and dragging moves the launcher around a 92 UI-unit
radius. Cursor coordinates are divided by the minimap effective scale before
subtracting its center. The optional `minimapAngle` setting stores radians on
drag stop; nonnumeric/nonfinite saved values use the original lower-left default.
Only an active drag installs OnUpdate; stopping/hiding removes it. A drag release
does not open the dashboard.

New API evidence against the pinned Forever source, relative to
`reference/blizzard-ui/Interface/AddOns/`:

- `Blizzard_SharedXML/SharedBasicControls.xml`, `TitleDragAreaTemplate`:
  `RegisterForDrag("LeftButton")`, `OnDragStart`, `OnDragStop`.
- `Blizzard_Minimap/Mainline/Minimap.lua`, cursor handling: `GetCursorPosition`,
  `GetEffectiveScale`, `GetCenter`.
- `Blizzard_SharedXML/Blizzard_RadialWheel.lua`: `math.atan2`, `math.sin`, `math.cos`.
- `Blizzard_Minimap/Mainline/Minimap.lua`: `ClearAllPoints`
  (also used throughout the pinned UI).

Tests cover drag/click separation, cursor scaling, saved position restoration,
invalid settings and drag cleanup. Actual texture loading and mouse behavior
(including combat and minimap replacements) require in-game verification.
