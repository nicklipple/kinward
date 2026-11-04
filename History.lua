local _, ns = ...
---@cast ns KinwardNamespace

local dispositions = {
    allowed = true,
    blocked = true,
    ["blocked-attempt"] = true,
    attempted = true,
    output = true,
    gap = true,
}
local function integer(v, maximum)
    return type(v) == "number" and v >= 0 and v <= maximum and v % 1 == 0
end
local function clean(v, maximum)
    return type(v) == "string" and #v <= maximum and not v:find("%c")
end
local function limits(retention, count)
    return integer(retention, 2592000) and retention >= 60 and integer(count, 10000) and count >= 1
end

---@param generation string
---@return KinwardHistory
function ns.NewHistory(generation)
    return {
        generation = generation,
        records = {},
        high = 0,
        pruned = 0,
        expired = 0,
        retention = 604800,
        maxRecords = 10000,
        lastSeen = 0,
    }
end

---@param r unknown
---@return boolean
function ns.ValidHistoryRecord(r)
    return type(r) == "table"
        and integer(r.seq, 2147483647)
        and r.seq > 0
        and integer(r.time, 4102444800)
        and integer(r.endedAt, 4102444800)
        and r.endedAt >= r.time
        and (r.direction == "read" or r.direction == "send" or r.direction == "system")
        and clean(r.channel, 64)
        and r.channel ~= ""
        and clean(r.character, 128)
        and clean(r.account, 128)
        and dispositions[r.disposition] == true
        and type(r.text) == "string"
        and #r.text <= 256
        and type(r.truncated) == "boolean"
end

---@param h unknown
---@param generation string
---@return boolean
function ns.ValidHistory(h, generation)
    if
        type(h) ~= "table"
        or h.generation ~= generation
        or not limits(h.retention, h.maxRecords)
        or not integer(h.high, 2147483647)
        or not integer(h.pruned, 2147483647)
        or not integer(h.expired, 2147483647)
        or h.pruned + h.expired > h.high
        or not integer(h.lastSeen, 4102444800)
        or (h.cursor ~= nil and (not integer(h.cursor, h.high)))
        or (h.updatedAt ~= nil and not integer(h.updatedAt, 4102444800))
        or (h.cacheRemoved ~= nil and not integer(h.cacheRemoved, 9007199254740991))
        or type(h.records) ~= "table"
    then
        return false
    end
    local count, previous = 0, 0
    for key, r in pairs(h.records) do
        if
            not integer(key, h.maxRecords)
            or key < 1
            or not ns.ValidHistoryRecord(r)
            or r.seq > h.high
        then
            return false
        end
        count = count + 1
    end
    for i = 1, count do
        local r = h.records[i]
        if not r or r.seq <= previous then
            return false
        end
        previous = r.seq
    end
    if h.cursor == nil then
        if h.high ~= count + h.pruned + h.expired then
            return false
        end
        for i, r in ipairs(h.records) do
            if r.seq ~= h.pruned + h.expired + i then
                return false
            end
        end
    end
    return count <= h.maxRecords
end

---@param h KinwardHistory
---@param now number
function ns.PruneHistory(h, now)
    local keep, lastExpired = {}, 0
    -- Expiry removes a prefix, including nearby out-of-order attempt timestamps.
    for i, r in ipairs(h.records) do
        if now - r.endedAt >= h.retention then
            lastExpired = i
        end
    end
    if lastExpired == 0 and #h.records <= h.maxRecords then
        return
    end
    for i = lastExpired + 1, #h.records do
        keep[#keep + 1] = h.records[i]
    end
    local overflow = math.max(0, #keep - h.maxRecords)
    if h.cursor ~= nil then
        h.cacheRemoved = (h.cacheRemoved or 0) + lastExpired + overflow
    else
        h.expired = math.min(2147483647, h.expired + lastExpired)
        h.pruned = math.min(2147483647, h.pruned + overflow)
    end
    if overflow > 0 then
        local bounded = {}
        for i = overflow + 1, #keep do
            bounded[#bounded + 1] = keep[i]
        end
        keep = bounded
    end
    h.records = keep
end

---@param profile KinwardSettings
function ns.HistoryRelationshipChanged(profile)
    if profile.supervision == "paired" and profile.history then
        profile.history.generation = profile.generation
    else
        profile.history = ns.NewHistory(profile.generation)
    end
end

---@param profile KinwardSettings
---@param retention number
---@param count number
---@param now number
---@return boolean
function ns.ConfigureHistory(profile, retention, count, now)
    if not limits(retention, count) then
        return false
    end
    profile.history = profile.history or ns.NewHistory(profile.generation)
    profile.history.retention, profile.history.maxRecords = retention, count
    ns.PruneHistory(profile.history, now)
    return true
end

---The caller supplies only accessible strings. No child UI or debug caller reads records.
---@param profile KinwardSettings
---@param now number
---@param direction 'read'|'send'|'system'
---@param channel string
---@param identity KinwardIdentity?
---@param disposition string
---@param body string
---@param endedAt? number
---@return KinwardHistoryRecord?
function ns.AppendHistory(profile, now, direction, channel, identity, disposition, body, endedAt)
    if profile.supervision ~= "paired" or profile.role ~= "child" then
        return nil
    end
    local h = profile.history or ns.NewHistory(profile.generation)
    if h.generation ~= profile.generation or h.high >= 2147483647 then
        return nil
    end
    local r = {
        seq = h.high + 1,
        time = math.floor(now),
        endedAt = math.floor(endedAt or now),
        direction = direction,
        channel = channel,
        character = identity and identity.character or "",
        account = identity and identity.account or "",
        disposition = disposition,
        text = body:sub(1, 256),
        truncated = #body > 256,
    }
    if not ns.ValidHistoryRecord(r) then
        return nil
    end
    profile.history, h.high = h, r.seq
    h.records[#h.records + 1] = r
    ns.PruneHistory(h, now)
    return r
end

local function hex(text)
    return (
        text:gsub(".", function(byte)
            return string.format("%02x", string.byte(byte))
        end)
    )
end
local function unhex(text)
    if #text > 512 or #text % 2 ~= 0 or text:find("[^%da-f]") then
        return nil
    end
    return (text:gsub("..", function(byte)
        return string.char(tonumber(byte, 16))
    end))
end

---@param profile KinwardSettings
---@param fields string[]
---@param now number
---@return string?
function ns.HistoryBatch(profile, fields, now)
    if #fields ~= 6 then
        return nil
    end
    local cursor = tonumber(fields[6])
    local h = profile.history or ns.NewHistory(profile.generation)
    if not cursor or not integer(cursor, h.high) then
        return nil
    end
    ns.PruneHistory(h, now)
    local oldest = h.records[1] and h.records[1].seq or h.high + 1
    local values = {
        "1",
        "history-batch",
        fields[3],
        profile.generation,
        fields[5],
        fields[6],
        tostring(math.max(cursor, oldest - 1)),
        tostring(h.high),
        tostring(oldest),
        tostring(h.pruned),
        tostring(h.expired),
        tostring(h.retention),
        tostring(h.maxRecords),
    }
    local count = 0
    for _, r in ipairs(h.records) do
        if r.seq > cursor then
            local encoded = hex(r.text)
            local row = {
                tostring(r.seq),
                tostring(r.time),
                r.direction,
                r.channel,
                r.character,
                r.account,
                r.disposition,
                encoded:sub(1, 256),
                encoded:sub(257),
                tostring(r.endedAt),
                r.truncated and "1" or "0",
            }
            local before = #values
            for _, value in ipairs(row) do
                values[#values + 1] = value
            end
            local priorCursor = values[7]
            values[7] = tostring(r.seq)
            if not ns.EncodeMessage(values) then
                for i = #values, before + 1, -1 do
                    values[i] = nil
                end
                values[7] = priorCursor
                break
            end
            count = count + 1
            if count == 3 then
                break
            end
        end
    end
    return ns.EncodeMessage(values)
end

---@param t KinwardTransport
---@param peer string
---@param fields string[]
---@param item KinwardDelivery
---@return boolean
function ns.AcceptHistoryBatch(t, peer, fields, item)
    local p = t.family.profile
    local child, requested = p.childProfiles[peer], ns.DecodeMessage(item.wire)
    if
        item.peer ~= peer
        or item.kind ~= "history"
        or fields[2] ~= "history-batch"
        or fields[3] ~= item.operation
        or fields[5] ~= item.sequence
        or t.io.now() >= item.deadline
        or p.role ~= "guardian"
        or not p.children[peer]
        or not child
        or child.generation ~= fields[4]
        or not child.members
        or not child.members[t.family.id]
        or not requested
        or fields[6] ~= requested[6]
        or #fields < 13
        or #fields > 46
        or (#fields - 13) % 11 ~= 0
    then
        return false
    end
    local cursor, nextCursor, high, oldest =
        tonumber(fields[6]), tonumber(fields[7]), tonumber(fields[8]), tonumber(fields[9])
    local pruned, expired, retention, maximum =
        tonumber(fields[10]), tonumber(fields[11]), tonumber(fields[12]), tonumber(fields[13])
    if
        not cursor
        or not nextCursor
        or not high
        or not oldest
        or not pruned
        or not expired
        or not retention
        or not maximum
        or not integer(high, 2147483647)
        or not integer(cursor, high)
        or not integer(nextCursor, high)
        or not integer(oldest, high + 1)
        or oldest < 1
        or not integer(pruned, 2147483647)
        or not integer(expired, 2147483647)
        or pruned + expired > high
        or not limits(retention, maximum)
    then
        return false
    end
    local h = child.history or ns.NewHistory(child.generation)
    if h.generation ~= fields[4] or high < h.high or cursor ~= (h.cursor or 0) then
        return false
    end
    local expected, rows = math.max(cursor + 1, oldest), {}
    for i = 14, #fields, 11 do
        local body = unhex(fields[i + 7] .. fields[i + 8])
        if not body or (fields[i + 10] ~= "0" and fields[i + 10] ~= "1") then
            return false
        end
        local r = {
            seq = tonumber(fields[i]),
            time = tonumber(fields[i + 1]),
            direction = fields[i + 2],
            channel = fields[i + 3],
            character = fields[i + 4],
            account = fields[i + 5],
            disposition = fields[i + 6],
            text = body,
            endedAt = tonumber(fields[i + 9]),
            truncated = fields[i + 10] == "1",
        }
        if not ns.ValidHistoryRecord(r) or r.seq ~= expected or r.seq > high then
            return false
        end
        expected = expected + 1
        rows[#rows + 1] = r
    end
    if nextCursor ~= expected - 1 or (#rows == 0 and nextCursor < high) then
        return false
    end
    for _, r in ipairs(rows) do
        h.records[#h.records + 1] = r
    end
    h.cursor, h.high, h.retention, h.maxRecords = nextCursor, high, retention, maximum
    -- Remote loss counts are not mixed with local cache eviction counters.
    ns.PruneHistory(h, t.io.now())
    h.pruned, h.expired, h.updatedAt = pruned, expired, math.floor(t.io.now())
    child.history = h
    t.family.outgoing[peer .. "/" .. item.operation] = nil
    if nextCursor < high then
        ns.TransportRequest(t, peer, "history", { tostring(nextCursor) }, 60)
    end
    return true
end

---@param t KinwardTransport
---@param peer string
---@return boolean
function ns.WatchHistory(t, peer)
    local child = t.family.profile.childProfiles[peer]
    if
        t.family.profile.role ~= "guardian"
        or not t.family.profile.children[peer]
        or not child
        or not child.members
        or not child.members[t.family.id]
    then
        return false
    end
    t.historyWatching = t.historyWatching or {}
    t.historyWatching[peer] = true
    return true
end

---@param t KinwardTransport
function ns.PollHistory(t)
    local now = t.io.now()
    if now < (t.nextHistoryPoll or 0) then
        return
    end
    t.nextHistoryPoll = now + 5
    ns.PruneProfileHistory(t.family.profile, now)
    for peer in pairs(t.historyWatching or {}) do
        local child = t.family.profile.childProfiles[peer]
        if not ns.WatchHistory(t, peer) then
            t.historyWatching[peer] = nil
        else
            local pending = false
            for _, item in ipairs(t.work) do
                if
                    item.peer == peer
                    and item.kind == "history"
                    and (item.state == "pending" or item.state == "delivered")
                then
                    pending = true
                end
            end
            if not pending then
                ns.TransportRequest(
                    t,
                    peer,
                    "history",
                    { tostring(child.history and child.history.cursor or 0) },
                    60
                )
            end
        end
    end
end

---@param profile KinwardSettings
---@param peer string
---@param filters KinwardHistoryFilters
---@param now number
---@return KinwardHistoryRecord[]
function ns.HistoryView(profile, peer, filters, now)
    local child = profile.role == "guardian"
        and profile.children[peer]
        and profile.childProfiles[peer]
    local h = child and child.history
    if not h then
        return {}
    end
    ns.PruneHistory(h, now)
    local rows = {}
    for i = #h.records, 1, -1 do
        local r = h.records[i]
        if
            (not filters.channel or r.channel == filters.channel)
            and (not filters.direction or r.direction == filters.direction)
            and (not filters.disposition or r.disposition == filters.disposition)
            and (not filters.seconds or r.endedAt >= now - filters.seconds)
            and (not filters.from or r.endedAt >= filters.from)
            and (not filters.to or r.time <= filters.to)
            and (
                not filters.identity
                or filters.identity == ""
                or (r.character .. " " .. r.account):lower():find(filters.identity:lower(), 1, true)
            )
        then
            rows[#rows + 1] = r
        end
    end
    table.sort(rows, function(a, b)
        if a.time == b.time then
            return a.seq > b.seq
        end
        return a.time > b.time
    end)
    return rows
end

---@param profile KinwardSettings
---@param now number
function ns.PruneProfileHistory(profile, now)
    if profile.history then
        ns.PruneHistory(profile.history, now)
    end
    for _, child in pairs(profile.childProfiles) do
        if child.history then
            ns.PruneHistory(child.history, now)
        end
    end
end
