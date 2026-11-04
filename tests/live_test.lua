-- Two independent mocked client boundaries exercise the real candidate transport
-- and chat adapters. This does not establish actual game-client behavior.
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end
local function network()
    local time, queue, clients = 1000, {}, {}
    local function client(id, role, character, realm)
        local ns, frames, menus, filters = {}, {}, {}, {}
        local originalSends = 0
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
                return 1, id
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
            if line:match("%.lua$") and line ~= "Core.lua" then
                setfenv(assert(loadfile(line)), env)("Kinward", ns)
            end
        end
        ns.initialized = true
        ns.settings = ns.NormalizeSettings(nil)
        ns.settings.role = role
        ns.ShowDashboard = function(d, section)
            assert(d.profile == ns.settings and section == "family")
        end
        ns.OpenDashboard = function(section, target)
            assert(section == "family")
            ns.dashboard = ns.dashboard or ns.NewDashboard(ns.settings)
            ns.dashboard.pairingTarget = target
        end
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
    assert(not ns.liveTestTransport and not ns.chat)
end)

test(
    "explicit live test pairs independent accounts across realms through real candidate adapters",
    function()
        local child, parent, advance = network()
        local c, p = child.ns, parent.ns
        assert(c.LiveTestCommand("status"):find("inactive", 1, true))
        assert(c.LiveTestCommand("start"):find("LIVE TEST", 1, true))
        assert(p.LiveTestCommand("start"):find("LIVE TEST", 1, true))
        local t = c.liveTestTransport
        assert(c.LiveTestCommand("start"):find("LIVE TEST", 1, true) and c.liveTestTransport == t)
        assert(c.ResolveGuardianPeer(t, "Parent-Other Realm") == "Parent#456")
        assert(c.RequestGuardianship(t, "Parent-Other Realm"))
        advance()
        local request = p.liveTestTransport.family.guardianInbox["Child#123"]
        assert(request and request.state == "pending")
        assert(p.AnswerGuardianship(p.liveTestTransport, "Child#123", request.token, true))
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
        assert(c.LiveTestCommand("status"):find("received", 1, true))
        assert(c.LiveTestCommand("stop"):find("stopped", 1, true))
        assert(not c.chat and not c.liveTestTransport and c.dashboard.transport == nil)
        assert(c.settings.supervision == "paired")
        for _, f in ipairs(child.frames) do
            assert(not f.scripts.OnUpdate)
        end
        assert(not child.filters.CHAT_MSG_WHISPER)
    end
)
print(string.format("%d live-test boundary tests passed (mocked Lua %s)", passed, _VERSION))
