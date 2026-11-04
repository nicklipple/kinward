# Phase 5 chat-control slice

Candidate implementation is available for ordinary whispers and party chat.
**Live activation and two-account acceptance remain unverified.** No client was
run. Core does not install the candidate adapter: P1-IN, P1-OUT, P1-ID and
P1-SESSION must establish the actual supported boundaries first. Phase 4's
pairing/routing gate also remains open. A passing simulator is not parental
control over actual chat.

## Implementation and integration contract

`Chat.lua` is pure and receives a profile and a context supplier. `WoWChat.lua`
provides the candidate incoming filters, outgoing wrapper, current friendship
resolver and lifecycle driver. They load after Dashboard and before Settings/Core;
loading declares functions only. The existing own-ADDON_LOADED initialization
continues to normalize saved variables before anything may use them.

A future verified bootstrap calls `NewWoWChat(profile, io, verified)` on that
initialization path, before supported chat is available. False returns
`chat-client-unverified` without any WoW API calls. There is no slash command or
saved preference that bypasses acceptance. As with the transport adapter, this
argument is an integration contract, not protection against local modification.
The future bootstrap must supply:

- `io.account(characterKey)`: current, accessible, unambiguous, verified
  Battle.net friendship mapping or nil. `ResolveWoWChatAccount` is the candidate
  source-based implementation; its mapping still requires P1-ID client evidence.
- `io.freshSession()`: an accessible, nonempty, at-most-128-byte token that has
  never been used for another login. Local identity/token bootstrap remains
  unresolved. Fixture tokens cannot be used as live credentials.

At most one candidate adapter may be active. Stop removes exactly its filters
and event handler, restores the outgoing field if still owned, and is idempotent.
If another addon wrapped it, the inactive closure passes through and teardown
reports that reload is required. Reload is also needed to clear taint. Disabling
the sample `enabled` preference cannot bypass an installed policy.

## Decisions, identity and lifecycle

- Incoming registrations cover `CHAT_MSG_WHISPER`, `CHAT_MSG_PARTY` and
  `CHAT_MSG_PARTY_LEADER`. Party leader messages share party permission. A blocked
  callback returns true; it never prints, persists or otherwise inspects text.
- Read decisions use channel plus accessible positive line ID. The latest 256
  unique lines retain the same decision across window callbacks, including
  callbacks that straddle an edit. Later messages evaluate current policy/time.
  Missing/inaccessible IDs still evaluate display permission, but produce no
  once-only bookkeeping. No text/name hash is used. Evicted IDs cannot provide
  unlimited replay deduplication. No prompts or history records are implemented.
- Outgoing interception covers current calls through
  `C_ChatInfo.SendChatMessage` for `WHISPER` and `PARTY`. It decides before calling
  the original function. Blocked sends return without that call and issue a
  generic notice at most once per two seconds, with no text or target in it.
  Unpaired profiles pass through. Other accessible chat types pass through and
  are outside this slice; inaccessible chat types on supervised profiles close.
- Ordinary whisper grants remain bidirectional. Character names are normalized
  with an explicit realm; names without a realm use the candidate engine local
  realm. Unknown, invalid or secret identity cannot satisfy a whisper grant.
  Party permission cannot authorize a whisper. Guardian communication requires
  the same current verified account mapping, never a familiar display name.
- The candidate resolver enumerates up to 200 friends/32 games each, rejecting
  overflow, missing/inaccessible relevant data and conflicting ownership. It
  requires current friendship, an online WoW character on the same project, and
  character/realm fields from that account's engine game record. It persists no
  numeric handles or mappings. Each new decision resolves afresh; friendship
  loss/alt changes cannot reuse a stale mapping. No party membership is consulted.
- Every uncached decision reads current policy and epoch time. No copied policy
  or monitoring/transport status controls enforcement. Loss of parent contact
  retains the last policy; duration grants still expire. Recovery is closed on
  supported paths; an unpaired profile is unrestricted.
- Session grants close until `PLAYER_ENTERING_WORLD` supplies accessible flags.
  Reload reuses a valid saved session ID. Initial login/alt login requests a fresh
  token; ordinary zone transitions preserve it. Invalid/immediately repeated fresh tokens
  fail closed. Reload with no saved token stays closed for session grants.
  `PLAYER_LOGOUT` alone cannot distinguish reload, so it is not used to rotate
  tokens. The actual flags and pre-chat installation order remain client tests.

Counters deliberately distinguish **blocked attempts**, **attempts passed to the
original function**, and **observed local whisper output events**. Errors from
the original function propagate and remain attempts. `CHAT_MSG_WHISPER_INFORM`
observations are deduplicated independently in a 256-entry cache; they may include
output from uncovered routes. They are not correlated receipts, cannot prove
remote delivery, and do not cover party output confirmation. Incoming party
callbacks may include the child's own echo; that is a read/display decision,
never evidence of outgoing prevention. No message body enters counters/caches.

## Pinned Forever API evidence

All paths are under `reference/blizzard-ui/Interface/AddOns/`, revision
`17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c` (1.60.1.70755).

| Boundary | Source evidence |
| --- | --- |
| Filter add/remove and discard return | `Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua`; consumer `Mainline/ChatFrameOverrides.lua` in the same addon |
| Ordinary send arguments/restrictions | `Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua`, `SendChatMessage`; callers in `Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua` and `SlashCommands.lua` |
| Whisper/party/party-leader and whisper output payloads | `ChatInfoDocumentation.lua`: payload 11 is `lineID` (NeverSecret); playerName is payload 2 |
| Accessible values | `Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua`, `canaccessvalue` |
| Local normalized realm | `Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`, `GetNormalizedRealmName` |
| Friend records and game ownership fields | `Blizzard_APIDocumentationGenerated/BattleNetDocumentation.lua`: `GetFriendAccountInfo`, `GetFriendNumGameAccounts`, `GetFriendGameAccountInfo`, `BNetAccountInfo`, `BNetGameAccountInfo` |
| Friend enumeration/project comparison | `Blizzard_FriendsFrame/Camelot/FriendsFrame.lua`: `BNGetNumFriends`, `WOW_PROJECT_ID` |
| Session flags/epoch clock | `Blizzard_APIDocumentationGenerated/SystemDocumentation.lua`, `PLAYER_ENTERING_WORLD`; `SystemTimeDocumentation.lua`, `GetServerTime` |
| Frame events/scripts, construction and print | Existing Core/Phase 4 evidence in ARCHITECTURE.md and PHASE4_TRANSPORT.md |

No new global or permissive annotation correction was needed. Mainline
annotations are analysis aids; these source paths provide availability evidence.

## Known uncovered routes and states

The pinned filter wrapper skips insecure callbacks when arguments are
inaccessible. **In that state this adapter cannot guarantee hiding incoming
text or recording a gap**, because it is not called. A deny decision in a mock
callback does not fix that engine limitation. Other filters can also affect
ordering and arguments. Scope must be resolved if actual restrictions defeat
core protection.

Replacing the current send field cannot block cached original references,
secure/engine sends, other chat APIs or addon code that replaces the wrapper.
Post-send echoes never prove prevention. The API is restricted/taint-sensitive;
wrapping must be tested rather than assumed safe in combat or macro paths.
Battle.net whispers, say/yell/emotes, guild/raid/instance/public chat, communities,
bubbles, TTS, voice and transcription remain uncovered. Separate whisper windows,
ElvUI and other alternate UI paths require independent observation. No global
chat coverage, tamper resistance or history capture is claimed.

## Single-client fixture walkthrough

Stage with `python3 scripts/phase2_simulator.py install`, then reload. Use the
Phase 4 visual demo (`/guardian demo`) or its documented network commands to pair
`parent` and `child` and sync the guardian's child profile. All following chat
commands evaluate fixture metadata only; they never send/filter live chat or
access GuardianDB. `network-chat ENDPOINT read|send CHANNEL CHARACTER ACCOUNT
LINE_ID` accepts `unused` placeholders where identity/line is irrelevant.

1. `/guardiansim network-chat child read party Friend-TestRealm unused 1`
   reports blocked after pairing. Repeat with the same line to exercise dedup.
2. `/guardiansim network parent allow child party read`, then
   `/guardiansim network-pump 5`. Read with line 2 is allowed; send remains blocked.
3. Allow party send separately, pump, and check send. Deny party read, pump, and
   read with line 3; expect blocked while send stays allowed.
4. `/guardiansim network parent allow child whisper-character read Friend-TestRealm`,
   pump, then check whisper read/send with `Friend-TestRealm unused` and new line
   IDs. Both allow; `Stranger-TestRealm` stays blocked despite party permission.
5. `/guardiansim network-connect parent off`: already applied permission continues.
   Reconnect, deny the same whisper target, pump, and check a new line; it blocks.
6. `network-login child` and `network-reload child` exercise injected fixture
   tokens only. Automated tests cover duration/session grants through actual
   candidate lifecycle callbacks as well as offline time and reload.
7. Child2 remains independent. A fresh unpaired endpoint is unrestricted, so pair
   child2 before comparing its closed defaults with child1's granted policy.

Remove with `python3 scripts/phase2_simulator.py remove`, then reload. Staged
harnesses are rejected by release validation. The live dashboard explicitly
labels saved permissions and unverified enforcement.

## Two-account acceptance checklist (pending)

First close the Phase 1/4 identity, route, lifecycle and boundary gates. Record
client flavor/build, window/UI, combat/restriction state and exact route in
PHASE1_RESULTS.md, with separate Forever/Retail results. A future verified
bootstrap must be reviewed and installed before testing this adapter live.

- Pair intended consenting accounts, grant/revoke party read and send
  independently; check incoming text in every relevant window. Repeat for party
  leader and both sides of a whisper-character grant, including same-realm names.
- The remote receiver must confirm blocked outbound markers were **not received**
  while an allowed control marker was received. Exercise normal edit box, /p,
  /w, /r, separate whisper window, macros and addon calls independently. Test
  cached API references/engine paths as uncovered routes, not successful blocks.
- Exercise current guardian communication, friend approval, another account with
  a similar name, unknown/secret identity, friendship removal, ambiguous records
  and alt switches. A party stranger must remain closed for whispers.
- Check policy before first supported chat at login, reload persistence,
  until-logout expiry on new/alt login, duration expiry after offline time,
  revocation while callbacks are active, parent disconnect and reconnect.
- Observe messaging lockdown, combat, errors, protected actions and taint. Check
  known bubbles/TTS/voice/alternate-UI exposure separately. Record skipped-filter
  states as unavailable enforcement; do not count them as passes.

`make check` runs strict Lua 5.1 adapter and network scenarios, zero-diagnostic
LuaLS, formatting, manifest and prior regression suites. `make package` validates
release contents. Neither substitutes for this pending client checklist.


Phase 6 extends the shared Chat decision with bounded sender-only prompts and an
optional candidate `GuardianChatIO.prompt(character)` callback. The fallback
notice includes only accessible sender identity and directs the child to the
Requests UI. No body is passed to either. See PHASE6_REQUESTS.md for preference,
rate limits, approval and integration contracts; the live gates above remain open.


Phase 7 extends the candidate boundary with guardian-only capture after policy
checks, held outgoing attempts/output correlation, current local-identity input
for party self echoes, bounded source/cache history and coverage heartbeats.
The Phase 5 decision/prompt caches still contain no bodies; separate private
history now stores accessible bodies for authorized guardians. Core remains
inactive. PHASE7_HISTORY.md supersedes the original Phase 5 no-capture description
for these added hooks, including the unchanged inaccessible-callback limitation.
