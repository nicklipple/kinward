# Request guardianship by name

The normal pairing flow no longer asks users to invent, exchange or type a code.
The child names an intended guardian and sends a request; the guardian clicks
Accept child. The child applies closed defaults and returns its new family state
automatically. Neither side needs to type an operation ID or manually sync.

The working demo uses isolated fixtures. **Live identity/routing/bootstrap gates
are still open**; Core does not activate a live transport. No two-account or
real-client verification is claimed by this change.

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

In a future verified live installation, an incoming request prints a guardian
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

Choose the child/kinward roles once during setup. The candidate resolves only current verified Battle.net friends. Full BattleTag,
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

## Right-click selection and explicit Retail live tests

Right-click a player portrait, party/raid member, chat player or friend and choose
**Kinward: Pair with player**. This opens Family. In the Child role, the selected
name and realm (or BattleTag from a Battle.net friend menu) fill the guardian
field. Review the resolved account and click Request guardianship. Selecting a
menu item never sends a request or grants access. Guardians instruct the selected
child to request them; the existing child-request/guardian-accept handshake stays
unchanged. Character selections retain their explicit realm. Ambiguous short
names still require a full name/BattleTag. A verified BattleTag remains usable
when unrelated character aliases are inaccessible.

The default alpha remains inert. For a test between two consenting Retail
accounts, with Kinward installed on both and the accounts Battle.net friends:

1. Enable Lua errors with `/console scriptErrors 1` on both clients. Open
   `/kinward ui`, select Child role on one and Guardian role on the other.
2. Run `/kinward test start` on **both** clients after entering the world. This
   explicitly starts candidate Battle.net transport and ordinary whisper/party
   capture/filter/send adapters. It does not record any acceptance gate as passed.
   Test activation is not saved; repeat after each reload/login.
3. On the child, right-click the parent's player name/portrait or Battle.net
   friend entry, choose Kinward's pairing entry, review the account, and request.
   On the parent, accept the child in Family. Confirm both dashboards report the
   applied relationship before evaluating permissions.
4. Use `/kinward test status` on each side to inspect activation/account and
   engine-mapped incoming packet counts. Zero counts while requesting indicate
   routing/mapping still needs real-client investigation. If names cannot resolve,
   try the Battle.net friend context menu/full BattleTag and confirm friendship,
   matching WoW project and online presence.
5. In a party, test incoming and outgoing party permission separately. Test an
   ordinary character whisper using a third consenting sender or the child's
   own outgoing target. A guardian's verified account always bypasses whisper
   restrictions, so guardian-to-child whispers are not a valid blocked-whisper
   test. Confirm actual remote visibility as well as the local Activity view.
6. Check Activity on the guardian and refresh history. Test expiry/reload,
   friendship loss, changed characters and error/taint logs. General/Trade/LFG,
   Battle.net whispers, voice, bubbles, cached sends and secret states are **not**
   established coverage. Do not treat those controls as proof of enforcement.
7. `/kinward test stop` removes owned filters/transport callbacks and then requires
   `/reload` to clear wrapper taint. Saved supervision/permissions remain intact.
   While inactive, this build does not enforce that saved policy.

The test token generator combines engine player GUID, server/precise time and a
persisted local counter. It is deliberately labeled a test generator, not a
verified production entropy/identity/session implementation. Starting a test
creates a fresh test session, so old session grants expire. Real incoming sender
ID semantics, payload restrictions, taint and lifecycle correctness still need
your actual two-account results. This is a test facility, not a verified release
activation path.

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

Source evidence permits implementing the test boundary; it is not proof that
Forever or Retail runtime acceptance passed. Automated tests cover real candidate
adapters on two independent mocked clients, menu identity/selection, cross-realm
pairing, applied permission updates, startup idempotence and teardown.
