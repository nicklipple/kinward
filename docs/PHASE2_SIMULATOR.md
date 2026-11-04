# Single-client policy simulator

Current user-facing pairing is [name request and one-click acceptance](PAIRING.md).
Older code/operation-entry procedures below remain diagnostic regression fixtures;
the normal Family UI no longer requires them.

Phase 2 provides synthetic `parent`, `parent2`, `child`, and `child2` endpoints.
Each owns independent production profiles; children begin paired to both fixture
guardians with closed defaults. These fixtures bypass pairing ceremonies. The transport now routes grants through the production Phase 3 decoder and
authorization logic. Use [the Phase 3 walkthrough](PHASE3_PROTOCOL.md) and
`family-reset` for actual simulated pairing; these legacy fixtures skip it.
There is no live route or child permission-request system.

From the Kinward directory, explicitly stage the development harness:

```sh
python3 scripts/phase2_simulator.py install
```

The shared TOC declares Forever `16001` and Retail `120105` (the user's reported
Retail build is `70783`). After an interface/TOC change, fully exit and restart
the game so addon discovery rescans the files. Enable Kinward, then run:

```text
/kinwardsim reset
/kinwardsim check child party read
/kinwardsim grant parent child party read duration 900
/kinwardsim pump
/kinwardsim check child party read
/kinwardsim check child party send
/kinwardsim check child2 party read
/kinwardsim advance 900
/kinwardsim check child party read
/kinwardsim grant parent2 child whisper-character read indefinite 0 Friend-TestRealm
/kinwardsim pump
/kinwardsim check child whisper send Friend-TestRealm
```

The first check is false, applied party read becomes true, send/other child stay
false, and read expires after 900 seconds. The explicit whisper grant works in
both directions. Every output is labeled `Kinward SIM`. Account-whisper fixtures
use `whisper-account` with target `friend`; checks require both
`Friend-TestRealm friend`. The guardian fixture is `Kinward-TestRealm parent`.
No text bodies or personal account information are used.

`grant SENDER RECIPIENT CHANNEL read|send MODE [SECONDS] [TARGET]` uses
`indefinite`, `duration`, or `session`. When specifying a whisper target, supply
`0` as the unused seconds placeholder for indefinite/session grants. Grants are
created using the recipient's fixture clock/session at enqueue time: delivery
latency consumes a duration; a login before delivery invalidates a session grant.
This is a simulator convention, not a delivery-start promise for the future UI.

Transport and lifecycle controls:

| Command after `/kinwardsim` | Effect |
| --- | --- |
| `delay 10` | Set delay in seconds for future packets. |
| `advance 10` | Advance shared time, including while endpoints are disconnected. |
| `pump [INDEX]` | Deliver one eligible packet; choose an index for reordering. |
| `loss on/off` | Drop future packets while reporting a simulated send attempt. |
| `duplicate on/off` | Queue two independent copies of future packets. |
| `connect child off/on` | Disconnect/reconnect destination; pending packets wait. A disconnected sender cannot enqueue. |
| `clock child 30` | Set endpoint clock offset in seconds. |
| `reload child` | Retain login token and grants. |
| `login child` | Replace login token; session grants cease to apply. |
| `status` | Show shared time and queue count. |
| `reset` | Discard simulator state and create fresh fixtures. |

The queue is bounded at 64 packets. Phase 3 adds persisted operation IDs,
deduplication and acknowledgements through shared production logic. Duplicate
writes do not reapply; distinct writes use arrival order. Retry/backoff and
per-setting revisions remain Phase 4 work. Parent and child
profiles, including extra fixtures, share no policy tables. The harness never
reads/writes `KinwardDB` or `ns.settings`, never calls live transport, and stores
nothing across a real UI reload. `reload`/`login` commands discard transient pairing/sends while preserving durable
protocol state, and simulate lifecycle;
they are not measurements of the actual client lifecycle.

Remove staging after use:

```sh
python3 scripts/phase2_simulator.py remove
make check
make package
```

Reload the client again to remove the slash command. The manifest refuses checks
and local packaging while staged; `.pkgmeta` excludes both the source under
`scripts/` and staged `Phase2Simulator.lua`. Staging is reversible and leaves
live SavedVariables untouched. Automated Lua tests execute the same harness in
a sandbox that rejects saved-variable reads and all WoW APIs except the existing
slash/output boundary. The user reported positive feedback ("lgtm") after the Retail checklist on
2026-11-03; individual outputs were not captured. See
[the result ledger](PHASE1_RESULTS.md). Forever simulator loading remains
unverified.


Phase 4 adds an independent `network-reset`/`network`/`network-pump` mode using
production fragmentation, receipts and delayed/lost application replies. See
[the network dashboard walkthrough](PHASE4_TRANSPORT.md). Original commands above
retain their existing simulator; the two models never share live state.


With the harness staged, `/kinward demo` opens the visual single-session demo.
Endpoint-switch buttons and automatic time advancement replace manual pumping
for interactive testing. The Family and Permissions tabs use production pairing,
confirmation and policy actions; outage buttons test loss and expiry. See the
[visual walkthrough](PHASE4_TRANSPORT.md#visual-one-session-demo). This remains
synthetic and cannot verify actual chat enforcement or remote routing.


Phase 5 adds `network-chat ENDPOINT read|send CHANNEL CHARACTER ACCOUNT LINE_ID`,
`network-reload ENDPOINT` and `network-login ENDPOINT`. These use independent
production Chat instances for network profiles, with fixture time/identity only.
See [the chat walkthrough](PHASE5_CHAT.md) for paired grant/revoke scenarios.
They never send or filter live chat and cannot verify actual session flags.


Phase 6 adds the visual Requests tab to each network endpoint and command actions
`request CHANNEL read|send TARGET|- REASON`, `requests CHILD`,
`decide CHILD REQUEST_ID approve|deny MODE|- SECONDS|-` and
`cancel-request REQUEST_ID`. Sender-only prompts use the endpoint's production
Chat instance; no message body enters the model. See [requests and temporary
approvals](PHASE6_REQUESTS.md) for offline, expiry, cancellation and approval demos.


Phase 7 adds a guardian-only Activity tab with per-child filtering and cursor
catchup. Add sample chat injects synthetic accessible messages into the selected
fixture child's production history model, never live chat or KinwardDB.
Connection retains diagnostics. [The history walkthrough](PHASE7_HISTORY.md)
covers privacy, outages, retention and revocation during transfer.
