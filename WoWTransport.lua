local _, ns = ...
---@cast ns GuardianNamespace

-- Source-backed candidate route, deliberately gated until P1-ID/P1-ROUTE pass.
-- The caller must supply a verified local account identity and a fresh instance
-- identifier; this module never invents authority from a payload or character name.
---@param family GuardianFamily
---@param instance string
---@param verified boolean Recorded client routing/identity acceptance, not a user preference.
---@return GuardianTransport?, string
function ns.NewWoWTransport(family, instance, verified)
    if not verified then
        return nil, "live-routing-unverified"
    end
    local prefix = "Guardian4"
    local registered = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if registered ~= 0 and registered ~= 1 then
        return nil, "prefix-unavailable"
    end
    ---@return table<string, boolean>, table<string, number>, table<number, string>
    local function discover()
        local friends, routes, senders, ambiguous = {}, {}, {}, {}
        local count = BNGetNumFriends()
        for friendIndex = 1, math.min(count, 200) do
            local account = C_BattleNet.GetFriendAccountInfo(friendIndex)
            if
                account
                and canaccessvalue(account.battleTag)
                and canaccessvalue(account.isFriend)
                and account.isFriend
                and ns.ValidIdentifier(account.battleTag)
            then
                local peer = account.battleTag
                friends[peer] = true
                local games = C_BattleNet.GetFriendNumGameAccounts(friendIndex)
                for gameIndex = 1, math.min(games, 32) do
                    local game = C_BattleNet.GetFriendGameAccountInfo(friendIndex, gameIndex)
                    if
                        game
                        and canaccessvalue(game.gameAccountID)
                        and canaccessvalue(game.clientProgram)
                        and canaccessvalue(game.isOnline)
                        and canaccessvalue(game.wowProjectID)
                        and game.clientProgram == "WoW"
                        and game.isOnline
                        and game.wowProjectID == WOW_PROJECT_ID
                    then
                        local handle = game.gameAccountID
                        if routes[peer] and routes[peer] ~= handle then
                            ambiguous[peer] = true
                        end
                        if senders[handle] and senders[handle] ~= peer then
                            ambiguous[peer], ambiguous[senders[handle]] = true, true
                        end
                        routes[peer], senders[handle] = handle, peer
                    end
                end
            end
        end
        for peer in pairs(ambiguous) do
            routes[peer] = nil
            for handle, owner in pairs(senders) do
                if owner == peer then
                    senders[handle] = nil
                end
            end
        end
        return friends, routes, senders
    end
    local t = ns.NewTransport(family, {
        instance = instance,
        now = GetServerTime,
        friends = function()
            local friends = discover()
            return friends
        end,
        resolve = function(peer)
            local _, routes = discover()
            return routes[peer]
        end,
        send = function(route, packet)
            if
                C_ChatInfo.InChatMessagingLockdown()
                or C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()
            then
                return "lockdown"
            end
            local result = C_BattleNet.SendGameData(route, prefix, packet)
            if result == 0 then
                return "sent"
            end
            if result == 3 or result == 8 then
                return "throttled"
            end
            if result == 11 then
                return "lockdown"
            end
            if result == 12 then
                return "unreachable"
            end
            return "send-error"
        end,
    })
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("BN_CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, receivedPrefix, packet, _, senderID)
        if
            not canaccessvalue(receivedPrefix)
            or not canaccessvalue(packet)
            or not canaccessvalue(senderID)
        then
            return
        end
        if receivedPrefix ~= prefix then
            return
        end
        -- BN_CHAT_MSG_ADDON senderID semantics are an open client gate. Never
        -- fall back to payload identity, account names or character strings.
        local _, _, senders = discover()
        local peer = senders[senderID]
        if peer then
            ns.TransportReceive(t, peer, packet)
        end
    end)
    local nextSync = 0
    frame:SetScript("OnUpdate", function()
        ns.TransportTick(t)
        local now = GetServerTime()
        if now >= nextSync then
            nextSync = now + 20
            for peer in pairs(family.profile.children) do
                local pending = false
                for _, item in ipairs(t.work) do
                    if
                        item.peer == peer
                        and item.kind == "sync"
                        and (item.state == "pending" or item.state == "delivered")
                    then
                        pending = true
                    end
                end
                if not pending then
                    ns.TransportRequest(t, peer, "sync", {}, 30)
                end
            end
        end
    end)
    t.stop = function()
        frame:UnregisterEvent("BN_CHAT_MSG_ADDON")
        frame:SetScript("OnEvent", nil)
        frame:SetScript("OnUpdate", nil)
    end
    return t, "candidate-route-active"
end
