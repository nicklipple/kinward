local _, ns = ...
---@cast ns KinwardNamespace

---@return string
function ns.RuntimeStatus()
    local t = ns.transport
    if t then
        local traffic = t.traffic
        return "Connected as "
            .. t.family.id
            .. " · chat monitoring "
            .. (ns.chat and "active" or "connecting")
            .. " · "
            .. t.family.profile.role
            .. "/"
            .. t.family.profile.supervision
            .. " · policy "
            .. (t.family.profile.policyRevision or 0)
            .. (ns.chat and (" · blocked reads " .. ns.chat.chat.blockedReads .. " · blocked sends " .. ns.chat.chat.blockedSends .. " · source history " .. (t.family.profile.history and #t.family.profile.history.records or 0)) or "")
            .. (
                traffic
                    and (" · sent " .. traffic.sent .. " · received " .. traffic.received .. " · unknown senders " .. traffic.unmapped .. " · last send " .. traffic.lastSend .. " · last receive " .. traffic.lastReceive)
                or ""
            )
    end
    return ns.runtimeStatus or "Connecting to Battle.net."
end

-- Settings are initialized on ADDON_LOADED; character/session identity is ready
-- at PLAYER_ENTERING_WORLD. Missing Battle.net identity is retried automatically.
---@return boolean
function ns.StartRuntime()
    local p = ns.settings
    if not ns.initialized or not p or not ns.runtimeWorldReady then
        ns.runtimeStatus = "Waiting for the character to enter the world."
        return false
    end
    local guid = UnitGUID("player")
    if not canaccessvalue(guid) or type(guid) ~= "string" or not ns.ValidIdentifier(guid) then
        ns.runtimeStatus = "Waiting for player identity."
        return false
    end
    local function token()
        local counter = p.runtimeCounter or p.liveTestCounter
        if
            type(counter) ~= "number"
            or counter ~= counter
            or counter < 0
            or counter >= 2147483646
        then
            counter = 0
        end
        counter = math.floor(counter) + 1
        p.runtimeCounter = counter
        return "kinward:"
            .. guid
            .. ":"
            .. GetServerTime()
            .. ":"
            .. string.format("%.6f", GetTimePreciseSec())
            .. ":"
            .. counter
    end
    if not ns.runtimeSession then
        ns.runtimeSession = ns.runtimeReload and p.sessionId or token()
    end
    if not ns.chat then
        local adapter, reason = ns.NewWoWChat(p, {
            account = ns.ResolveWoWChatAccount,
            freshSession = token,
            sessionId = ns.runtimeSession,
            selfCharacter = function()
                local name, realm = UnitFullName("player")
                if not canaccessvalue(name) or not canaccessvalue(realm) then
                    return nil
                end
                realm = realm or GetNormalizedRealmName()
                return ns.CharacterKey(name, realm)
            end,
        })
        if not adapter then
            ns.runtimeStatus = "Chat monitoring could not start: " .. reason
            return false
        end
    end
    if not ns.transport then
        local _, account = BNGetInfo()
        if
            not canaccessvalue(account)
            or type(account) ~= "string"
            or not ns.ValidIdentifier(account)
        then
            ns.runtimeStatus =
                "Waiting for Battle.net connection. Pairing reconnects automatically."
            if ns.dashboard then
                ns.dashboard.chat = ns.chat and ns.chat.chat
                ns.dashboard.connectionStatus = ns.runtimeStatus
            end
            return false
        end
        token()
        local instance = "kw-"
            .. guid:gsub("[^%w]", ""):sub(-6)
            .. "-"
            .. GetServerTime()
            .. "-"
            .. p.runtimeCounter
        local family = ns.NewFamily(p, account, token)
        local t, reason = ns.NewWoWTransport(family, instance)
        if not t then
            ns.runtimeStatus = "Pairing could not connect: " .. reason
            return false
        end
        ns.transport = t
    end
    ns.runtimeStatus = ns.RuntimeStatus()
    if ns.dashboard then
        ns.dashboard.transport = ns.transport
        ns.dashboard.chat = ns.chat and ns.chat.chat
        ns.dashboard.connectionStatus = ns.runtimeStatus
    end
    return true
end
