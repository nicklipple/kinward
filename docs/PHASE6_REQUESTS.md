# Phase 6 requests and temporary approvals

The shared request model, protocol operations, Requests tab and isolated demo
are implemented. **Live operation and real-client privacy acceptance remain
unverified.** Phase 1 identity, routing, chat and lifecycle gates and Phase 4/5
live activation remain open. Core still installs neither live transport nor chat
interception. No actual client or two-account experiment was run.

Connection retains transport diagnostics. Requests handles access decisions.
Activity now supplies the Phase 7 chat-history viewer (see PHASE7_HISTORY.md); the request model neither
captures chat history nor replays hidden messages.

## Request and expiry contracts

`Requests.lua` contains pure logic. A paired child creates a channel/read-or-send
request or a bidirectional whisper request for one exact normalized character
or verified account. Temporary exceptions use the same scope with a limited
grant at approval; they never broaden other channels. The optional reason is
child-entered text, at most 160 bytes without control characters. It is never
populated from incoming chat. Whisper account approval still requires a current
verified mapping at enforcement time; a request's account target proves nothing
about an actual sender.

The child owns authoritative `pending`, `approved`, `denied`, `cancelled` and
`expired` states. Creating a request grants nothing. The first terminal decision
accepted by the child wins. Cancelling after application cannot revoke an
already applied grant; the guardian must revoke the permission separately.
Decisions displayed on a guardian are last fetched state, with separate decision
delivery/application status. Terminal approved state records a past decision;
current permission may subsequently expire or be revoked (see Permissions).

- Up to **32 records** per child, with **24-hour request freshness** starting at
  creation. Expiry is checked against injected epoch time on read or mutation,
  including after offline time/reload. Pending identical scope/target requests
  deduplicate; whisper read/send share one scope.
- Requests remain in the child's account profile while disconnected. Guardians
  fetch them when both endpoints can communicate; no offline server is assumed.
  At capacity, expired/other terminal records can be replaced, oldest freshness
  deadline first. Pending work is never displaced. If all 32 remain pending,
  creation reports full. A failed creation does not evict existing work.
- Stable IDs are `LOCAL_ID:request:SEQUENCE`; a persisted monotonically increasing
  sequence survives reload and reset. Relationship changes clear request records,
  while retaining the counter. Missing/rewound counters with existing local
  records enter recovery. Exhaustion closes further creation rather than reuse.
- Reasons, targets, states, request session, base policy revision and freshness
  deadline persist. Payloads and records are validated and bounded. Malformed
  paired data or guardian display caches enter recovery, preserving damaged data.
  This is an additive schema-1 migration, not a supervision reset.

Approvals offer **indefinite**, **until logout**, **15 minutes** or **45 minutes**
in the visual UI. The protocol supports whole-second durations from 1 to 86400.
Duration starts at the child's first successful application, not at guardian
click, first transmission or acknowledgement. Until-logout grants require the
same nonempty session token as when the request was created; reload preserves
it, a new login invalidates it. All actual session behavior remains P1-SESSION
client work. Expiry after offline time uses the existing production evaluator.

Every queued decision has a **60-second delivery deadline** in the UI. A late
packet cannot grant access even if it arrives after local transport expiry.
Retries retain operation IDs and durable child replay results, so lost replies
cannot restart a duration or create a second write. Kinward transport work is
transient across reload; fetch the child's state before making a new decision.

Approval requires the request's recorded base revision to equal the child's
current policy revision. **Any intervening permission edit**, including a revoke
or an unrelated setting, rejects the stale approval. This deliberately uses a
conservative whole-policy check. Cancel/deny the obsolete request and create a
fresh one. If approval applies first, a later accepted revoke removes it through
the ordinary policy path. A denial can terminate an obsolete pending request.
Generation/current-guardian authorization is checked before either operation.

## Protocol and delivery

The existing bounded version-1 envelope, authenticated transport identity,
fragmentation, deadlines, replay window and per-child policy revisions are reused.
New operation names are additive; old peers can reject unsupported operations.
There is no new service, library, WoW global or runtime dependency.

| Operation | Fields following the five-field envelope |
| --- | --- |
| `request-list` | cursor 1–32 |
| `requests` reply | echoed cursor; `0/` or `1/` plus next cursor or `done` (prompt setting); request ID; channel; direction; target; reason; expiry; state; base policy revision; request session ID |
| `request-decision` | exact request ID; `approve` or `deny`; grant mode (empty for deny); duration seconds (empty otherwise); base revision; absolute delivery deadline |
| `request-prompts` | `true` or `false`; absolute delivery deadline |

A complete empty page has an empty ID and empty request fields. Request-list
responses are correlated with the outgoing operation/sequence/cursor, validated,
and checked against current child generation. Page scans stage at most 32 records
and replace the displayed inbox only after completion; previous complete results
stay visible during refresh. Scans are display data, not an atomic authority
snapshot: requests may change during paging. The child always rechecks the
current request, expiry, revision and session when applying a decision.

The simulator and candidate WoW transport poll known authorized child profiles
every 20 seconds, with at most one poll scan pending per peer. The dashboard also
polls while visible and provides Refresh requests. All traffic shares existing
transport bounds/rate limits; a full 32-record scan can take over a minute.
Delivery loss can leave last fetched results stale; do not read silence as a
request decision. Refresh and application acknowledgements make progress visible.
Replies are rechecked for current authorization before queued transmission.
No unauthorized or revoked guardian can fetch new request reasons or grant access.

`request-decision` enters Family's existing durable replay gate, then delegates
the actual grant to its ordinary policy mutation function. Approval state is set
only after that mutation succeeds and increments the child policy revision.
Successful decisions queue an inbox refresh and policy sync. Denial returns
`request-denied`; delivery and application are still distinct transport states.

## Blocked-whisper prompt and UI

`Chat.lua` supplies only an accessible normalized character identity from a new
blocked ordinary-whisper read decision to the pure prompt model. No message body
is an argument. Missing/secret/invalid identity produces no prompt. Party blocks
and allowed whispers do not prompt. Duplicate frame callbacks reuse line-ID
results and do not notify again. Without a usable line ID, display still evaluates
but no prompt is generated. Prompt state contains only identity, relationship
and a 60-second expiry, never hidden text.

Default prompt limits are one new notification per **10 seconds globally** and
once per **60 seconds per character**, with at most 64 unexpired sender entries.
Current guardians can disable stranger prompts via an authenticated control
operation. Disabling prompts never allows blocked content; manual requests remain
available. Relationship and prompt expiry are checked again at UI action time.

The candidate WoW filter invokes optional `KinwardChatIO.prompt(character)` on
a new prompt. A future verified bootstrap can use it to open the child dashboard
bound to its current transport/chat model. Without that callback the candidate
prints only the accessible sender and directs the child to `/kinward ui`.
The bound dashboard offers **Request whisper access** from the sender-only prompt.
The live bootstrap remains gated; no real whispers are intercepted today.

The Requests tab provides scope selection, target and optional reason, browsing
and cancellation for children. Guardians browse one child's exact request scope,
identity and reason and choose a duration or denial. Buttons capture the rendered
request and child generation, and pass separate arguments (including spaced realm
names). The view explains duration start/deadline and shows pending/delivered/
applied/rejected decision status. Connection retains debug details separately.

All widget APIs were already pinned and used by the dashboard (frame/button/text,
edit-box max letters, show/hide and script handlers); no new WoW API was introduced.
The Phase 5 filter, `canaccessvalue`, print and session/clock evidence remains in
PHASE5_CHAT.md. The pinned inaccessible-argument filter bypass is unchanged: no
callback means no enforcement or prompt guarantee. Mocked widgets and secret
sentinels do not verify actual rendering, lockdown, protected paths or taint.

## One-client demo

Stage with `python3 scripts/phase2_simulator.py install`, reload, then
`/kinward demo`. Pair parent/child with the existing Family controls and sync.
The demo is closure-local, uses fixture identity/time and never accesses live
SavedVariables, chat or messaging. Connection remains available throughout.

1. Switch to **child**, open **Requests**, select Party/read, enter a reason and
   Send access request. It stays pending and chat permission remains closed.
2. Switch to **parent**, select child, open Requests and Refresh requests. Read
   exact scope/reason, then approve for 15 minutes. Observe queued/application
   status and switch back to child to see the applied result.
3. Check `/kinwardsim network-chat child read party Friend-TestRealm unused 1`:
   allowed. Check send separately: still blocked. Whisper access remains closed.
4. On child, cycle Access to Whisper character, enter `Friend-TestRealm`, request,
   then on parent refresh and approve Until logout. Both whisper directions allow
   that character, while a party stranger remains closed.
5. Use `/kinwardsim network-reload child`: the session grant survives. Use
   `/kinwardsim network-login child`: it expires. These are fixture tokens only.
6. With a closed character whisper, invoke
   `/kinwardsim network-chat child read whisper Stranger-TestRealm unused 77`.
   Child's dashboard shows the sender-only prompt and a request button. Repeat
   line 77: no duplicate prompt. Disable Stranger prompts from the parent Requests
   tab, pump, and repeat with a new sender: no new prompt, still blocked.
7. Toggle parent link off, create a different child request, then reconnect and
   refresh: it is delivered. Cancel another pending request before an approval
   applies: the approval is rejected. Packet-loss/delay controls exercise retries.
8. Approve, advance fixture time by 65 seconds repeatedly or use the command
   clock controls, and confirm expiry. Add parent2 to test two guardians; only
   the child's first terminal decision takes effect. Child2 stays independent.

Command equivalents (fresh fixture IDs start at `child:request:1`):

```text
/kinwardsim network child request party read - Playing with my group
/kinwardsim network parent requests child
/kinwardsim network-pump 8
/kinwardsim network parent decide child REQUEST_ID approve duration 900
/kinwardsim network parent decide child REQUEST_ID deny - -
/kinwardsim network child cancel-request REQUEST_ID
```

The visual view intentionally uses scopes/reasons instead of raw protocol IDs.
For command-only fixtures, read the returned production profile in automated
scenarios or construct the documented sequence ID, e.g. `child:request:1` after
network-reset. Prefer visual controls for manual browsing.

Remove the staged harness with `python3 scripts/phase2_simulator.py remove` and
reload. Manifest/package validation rejects staged developer assets.

## Acceptance and checks

Strict Lua 5.1 tests cover migration/corruption, bounded offline queues, reconnect,
all decisions/durations, duplicate/replayed approvals, deadlines, reset/re-pair,
unknown identity, cancellation/expiry, two guardians, both revocation orders,
secret-body sentinel callbacks, prompt preference/flood limits, paged inboxes,
actual request widgets and isolation between child selections. `make check` also
runs prior suites, formatting, zero-diagnostic LuaLS and manifest validation.
`make package` builds the runtime-only release archive.

Client acceptance is still pending. Once prior live gates and bootstrap close,
use consenting accounts to repeat channel/whisper requests online/offline,
15m/45m/until-logout grants, reload/new login, expiry after offline time, cancellation,
revocation races, two guardians and parent disconnect. Send a distinctive blocked
incoming body, then confirm every child-visible window/widget/debug output
contains only sender identity and **never that body**. Check disabled prompts,
floods, separate whisper windows, actual lockdown/secret arguments, errors and
taint. Record Forever and Retail separately in PHASE1_RESULTS.md. Approval must
affect subsequent chat only; do not replay the earlier hidden message.
