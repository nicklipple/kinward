# Phase 1 result ledger

As of 2026-11-03, no live experiments have been run. Local source review and
mocked probe tests are the only evidence. This file deliberately contains no
invented client successes. See CAPABILITIES.md for the source evidence matrix.

The user confirmed on 2026-11-03 that two test accounts are unavailable.
Manual probing is deferred until the Phase 2 single-client harness is available.
That harness will provide isolated simulated parent/child endpoints for shared
logic and workflow testing; it cannot supply actual two-account chat, Battle.net
identity or live transport evidence. Keep those acceptance gates open until
real accounts become available; no additional account is required for current
pure-logic/harness development.

| Gate | Forever client result | Retail observation | Outstanding evidence |
| --- | --- | --- | --- |
| P1-IN | Untested | Untested | Ordinary incoming filter demonstration, per window/event |
| P1-OUT | Untested | Untested | Receiver confirms an actual prevented route; bypass/error/taint matrix |
| P1-ID | Untested | Untested | Two-account friendship, sender resolution, durable identity and alts |
| P1-ROUTE | Untested | Untested | Bidirectional remote receipt plus sender mapping; failures/reconnect |
| P1-SESSION | Untested | Untested | Reload/new-login flags, logout/disconnect and clocks |
| P1-LOCK | Untested | Untested | Accessible chat/identity during actual messaging lockdown |
| P1-SURFACES | Untested | Untested | Bubbles, voice, TTS and transcription exposure |

Source-supported limitation: the pinned message filter skips insecure callbacks
when arguments cannot be accessed. The outgoing probe wraps only the current
`C_ChatInfo.SendChatMessage` field; cached references and other engine/API paths
are outside its guarantee. These are scope risks, not successful live tests.

Copy this record for each run; keep Forever and Retail entries separate:

```text
Date / tester:
Client flavor / full GetBuildInfo returns / interface:
Pinned-source revision (or mismatch):
Accounts A/B (pseudonyms), realms/factions, friendship setup:
UI/addon versions and enabled addons:
Procedure ID / route / window / direction / unique marker suffix:
Combat state / messaging lockdown / addon restriction:
Probe activation and control-message receipt:
Expected result:
Observed sender counter / remote receive / visible or audible surfaces:
Raw send/registration result or sanitized exception:
Transport sender mapping and accessible identity fields:
Reload/alt/offline transition and freshly resolved handles:
Errors / taint / protected-action failures:
Outcome: verified for this exact configuration | unsupported | untested
Evidence location and remaining uncertainty:
Cleanup/reload and settings restored:
```

Acceptance remains open until P1-IN, P1-OUT and P1-ID/P1-ROUTE meet their live
gates, or a precise core blocker is observed and the resulting scope is agreed
with the user. No mocks, interface number or matching source names close them.


## Retail development loading metadata — 2026-11-03

User observed Kinward as "incompatible" in the Retail addon list while its
manifest declared only Forever `16001`. User ran `GetBuildInfo()` and reported
return 2 = `70783`, return 4 = `120105`. The shared TOC now declares
`16001, 120105`. Retail version 12.1.5 is also recorded in the local `.build.info`.
The user subsequently confirmed `/kinward` works in the Retail client after
this correction. This establishes user-observed loading/slash-command behavior
only; the simulator and live chat adapters have not yet been verified in-game.
This is Retail metadata evidence only; no Forever runtime gate is closed.


## Retail Phase 2 simulator feedback — 2026-11-03

After confirming `/kinward` loaded, the user received an in-game simulator
checklist for closed defaults, party read/send independence, second-child
isolation, duration expiry, simulated reload/login expiry, and bidirectional
character whispers. The user responded "lgtm" and reported no errors or
unexpected results. This is user-reported positive feedback on the Retail
simulator; individual outputs were not captured and Codex did not observe the
client directly. The temporary simulator was subsequently removed.

Real chat prevention, live Battle.net identity, inter-account delivery and
Forever client behavior remain unverified. Simulated login/reload commands do
not establish the actual client's session lifecycle.


## Phase 4 implementation — 2026-11-03

Shared bounded transport, receipt/application states, policy revision/deadline
handling, revision-bound snapshots and the minimal dashboard are implemented.
The network harness and mocked WoW/widget branches are covered by strict Lua
5.1 tests. No Phase 4 game-client test was performed and no two accounts became
available. The candidate `SendGameData` adapter remains inactive: sender ID
mapping, stable/local account identity, token generation, alt changes, lockdown
and actual delivery remain unverified. See PHASE4_TRANSPORT.md for activation
prerequisites and the separate one-client/two-account checklists. This entry
closes none of P1-ID, P1-ROUTE or Phase 4 live acceptance.


## Phase 5 implementation — 2026-11-03

Candidate ordinary-whisper/party adapters, fresh friendship mapping, lifecycle
handling and shared network-to-chat scenarios are implemented and exercised
with strict Lua 5.1 mocks. Core keeps live adapters inactive. No client was run,
no outbound receiver evidence was collected, and two accounts remain unavailable.
All gates above remain open. Source limitations include inaccessible incoming
callbacks being skipped and cached/secure outgoing routes bypassing a wrapper.
See PHASE5_CHAT.md for exact scope and separate fixture/client checklists.


## Phase 6 implementation — 2026-11-03

Shared durable requests, temporary approval validation, scoped policy mutation,
authorized paged polling, sender-only prompts and Requests UI are implemented.
Strict Lua 5.1 network/widget/boundary scenarios cover those branches, including
secret-body sentinels. No client was run and no two-account request, actual prompt
privacy, rendering, restricted-state or delivery result was collected. The
candidate adapters remain inactive in Core; all earlier live gates remain open.
See PHASE6_REQUESTS.md for fixture walkthrough and pending client acceptance.


## Phase 7 implementation — 2026-11-04

Shared history capture/storage, bounded authenticated catchup and a guardian-only
Activity browser are implemented. Strict Lua 5.1 network/widget/candidate-boundary
scenarios include throwing secret sentinels, real protocol batches, retention,
queued revocation and control priority. No actual client or two-account test was
performed. Core keeps live capture/transport inactive. Filter callback bypass,
restricted intervals, party self identity and engine/secure/cached send paths
remain explicit coverage gates. All earlier live gates remain open; see
PHASE7_HISTORY.md for scope, demo and pending acceptance.


## Streamlined pairing implementation — 2026-11-04

Child name requests, guardian accept/decline cards, additional-guardian approval
buttons, current-friend alias resolution and the guarded live popup branch are
covered by shared protocol/widget/adapter mocks. No actual client or two-account
pairing test was performed. Closed defaults and current-peer authorization remain
mandatory. The candidate transport is still inactive in Core; existing live
identity/routing/bootstrap gates remain open. See PAIRING.md for the new demo.
