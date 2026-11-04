-- Development only. Staged by scripts/phase1_probe.py; never ship this file.
local marker, prefix = "KINWARD-P1", "KinwardP1"
local active = false
local originalSend, wrappedSend
local incoming, outgoing, received = 0, 0, 0
local events =
    { "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_BN_WHISPER" }
local frame = CreateFrame("Frame")
local initialLogin, reloading

local function report(label, value)
    if canaccessvalue(value) then
        print("Kinward probe: " .. label .. "=" .. tostring(value))
    else
        print("Kinward probe: " .. label .. "=<inaccessible>")
    end
end

local function matches(text)
    return canaccessvalue(text) and type(text) == "string" and text:sub(1, #marker) == marker
end

local function filter(_, _, text)
    if matches(text) then
        incoming = incoming + 1
        return true
    end
    return false
end

local function stop()
    active = false
    for _, event in ipairs(events) do
        ChatFrameUtil.RemoveMessageEventFilter(event, filter)
    end
    frame:UnregisterAllEvents()
    if wrappedSend and C_ChatInfo.SendChatMessage == wrappedSend then
        C_ChatInfo.SendChatMessage = originalSend
    elseif wrappedSend then
        print(
            "Kinward probe: send function changed by another addon; reload required to remove chained wrapper"
        )
    end
    originalSend, wrappedSend = nil, nil
    print("Kinward probe: stopped; reload to clear taint and registered prefix")
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, a, b, _, sender)
    if event == "PLAYER_ENTERING_WORLD" then
        initialLogin, reloading = a, b
        return
    end
    if not active then
        return
    end
    if event == "CHAT_MSG_ADDON" or event == "BN_CHAT_MSG_ADDON" then
        if canaccessvalue(a) and a == prefix then
            received = received + 1
            report(event .. " sender", sender)
            report("marker payload", matches(b))
        end
    else
        report("event", event)
    end
end)

SlashCmdList.KINWARDPROBE = function(input)
    local command, target = input:match("^(%S+)%s*(.-)%s*$")
    if command == "stop" then
        stop()
    elseif command == "start" then
        if active then
            return
        end
        -- Fail before mutation if the pinned filter/security APIs are missing.
        assert(type(canaccessvalue) == "function", "Missing canaccessvalue")
        assert(
            type(ChatFrameUtil.AddMessageEventFilter) == "function",
            "Missing Forever filter API"
        )
        originalSend = C_ChatInfo.SendChatMessage
        assert(type(originalSend) == "function", "Missing send API")
        incoming, outgoing, received = 0, 0, 0
        active = true
        local send = originalSend
        wrappedSend = function(text, ...)
            if active and matches(text) then
                outgoing = outgoing + 1
                print("Kinward probe: prevented marker at C_ChatInfo.SendChatMessage boundary")
                return
            end
            return send(text, ...)
        end
        C_ChatInfo.SendChatMessage = wrappedSend
        for _, event in ipairs(events) do
            ChatFrameUtil.AddMessageEventFilter(event, filter)
        end
        for _, event in ipairs({
            "PLAYER_ENTERING_WORLD",
            "PLAYER_LOGOUT",
            "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED",
            "CHAT_MSG_ADDON",
            "BN_CHAT_MSG_ADDON",
            "BN_FRIEND_INFO_CHANGED",
            "BN_FRIEND_ACCOUNT_ONLINE",
            "BN_FRIEND_ACCOUNT_OFFLINE",
        }) do
            frame:RegisterEvent(event)
        end
        report("prefix registration result", C_ChatInfo.RegisterAddonMessagePrefix(prefix))
        print("Kinward probe: active; only KINWARD-P1-prefixed text is filtered/prevented")
    elseif command == "status" then
        report("active", active)
        report("filter callbacks discarded (not unique messages)", incoming)
        report("outgoing boundary prevented", outgoing)
        report("route receives (not acknowledgements)", received)
        report("initial login", initialLogin)
        report("UI reload", reloading)
        report("server time", GetServerTime())
        report("monotonic time", GetTimePreciseSec())
        report("messaging lockdown", C_ChatInfo.InChatMessagingLockdown())
        report("outgoing addon restriction", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted())
    elseif active and command == "char" and target ~= "" then
        report(
            "character send result",
            C_ChatInfo.SendAddonMessage(prefix, marker, "WHISPER", target)
        )
    elseif active and command == "bn" and tonumber(target) then
        report(
            "Battle.net send result",
            C_BattleNet.SendGameData(assert(tonumber(target)), prefix, marker)
        )
    else
        print(
            "Kinward probe: start | stop | status | char Name-Realm | bn gameAccountID; see docs/PHASE1_PROBES.md"
        )
    end
end
-- Intentional development-only slash global, typed in types/addon.lua.
SLASH_KINWARDPROBE1 = "/kinwardprobe"
