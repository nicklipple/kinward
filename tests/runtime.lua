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
                return time
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
            C_ChatInfo = {
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
    local function advance()
        for _ = 1, 160 do
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

print(string.format("%d automatic runtime boundary tests passed (mocked Lua %s)", passed, _VERSION))
