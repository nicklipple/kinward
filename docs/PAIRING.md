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
