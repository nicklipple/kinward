# Guardian implementation plan

Status: planned. Only the initial scaffold is implemented.
[REQUIREMENTS.md](REQUIREMENTS.md) defines the product behavior. Implement the
phases in order; each numbered task should fit a focused, reviewable change.
Do not start by building the entire settings interface or transport framework.

## Delivery approach

Build a small complete path first: pair, apply one permission, enforce it, request
an exception and approve it. Then add monitoring and broaden chat coverage.
Keep policy, pairing and request logic independent from WoW calls. Use the same
logic in unit tests, the single-client simulator and live operation.

A phase is complete when its acceptance criteria pass, `make check` passes and
any remaining client-only limitations are documented. Run `make package` when
changing loading or release contents. Never describe simulated behavior as
real-client verification. Check every new API against the pinned Forever source;
record Retail observations separately while developing in `_retail_`.

## Phase 0 — Existing foundation (complete)

The repository already has initialization, saved settings, a slash command,
pinned dependencies, static analysis, strict Lua 5.1 tests, manifest validation,
packaging and CI. Runtime files live at the repository root in
`_retail_/Interface/AddOns/Guardian/`.

This phase provides no pairing, restrictions or monitoring.

## Phase 1 — Establish what the client can enforce

Purpose: resolve the risks that could change the product before building on them.

- [ ] **1.1 API evidence matrix.** Record the Forever symbols/source paths,
  expected loading order and client test procedure for chat filters, send paths,
  Battle.net identity, addon messages, clocks/session events, bubbles and voice.
  Mark each capability verified, unsupported or still untested. Do not silently
  substitute Retail definitions or an interface number for Forever's.
- [ ] **1.2 Incoming and outgoing chat experiments.** Add a developer-only probe
  with explicit activation and cleanup. Check normal chat entry, slash commands,
  replies, separate whisper windows, macros and addon-originated sends where
  applicable. Establish which supported paths can be blocked before sending;
  hiding the outgoing echo is not prevention. Record errors and taint.
- [ ] **1.3 Identity and routing experiments.** With two consenting test accounts,
  verify Battle.net friendship lookup, character-to-account resolution, changing
  alts and available addon-message routes. Establish what identity is stable
  across login, and what numeric handles must be resolved afresh. Test account
  appearing offline, unavailable lookups and delivery failure results.
- [ ] **1.4 Session and restricted-state experiments.** Verify how to distinguish
  reload from logout/new session, and what chat/identity data remain accessible
  during lockdown. Investigate bubbles and voice controls without promising
  global coverage. Verify whether speech/text-to-speech surfaces need handling.

Deliverable: `docs/CAPABILITIES.md`, reproducible probe instructions and a clear
initial support matrix. Keep probes out of the release package.

Acceptance: the first incoming filter, an actual outgoing prevention path and a
usable pairing/communication path are demonstrated, or the precise blocking
capability is reported. If core enforcement is unavailable, resolve that scope
with the user before claiming or building a working parental-control release.
Work on pure logic can proceed while two-account tests are pending, but this
phase must not be marked verified based on mocks.

## Phase 2 — Policy, persistence and single-client test harness

Purpose: make the rules deterministic and testable without the game.

- [ ] **2.1 Versioned account profile.** Migrate the existing `GuardianDB` into a
  documented schema for role, family relationships, pairing generation, policy
  and bounded queues. Preserve valid data; distinguish absent initial data from
  damaged paired state so corruption cannot silently remove supervision.
- [ ] **2.2 Pure policy evaluator.** Evaluate channel/read/send permissions and
  bidirectional whisper grants. Unpaired means unrestricted; paired means closed
  defaults with the guardian control path preserved. Party permission never
  grants whisper permission. Unknown account identity does not satisfy a friend
  approval. Use normalized character/realm identity and verified account mappings.
- [ ] **2.3 Expiry and session model.** Inject time and session context. Implement
  indefinite, explicit-duration and until-logout grants. Reload preserves session
  grants; a new login invalidates them. Re-evaluate expiry after offline time.
- [ ] **2.4 Isolated parent/child simulator.** Instantiate two independent stores
  and endpoints in one client, sharing production logic and an in-memory
  transport. Add a second guardian and second child as test fixtures when needed.
  Provide delivery delay, loss, duplication, reordering, disconnect and clock
  controls. Never send simulator traffic or modify live saved pairing/policy.
- [ ] **2.5 Tooling updates.** Extend TOC ordering, types, formatting targets and
  tests as runtime modules are added. Maintain runtime-manifest completeness and
  keep test/probe assets out of both zip and CurseForge packages.

Deliverable: a policy engine and a command-driven demo/test harness; no polished
UI is needed yet.

Acceptance: automated cases cover default rules, migrations/malformed data,
read/send independence, party-versus-whisper separation, unknown identity and
all expiry modes. Simulator state is demonstrably isolated from live state.

## Phase 3 — Pairing and authenticated family operations

Purpose: establish who can control or monitor each child.

- [ ] **3.1 Minimal protocol.** Define versioned message envelopes, operation IDs,
  relationship/generation IDs, bounded payloads and strict decoding. Validate
  transport-reported identity rather than trusting sender fields in payloads.
  Define acknowledgements, duplicate handling and unsupported-version behavior.
- [ ] **3.2 First guardian pairing.** Implement short-lived single-use codes,
  attempt limits, friendship verification and explicit confirmation tied to the
  intended peer. Pairing completion installs closed defaults atomically. Do not
  grant history access or policy authority to someone who merely knows a code.
- [ ] **3.3 Additional guardians and children.** Maintain independent child
  profiles on the guardian side. Require an existing guardian's approval for
  additions to an already supervised child. Let either authorized guardian edit
  policy and remove another, with confirmation.
- [ ] **3.4 Stop supervision and recovery.** Require explicit confirmation to
  remove the last guardian. Use a new relationship generation after reset or
  re-pairing; reject traffic from revoked or stale relationships, including
  delayed policy changes and history requests. Clear associated delivery work.
- [ ] **3.5 Adversarial protocol tests.** Exercise wrong/expired/reused codes,
  unpaired senders, spoofed payload identity, oversized/malformed messages,
  revoked guardians, replay and reconnect during pairing. This protects against
  unrelated players, not local modification by a child.

Deliverable: pairing and family membership working in the simulator.

Acceptance: only an authorized current guardian can change policy or receive
history; a reset/re-pair cannot restore an old guardian's access.

## Phase 4 — Live transport and the first guardian dashboard

Purpose: make a policy change travel between real installations visibly.

- [ ] **4.1 WoW transport adapter.** Use the route verified in phase 1. Implement
  bounded fragmentation/reassembly if needed, rate limits, timeout, retries and
  backoff. Handle offline, throttled and lockdown results. No external service
  or offline server delivery is assumed.
- [ ] **4.2 Reconnect and alt discovery.** Resolve approved peers through verified
  Battle.net data, resume delivery after both endpoints become reachable and
  reconcile current membership/policy. Keep ambiguous identity unresolved.
- [ ] **4.3 Per-setting synchronization.** The child orders accepted changes and
  assigns revisions. Retries retain operation IDs and cannot create new writes.
  Independent settings do not overwrite each other. Surface last-applied order
  and delivery deadlines so stale queued edits are not applied unexpectedly.
- [ ] **4.4 Minimal functional UI.** Provide role setup, pairing, guardian child
  list, membership controls and read/send permission controls. Show pending,
  delivered and applied acknowledgement states separately. Child UI shows
  supervision status and currently effective permissions.
- [ ] **4.5 Presence.** Show responding, last contact and unreachable. Do not label
  an unreachable child as definitely offline or addon-disabled. Distinguish
  monitoring/transport loss from the existing policy continuing to operate.

Deliverable: a guardian can pair and change a child's policy through real addon
messages; the same flow is demonstrable in one client using the simulator.

Acceptance: two-account tests demonstrate delivery, acknowledgements, alt
switches and offline recovery. Tests show per-setting conflict ordering and no
cross-child data leakage. If two accounts are unavailable, retain an explicit
unverified gate; the simulator does not satisfy it.

## Phase 5 — First complete chat-control slice

Purpose: connect approved policy to real chat behavior, initially with a narrow
verified surface rather than claiming all chat at once.

- [ ] **5.1 Incoming adapter.** Wire the policy evaluator into the verified common
  chat-filter path. Start with ordinary whispers and party chat; handle duplicate
  frame callbacks without duplicate decisions, records or prompts.
- [ ] **5.2 Outgoing adapter.** Apply the same policy before a supported send path
  executes. Explain blocked sends to the child without exposing blocked incoming
  content. Distinguish a blocked attempt, an attempted send and confirmed output.
- [ ] **5.3 Whisper identity.** Support character-only approval first, then
  verified Battle.net-friend approval. Never allow a stranger solely because of
  party membership. Missing or secret identity must not become an accidental
  allow. Preserve the necessary guardian communication path.
- [ ] **5.4 Runtime lifecycle.** Apply saved policy before supported chat becomes
  available, survive reload/alt changes, update permissions without stale filters
  and leave unpaired profiles unrestricted. Handle loss of monitoring while
  continuing the last policy within verified enforcement capabilities.

Deliverable: the first usable vertical slice: pair, grant/revoke party or whisper
access, and demonstrate the correct effect on read and send independently.

Acceptance: a two-account checklist confirms blocked text is hidden and blocked
outbound messages are not received on supported paths. Cover reload, logout,
policy revocation and parent disconnect. Document any uncovered route.

## Phase 6 — Child requests and temporary approvals

- [ ] **6.1 Request model.** Add channel, whisper and temporary-exception requests,
  optional reasons, stable request IDs and pending/approved/denied/cancelled
  state. Queue offline requests with size limits and expiry/freshness rules.
- [ ] **6.2 Blocked-whisper prompt.** Show the sender's character name, hide their
  message body, and offer a request to read/send whispers. Respect the guardian
  prompt setting; suppress duplicates and limit notification floods.
- [ ] **6.3 Guardian approval UI.** Show the exact scope, identity and reason.
  Offer indefinite, until-logout and explicit durations such as 15m/45m. Bind an
  approval to its request/target; do not treat it as permission for other channels.
- [ ] **6.4 Apply and acknowledge.** Route grants through the existing policy
  protocol. A request is effective only when the child applies it. Handle two
  guardians answering, withdrawn/expired requests and revocation racing approval.
  Define duration start and command delivery deadline explicitly in the UI.
- [ ] **6.5 Do not replay hidden history by default.** Approval affects subsequent
  chat. Replaying previously blocked content requires a separate product decision.

Deliverable: child request to guardian decision to effective expiring permission,
working online and after reconnect.

Acceptance: simulator and unit tests cover the full state transitions, duplicate
approvals, expired requests, conflicting decisions and expiry across reload and
logout. Real-client tests confirm the prompt never reveals the message body.

## Phase 7 — Monitoring and bounded history

- [ ] **7.1 Capture once.** Record accessible incoming/outgoing chat, blocked
  incoming messages and intercepted blocked-send attempts once per message.
  Include direction, channel, identity, time and disposition. Never serialize,
  compare or persist inaccessible secret values; record a gap instead.
- [ ] **7.2 Bounded storage.** Add configurable retention/count limits and bounded
  delivery queues. Seven days/10,000 records are proposed starting defaults to
  confirm before release. Report truncation, expiry and unavailable intervals.
- [ ] **7.3 Authorized history delivery.** Send only to current approved guardians,
  with batch limits, sequence/cursor tracking, deduplication and resumable catchup.
  Prioritize control messages and requests ahead of history backlog. Recheck
  authorization when sending, not just when originally queuing a record.
- [ ] **7.4 Guardian viewer.** Add per-child live/history views, channel and
  disposition filters, catchup progress and monitoring-gap indicators. Keep
  blocked text out of child-visible widgets, debug output and simulator/live
  crossover. Clearly indicate to the child that monitoring is active.

Deliverable: guardians can review accessible live and queued chat accurately,
including blocked content that the child cannot see.

Acceptance: tests verify retention, reconnect catchup, duplicate batches,
revocation during transfer, isolation between children and guardians, and that
history traffic cannot starve pairing or policy changes. Verify actual capture
coverage and restricted-state gaps in-client.

## Phase 8 — Broaden coverage and prepare the first release

- [ ] **8.1 Remaining chat types.** Extend the tested slice to say, yell, emotes,
  instance/raid, guild/officer, public/custom channels, communities and supported
  Battle.net chat. Match channel identity rather than treating a transient
  channel number as a permanent identity. Test each read/send permission.
- [ ] **8.2 Other chat surfaces.** Verify separate whisper windows, bubbles and
  text-to-speech; disable uncontrolled surfaces where feasible and document
  remaining exposure. Verify practical voice controls. Test default UI and ElvUI
  separately; shared hooks alone do not establish compatibility.
- [ ] **8.3 Family workflow polish.** Test several children/two guardians, rename
  and transfer behavior, friendship removal, outdated addon versions and missing
  identity. Make unsupported paths and pending state clear. Optional profile
  export/import must not silently carry authority to the wrong account.
- [ ] **8.4 Reproducible regression scenarios.** Add one-client demo scenarios for
  pairing, requests, expiry, conflicts, outages, reset/re-pair and history gaps.
  Maintain a separate two-account manual smoke checklist with recorded results.
- [ ] **8.5 Release validation.** Run bootstrap, checks, guardrail probes and
  packaging. Confirm `.pkgmeta` and local zip exclude tools, probes, references,
  test data and saved personal data. Run client smoke tests across the supported
  UI/lockdown/session cases. Reverify the Forever build/interface and APIs when
  it becomes the active test client; record actual build-specific results.

Deliverable: first release with an explicit supported-chat matrix and honest
monitoring/enforcement limitations. Uploading or publishing is a separate action.

Acceptance: release claims match the verified matrix; unresolved core chat
prevention or identity problems are not hidden behind a passing simulator.

## Milestones and dependency gates

| Milestone | Required phases | Demonstration |
| --- | --- | --- |
| Testable rules | 1 evidence started, 2 | Two isolated profiles evaluate the same production policy. |
| Paired control | 3–4; phase 1 routing verified | A real guardian changes an acknowledged child policy. |
| First usable slice | 5; phase 1 enforcement verified | Whispers/party are independently readable/sendable as approved. |
| Child self-service | 6 | Child requests access; guardian grants it with expiry. |
| Reviewable supervision | 7 | Guardian sees accessible history and explicit gaps. |
| First release | 8; all required client gates passed | Supported channels/surfaces and limits are documented and tested. |

The next implementation task is **1.1**, followed by the smallest probes needed
for **1.2–1.4**. No new framework or third-party runtime library is assumed.
