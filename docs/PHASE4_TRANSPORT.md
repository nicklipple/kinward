# Phase 4 transport and dashboard

Current user-facing pairing is [name request and one-click acceptance](PAIRING.md).
Older code/operation-entry procedures below remain diagnostic regression fixtures;
the normal Family UI no longer requires them.

Implementation status: shared transport, synchronization, dashboard and isolated
network simulation are implemented. **Phase 4 live acceptance remains open.**
No actual client, two-account delivery, alt transition, widget rendering, taint
or lockdown experiment was run by the implementation agent.

The plan explicitly requires the route verified in Phase 1. P1-ID/P1-ROUTE are
still unverified and two test accounts are unavailable. Consequently Core does
not activate the candidate WoW adapter. `/kinward ui` opens a local dashboard;
`/kinward role guardian` or `role child` saves a role only while unpaired without
children. The window has a child selector, role buttons and Permissions, Family
& pairing, Requests, Activity, and Connection tabs. Read/send rows have separate Allow/Block controls
and colored saved/pending/delivered states. Whisper controls specify a character
or account target and clearly apply bidirectionally. Family provides peer/code
fields, pairing and sync buttons, exact pending-peer confirmation, additional
guardian approval and membership removal. Destructive actions require a second
confirmation bound to the original child and peer. Connection retains detailed
acknowledgements, deadlines and last-contact evidence. Unavailable live actions
are disabled. The command interface remains available through slash commands;
ordinary use of the visual window requires no console commands.

A future verified bootstrap must provide `NewWoWTransport` with an authenticated
local account ID, a fresh alphanumeric/hyphen instance ID (at most 36 characters)
and recorded route acceptance. The family's fresh-token supplier must also meet
Phase 3's uniqueness requirements. Random generation and local BattleTag
bootstrap remain client gates; synthetic fixtures never supply live credentials.
There is deliberately no slash-command override for this gate. The `verified`
argument is an integration contract, not authentication or a security boundary
against local addon modification. Once those inputs are verified, bind the
returned transport to `NewDashboard(profile, transport, GetServerTime)` and use
its stop callback on adapter teardown. False returns before any WoW API call.

## Candidate WoW route and source evidence

All paths below are relative to `reference/blizzard-ui/Interface/AddOns/` at the
pinned Forever commit recorded in ARCHITECTURE.md; Mainline annotations are not
availability evidence.

- `Blizzard_APIDocumentationGenerated/BattleNetDocumentation.lua`:
  `GetFriendAccountInfo`, `GetFriendNumGameAccounts`,
  `GetFriendGameAccountInfo`, `SendGameData`, `BNetAccountInfo` and
  `BNetGameAccountInfo`. The candidate durable peer key is the exact BattleTag
  returned for a current friend. Its stability must be confirmed in-client;
  friendship, renamed tags and unavailable identity never infer a replacement.
- `Blizzard_FriendsFrame/Camelot/FriendsFrame.lua` uses `BNGetNumFriends()` and
  compares `wowProjectID` with `WOW_PROJECT_ID`. The adapter enumerates up to 200
  friends/32 games each. It resolves only online WoW games for this project.
  It enumerates again for every send/receive, without persisting handles. Two
  eligible games or conflicting ownership leave the peer unresolved.
- `Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua` documents
  `BN_CHAT_MSG_ADDON(prefix, text, channel, senderID)`, prefix registration and
  messaging restriction functions. **Whether senderID equals the enumerated
  gameAccountID remains unverified.** The adapter requires that mapping; it has
  no payload/character/account-handle fallback. A mismatch blocks activation
  until a tested mapping replaces this candidate.
- `ChatConstantsDocumentation.lua` in the same generated directory: prefix
  success 0/duplicate 1; send success 0, throttles 3/8, lockdown 11, offline 12.
  Success means attempted transmission, never remote receipt or application.
- `FrameScriptDocumentation.lua`: `canaccessvalue`. Inaccessible prefix, bytes,
  sender ID or inspected identity fields are discarded before using them.
  `SystemTimeDocumentation.lua`: `GetServerTime` for absolute deadlines.
- The generated `SimpleFrameAPIDocumentation`, `SimpleScriptRegionAPIDocumentation`,
  `SimpleScriptRegionResizingAPIDocumentation`, `SimpleTextureBaseAPIDocumentation`,
  `SimpleFontStringAPIDocumentation`, `SimpleScrollFrameAPIDocumentation`,
  `SimpleButtonAPIDocumentation` and `SimpleEditBoxAPIDocumentation` files document
  the widget construction, sizing, texture, text, focus, scroll-child and script
  methods used in Dashboard.lua. The visual controls additionally use
  `SimpleButtonAPIDocumentation.lua:SetEnabled` and
  `SimpleFontStringAPIDocumentation.lua:SetTextColor`; both are present in the
  same pinned Forever source. `OnTextChanged` updates field validation, while
  `OnShow` refreshes the retained per-model window.
- `Blizzard_SharedXML/Blizzard_SharedXML.toc` loads `SecureScrollTemplates.xml`,
  `[Family]/SharedUIPanelTemplates.xml` and `Shared/InputBox/InputBoxTemplates.xml`;
  these define `UIPanelScrollFrameTemplate`, `UIPanelButtonTemplate` and
  `InputBoxTemplate`. `Blizzard_Fonts_Shared/Shared/FontStyles.xml` defines
  `GameFontNormal`. Source presence does not verify client rendering/loading.

No character whisper fallback, external service or offline server is assumed.
The live adapter polls current known children every 20 seconds, refreshing
membership/generation/revision and fetching a policy snapshot when needed.
Actual alt routing, friendship loss and messaging restrictions remain test gates.

## Transport and synchronization contracts

`Transport.lua` is pure. Its clock, trusted friendship map, peer resolution and
send function are injected. The same module drives the staged network harness.

- The version 1 family envelope is carried in `F|ID|INDEX|TOTAL|PAYLOAD` frames.
  Payloads are at most 180 bytes, IDs at most 48 characters, and packets at most
  240 bytes. At most 12 fragments/2048 reconstructed bytes, 32 concurrent
  assemblies, 15-second assembly lifetime, 64 accepted inbound frames/second,
  64 queued/status operations and one outbound packet per 0.15 seconds bound
  work. Caller instance IDs must be fresh across transport reconstruction.
- `D|ID` is an authenticated peer receipt. UI state starts **pending**, changes to
  **delivered** only on receipt, and to **applied** only on a correlated successful
  family reply. An application reply can arrive without its receipt. Rejections,
  cancellation and expiry are separate terminal states. Pair receipt normally
  reports `confirmation-required`; supervision begins only after confirmation
  and a subsequent authorized sync.
- Retries resend identical wire bytes and operation IDs, with 2/4/8/16-second
  acknowledgement backoff. Throttles wait two seconds; other send restrictions
  wait five. Unresolved routes are retried after two seconds. Replies share the
  global budget and receive priority. Lost replies cause request retransmission;
  the child's durable replay ledger returns the original result/revision.
- Dashboard commands have a 60-second absolute delivery deadline, shown in the
  UI. The API permits at most 300 seconds. Live policy requests require the
  deadline field; the child checks it before a new write. A timed-out command
  is not automatically recreated on reconnect. Clock skew can reject a command;
  no deadline extension or duration restart is inferred from reconnect.
- The child increments a persisted global policy revision once per newly accepted
  setting write. It patches only that channel/direction or bidirectional whisper
  target. Distinct guardians' writes are ordered by child acceptance. A retry
  never becomes another write. Reordered same-setting operations follow actual
  acceptance order, not guardian clock or send order. Revisions are returned in
  acknowledgements and preserved with replay entries across reload.
- Authorized sync returns current generation, revision and guardian membership.
  Sequential `snapshot` pages are bound to generation/revision; changes between
  pages invalidate the fetch. The receiver installs a completed snapshot
  atomically. At most 128 entries are fetched; larger profiles explicitly report
  `snapshot-truncated`. `inspect` fetches one setting, including a revocation;
  old views cannot replace a known newer revision. Membership changes invalidate
  queued old-generation writes. Snapshot/setting replies recheck authority before
  sending, so revocation cancels unsent content.
- Queues and presence are transient. Reload retains accepted policy, revision,
  sender sequences and replay state; it discards unacknowledged local commands.
  Sync reconciles actual saved child state after reconnect. No hidden automatic
  resend across reload is promised.
- Presence is **responding** for 30 seconds after an accepted authenticated
  exchange and **unreachable** otherwise. Last contact is shown while the addon
  runs. Unreachable makes no claim about offline status or addon installation.
  Saved policy is retained through transport loss; real enforcement is Phase 5
  and still unverified.

## One-client walkthrough

Stage the existing development harness (kept out of all packages):

```sh
python3 scripts/phase2_simulator.py install
```

Reload the game and run:

```text
/kinwardsim network-reset
/kinwardsim network child invite parent 12345678
/kinwardsim network parent pair child 12345678
/kinwardsim network-pump 2
/kinwardsim network-status child
/kinwardsim network child confirm parent parent:1 confirm
/kinwardsim network parent sync child
/kinwardsim network-pump 4
/kinwardsim network-ui parent
/kinwardsim network-ui child
/kinwardsim network parent allow child party read
/kinwardsim network-pump 5
/kinwardsim network-status parent
/kinwardsim network-status child
```

The guardian shows applied order 1; party read becomes true while send remains
false. Each window's buttons act against its own simulated endpoint. These
manual commands advance time with `network-pump`; `/kinward demo` additionally
starts automatic fixture-clock advancement. No simulated traffic reaches WoW messaging.
The code is a fixed synthetic fixture, not a live pairing-code generator.

Additional simulator slash command arguments (prefix each with
`/kinwardsim network ENDPOINT`; the visual window uses buttons and fields):

```text
inspect child party send
deny child party read
allow child whisper-character read Friend-TestRealm
invite parent2 87654321
pair child 87654321
add child parent2 parent2:1 confirm
remove child parent2 confirm
remove child parent stop
stop confirm
```

`invite`/`confirm`/`stop` run on the child; `pair`/`sync`/`allow`/`deny`/`inspect`/
`add`/`remove` run on a guardian. Additional guardians require an existing
guardian's exact pending-peer/operation confirmation. Run `network-status child`
to read the actual operation ID. Sync again after membership changes. The final
`remove ... stop` explicitly stops last-guardian supervision. Child UI reports
current effective fixture permissions, including expiry and session inputs.

Exercise outages:

```text
/kinwardsim network-connect child off
/kinwardsim network parent deny child party read
/kinwardsim network-pump 10
/kinwardsim network-status parent
/kinwardsim network-connect child on
/kinwardsim network-pump 20
/kinwardsim network-status parent
```

The edit applies if delivered within its deadline. Repeat with 65 seconds before
reconnection to see expiry without application. `network-loss on|off`,
`network-delay SECONDS` (0–60) and `network-duplicate on|off` affect both receipts
and application replies. Use `network-status` to check pending/delivered/applied;
short intermediate states can pass between pump calls. Existing Phase 2–3
commands retain their original isolated simulator and semantics.

After use:

```sh
python3 scripts/phase2_simulator.py remove
make check
```

Reload to remove staged commands and windows. Check/package runs require the
harness removed; it can be staged again after validation for development use.
Tests cover production logic and mocked widget/adapter calls;
they do not establish game rendering, authentication or actual delivery.

## Visual one-session demo

After staging the harness and reloading, run `/kinward demo`, or click
**Single-session demo** in `/kinward ui`. The four endpoint buttons switch
between parent, child, parent2 and child2 in the same window. Fixtures remain
isolated from live profiles. The demo clock advances automatically while the
client runs; no `network-pump` command is needed.

1. Switch to **child** → **Family & pairing**. Enter peer `parent` and code
   `12345678`, then click **Create invitation**.
2. Switch to **parent**. Enter peer `child` and the same code, then click
   **Request pairing**. Allow a moment for simulated delivery.
3. Switch to **child**, click **Confirm this guardian**, review the exact peer
   and operation, then click **Confirm action**.
4. Switch to **parent**, click **Sync child**, wait for acknowledgement, and open
   **Permissions**. The child now appears in the selector. Click Party read
   **Allow**; read changes through Pending/Delivered to Allowed, while send
   remains blocked. **Connection** shows the applied acknowledgement and revision.
5. Switch to **child** to inspect its effective saved permissions. Changes to
   the guardian's selected child never write another child's policy.
6. **Toggle child link** disconnects/reconnects the selected child (default
   `child`). **Toggle packet loss** drops both requests and replies.
   **Advance 65 sec** tests deadline expiry. A queued permission change that
   expires while disconnected does not apply when reconnected.

Use the Family peer/code fields to repeat pairing for child2 or parent2. For an
additional guardian, the child first invites that exact peer; the new guardian
requests pairing. The existing guardian enters the pending peer and operation
(shown on the child Family tab) and chooses **Approve guardian**, then confirms.
Membership rows offer **Remove guardian**; removing the last guardian explicitly
asks to stop supervision. Cancel leaves the original relationship untouched.

`/kinwardsim network-reset` starts fresh unpaired fixtures and hides old demo
windows. Run `/kinward demo` again. Closing/reopening windows reuses the same
model and frame; it does not reset pairing or apply another operation.
Mocked visual workflow tests cover buttons, confirmation/cancellation, selected
child isolation, disabled live controls, spaced realm targets and a complete
single-session pairing/edit/outage flow. Actual layout, fonts, scaling, scrolling,
combat behavior and taint still require an in-game check on each client.

## Two-account acceptance still required

Record actual build-specific results in PHASE1_RESULTS.md. First establish the
local account identity, current friendship, senderID/gameAccountID mapping,
BattleTag stability and prefix/send results. Supply a tested fresh-token source
before integrating live pairing. Then demonstrate bidirectional pairing and
explicit confirmation, independent read/send changes with all acknowledgement
states, two guardians' conflicts, second-child isolation, alt changes, loss and
reconnect before/after deadlines, revocation during a snapshot, reload and
messaging lockdown. Check errors, taint and inaccessible data on both clients.
Forever and Retail records remain separate. These checks close Phase 4 only
when actual two-account results pass; the one-client simulation cannot do so.

## Permission navigation

Permissions has separate Chat channels and Whisper contacts views. The channel
list scrolls and includes stable keys `channel:general`,
`channel:lookingforgroup`, `channel:trade`, `channel:services` and
`channel:localdefense`, alongside group, say and yell controls. These use the
existing independent read/send policy operations; displaying a setting does not
add capture/enforcement coverage for that route.

Whisper contacts lists fetched character/account settings and pending policy
changes, five contacts per page. Select a row to edit bidirectional access or use
Add whisper contact. Revoked/expired entries remain visible with their state.
Changing child or relationship clears the editor and resets contact paging.
Guardians retain their existing automatic verified-account access. Sync selected
child fetches saved settings; empty/unknown caches do not establish an empty
allowlist. No new widget APIs were introduced for this navigation.

## Battle.net send restrictions

The transport calls `C_BattleNet.SendGameData` and handles its
`SendAddonMessageResult` directly: Success sends, AddonMessageThrottle/
ChannelThrottle back off, AddOnMessageLockdown waits, and TargetOffline retries
while the deadline remains valid. It must not infer Battle.net data restrictions
from `AreOutgoingAddonChatMessagesRestricted` or `InChatMessagingLockdown` before
calling the API.

The pinned Forever `ChatInfoDocumentation.lua` describes the former as a
realm-based restriction on outgoing addon-generated chat;
`Blizzard_Game/Mainline/EventImplementation.lua` uses it to govern the
CooldownBroadcaster. `BattleNetDocumentation.lua` defines SendGameData and its
SendAddonMessageResult return. `ChatConstantsDocumentation.lua` maps success to
0, throttles to 3/8, lockdown to 11, and offline to 12. No WoW restriction is
bypassed: actual SendGameData failure results are still honored.

Regression tests exercise two complete candidate-adapter clients with the chat
restriction flags true, and separately verify actual SendGameData result 11
does not deliver a request or report successful transmission.
