# Reproducing the Phase 1 experiments

These are development experiments, not supervision. Use two consenting test
accounts A and B and harmless text beginning with `GUARDIAN-P1`. Run both ends
in the same target build, first with default UI and only Guardian enabled; repeat
with ElvUI separately if installed. This workspace is currently in Retail;
record Retail separately from Forever, including failed symbol/loading checks.
No client results have been collected yet.

## Setup and cleanup

From the Guardian repository, with no other TOC edits in progress:

```sh
python3 scripts/phase1_probe.py install
```

This stages `Phase1Probe.lua` and appends one marked block to Guardian.toc.
Nothing is active on load except a session-metadata event listener and the
`/guardianprobe` command. In each client enable script errors, record build,
then activate explicitly:

```text
/console scriptErrors 1
/dump GetBuildInfo()
/guardianprobe status
/guardianprobe start
```

`start` resets counters; repeating it while active does nothing. Only marker
text is filtered/prevented; ordinary chat passes through. Probe counts are
callback/boundary invocations, not deduplicated messages or delivery proof.
`status` shows initial-login/reload flags, clocks, messaging lockdown and outgoing
addon restrictions. No bodies are logged, persisted or automatically echoed.
Only explicit `char`/`bn` commands transmit a fixed marker; no automatic replies.
The probe does not replace Battle.net whispers, emote APIs or secure macros.

For every run record errors from the error dialog, blocked/protected action
reports, and taint attributable to the experiment. Optional `/console taintLog 1`
provides a client log; note its original value and restore it afterward. Logs
may contain unrelated private data; copy only the relevant sanitized evidence.
An error is a result, not a reason to bypass a protected action.

Cleanup on both accounts:

```text
/guardianprobe stop
```

Then, from the repository:

```sh
python3 scripts/phase1_probe.py remove
make check
make package
```

Reload both clients. Removal preserves unrelated TOC edits and refuses to erase
an edited staged probe; preserve/reconcile those edits if warned. If another
addon wrapped the probe, `stop` leaves that addon's wrapper in place and prints
a reload requirement. Always reload after cleanup: restoring a Lua field does
not remove taint, cached references, prefix registrations or slash registrations.
Stop also removes the session listener, so install/reload again before another
session experiment. Probe files are excluded from both package systems; local
validation deliberately fails while the probe is staged. Do not run a release
packager against a staged development TOC.

## P1-IN — incoming filter

1. Activate on A; leave B's probe stopped. From B whisper A
   `GUARDIAN-P1 incoming-01`, then `control incoming-02`. Send analogous party
   messages. A should see only control messages in each subscribed chat frame;
   status should count discarded callbacks. Do not equate multiple callbacks
   with multiple received messages.
2. Repeat with several chat tabs, a separate whisper conversation window, and
   Battle.net whisper. Inspect each window, notifications and TTS separately.
   B may send marker Battle.net whispers with its probe active because that
   outgoing API is not wrapped. Keep ordinary whisper outgoing probe stopped on B.
3. Stop on A and repeat; marker text must become visible again. Record each
   covered event/window separately. This proves display filtering only.

## P1-OUT — actual outgoing prevention

Keep B's probe **stopped** so its incoming filter cannot conceal a leaked send.
Activate A. For every route below first send a non-marker control and confirm
B receives it; then attempt a distinct `GUARDIAN-P1 route-N` marker and check
both A's prevented counter and B's actual receipt. Observe both long enough to
rule out normal delivery delay. Any marker received on B is a bypass, regardless
of A's displayed echo or counter. Repeat outside combat, in combat, and in any
observed messaging-lockdown state; the states are not interchangeable.

| Route | Action on A | What the experiment decides |
| --- | --- | --- |
| Normal entry | Select party or whisper B, type marker and Enter | Whether shared send API replacement is reached and permitted |
| Slash types | `/p GUARDIAN-P1 party-01`, `/w Name-Realm GUARDIAN-P1 whisper-01` | Slash normalization and final send coverage |
| Reply/retell | Receive a control whisper, then `/r GUARDIAN-P1 reply-01` and `/t GUARDIAN-P1 retell-01` | Direct reply handler and current recipient coverage |
| Separate window | Open B's whisper window, send marker | Instance edit box versus shared boundary |
| Plain chat macro | Button macro `/p GUARDIAN-P1 macro-01` | Secure command path; do not assume it uses replaceable Lua field |
| Script macro/addon send | `/run C_ChatInfo.SendChatMessage("GUARDIAN-P1 script-01", "WHISPER", nil, "Name-Realm")` | Direct current API reference; errors/restrictions also recorded |
| Cached reference | Before start, `/run GuardianP1CachedSend = C_ChatInfo.SendChatMessage`; after start call it with same arguments | Known wrapper limitation: an earlier captured reference may bypass it. Clear with `/run GuardianP1CachedSend = nil`, then reload |
| Battle.net chat | Send a marker from BNet conversation window | Separate API, outside this wrapper; expected uncovered until tested |
| Emote | `/e GUARDIAN-P1 emote-01` and a built-in emote | Custom text versus `PerformEmote`; record separately |

The optional cached-reference macro creates a temporary developer global only
for that experiment. No post-hook is used: its callback would run after sending.
Do not interpret taint or a protected-call error as successful product
prevention. Acceptance needs at least one explicit route that is actually
prevented on the remote receiver without breaking required chat controls.

## P1-ID — friendship, identity and alt changes

Do this only with the test friendship; do not enumerate unrelated friends.
At each step inspect accessible fields locally and record pseudonyms rather
than real names/BattleTags in the ledger. Never stringify/dump inaccessible
values. An unavailable/nil lookup is a result and cannot authorize identity.

1. Determine the consenting peer's current friend index from the friends UI.
   Inspect `C_BattleNet.GetFriendAccountInfo(index)` and
   `C_BattleNet.GetFriendNumGameAccounts(index)`, then
   `C_BattleNet.GetFriendGameAccountInfo(index, gameIndex)` for each of **that
   peer's** active game accounts. Record field availability: `battleTag`,
   `isFriend`, `bnetAccountID`, `gameAccountID`, `playerGuid`, `characterName`,
   `realmName`, `clientProgram`, `wowProjectID`, `regionID`, `isOnline`,
   `appearOffline`/`isAppearOffline`. Do not use account display names as keys.
2. Cross-check the peer's accessible character GUID with
   `C_BattleNet.GetAccountInfoByGUID(guid)` and
   `C_BattleNet.GetGameAccountInfoByGUID(guid)`. Cross-check current handles with
   `GetAccountInfoByID(id)` and `GetGameAccountInfoByID(id)`. Record nil,
   ambiguity, restrictions and all disagreements rather than guessing ownership.
3. B changes alts, logs out/in and restarts; A reloads and restarts. Re-resolve
   friend index and all numeric handles at every transition. Repeat with a
   second WoW game account under the test Battle.net account if available.
   Record which identity is stable and whether one BNet identity ambiguously
   covers multiple WoW accounts. A stable key is a test result, not an assumption
   about a numeric handle or permanent BattleTag immutability.
4. B appears offline, then exits. Repeat lookups and route sends; also test an
   unavailable GUID/previous handle and friendship removal/re-addition with
   consent. A failed lookup must remain unresolved. Record friend-event names
   printed by the probe and whether changes require refreshing lookups.

## P1-ROUTE — candidate communication paths

Activate both probes; note exact prefix-registration results (0 success,
1 duplicate). On each endpoint:

```text
/guardianprobe char PeerName-PeerRealm
/guardianprobe bn CURRENT_PEER_GAME_ACCOUNT_ID
```

Replace the numeric placeholder using a freshly resolved game-account record
from P1-ID. Run both directions; note send result and the peer's **receive**
event, transport-provided sender, and marker flag. `bn` takes a game-account
handle, not friend index or bnetAccountID. There is no automatic acknowledgement;
separate manual sends in both directions establish bidirectional reachability.

Resolve a BN receive `senderID` through both account/game lookup candidates and
match it to the actual consenting sender. Record which mapping works; do not
trust an identity in a payload. Character event senders must likewise be mapped
to the verified friend. Repeat same/different realms and factions if available,
party versus ungrouped, alt changes, appear-offline, exit/reconnect, unavailable
old target and lockdown. Record nil/exception/enum failure and absence of receive
separately. Do not flood to manufacture throttling; record natural throttle
results if observed. Group-route or fragmentation limits require later tests
before using those features. An empty successful local return is not delivery.

Acceptance requires a working route plus a reliable transport-sender mapping
to the intended current friend, not just a loopback or receipt of arbitrary data.

## P1-SESSION and P1-LOCK — sessions, clocks and restricted data

1. Install probe before login. Run status at initial login, after a zone change,
   after `/reload`, and after logout/login. Repeat restart and abrupt disconnect
   where practical. Status reads entering-world flags even before activation;
   record them before `start`. Compare epoch/monotonic clocks over reload and
   offline time. The probe deliberately stores no session grants or saved token.
2. During combat and actual reported `InChatMessagingLockdown()` separately,
   repeat incoming markers, identity lookup availability and both route sends.
   Combat alone does not prove messaging lockdown. If no lockdown state can be
   reached, leave that row untested. Record missed filter callbacks versus
   displayed content, secret/inaccessible data and any API error without copying
   message bodies or trying to unlock them. Skipped callbacks are a known source
   limitation; determine whether it affects required ordinary chat in practice.
3. Record disconnect/logout event observations. Do not infer safe session
   persistence merely from `PLAYER_LOGOUT` firing; candidate login flags need
   verification before Phase 2 session rules rely on them.

## P1-SURFACES — bubbles, voice and speech

1. Use the normal settings UI to record and toggle original chat bubble settings
   (`chatBubbles`, `chatBubblesParty`, `chatBubblesRaid` where present). Send party
   marker/control messages from B while A's incoming filter is active. Check
   visible bubbles independently of chat frames; repeat with settings disabled,
   reload and combat. `C_ChatBubbles.GetAllChatBubbles()` is an inspection
   candidate, not proof that the frames can safely be hidden or read. Do not
   inspect inaccessible frame contents. Restore settings.
2. With consenting accounts in built-in voice, test joining, leaving, incoming
   audio, mic transmission and rejoining through UI. The documented
   `C_VoiceChat.LeaveChannel(channelID)` can be tested with an actual active
   channel ID. Record active channel/rejoin behavior, errors and whether controls
   are protected. Volume APIs are only candidates; no global disable is claimed.
3. Enable chat TTS for whisper/party, send hidden markers and listen for leakage.
   Independently test speech-to-text transcripts (`speechToText` setting),
   speak-for-me and voice transcription windows with harmless test speech.
   Record any surface that remains readable/audible, including queued TTS after
   revocation. These surfaces need explicit product handling or a documented
   supported-configuration limit. Restore original voice/accessibility settings.

Enter actual results in PHASE1_RESULTS.md. If core prevention or identity fails,
record the exact path/state and resolve support scope before a working release.
