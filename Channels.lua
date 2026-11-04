local _, ns = ...
---@cast ns KinwardNamespace

-- Stable policy keys: channel numbers are connection-local and never persisted.
ns.ChannelCatalog = {
    { "party", "Party" },
    { "say", "Say" },
    { "yell", "Yell" },
    { "guild", "Guild" },
    { "raid", "Raid" },
    { "instance", "Instance" },
    { "channel:general", "General" },
    { "channel:lookingforgroup", "Looking For Group" },
    { "channel:trade", "Trade" },
    { "channel:services", "Trade (Services)" },
    { "channel:localdefense", "Local Defense" },
    { "officer", "Officer" },
    { "emote", "Emotes" },
    { "communities", "Communities" },
    { "channel:custom", "Custom channels" },
    { "channel:public", "Other public" },
    { "other", "Other player chat" },
}

---@param name unknown
---@return string?
function ns.CustomChannelKey(name)
    if type(name) ~= "string" or #name == 0 or #name > 48 or name:find("[%c|]") then
        return nil
    end
    local clean = name:match("^%s*(.-)%s*$")
    return clean ~= "" and "channel:custom:" .. clean:lower() or nil
end

---@param name unknown
---@param zone unknown
---@return string
function ns.PublicChannelKey(name, zone)
    if type(zone) ~= "number" or zone < 0 or zone % 1 ~= 0 then
        return "channel:unknown"
    end
    if zone == 0 then
        return ns.CustomChannelKey(name) or "channel:unknown"
    end
    -- Static engine zone IDs are distinct from the transient /1, /2 numbers.
    local known = {
        [1] = "general",
        [2] = "trade",
        [22] = "localdefense",
        [26] = "lookingforgroup",
    }
    if known[zone] then
        return "channel:" .. known[zone]
    end
    if type(name) == "string" then
        local plain = name:lower():gsub("[%s%p]", "")
        if plain == "tradeservices" or plain == "services" then
            return "channel:services"
        end
    end
    return "channel:zone:" .. zone
end

---@param channel string
---@return string
function ns.ChannelCategory(channel)
    if channel:find("^channel:custom:") then
        return "channel:custom"
    elseif channel:find("^channel:zone:") or channel == "channel:unknown" then
        return "channel:public"
    end
    return channel
end

-- History stores a readable label separately from the stable policy key within
-- the existing channel field, preserving compatibility with older history rows.
---@param channel string
---@param name unknown
---@return string
function ns.HistoryChannel(channel, name)
    if
        channel:find("^channel:zone:")
        and type(name) == "string"
        and #name > 0
        and not name:find("[%c|]")
        and #channel + #name + 1 <= 64
    then
        return channel .. "|" .. name
    end
    return channel
end

---@param channel string
---@return string
function ns.HistoryChannelBase(channel)
    return channel:match("^(channel:zone:%d+)|") or channel
end

---@param channel string
---@return string
function ns.HistoryChannelLabel(channel)
    return channel:match("^channel:zone:%d+|(.+)$") or channel:gsub("^channel:custom:", "")
end

---@param f KinwardFamily
---@param fields string[]
---@return string?
function ns.ChannelInventoryReply(f, fields)
    local cursor = tonumber(fields[6])
    if not cursor or cursor < 1 or cursor > 64 or cursor % 1 ~= 0 then
        return nil
    end
    local rows = f.channels and f.channels() or {}
    table.sort(rows, function(a, b)
        return a[1] < b[1]
    end)
    local signature = {}
    for _, row in ipairs(rows) do
        signature[#signature + 1] = row[1] .. "=" .. row[2]
    end
    local version = table.concat(signature, "\n")
    if version ~= f.channelSignature then
        f.channelSignature = version
        f.channelVersion = (f.channelVersion or 0) + 1
    end
    local revision = tostring(f.channelVersion or 0)
    if cursor > 1 and fields[7] ~= revision then
        return nil
    end
    local row = rows[cursor]
    return ns.EncodeMessage({
        "1",
        "channels",
        fields[3],
        f.profile.generation,
        fields[5],
        revision,
        cursor < #rows and tostring(cursor + 1) or "done",
        row and row[1] or "",
        row and row[2] or "",
    })
end

---@param t KinwardTransport
---@param peer string
---@param fields string[]
---@param item KinwardDelivery
---@return boolean
function ns.AcceptChannelPage(t, peer, fields, item)
    local child = t.family.profile.childProfiles[peer]
    local request = ns.DecodeMessage(item.wire)
    if
        #fields ~= 9
        or not child
        or not t.family.profile.children[peer]
        or not child.members
        or not child.members[t.family.id]
        or child.generation ~= fields[4]
        or not request
    then
        return false
    end
    local cursor = tonumber(request[6])
    if
        not cursor
        or cursor < 1
        or cursor > 64
        or cursor % 1 ~= 0
        or not fields[6]:match("^%d+$")
        or (fields[7] ~= "done" and (tonumber(fields[7]) ~= cursor + 1 or cursor >= 64))
        or (fields[8] == "" and (fields[9] ~= "" or fields[7] ~= "done" or cursor ~= 1))
    then
        return false
    end
    if
        fields[8] ~= ""
        and (
            not fields[8]:find("^channel:")
            or fields[8]:find("[|%c]")
            or #fields[8] > 128
            or #fields[9] == 0
            or #fields[9] > 128
            or fields[9]:find("[|%c]")
        )
    then
        return false
    end
    t.channelPages = t.channelPages or {}
    if cursor == 1 then
        t.channelPages[peer] = { revision = fields[6], rows = {}, cursor = 1 }
    end
    local page = t.channelPages[peer]
    if not page or page.revision ~= fields[6] or page.cursor ~= cursor then
        return false
    end
    if fields[8] ~= "" then
        page.rows[#page.rows + 1] = { fields[8], fields[9] }
    end
    if fields[7] == "done" then
        t.joinedChannels = t.joinedChannels or {}
        t.joinedChannels[peer] = page.rows
        t.channelGenerations = t.channelGenerations or {}
        t.channelGenerations[peer] = fields[4]
        t.channelPages[peer] = nil
    else
        if tonumber(fields[7]) ~= cursor + 1 or cursor >= 64 then
            return false
        end
        page.cursor = cursor + 1
        ns.TransportRequest(t, peer, "channel-list", { fields[7], fields[6] }, 60)
    end
    t.family.outgoing[peer .. "/" .. item.operation] = nil
    return true
end

---@param t KinwardTransport
function ns.PollChannels(t)
    for peer, generation in pairs(t.channelGenerations or {}) do
        local child = t.family.profile.childProfiles[peer]
        if
            not child
            or not t.family.profile.children[peer]
            or child.generation ~= generation
            or not child.members
            or not child.members[t.family.id]
        then
            t.channelGenerations[peer] = nil
            if t.joinedChannels then
                t.joinedChannels[peer] = nil
            end
            if t.channelPages then
                t.channelPages[peer] = nil
            end
        end
    end
    if t.io.now() < (t.nextChannelPoll or 0) then
        return
    end
    t.nextChannelPoll = t.io.now() + 20
    for peer, child in pairs(t.family.profile.childProfiles) do
        if t.family.profile.children[peer] and child.members and child.members[t.family.id] then
            local pending = false
            for _, item in ipairs(t.work) do
                if
                    item.peer == peer
                    and item.kind == "channel-list"
                    and (item.state == "pending" or item.state == "delivered")
                then
                    pending = true
                end
            end
            if not pending then
                ns.TransportRequest(t, peer, "channel-list", { "1", "" }, 60)
            end
        end
    end
end
