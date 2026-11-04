# Request guardianship by name

The normal pairing flow no longer asks users to invent, exchange or type a code.
The child names an intended guardian and sends a request; the guardian clicks
Accept child. The child applies closed defaults and returns its new family state
automatically. Neither side needs to type an operation ID or manually sync.

Kinward starts its live connection and supported chat monitoring automatically
after the character enters the world. The demo uses isolated fixtures. Actual
engine delivery, taint and coverage still require two-account/client testing.

## Try the demo

The development simulator is left staged for this checkout. Reload, then run
`/kinward demo`:

1. Click **child**, open **Family & pairing**, and enter `parent` in the guardian
   name field. Check the resolved account shown below the field.
2. Click **Request guardianship**. No code is displayed or required.
3. Switch to **parent**. Click **Guardianship requests (1)** or open Family.
4. Click **Accept child**. Wait for the applied response: child appears in the
   list and Permissions becomes editable with closed defaults. Decline is also
   available; it grants nothing.

In the live addon, an incoming request prints a guardian
notification and opens/focuses the live Family dashboard when it belongs to the
verified live profile. Existing windows are reused. Duplicates do not reopen it.
The simulator keeps endpoint switching explicit so a synthetic parent's window
does not unexpectedly cover the child's window in the same client.

To add another guardian, child requests `parent2`, parent2 accepts, and the
existing parent opens Family. The pending candidate appears automatically;
**Approve guardian**, then the existing confirmation button, approves the exact
child/candidate. There are no peer/operation input fields. Until approval applies,
parent2 has no policy/history access. Membership changes sync automatically.

## Names and consent

Choose the child/guardian roles once during setup. The candidate resolves only current verified Battle.net friends. Full BattleTag,
current online character name, or Name-Realm can identify a friend; ambiguous,
missing, inaccessible or incomplete lookup data never guesses account ownership.
Full names/BattleTags are recommended where character names collide. Offline
accounts can be identified by BattleTag when the friendship data is available,
but requests still expire if they cannot be delivered.

The child sees the resolved stable account before clicking Request. The click
resolves again and rejects a changed result. The guardian sees the transport-
verified requesting account and should accept only a recognized child. Familiar
names, friendship, knowing a request token or knowing an old code do not grant
control/history authority. Tokens are internal; users do not create them.

The simulator recognizes `parent`, `parent2`, `child`, `child2` and their
`-TestRealm` fixture forms. These are synthetic aliases, not live player lookup.
The live adapter's character aliases use the already pinned Forever Battle.net
friend/game account fields (`characterName`, `realmName`, `battleTag`, project,
online/friendship state). No new WoW API was added. P1-ID/P1-ROUTE must still
verify those engine records, stable/local identity and routing before activation.

## Handshake and bounds

`Pairing.lua` implements the pure handshake. `PairingPanel.lua` renders its name,
preview, pending child cards, accept/decline buttons and existing-guardian approval.
The UI uses the existing pinned widgets and literal text escaping. The candidate
WoW adapter opens the live Family view only when the profile matches the current
live namespace settings; simulator profiles cannot trigger a live popup.

- A request lives for two minutes and binds a fresh internal token, intended peer,
  current child generation and absolute expiry. The injected Family token supplier
  must satisfy its existing globally fresh/unpredictable live contract. Fixture
  counters are never live randomness. No new randomness provider is invented.
- The child can cancel. Cancellation/replacement/expiry, changed friendship,
  wrong peer/token/generation and unsolicited acceptance cannot install a family.
  Queued obsolete requests stop sending; already delivered notifications can
  remain visible until expiry, but a delayed acceptance still fails on the child.
- Each guardian inbox contains at most sixteen short-lived peer-bound entries,
  displayed three at a time. Duplicate requests are deduplicated by sender
  sequence/token; older requests cannot replace a newer row. A rendered Accept
  button binds the exact token, so an inbox replacement cannot swap its target.
- First acceptance reuses the existing atomic Family confirmation mutation:
  closed defaults are installed before the new state is acknowledged. Repeated
  or lost replies do not rotate generations or install defaults twice.
- A small validated `pairingReceipt` persists the accepted peer/token/operation/
  sequence, original/current generation and expiry. It allows the same acceptance
  to return state after reply loss/reload, only while the peer remains a current
  guardian. Reset/membership rotation clears it; malformed saved receipts enter
  recovery. Pending proposals and inboxes are transient, so an uncompleted
  request must be sent again after reload.
- Additional guardians wait for an existing guardian's authenticated approval.
  A bounded `pairing-pending` read exposes only the candidate/token/expiry to
  current guardians. The existing add operation rotates generation and current
  membership/policy sync follows automatically. Candidate sync polling runs at
  five-second intervals while waiting, with existing transport deadlines/bounds.

New envelope operations are `guardian-request`, `guardian-accept` and
`guardian-decline` (token, expiry), plus authorized `pairing-pending` and its
`pairing-candidate` reply (candidate peer, token, expiry). They reuse canonical
operation IDs, authenticated transport sender identity, fragmentation, receipts,
retry/backoff and existing field/byte limits. The child can originate only the
new request operation; this does not give it guardian policy authority.

The legacy short-code protocol and diagnostic commands remain for existing
fixtures/backward regression coverage. They are not advertised as the normal UI
and are unnecessary for this flow. Earlier phase documents describing manually
entered codes/operation IDs are historical; this walkthrough supersedes them
for everyday pairing.

## Verification

`make check` includes the new handshake/widget/adapter scenarios and all previous
phase suites: one-name/one-accept pairing, initial defaults, cancel/decline/expiry,
wrong peer/token, replay and reset, freshness, duplicate/reordered delivery,
friendship loss, bounded inbox, persisted receipts, additional guardian approval,
verified name ambiguity/alt changes and the guarded live-popup branch. The release
package excludes the explicitly staged simulator.

Real-client tests remain necessary for actual names/friendship data, request
arrival while Family is hidden, popup behavior, receiver identity, reconnect,
restricted states and taint. Record Forever and Retail separately. Simulated or
mocked success does not close the live gates.

## Right-click selection and automatic connection

Right-click a player portrait, party/raid member, chat player or friend and choose
**Kinward: Pair with player**. This opens Family. In the Child role, the selected
name and realm (or BattleTag from a Battle.net friend menu) fill the guardian
field. Review the resolved account and click Request guardianship. Selecting a
menu item never sends a request or grants access. Guardians instruct the selected
child to request them; the child-request/guardian-accept handshake stays intact.

There is no activation command, verified flag or test-mode requirement. Core
starts Runtime.lua from PLAYER_ENTERING_WORLD after SavedVariables initialize.
It installs chat monitoring even while Battle.net is connecting and retries
missing player/Battle.net identity every two seconds and on BN_CONNECTED.
Dashboard models attach to the same shared live transport and chat adapter.
Fresh login creates a new session token; reload retains the saved session token.
The runtime token generator combines engine player GUID, server/precise time and
a durable local counter. It is not a secret used instead of Battle.net sender
authentication: peer identities still come from current engine friendships.

For a two-account check:

1. Install the same build on both clients, enable Lua errors with
   `/console scriptErrors 1`, and log in or `/reload`.
2. Open `/kinward ui`; select Child role on one and Guardian role on the other.
   Both accounts must be Battle.net friends and online in the same WoW version.
3. On the child, select the parent from a right-click menu, review the account,
   and request guardianship. On the parent, accept in Family.
4. The child form displays delivery progress: queued, sent, received or blocked.
   `/kinward status` and Connection report sent/received packets, unmapped engine
   senders and API send results. These diagnostics contain no captured message
   bodies. Zero received packets indicates a delivery issue; unmapped packets
   indicate a sender-mapping issue. Unknown/untrusted sender packets are discarded.
5. Confirm the relationship on both clients, then test independent read/send
   party controls, whisper grants, Requests and Activity. Guardian account
   whispers always bypass restrictions, so use a third consenting sender or an
   outgoing non-guardian target to test blocked whispers.
6. Reload and check automatic reconnection and session grants. General/Trade/LFG,
   Battle.net whispers, bubbles, voice, cached sends and secret states are not
   established coverage. Actual remote visibility and taint need client checks.

The former `/kinward test start|status|stop` path has been removed. Normal login
now starts the actual adapters. No tests or source inspection are claimed as
real-client delivery/coverage acceptance.

Pinned Forever API evidence (Gethe 17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c,
under `reference/blizzard-ui/Interface/AddOns/`):

- `Blizzard_Menu/Menu.lua`: `Menu.ModifyMenu` and context-data callbacks.
- `Blizzard_UnitPopupShared/UnitPopupShared.lua`: `MENU_UNIT_` tags and player
  context `name`, `surname`, `unit`, `accountInfo`.
- `Blizzard_UnitPopupShared/UnitPopupSharedMenus.lua`: PLAYER/PARTY/RAID_PLAYER,
  FRIEND/FRIEND_OFFLINE, BN_FRIEND/BN_FRIEND_OFFLINE, CHAT_ROSTER registrations.
- `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua`: `UnitIsPlayer`,
  `UnitIsUnit`, `UnitFullName` and Battle.net context account info.
- `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`: `UnitFullName`,
  `UnitGUID`; `PlayerScriptDocumentation.lua`: `GetNormalizedRealmName`.
- `Blizzard_AddFriend/AddFriendTemplates.lua`: `BNGetInfo` BattleTag return.
- `Blizzard_Console/Blizzard_Console.lua`: `GetTimePreciseSec`.

Source evidence permits implementing the runtime boundary; it is not proof that
Forever or Retail runtime acceptance passed. Automated tests cover real candidate
adapters on two independent mocked clients, menu identity/selection, cross-realm
pairing, applied permission updates, automatic startup, delayed Battle.net readiness and reload/new-login sessions.
