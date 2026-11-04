local _, ns = ...
---@cast ns GuardianNamespace

-- All clocks, identity and I/O are injected. No numeric WoW handle is persisted.
---@param family GuardianFamily
---@param io GuardianTransportIO
---@return GuardianTransport
function ns.NewTransport(family, io)
    return {
        family = family,
        io = io,
        serial = 0,
        work = {},
        incoming = {},
        contacts = {},
        snapshots = {},
        completedSnapshots = {},
        nextSend = 0,
    }
end

local function size(values)
    local n = 0
    for _ in pairs(values) do
        n = n + 1
    end
    return n
end

local function forget(t, item, state)
    item.state = state
    t.family.outgoing[item.peer .. "/" .. item.operation] = nil
end

local function enqueue(t, peer, wire, deadline, reply)
    if #t.work >= 64 then
        for index, item in ipairs(t.work) do
            if
                item.state == "applied"
                or item.state == "finished"
                or item.state == "expired"
                or item.state == "rejected"
                or item.state == "cancelled"
            then
                table.remove(t.work, index)
                break
            end
        end
    end
    local fields = ns.DecodeMessage(wire)
    if #t.work >= 64 or not fields or deadline <= t.io.now() or deadline > t.io.now() + 300 then
        return nil
    end
    t.serial = t.serial + 1
    local id = t.io.instance .. "-" .. t.serial
    if not id:match("^[%w%-]+$") or #id > 48 then
        return nil
    end
    local item = {
        peer = peer,
        wire = wire,
        deadline = deadline,
        reply = reply,
        operation = fields[3],
        generation = fields[4],
        kind = fields[2],
        sequence = fields[5],
        id = id,
        state = "pending",
        cursor = 1,
        attempts = 0,
        due = t.io.now(),
        result = "queued",
    }
    if reply then
        table.insert(t.work, 1, item)
    else
        t.work[#t.work + 1] = item
    end
    return item
end

---@param t GuardianTransport
---@param peer string
---@param kind string
---@param args string[]
---@param seconds? number
---@return GuardianDelivery?, string
function ns.TransportRequest(t, peer, kind, args, seconds)
    local now = t.io.now()
    seconds = seconds or 60
    if seconds <= 0 or seconds > 300 or seconds ~= seconds then
        return nil, "invalid-deadline"
    end
    local child = t.family.profile.childProfiles[peer]
    if kind ~= "pair" and kind ~= "sync" and not child then
        return nil, "sync-required"
    end
    local arguments = {}
    for i, value in ipairs(args) do
        arguments[i] = value
    end
    if kind == "policy" then
        if #arguments ~= 6 then
            return nil, "invalid-policy"
        end
        arguments[7] = tostring(now + seconds)
    end
    local wire =
        ns.FamilyRequest(t.family, peer, child and child.generation or "initial", kind, arguments)
    if not wire then
        return nil, "queue-full"
    end
    local item = enqueue(t, peer, wire, now + seconds, false)
    if not item then
        local fields = ns.DecodeMessage(wire)
        if fields then
            t.family.outgoing[peer .. "/" .. fields[3]] = nil
        end
    end
    return item, item and "queued" or "queue-full"
end

---@param t GuardianTransport
---@param peer string
---@return string, number?
function ns.TransportPresence(t, peer)
    local last = t.contacts[peer]
    return last and t.io.now() - last < 30 and "responding" or "unreachable", last
end

local function reply(t, peer, wire)
    local fields = ns.DecodeMessage(wire)
    if
        not fields
        or (
            fields[2] ~= "ack"
            and fields[2] ~= "state"
            and fields[2] ~= "setting"
            and fields[2] ~= "snapshot"
        )
    then
        return false
    end
    for _, item in ipairs(t.work) do
        if
            not item.reply
            and item.peer == peer
            and item.operation == fields[3]
            and item.sequence == fields[5]
            and (item.state == "pending" or item.state == "delivered")
            and t.io.now() < item.deadline
        then
            if item.kind ~= "sync" and fields[4] ~= item.generation then
                return false
            end
            local accepted, result
            if fields[2] == "snapshot" and item.kind == "snapshot" and #fields == 14 then
                local child = t.family.profile.childProfiles[peer]
                local requested = ns.DecodeMessage(item.wire)
                local revision = tonumber(fields[6])
                if
                    not child
                    or child.generation ~= fields[4]
                    or not requested
                    or fields[7] ~= requested[6]
                    or not revision
                    or revision < 0
                    or revision % 1 ~= 0
                then
                    return false
                end
                local snapshot = t.snapshots[peer]
                if fields[7] == "1" then
                    snapshot =
                        { revision = revision, generation = fields[4], settings = {}, cursor = 1 }
                    t.snapshots[peer] = snapshot
                end
                if
                    not snapshot
                    or snapshot.revision ~= revision
                    or snapshot.generation ~= fields[4]
                    or snapshot.cursor ~= tonumber(fields[7])
                then
                    return false
                end
                if fields[9] ~= "" then
                    snapshot.settings[fields[9] .. "/" .. fields[10] .. "/" .. fields[11]] = {
                        mode = fields[12],
                        expiresAt = tonumber(fields[13]),
                        sessionId = fields[14],
                        revision = revision,
                    }
                end
                t.family.outgoing[peer .. "/" .. item.operation] = nil
                accepted, result = true, "snapshot"
                if fields[8] == "done" or fields[8] == "truncated" then
                    if revision >= (child.revision or 0) then
                        child.settings, child.revision, child.result =
                            snapshot.settings, revision, "snapshot-" .. fields[8]
                        t.completedSnapshots[peer] = fields[4] .. "/" .. fields[6]
                    end
                    t.snapshots[peer] = nil
                else
                    local cursor = tonumber(fields[8])
                    if not cursor or cursor ~= tonumber(fields[7]) + 1 or cursor > 128 then
                        return false
                    end
                    snapshot.cursor = cursor
                    ns.TransportRequest(t, peer, "snapshot", { fields[8], fields[6] }, 60)
                end
            elseif fields[2] == "setting" and item.kind == "inspect" and #fields == 12 then
                local requested = ns.DecodeMessage(item.wire)
                local revision = tonumber(fields[12])
                if
                    not requested
                    or fields[6] ~= requested[6]
                    or fields[7] ~= requested[7]
                    or fields[8] ~= requested[8]
                    or not revision
                    or revision < 0
                    or revision % 1 ~= 0
                then
                    return false
                end
                local child = t.family.profile.childProfiles[peer]
                if not child or child.generation ~= fields[4] then
                    return false
                end
                if revision < (child.revision or 0) then
                    forget(t, item, "cancelled")
                    return false
                end
                child.revision = revision
                child.settings = child.settings or {}
                local bidirectional = fields[6] == "whisper-character"
                    or fields[6] == "whisper-account"
                local key = fields[6]
                    .. "/"
                    .. (bidirectional and "read" or fields[7])
                    .. "/"
                    .. fields[8]
                if bidirectional then
                    child.settings[fields[6] .. "/send/" .. fields[8]] = nil
                end
                local old = child.settings[key]
                if not old and size(child.settings) >= 128 then
                    return false
                end
                if not old or revision >= old.revision then
                    child.settings[key] = {
                        mode = fields[9],
                        expiresAt = tonumber(fields[10]),
                        sessionId = fields[11],
                        revision = revision,
                    }
                end
                accepted, result = true, "setting"
                t.family.outgoing[peer .. "/" .. item.operation] = nil
            else
                accepted, result = ns.FamilyReply(t.family, peer, wire)
                -- Older acknowledgements for independent settings still confirm their own operation.
                if result == "stale-reply" and fields[2] == "ack" and #fields == 7 then
                    local child = t.family.profile.childProfiles[peer]
                    accepted = child ~= nil and child.generation == item.generation
                    result = fields[6]
                end
            end
            if not accepted then
                return false
            end
            item.result = result
            item.revision = tonumber(fields[2] == "snapshot" and fields[6] or fields[7])
            if item.kind == "policy" and result == "applied" then
                local child = t.family.profile.childProfiles[peer]
                if child then
                    child.revision = math.max(child.revision or 0, item.revision or 0)
                end
                local requested = ns.DecodeMessage(item.wire)
                if requested then
                    ns.TransportRequest(
                        t,
                        peer,
                        "inspect",
                        { requested[6], requested[7], requested[11] },
                        60
                    )
                end
            end
            if item.kind == "policy" and result == "applied" then
                local pendingSync = false
                for _, work in ipairs(t.work) do
                    if
                        work.peer == peer
                        and work.kind == "sync"
                        and not work.reply
                        and (work.state == "pending" or work.state == "delivered")
                    then
                        pendingSync = true
                    end
                end
                if not pendingSync then
                    ns.TransportRequest(t, peer, "sync", {}, 60)
                end
            end
            item.state = (
                result == "applied"
                or result == "paired"
                or result == "setting"
                or result == "snapshot"
                or result == "guardian-added"
                or result == "guardian-removed"
                or result == "stopped"
            )
                    and "applied"
                or "rejected"
            if fields[2] == "state" then
                local child = t.family.profile.childProfiles[peer]
                child.revision, child.members = tonumber(fields[7]), {}
                local snapshotPending = false
                for _, work in ipairs(t.work) do
                    if
                        work.peer == peer
                        and work.kind == "snapshot"
                        and not work.reply
                        and work.generation == fields[4]
                        and (work.state == "pending" or work.state == "delivered")
                        and work.deadline > t.io.now()
                    then
                        snapshotPending = true
                    end
                end
                if
                    not snapshotPending
                    and t.completedSnapshots[peer] ~= fields[4] .. "/" .. fields[7]
                then
                    ns.TransportRequest(t, peer, "snapshot", { "1", "" }, 60)
                end
                for i = 8, #fields do
                    child.members[fields[i]] = true
                end
            end
            t.contacts[peer] = t.io.now()
            return true
        end
    end
    return false
end

-- Called only after an adapter authenticates the transport sender. Bound all
-- allocations before accepting fragments, including those from unpaired friends.
---@param t GuardianTransport
---@param peer string
---@param packet unknown
---@return boolean
function ns.TransportReceive(t, peer, packet)
    if not t.io.friends()[peer] or type(packet) ~= "string" or #packet > 240 then
        return false
    end
    local now = t.io.now()
    if not t.receiveWindow or now >= t.receiveWindow + 1 then
        t.receiveWindow, t.receiveCount = now, 0
    end
    t.receiveCount = (t.receiveCount or 0) + 1
    if t.receiveCount > 64 then
        return false
    end
    local receipt = packet:match("^D|([%w%-]+)$")
    if receipt then
        for _, item in ipairs(t.work) do
            if item.peer == peer and item.id == receipt and item.state == "pending" then
                item.state = "delivered"
                return true
            end
        end
        return false
    end
    local id, indexText, totalText, payload = packet:match("^F|([%w%-]+)|(%d+)|(%d+)|(.*)$")
    local index, total = tonumber(indexText), tonumber(totalText)
    if
        not id
        or #id > 48
        or not index
        or not total
        or total < 1
        or total > 12
        or index < 1
        or index > total
        or #payload > 180
    then
        return false
    end
    local key = peer .. "/" .. id
    local assembly = t.incoming[key]
    if not assembly then
        if size(t.incoming) >= 32 then
            return false
        end
        assembly = { peer = peer, total = total, parts = {}, expires = t.io.now() + 15 }
        t.incoming[key] = assembly
    end
    if assembly.total ~= total or t.io.now() >= assembly.expires then
        t.incoming[key] = nil
        return false
    end
    if assembly.parts[index] and assembly.parts[index] ~= payload then
        t.incoming[key] = nil
        return false
    end
    assembly.parts[index] = payload
    if size(assembly.parts) ~= total then
        return true
    end
    t.incoming[key] = nil
    local wire = table.concat(assembly.parts)
    if #wire > 2048 then
        return false
    end
    if reply(t, peer, wire) then
        return true
    end
    local fields = ns.DecodeMessage(wire)
    if
        not fields
        or fields[2] == "ack"
        or fields[2] == "state"
        or fields[2] == "setting"
        or (fields[2] == "snapshot" and #fields ~= 7)
    then
        return false
    end
    if fields[2] == "policy" and #fields ~= 12 then
        return false
    end
    local ok, _, response = ns.FamilyReceive(t.family, peer, wire, t.io.now(), t.io.friends())
    if response then
        -- Receipt and application acknowledgement are distinct packets. Both use
        -- the same global send budget and may independently be lost.
        local item = enqueue(t, peer, response, t.io.now() + 30, true)
        if item then
            item.receipt = "D|" .. id
        end
    end
    if ok then
        t.contacts[peer] = t.io.now()
    end
    return ok
end

---@param t GuardianTransport
function ns.TransportTick(t)
    local now = t.io.now()
    for key, assembly in pairs(t.incoming) do
        if now >= assembly.expires then
            t.incoming[key] = nil
        end
    end
    for _, item in ipairs(t.work) do
        if item.state == "pending" or item.state == "delivered" then
            local child = t.family.profile.childProfiles[item.peer]
            if now >= item.deadline then
                forget(t, item, "expired")
            elseif
                not t.io.friends()[item.peer]
                or (not item.reply and item.kind ~= "pair" and item.kind ~= "sync" and (not child or child.generation ~= item.generation))
                or (
                    item.reply
                    and (item.kind == "state" or item.kind == "setting" or item.kind == "snapshot")
                    and not ns.CanControl(t.family.profile, item.peer, item.generation)
                )
            then
                forget(t, item, "cancelled")
            elseif now >= item.due and now >= t.nextSend then
                local route = t.io.resolve(item.peer)
                if not route then
                    item.result, item.due = "unreachable", now + 2
                else
                    local count = math.ceil(#item.wire / 180)
                    local packet = item.receipt
                        or (
                            "F|"
                            .. item.id
                            .. "|"
                            .. item.cursor
                            .. "|"
                            .. count
                            .. "|"
                            .. item.wire:sub((item.cursor - 1) * 180 + 1, item.cursor * 180)
                        )
                    local result = t.io.send(route, packet)
                    t.nextSend = now + 0.15
                    item.result = result
                    if result == "sent" then
                        if item.receipt then
                            item.receipt = nil
                        elseif item.cursor < count then
                            item.cursor = item.cursor + 1
                        elseif item.reply then
                            item.state = "finished"
                        else
                            item.cursor, item.attempts = 1, item.attempts + 1
                            item.due = now + math.min(16, 2 ^ math.min(item.attempts, 4))
                        end
                    else
                        item.due = now + (result == "throttled" and 2 or 5)
                    end
                end
                return
            end
        end
    end
end
