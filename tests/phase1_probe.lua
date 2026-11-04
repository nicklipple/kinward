-- Probe boundary/lifecycle tests; these do not establish client capabilities.
local source = "scripts/probes/Phase1Probe.lua"
local secret = {}
local registered, filters, sends, reports = {}, {}, 0, {}
local frame = {}
function frame:RegisterEvent(event)
    registered[event] = true
end
function frame:UnregisterAllEvents()
    registered = {}
end
function frame:SetScript(_, callback)
    self.callback = callback
end
local function send()
    sends = sends + 1
    return "sent"
end
local env = {
    assert = assert,
    type = type,
    ipairs = ipairs,
    tonumber = tonumber,
    tostring = tostring,
    canaccessvalue = function(value)
        return value ~= secret
    end,
    CreateFrame = function()
        return frame
    end,
    print = function(message)
        reports[#reports + 1] = message
    end,
    GetServerTime = function()
        return 100
    end,
    GetTimePreciseSec = function()
        return 2
    end,
    SlashCmdList = {},
    ChatFrameUtil = {
        AddMessageEventFilter = function(event, callback)
            assert(not filters[event])
            filters[event] = callback
        end,
        RemoveMessageEventFilter = function(event, callback)
            assert(not filters[event] or filters[event] == callback)
            filters[event] = nil
        end,
    },
    C_ChatInfo = {
        SendChatMessage = send,
        RegisterAddonMessagePrefix = function(prefix)
            assert(prefix == "GuardianP1")
            return 0
        end,
        SendAddonMessage = function(prefix, body, route, target)
            assert(
                prefix == "GuardianP1"
                    and body == "GUARDIAN-P1"
                    and route == "WHISPER"
                    and target == "Peer-Realm"
            )
            return 0
        end,
        InChatMessagingLockdown = function()
            return false
        end,
        AreOutgoingAddonChatMessagesRestricted = function()
            return false
        end,
    },
    C_BattleNet = {
        SendGameData = function(id, prefix, body)
            assert(id == 42 and prefix == "GuardianP1" and body == "GUARDIAN-P1")
            return 0
        end,
    },
}
setmetatable(env, {
    __index = function(_, key)
        error("Unexpected probe global: " .. key)
    end,
})
setfenv(assert(loadfile(source)), env)()
local command = env.SlashCmdList.GUARDIANPROBE
assert(env.SLASH_GUARDIANPROBE1 == "/guardianprobe")
assert(env.C_ChatInfo.SendChatMessage == send and next(filters) == nil)
frame.callback(frame, "PLAYER_ENTERING_WORLD", true, false)
command("status")
command("start")
command("start") -- idempotent
local wrapper = env.C_ChatInfo.SendChatMessage
assert(wrapper ~= send)
assert(wrapper("GUARDIAN-P1 blocked", "WHISPER", nil, "Peer") == nil and sends == 0)
assert(wrapper("ordinary text", "SAY") == "sent" and sends == 1)
assert(wrapper(secret) == "sent" and sends == 2) -- no comparison of inaccessible data
assert(filters.CHAT_MSG_WHISPER(nil, nil, "GUARDIAN-P1 hidden"))
assert(not filters.CHAT_MSG_WHISPER(nil, nil, "ordinary text"))
assert(not filters.CHAT_MSG_WHISPER(nil, nil, secret))
command("char Peer-Realm")
command("bn 42")
frame.callback(frame, "BN_CHAT_MSG_ADDON", "GuardianP1", secret, "WHISPER", secret)
frame.callback(frame, "CHAT_MSG_ADDON", secret, secret, secret, secret)
command("status")
command("stop")
assert(env.C_ChatInfo.SendChatMessage == send and next(filters) == nil and next(registered) == nil)
assert(wrapper("GUARDIAN-P1 after stop") == "sent") -- cached wrappers must pass through
command("start")
local ours = env.C_ChatInfo.SendChatMessage
local other = function(...)
    return ours(...)
end
env.C_ChatInfo.SendChatMessage = other
command("stop")
assert(env.C_ChatInfo.SendChatMessage == other) -- never overwrite another addon
assert(other("GUARDIAN-P1 after chained stop") == "sent")
print(
    "ok - phase 1 probe activation, filtering, send prevention boundary, secret handling, routes and cleanup (mocked)"
)
