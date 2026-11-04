-- Two independent mocked client boundaries exercise the real candidate transport
-- and chat adapters. This does not establish actual game-client behavior.
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end
local function network(savedSession)
    local time, queue, clients = 1000, {}, {}
    local function client(id, role, character, realm)
        local ns, frames, menus, filters = {}, {}, {}, {}
        local originalSends, bnetReady = 0, true
        local env = {
            type = type,
            pairs = pairs,
            ipairs = ipairs,
            next = next,
            math = math,
            string = string,
            table = table,
            tonumber = tonumber,
            tostring = tostring,
            select = select,
            date = os.date,
            canaccessvalue = function(v)
                return type(v) ~= "table" or not v.secret
            end,
            WOW_PROJECT_ID = 1,
            BNGetNumFriends = function()
                return 1
            end,
            BNGetInfo = function()
                return 1, bnetReady and id or nil
            end,
            GetServerTime = function()
                return math.floor(time)
            end,
            GetTimePreciseSec = function()
                return time + 0.12345
            end,
            UnitGUID = function()
                return "Player-1-" .. character
            end,
            UnitFullName = function()
                return character, realm
            end,
            UnitIsPlayer = function()
                return true
            end,
            UnitIsUnit = function(a, b)
                return a == b
            end,
            GetNormalizedRealmName = function()
                return realm
            end,
            print = function() end,
            Minimap = false,
            SlashCmdList = {},
            C_AddOns = {
                GetAddOnMetadata = function()
                    return "0.1.0"
                end,
            },
            Menu = {
                ModifyMenu = function(tag, callback)
                    menus[tag] = callback
                end,
            },
            C_Club = {
                SendMessage = function()
                    originalSends = originalSends + 1
                end,
            },
            GetChannelName = function(channel)
                if channel == 1 then
                    return 1, "General", 0, false
                end
                if channel == 5 then
                    return 5, "FamilyRoom", 0, false
                end
                if channel == 6 then
                    return 6, "General", 0, false
                end
                return 0
            end,
            C_ChatInfo = {
                GetChannelInfoFromIdentifier = function(name)
                    return { name = name, zoneChannelID = name == "FamilyRoom" and 0 or 1 }
                end,
                RegisterAddonMessagePrefix = function()
                    return 0
                end,
                InChatMessagingLockdown = function()
                    return false
                end,
                AreOutgoingAddonChatMessagesRestricted = function()
                    return false
                end,
                SendChatMessage = function()
                    originalSends = originalSends + 1
                end,
            },
            ChatFrameUtil = {
                AddMessageEventFilter = function(event, callback)
                    filters[event] = callback
                end,
                RemoveMessageEventFilter = function(event)
                    filters[event] = nil
                end,
            },
        }
        local peer
        env.C_BattleNet = {
            SendWhisper = function()
                originalSends = originalSends + 1
                return true
            end,
            GetAccountInfoByID = function(bnetID)
                if bnetID == 777 then
                    return { isFriend = true, battleTag = "Friend#777" }
                end
                if bnetID == peer.handle + 1000 then
                    return { isFriend = true, battleTag = peer.id }
                end
                return { isFriend = false, battleTag = "Stranger#999" }
            end,
            GetFriendAccountInfo = function()
                return { isFriend = true, battleTag = peer.id }
            end,
            GetFriendNumGameAccounts = function()
                return 1
            end,
            GetFriendGameAccountInfo = function()
                return {
                    gameAccountID = peer.handle,
                    clientProgram = "WoW",
                    isOnline = true,
                    wowProjectID = 1,
                    characterName = peer.character,
                    realmName = peer.realm,
                }
            end,
            SendGameData = function(handle, prefix, packet)
                assert(handle == peer.handle)
                queue[#queue + 1] =
                    { receiver = peer, sender = clients[id], prefix = prefix, packet = packet }
                return 0
            end,
        }
        env.CreateFrame = function()
            local f = { scripts = {}, events = {} }
            function f:RegisterEvent(event)
                self.events[event] = true
            end
            function f:UnregisterEvent(event)
                self.events[event] = nil
            end
            function f:SetScript(event, callback)
                self.scripts[event] = callback
            end
            frames[#frames + 1] = f
            return f
        end
        setmetatable(env, {
            __index = function(_, key)
                error("Unexpected client API " .. key)
            end,
        })
        for line in io.lines("Kinward.toc") do
            if line:match("%.lua$") then
                if line == "Core.lua" then
                    local saved = ns.NormalizeSettings(nil)
                    saved.role = role
                    saved.sessionId = savedSession
                    env.KinwardDB = saved
                end
                setfenv(assert(loadfile(line)), env)("Kinward", ns)
            end
        end
        ns.ShowDashboard = function(d, section)
            assert(d.profile == ns.settings and (section == nil or section == "family"))
        end
        local function dispatch(event, a, b, c, d)
            local count = #frames
            for i = 1, count do
                local f = frames[i]
                if f.events[event] then
                    f.scripts.OnEvent(f, event, a, b, c, d)
                end
            end
        end
        dispatch("ADDON_LOADED", "Kinward")
        local c = {
            ns = ns,
            env = env,
            frames = frames,
            filters = filters,
            menus = menus,
            id = id,
            character = character,
            realm = realm,
            handle = #frames + (role == "child" and 10 or 20),
            sends = function()
                return originalSends
            end,
            connect = function(p)
                peer = p
            end,
            dispatch = dispatch,
            enter = function(initial, reload)
                dispatch("PLAYER_ENTERING_WORLD", initial ~= false, reload == true)
            end,
            setBnet = function(ready)
                bnetReady = ready
            end,
        }
        clients[id] = c
        return c
    end
    local child = client("Child#123", "child", "Kid", "Child Realm")
    local parent = client("Parent#456", "guardian", "Parent", "Other Realm")
    child.connect(parent)
    parent.connect(child)
    local function advance(seconds)
        for _ = 1, math.floor((seconds or 16) * 10) do
            time = time + 0.1
            for _, c in pairs(clients) do
                for _, f in ipairs(c.frames) do
                    if f.scripts.OnUpdate then
                        f.scripts.OnUpdate(f, 0.1)
                    end
                end
            end
            local pending = queue
            queue = {}
            for _, packet in ipairs(pending) do
                for _, f in ipairs(packet.receiver.frames) do
                    if f.events.BN_CHAT_MSG_ADDON then
                        f.scripts.OnEvent(
                            f,
                            "BN_CHAT_MSG_ADDON",
                            packet.prefix,
                            packet.packet,
                            "",
                            packet.sender.handle
                        )
                    end
                end
            end
        end
    end
    return child, parent, advance
end

test("player menus retain realm/account identity, capture selection, and register once", function()
    local c = network()
    local ns = c.ns
    ns.InstallPlayerMenu()
    ns.InstallPlayerMenu()
    local entry, callback
    local root = {
        CreateButton = function(_, caption, fn)
            entry, callback = caption, fn
        end,
    }
    local context = { name = "Parent", surname = "Other Realm" }
    c.menus.MENU_UNIT_PLAYER(nil, root, context)
    assert(entry == "Kinward: Pair with player")
    context.name = "Different" -- Captured target cannot change with recycled menu data.
    callback()
    assert(ns.dashboard.pairingTarget == "Parent-Other Realm")
    assert(
        ns.PlayerMenuTarget({ accountInfo = { battleTag = "Parent#456" }, name = "Wrong" })
            == "Parent#456"
    )
    assert(not ns.PlayerMenuTarget({ name = { secret = true } }))
    assert(not ns.PlayerMenuTarget({ name = "|Hplayer:spoof" }))
    assert(not ns.PlayerMenuTarget({ unit = "player" }))
    assert(not ns.transport and not ns.chat)
end)

test(
    "normal login automatically pairs independent accounts across realms and applies permissions",
    function()
        local child, parent, advance = network()
        local c, p = child.ns, parent.ns
        assert(not c.transport and not c.chat)
        child.enter()
        parent.enter()
        assert(c.RuntimeStatus():find("Connected", 1, true))
        assert(p.RuntimeStatus():find("Connected", 1, true))
        local t = c.transport
        child.enter(false, false)
        assert(c.transport == t)
        c.OpenDashboard("family", "Parent-Other Realm")
        assert(c.dashboard.pairingTarget == "Parent-Other Realm")
        assert(c.ResolveGuardianPeer(t, "Parent-Other Realm") == "Parent#456")
        assert(c.RequestGuardianship(t, c.dashboard.pairingTarget))
        advance()
        local request = p.transport.family.guardianInbox["Child#123"]
        assert(request and request.state == "pending")
        assert(p.AnswerGuardianship(p.transport, "Child#123", request.token, true))
        advance()
        assert(c.settings.supervision == "paired" and c.settings.guardians["Parent#456"])
        assert(p.settings.children["Child#123"])
        child.env.C_ChatInfo.SendChatMessage("blocked", "PARTY")
        assert(child.sends() == 0)
        p.DashboardAction(
            p.dashboard,
            "policy",
            { "Child#123", "party", "send", "indefinite", "", "", "" }
        )
        advance()
        child.env.C_ChatInfo.SendChatMessage("allowed", "PARTY")
        assert(child.sends() == 1)
        assert(c.RuntimeStatus():find("received", 1, true))
        assert(c.settings.supervision == "paired")
        -- No start command was used anywhere: actual Core login events connect
        -- and attach the real adapters to a dashboard opened through the menu.
        assert(c.transport == c.dashboard.transport and c.chat.chat == c.dashboard.chat)
    end
)
test("Battle.net startup retries automatically while chat monitoring stays installed", function()
    local child, parent, advance = network()
    child.setBnet(false)
    child.enter()
    parent.enter()
    assert(child.ns.chat and not child.ns.transport)
    assert(child.ns.RuntimeStatus():find("Battle.net", 1, true))
    child.ns.OpenDashboard("family")
    child.setBnet(true)
    advance()
    assert(child.ns.transport and child.ns.dashboard.transport == child.ns.transport)
    local count = #child.frames
    child.dispatch("BN_CONNECTED")
    assert(#child.frames == count)
end)

test("reload preserves session grants and a fresh login expires them automatically", function()
    local child, parent = network("saved-session")
    child.enter(false, true)
    parent.enter()
    assert(child.ns.settings.sessionId == "saved-session")
    assert(child.ns.chat and child.ns.transport)
    local fresh = network("saved-session")
    fresh.enter(true, false)
    assert(fresh.ns.settings.sessionId ~= "saved-session")
    local token = fresh.ns.settings.sessionId
    fresh.enter(false, false)
    assert(fresh.ns.settings.sessionId == token)
end)

test("unknown engine senders are diagnosed without creating pairing requests", function()
    local child, parent = network()
    child.enter()
    parent.enter()
    parent.dispatch("BN_CHAT_MSG_ADDON", "Kinward4", "untrusted", "", 999)
    assert(parent.ns.transport.traffic.received == 1)
    assert(parent.ns.transport.traffic.unmapped == 1)
    assert(not next(parent.ns.transport.family.guardianInbox or {}))
    assert(parent.ns.RuntimeStatus():find("unknown senders 1", 1, true))
end)

test("failed game-data sends remain visible rather than pretending request delivery", function()
    local child, parent, advance = network()
    child.enter()
    parent.enter()
    child.env.C_BattleNet.SendGameData = function()
        return 12
    end
    assert(child.ns.RequestGuardianship(child.ns.transport, "Parent-Other Realm"))
    advance()
    assert(child.ns.transport.traffic.sent == 0)
    assert(child.ns.RuntimeStatus():find("last send 12", 1, true))
    assert(not next(parent.ns.transport.family.guardianInbox or {}))
end)

test("visible chat restrictions do not prevent Battle.net pairing delivery", function()
    local child, parent, advance = network()
    for _, c in ipairs({ child, parent }) do
        c.env.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function()
            return true
        end
        c.env.C_ChatInfo.InChatMessagingLockdown = function()
            return true
        end
        c.enter()
    end
    assert(child.ns.RequestGuardianship(child.ns.transport, "Parent-Other Realm"))
    advance()
    local request = parent.ns.transport.family.guardianInbox["Child#123"]
    assert(request and request.state == "pending")
    assert(child.ns.transport.traffic.sent > 0 and child.ns.transport.traffic.lastSend == "0")
    assert(parent.ns.AnswerGuardianship(parent.ns.transport, "Child#123", request.token, true))
    advance()
    assert(child.ns.settings.supervision == "paired" and parent.ns.settings.children["Child#123"])
end)

test("an actual Battle.net lockdown result defers pairing without claiming delivery", function()
    local child, parent, advance = network()
    child.enter()
    parent.enter()
    child.env.C_BattleNet.SendGameData = function()
        return 11
    end
    assert(child.ns.RequestGuardianship(child.ns.transport, "Parent-Other Realm"))
    advance()
    assert(child.ns.transport.traffic.sent == 0)
    assert(child.ns.RuntimeStatus():find("last send 11", 1, true))
    assert(not next(parent.ns.transport.family.guardianInbox or {}))
    local pending
    for _, item in ipairs(child.ns.transport.work) do
        if item.kind == "guardian-request" then
            pending = item
        end
    end
    assert(pending and pending.state == "pending" and pending.result == "lockdown")
end)

local function pairedNetwork()
    local child, parent, advance = network()
    child.enter()
    parent.enter()
    child.ns.OpenDashboard("family", "Parent-Other Realm")
    assert(child.ns.RequestGuardianship(child.ns.transport, "Parent-Other Realm"))
    advance()
    local r = parent.ns.transport.family.guardianInbox["Child#123"]
    assert(r and parent.ns.AnswerGuardianship(parent.ns.transport, "Child#123", r.token, true))
    advance()
    assert(child.ns.settings.supervision == "paired")
    return child, parent, advance
end
local line = 100
local function incoming(c, event, body, zone, base, bn)
    line = line + 1
    return c.filters[event](
        {},
        event,
        body,
        "Stranger-SomeRealm",
        "",
        "",
        "",
        "",
        zone or 0,
        0,
        base or "",
        0,
        line,
        "",
        bn
    )
end

test("every standard player chat route blocks and captures by default", function()
    local child = pairedNetwork()
    for _, spec in ipairs({
        { "SAY", "CHAT_MSG_SAY", "say" },
        { "YELL", "CHAT_MSG_YELL", "yell" },
        { "GUILD", "CHAT_MSG_GUILD", "guild" },
        { "OFFICER", "CHAT_MSG_OFFICER", "officer" },
        { "RAID", "CHAT_MSG_RAID", "raid" },
        { "RAID_WARNING", "CHAT_MSG_RAID_WARNING", "raid" },
        { "INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT", "instance" },
        { "EMOTE", "CHAT_MSG_EMOTE", "emote" },
        { "PARTY", "CHAT_MSG_PARTY", "party" },
        { "COMMUNITIES_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL", "communities" },
    }) do
        child.env.C_ChatInfo.SendChatMessage("OUT-" .. spec[1], spec[1])
        assert(incoming(child, spec[2], "IN-" .. spec[1]))
        local records = child.ns.settings.history.records
        assert(records[#records].channel == spec[3] and records[#records].disposition == "blocked")
        assert(records[#records - 1].disposition == "blocked-attempt")
    end
    assert(child.sends() == 0)
end)

test(
    "custom channel defaults, named overrides and stable public keys use the real adapters",
    function()
        local child, parent, advance = pairedNetwork()
        child.env.C_ChatInfo.SendChatMessage("BLOCKED-CUSTOM", "CHANNEL", nil, 5)
        assert(child.sends() == 0)
        assert(incoming(child, "CHAT_MSG_CHANNEL", "BLOCKED-GENERAL", 1, "General - City"))
        assert(child.ns.PublicChannelKey("General", 0) == "channel:custom:general")
        for _, direction in ipairs({ "read", "send" }) do
            parent.ns.DashboardAction(
                parent.ns.dashboard,
                "policy",
                { "Child#123", "channel:custom", direction, "indefinite", "", "", "" }
            )
        end
        advance()
        child.env.C_ChatInfo.SendChatMessage("ALLOWED-CUSTOM", "CHANNEL", nil, 5)
        assert(
            child.sends() == 1
                and not incoming(child, "CHAT_MSG_CHANNEL", "ALLOWED", 0, "FamilyRoom")
        )
        parent.ns.DashboardAction(
            parent.ns.dashboard,
            "policy",
            { "Child#123", "channel:custom:familyroom", "read", "revoke", "", "", "" }
        )
        advance()
        assert(incoming(child, "CHAT_MSG_CHANNEL", "DENIED-EXCEPTION", 0, "FamilyRoom"))
        assert(not incoming(child, "CHAT_MSG_CHANNEL", "OTHER-ROOM", 0, "OtherRoom"))
        assert(child.ns.settings.policy.channels["channel:custom:familyroom"].read.mode == "deny")
        assert(child.ns.NormalizeSettings(child.ns.settings).supervision == "paired")
    end
)

test(
    "Battle.net whispers and community sends enforce and capture without confusing account IDs",
    function()
        local child, parent, advance = pairedNetwork()
        assert(child.env.C_BattleNet.SendWhisper(999, "BLOCKED-BNET") == false)
        assert(incoming(child, "CHAT_MSG_BN_WHISPER", "BLOCKED-BNET-IN", nil, nil, 999))
        assert(child.env.C_BattleNet.SendWhisper(parent.handle + 1000, "GUARDIAN-BNET"))
        assert(
            not incoming(
                child,
                "CHAT_MSG_BN_WHISPER",
                "GUARDIAN-BNET-IN",
                nil,
                nil,
                parent.handle + 1000
            )
        )
        parent.ns.DashboardAction(
            parent.ns.dashboard,
            "policy",
            { "Child#123", "whisper-account", "read", "indefinite", "", "", "Friend#777" }
        )
        advance()
        assert(child.env.C_BattleNet.SendWhisper(777, "ALLOWED-FRIEND"))
        assert(not incoming(child, "CHAT_MSG_BN_WHISPER", "ALLOWED-FRIEND-IN", nil, nil, 777))
        local sent = child.sends()
        child.env.C_Club.SendMessage("123", "456", "BLOCKED-COMMUNITY")
        assert(child.sends() == sent)
        assert(
            child.ns.settings.history.records[#child.ns.settings.history.records].channel
                == "communities"
        )
    end
)

test(
    "integer server clocks deliver captured say history while background control polls run",
    function()
        local child, parent, advance = pairedNetwork()
        assert(child.ns.transport.io.now() % 1 == 0)
        assert(child.ns.transport.io.monotonic() % 1 ~= 0)
        local polls = 0
        local request = parent.ns.TransportRequest
        parent.ns.TransportRequest = function(t, peer, kind, args, seconds)
            if kind == "pairing-pending" then
                polls = polls + 1
            end
            return request(t, peer, kind, args, seconds)
        end
        for i = 1, 18 do
            child.env.C_ChatInfo.SendChatMessage("SAY-HISTORY-" .. i .. string.rep("x", 200), "SAY")
        end
        assert(child.sends() == 0)
        assert(parent.ns.WatchHistory(parent.ns.transport, "Child#123"))
        advance(120)
        local h = parent.ns.settings.childProfiles["Child#123"].history
        assert(h and h.cursor == child.ns.settings.history.high)
        local found = 0
        for _, record in ipairs(h.records) do
            if record.channel == "say" and record.text:find("SAY-HISTORY-", 1, true) then
                assert(record.disposition == "blocked-attempt")
                found = found + 1
            end
        end
        assert(found == 18 and polls <= 6)
    end
)

test("channel history retains names for arbitrary zone channel IDs", function()
    local child, parent, advance = pairedNetwork()
    assert(
        incoming(
            child,
            "CHAT_MSG_CHANNEL",
            "arbitrary channel message",
            987,
            "Visitors - Test Area"
        )
    )
    assert(parent.ns.WatchHistory(parent.ns.transport, "Child#123"))
    advance(30)
    local rows = parent.ns.HistoryView(
        parent.ns.settings,
        "Child#123",
        { channel = "channel:zone:987" },
        2000
    )
    assert(#rows == 1 and rows[1].channel == "channel:zone:987|Visitors - Test Area")
    assert(parent.ns.HistoryChannelLabel(rows[1].channel) == "Visitors - Test Area")
    assert(parent.ns.HistoryChannelBase(rows[1].channel) == "channel:zone:987")
end)

test(
    "joined channel inventory includes silent arbitrary channels and tracks join and leave",
    function()
        local child, parent, advance = pairedNetwork()
        local names = { [1] = "Newcomer Chat", [7] = "Silent Room", [20] = "Visitors" }
        child.env.GetChannelName = function(number)
            return names[number] and number or 0, names[number]
        end
        child.env.C_ChatInfo.GetChannelInfoFromIdentifier = function(name)
            return {
                name = name,
                zoneChannelID = name == "Newcomer Chat" and 32 or name == "Visitors" and 987 or 0,
            }
        end
        advance(45)
        local t = parent.ns.transport
        local joined = assert(t.joinedChannels["Child#123"])
        assert(#joined == 3)
        local indexed = {}
        for _, row in ipairs(joined) do
            indexed[row[1]] = row[2]
        end
        assert(indexed["channel:zone:32"] == "Newcomer Chat")
        assert(indexed["channel:zone:987"] == "Visitors")
        assert(indexed["channel:custom:silent room"] == "Silent Room")
        for _, record in ipairs(child.ns.settings.history.records) do
            assert(not record.channel:find("^channel:")) -- discovery requires no channel traffic
        end
        for _, direction in ipairs({ "read", "send" }) do
            parent.ns.DashboardAction(
                parent.ns.dashboard,
                "policy",
                { "Child#123", "channel:zone:32", direction, "indefinite", "", "", "" }
            )
        end
        advance(20)
        assert(not incoming(child, "CHAT_MSG_CHANNEL", "allowed newcomer", 32, "Newcomer Chat"))
        assert(incoming(child, "CHAT_MSG_CHANNEL", "blocked visitors", 987, "Visitors"))
        child.env.C_ChatInfo.SendChatMessage("allowed outgoing", "CHANNEL", nil, 1)
        child.env.C_ChatInfo.SendChatMessage("blocked outgoing", "CHANNEL", nil, 20)
        assert(child.sends() == 1)
        names[7], names[20], names[9] = nil, nil, "Joined Later"
        advance(45)
        joined = assert(t.joinedChannels["Child#123"])
        assert(#joined == 2)
        indexed = {}
        for _, row in ipairs(joined) do
            indexed[row[1]] = row[2]
        end
        assert(indexed["channel:custom:joined later"] == "Joined Later")
        assert(not indexed["channel:zone:987"] and not indexed["channel:custom:silent room"])
        t.family.profile.children["Child#123"] = nil
        parent.ns.PollChannels(t)
        assert(not t.joinedChannels["Child#123"])
    end
)

print(string.format("%d automatic runtime boundary tests passed (mocked Lua %s)", passed, _VERSION))
