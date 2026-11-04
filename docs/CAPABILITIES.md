# Phase 1 capability evidence

Status (2026-11-03): source investigation and reproducible development probes
implemented; **client acceptance pending**. No game client or two-account test
was run. No enforcement or pairing capability is marked client verified.
The precise outstanding gates are receipt-confirmed outgoing prevention, an
incoming filter demonstration, and authenticated-peer-capable communication.
Pure logic may proceed; this is not a working parental-control release.

All paths below are relative to `reference/blizzard-ui/Interface/AddOns/` at
Gethe `forever` commit `17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c`, version
**1.60.1.70755**. `A/` abbreviates `Blizzard_APIDocumentationGenerated/` and
`B/` abbreviates `Blizzard_ChatFrameBase/`. Source verification establishes a
symbol/branch implementation, not engine behavior. See [probe procedures](PHASE1_PROBES.md)
and [the result ledger](PHASE1_RESULTS.md) for how to close each gate.
Retail observations must use a separate ledger entry and never close a Forever gate.

| Capability | Pinned symbols and source | Evidence / initial support status | Client procedure |
| --- | --- | --- | --- |
| Incoming ordinary whisper/party and Battle.net whisper display | `ChatFrameUtil.AddMessageEventFilter`, `RemoveMessageEventFilter`, `ProcessMessageEventFilters`: `B/Shared/ChatFrameFilters.lua`; consumer `B/Mainline/ChatFrameOverrides.lua` | Source verified; client untested. Returning true discards display in this consumer. Callback can run once per frame. Does not establish other UI coverage. | P1-IN |
| Inaccessible incoming text | `canaccessvalue(...)` gate in `B/Shared/ChatFrameFilters.lua`; `A/FrameScriptDocumentation.lua`; chat events marked `SecretInChatMessagingLockdown` in `A/ChatInfoDocumentation.lua` | **Unsupported by this filter when arguments are inaccessible:** callback is skipped. Cannot promise closed-default blocking or capture in this state. Exact reachable states untested. | P1-LOCK |
| Standard edit box, whisper windows | `ChatFrameEditBoxBaseMixin:SendText`, `ParseText`; `ChatFrameEditBoxMixin:OnPreSendText`: `B/Shared/ChatFrameEditBox.lua`; `B/Shared/FloatingChatFrame.lua` | Source verified; client untested. `ParseText(1)` runs before `OnPreSendText`, so the latter cannot universally cancel slash/macro sends already performed. | P1-OUT |
| Outgoing ordinary chat boundary | `C_ChatInfo.SendChatMessage`: `A/ChatInfoDocumentation.lua`; direct callers in `B/Shared/ChatFrameEditBox.lua` and `B/Shared/SlashCommands.lua` (`REPLY`, `DND`, channel send); secure command parsing in edit box | Source verified; wrapper experiment untested. A wrapper prevents calls routed through it, but cached references, secure engine paths and taint remain unresolved. A post-hook or outgoing-echo filter cannot prevent a send. | P1-OUT |
| Battle.net outgoing chat and emotes | `C_BattleNet.SendWhisper`: `A/BattleNetDocumentation.lua`; `C_ChatInfo.PerformEmote`: `A/ChatInfoDocumentation.lua`; edit box callers above | Source verified; **not intercepted by this probe's ordinary-chat wrapper**. Global coverage untested and not claimed. | P1-OUT |
| Friend/account and alt resolution | `C_BattleNet.GetFriendAccountInfo`, `GetFriendNumGameAccounts`, `GetFriendGameAccountInfo`, `GetAccountInfoByGUID`, `GetAccountInfoByID`, `GetGameAccountInfoByGUID`, `GetGameAccountInfoByID`; structures `BNetAccountInfo`, `BNetGameAccountInfo`: `A/BattleNetDocumentation.lua` | Source verified; client untested. Records include BattleTag, friendship, account/game handles, WoW GUID and character/realm fields, some nilable. Names alone do not prove ownership. No durable pairing identity chosen. | P1-ID |
| Character addon route | `C_ChatInfo.RegisterAddonMessagePrefix`, `SendAddonMessage`; `CHAT_MSG_ADDON` payload includes prefix/text/channel/sender: `A/ChatInfoDocumentation.lua` | Source verified; two-account routing untested. Return code is not an applied acknowledgement. Sender identity must be validated independently. | P1-ROUTE |
| Battle.net addon route | `C_BattleNet.SendGameData(gameAccountID, prefix, data)`: `A/BattleNetDocumentation.lua`; `BN_CHAT_MSG_ADDON(prefix, text, channel, senderID)`: `A/ChatInfoDocumentation.lua` | Source verified; two-account routing and senderID resolution untested. Do not assume senderID is a durable account identifier or equivalent to the send target. | P1-ID / P1-ROUTE |
| Delivery failures and restrictions | `Enum.SendAddonMessageResult`, `Enum.RegisterAddonMessagePrefixResult`: `A/ChatConstantsDocumentation.lua`; `C_ChatInfo.InChatMessagingLockdown`, `AreOutgoingAddonChatMessagesRestricted`: `A/ChatInfoDocumentation.lua` | Source verified; runtime results untested. Results include success, throttle, lockdown and target offline. Prefix success is **0**, duplicate is **1**, not a boolean success flag. | P1-ROUTE / P1-LOCK |
| Reload versus session | `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)`, `PLAYER_LOGIN`, `PLAYER_LOGOUT`: `A/SystemDocumentation.lua` | Source verified; client untested. Use entering-world flags as candidate session discriminator. Logout alone is insufficient evidence for reload/new-login distinction. Abrupt termination needs conservative new-session handling. | P1-SESSION |
| Clocks | `GetServerTime`: `A/SystemTimeDocumentation.lua`; `GetTimePreciseSec`: `A/OsDocumentation.lua` | Source verified; client untested. Server epoch is a candidate for offline expiry; monotonic values are not persisted expiry timestamps. | P1-SESSION |
| Bubbles | `C_ChatBubbles.GetAllChatBubbles`: `A/ChatBubblesDocumentation.lua`; `chatBubbles`, `chatBubblesParty` usage in `Blizzard_SettingsDefinitions_Frame/Interface.lua` | Source verified; feasible suppression untested. Chat-frame filters do not prove bubble suppression; no global bubble enforcement promised. | P1-SURFACES |
| Voice | `C_VoiceChat.LeaveChannel`, `SetInputVolume`, `SetOutputVolume`: `A/VoiceChatDocumentation.lua` | Source verified; practical disable/rejoin behavior untested. Leaving a channel or reducing volume does not establish global voice prevention. | P1-SURFACES |
| TTS, transcription and speak-for-me | `C_VoiceChat.SpeakText`, `StopSpeakingText`: `A/VoiceChatDocumentation.lua`; `Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua`, `TextToSpeech.lua`, `VoiceChatTranscriptionFrame.lua`, `VoiceChatTranscriptionButton.lua` (`speechToText`, `IsSpeakForMeActive`) | Source verified; distinct speech/text surfaces require handling and client verification. No automatic suppression from ordinary chat filtering assumed. | P1-SURFACES |

## Expected loading and cleanup

`B/Blizzard_ChatFrameBase.toc` loads the slash registry, secure filter-array
factory (`Shared/ChatFrameFiltersSecure.lua`, secure environment), filter API,
edit-box implementation, family/game overrides, XML instances and floating
chat windows in that order. Forever's Camelot overrides layer over family
implementations; paths named Mainline in this **Forever snapshot** are source
components, not a substituted Retail baseline. `Blizzard_ChatFrame` depends on
`Blizzard_ChatFrameBase` and loads TTS/transcription UI separately. Generated API
documentation describes engine APIs; its load order is not a runtime dependency.
Guardian still loads Settings then Core; the optional probe is staged last.
Normal client order and alternate UI loading still need observation. The probe
checks required filter/security symbols before activation; missing symbols are
recorded as a capability failure, not replaced with legacy API guesses.

Probe installation changes the development TOC only. It starts inactive, then
explicit activation installs four incoming filters and replaces one outgoing
function for marker text. Stop removes filters/events and restores the send
function only if it still owns it. Reload is required to clear taint, prefix
registration, slash registration and any downstream cached wrappers. Probes do
not modify GuardianDB, pair accounts, grant policy, save message bodies or reply
to incoming traffic. See cleanup details before running experiments.

## Phase gate

1.1 is complete as a source evidence matrix and client test specification.
1.2–1.4 have executable/manual procedures, but their live demonstrations remain
pending. Two test accounts are unavailable; manual probing is deferred until
the Phase 2 single-client simulator is available. Development can proceed on
shared logic and isolated simulated endpoints while live gates remain open.
The known inaccessible-filter gap must be reflected in future product
scope; if observed states make core enforcement unavailable, resolve that scope
with the user before proceeding toward a working release. Simulated boundary
checks do not close any live gate. No protocol, policy engine or release claims
are introduced by Phase 1 preparation.
