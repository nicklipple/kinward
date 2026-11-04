local _, ns = ...
---@cast ns KinwardNamespace

-- Explicit, nonpersistent test activation. This does not record client acceptance.
---@param command string
---@return string
function ns.LiveTestCommand(command)
    local p = ns.settings
    if not ns.initialized or not p then
        return "Kinward is not initialized."
    end
    if command == "status" then
        local t = ns.liveTestTransport
        return t
                and ("LIVE TEST (unverified) · account " .. t.family.id .. " · received " .. (t.testReceived or 0) .. " engine-mapped packets · chat " .. (ns.chat and "active" or "inactive"))
            or "Live test is inactive. On both consenting accounts, choose roles, then /kinward test start."
    end
    if command == "stop" then
        if ns.chat then
            ns.chat.stop()
        end
        if ns.liveTestTransport and ns.liveTestTransport.stop then
            ns.liveTestTransport.stop()
        end
        ns.liveTestTransport = nil
        if ns.dashboard then
            ns.dashboard.transport, ns.dashboard.chat = nil, nil
        end
        return "Live test stopped. Reload WoW to clear wrappers/taint. Saved supervision and permissions remain."
    end
    if command ~= "start" then
        return "Commands: /kinward test start | status | stop"
    end
    if ns.liveTestTransport then
        return ns.LiveTestCommand("status")
    end
    if p.role ~= "child" and p.role ~= "guardian" then
        return "Choose Child role or Guardian role in /kinward ui first."
    end
    local _, account = BNGetInfo()
    local guid = UnitGUID("player")
    if
        not canaccessvalue(account)
        or not ns.ValidIdentifier(account)
        or not canaccessvalue(guid)
        or type(guid) ~= "string"
        or not ns.ValidIdentifier(guid)
    then
        return "Battle.net account/player identity is unavailable. Log in fully and try again."
    end
    -- Test identifiers bind the engine's account/character to time and a durable
    -- local counter. They are not claimed to be production authentication secrets.
    local function token()
        local counter = p.liveTestCounter
        if
            type(counter) ~= "number"
            or counter ~= counter
            or counter < 0
            or counter >= 2147483646
        then
            counter = 0
        end
        counter = math.floor(counter) + 1
        p.liveTestCounter = counter
        return "test:"
            .. guid
            .. ":"
            .. GetServerTime()
            .. ":"
            .. string.format("%.6f", GetTimePreciseSec())
            .. ":"
            .. counter
    end
    token() -- Advance the durable counter for this test activation.
    local instance = "test-"
        .. guid:gsub("[^%w]", ""):sub(-6)
        .. "-"
        .. GetServerTime()
        .. "-"
        .. p.liveTestCounter
    local family = ns.NewFamily(p, account, token)
    local t, reason = ns.NewWoWTransport(family, instance, false, true)
    if not t then
        return "Live test could not start: " .. reason
    end
    local adapter, chatReason = ns.NewWoWChat(p, {
        account = ns.ResolveWoWChatAccount,
        freshSession = token,
        selfCharacter = function()
            local name, realm = UnitFullName("player")
            if not canaccessvalue(name) or not canaccessvalue(realm) then
                return nil
            end
            realm = realm or GetNormalizedRealmName()
            return ns.CharacterKey(name, realm)
        end,
    }, false, true)
    if not adapter then
        if t.stop then
            t.stop()
        end
        return "Live test could not start chat: " .. chatReason
    end
    -- Activation can occur after PLAYER_ENTERING_WORLD. New test activation
    -- deliberately starts a fresh session, expiring previous session grants.
    ns.liveTestTransport = t
    ns.dashboard = ns.dashboard or ns.NewDashboard(p, t, GetServerTime, adapter.chat)
    ns.dashboard.transport, ns.dashboard.chat = t, adapter.chat
    ns.dashboard.message =
        "LIVE TEST: candidate whisper/party monitoring only; enforcement and routing are unverified."
    ns.ShowDashboard(ns.dashboard, "family")
    return ns.LiveTestCommand("status")
end
