# Phase 7 monitoring and bounded history

Shared storage/capture, authenticated catchup and the guardian Activity browser
are implemented. **Live capture/delivery and actual client coverage remain
unverified.** Core does not activate either candidate adapter. Prior Phase 1,
Phase 4 and Phase 5 bootstrap/identity/routing/enforcement gates remain open.
No actual game client or two-account test was run.

Activity is the child chat viewer for guardians. Connection keeps diagnostics;
Requests keeps access decisions. The isolated demo shares the production history
logic but contains synthetic profiles/messages only.

## Capture and dispositions

`HistoryCapture.lua` receives only accessible metadata/text from `WoWChat.lua`.
It does not call game APIs. The candidate covers ordinary incoming whispers and
party/party-leader filters, supported ordinary WHISPER/PARTY send calls and local
whisper-output events. No say/yell, guild/raid/instance/public, Battle.net chat,
bubbles, voice, TTS, separate-window or alternate-UI coverage is newly claimed.

| Disposition | Meaning |
| --- | --- |
| `allowed` | Accessible incoming text allowed by current read policy |
| `blocked` | Accessible incoming text discarded on the supported filter path |
| `blocked-attempt` | Intercepted send prevented before the original function call |
| `attempted` | Send passed toward the original function; output unconfirmed |
| `output` | A local output event was observed; **not a remote delivery receipt** |
| `gap` | Fixed description of unavailable or ambiguous capture, without inaccessible data |

Records carry source sequence, timestamp, direction, stable channel key,
accessible normalized character/current verified account when available, disposition,
text, interval end and truncation flag. Missing identity remains unknown. Character
names do not prove account ownership. Account mapping still needs P1-ID evidence.

Incoming capture deduplicates channel/line IDs in a 256-entry transient window,
independent of policy decision caching. Missing usable IDs skip capture and emit
at most one fixed gap per ten seconds; no content hash guesses uniqueness.
Repeated filter callbacks neither duplicate records nor reveal incoming text
through notices. Existing sender-only request prompts are unchanged.

Allowed sends are held for a two-second correlation window, up to 64 entries.
A single matching accessible text/channel/target and local echo yields one
`output` record instead of separate attempt/output records. Without an echo,
flush writes `attempted`; an original send error is still only an attempt.
Normal PLAYER_LOGOUT flushes pending attempts before saved-state persistence.
An abrupt crash can lose a transient final attempt; restart always marks the
preceding interval/in-flight-send uncertainty instead of asserting completeness.
Identical concurrent sends, truncated comparisons and matches to the last 64
flushed attempts within 60 seconds produce a correlation gap rather than
inventing confirmed output. Unmatched output events are independent observations
of potentially uncovered sends. Matching cannot prove engine/receiver behavior;
changed text, late echoes and uncovered paths can remain uncorrelated. No universal
once-per-physical-message claim is made beyond the supported dedup/correlation
window. Local observed output never proves remote receipt.

Party self echoes require `KinwardChatIO.selfCharacter()` to supply a verified
current character-realm key. The boundary normalizes it, guards inaccessible
values and compares it with accessible sender identity. Self echoes feed outgoing
observation even if party read is closed; other party members feed incoming
capture. Without enough verified local/sender identity, party capture records a
coverage gap instead of misclassifying an echo. A future verified live bootstrap
must supply that identity; no new identity API or guessed local name was added.

The candidate checks `canaccessvalue` **before** any text/identity comparison,
conversion or persistence. An inaccessible value becomes nil at the boundary;
the pure capture module receives a fixed gap, never the secret. Accessible text
is capped at **256 bytes**, with visible truncation metadata. Pending captures and
recent-correlation entries are bounded and transient. Stopping supervision clears
retained source history; old pending captures cannot cross a relationship reset.

The known pinned filter limitation still applies: when inaccessible arguments
cause the engine to skip insecure callbacks, this addon cannot capture that
message, suppress it or emit a per-message gap. The candidate's one-second
`InChatMessagingLockdown` heartbeat marks a **potential unavailable interval**;
it cannot enumerate skipped messages or cover every unobservable surface.
Startup/reload gaps use persisted last-seen time. Interval records retain start
and end, and overlap time-window filters correctly. Adapter stop records an end
notice. These are coverage indicators, not evidence that nothing happened.

## Persistence, retention and configuration

`History.lua` is pure storage/validation, batch and viewer logic. New optional
schema-1 fields are additive:

- Child `history`: relationship generation, bounded record array, monotonically
  increasing `high`, cumulative count-pruned/expired totals, retention seconds,
  maximum rows and last monitoring heartbeat.
- Kinward `childProfiles[peer].history`: validated received records plus durable
  catchup cursor, source high watermark/loss totals/configuration, last fetch and
  separate local cache-removal count.

Development defaults are **seven days / 10,000 records per child**. These remain
proposed release defaults to confirm before publishing. Guardians can configure
retention/count in Activity; the pure validator supports 60 seconds–30 days and
1–10,000 rows. Lower limits prune retained source data immediately. Source and
guardian caches are separately bounded; limits apply per child, at most the
existing sixteen child profiles. Count loss, expiry, byte truncation and missing
intervals remain visible rather than pretending a complete transcript.

Retention uses interval end timestamps. Expiry and count removal discard a
sequence prefix, preserving resumable cursors; nearby out-of-order send timestamps
can conservatively remove additional preceding rows, included in loss totals.
Core prunes normalized source/cached data on its own ADDON_LOADED using the
already evidenced server clock. Active monitor heartbeats, history polls and
viewer reads also prune. Offline time therefore counts toward retention. No WoW
calls occur when the new modules are loaded.

Stored arrays, sequences, limits, timestamps and dispositions are strictly
validated. Malformed paired history or guardian caches enter recovery; valid
older profiles without history migrate without losing supervision. Source
record sequences must agree with retained rows and cumulative loss counts.
Sequence exhaustion stops new records rather than reusing IDs. Removing all
SavedVariables is outside the cooperative trust model and is not authenticated
recovery; an unexpected source cursor reset requires investigation rather than
automatic authority restoration.

Adding/removing a guardian rotates family generation. Retained source records
can be fetched under the new current authorization; guardian caches reset with
the generation and fetch afresh. A newly approved guardian can review retained
history after approval. Merely knowing a pairing code cannot fetch it. Removing
the last guardian/reset clears source history, so a later re-pair does not expose
the prior supervision's records. Data already legitimately received cannot be
remotely erased by revocation.

## Delivery and priority

History uses the existing authenticated bounded transport, never a new service.
A guardian opening Activity watches that selected child; received cursors persist
across reload. Watched children continue polling every five seconds while the
candidate transport or simulator driver runs, including after switching tabs.
Without a view/watch, records remain on the child for later catchup. Both endpoints
must be reachable; there is no offline server delivery. Reconnect resumes at the
last accepted cursor and reports any retention gap.

`history` takes one field after the existing five-field envelope: last received
source cursor (zero initially). A `history-batch` reply contains:

```text
1..5   existing envelope: version/kind/operation/generation/sequence
6..13  requested cursor, next cursor, source high, oldest retained sequence,
       cumulative count-pruned, cumulative expired, retention seconds, max rows
14..   up to three records, eleven fields each:
       sequence, time, direction, channel, character, account, disposition,
       body hex part 1, body hex part 2, interval end, truncation flag (0/1)
```

Only `history-batch` may use up to 46 atoms; other operations remain capped at 16.
The existing 256-byte atom and 2048-byte total limits remain. Bodies use hex to
round-trip controls/newlines without weakening the existing protocol decoder;
a 256-byte body uses at most two atoms. Batches shrink to fit total wire size.
Existing 180-byte fragments/12-fragment assembly, sender rate limit, retry and
backoff bounds apply. Legacy five-field history authorization remains supported
for the older simulator; it returns no content.

The guardian validates the full batch before mutation: exact child/operation/
sequence/request cursor/generation/deadline, current recorded membership, limits,
loss counters, consecutive returned source sequences and every record. Accepted
cursor advances atomically with records. Repeated, reordered, malformed or
unsolicited batches cannot append duplicates or advance another child's cursor.
Empty replies can advance past a fully expired prefix and report its loss.

Only a current approved guardian/generation can request history. Source replies
are authorized **again before every queued fragment send**, including after a
membership change. An old queued response is cancelled, with no payload-identity
fallback. Already transmitted bytes cannot be retracted. Receiver authorization
also checks its current membership/generation view before inserting records.

History request/reply work runs after pairing, policy, acknowledgements and
request traffic. There are at most **16 active history jobs**, a **48-entry queue
ceiling for new history work**, and the ordinary **64-entry control ceiling**;
terminal jobs can be reclaimed. This reserves control capacity instead of queuing
10,000 records individually. One active watched fetch per child bounds catchup;
large backlogs can take substantial time at the shared send rate. Control traffic
can delay history and history deadlines can expire; progress must not imply
instant or guaranteed-complete delivery.

`history-config` is an authenticated replay-protected mutation with retention,
count and absolute deadline. It changes retention, not chat permission or policy
revision. The UI uses a 60-second delivery deadline. Metadata from later batches
shows the child's applied limits; queued configuration is not shown as applied.

## Kinward and child UI

Activity is visible only on guardian dashboards. It displays twenty matching
records per page, newest by time, then sequence. Controls cycle channel,
incoming/outgoing/system, disposition and retained/all/15m/hour/24h/7d windows.
The conversation field filters accessible character/BattleTag substrings. Each
record shows local date/time, channel, identity, disposition, body and truncation
or interval information. Source cursor/high, reachability, retention and loss
counts show catchup/gaps; they do not imply complete monitoring while unreachable.
Connection retains diagnostic states without message bodies.

Child dashboards show whether monitoring is active on supported routes; they do
not create an Activity view with their retained source text. Hidden Activity text
is cleared for child roles. The sender-only request prompt never consumes a body.
Diagnostic `/kinward`/Connection and synthetic injection do not print hidden
history. Source history still exists in local SavedVariables: this cooperative
addon does not prevent inspecting or modifying local files/addon code.

All user-provided/history text passes through literal UI escaping. Formatting
codes and hyperlinks cannot execute by being rendered as raw chat markup.
`PLAYER_LOGOUT` uses the already pinned
`Blizzard_APIDocumentationGenerated/SystemDocumentation.lua` event evidence.
`Activity.lua` owns the viewer closure separately to respect Lua 5.1's sixty-upvalue
limit; it uses the existing frame/widget API set. `date(format, timestamp)` is the
only newly used WoW Lua symbol, evidenced by pinned
`reference/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/TimeUtil.lua` lines 47–53
at Forever commit `17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c`. It formats already
validated ordinary timestamps. Other APIs, including the server clock, restriction
flag and widgets, have Phase 4/5 evidence. No permissive annotations/globals,
new library or runtime service were introduced.

## One-client walkthrough

1. Stage with `python3 scripts/phase2_simulator.py install`, reload, then
   `/kinward demo`. Pair parent/child with Family and sync as in Phase 4.
2. On parent, select child and open **Activity**. Click **Add sample chat**, then
   **Refresh history**. Synthetic party/whisper lines, a send disposition and a
   gap appear after transport ticks. The fixture clock is synthetic, so rendered
   dates reflect fixture time, not the real calendar. No real chat is sent/captured.
3. Cycle channels/outcomes/time, search `stranger`, and browse Older/Newer. Change
   selected child; rows remain separate. Switch to child: Activity is absent,
   monitoring is marked SIMULATION, and no blocked sample body appears in widgets.
4. Toggle the child link/packet loss, add more samples, then reconnect. History
   resumes at its cursor. Policy and Requests actions still deliver during backlog.
5. Apply a small history row limit in Activity and add samples. Observe count-loss
   totals and cursor progress. Change retention days only on synthetic profiles.
6. Pair parent2 and exercise revocation during catchup. Newly queued fragments
   cannot go to the removed guardian. Stop/re-pair starts without prior source
   history. Connection continues to show diagnostics only.

Remove the harness with `python3 scripts/phase2_simulator.py remove`, reload, and
run checks/package. Staged development files are rejected for distribution.

## Automated and client acceptance

Strict Lua 5.1 scenarios exercise allowed/blocked reads, pre-send attempts and
correlation, real candidate callback boundaries with throwing secret sentinels,
intervals, retention/count bounds, malformed persistence/protocol, cursor resume,
loss/duplicates/reconnect, authorized-only access, queued revocation, child/kinward
isolation, control priority/capacity and actual Activity widget handlers. Prior
phase suites, formatting, zero-diagnostic LuaLS and manifest checks remain required.
The package contains runtime files only. These tests cannot establish engine
filter coverage, taint, secret-state behavior or real delivery.

Once the earlier live gates/bootstrap are verified, test consenting real accounts
for supported incoming/outgoing allowed and blocked paths, separate windows,
identity changes, duplicate callbacks, reload/alt changes, offline retention,
parent disconnect/catchup, two guardians and revocation between fragments. Confirm
blocked bodies appear only in the guardian viewer and never in child widgets,
prompts, debug output, TTS or other accessible surfaces. Check actual lockdown,
errors/taint/protected actions and all known uncovered routes. Mark unavailable
coverage explicitly and record Forever and Retail results separately in
PHASE1_RESULTS.md. **No such client result is claimed by Phase 7 implementation.**

## Activity chat presentation

Activity renders each page in chronological chat order, with date separators,
short timestamps, channel colors and sender/recipient prefixes. Blocked reads,
blocked sends, send attempts, local output and capture gaps keep explicit labels;
local output still does not establish delivery. Captured text escapes pipes and
flattens line breaks before trusted color markup is applied. Paging and filters
still operate over the same retained history.

The font object `ChatFontNormal` is evidenced in the pinned Forever source at
`Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameEditBox.xml` and
`ChatFrameOverrides.lua`. The dark chat background uses the existing evidenced
texture methods. Actual font rendering, wrapping and scrolling require client
verification.

The channel filter uses WoW's native `DropdownButton` with
`WowStyle1DropdownTemplate`: click to open the channel list, then select any
channel directly. The selected channel appears on the control and changing it
resets history paging. Other filters and conversation search remain active.
The native menu owns selection indicators, dismissal and keyboard behavior.
Pinned Forever evidence: `Blizzard_Menu/11_0_0_MenuImplementationGuide.lua`
(CreateFrame example, radio selection and automatic selection text),
`Blizzard_Menu/DropdownButton.lua` (`SetupMenu`), and
`Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua` (`CreateRadio` usage).
Actual dropdown placement and interaction still require in-game verification.

## Expanded player text routes and history pacing

The adapter now handles Say, Yell, party, raid, instance, guild, officer,
character and Battle.net whispers, emotes, public/custom channel messages, and
community messages rendered through chat frames. Named custom channels can
inherit the Custom channels setting or override either direction explicitly.
Outgoing community and Battle.net messages use their corresponding API wrappers.
Activity can select the expanded categories and captured custom-channel names.

Transport deadlines still use server epoch time; packet spacing now uses the
subsecond `GetTimePreciseSec` clock. Empty pairing-candidate polls back off to
30 seconds. A two-client mocked regression uses integer server time and verifies
that 18 blocked Say messages reach the guardian while background polls run.

The native Communities window directly renders club messages outside the chat
frame filter, and voice, inaccessible/secret values and other engine paths are
not established coverage. In-game testing is still required; this change does not
claim those surfaces are blocked or captured.

Pinned Forever evidence: `Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua`
for chat/Battle.net send routes; `ChatFrameUtil.lua` for channel event arguments;
`Blizzard_APIDocumentationGenerated/BattleNetDocumentation.lua` for
`GetAccountInfoByID` and `SendWhisper`; `ClubDocumentation.lua` for
`C_Club.SendMessage`; `ChatInfoDocumentation.lua` for channel info and events;
`Blizzard_Communities/CommunitiesChatFrame.lua` for the separate native window;
and `Blizzard_Console/Blizzard_Console.lua` for `GetTimePreciseSec`.
