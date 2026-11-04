-- Strict boundary tests: unexpected APIs/globals fail; no actual client is run.
local ns, frames, filters, notices, sends = {}, {}, {}, {}, {}
local now, token, account = 1000, 0, nil
local friends = {}
local secret = setmetatable({}, {
    __tostring = function()
        error("Secret serialized")
    end,
    __eq = function()
        error("Secret compared")
    end,
    __index = function()
        error("Secret indexed")
    end,
})
local function accessible(value)
    return not rawequal(value, secret)
end
local function original(...)
    sends[#sends + 1] = { n = select("#", ...), ... }
    return "result", nil, 42
end
local function strict(t)
    return setmetatable(t, {
        __index = function(_, k)
            error("Unexpected API/global: " .. k)
        end,
    })
end
local env = strict({
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    math = math,
    string = string,
    table = table,
    tonumber = tonumber,
    tostring = tostring,
    select = select,
    canaccessvalue = accessible,
    BNGetNumFriends = function()
        return #friends
    end,
    WOW_PROJECT_ID = 99,
    C_Club = {},
    C_BattleNet = strict({
        SendWhisper = original,
        GetFriendAccountInfo = function(i)
            return friends[i].account
        end,
        GetFriendNumGameAccounts = function(i)
            return #friends[i].games
        end,
        GetFriendGameAccountInfo = function(i, g)
            return friends[i].games[g]
        end,
    }),
    GetServerTime = function()
        return now
    end,
    GetNormalizedRealmName = function()
        return "Test Realm"
    end,
    print = function(s)
        notices[#notices + 1] = s
    end,
    C_ChatInfo = strict({ SendChatMessage = original }),
    ChatFrameUtil = strict({
        AddMessageEventFilter = function(event, callback)
            assert(not filters[event], "Filter installed twice")
            filters[event] = callback
        end,
        RemoveMessageEventFilter = function(event, callback)
            assert(filters[event] == callback)
            filters[event] = nil
        end,
    }),
    CreateFrame = function(kind)
        assert(kind == "Frame")
        local f = strict({ events = {}, scripts = {} })
        function f:RegisterEvent(e)
            self.events[e] = true
        end
        function f:UnregisterEvent(e)
            self.events[e] = nil
        end
        function f:SetScript(k, callback)
            self.scripts[k] = callback
        end
        frames[#frames + 1] = f
        return f
    end,
    SlashCmdList = {},
})
setmetatable(env, {
    __index = function(_, k)
        error("Unexpected global read: " .. k)
    end,
    __newindex = function(t, k, v)
        assert(k == "SLASH_KINWARDSIM1", "Unexpected global write: " .. k)
        rawset(t, k, v)
    end,
})
for _, file in ipairs({
    "Channels.lua",
    "Policy.lua",
    "Profile.lua",
    "Session.lua",
    "Requests.lua",
    "History.lua",
    "HistoryCapture.lua",
    "Protocol.lua",
    "Family.lua",
    "Pairing.lua",
    "Transport.lua",
    "Activity.lua",
    "PairingPanel.lua",
    "Dashboard.lua",
    "Chat.lua",
    "WoWChat.lua",
    "scripts/probes/Phase2Simulator.lua",
}) do
    setfenv(assert(loadfile(file)), env)("Kinward", ns)
end
local passed = 0
local function test(name, body)
    assert(not ns.chat)
    filters, notices, sends = {}, {}, {}
    account, now = nil, 1000
    body()
    if ns.chat then
        ns.chat.stop()
    end
    passed = passed + 1
    print("ok - " .. name)
end
local ioAdapter = {
    account = function(key)
        assert(key == ns.CharacterKey(key))
        return account
    end,
    freshSession = function()
        token = token + 1
        return "login:" .. token
    end,
}
local function profile()
    local p = ns.NormalizeSettings(nil)
    p.role, p.supervision, p.generation = "child", "paired", "generation:1"
    p.guardians = { parent = true }
    return p
end
local function start(p)
    local a, reason = ns.NewWoWChat(p, ioAdapter)
    assert(a, reason)
    return a, frames[#frames]
end
local function incoming(event, sender, line, body)
    return filters[event]({}, event, body or secret, sender, "", "", "", "", 0, 0, "", 0, line)
end
local function enter(f, initial, reload)
    f.scripts.OnEvent(f, "PLAYER_ENTERING_WORLD", initial, reload)
end
local function output(f, line)
    f.scripts.OnEvent(
        f,
        "CHAT_MSG_WHISPER_INFORM",
        secret,
        secret,
        "",
        "",
        "",
        "",
        0,
        0,
        "",
        0,
        line
    )
end
local indefinite = { mode = "indefinite" }

test("closed incoming party and whisper decisions are shared across windows", function()
    local a = start(profile())
    assert(incoming("CHAT_MSG_WHISPER", "Stranger", 1))
    assert(incoming("CHAT_MSG_WHISPER", "Stranger", 1))
    assert(incoming("CHAT_MSG_PARTY", "Stranger", 2))
    assert(incoming("CHAT_MSG_PARTY_LEADER", "Stranger", 2))
    assert(a.chat.decisions == 2 and a.chat.blockedReads == 2)
    assert(#notices == 1 and notices[1]:find("stranger-testrealm", 1, true) and #sends == 0)
end)
test("party read/send independent; revocation applies on the next message", function()
    local p = profile()
    local a = start(p)
    p.policy.channels.party = { read = indefinite }
    assert(not incoming("CHAT_MSG_PARTY", "Stranger", 1))
    env.C_ChatInfo.SendChatMessage("hidden outgoing", "PARTY")
    assert(#sends == 0 and a.chat.blockedSends == 1)
    p.policy.channels.party = { send = indefinite }
    assert(incoming("CHAT_MSG_PARTY", "Stranger", 2))
    local x, y, z = env.C_ChatInfo.SendChatMessage("text", "PARTY", nil, nil, "extra")
    assert(x == "result" and y == nil and z == 42 and sends[1].n == 5)
    assert(a.chat.attemptedSends == 1 and a.chat.observedOutputs == 0)
    p.policy.channels.party.send = nil
    env.C_ChatInfo.SendChatMessage("text", "PARTY")
    assert(#sends == 1)
end)
test("party permission cannot authorize a stranger's whisper", function()
    local p = profile()
    p.policy.channels.party = { read = indefinite, send = indefinite }
    start(p)
    assert(incoming("CHAT_MSG_WHISPER", "Stranger", 1))
    env.C_ChatInfo.SendChatMessage("text", "WHISPER", nil, "Stranger")
    assert(#sends == 0)
end)
test("character approval is bidirectional and normalizes local/cross-realm targets", function()
    local p = profile()
    p.policy.whispers.friend =
        { mode = "indefinite", kind = "character", target = "friend-testrealm" }
    start(p)
    assert(not incoming("CHAT_MSG_WHISPER", "Friend", 1))
    env.C_ChatInfo.SendChatMessage("text", "WHISPER", nil, "FRIEND-Test Realm")
    assert(#sends == 1)
    assert(incoming("CHAT_MSG_WHISPER", "Friend-OtherRealm", 2))
    assert(incoming("CHAT_MSG_WHISPER", nil, 3))
    assert(incoming("CHAT_MSG_WHISPER", secret, 4))
end)
test("verified friend/kinward identity is refreshed and never inferred from names", function()
    local p = profile()
    p.policy.whispers.friend = { mode = "indefinite", kind = "account", target = "friend-account" }
    start(p)
    assert(incoming("CHAT_MSG_WHISPER", "Friend", 1))
    account = "friend-account"
    assert(not incoming("CHAT_MSG_WHISPER", "Friend", 2))
    account = nil -- Friendship removal / unresolved alt.
    assert(incoming("CHAT_MSG_WHISPER", "Friend", 3))
    account = "parent"
    assert(not incoming("CHAT_MSG_WHISPER", "KinwardAlt", 4))
    env.C_ChatInfo.SendChatMessage("text", "WHISPER", nil, "KinwardAlt")
    assert(#sends == 1)
    account = secret
    assert(incoming("CHAT_MSG_WHISPER", "Friend", 5))
    account = "parent"
    assert(incoming("CHAT_MSG_WHISPER", secret, 6))
end)
test(
    "blocked-whisper callback receives only accessible identity and honors prompt preference",
    function()
        local p = profile()
        local received = {}
        ioAdapter.prompt = function(...)
            assert(select("#", ...) == 1)
            received[#received + 1] = ...
        end
        start(p)
        incoming("CHAT_MSG_WHISPER", "Friend", 1, secret)
        incoming("CHAT_MSG_WHISPER", "Friend", 1, secret)
        assert(#received == 1 and received[1] == "friend-testrealm")
        now = now + 61
        p.requestPrompts = false
        incoming("CHAT_MSG_WHISPER", "Other", 2, secret)
        incoming("CHAT_MSG_WHISPER", secret, 3, secret)
        assert(#received == 1 and #notices == 0)
        ioAdapter.prompt = nil
    end
)
test("candidate BN resolver requires fresh, unambiguous same-project friendships", function()
    local game = {
        clientProgram = "WoW",
        isOnline = true,
        wowProjectID = 99,
        characterName = "Friend",
        realmName = "Test Realm",
    }
    friends = { { account = { isFriend = true, battleTag = "Friend#123" }, games = { game } } }
    assert(ns.ResolveWoWChatAccount("friend-testrealm") == "Friend#123")
    game.characterName = "Alt"
    assert(ns.ResolveWoWChatAccount("friend-testrealm") == nil)
    assert(ns.ResolveWoWChatAccount("alt-testrealm") == "Friend#123")
    game.realmName = secret
    assert(ns.ResolveWoWChatAccount("alt-testrealm") == nil)
    game.realmName = "Test Realm"
    game.wowProjectID = 1
    assert(ns.ResolveWoWChatAccount("alt-testrealm") == nil)
    game.wowProjectID = 99
    friends[2] = { account = { isFriend = true, battleTag = "Other#456" }, games = { game } }
    assert(ns.ResolveWoWChatAccount("alt-testrealm") == nil)
    friends[2].account.isFriend = false
    assert(ns.ResolveWoWChatAccount("alt-testrealm") == "Friend#123")
    friends[1].account.isFriend = false
    assert(ns.ResolveWoWChatAccount("alt-testrealm") == nil)
    friends = {}
end)
test("session grants wait for lifecycle, survive reload and expire at a new login", function()
    local p = profile()
    p.sessionId = "previous"
    p.policy.channels.party = { read = { mode = "session", sessionId = "previous" } }
    local a, f = start(p)
    assert(incoming("CHAT_MSG_PARTY", "Friend", 1))
    enter(f, false, true)
    assert(not incoming("CHAT_MSG_PARTY", "Friend", 2))
    a.stop()
    a, f = start(p)
    enter(f, false, true)
    assert(not incoming("CHAT_MSG_PARTY", "Friend", 3))
    a.stop()
    a, f = start(p)
    enter(f, true, false)
    assert(p.sessionId ~= "previous" and incoming("CHAT_MSG_PARTY", "Friend", 4))
    local session = p.sessionId
    enter(f, false, false)
    assert(p.sessionId == session)
end)
test("unavailable lifecycle and repeated login tokens cannot revive session grants", function()
    local p = profile()
    p.sessionId = "previous"
    p.policy.channels.party = { read = { mode = "session", sessionId = "previous" } }
    local a = assert(ns.NewWoWChat(p, {
        account = ioAdapter.account,
        freshSession = function()
            return "previous"
        end,
    }))
    local f = frames[#frames]
    enter(f, true, false)
    assert(p.sessionId == nil and incoming("CHAT_MSG_PARTY", "Friend", 1))
    enter(f, false, true)
    assert(incoming("CHAT_MSG_PARTY", "Friend", 2))
    enter(f, secret, secret)
    assert(incoming("CHAT_MSG_PARTY", "Friend", 3))
    a.stop()
end)
test("expiry uses current time even after monitoring loss and reload", function()
    local p = profile()
    p.policy.channels.party = { read = { mode = "duration", expiresAt = 1010 } }
    local a = start(p)
    assert(not incoming("CHAT_MSG_PARTY", "Friend", 1))
    now = 1010
    assert(incoming("CHAT_MSG_PARTY", "Friend", 2))
    a.stop()
    start(p)
    assert(incoming("CHAT_MSG_PARTY", "Friend", 3))
end)
test("output events are deduplicated observations, never inferred from a send", function()
    local p = profile()
    p.policy.whispers.friend =
        { mode = "indefinite", kind = "character", target = "friend-testrealm" }
    local a, f = start(p)
    env.C_ChatInfo.SendChatMessage("text", "WHISPER", nil, "Friend")
    assert(a.chat.attemptedSends == 1 and a.chat.observedOutputs == 0)
    output(f, 1)
    output(f, 1)
    output(f, secret)
    assert(a.chat.observedOutputs == 1)
end)
test("blocked send notices are bounded, generic and do not reveal text or identity", function()
    local a = start(profile())
    for _ = 1, 100 do
        env.C_ChatInfo.SendChatMessage(secret, "WHISPER", nil, secret)
    end
    assert(a.chat.blockedSends == 100 and #notices == 1)
    assert(not notices[1]:find("secret") and not notices[1]:find("Stranger"))
    now = 1002
    env.C_ChatInfo.SendChatMessage(secret, secret, nil, secret)
    assert(#notices == 2 and #sends == 0)
end)
test("dedup cache is bounded and inaccessible/missing IDs are never content-hashed", function()
    local a = start(profile())
    for i = 1, 1000 do
        incoming("CHAT_MSG_WHISPER", secret, i)
    end
    assert(#a.chat.order == 256)
    local n = 0
    for _ in pairs(a.chat.seen) do
        n = n + 1
    end
    assert(n == 256 and a.chat.decisions == 1000)
    assert(incoming("CHAT_MSG_WHISPER", secret, secret))
    assert(incoming("CHAT_MSG_WHISPER", secret, nil))
    assert(a.chat.decisions == 1000)
end)
test(
    "unpaired profiles pass through; recovery stays closed; saved enabled cannot disable policy",
    function()
        local p = ns.NormalizeSettings(nil)
        local a = start(p)
        assert(not incoming("CHAT_MSG_WHISPER", secret, 1))
        env.C_ChatInfo.SendChatMessage(secret, secret, nil, secret)
        assert(#sends == 1)
        p.supervision, p.enabled = "recovery", false
        assert(incoming("CHAT_MSG_WHISPER", "Friend", 2))
        env.C_ChatInfo.SendChatMessage(secret, "WHISPER", nil, secret)
        assert(#sends == 1 and a.chat.blockedSends == 1)
    end
)
test("allowed guild sends preserve exact arguments and returns", function()
    local p = profile()
    p.policy.channels.guild = { send = indefinite }
    start(p)
    local x, y, z = env.C_ChatInfo.SendChatMessage(secret, "GUILD", 7, "target", nil, 99)
    assert(x == "result" and y == nil and z == 42)
    assert(sends[1].n == 6 and sends[1][3] == 7 and sends[1][6] == 99)
end)
test("original send failures remain attempted sends without observed output", function()
    local failure = function()
        error("engine rejected send")
    end
    env.C_ChatInfo.SendChatMessage = failure
    local p = profile()
    p.policy.channels.party = { send = indefinite }
    local a = start(p)
    local ok, message = pcall(env.C_ChatInfo.SendChatMessage, "text", "PARTY")
    assert(not ok and message:find("engine rejected send", 1, true))
    assert(a.chat.attemptedSends == 1 and a.chat.observedOutputs == 0)
    a.stop()
    assert(env.C_ChatInfo.SendChatMessage == failure)
    env.C_ChatInfo.SendChatMessage = original
end)
test("teardown preserves other addons' wrappers and prevents duplicate installation", function()
    local a, f = start(profile())
    local duplicate, reason = ns.NewWoWChat(profile(), ioAdapter)
    assert(not duplicate and reason == "chat-already-active")
    local downstream = env.C_ChatInfo.SendChatMessage
    local other = function(...)
        return downstream(...)
    end
    env.C_ChatInfo.SendChatMessage = other
    assert(a.stop() == "chained-wrapper-reload-required")
    assert(env.C_ChatInfo.SendChatMessage == other and not next(filters))
    assert(not next(f.events) and not f.scripts.OnEvent)
    env.C_ChatInfo.SendChatMessage("text", "WHISPER", nil, "Stranger")
    assert(#sends == 1)
    env.C_ChatInfo.SendChatMessage = original
end)
test(
    "network pairing, applied policy, chat, revocation and parent loss share production state",
    function()
        local n = ns.NewNetworkSimulator()
        local function cmd(id, s)
            return ns.DashboardCommand(n.dashboards[id], s)
        end
        cmd("child", "invite parent 12345678")
        cmd("parent", "pair child 12345678")
        ns.NetworkAdvance(n, 2)
        local f = n.transports.child.family
        assert(
            ns.FamilyConfirm(
                f,
                "parent",
                f.pending.operation,
                true,
                n.sim.now,
                n.sim.endpoints.child.friends
            )
        )
        cmd("parent", "sync child")
        ns.NetworkAdvance(n, 4)
        local c, c2 = n.chats.child, n.chats.child2
        assert(not ns.ChatDecision(c, "party", "read", nil, 1))
        assert(
            ns.TransportRequest(
                n.transports.parent,
                "child",
                "policy",
                { "party", "read", "indefinite", "", "", "" }
            )
        )
        ns.NetworkAdvance(n, 5)
        assert(ns.ChatDecision(c, "party", "read", nil, 2))
        assert(not ns.ChatDecision(c, "party", "send"))
        -- Child2 is unpaired, then paired closed to make isolation observable.
        c2.profile.supervision = "paired"
        assert(not ns.ChatDecision(c2, "party", "read", nil, 1))
        n.sim.endpoints.parent.online = false
        assert(ns.ChatDecision(c, "party", "read", nil, 3))
        n.sim.endpoints.parent.online = true
        assert(
            ns.TransportRequest(
                n.transports.parent,
                "child",
                "policy",
                { "party", "read", "revoke", "", "", "" }
            )
        )
        ns.NetworkAdvance(n, 5)
        assert(not ns.ChatDecision(c, "party", "read", nil, 4))
    end
)
test("simulator chat commands remain isolated and simulate reload versus login", function()
    local command = env.SlashCmdList.KINWARDSIM
    command("network-reset")
    command("network-chat child read party Friend-TestRealm unused 1")
    assert(notices[#notices]:find("allowed; unpaired", 1, true))
    command("network-reload child")
    assert(notices[#notices]:find("child:1", 1, true))
    command("network-login child")
    assert(notices[#notices]:find("child:2", 1, true))
    assert(not next(filters) and #sends == 0)
end)
print(string.format("%d Phase 5 tests passed (Lua %s)", passed, _VERSION))
