local _, ns = ...
---@cast ns KinwardNamespace

local events = {
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_PARTY = "party",
    CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "yell",
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_OFFICER = "officer",
    CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_INSTANCE_CHAT = "instance",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
    CHAT_MSG_EMOTE = "emote",
    CHAT_MSG_TEXT_EMOTE = "emote",
    CHAT_MSG_CHANNEL = "channel",
    CHAT_MSG_COMMUNITIES_CHANNEL = "communities",
    CHAT_MSG_BN_WHISPER = "bnet",
}
local sends = {
    WHISPER = "whisper",
    PARTY = "party",
    SAY = "say",
    YELL = "yell",
    GUILD = "guild",
    OFFICER = "officer",
    RAID = "raid",
    RAID_WARNING = "raid",
    INSTANCE_CHAT = "instance",
    EMOTE = "emote",
    COMMUNITIES_CHANNEL = "communities",
}

---Fresh candidate mapping from engine friendship records, never chat payloads.
---Use only after P1-ID establishes the account/character mapping in this client.
---@param character string Normalized character-realm key.
---@return string?
function ns.ResolveWoWChatAccount(character)
    local count = BNGetNumFriends()
    if
        not canaccessvalue(count)
        or type(count) ~= "number"
        or count % 1 ~= 0
        or count < 0
        or count > 200
    then
        return nil
    end
    local resolved
    for friendIndex = 1, count do
        local account = C_BattleNet.GetFriendAccountInfo(friendIndex)
        if not account or not canaccessvalue(account.isFriend) then
            return nil
        end
        if account.isFriend then
            if
                not canaccessvalue(account.battleTag) or not ns.ValidIdentifier(account.battleTag)
            then
                return nil
            end
            local games = C_BattleNet.GetFriendNumGameAccounts(friendIndex)
            if
                not canaccessvalue(games)
                or type(games) ~= "number"
                or games % 1 ~= 0
                or games < 0
                or games > 32
            then
                return nil
            end
            for gameIndex = 1, games do
                local game = C_BattleNet.GetFriendGameAccountInfo(friendIndex, gameIndex)
                if
                    not game
                    or not canaccessvalue(game.clientProgram)
                    or not canaccessvalue(game.isOnline)
                then
                    return nil
                end
                if game.clientProgram == "WoW" and game.isOnline then
                    if not canaccessvalue(game.wowProjectID) then
                        return nil
                    end
                    if game.wowProjectID == WOW_PROJECT_ID then
                        if
                            not canaccessvalue(game.characterName)
                            or not canaccessvalue(game.realmName)
                        then
                            return nil
                        end
                        if type(game.realmName) ~= "string" or game.realmName == "" then
                            return nil
                        end
                        local key = ns.CharacterKey(game.characterName, game.realmName)
                        if not key then
                            return nil
                        end
                        if key == character then
                            if resolved and resolved ~= account.battleTag then
                                return nil -- Two different friends claim the same character.
                            end
                            resolved = account.battleTag
                        end
                    end
                end
            end
        end
    end
    return resolved
end

---Install after SavedVariables and character identity initialize.
---@param profile KinwardSettings
---@param io KinwardChatIO
---@return KinwardWoWChat?, string
function ns.NewWoWChat(profile, io)
    if ns.chat then
        return nil, "chat-already-active"
    end
    local sessionReady, active = false, true
    if io.sessionId then
        sessionReady = ns.BeginSession(profile, io.sessionId)
    end
    ---@type table<string, string>
    local accounts = {}
    local bnetAccounts = {}
    local chat = ns.NewChat(profile, function()
        return {
            now = GetServerTime(),
            sessionId = sessionReady and profile.sessionId or "",
            accounts = accounts,
            bnetAccounts = bnetAccounts,
        }
    end)
    chat.monitoring = true
    ns.HistoryHeartbeat(chat, false)
    local function accessibleBody(text)
        if canaccessvalue(text) and type(text) == "string" then
            return text
        end
        return nil
    end
    ---@param name unknown
    ---@return KinwardIdentity?
    local function identity(name)
        accounts = {} -- Never reuse a mapping after an alt/friendship change.
        if not canaccessvalue(name) or type(name) ~= "string" then
            return nil
        end
        local key = ns.CharacterKey(name)
        if not key and not name:find("-", 1, true) then
            local realm = GetNormalizedRealmName()
            if canaccessvalue(realm) then
                key = ns.CharacterKey(name, realm)
            end
        end
        if not key then
            return nil
        end
        -- Resolver must return only current, unambiguous, verified BN friendships.
        -- Neither a payload account claim, GUID guess nor party membership suffices.
        local account = io.account(key)
        if not canaccessvalue(account) or not ns.ValidIdentifier(account) then
            account = nil
        end
        accounts[key] = account
        return { character = key, account = account }
    end
    local function bnetIdentity(id)
        bnetAccounts = {}
        if not canaccessvalue(id) or type(id) ~= "number" or id <= 0 then
            return nil
        end
        local account = C_BattleNet.GetAccountInfoByID(id)
        if
            not account
            or not canaccessvalue(account.isFriend)
            or not account.isFriend
            or not canaccessvalue(account.battleTag)
            or not ns.ValidIdentifier(account.battleTag)
        then
            return nil
        end
        bnetAccounts[account.battleTag] = true
        return { account = account.battleTag }
    end
    local function channelTarget(target)
        if
            not canaccessvalue(target) or (type(target) ~= "number" and type(target) ~= "string")
        then
            return "channel:unknown"
        end
        local _, name, _, community = GetChannelName(target)
        if not canaccessvalue(name) or type(name) ~= "string" then
            return "channel:unknown"
        end
        if canaccessvalue(community) and community then
            return "communities"
        end
        local info = C_ChatInfo.GetChannelInfoFromIdentifier(name)
        if not info or not canaccessvalue(info.zoneChannelID) then
            return "channel:unknown"
        end
        return ns.PublicChannelKey(name, info.zoneChannelID)
    end
    local function filter(
        _,
        event,
        text,
        sender,
        _,
        _,
        _,
        _,
        zone,
        _,
        baseName,
        _,
        line,
        _,
        bnSender
    )
        if not active then
            return false
        end
        if not canaccessvalue(line) then
            line = nil
        end
        local previousPrompt = chat.prompt
        local channel = events[event]
        if channel == "channel" then
            channel = canaccessvalue(zone)
                    and canaccessvalue(baseName)
                    and ns.PublicChannelKey(baseName, zone)
                or "channel:unknown"
        end
        local senderIdentity = channel == "bnet" and bnetIdentity(bnSender) or identity(sender)
        local allowed = ns.ChatDecision(chat, channel, "read", senderIdentity, line)
        local selfKey = io.selfCharacter and io.selfCharacter()
        if not canaccessvalue(selfKey) or type(selfKey) ~= "string" then
            selfKey = nil
        else
            selfKey = ns.CharacterKey(selfKey)
        end
        if channel ~= "whisper" and channel ~= "bnet" and (not selfKey or not senderIdentity) then
            ns.CaptureRead(
                chat,
                channel,
                nil,
                nil,
                allowed,
                line,
                channel == "party"
                        and "Party capture unavailable without verified local/sender identity."
                    or "Chat capture unavailable without local/sender identity."
            )
        elseif
            channel ~= "whisper"
            and channel ~= "bnet"
            and senderIdentity
            and senderIdentity.character == selfKey
        then
            ns.CaptureOutput(chat, channel, nil, accessibleBody(text), line)
        else
            ns.CaptureRead(chat, channel, senderIdentity, accessibleBody(text), allowed, line)
        end
        if chat.prompt and chat.prompt ~= previousPrompt then
            if io.prompt then
                io.prompt(chat.prompt.character)
            else
                print(
                    "Kinward: blocked whisper from "
                        .. chat.prompt.character
                        .. ". Open /kinward ui to request access."
                )
            end
        end
        return not allowed
    end
    local original = C_ChatInfo.SendChatMessage
    local nextNotice = 0
    local wrapped = function(text, chatType, language, target, ...)
        if not active or profile.supervision == "unpaired" then
            return original(text, chatType, language, target, ...)
        end
        local accessible = canaccessvalue(chatType)
        local channel = accessible and sends[chatType] or "other"
        if accessible and chatType == "CHANNEL" then
            channel = channelTarget(target)
        end
        local recipient = channel == "whisper" and identity(target) or nil
        local allowed = ns.ChatDecision(chat, channel or "unknown", "send", recipient)
        ns.CaptureSend(chat, channel or "unknown", recipient, accessibleBody(text), allowed)
        if not allowed then
            local now = GetServerTime()
            if now >= nextNotice then
                nextNotice = now + 2
                print("Kinward: this send was blocked by your current chat permissions.")
            end
            return
        end
        -- This is an attempt, not confirmation of output or remote receipt.
        return original(text, chatType, language, target, ...)
    end
    local originalBnet, originalClub = C_BattleNet.SendWhisper, C_Club and C_Club.SendMessage
    local function extraSend(channel, body, recipient)
        local allowed = ns.ChatDecision(chat, channel, "send", recipient)
        ns.CaptureSend(chat, channel, recipient, accessibleBody(body), allowed)
        if not allowed then
            print("Kinward: this send was blocked by your current chat permissions.")
        end
        return allowed
    end
    local bnetWrapped = function(id, body, ...)
        if not active or profile.supervision == "unpaired" then
            return originalBnet(id, body, ...)
        end
        if not extraSend("bnet", body, bnetIdentity(id)) then
            return false
        end
        return originalBnet(id, body, ...)
    end
    local clubWrapped = function(club, stream, body, ...)
        if not active or profile.supervision == "unpaired" then
            return originalClub(club, stream, body, ...)
        end
        if extraSend("communities", body, nil) then
            return originalClub(club, stream, body, ...)
        end
    end
    if originalBnet then
        C_BattleNet.SendWhisper = bnetWrapped
    end
    if originalClub then
        C_Club.SendMessage = clubWrapped
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    frame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
    frame:RegisterEvent("PLAYER_LOGOUT")
    local outputs, outputOrder = {}, {}
    frame:SetScript("OnEvent", function(_, event, initial, reload, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            if
                not canaccessvalue(initial)
                or not canaccessvalue(reload)
                or type(initial) ~= "boolean"
                or type(reload) ~= "boolean"
            then
                sessionReady = false
                return
            end
            if sessionReady and not initial and not reload then
                return -- Zone transitions do not create a new login.
            end
            local token
            if reload and not initial then
                token = profile.sessionId or ""
            else
                token = io.freshSession()
            end
            if (not reload or initial) and token == profile.sessionId then
                token = "" -- A broken generator cannot reactivate a previous login grant.
            end
            sessionReady = ns.BeginSession(profile, token)
            if not sessionReady then
                profile.sessionId = nil
            end
            chat.seen, chat.order = {}, {}
        elseif event == "PLAYER_LOGOUT" then
            ns.FlushHistorySends(chat, true)
            ns.HistoryHeartbeat(chat, chat.restrictedSince ~= nil)
            ns.HistoryGap(chat, "Monitoring paused for logout or reload.")
        elseif event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
            -- lineID is payload 11; initial/reload occupy payload 1/2 here.
            local line = select(9, ...)
            if
                canaccessvalue(line)
                and type(line) == "number"
                and line > 0
                and line < math.huge
            then
                if not outputs[line] then
                    if #outputOrder == 256 then
                        outputs[table.remove(outputOrder, 1)] = nil
                    end
                    outputs[line] = true
                    outputOrder[#outputOrder + 1] = line
                    chat.observedOutputs = chat.observedOutputs + 1
                    ns.CaptureOutput(
                        chat,
                        event == "CHAT_MSG_BN_WHISPER_INFORM" and "bnet" or "whisper",
                        event == "CHAT_MSG_BN_WHISPER_INFORM" and bnetIdentity(select(11, ...))
                            or identity(reload),
                        accessibleBody(initial),
                        line
                    )
                end
            end
        end
    end)
    local nextHeartbeat = 0
    frame:SetScript("OnUpdate", function()
        local now = GetServerTime()
        if now >= nextHeartbeat then
            nextHeartbeat = now + 1
            local restricted = C_ChatInfo.InChatMessagingLockdown()
            ns.HistoryHeartbeat(chat, not canaccessvalue(restricted) or restricted)
        end
    end)
    for event in pairs(events) do
        ChatFrameUtil.AddMessageEventFilter(event, filter)
    end
    C_ChatInfo.SendChatMessage = wrapped
    local adapter = {
        chat = chat,
        stop = function()
            if not active then
                return "already-stopped"
            end
            ns.FlushHistorySends(chat, true)
            ns.HistoryGap(chat, "Monitoring adapter stopped.")
            chat.monitoring = false
            active = false
            ns.chat = nil
            for event in pairs(events) do
                ChatFrameUtil.RemoveMessageEventFilter(event, filter)
            end
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            frame:UnregisterEvent("CHAT_MSG_WHISPER_INFORM")
            frame:UnregisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
            frame:UnregisterEvent("PLAYER_LOGOUT")
            frame:SetScript("OnEvent", nil)
            frame:SetScript("OnUpdate", nil)
            local clean = true
            if originalBnet then
                if C_BattleNet.SendWhisper == bnetWrapped then
                    C_BattleNet.SendWhisper = originalBnet
                else
                    clean = false
                end
            end
            if originalClub then
                if C_Club.SendMessage == clubWrapped then
                    C_Club.SendMessage = originalClub
                else
                    clean = false
                end
            end
            if C_ChatInfo.SendChatMessage == wrapped then
                C_ChatInfo.SendChatMessage = original
            else
                clean = false
            end
            return clean and "stopped-reload-to-clear-taint" or "chained-wrapper-reload-required"
        end,
    }
    ns.chat = adapter
    return adapter, "monitoring-active"
end
