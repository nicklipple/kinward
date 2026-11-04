local _, ns = ...
---@cast ns KinwardNamespace

-- Source-backed candidate route, deliberately gated until P1-ID/P1-ROUTE pass.
-- The caller must supply a verified local account identity and a fresh instance
-- identifier; this module never invents authority from a payload or character name.
---@param family KinwardFamily
---@param instance string
---@param verified boolean Recorded client routing/identity acceptance, not a user preference.
---@param testing? boolean Explicit consenting-account test; does not verify the route.
---@return KinwardTransport?, string
function ns.NewWoWTransport(family, instance, verified, testing)
    if not verified and not testing then
        return nil, "live-routing-unverified"
    end
    local prefix = "Kinward4"
    local registered = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if registered ~= 0 and registered ~= 1 then
        return nil, "prefix-unavailable"
    end
    ---@return table<string, boolean>, table<string, number>, table<number, string>, table<string, string|false>
    local function discover()
        local friends, routes, senders, ambiguous = {}, {}, {}, {}
        ---@type table<string, string|false>
        local names = {}
        local function alias(name, peer)
            local key = ns.CharacterKey(name) or name:lower()
            if names[key] ~= nil and names[key] ~= peer then
                names[key] = false
            else
                names[key] = peer
            end
        end
        local count = BNGetNumFriends()
        if
            not canaccessvalue(count)
            or type(count) ~= "number"
            or count < 0
            or count > 200
            or count % 1 ~= 0
        then
            return {}, {}, {}, {}
        end
        local incomplete = false
        for friendIndex = 1, math.min(count, 200) do
            local account = C_BattleNet.GetFriendAccountInfo(friendIndex)
            if not account or not canaccessvalue(account.isFriend) then
                return {}, {}, {}, {}
            end
            if
                account.isFriend
                and (
                    not canaccessvalue(account.battleTag)
                    or not ns.ValidIdentifier(account.battleTag)
                )
            then
                return {}, {}, {}, {}
            end
            if
                account
                and canaccessvalue(account.battleTag)
                and canaccessvalue(account.isFriend)
                and account.isFriend
                and ns.ValidIdentifier(account.battleTag)
            then
                local peer = account.battleTag
                friends[peer] = true
                alias(peer, peer)
                local games = C_BattleNet.GetFriendNumGameAccounts(friendIndex)
                if
                    not canaccessvalue(games)
                    or type(games) ~= "number"
                    or games < 0
                    or games > 32
                    or games % 1 ~= 0
                then
                    return {}, {}, {}, {}
                end
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
                        if
                            canaccessvalue(game.characterName)
                            and canaccessvalue(game.realmName)
                            and type(game.characterName) == "string"
                            and type(game.realmName) == "string"
                        then
                            local key = ns.CharacterKey(game.characterName, game.realmName)
                            if key then
                                alias(key, peer)
                                alias(game.characterName, peer)
                            else
                                incomplete = true
                            end
                        else
                            incomplete = true
                        end
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
            for name, owner in pairs(names) do
                if owner == peer then
                    names[name] = false
                end
            end
            for handle, owner in pairs(senders) do
                if owner == peer then
                    senders[handle] = nil
                end
            end
        end
        if incomplete then
            -- An inaccessible character can make name aliases ambiguous, but
            -- a complete engine-provided BattleTag still identifies its friend.
            names = {}
            for peer in pairs(friends) do
                if not ambiguous[peer] then
                    alias(peer, peer)
                end
            end
        end
        return friends, routes, senders, names
    end
    local t = ns.NewTransport(family, {
        instance = instance,
        now = GetServerTime,
        friends = function()
            local friends = discover()
            return friends
        end,
        findPeer = function(name)
            local _, _, _, names = discover()
            local peer = names[ns.CharacterKey(name) or name:lower()]
            return type(peer) == "string" and peer or nil
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
    t.testing = testing == true
    t.testReceived = 0
    t.pairingPolling = true
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
            t.testReceived = (t.testReceived or 0) + 1
            local previous = family.guardianInbox and family.guardianInbox[peer]
            local previousToken = previous and previous.token
            ns.TransportReceive(t, peer, packet)
            local request = family.guardianInbox and family.guardianInbox[peer]
            if
                request
                and request.state == "pending"
                and request.token ~= previousToken
                and family.profile.role == "guardian"
            then
                print(
                    "Kinward: "
                        .. peer:gsub("|", "||")
                        .. " requested guardianship. Accept or decline in Family."
                )
                -- Only the verified live profile can open the live dashboard.
                if ns.settings == family.profile then
                    ns.dashboard = ns.dashboard or ns.NewDashboard(family.profile, t, GetServerTime)
                    ns.dashboard.transport = t
                    ns.ShowDashboard(ns.dashboard, "family")
                end
            end
        end
    end)
    local nextSync = 0
    frame:SetScript("OnUpdate", function()
        ns.TickGuardianship(t)
        ns.PollHistory(t)
        ns.PollRequests(t)
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
