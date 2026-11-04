# Phase 3 family protocol and simulator

Current user-facing pairing is [name request and one-click acceptance](PAIRING.md).
Older code/operation-entry procedures below remain diagnostic regression fixtures;
the normal Family UI no longer requires them.

`Protocol.lua` and `Family.lua` are pure production modules. The staged simulator
runs these same modules with synthetic transport identities, friendship maps,
clocks, codes and generation tokens. No live transport, randomness source,
Battle.net lookup, chat interception or history storage is installed. This work
establishes authorization logic, not verified live authentication or enforcement.
Phase 1 client gates and Phase 4 live delivery remain open.

## Trust and bounds

The adapter supplies a **verified stable peer identity separately from the wire
message**, a trusted friendship map, and a clock. Never accept a payload's sender
claim, a display name, a transient numeric Battle.net handle, or an ambiguous
identity as that peer. Ordinary friendship does not grant control or history.
The live identity/transport adapter must establish these inputs before use.

`NewFamily` takes a normalized profile and a token supplier. Its tokens must be
fresh across reset, re-pair, reload, deleted saved data and different machines.
The adapter must supply fresh unpredictable eight-digit pairing codes; simulator
codes and monotonically counted generation tokens are deliberate test fixtures
and must never be reused as live credentials. There are no new WoW APIs in this
phase. Live token/code generation needs evidence and implementation with the
future adapter; the pure logic does not pretend to supply secure randomness.

Each child has at most eight guardians; each guardian endpoint tracks at most
16 child destinations. Messages are at most 2,048 bytes, 16 fields, 256 bytes per
field. Identifiers are nonempty and at most 128 bytes. Control characters are
rejected on the wire. There is no executable deserialization. The current
2,048-byte logical limit is **not** a claim that live addon routes accept that
size; Phase 4 must fragment/rate-limit for the verified route.

## Wire version 1

A message is a concatenation of `decimal-byte-length:field` strings. Leading
zeros in lengths, truncated fields, trailing garbage, too many fields, excessive
lengths and inaccessible types are rejected. At least five fields are required:

| Position | Meaning |
| --- | --- |
| 1 | Version, exactly `1`. Unsupported versions return `unsupported-version` locally and have no effect. |
| 2 | Operation kind. |
| 3 | Operation ID, `verified-peer:sequence` for commands. It carries no identity authority. |
| 4 | Child relationship generation; opaque, not a clock. `pair` uses bootstrap marker `pairing` instead. |
| 5 | Canonical decimal sequence, 1 through 2,147,483,647. |
| 6 onward | Exact operation-specific arguments below. Extra fields are rejected. |

| Kind | Additional fields |
| --- | --- |
| `pair` | Code. Must match intended peer and active invitation, with generation marker `pairing`. |
| `policy` | Channel, `read/send`, grant mode (or `revoke`), absolute expiry or empty, session token or empty, whisper target or empty. `revoke` removes that setting and requires empty expiry/session fields. |
| `add` | Intended guardian, exact pending pairing operation ID, literal `confirm`. |
| `remove` | Guardian to remove, literal `confirm`; use `stop` for the last guardian. |
| `history` | None. Returns an authorization result only; records arrive in Phase 7. |
| `sync` | None. Current guardians can discover the child's current generation even if their saved generation is stale. |
| `ack` | Result string. Response only, never a command. |
| `state` | Literal `paired`. Response to `sync` with the current generation. |

The child accepts policy/history/membership commands only from current guardians
in the exact current generation. A `sync` requires current guardian identity even
though it accepts a stale generation. Unauthorized/malformed traffic has no
response on the wire. Authorized commands return result acknowledgements;
accepted pairing offers acknowledge `confirmation-required`, which is **not**
pairing completion. After confirmed membership changes guardians must `sync`. Pairing uses a
bootstrap marker so that a previously revoked guardian can explicitly re-pair
with a new invitation without knowing the new generation.
A response is accepted only from the intended transport peer for an outstanding
operation with matching sequence (and matching generation for acknowledgements).
Replies cannot execute commands. Out-of-order replies cannot replace newer
per-child status. Guardian child records contain generation and result, not
shared policy tables. Pending/delivered/retried UI states remain Phase 4 work.

The child persists a sliding 64-operation replay window per guardian in the
profile. Within a generation, identical retries return the original result
without reapplying, and the same sequence with different bytes is a collision.
Older-than-window traffic is rejected rather than forgotten and reapplied.
Distinct operations within the window apply in arrival order. The monotonic
sender sequence is also persisted. Reload therefore preserves replay rejection;
pending sends and pairing ceremonies are transient. At sequence exhaustion a
new relationship is needed. Timeouts, retry/backoff and synchronization revisions
are Phase 4 work; 64 outstanding requests bound memory until completion or a
new endpoint session discards pending requests.

## Pairing, membership and reset

1. The child creates an invitation tied to a specific intended verified friend.
   It lasts 120 seconds. Five failed or accepted attempts exhaust an endpoint's
   attempt budget; replacing an invitation does not reset that budget. Reload
   discards the invitation and pending confirmation, as well as the budget.
2. A matching offer consumes the code immediately and records the exact peer,
   operation ID and deadline. Exact duplicates of that pending offer return the
   same confirmation acknowledgement; they do not create another pairing or
   extend the deadline. Knowing the code grants neither policy nor history
   access. First pairing requires local child confirmation of those details
   before the original deadline, with friendship checked again.
3. First confirmation installs membership, a fresh generation and closed policy
   together. Unpaired policy remains unrestricted until this confirmation.
4. For an already supervised child, local confirmation cannot add a guardian.
   A current guardian must send `add` naming that exact pending peer/operation
   and confirming it. The child rechecks friendship and expiry. Existing policy
   is retained. Either current guardian may edit policy or remove another.
5. Every addition/removal rotates the generation. Removing the last guardian
   needs the distinct `stop` confirmation and restores unrestricted unpaired
   state. Explicit local `FamilyReset` also handles stop/recovery; it never
   happens automatically on corruption, missing identity or delivery failure.
6. Rotation/reset clears child replay/delivery/request work and pending pairing.
   Simulator membership changes also discard queued packets for that child.
   Delayed old-generation messages remain invalid even if they arrive through
   an external queue. Reset/re-pair never restores old membership.

History is only an authorization gate in this phase: `history` returns
`history-authorized` without any chat data. Future history delivery must call
`FamilyCanDeliver` again **when sending every batch**, including previously
queued work. A prior successful history request is never a lasting capability.
Tests cover this revocation gate; history capture, records and viewers remain
Phase 7 work. The model protects against unrelated players, not local addon or
SavedVariables modification by a cooperative child.

## One-client walkthrough

Use the same staging tool as Phase 2, from the Guardian directory:

```sh
python3 scripts/phase2_simulator.py install
```

Restart/reload the client as described in [Phase 2](PHASE2_SIMULATOR.md). Run:

```text
/guardiansim reset
/guardiansim family-reset
/guardiansim check child party read
/guardiansim invite child parent 12345678
/guardiansim pair parent child 12345678
/guardiansim pump
/guardiansim pending child
/guardiansim confirm child parent parent:1 confirm
/guardiansim check child party read
/guardiansim sync parent child
/guardiansim pump
/guardiansim grant parent child party read indefinite
/guardiansim pump
/guardiansim check child party read
/guardiansim check child party send
/guardiansim check child2 party read
```

Fresh `child` starts unrestricted. `pending` shows `parent parent:1`; pairing
confirmation closes permissions. The grant opens party read only. Unpaired
`child2` stays unrestricted, with its own independent state. The legacy `reset`
without `family-reset` still supplies pre-paired Phase 2 fixtures.

Continue with a second guardian:

```text
/guardiansim invite child parent2 87654321
/guardiansim pair parent2 child 87654321
/guardiansim pump
/guardiansim pending child
/guardiansim confirm child parent2 parent2:1 confirm
/guardiansim add parent child parent2 parent2:1 confirm
/guardiansim pump
/guardiansim sync parent2 child
/guardiansim pump
/guardiansim remove parent2 child parent confirm
/guardiansim pump
/guardiansim history parent child
/guardiansim pump
/guardiansim sync parent2 child
/guardiansim pump
/guardiansim remove parent2 child parent2 confirm
/guardiansim pump
/guardiansim remove parent2 child parent2 stop
/guardiansim pump
/guardiansim check child party send
```

The local second confirmation reports `guardian-approval-required`. The `add`
from the existing guardian succeeds. Removed `parent` gets `unauthorized` for
history. Last removal with `confirm` reports `stop-confirmation-required`;
`stop` succeeds and the final send check is unrestricted. `stop child confirm`
is also an explicit local stop/recovery command.

Codes/operation numbers above assume this exact fresh walkthrough. Use `pending`
after changing steps, because operation IDs increase on every request. Additional
commands: `friend CHILD PEER on/off` controls the trusted synthetic friendship
map; `delay`, `loss`, `duplicate`, `connect`, `clock`, `advance` and indexed `pump`
work as in Phase 2. `reload`/`login` reconstruct an endpoint, discard transient
pairing/sends, and preserve durable membership, replay state and sender sequence.
Simulator replies are handled synchronously at successful delivery when the
sender is reachable; acknowledgement delay/loss/retry is not yet simulated.

`revoke PARENT CHILD CHANNEL read|send [TARGET]` removes a grant through the
same policy protocol. Repeat pairing with `child2` to test independent guardian child records. Advance
120 seconds before confirmation to test expiry; send a wrong code five times to
test lockout; revoke a guardian with delayed work queued to test invalidation.
All controls affect isolated memory. They never send live addon messages or
read/write `GuardianDB` or live namespace settings. No Phase 3 client walkthrough
has been run by the implementation agent.

After use:

```sh
python3 scripts/phase2_simulator.py remove
make check
```

Reload to remove the staged command. Development assets remain excluded from
both zip and CurseForge packages. Automated Lua 5.1 tests exercise the wire codec,
actual production operations and the command walkthrough under a strict global
sandbox. These establish logic, not live friendship/authentication, taint,
combat-lockdown behavior or two-client delivery.
