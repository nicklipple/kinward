---@alias GuardianClock fun(): number

---@meta

---@class GuardianSettings
---@field enabled boolean

---@class GuardianNamespace
---@field NormalizeSettings fun(saved: unknown): GuardianSettings
---@field initialized boolean
---@field settings? GuardianSettings

---@type GuardianSettings|nil
GuardianDB = nil
---@type string
SLASH_GUARDIAN1 = "/guardian"

-- Only assigned when the Phase 1 development probe is explicitly staged.
---@type string
SLASH_GUARDIANPROBE1 = "/guardianprobe"

---@class GuardianGrant
---@field mode 'indefinite'|'duration'|'session'
---@field expiresAt? number
---@field sessionId? string
---@field kind? 'character'|'account'
---@field target? string

---@class GuardianPolicy
---@field channels table<string, {read?: GuardianGrant, send?: GuardianGrant}>
---@field whispers table<string, GuardianGrant>

---@class GuardianIdentity
---@field character? string
---@field account? string

---@class GuardianContext
---@field now number Epoch seconds from an injected clock.
---@field sessionId string Adapter-supplied login token, retained across reload.
---@field accounts table<string, string> Trusted character-to-account mappings.

---@class GuardianSettings
---@field schemaVersion integer
---@field role 'unset'|'guardian'|'child'
---@field supervision 'unpaired'|'paired'|'recovery'
---@field generation string
---@field guardians table<string, boolean>
---@field children table<string, boolean>
---@field policy GuardianPolicy
---@field queues table<string, string[]>
---@field sessionId? string
---@field damaged? unknown

---@class GuardianNamespace
---@field profileVersion integer
---@field ValidIdentifier fun(value: unknown): boolean
---@field ValidGrant fun(grant: unknown): boolean
---@field CharacterKey fun(name: unknown, realm?: string): string?
---@field GrantActive fun(grant: GuardianGrant?, context: GuardianContext): boolean
---@field Evaluate fun(profile: GuardianSettings, channel: string, direction: 'read'|'send', identity: GuardianIdentity?, context: GuardianContext): boolean, string
---@field CanControl fun(profile: GuardianSettings, verifiedAccount: string, generation: string): boolean
---@field BeginSession fun(profile: GuardianSettings, sessionId: string): boolean
---@field NewGrant fun(mode: 'indefinite'|'duration'|'session', context: GuardianContext, seconds?: number): GuardianGrant?

---@class GuardianSimEndpoint
---@field profile GuardianSettings
---@field online boolean
---@field offset number
---@field login integer

---@class GuardianSimPacket
---@field sender string
---@field recipient string
---@field due number
---@field wire string

---@class GuardianSimulator
---@field now number
---@field delay number
---@field loss boolean
---@field duplicate boolean
---@field endpoints table<string, GuardianSimEndpoint>
---@field queue GuardianSimPacket[]

---@class GuardianNamespace
---@field NewSimulator fun(): GuardianSimulator
---@field SimContext fun(sim: GuardianSimulator, id: string): GuardianContext
---@field SimSend fun(sim: GuardianSimulator, sender: string, recipient: string, channel: string, direction: 'read'|'send', grant: GuardianGrant, target?: string): boolean
---@field SimDeliver fun(sim: GuardianSimulator, index?: integer): boolean, string

-- Only assigned when the Phase 2 simulator is explicitly staged.
---@type string
SLASH_GUARDIANSIM1 = "/guardiansim"

---@class GuardianReplayEntry
---@field wire string
---@field result string

---@class GuardianReplayLedger
---@field high number
---@field entries table<string, GuardianReplayEntry>

---@class GuardianChildProfile
---@field replySequence? number
---@field generation string
---@field result string

---@class GuardianSettings
---@field familyReplay table<string, GuardianReplayLedger>
---@field familySequence table<string, number>
---@field childProfiles table<string, GuardianChildProfile>

---@class GuardianFamily
---@field profile GuardianSettings
---@field id string
---@field freshToken fun(): string
---@field attempts integer
---@field invite? {peer: string, code: string, expires: number}
---@field pending? {peer: string, operation: string, expires: number, wire: string}
---@field outgoing table<string, {kind: string, generation: string, sequence: string}>

---@class GuardianNamespace
---@field EncodeMessage fun(fields: string[]): string?
---@field DecodeMessage fun(wire: unknown): string[]?, string
---@field NewFamily fun(profile: GuardianSettings, id: string, freshToken: fun(): string): GuardianFamily
---@field FamilyInvite fun(endpoint: GuardianFamily, peer: string, code: string, now: number): boolean
---@field FamilyConfirm fun(endpoint: GuardianFamily, peer: string, operation: string, confirmed: boolean, now: number, friends: table<string, boolean>): boolean, string
---@field FamilyReset fun(endpoint: GuardianFamily, confirmed: boolean): boolean, string
---@field FamilyCanDeliver fun(endpoint: GuardianFamily, peer: string, generation: string): boolean
---@field FamilyReceive fun(endpoint: GuardianFamily, peer: string, wire: unknown, now: number, friends: table<string, boolean>): boolean, string, string?
---@field FamilyRequest fun(endpoint: GuardianFamily, peer: string, generation: string, kind: string, arguments: string[]): string?
---@field FamilyReply fun(endpoint: GuardianFamily, peer: string, wire: unknown): boolean, string

---@class GuardianSimEndpoint
---@field family GuardianFamily
---@field friends table<string, boolean>

---@class GuardianSimulator
---@field token integer
---@field familyMode boolean

---@class GuardianNamespace
---@field SimEnqueue fun(sim: GuardianSimulator, sender: string, recipient: string, wire: string): boolean
---@field SimFamilySend fun(sim: GuardianSimulator, sender: string, recipient: string, kind: string, arguments: string[]): boolean
---@field SimFreshFamily fun(sim: GuardianSimulator)

---@class GuardianReplayEntry
---@field revision? number

---@class GuardianSettings
---@field policyRevision? number

---@class GuardianSettingView
---@field mode string
---@field expiresAt? number
---@field sessionId? string
---@field revision number

---@class GuardianChildProfile
---@field revision? number
---@field members? table<string, boolean>
---@field settings? table<string, GuardianSettingView>

---@class GuardianTransportIO
---@field instance string Fresh per endpoint construction; alphanumeric/hyphen, <= 36 characters.
---@field now fun(): number
---@field friends fun(): table<string, boolean>
---@field resolve fun(peer: string): number?
---@field send fun(route: number, packet: string): string

---@class GuardianDelivery
---@field peer string
---@field wire string
---@field deadline number
---@field reply boolean
---@field operation string
---@field generation string
---@field kind string
---@field sequence string
---@field id string
---@field state string
---@field cursor integer
---@field attempts integer
---@field due number
---@field result string
---@field revision? number
---@field receipt? string

---@class GuardianAssembly
---@field peer string
---@field total number
---@field parts table<number, string>
---@field expires number

---@class GuardianTransport
---@field family GuardianFamily
---@field io GuardianTransportIO
---@field serial integer
---@field work GuardianDelivery[]
---@field incoming table<string, GuardianAssembly>
---@field contacts table<string, number>
---@field nextSend number
---@field stop? fun()

---@class GuardianDashboard
---@field profile GuardianSettings
---@field transport? GuardianTransport
---@field message string
---@field now fun(): number

---@class GuardianNamespace
---@field NewTransport fun(family: GuardianFamily, io: GuardianTransportIO): GuardianTransport
---@field TransportRequest fun(t: GuardianTransport, peer: string, kind: string, args: string[], seconds?: number): GuardianDelivery?, string
---@field TransportReceive fun(t: GuardianTransport, peer: string, packet: unknown): boolean
---@field TransportTick fun(t: GuardianTransport)
---@field TransportPresence fun(t: GuardianTransport, peer: string): string, number?
---@field NewWoWTransport fun(family: GuardianFamily, instance: string, verified: boolean): GuardianTransport?, string
---@field NewDashboard fun(profile: GuardianSettings, transport?: GuardianTransport, now?: GuardianClock, chat?: GuardianChat): GuardianDashboard
---@field DashboardCommand fun(d: GuardianDashboard, message: string): string
---@field DashboardText fun(d: GuardianDashboard): string
---@field ShowDashboard fun(d: GuardianDashboard, section?: string)
---@field dashboard? GuardianDashboard

---@class GuardianNetworkSimulator
---@field sim GuardianSimulator
---@field transports table<string, GuardianTransport>
---@field dashboards table<string, GuardianDashboard>
---@field routes table<string, number>

---@class GuardianNamespace
---@field NewNetworkSimulator fun(): GuardianNetworkSimulator
---@field NetworkAdvance fun(network: GuardianNetworkSimulator, seconds: number)

---@class GuardianTransport
---@field completedSnapshots table<string, string>
---@field snapshots table<string, {revision: number, generation: string, settings: table<string, GuardianSettingView>, cursor: number}>

---@class GuardianTransport
---@field receiveWindow? number
---@field receiveCount? number

---@class GuardianDashboard
---@field window? Frame
---@field selectedChild? string
---@field demo? GuardianNetworkSimulator

---@class GuardianNamespace
---@field DashboardAction fun(d: GuardianDashboard, kind: string, args: string[]): string
---@field DashboardPermission fun(d: GuardianDashboard, child: string?, channel: string, direction: 'read'|'send', target?: string): string, number, number, number
---@field ShowNetworkDemo? fun()

---@class GuardianChat
---@field profile GuardianSettings
---@field context fun(): GuardianContext
---@field seen table<string, {allowed: boolean, reason: string}>
---@field order string[]
---@field decisions integer
---@field blockedReads integer
---@field blockedSends integer
---@field attemptedSends integer
---@field observedOutputs integer Local whisper output events, not delivery receipts.

---@class GuardianChatIO
---@field prompt? fun(character: string) Open the child dashboard; no message body.
---@field account fun(character: string): string? Current verified BN friend, or nil.
---@field freshSession fun(): string Fresh login token; must not repeat a saved token.

---@class GuardianWoWChat
---@field chat GuardianChat
---@field stop fun(): string

---@class GuardianNamespace
---@field NewChat fun(profile: GuardianSettings, context: fun(): GuardianContext): GuardianChat
---@field ChatDecision fun(chat: GuardianChat, channel: string, direction: 'read'|'send', identity?: GuardianIdentity, line?: number): boolean, string
---@field NewWoWChat fun(profile: GuardianSettings, io: GuardianChatIO, verified: boolean): GuardianWoWChat?, string

---@class GuardianNamespace
---@field chat? GuardianWoWChat

---@class GuardianNetworkSimulator
---@field chats table<string, GuardianChat>

---@class GuardianNamespace
---@field ResolveWoWChatAccount fun(character: string): string?

---@class GuardianRequest
---@field id string
---@field generation string
---@field channel string
---@field direction 'read'|'send'
---@field target string
---@field reason string
---@field expires number
---@field state 'pending'|'approved'|'denied'|'cancelled'|'expired'
---@field baseRevision number
---@field sessionId string

---@class GuardianRequestState
---@field requests? table<string, GuardianRequest>
---@field generation string
---@field requestPrompts? boolean
---@field requestSequence? number

---@class GuardianSettings
---@field requests? table<string, GuardianRequest>
---@field requestPrompts? boolean
---@field requestSequence? number

---@class GuardianChildProfile
---@field requests? table<string, GuardianRequest>
---@field requestPrompts? boolean

---@class GuardianChat
---@field promptSeen? table<string, number>
---@field nextPrompt? number
---@field prompt? {character: string, expires: number, generation: string}

---@class GuardianTransport
---@field nextRequestPoll? number

---@class GuardianDashboard
---@field chat? GuardianChat

---@class GuardianNamespace
---@field ValidRequest fun(r: unknown): boolean
---@field ValidRequestState fun(profile: GuardianRequestState): boolean
---@field ExpireRequests fun(profile: GuardianSettings, now: number)
---@field RequestRows fun(profile: GuardianSettings, now: number): GuardianRequest[]
---@field CreateRequest fun(profile: GuardianSettings, id: string, channel: string, direction: 'read'|'send', target: string, reason: string, now: number): GuardianRequest?, string
---@field CancelRequest fun(profile: GuardianSettings, id: string, now: number): boolean, string
---@field ApplyRequestDecision fun(profile: GuardianSettings, fields: string[], now: number, applyPolicy: fun(fields: string[]): string): string
---@field ChatWhisperPrompt fun(chat: GuardianChat, identity: GuardianIdentity)
---@field RequestPage fun(profile: GuardianSettings, fields: string[], now: number): string?
---@field AcceptRequestPage fun(t: GuardianTransport, peer: string, fields: string[], item: GuardianDelivery): boolean
---@field PollRequests fun(t: GuardianTransport)

---@class GuardianTransport
---@field requestSnapshots? table<string, {generation: string, cursor: number, requests: table<string, GuardianRequest>}>

---@class GuardianHistoryRecord
---@field seq number
---@field time number
---@field endedAt number
---@field direction 'read'|'send'|'system'
---@field channel string
---@field character string
---@field account string
---@field disposition string
---@field text string
---@field truncated boolean

---@class GuardianHistory
---@field generation string
---@field records GuardianHistoryRecord[]
---@field high number
---@field pruned number
---@field expired number
---@field retention number
---@field maxRecords number
---@field lastSeen number
---@field cursor? number
---@field updatedAt? number
---@field cacheRemoved? number

---@class GuardianHistoryFilters
---@field channel? string
---@field direction? string
---@field disposition? string
---@field identity? string
---@field seconds? number
---@field from? number
---@field to? number

---@class GuardianCapturePending
---@field generation string
---@field time number
---@field channel string
---@field identity? GuardianIdentity
---@field text string
---@field truncated boolean

---@class GuardianSettings
---@field history? GuardianHistory

---@class GuardianChildProfile
---@field history? GuardianHistory

---@class GuardianChat
---@field monitoring? boolean
---@field captureStarted? boolean
---@field nextCaptureGap? number
---@field captureSeen? table<string, boolean>
---@field captureOrder? string[]
---@field pendingCaptures? GuardianCapturePending[]
---@field recentCaptures? GuardianCapturePending[]
---@field restrictedSince? number

---@class GuardianTransport
---@field historyWatching? table<string, boolean>
---@field nextHistoryPoll? number

---@class GuardianChatIO
---@field selfCharacter? fun(): string? Verified normalized current local character.

---@class GuardianNamespace
---@field NewHistory fun(generation: string): GuardianHistory
---@field ValidHistoryRecord fun(record: unknown): boolean
---@field ValidHistory fun(history: unknown, generation: string): boolean
---@field PruneHistory fun(history: GuardianHistory, now: number)
---@field HistoryRelationshipChanged fun(profile: GuardianSettings)
---@field ConfigureHistory fun(profile: GuardianSettings, retention: number, count: number, now: number): boolean
---@field AppendHistory fun(profile: GuardianSettings, now: number, direction: 'read'|'send'|'system', channel: string, identity: GuardianIdentity?, disposition: string, body: string, endedAt?: number): GuardianHistoryRecord?
---@field HistoryBatch fun(profile: GuardianSettings, fields: string[], now: number): string?
---@field AcceptHistoryBatch fun(t: GuardianTransport, peer: string, fields: string[], item: GuardianDelivery): boolean
---@field WatchHistory fun(t: GuardianTransport, peer: string): boolean
---@field PollHistory fun(t: GuardianTransport)
---@field HistoryView fun(profile: GuardianSettings, peer: string, filters: GuardianHistoryFilters, now: number): GuardianHistoryRecord[]
---@field HistoryGap fun(chat: GuardianChat, reason: string, since?: number)
---@field CaptureRead fun(chat: GuardianChat, channel: string, identity: GuardianIdentity?, body: string?, allowed: boolean, line: number?, gapReason?: string)
---@field CaptureSend fun(chat: GuardianChat, channel: string, identity: GuardianIdentity?, body: string?, allowed: boolean)
---@field CaptureOutput fun(chat: GuardianChat, channel: string, identity: GuardianIdentity?, body: string?, line: number?)
---@field FlushHistorySends fun(chat: GuardianChat, force?: boolean)
---@field HistoryHeartbeat fun(chat: GuardianChat, restricted: boolean)

---@class GuardianNamespace
---@field SimHistorySamples fun(network: GuardianNetworkSimulator, child: string)

---@alias GuardianClick fun()
---@alias GuardianActivityRefresh fun(visible: boolean, canEdit: boolean)

---@class GuardianActivityWidgets
---@field button fun(parent: Frame, x: number, y: number, width: number, caption: string, callback: GuardianClick): Button
---@field input fun(parent: Frame, x: number, y: number, width: number): EditBox
---@field label fun(parent: Frame, x: number, y: number, width: number, value: string, font?: string): FontString

---@class GuardianNamespace
---@field NewActivityPanel fun(d: GuardianDashboard, activity: Frame, widgets: GuardianActivityWidgets): GuardianActivityRefresh

---@class GuardianNamespace
---@field PruneProfileHistory fun(profile: GuardianSettings, now: number)

---@class GuardianPairingProposal
---@field peer string
---@field token string
---@field generation string
---@field expires number
---@field state string
---@field operation? string
---@field sequence? string

---@class GuardianPairingInbox: GuardianPairingProposal
---@field sequence string

---@class GuardianPairingReceipt
---@field peer string
---@field token string
---@field requestGeneration string
---@field generation string
---@field operation string
---@field sequence string
---@field expires number

---@class GuardianFamily
---@field proposal? GuardianPairingProposal
---@field guardianInbox? table<string, GuardianPairingInbox>

---@class GuardianSettings
---@field pairingReceipt? GuardianPairingReceipt

---@class GuardianTransportIO
---@field findPeer? fun(name: string): string? Resolve only current unambiguous verified friend aliases.

---@class GuardianTransport
---@field nextPairingPoll? number
---@field pairingPolling? boolean
---@field guardianCandidates? table<string, {peer: string, token: string, generation: string, expires: number}>

---@alias GuardianFamilyConfirm fun(caption: string, kind: string, args: string[])
---@alias GuardianPairingRefresh fun(canEdit: boolean, visible: boolean)

---@class GuardianNamespace
---@field ValidPairingReceipt fun(profile: GuardianSettings): boolean
---@field StorePairingReceipt fun(endpoint: GuardianFamily, proposal?: GuardianPairingProposal)
---@field RequestGuardianship fun(t: GuardianTransport, name: string, expectedPeer?: string): boolean, string
---@field AnswerGuardianship fun(t: GuardianTransport, peer: string, token: string, accept: boolean): boolean, string
---@field ReceiveGuardianship fun(endpoint: GuardianFamily, peer: string, fields: string[], now: number, friends: table<string, boolean>): boolean, string, string?
---@field AcceptGuardianCandidate fun(t: GuardianTransport, peer: string, fields: string[], item: GuardianDelivery): boolean
---@field TickGuardianship fun(t: GuardianTransport)
---@field PairingWorkValid fun(t: GuardianTransport, item: GuardianDelivery): boolean
---@field NewPairingPanel fun(d: GuardianDashboard, family: Frame, widgets: GuardianActivityWidgets, confirm: GuardianFamilyConfirm): GuardianPairingRefresh

---@class GuardianNamespace
---@field ResolveGuardianPeer fun(t: GuardianTransport, name: string): string?

---@class GuardianDashboard
---@field focusSection? fun(section: string)

---@class GuardianNamespace
---@field minimapButton? Button
---@field InstallMinimapButton fun(): Button?
---@field OpenDashboard fun()
