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
---@field NewDashboard fun(profile: GuardianSettings, transport?: GuardianTransport, now?: fun(): number): GuardianDashboard
---@field DashboardCommand fun(d: GuardianDashboard, message: string): string
---@field DashboardText fun(d: GuardianDashboard): string
---@field ShowDashboard fun(d: GuardianDashboard)
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
