# Account profile schema 1

`GuardianDB` is initialized only on Guardian's `ADDON_LOADED`. `Profile.lua`
normalizes persisted data; `Policy.lua` and `Session.lua` have no WoW calls.
The account-wide profile is shared by all local characters. `enabled` remains a
legacy preference and never bypasses supervised policy evaluation.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer 1; unknown versions enter recovery. |
| `role` | `unset`, `guardian`, or `child`. |
| `supervision` | `unpaired`, `paired`, or `recovery`. |
| `generation` | Nonempty bounded relationship-generation token. Phase 3 creates relationship generations with an injected fresh-token supplier; `initial` is a fresh scaffold marker only. |
| `guardians`, `children` | Maps of stable account identifiers to `true`; no numeric live Battle.net handles. A paired child requires one to eight guardians; child destinations are bounded at 16. |
| `policy.channels[key].read/send` | Independent grants. Omitted directions are closed when paired. Use stable keys (`party`, `raid`, `channel:general`, etc.); never transient channel numbers. |
| `policy.whispers[key]` | Grant with `kind = character/account` and `target`; permits both read and send. Map keys are local record IDs. |
| `queues.requests/delivery` | Up to 64 opaque work-ID strings each, 1–128 bytes. Only the first 64 slots are considered; malformed entries are discarded. Payload/state machines arrive in later phases. |
| `familyReplay` | Up to eight guardian replay ledgers. Each contains `high` and up to 64 sequence-keyed `{wire, result}` entries. Preserved across reload; cleared on generation rotation. |
| `familySequence` | Up to 16 destination sequence counters, preserved across reload and never reset within a relationship generation. |
| `childProfiles` | Up to 16 independent guardian-side records keyed by verified child identity: `generation`, `result`, optional latest `replySequence`. |
| `sessionId` | Optional adapter-supplied login token. Reload reuses it; a new login replaces it. |
| `damaged` | Original malformed state retained for explicit recovery. Repeated normalization retains the same original instead of nesting it. |

A grant has `mode = indefinite`, `mode = duration` with a finite positive absolute
`expiresAt`, or `mode = session` with a nonempty `sessionId`. Explicit durations
are measured in seconds from the injected creation clock. They expire exactly at
`now >= expiresAt`; offline time counts. No clock synchronization or tamper
resistance is promised. Revocation removes a grant. There is no conversation or
implicit channel-wide whisper approval.

Only absent (`nil`) data and the old scaffold table (no new schema fields) migrate
to unrestricted initial state. Legacy `enabled` and unknown fields are preserved.
Valid version-1 tables retain membership, generation, grants and unknown fields.
Malformed scalars, incomplete paired profiles, invalid grants and unknown schemas
produce a restricted recovery profile with the original in `damaged`. Recovery
must be resolved explicitly; Phase 3 provides a confirmed local recovery reset,
with no automatic reset or authority restoration. Optional Phase 3 fields are
initialized for existing valid schema-1 profiles; malformed authority ledgers
fail closed. This additive migration preserves Phase 2 policy/membership. Deleting SavedVariables remains outside the cooperative trust model.

Character grants require a realm. Keys use bytewise lowercase and remove spaces,
apostrophes and hyphens from realm spelling; character punctuation is rejected.
Lua 5.1 lowercase is not Unicode case folding. Non-ASCII names must use the same
client spelling until a verified identity adapter supplies canonical identities.
Never assume a local realm for a realm-less name.

An account grant or guardian whisper bypass requires both a character and an
account claim matching `context.accounts[normalizedCharacter]`. This map is
trusted input supplied by a future verified adapter, never a sender payload.
Unknown/ambiguous identity fails closed. `CanControl` additionally checks current
membership and generation; Phase 3 supplies shared protocol authorization with transport identity injected
by the future live adapter. See [the protocol](PHASE3_PROTOCOL.md). Ordinary
channel approval does not permit control operations or whispers.

The production evaluator is ready for adapters. Runtime does not yet infer
login versus reload, resolve live identity, send policy messages, or intercept
chat. Phase 1 live evidence and Phases 4–5 remain required before enforcement.


Phase 4 adds optional `policyRevision` (nonnegative bounded integer) and replay
entry `revision` values, retaining schema 1 compatibility. Guardian child records
may cache `revision`, current `members` (at most eight) and `settings` (at most
128 typed grant/revocation views with child revisions). These are display data,
not authority. Malformed caches enter recovery consistently with other malformed
profile data. Missing additive fields are accepted. Transport queues, packet IDs,
reassembly, contacts and partial snapshots are never persisted; sender sequences
and accepted child policy/replay state survive reload.
