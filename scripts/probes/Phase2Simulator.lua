local _, ns = ...
---@cast ns GuardianNamespace

---@return GuardianSimulator
function ns.NewSimulator()
    ---@type GuardianSimulator
    local sim = {
        now = 1000,
        delay = 0,
        loss = false,
        duplicate = false,
        token = 0,
        familyMode = false,
        endpoints = {},
        queue = {},
    }
    for _, id in ipairs({ "parent", "parent2", "child", "child2" }) do
        local profile = ns.NormalizeSettings(nil)
        local child = id == "child" or id == "child2"
        profile.role = child and "child" or "guardian"
        profile.supervision = child and "paired" or "unpaired"
        profile.generation = "fixture-" .. id
        if child then
            profile.guardians = { parent = true, parent2 = true }
        else
            profile.children = { child = true, child2 = true }
        end
        ns.BeginSession(profile, id .. ":1")
        sim.endpoints[id] = {
            profile = profile,
            online = true,
            offset = 0,
            login = 1,
            family = ns.NewFamily(profile, id, function()
                sim.token = sim.token + 1
                return "sim-generation:" .. sim.token
            end),
            friends = { parent = true, parent2 = true, child = true, child2 = true },
        }
    end
    return sim
end

---@param sim GuardianSimulator
---@param id string
---@return GuardianContext
function ns.SimContext(sim, id)
    local endpoint = sim.endpoints[id]
    return {
        now = sim.now + endpoint.offset,
        sessionId = endpoint.profile.sessionId or "missing",
        accounts = { ["guardian-testrealm"] = "parent", ["friend-testrealm"] = "friend" },
    }
end

---@param sim GuardianSimulator
---@param sender string
---@param recipient string
---@param channel string Use whisper-character or whisper-account for bidirectional grants.
---@param direction 'read'|'send'
---@param grant GuardianGrant
---@param target? string
---@return boolean
function ns.SimSend(sim, sender, recipient, channel, direction, grant, target)
    local from, to = sim.endpoints[sender], sim.endpoints[recipient]
    if not from or not to or not from.online or not ns.ValidGrant(grant) then
        return false
    end
    local arguments = {
        channel,
        direction,
        grant.mode,
        grant.expiresAt and tostring(grant.expiresAt) or "",
        grant.sessionId or "",
        target or "",
    }
    if sim.familyMode then
        return ns.SimFamilySend(sim, sender, recipient, "policy", arguments)
    end
    local sequence = (from.profile.familySequence[recipient] or 0) + 1
    from.profile.familySequence[recipient] = sequence
    local wire = ns.EncodeMessage({
        "1",
        "policy",
        sender .. ":" .. sequence,
        to.profile.generation,
        tostring(sequence),
        channel,
        direction,
        grant.mode,
        grant.expiresAt and tostring(grant.expiresAt) or "",
        grant.sessionId or "",
        target or "",
    })
    return wire ~= nil and ns.SimEnqueue(sim, sender, recipient, wire)
end

---@param sim GuardianSimulator
---@param index? integer Select a packet to exercise reordering.
---@return boolean, string
function ns.SimDeliver(sim, index)
    index = index or 1
    local packet = sim.queue[index]
    if not packet then
        return false, "empty"
    end
    local endpoint = sim.endpoints[packet.recipient]
    if packet.due > sim.now or not endpoint.online then
        return false, "waiting"
    end
    table.remove(sim.queue, index)
    local generation = endpoint.profile.generation
    local applied, reason, reply = ns.FamilyReceive(
        endpoint.family,
        packet.sender,
        packet.wire,
        sim.now + endpoint.offset,
        endpoint.friends
    )
    if generation ~= endpoint.profile.generation then
        for i = #sim.queue, 1, -1 do
            if
                sim.queue[i].sender == packet.recipient
                or sim.queue[i].recipient == packet.recipient
            then
                table.remove(sim.queue, i)
            end
        end
    end
    if reply and sim.endpoints[packet.sender].online then
        ns.FamilyReply(sim.endpoints[packet.sender].family, packet.recipient, reply)
    end
    return applied, reason
end

---@param sim GuardianSimulator
---@param sender string
---@param recipient string
---@param wire string
---@return boolean
function ns.SimEnqueue(sim, sender, recipient, wire)
    if
        not sim.endpoints[sender]
        or not sim.endpoints[recipient]
        or not sim.endpoints[sender].online
    then
        return false
    end
    if sim.loss then
        return true
    end
    local copies = sim.duplicate and 2 or 1
    if #sim.queue + copies > 64 then
        return false
    end
    for _ = 1, copies do
        sim.queue[#sim.queue + 1] =
            { sender = sender, recipient = recipient, wire = wire, due = sim.now + sim.delay }
    end
    return true
end

---@param sim GuardianSimulator
---@param sender string
---@param recipient string
---@param kind string
---@param arguments string[]
---@return boolean
function ns.SimFamilySend(sim, sender, recipient, kind, arguments)
    local from, to = sim.endpoints[sender], sim.endpoints[recipient]
    if not from or not to then
        return false
    end
    local child = from.profile.childProfiles[recipient]
    local generation = child and child.generation or to.profile.generation
    local wire = ns.FamilyRequest(from.family, recipient, generation, kind, arguments)
    return wire ~= nil and ns.SimEnqueue(sim, sender, recipient, wire)
end

---@param sim GuardianSimulator
function ns.SimFreshFamily(sim)
    sim.familyMode = true
    sim.queue = {}
    for id, endpoint in pairs(sim.endpoints) do
        endpoint.profile = ns.NormalizeSettings(nil)
        endpoint.profile.role = id:find("child", 1, true) == 1 and "child" or "guardian"
        ns.BeginSession(endpoint.profile, id .. ":" .. endpoint.login)
        endpoint.family = ns.NewFamily(endpoint.profile, id, function()
            sim.token = sim.token + 1
            return "sim-generation:" .. sim.token
        end)
    end
end

-- Phase 4 exercises real fragmentation, receipts, retries and acknowledgements.
-- Neither this network nor its dashboards can obtain the live profile/transport.
---@return GuardianNetworkSimulator
function ns.NewNetworkSimulator()
    local sim = ns.NewSimulator()
    ns.SimFreshFamily(sim)
    local network = {
        sim = sim,
        transports = {},
        dashboards = {},
        routes = { parent = 1, parent2 = 2, child = 3, child2 = 4 },
    }
    for id, endpoint in pairs(sim.endpoints) do
        local sender, source = id, endpoint
        local transport = ns.NewTransport(endpoint.family, {
            instance = "sim-" .. id,
            now = function()
                return sim.now + source.offset
            end,
            friends = function()
                return source.friends
            end,
            resolve = function(peer)
                local target = sim.endpoints[peer]
                return source.online and target and target.online and network.routes[peer] or nil
            end,
            send = function(route, packet)
                local recipient
                for peer, handle in pairs(network.routes) do
                    if handle == route then
                        recipient = peer
                    end
                end
                if not recipient or not source.online or not sim.endpoints[recipient].online then
                    return "unreachable"
                end
                if #sim.queue >= 256 then
                    return "throttled"
                end
                if not sim.loss then
                    sim.queue[#sim.queue + 1] = {
                        sender = sender,
                        recipient = recipient,
                        wire = packet,
                        due = sim.now + sim.delay,
                    }
                    if sim.duplicate and #sim.queue < 256 then
                        sim.queue[#sim.queue + 1] = {
                            sender = sender,
                            recipient = recipient,
                            wire = packet,
                            due = sim.now + sim.delay,
                        }
                    end
                end
                return "sent"
            end,
        })
        network.transports[id] = transport
        network.dashboards[id] = ns.NewDashboard(endpoint.profile, transport)
    end
    return network
end

---@param network GuardianNetworkSimulator
---@param seconds number
function ns.NetworkAdvance(network, seconds)
    local sim = network.sim
    for _ = 1, math.min(1500, math.floor(seconds * 5)) do
        sim.now = sim.now + 0.2
        for _, transport in pairs(network.transports) do
            ns.TransportTick(transport)
        end
        for i = #sim.queue, 1, -1 do
            local packet = sim.queue[i]
            if packet.due <= sim.now then
                table.remove(sim.queue, i)
                if sim.endpoints[packet.recipient].online then
                    ns.TransportReceive(
                        network.transports[packet.recipient],
                        packet.sender,
                        packet.wire
                    )
                end
            end
        end
    end
end

-- This file is staged explicitly and never included in distribution manifests.
-- All state is held in this closure, with no reference to GuardianDB/ns.settings.
local active, network
local demoDriver
-- Explicit developer activation only. The driver advances injected fixture time;
-- it never calls live chat/Battle.net or accesses SavedVariables.
function ns.ShowNetworkDemo()
    network = network or ns.NewNetworkSimulator()
    for _, dashboard in pairs(network.dashboards) do
        dashboard.demo = network
    end
    if not demoDriver then
        demoDriver = CreateFrame("Frame")
        local elapsed = 0
        demoDriver:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + delta
            if elapsed >= 0.2 then
                ns.NetworkAdvance(network, elapsed)
                elapsed = 0
            end
        end)
    end
    ns.ShowDashboard(network.dashboards.parent)
end
SLASH_GUARDIANSIM1 = "/guardiansim"
SlashCmdList.GUARDIANSIM = function(message)
    local words = {}
    for word in message:gmatch("%S+") do
        words[#words + 1] = word
    end
    local command = words[1]
    if command == "network-reset" then
        if network then
            for _, dashboard in pairs(network.dashboards) do
                if dashboard.window then
                    dashboard.window:Hide()
                end
            end
        end
        network = ns.NewNetworkSimulator()
        print(
            "Guardian SIM network: isolated unpaired endpoints; receipts/acks use fault controls."
        )
        return
    elseif command == "network-pump" and network then
        ns.NetworkAdvance(network, tonumber(words[2]) or 5)
        print("Guardian SIM network: time=" .. network.sim.now)
        return
    elseif command == "network" and network and network.dashboards[words[2]] then
        local input = {}
        for i = 3, #words do
            input[#input + 1] = words[i]
        end
        local d = network.dashboards[words[2]]
        print("Guardian SIM network: " .. ns.DashboardCommand(d, table.concat(input, " ")))
        return
    elseif command == "network-status" and network and network.dashboards[words[2]] then
        print(ns.DashboardText(network.dashboards[words[2]]))
        return
    elseif command == "network-ui" and network and network.dashboards[words[2]] then
        ns.ShowDashboard(network.dashboards[words[2]])
        return
    elseif command == "network-loss" and network then
        network.sim.loss = words[2] == "on"
        return
    elseif command == "network-delay" and network then
        network.sim.delay = math.max(0, math.min(60, tonumber(words[2]) or 0))
        return
    elseif command == "network-duplicate" and network then
        network.sim.duplicate = words[2] == "on"
        return
    elseif command == "network-connect" and network and network.sim.endpoints[words[2]] then
        network.sim.endpoints[words[2]].online = words[3] == "on"
        return
    end
    if command == "reset" then
        active = ns.NewSimulator()
        print("Guardian SIM: reset synthetic parent/parent2/child/child2; live state untouched.")
        return
    end
    if not active then
        print("Guardian SIM: /guardiansim reset first. See docs/PHASE2_SIMULATOR.md.")
        return
    end
    local sim = active
    local endpoint = sim.endpoints[words[2]]
    if command == "family-reset" then
        ns.SimFreshFamily(sim)
    elseif command == "invite" and endpoint then
        print(
            "Guardian SIM: invited="
                .. tostring(
                    ns.FamilyInvite(
                        endpoint.family,
                        words[3],
                        words[4] or "",
                        sim.now + endpoint.offset
                    )
                )
        )
        return
    elseif command == "confirm" and endpoint then
        local ok, reason = ns.FamilyConfirm(
            endpoint.family,
            words[3],
            words[4],
            words[5] == "confirm",
            sim.now + endpoint.offset,
            endpoint.friends
        )
        print("Guardian SIM: " .. tostring(ok) .. " " .. reason)
        return
    elseif command == "stop" and endpoint then
        local ok, reason = ns.FamilyReset(endpoint.family, words[3] == "confirm")
        if ok then
            for i = #sim.queue, 1, -1 do
                if sim.queue[i].sender == words[2] or sim.queue[i].recipient == words[2] then
                    table.remove(sim.queue, i)
                end
            end
        end
        print("Guardian SIM: " .. tostring(ok) .. " " .. reason)
        return
    elseif command == "pending" and endpoint then
        local pending = endpoint.family.pending
        print(
            "Guardian SIM: pending="
                .. (pending and (pending.peer .. " " .. pending.operation) or "none")
        )
        return
    elseif command == "friend" and endpoint and sim.endpoints[words[3]] then
        endpoint.friends[words[3]] = words[4] == "on"
    elseif
        (
            command == "pair"
            or command == "sync"
            or command == "history"
            or command == "add"
            or command == "remove"
        )
        and endpoint
        and sim.endpoints[words[3]]
    then
        local arguments = {}
        for i = 4, #words do
            arguments[#arguments + 1] = words[i]
        end
        print(
            "Guardian SIM: queued="
                .. tostring(ns.SimFamilySend(sim, words[2], words[3], command, arguments))
        )
        return
    elseif command == "advance" or command == "delay" then
        local seconds = tonumber(words[2])
        if seconds and seconds >= 0 and seconds < math.huge then
            if command == "advance" then
                sim.now = sim.now + seconds
            else
                sim.delay = seconds
            end
        end
    elseif command == "loss" or command == "duplicate" then
        sim[command] = words[2] == "on"
    elseif command == "connect" and endpoint then
        endpoint.online = words[3] == "on"
    elseif command == "clock" and endpoint then
        local offset = tonumber(words[3])
        if offset and offset == offset and math.abs(offset) < math.huge then
            endpoint.offset = offset
        end
    elseif (command == "login" or command == "reload") and endpoint then
        if command == "login" then
            endpoint.login = endpoint.login + 1
        end
        endpoint.profile = ns.NormalizeSettings(endpoint.profile)
        endpoint.family = ns.NewFamily(endpoint.profile, words[2], endpoint.family.freshToken)
        ns.BeginSession(endpoint.profile, words[2] .. ":" .. endpoint.login)
    elseif command == "revoke" and endpoint and sim.endpoints[words[3]] then
        print(
            "Guardian SIM: queued="
                .. tostring(
                    ns.SimFamilySend(
                        sim,
                        words[2],
                        words[3],
                        "policy",
                        { words[4] or "", words[5] or "", "revoke", "", "", words[6] or "" }
                    )
                )
        )
        return
    elseif command == "grant" and endpoint and sim.endpoints[words[3]] then
        local mode = words[6]
        if
            (words[5] ~= "read" and words[5] ~= "send")
            or (mode ~= "indefinite" and mode ~= "session" and mode ~= "duration")
        then
            print("Guardian SIM: invalid grant direction/mode.")
            return
        end
        -- Fixture command uses the recipient clock/session as the application context.
        local grant = ns.NewGrant(mode, ns.SimContext(sim, words[3]), tonumber(words[7]))
        print(
            "Guardian SIM: queued="
                .. tostring(
                    grant ~= nil
                        and ns.SimSend(sim, words[2], words[3], words[4], words[5], grant, words[8])
                )
        )
        return
    elseif command == "pump" then
        local index = tonumber(words[2]) or 1
        local applied, reason = ns.SimDeliver(sim, index)
        print("Guardian SIM: " .. tostring(applied) .. " " .. reason)
        return
    elseif command == "check" and endpoint and (words[4] == "read" or words[4] == "send") then
        local allowed, reason = ns.Evaluate(endpoint.profile, words[3], words[4], {
            character = words[5],
            account = words[6],
        }, ns.SimContext(sim, words[2]))
        print("Guardian SIM: allowed=" .. tostring(allowed) .. " " .. reason)
        return
    end
    print(string.format("Guardian SIM: time=%s queued=%d; fixtures only", sim.now, #sim.queue))
end
