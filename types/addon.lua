---@alias KinwardClock fun(): number

---@meta

---@class KinwardSettings
---@field enabled boolean
---@field minimapAngle? number Saved minimap position in radians.

---@class KinwardNamespace
---@field NormalizeSettings fun(saved: unknown): KinwardSettings
---@field initialized boolean
---@field settings? KinwardSettings

---@type KinwardSettings|nil
KinwardDB = nil
---@type string
SLASH_KINWARD1 = "/kinward"

-- Only assigned when the Phase 1 development probe is explicitly staged.
---@type string
SLASH_KINWARDPROBE1 = "/kinwardprobe"

---@class KinwardGrant
---@field mode 'indefinite'|'duration'|'session'
---@field expiresAt? number
---@field sessionId? string
---@field kind? 'character'|'account'
---@field target? string

---@class KinwardPolicy
---@field channels table<string, {read?: KinwardGrant, send?: KinwardGrant}>
---@field whispers table<string, KinwardGrant>

---@class KinwardIdentity
---@field character? string
---@field account? string

---@class KinwardContext
---@field now number Epoch seconds from an injected clock.
---@field sessionId string Adapter-supplied login token, retained across reload.
---@field accounts table<string, string> Trusted character-to-account mappings.

---@class KinwardSettings
---@field schemaVersion integer
---@field role 'unset'|'guardian'|'child'
---@field supervision 'unpaired'|'paired'|'recovery'
---@field generation string
---@field guardians table<string, boolean>
---@field children table<string, boolean>
---@field policy KinwardPolicy
---@field queues table<string, string[]>
---@field sessionId? string
---@field damaged? unknown

---@class KinwardNamespace
---@field profileVersion integer
---@field ValidIdentifier fun(value: unknown): boolean
---@field ValidGrant fun(grant: unknown): boolean
---@field CharacterKey fun(name: unknown, realm?: string): string?
---@field GrantActive fun(grant: KinwardGrant?, context: KinwardContext): boolean
---@field Evaluate fun(profile: KinwardSettings, channel: string, direction: 'read'|'send', identity: KinwardIdentity?, context: KinwardContext): boolean, string
---@field CanControl fun(profile: KinwardSettings, verifiedAccount: string, generation: string): boolean
---@field BeginSession fun(profile: KinwardSettings, sessionId: string): boolean
---@field NewGrant fun(mode: 'indefinite'|'duration'|'session', context: KinwardContext, seconds?: number): KinwardGrant?

---@class KinwardSimEndpoint
---@field profile KinwardSettings
---@field online boolean
---@field offset number
---@field login integer

---@class KinwardSimPacket
---@field sender string
---@field recipient string
---@field due number
---@field wire string

---@class KinwardSimulator
---@field now number
---@field delay number
---@field loss boolean
---@field duplicate boolean
---@field endpoints table<string, KinwardSimEndpoint>
---@field queue KinwardSimPacket[]

---@class KinwardNamespace
---@field NewSimulator fun(): KinwardSimulator
---@field SimContext fun(sim: KinwardSimulator, id: string): KinwardContext
---@field SimSend fun(sim: KinwardSimulator, sender: string, recipient: string, channel: string, direction: 'read'|'send', grant: KinwardGrant, target?: string): boolean
---@field SimDeliver fun(sim: KinwardSimulator, index?: integer): boolean, string

-- Only assigned when the Phase 2 simulator is explicitly staged.
---@type string
SLASH_KINWARDSIM1 = "/kinwardsim"

---@class KinwardReplayEntry
---@field wire string
---@field result string

---@class KinwardReplayLedger
---@field high number
---@field entries table<string, KinwardReplayEntry>

---@class KinwardChildProfile
---@field replySequence? number
---@field generation string
---@field result string

---@class KinwardSettings
---@field familyReplay table<string, KinwardReplayLedger>
---@field familySequence table<string, number>
---@field childProfiles table<string, KinwardChildProfile>

---@class KinwardFamily
---@field profile KinwardSettings
---@field id string
---@field freshToken fun(): string
---@field attempts integer
---@field invite? {peer: string, code: string, expires: number}
---@field pending? {peer: string, operation: string, expires: number, wire: string}
---@field outgoing table<string, {kind: string, generation: string, sequence: string}>

---@class KinwardNamespace
---@field EncodeMessage fun(fields: string[]): string?
---@field DecodeMessage fun(wire: unknown): string[]?, string
---@field NewFamily fun(profile: KinwardSettings, id: string, freshToken: fun(): string): KinwardFamily
---@field FamilyInvite fun(endpoint: KinwardFamily, peer: string, code: string, now: number): boolean
---@field FamilyConfirm fun(endpoint: KinwardFamily, peer: string, operation: string, confirmed: boolean, now: number, friends: table<string, boolean>): boolean, string
---@field FamilyReset fun(endpoint: KinwardFamily, confirmed: boolean): boolean, string
---@field FamilyCanDeliver fun(endpoint: KinwardFamily, peer: string, generation: string): boolean
---@field FamilyReceive fun(endpoint: KinwardFamily, peer: string, wire: unknown, now: number, friends: table<string, boolean>): boolean, string, string?
---@field FamilyRequest fun(endpoint: KinwardFamily, peer: string, generation: string, kind: string, arguments: string[]): string?
---@field FamilyReply fun(endpoint: KinwardFamily, peer: string, wire: unknown): boolean, string

---@class KinwardSimEndpoint
---@field family KinwardFamily
---@field friends table<string, boolean>

---@class KinwardSimulator
---@field token integer
---@field familyMode boolean

---@class KinwardNamespace
---@field SimEnqueue fun(sim: KinwardSimulator, sender: string, recipient: string, wire: string): boolean
---@field SimFamilySend fun(sim: KinwardSimulator, sender: string, recipient: string, kind: string, arguments: string[]): boolean
---@field SimFreshFamily fun(sim: KinwardSimulator)

---@class KinwardReplayEntry
---@field revision? number

---@class KinwardSettings
---@field policyRevision? number

---@class KinwardSettingView
---@field mode string
---@field expiresAt? number
---@field sessionId? string
---@field revision number

---@class KinwardChildProfile
---@field revision? number
---@field members? table<string, boolean>
---@field settings? table<string, KinwardSettingView>

---@class KinwardTransportIO
---@field instance string Fresh per endpoint construction; alphanumeric/hyphen, <= 36 characters.
---@field now fun(): number
---@field friends fun(): table<string, boolean>
---@field resolve fun(peer: string): number?
---@field send fun(route: number, packet: string): string

---@class KinwardDelivery
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

---@class KinwardAssembly
---@field peer string
---@field total number
---@field parts table<number, string>
---@field expires number

---@class KinwardTransport
---@field family KinwardFamily
---@field io KinwardTransportIO
---@field serial integer
---@field work KinwardDelivery[]
---@field incoming table<string, KinwardAssembly>
---@field contacts table<string, number>
---@field nextSend number
---@field stop? fun()

---@class KinwardDashboard
---@field profile KinwardSettings
---@field transport? KinwardTransport
---@field message string
---@field now fun(): number

---@class KinwardNamespace
---@field NewTransport fun(family: KinwardFamily, io: KinwardTransportIO): KinwardTransport
---@field TransportRequest fun(t: KinwardTransport, peer: string, kind: string, args: string[], seconds?: number): KinwardDelivery?, string
---@field TransportReceive fun(t: KinwardTransport, peer: string, packet: unknown): boolean
---@field TransportTick fun(t: KinwardTransport)
---@field TransportPresence fun(t: KinwardTransport, peer: string): string, number?
---@field NewWoWTransport fun(family: KinwardFamily, instance: string, verified: boolean, testing?: boolean): KinwardTransport?, string
---@field NewDashboard fun(profile: KinwardSettings, transport?: KinwardTransport, now?: KinwardClock, chat?: KinwardChat): KinwardDashboard
---@field DashboardCommand fun(d: KinwardDashboard, message: string): string
---@field DashboardText fun(d: KinwardDashboard): string
---@field ShowDashboard fun(d: KinwardDashboard, section?: string)
---@field dashboard? KinwardDashboard

---@class KinwardNetworkSimulator
---@field sim KinwardSimulator
---@field transports table<string, KinwardTransport>
---@field dashboards table<string, KinwardDashboard>
---@field routes table<string, number>

---@class KinwardNamespace
---@field NewNetworkSimulator fun(): KinwardNetworkSimulator
---@field NetworkAdvance fun(network: KinwardNetworkSimulator, seconds: number)

---@class KinwardTransport
---@field completedSnapshots table<string, string>
---@field snapshots table<string, {revision: number, generation: string, settings: table<string, KinwardSettingView>, cursor: number}>

---@class KinwardTransport
---@field receiveWindow? number
---@field receiveCount? number

---@class KinwardDashboard
---@field window? Frame
---@field selectedChild? string
---@field demo? KinwardNetworkSimulator

---@class KinwardNamespace
---@field DashboardAction fun(d: KinwardDashboard, kind: string, args: string[]): string
---@field DashboardPermission fun(d: KinwardDashboard, child: string?, channel: string, direction: 'read'|'send', target?: string): string, number, number, number
---@field ShowNetworkDemo? fun()

---@class KinwardChat
---@field profile KinwardSettings
---@field context fun(): KinwardContext
---@field seen table<string, {allowed: boolean, reason: string}>
---@field order string[]
---@field decisions integer
---@field blockedReads integer
---@field blockedSends integer
---@field attemptedSends integer
---@field observedOutputs integer Local whisper output events, not delivery receipts.

---@class KinwardChatIO
---@field prompt? fun(character: string) Open the child dashboard; no message body.
---@field account fun(character: string): string? Current verified BN friend, or nil.
---@field freshSession fun(): string Fresh login token; must not repeat a saved token.

---@class KinwardWoWChat
---@field chat KinwardChat
---@field stop fun(): string

---@class KinwardNamespace
---@field NewChat fun(profile: KinwardSettings, context: fun(): KinwardContext): KinwardChat
---@field ChatDecision fun(chat: KinwardChat, channel: string, direction: 'read'|'send', identity?: KinwardIdentity, line?: number): boolean, string
---@field NewWoWChat fun(profile: KinwardSettings, io: KinwardChatIO, verified: boolean, testing?: boolean): KinwardWoWChat?, string

---@class KinwardNamespace
---@field chat? KinwardWoWChat

---@class KinwardNetworkSimulator
---@field chats table<string, KinwardChat>

---@class KinwardNamespace
---@field ResolveWoWChatAccount fun(character: string): string?

---@class KinwardRequest
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

---@class KinwardRequestState
---@field requests? table<string, KinwardRequest>
---@field generation string
---@field requestPrompts? boolean
---@field requestSequence? number

---@class KinwardSettings
---@field requests? table<string, KinwardRequest>
---@field requestPrompts? boolean
---@field requestSequence? number

---@class KinwardChildProfile
---@field requests? table<string, KinwardRequest>
---@field requestPrompts? boolean

---@class KinwardChat
---@field promptSeen? table<string, number>
---@field nextPrompt? number
---@field prompt? {character: string, expires: number, generation: string}

---@class KinwardTransport
---@field nextRequestPoll? number

---@class KinwardDashboard
---@field chat? KinwardChat

---@class KinwardNamespace
---@field ValidRequest fun(r: unknown): boolean
---@field ValidRequestState fun(profile: KinwardRequestState): boolean
---@field ExpireRequests fun(profile: KinwardSettings, now: number)
---@field RequestRows fun(profile: KinwardSettings, now: number): KinwardRequest[]
---@field CreateRequest fun(profile: KinwardSettings, id: string, channel: string, direction: 'read'|'send', target: string, reason: string, now: number): KinwardRequest?, string
---@field CancelRequest fun(profile: KinwardSettings, id: string, now: number): boolean, string
---@field ApplyRequestDecision fun(profile: KinwardSettings, fields: string[], now: number, applyPolicy: fun(fields: string[]): string): string
---@field ChatWhisperPrompt fun(chat: KinwardChat, identity: KinwardIdentity)
---@field RequestPage fun(profile: KinwardSettings, fields: string[], now: number): string?
---@field AcceptRequestPage fun(t: KinwardTransport, peer: string, fields: string[], item: KinwardDelivery): boolean
---@field PollRequests fun(t: KinwardTransport)

---@class KinwardTransport
---@field requestSnapshots? table<string, {generation: string, cursor: number, requests: table<string, KinwardRequest>}>

---@class KinwardHistoryRecord
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

---@class KinwardHistory
---@field generation string
---@field records KinwardHistoryRecord[]
---@field high number
---@field pruned number
---@field expired number
---@field retention number
---@field maxRecords number
---@field lastSeen number
---@field cursor? number
---@field updatedAt? number
---@field cacheRemoved? number

---@class KinwardHistoryFilters
---@field channel? string
---@field direction? string
---@field disposition? string
---@field identity? string
---@field seconds? number
---@field from? number
---@field to? number

---@class KinwardCapturePending
---@field generation string
---@field time number
---@field channel string
---@field identity? KinwardIdentity
---@field text string
---@field truncated boolean

---@class KinwardSettings
---@field history? KinwardHistory

---@class KinwardChildProfile
---@field history? KinwardHistory

---@class KinwardChat
---@field monitoring? boolean
---@field captureStarted? boolean
---@field nextCaptureGap? number
---@field captureSeen? table<string, boolean>
---@field captureOrder? string[]
---@field pendingCaptures? KinwardCapturePending[]
---@field recentCaptures? KinwardCapturePending[]
---@field restrictedSince? number

---@class KinwardTransport
---@field historyWatching? table<string, boolean>
---@field nextHistoryPoll? number

---@class KinwardChatIO
---@field selfCharacter? fun(): string? Verified normalized current local character.

---@class KinwardNamespace
---@field NewHistory fun(generation: string): KinwardHistory
---@field ValidHistoryRecord fun(record: unknown): boolean
---@field ValidHistory fun(history: unknown, generation: string): boolean
---@field PruneHistory fun(history: KinwardHistory, now: number)
---@field HistoryRelationshipChanged fun(profile: KinwardSettings)
---@field ConfigureHistory fun(profile: KinwardSettings, retention: number, count: number, now: number): boolean
---@field AppendHistory fun(profile: KinwardSettings, now: number, direction: 'read'|'send'|'system', channel: string, identity: KinwardIdentity?, disposition: string, body: string, endedAt?: number): KinwardHistoryRecord?
---@field HistoryBatch fun(profile: KinwardSettings, fields: string[], now: number): string?
---@field AcceptHistoryBatch fun(t: KinwardTransport, peer: string, fields: string[], item: KinwardDelivery): boolean
---@field WatchHistory fun(t: KinwardTransport, peer: string): boolean
---@field PollHistory fun(t: KinwardTransport)
---@field HistoryView fun(profile: KinwardSettings, peer: string, filters: KinwardHistoryFilters, now: number): KinwardHistoryRecord[]
---@field HistoryGap fun(chat: KinwardChat, reason: string, since?: number)
---@field CaptureRead fun(chat: KinwardChat, channel: string, identity: KinwardIdentity?, body: string?, allowed: boolean, line: number?, gapReason?: string)
---@field CaptureSend fun(chat: KinwardChat, channel: string, identity: KinwardIdentity?, body: string?, allowed: boolean)
---@field CaptureOutput fun(chat: KinwardChat, channel: string, identity: KinwardIdentity?, body: string?, line: number?)
---@field FlushHistorySends fun(chat: KinwardChat, force?: boolean)
---@field HistoryHeartbeat fun(chat: KinwardChat, restricted: boolean)

---@class KinwardNamespace
---@field SimHistorySamples fun(network: KinwardNetworkSimulator, child: string)

---@alias KinwardClick fun()
---@alias KinwardActivityRefresh fun(visible: boolean, canEdit: boolean)

---@class KinwardActivityWidgets
---@field button fun(parent: Frame, x: number, y: number, width: number, caption: string, callback: KinwardClick): Button
---@field input fun(parent: Frame, x: number, y: number, width: number): EditBox
---@field label fun(parent: Frame, x: number, y: number, width: number, value: string, font?: string): FontString

---@class KinwardNamespace
---@field NewActivityPanel fun(d: KinwardDashboard, activity: Frame, widgets: KinwardActivityWidgets): KinwardActivityRefresh

---@class KinwardNamespace
---@field PruneProfileHistory fun(profile: KinwardSettings, now: number)

---@class KinwardPairingProposal
---@field peer string
---@field token string
---@field generation string
---@field expires number
---@field state string
---@field operation? string
---@field sequence? string

---@class KinwardPairingInbox: KinwardPairingProposal
---@field sequence string

---@class KinwardPairingReceipt
---@field peer string
---@field token string
---@field requestGeneration string
---@field generation string
---@field operation string
---@field sequence string
---@field expires number

---@class KinwardFamily
---@field proposal? KinwardPairingProposal
---@field guardianInbox? table<string, KinwardPairingInbox>

---@class KinwardSettings
---@field pairingReceipt? KinwardPairingReceipt

---@class KinwardTransportIO
---@field findPeer? fun(name: string): string? Resolve only current unambiguous verified friend aliases.

---@class KinwardTransport
---@field nextPairingPoll? number
---@field pairingPolling? boolean
---@field guardianCandidates? table<string, {peer: string, token: string, generation: string, expires: number}>

---@alias KinwardFamilyConfirm fun(caption: string, kind: string, args: string[])
---@alias KinwardPairingRefresh fun(canEdit: boolean, visible: boolean)

---@class KinwardNamespace
---@field ValidPairingReceipt fun(profile: KinwardSettings): boolean
---@field StorePairingReceipt fun(endpoint: KinwardFamily, proposal?: KinwardPairingProposal)
---@field RequestGuardianship fun(t: KinwardTransport, name: string, expectedPeer?: string): boolean, string
---@field AnswerGuardianship fun(t: KinwardTransport, peer: string, token: string, accept: boolean): boolean, string
---@field ReceiveGuardianship fun(endpoint: KinwardFamily, peer: string, fields: string[], now: number, friends: table<string, boolean>): boolean, string, string?
---@field AcceptGuardianCandidate fun(t: KinwardTransport, peer: string, fields: string[], item: KinwardDelivery): boolean
---@field TickGuardianship fun(t: KinwardTransport)
---@field PairingWorkValid fun(t: KinwardTransport, item: KinwardDelivery): boolean
---@field NewPairingPanel fun(d: KinwardDashboard, family: Frame, widgets: KinwardActivityWidgets, confirm: KinwardFamilyConfirm): KinwardPairingRefresh

---@class KinwardNamespace
---@field ResolveGuardianPeer fun(t: KinwardTransport, name: string): string?

---@class KinwardDashboard
---@field focusSection? fun(section: string)

---@class KinwardNamespace
---@field minimapButton? Button
---@field InstallMinimapButton fun(): Button?
---@field OpenDashboard fun(section?: string, target?: string)

---@class KinwardNamespace
---@field InstallPlayerMenu fun()
---@field PlayerMenuTarget fun(context: table): string?
---@field playerMenuInstalled? boolean
---@field LiveTestCommand fun(command: string): string
---@field liveTestTransport? KinwardTransport

---@class KinwardTransport
---@field testing? boolean
---@field testReceived? number

---@class KinwardSettings
---@field liveTestCounter? number

---@class KinwardDashboard
---@field pairingTarget? string
