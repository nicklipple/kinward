-- Pure modules and the staged command harness run in a strict WoW-like sandbox.
local ns, commands, output = {}, {}, {}
local live = { sentinel = true }
local env = {
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    math = math,
    string = string,
    table = table,
    tonumber = tonumber,
    tostring = tostring,
    SlashCmdList = commands,
    print = function(value)
        output[#output + 1] = value
    end,
}
setmetatable(env, {
    __index = function(_, key)
        error("Unexpected global read: " .. key)
    end,
    __newindex = function(t, key, value)
        assert(key == "SLASH_GUARDIANSIM1", "Unexpected global write: " .. key)
        rawset(t, key, value)
    end,
})
for _, file in ipairs({
    "Policy.lua",
    "Profile.lua",
    "Session.lua",
    "Protocol.lua",
    "Family.lua",
    "scripts/probes/Phase2Simulator.lua",
}) do
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)("Guardian", ns)
end
ns.settings = live
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end
local function fixture()
    local sim = ns.NewSimulator()
    return sim, sim.endpoints.child.profile, ns.SimContext(sim, "child")
end
local function allows(profile, context, channel, direction, identity)
    return ns.Evaluate(profile, channel or "party", direction or "read", identity, context)
end

test("fresh and legacy migration preserve enabled and unknown fields", function()
    local legacy = { enabled = false, custom = { keep = true } }
    assert(ns.NormalizeSettings(legacy) == legacy)
    assert(legacy.schemaVersion == 1 and legacy.supervision == "unpaired" and not legacy.enabled)
    assert(legacy.custom.keep)
    local a, b = ns.NormalizeSettings(nil), ns.NormalizeSettings(nil)
    assert(a ~= b and a.policy ~= b.policy and a.guardians ~= b.guardians)
    assert(allows(a, { now = 0, sessionId = "x", accounts = {} }))
end)
test("damaged and unknown-version state cannot silently unpair", function()
    local malformed = {
        false,
        1,
        "bad",
        { schemaVersion = 99 },
        { role = "child" },
        { policy = {} },
        { guardians = { parent = true } },
    }
    for _, value in ipairs(malformed) do
        local profile = ns.NormalizeSettings(value)
        assert(profile.supervision == "recovery" and profile.damaged == value)
        assert(not allows(profile, { now = 0, sessionId = "x", accounts = {} }))
        local again = ns.NormalizeSettings(profile)
        -- Original evidence remains bounded across reloads, including false.
        assert(again.supervision == "recovery" and again.damaged == value)
    end
end)
test("paired profile survives normalization with grants and membership", function()
    local _, profile = fixture()
    profile.policy.channels.party = { read = { mode = "indefinite" } }
    assert(ns.NormalizeSettings(profile) == profile)
    assert(profile.guardians.parent and profile.guardians.parent2)
    assert(profile.policy.channels.party.read.mode == "indefinite")
end)
test("malformed paired components fail closed", function()
    local edits = {
        function(p)
            p.guardians = {}
        end,
        function(p)
            p.policy.channels.party = { read = true }
        end,
        function(p)
            p.policy.channels.party = { write = { mode = "indefinite" } }
        end,
        function(p)
            p.policy.whispers.x = { mode = "indefinite", kind = "account" }
        end,
        function(p)
            p.queues = false
        end,
        function(p)
            p.generation = ""
        end,
        function(p)
            p.role = "guardian"
        end,
        function(p)
            p.sessionId = {}
        end,
    }
    for _, edit in ipairs(edits) do
        local _, p = fixture()
        edit(p)
        assert(ns.NormalizeSettings(p).supervision == "recovery")
    end
end)
test("queue IDs are bounded and invalid entries discarded", function()
    local _, profile = fixture()
    for i = 1, 100 do
        profile.queues.requests[i] = "work:" .. i
    end
    profile.queues.delivery = { "ok", false, string.rep("x", 129), "also-ok" }
    ns.NormalizeSettings(profile)
    assert(#profile.queues.requests == 64 and #profile.queues.delivery == 2)
end)
test("closed defaults, independent read/send and channel scope", function()
    local _, p, context = fixture()
    for _, channel in ipairs({ "party", "raid", "say", "channel:general", "whisper" }) do
        assert(not allows(p, context, channel, "read"))
        assert(not allows(p, context, channel, "send"))
    end
    p.policy.channels.party = { read = { mode = "indefinite" } }
    assert(allows(p, context) and not allows(p, context, "party", "send"))
    assert(not allows(p, context, "raid"))
    assert(not allows(p, context, "whisper", "read", { character = "Friend-TestRealm" }))
    p.policy.channels.party = { send = { mode = "indefinite" } }
    assert(not allows(p, context) and allows(p, context, "party", "send"))
end)
test("normalized character whispers are bidirectional and realm-specific", function()
    local _, p, context = fixture()
    assert(ns.CharacterKey("Friend", "Test Realm") == "friend-testrealm")
    assert(ns.CharacterKey("Friend-Quel'Thalas") == "friend-quelthalas")
    assert(not ns.CharacterKey("Friend") and not ns.CharacterKey("bad$-Realm"))
    p.policy.whispers.friend =
        { kind = "character", target = "friend-testrealm", mode = "indefinite" }
    for _, direction in ipairs({ "read", "send" }) do
        assert(allows(p, context, "whisper", direction, { character = "FRIEND-Test Realm" }))
        assert(not allows(p, context, "whisper", direction, { character = "Friend-Other" }))
    end
end)
test("account grants and guardian path require verified mappings", function()
    local _, p, context = fixture()
    p.policy.whispers.friend = { kind = "account", target = "friend", mode = "indefinite" }
    assert(not allows(p, context, "whisper", "read", { account = "friend" }))
    assert(
        not allows(
            p,
            context,
            "whisper",
            "read",
            { character = "Stranger-Realm", account = "friend" }
        )
    )
    assert(
        allows(
            p,
            context,
            "whisper",
            "send",
            { character = "Friend-TestRealm", account = "friend" }
        )
    )
    assert(
        allows(
            p,
            context,
            "whisper",
            "read",
            { character = "Guardian-TestRealm", account = "parent" }
        )
    )
    assert(
        not allows(
            p,
            context,
            "whisper",
            "read",
            { character = "Stranger-Realm", account = "parent" }
        )
    )
    assert(ns.CanControl(p, "parent", p.generation))
    assert(not ns.CanControl(p, "parent", "old") and not ns.CanControl(p, "stranger", p.generation))
end)
test("indefinite and timed expiry use injected absolute time including offline time", function()
    local sim, p, context = fixture()
    p.policy.channels.party = { read = ns.NewGrant("duration", context, 900) }
    sim.now = 1899
    assert(allows(p, ns.SimContext(sim, "child")))
    sim.now = 1900
    assert(not allows(p, ns.SimContext(sim, "child")))
    sim.now = 100000
    assert(not allows(ns.NormalizeSettings(p), ns.SimContext(sim, "child")))
    p.policy.channels.party.read = ns.NewGrant("indefinite", context)
    assert(allows(p, ns.SimContext(sim, "child")))
    for _, value in ipairs({ -1, 0, math.huge, 0 / 0 }) do
        assert(not ns.NewGrant("duration", context, value))
    end
end)
test("session grants survive reload and invalidate on a new login", function()
    local sim, p, context = fixture()
    p.policy.channels.party = { read = ns.NewGrant("session", context) }
    ns.BeginSession(p, "child:1")
    assert(allows(ns.NormalizeSettings(p), ns.SimContext(sim, "child")))
    assert(not ns.BeginSession(p, ""))
    ns.BeginSession(p, "child:2")
    assert(not allows(p, ns.SimContext(sim, "child")))
end)
test("transport delays, disconnects, reordering, duplicates and snapshots", function()
    local sim, p = fixture()
    local grant = { mode = "duration", expiresAt = 2000 }
    sim.delay, sim.duplicate = 10, true
    assert(ns.SimSend(sim, "parent", "child", "party", "read", grant))
    grant.expiresAt = 1
    assert(#sim.queue == 2 and not ns.SimDeliver(sim))
    sim.now = sim.now + 10
    sim.endpoints.child.online = false
    assert(not ns.SimDeliver(sim, 2) and #sim.queue == 2)
    sim.endpoints.child.online = true
    assert(ns.SimDeliver(sim, 2) and ns.SimDeliver(sim, 1))
    assert(p.policy.channels.party.read.expiresAt == 2000)
    assert(not sim.endpoints.child2.profile.policy.channels.party)
    assert(not sim.endpoints.parent.profile.policy.channels.party)
    sim.loss = true
    assert(ns.SimSend(sim, "parent", "child", "raid", "read", grant) and #sim.queue == 0)
end)
test("bounded transport rejects stale generations and unauthorized fixtures", function()
    local sim, p = fixture()
    local grant = { mode = "indefinite" }
    assert(ns.SimSend(sim, "child2", "child", "party", "read", grant))
    assert(not ns.SimDeliver(sim) and not p.policy.channels.party)
    assert(ns.SimSend(sim, "parent", "child", "party", "read", grant))
    p.generation = "new"
    assert(not ns.SimDeliver(sim))
    for _ = 1, 64 do
        assert(ns.SimSend(sim, "parent", "child", "party", "read", grant))
    end
    assert(not ns.SimSend(sim, "parent", "child", "party", "read", grant))
end)
test("whisper expiry, alt mapping and revocation share the same evaluator", function()
    local sim, p, context = fixture()
    local grant = ns.NewGrant("duration", context, 15)
    grant.kind, grant.target = "account", "friend"
    p.policy.whispers.friend = grant
    context.accounts["alt-testrealm"] = "friend"
    local alt = { character = "Alt-TestRealm", account = "friend" }
    assert(allows(p, context, "whisper", "read", alt))
    context.accounts["alt-testrealm"] = nil
    assert(not allows(p, context, "whisper", "read", alt))
    sim.now = sim.now + 15
    assert(not allows(p, ns.SimContext(sim, "child"), "whisper", "send", {
        character = "Friend-TestRealm",
        account = "friend",
    }))
    local session = ns.NewGrant("session", context)
    session.kind, session.target = "character", "friend-testrealm"
    p.policy.whispers.friend = session
    assert(allows(p, context, "whisper", "send", { character = "Friend-TestRealm" }))
    context.sessionId = "child:2"
    assert(not allows(p, context, "whisper", "read", { character = "Friend-TestRealm" }))
end)
test("reordered distinct writes apply in delivery order and queues snapshot fields", function()
    local sim, p = fixture()
    assert(
        ns.SimSend(sim, "parent", "child", "party", "read", { mode = "duration", expiresAt = 2000 })
    )
    assert(
        ns.SimSend(
            sim,
            "parent2",
            "child",
            "party",
            "read",
            { mode = "duration", expiresAt = 3000 }
        )
    )
    assert(ns.SimDeliver(sim, 2) and p.policy.channels.party.read.expiresAt == 3000)
    assert(ns.SimDeliver(sim, 1) and p.policy.channels.party.read.expiresAt == 2000)
    p.policy.channels.party.read = nil
    assert(not allows(p, ns.SimContext(sim, "child")))
end)
test("command-driven demo and clocks never access live saved state or APIs", function()
    local command = commands.GUARDIANSIM
    command("reset")
    command("check child party read")
    assert(output[#output]:find("allowed=false", 1, true))
    command("grant parent child party read session")
    command("pump")
    command("reload child")
    command("check child party read")
    assert(output[#output]:find("allowed=true", 1, true))
    command("login child")
    command("check child party read")
    assert(output[#output]:find("allowed=false", 1, true))
    command("grant parent2 child whisper-character read indefinite 0 Friend-TestRealm")
    command("pump")
    command("check child whisper send Friend-TestRealm")
    assert(output[#output]:find("allowed=true", 1, true))
    command("grant parent child party read duration 15")
    command("pump")
    command("clock child 20")
    command("check child party read")
    assert(output[#output]:find("allowed=false", 1, true))
    assert(ns.settings == live and live.sentinel and next(live, "sentinel") == nil)
end)
print(string.format("%d phase 2 tests passed (Lua %s)", passed, _VERSION))
