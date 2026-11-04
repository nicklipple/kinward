local ns, output, commands = {}, {}, {}
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
        assert(key == "SLASH_KINWARDSIM1", "Unexpected global write: " .. key)
        rawset(t, key, value)
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
    "Chat.lua",
    "scripts/probes/Phase2Simulator.lua",
}) do
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)("Kinward", ns)
end
local live = { sentinel = true }
ns.settings = live
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end
local function fresh()
    local sim = ns.NewSimulator()
    ns.SimFreshFamily(sim)
    return sim, sim.endpoints.child.family
end
local function receive(sim, sender, wire, child)
    local e = sim.endpoints[child or "child"]
    return ns.FamilyReceive(e.family, sender, wire, sim.now + e.offset, e.friends)
end
local function request(sim, sender, kind, args, child, generation)
    child = child or "child"
    local wire = ns.FamilyRequest(
        sim.endpoints[sender].family,
        child,
        generation or sim.endpoints[child].profile.generation,
        kind,
        args or {}
    )
    assert(wire)
    return wire
end
local function pair(sim, child, parent, code)
    local e = sim.endpoints[child]
    assert(ns.FamilyInvite(e.family, parent, code or "12345678", sim.now))
    local wire = request(sim, parent, "pair", { code or "12345678" }, child)
    assert(receive(sim, parent, wire, child))
    local operation = assert(e.family.pending).operation
    if e.profile.supervision == "paired" then
        local approver = next(e.profile.guardians)
        assert(
            receive(
                sim,
                approver,
                request(sim, approver, "add", { parent, operation, "confirm" }, child),
                child
            )
        )
    else
        assert(ns.FamilyConfirm(e.family, parent, operation, true, sim.now, e.friends))
    end
end
local function policy(sim, parent, mode, expiry, child)
    return request(
        sim,
        parent,
        "policy",
        { "party", "read", mode or "indefinite", expiry or "", "", "" },
        child
    )
end
local function sync(sim, parent, child)
    local wire = request(sim, parent, "sync", {}, child)
    local ok, _, reply = receive(sim, parent, wire, child)
    assert(ok and reply)
    assert(ns.FamilyReply(sim.endpoints[parent].family, child, reply))
end

test("strict bounded non-executable codec and unsupported versions", function()
    local fields = { "1", "pair", "parent:1", "initial", "1", "12345678" }
    local wire = assert(ns.EncodeMessage(fields))
    local decoded = assert(ns.DecodeMessage(wire))
    for i, value in ipairs(fields) do
        assert(decoded[i] == value)
    end
    for _, value in ipairs({
        false,
        {},
        1,
        "",
        "1:a",
        "01:11:x1:x1:x1:1",
        "9999:x",
        wire .. "1:",
        string.rep("x", 2049),
        "return os.execute('bad')",
    }) do
        assert(not ns.DecodeMessage(value))
    end
    fields[1] = "2"
    local _, reason = ns.DecodeMessage(assert(ns.EncodeMessage(fields)))
    assert(reason == "unsupported-version")
    fields[6] = string.rep("a", 257)
    assert(not ns.EncodeMessage(fields))
    fields[6] = "bad\n"
    assert(not ns.EncodeMessage(fields))
    fields[6] = "good"
    for _ = 7, 17 do
        fields[#fields + 1] = "x"
    end
    assert(not ns.EncodeMessage(fields))
end)

test(
    "code knowledge alone never grants authority; confirmation binds peer and operation",
    function()
        local sim, child = fresh()
        assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
        local wire = request(sim, "parent", "pair", { "12345678" })
        assert(receive(sim, "parent", wire))
        assert(child.profile.supervision == "unpaired")
        assert(not receive(sim, "parent", policy(sim, "parent")))
        assert(not receive(sim, "parent", request(sim, "parent", "history")))
        local operation = child.pending.operation
        assert(
            not ns.FamilyConfirm(
                child,
                "parent2",
                operation,
                true,
                sim.now,
                sim.endpoints.child.friends
            )
        )
        assert(
            not ns.FamilyConfirm(
                child,
                "parent",
                "wrong",
                true,
                sim.now,
                sim.endpoints.child.friends
            )
        )
        assert(
            not ns.FamilyConfirm(
                child,
                "parent",
                operation,
                false,
                sim.now,
                sim.endpoints.child.friends
            )
        )
        assert(
            ns.FamilyConfirm(child, "parent", operation, true, sim.now, sim.endpoints.child.friends)
        )
        assert(child.profile.supervision == "paired" and child.profile.guardians.parent)
        assert(not next(child.profile.policy.channels) and not next(child.profile.policy.whispers))
        assert(not receive(sim, "parent", wire))
    end
)

test("wrong/expired codes, unknown friendship, spoofed identities and bounded attempts", function()
    local sim, child = fresh()
    assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
    local wire = request(sim, "parent", "pair", { "12345678" })
    assert(not receive(sim, "parent2", wire))
    sim.endpoints.child.friends.parent = nil
    assert(not receive(sim, "parent", wire))
    sim.endpoints.child.friends.parent = true
    for _ = 1, 4 do
        assert(not receive(sim, "parent", request(sim, "parent", "pair", { "00000000" })))
    end
    assert(not receive(sim, "parent", wire))
    assert(not ns.FamilyInvite(child, "parent", "87654321", sim.now))
    sim, child = fresh()
    assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
    sim.now = sim.now + 120
    assert(not receive(sim, "parent", request(sim, "parent", "pair", { "12345678" })))
    sim, child = fresh()
    assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
    assert(receive(sim, "parent", request(sim, "parent", "pair", { "12345678" })))
    sim.now = sim.now + 120
    assert(
        not ns.FamilyConfirm(
            child,
            "parent",
            child.pending.operation,
            true,
            sim.now,
            sim.endpoints.child.friends
        )
    )
end)

test("friendship is rechecked on confirmation and reconnect/reload drops pending codes", function()
    local sim, child = fresh()
    assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
    local wire = request(sim, "parent", "pair", { "12345678" })
    sim.delay = 10
    assert(ns.SimEnqueue(sim, "parent", "child", wire))
    sim.endpoints.child.online = false
    sim.now = sim.now + 10
    assert(not ns.SimDeliver(sim))
    sim.endpoints.child.online = true
    assert(ns.SimDeliver(sim))
    local op = child.pending.operation
    sim.endpoints.child.friends.parent = false
    assert(not ns.FamilyConfirm(child, "parent", op, true, sim.now, sim.endpoints.child.friends))
    local restored = ns.NewFamily(ns.NormalizeSettings(child.profile), "child", child.freshToken)
    assert(not restored.invite and not restored.pending)
    assert(not ns.FamilyReceive(restored, "parent", wire, sim.now, { parent = true }))
end)

test("additional guardians require a current guardian's exact confirmation", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    local original = child.profile.generation
    assert(ns.FamilyInvite(child, "parent2", "87654321", sim.now))
    assert(receive(sim, "parent2", request(sim, "parent2", "pair", { "87654321" })))
    local operation = child.pending.operation
    assert(
        not ns.FamilyConfirm(
            child,
            "parent2",
            operation,
            true,
            sim.now,
            sim.endpoints.child.friends
        )
    )
    assert(
        not receive(
            sim,
            "parent2",
            request(sim, "parent2", "add", { "parent2", operation, "confirm" })
        )
    )
    assert(
        not receive(sim, "parent", request(sim, "parent", "add", { "parent2", "wrong", "confirm" }))
    )
    assert(not receive(sim, "parent", request(sim, "parent", "add", { "parent2", operation, "" })))
    assert(
        receive(sim, "parent", request(sim, "parent", "add", { "parent2", operation, "confirm" }))
    )
    assert(child.profile.guardians.parent2 and child.profile.generation ~= original)
    assert(receive(sim, "parent2", policy(sim, "parent2")))
    assert(receive(sim, "parent", policy(sim, "parent")))
end)

test("independent guardian child profiles, authenticated replies and history gates", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    pair(sim, "child2", "parent", "87654321")
    sync(sim, "parent", "child")
    sync(sim, "parent", "child2")
    local parent = sim.endpoints.parent.family
    assert(parent.profile.childProfiles.child ~= parent.profile.childProfiles.child2)
    local wire = policy(sim, "parent")
    local ok, _, ack = receive(sim, "parent", wire)
    assert(ok and ack)
    assert(not ns.FamilyReply(parent, "child2", ack))
    assert(ns.FamilyReply(parent, "child", ack))
    assert(not ns.FamilyReply(parent, "child", ack))
    assert(parent.profile.childProfiles.child.result == "applied")
    assert(parent.profile.childProfiles.child2.result == "paired")
    assert(not sim.endpoints.child2.profile.policy.channels.party)
    assert(receive(sim, "parent", request(sim, "parent", "history")))
    assert(not receive(sim, "parent2", request(sim, "parent2", "history")))
    assert(ns.FamilyCanDeliver(child, "parent", child.profile.generation))
end)

test("duplicates never reapply, ID collisions reject, bounded replay survives reload", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    local first = policy(sim, "parent", "duration", "2000")
    assert(receive(sim, "parent", first))
    local second = policy(sim, "parent", "duration", "3000")
    assert(receive(sim, "parent", second))
    assert(receive(sim, "parent", first))
    assert(child.profile.policy.channels.party.read.expiresAt == 3000)
    local fields = assert(ns.DecodeMessage(first))
    fields[9] = "4000"
    local ok, reason = receive(sim, "parent", assert(ns.EncodeMessage(fields)))
    assert(not ok and reason == "operation-collision")
    local restored = ns.NewFamily(ns.NormalizeSettings(child.profile), "child", child.freshToken)
    assert(ns.FamilyReceive(restored, "parent", first, sim.now, { parent = true }))
    assert(restored.profile.policy.channels.party.read.expiresAt == 3000)
    -- Simulate acknowledged/lost outbound work expiry while exercising receiver window.
    for _ = 1, 70 do
        sim.endpoints.parent.family.outgoing = {}
        assert(receive(sim, "parent", policy(sim, "parent")))
    end
    ok, reason = receive(sim, "parent", first)
    assert(not ok and reason == "replay-too-old")
    local count = 0
    for _ in pairs(child.profile.familyReplay.parent.entries) do
        count = count + 1
    end
    assert(count == 64)
end)

test("either guardian can remove another; revoked or stale work cannot regain access", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    pair(sim, "child", "parent2", "87654321")
    local generation = child.profile.generation
    local delayed = policy(sim, "parent")
    local history = request(sim, "parent", "history")
    child.profile.queues.delivery = { "queued-history" }
    assert(not receive(sim, "parent2", request(sim, "parent2", "remove", { "parent", "" })))
    assert(receive(sim, "parent2", request(sim, "parent2", "remove", { "parent", "confirm" })))
    assert(not child.profile.guardians.parent and child.profile.guardians.parent2)
    assert(#child.profile.queues.delivery == 0)
    assert(not ns.FamilyCanDeliver(child, "parent", generation))
    assert(not receive(sim, "parent", delayed) and not receive(sim, "parent", history))
    assert(not receive(sim, "parent", policy(sim, "parent")))
    assert(not receive(sim, "parent", request(sim, "parent", "sync")))
    assert(receive(sim, "parent2", policy(sim, "parent2")))
end)

test("last-guardian stop, reset/re-pair and recovery require explicit confirmation", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    local generation = child.profile.generation
    local old = policy(sim, "parent")
    assert(not receive(sim, "parent", request(sim, "parent", "remove", { "parent", "confirm" })))
    assert(not ns.FamilyReset(child, false))
    assert(receive(sim, "parent", request(sim, "parent", "remove", { "parent", "stop" })))
    assert(child.profile.supervision == "unpaired" and child.profile.generation ~= generation)
    assert(not receive(sim, "parent", old))
    pair(sim, "child", "parent2", "87654321")
    assert(not child.profile.guardians.parent and child.profile.guardians.parent2)
    assert(not receive(sim, "parent", old))
    child.profile = ns.NormalizeSettings({ schemaVersion = 999 })
    assert(child.profile.supervision == "recovery")
    assert(not ns.FamilyInvite(child, "parent", "12345678", sim.now))
    assert(not ns.FamilyReset(child, false))
    assert(ns.FamilyReset(child, true))
    assert(child.profile.supervision == "unpaired" and not child.profile.damaged)
end)

test("strict operation schemas and malformed persisted authority fail closed", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    local valid = assert(ns.DecodeMessage(policy(sim, "parent")))
    valid[#valid + 1] = "spoofed-sender"
    assert(not receive(sim, "parent", assert(ns.EncodeMessage(valid))))
    assert(not receive(sim, "parent2", policy(sim, "parent")))
    assert(not receive(sim, "parent", string.rep("x", 2049)))
    local bads = {
        { parent = { high = 1, entries = { x = { wire = "x", result = "applied" } } } },
        { stranger = { high = 1, entries = {} } },
        { parent = { high = math.huge, entries = {} } },
    }
    for _, bad in ipairs(bads) do
        local profile = ns.NormalizeSettings(nil)
        profile.role, profile.supervision, profile.guardians = "child", "paired", { parent = true }
        profile.familyReplay = bad
        assert(ns.NormalizeSettings(profile).supervision == "recovery")
    end
end)

test("single-client command workflow uses production pairing and remains isolated", function()
    local command = commands.KINWARDSIM
    command("reset")
    command("family-reset")
    command("check child party read")
    assert(output[#output]:find("allowed=true", 1, true))
    command("invite child parent 12345678")
    command("pair parent child 12345678")
    command("pump")
    command("pending child")
    assert(output[#output]:find("parent parent:1", 1, true))
    command("confirm child parent parent:1 confirm")
    command("check child party read")
    assert(output[#output]:find("allowed=false", 1, true))
    command("sync parent child")
    command("pump")
    command("grant parent child party read indefinite")
    command("pump")
    command("check child party read")
    assert(output[#output]:find("allowed=true", 1, true))
    command("invite child parent2 87654321")
    command("pair parent2 child 87654321")
    command("pump")
    command("add parent child parent2 parent2:1 confirm")
    command("pump")
    command("sync parent2 child")
    command("pump")
    command("remove parent2 child parent confirm")
    command("pump")
    command("history parent child")
    command("pump")
    assert(output[#output]:find("unauthorized", 1, true))
    command("stop child confirm")
    command("check child party read")
    assert(output[#output]:find("allowed=true", 1, true))
    assert(ns.settings == live and live.sentinel and next(live, "sentinel") == nil)
end)

test(
    "canonical integer sequence and exact policy modes; revocation cannot be replayed away",
    function()
        local sim, child = fresh()
        pair(sim, "child", "parent")
        local fields = assert(ns.DecodeMessage(policy(sim, "parent")))
        fields[5], fields[3] = "1.5", "parent:1.5"
        assert(not ns.DecodeMessage(assert(ns.EncodeMessage(fields))))
        local first = policy(sim, "parent")
        assert(receive(sim, "parent", first))
        assert(
            receive(
                sim,
                "parent",
                request(sim, "parent", "policy", { "party", "read", "revoke", "", "", "" })
            )
        )
        assert(not child.profile.policy.channels.party.read)
        assert(receive(sim, "parent", first))
        assert(not child.profile.policy.channels.party.read)
        assert(
            not receive(
                sim,
                "parent",
                request(sim, "parent", "policy", { "party", "read", "indefinite", "1", "", "" })
            )
        )
        assert(
            not receive(
                sim,
                "parent",
                request(
                    sim,
                    "parent",
                    "policy",
                    { "whisper-character", "read", "indefinite", "", "", "NoRealm" }
                )
            )
        )
        assert(
            receive(
                sim,
                "parent",
                request(
                    sim,
                    "parent",
                    "policy",
                    { "whisper-character", "read", "indefinite", "", "", "Friend-TestRealm" }
                )
            )
        )
        assert(
            receive(
                sim,
                "parent",
                request(
                    sim,
                    "parent",
                    "policy",
                    { "whisper-character", "read", "revoke", "", "", "Friend-TestRealm" }
                )
            )
        )
        assert(not next(child.profile.policy.whispers))
    end
)

test("fresh generation failures leave authority and policy unchanged", function()
    local sim, child = fresh()
    child.freshToken = function()
        return child.profile.generation
    end
    assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
    assert(receive(sim, "parent", request(sim, "parent", "pair", { "12345678" })))
    assert(
        not ns.FamilyConfirm(
            child,
            "parent",
            child.pending.operation,
            true,
            sim.now,
            sim.endpoints.child.friends
        )
    )
    assert(child.profile.supervision == "unpaired" and not next(child.profile.guardians))
    child.freshToken = function()
        return "fresh-first-generation"
    end
    assert(
        ns.FamilyConfirm(
            child,
            "parent",
            child.pending.operation,
            true,
            sim.now,
            sim.endpoints.child.friends
        )
    )
    assert(receive(sim, "parent", policy(sim, "parent")))
    child.profile.queues.delivery = { "keep" }
    assert(not ns.FamilyReset(child, true))
    assert(
        child.profile.guardians.parent
            and child.profile.policy.channels.party.read
            and #child.profile.queues.delivery == 1
    )
end)

test("bounded destinations, outstanding work and guardian membership", function()
    local sim, child = fresh()
    local parent = sim.endpoints.parent.family
    for i = 1, 16 do
        assert(ns.FamilyRequest(parent, "child" .. i, "initial", "sync", {}))
    end
    assert(not ns.FamilyRequest(parent, "child17", "initial", "sync", {}))
    for _ = 17, 64 do
        assert(ns.FamilyRequest(parent, "child1", "initial", "sync", {}))
    end
    assert(not ns.FamilyRequest(parent, "child1", "initial", "sync", {}))
    sim, child = fresh()
    pair(sim, "child", "parent")
    for i = 1, 7 do
        child.profile.guardians["fixture" .. i] = true
    end
    assert(ns.NormalizeSettings(child.profile).supervision == "paired")
    assert(ns.FamilyInvite(child, "parent2", "87654321", sim.now))
    assert(receive(sim, "parent2", request(sim, "parent2", "pair", { "87654321" })))
    local ok, reason = receive(
        sim,
        "parent",
        request(sim, "parent", "add", { "parent2", child.pending.operation, "confirm" })
    )
    assert(not ok and reason == "guardian-limit" and not child.profile.guardians.parent2)
    child.profile.guardians.overflow = true
    assert(ns.NormalizeSettings(child.profile).supervision == "recovery")
end)

test(
    "old state replies cannot roll a guardian child record back after membership change",
    function()
        local sim, child = fresh()
        pair(sim, "child", "parent")
        local first = request(sim, "parent", "sync")
        local _, _, oldReply = receive(sim, "parent", first)
        local generation = child.profile.generation
        pair(sim, "child", "parent2", "87654321")
        sync(sim, "parent", "child")
        local parent = sim.endpoints.parent.family
        assert(parent.profile.childProfiles.child.generation ~= generation)
        local ok, reason = ns.FamilyReply(parent, "child", oldReply)
        assert(not ok and reason == "stale-reply")
        assert(parent.profile.childProfiles.child.generation == child.profile.generation)
    end
)

test("malformed authority preserves original evidence; old schema gains additive fields", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    local profile = child.profile
    local generation = profile.generation
    profile.familyReplay, profile.familySequence, profile.childProfiles = nil, nil, nil
    assert(ns.NormalizeSettings(profile) == profile)
    assert(profile.supervision == "paired" and profile.generation == generation)
    profile.familyReplay = false
    local normalized = ns.NormalizeSettings(profile)
    assert(normalized.supervision == "recovery" and normalized.damaged == profile)
    assert(profile.supervision == "paired" and profile.familyReplay == false)
    assert(ns.NormalizeSettings(normalized).damaged == profile)
end)

test("pair retries are idempotent and a revoked guardian can explicitly re-pair", function()
    local sim, child = fresh()
    assert(ns.FamilyInvite(child, "parent", "12345678", sim.now))
    local wire = request(sim, "parent", "pair", { "12345678" })
    local ok, reason, ack = receive(sim, "parent", wire)
    assert(ok and reason == "confirmation-required" and ack)
    local deadline, attempts = child.pending.expires, child.attempts
    local _, _, duplicateAck = receive(sim, "parent", wire)
    assert(duplicateAck == ack and child.pending.expires == deadline and child.attempts == attempts)
    assert(
        ns.FamilyConfirm(
            child,
            "parent",
            child.pending.operation,
            true,
            sim.now,
            sim.endpoints.child.friends
        )
    )
    sync(sim, "parent", "child")
    local stale = sim.endpoints.parent.profile.childProfiles.child.generation
    assert(ns.FamilyReset(child, true))
    pair(sim, "child", "parent", "87654321")
    assert(child.profile.generation ~= stale)
    sync(sim, "parent", "child")
    assert(sim.endpoints.parent.profile.childProfiles.child.generation == child.profile.generation)
    assert(receive(sim, "parent", policy(sim, "parent")))
end)

test("simulator clears generation-bound packets and exposes protocol revocation", function()
    local sim, child = fresh()
    pair(sim, "child", "parent")
    pair(sim, "child", "parent2", "87654321")
    sync(sim, "parent2", "child")
    assert(ns.SimFamilySend(sim, "parent2", "child", "remove", { "parent", "confirm" }))
    assert(ns.SimEnqueue(sim, "parent", "child", policy(sim, "parent")))
    assert(ns.SimDeliver(sim))
    assert(#sim.queue == 0 and not child.profile.guardians.parent)
    local command = commands.KINWARDSIM
    command("reset")
    command("family-reset")
    command("invite child parent 12345678")
    command("pair parent child 12345678")
    command("pump")
    command("confirm child parent parent:1 confirm")
    command("sync parent child")
    command("pump")
    command("grant parent child party read indefinite")
    command("pump")
    command("revoke parent child party read")
    command("pump")
    command("check child party read")
    assert(output[#output]:find("allowed=false", 1, true))
    command("remove parent child parent confirm")
    command("pump")
    assert(output[#output]:find("stop-confirmation-required", 1, true))
    command("remove parent child parent stop")
    command("pump")
    command("check child party read")
    assert(output[#output]:find("allowed=true", 1, true))
end)

print(string.format("%d phase 3 tests passed (Lua %s)", passed, _VERSION))
