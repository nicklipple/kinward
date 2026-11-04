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
    local known =
        { [1] = "general", [2] = "trade", [22] = "localdefense", [26] = "lookingforgroup" }
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
