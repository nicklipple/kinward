local ns, commands, output = {}, {}, {}
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
    SlashCmdList = commands,
    print = function(s)
        output[#output + 1] = s
    end,
}
setmetatable(env, {
    __index = function(_, key)
        error("Unexpected global read: " .. key)
    end,
    __newindex = function(t, key, value)
        assert(key == "SLASH_KINWARDSIM1", "Unexpected global write: " .. key)
        rawset(t, key, value)
    end,
})
for _, file in ipairs({
    "Policy.lua",
    "Profile.lua",
    "Session.lua",
    "Requests.lua",
    "History.lua",
    "HistoryCapture.lua",
    "Protocol.lua",
    "Family.lua",
    "Pairing.lua",
    "Transport.lua",
    "WoWTransport.lua",
    "Activity.lua",
    "PairingPanel.lua",
    "Dashboard.lua",
    "Chat.lua",
    "scripts/probes/Phase2Simulator.lua",
}) do
    setfenv(assert(loadfile(file)), env)("Kinward", ns)
end
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end
local function advance(n, seconds)
    ns.NetworkAdvance(n, seconds or 5)
end
local function command(n, id, text)
    return ns.DashboardCommand(n.dashboards[id], text)
end
local function pair(n, child, parent)
    command(n, child, "invite " .. parent .. " 12345678")
    command(n, parent, "pair " .. child .. " 12345678")
    advance(n, 2)
    local f = n.transports[child].family
    assert(f.pending)
    if f.profile.supervision == "paired" then
        local existing = next(f.profile.guardians)
        command(
            n,
            existing,
            "add " .. child .. " " .. parent .. " " .. f.pending.operation .. " confirm"
        )
        advance(n, 3)
        assert(f.profile.guardians[parent])
    else
        assert(
            ns.FamilyConfirm(
                f,
                parent,
                f.pending.operation,
                true,
                n.sim.now,
                n.sim.endpoints[child].friends
            )
        )
    end
    command(n, parent, "sync " .. child)
    advance(n, 4)
    assert(n.sim.endpoints[parent].profile.childProfiles[child])
end
local function paired()
    local n = ns.NewNetworkSimulator()
    pair(n, "child", "parent")
    return n, n.transports.parent, n.sim.endpoints.child.profile
end
local function request(n, kind, args, seconds, parent, child)
    local item, reason =
        ns.TransportRequest(n.transports[parent or "parent"], child or "child", kind, args, seconds)
    assert(item, reason)
    return item
end
local function policy(n, channel, direction, mode, seconds, parent, child)
    return request(
        n,
        "policy",
        { channel, direction, mode or "indefinite", "", "", "" },
        seconds,
        parent,
        child
    )
end

test("dashboard pairing, confirmed supervision, sync and policy use shared transport", function()
    local n, t, child = paired()
    local item = policy(n, "party", "read")
    assert(item.state == "pending")
    advance(n)
    assert(item.state == "applied" and item.revision == 1)
    assert(child.policy.channels.party.read and not child.policy.channels.party.send)
    local view = t.family.profile.childProfiles.child
    assert(view.settings["party/read/"].mode == "indefinite")
    assert(ns.DashboardText(n.dashboards.parent):find("applied", 1, true))
    assert(ns.DashboardText(n.dashboards.child):find("party read: true", 1, true))
end)

test(
    "receipt marks delivered before application acknowledgement; send result alone does not",
    function()
        local n, t = paired()
        local item = policy(n, "party", "read")
        ns.TransportTick(t)
        assert(item.state == "pending")
        -- Deliver request, then receipt, holding the acknowledgement.
        while #n.sim.queue > 0 do
            local packet = table.remove(n.sim.queue, 1)
            ns.TransportReceive(n.transports[packet.recipient], packet.sender, packet.wire)
        end
        for _ = 1, 3 do
            n.sim.now = n.sim.now + 0.2
            ns.TransportTick(n.transports.child)
            local packet = table.remove(n.sim.queue, 1)
            if packet then
                if packet.wire:sub(1, 2) == "D|" then
                    ns.TransportReceive(t, packet.sender, packet.wire)
                    break
                end
            end
        end
        assert(item.state == "delivered")
        advance(n, 10)
        assert(item.state == "applied")
    end
)

test("lost acknowledgements retry the identical operation and preserve child order", function()
    local n, t, child = paired()
    local item = policy(n, "party", "read")
    -- Drop child replies but retain parent traffic.
    local original = n.transports.child.io.send
    n.transports.child.io.send = function()
        return "sent"
    end
    advance(n, 8)
    assert(child.policyRevision == 1 and item.attempts >= 2 and item.state == "pending")
    local wire, operation = item.wire, item.operation
    n.transports.child.io.send = original
    advance(n, 20)
    assert(item.state == "applied" and item.wire == wire and item.operation == operation)
    assert(child.policyRevision == 1 and item.revision == 1)
    assert(next(t.family.outgoing) == nil)
end)

test("loss, duplication, delay and disconnection recover before deadline", function()
    local n, _, child = paired()
    n.sim.loss, n.sim.duplicate = true, true
    local item = policy(n, "party", "send")
    advance(n, 5)
    assert(not child.policy.channels.party)
    n.sim.loss, n.sim.delay = false, 0.4
    n.sim.endpoints.child.online = false
    advance(n, 5)
    n.routes.child = 99 -- New transient game handle after changing alts.
    n.sim.endpoints.child.online = true
    advance(n, 20)
    assert(item.state == "applied" and child.policyRevision == 1)
end)

test(
    "independent settings, two guardians and reordered writes use child acceptance order",
    function()
        local n, _, child = paired()
        pair(n, "child", "parent2")
        command(n, "parent", "sync child")
        advance(n)
        local read = policy(n, "party", "read", "indefinite", 60, "parent")
        local send = policy(n, "party", "send", "indefinite", 60, "parent2")
        advance(n)
        assert(read.state == "applied" and send.state == "applied")
        assert(read.revision ~= send.revision and child.policyRevision == 2)
        -- Order two same-setting writes explicitly at the child, then replay the first.
        local a = policy(n, "party", "read", "indefinite")
        local b = policy(n, "party", "read", "revoke")
        local f = n.transports.child.family
        assert(ns.FamilyReceive(f, "parent", b.wire, n.sim.now, { parent = true }))
        assert(ns.FamilyReceive(f, "parent", a.wire, n.sim.now, { parent = true }))
        assert(child.policyRevision == 4 and child.policy.channels.party.read)
        assert(ns.FamilyReceive(f, "parent", b.wire, n.sim.now, { parent = true }))
        assert(child.policyRevision == 4 and child.policy.channels.party.read)
    end
)

test("stale queued policy expires locally and delayed packets cannot apply at the child", function()
    local n, _, child = paired()
    n.sim.endpoints.child.online = false
    local item = policy(n, "party", "read", "indefinite", 3)
    advance(n, 5)
    assert(item.state == "expired")
    local ok, reason = ns.FamilyReceive(
        n.transports.child.family,
        "parent",
        item.wire,
        n.sim.now,
        { parent = true }
    )
    assert(not ok and reason == "delivery-expired" and not child.policy.channels.party)
    n.sim.endpoints.child.online = true
    advance(n)
    assert(not child.policy.channels.party)
end)

test("generation change cancels queued edits, snapshots reconcile membership and policy", function()
    local n, t, child = paired()
    policy(n, "party", "read")
    advance(n)
    n.sim.endpoints.child.online = false
    local delayed = policy(n, "party", "send")
    delayed.due = n.sim.now + 50
    n.sim.endpoints.child.online = true
    pair(n, "child", "parent2")
    command(n, "parent", "sync child")
    advance(n, 10)
    local view = t.family.profile.childProfiles.child
    assert(delayed.state == "cancelled" or delayed.state == "rejected")
    assert(view.generation == child.generation and view.members.parent2)
    assert(view.settings["party/read/"].mode == "indefinite")
    assert(not child.policy.channels.party.send)
end)

test("child isolation rejects wrong-peer receipts and acknowledgements", function()
    local n, t = paired()
    pair(n, "child2", "parent")
    local item = policy(n, "party", "read")
    assert(not ns.TransportReceive(t, "child2", "D|" .. item.id))
    assert(item.state == "pending")
    advance(n)
    assert(n.sim.endpoints.child.profile.policy.channels.party.read)
    assert(not n.sim.endpoints.child2.profile.policy.channels.party)
    assert(t.family.profile.childProfiles.child2.settings["party/read/"] == nil)
end)

test(
    "bounded fragments reject malformed, oversized, conflicting and unauthenticated input",
    function()
        local n = paired()
        local t = n.transports.child
        assert(not ns.TransportReceive(t, "stranger", "F|x|1|1|x"))
        for _, packet in ipairs({
            string.rep("x", 241),
            "F|x|0|1|x",
            "F|x|1|13|x",
            "F|x|1|1|" .. string.rep("x", 181),
        }) do
            assert(not ns.TransportReceive(t, "parent", packet))
        end
        assert(ns.TransportReceive(t, "parent", "F|x|1|2|abc"))
        assert(not ns.TransportReceive(t, "parent", "F|x|1|2|def"))
        for i = 1, 32 do
            assert(ns.TransportReceive(t, "parent", "F|x" .. i .. "|1|2|abc"))
        end
        assert(not ns.TransportReceive(t, "parent", "F|overflow|1|2|abc"))
        advance(n, 16)
        assert(next(t.incoming) == nil)
    end
)

test("fragmentation reassembles reversed and duplicate parts without duplicate writes", function()
    local n, _, child = paired()
    local target = string.rep("a", 120)
    local item = request(n, "policy", { "whisper-account", "read", "indefinite", "", "", target })
    assert(#item.wire > 180)
    local packets = {}
    for i = 1, math.ceil(#item.wire / 180) do
        packets[i] = "F|manual|"
            .. i
            .. "|"
            .. math.ceil(#item.wire / 180)
            .. "|"
            .. item.wire:sub((i - 1) * 180 + 1, i * 180)
    end
    for i = #packets, 1, -1 do
        assert(ns.TransportReceive(n.transports.child, "parent", packets[i]))
    end
    for i = #packets, 1, -1 do
        assert(ns.TransportReceive(n.transports.child, "parent", packets[i]))
    end
    assert(child.policyRevision == 1 and child.policy.whispers["whisper-account:" .. target])
end)

test("throttling and lockdown back off without losing operation or pretending delivery", function()
    local n, t = paired()
    local send = t.io.send
    local item = policy(n, "party", "read")
    local calls = 0
    t.io.send = function()
        calls = calls + 1
        return "lockdown"
    end
    advance(n, 4)
    assert(calls == 1 and item.state == "pending")
    t.io.send = function()
        return "throttled"
    end
    advance(n, 3)
    assert(item.state == "pending" and item.result == "throttled")
    t.io.send = send
    advance(n, 5)
    assert(item.state == "applied")
end)

test(
    "presence means responding or unreachable, with last contact and saved policy retained",
    function()
        local n, t, child = paired()
        policy(n, "party", "read")
        advance(n)
        assert(ns.TransportPresence(t, "child") == "responding")
        n.sim.endpoints.child.online = false
        advance(n, 31)
        local status, last = ns.TransportPresence(t, "child")
        assert(status == "unreachable" and last and child.policy.channels.party.read)
        assert(ns.DashboardText(n.dashboards.parent):find("last contact", 1, true))
    end
)

test("persisted revision and replay survive reload; transient work is discarded", function()
    local n, _, child = paired()
    local item = policy(n, "party", "read")
    advance(n)
    local restored = ns.NewFamily(ns.NormalizeSettings(child), "child", function()
        return "new-generation"
    end)
    local ok, _, ack = ns.FamilyReceive(restored, "parent", item.wire, n.sim.now, { parent = true })
    assert(ok and ns.DecodeMessage(ack)[7] == "1" and child.policyRevision == 1)
    child.policyRevision = -1
    assert(ns.NormalizeSettings(child).supervision == "recovery")
end)

test("command harness remains isolated and child effective view respects expiry", function()
    local live = { marker = true }
    ns.settings = live
    local c = commands.KINWARDSIM
    c("network-reset")
    c("network child invite parent 12345678")
    c("network parent pair child 12345678")
    c("network-pump 2")
    c("network child confirm parent parent:1 confirm")
    c("network parent sync child")
    c("network-pump 4")
    c("network parent allow child party read")
    c("network-pump 5")
    c("network-status child")
    assert(output[#output]:find("party read: true", 1, true))
    c("network-loss on")
    c("network parent deny child party read")
    c("network-pump 5")
    c("network-status parent")
    assert(output[#output]:find("pending", 1, true))
    assert(ns.settings == live and next(live) == "marker")
    local n, _, child = paired()
    child.policy.channels.party = { read = { mode = "duration", expiresAt = n.sim.now + 1 } }
    advance(n, 2)
    assert(ns.DashboardText(n.dashboards.child):find("party read: false", 1, true))
end)
test(
    "candidate WoW adapter refreshes alt handles, rejects ambiguous identity and reports restrictions",
    function()
        local n = ns.NewNetworkSimulator()
        local scripts, handle, gameCount, code, locked, restricted = {}, 41, 1, 0, false, false
        local secret = {}
        local frame = {}
        function frame:RegisterEvent(event)
            assert(event == "BN_CHAT_MSG_ADDON")
        end
        function frame:UnregisterEvent(event)
            assert(event == "BN_CHAT_MSG_ADDON")
        end
        function frame:SetScript(name, callback)
            assert(name == "OnEvent" or name == "OnUpdate")
            scripts[name] = callback
        end
        local sent = {}
        local mocks = {
            WOW_PROJECT_ID = 99,
            BNGetNumFriends = function()
                return 1
            end,
            GetServerTime = function()
                return n.sim.now
            end,
            canaccessvalue = function(value)
                return value ~= secret
            end,
            CreateFrame = function(kind)
                assert(kind == "Frame")
                return frame
            end,
            C_ChatInfo = {
                RegisterAddonMessagePrefix = function(prefix)
                    assert(prefix == "Kinward4")
                    return 0
                end,
                InChatMessagingLockdown = function()
                    return locked
                end,
                AreOutgoingAddonChatMessagesRestricted = function()
                    return restricted
                end,
            },
            C_BattleNet = {
                GetFriendAccountInfo = function(index)
                    assert(index == 1)
                    return { battleTag = "parent", isFriend = true }
                end,
                GetFriendNumGameAccounts = function()
                    return gameCount
                end,
                GetFriendGameAccountInfo = function(_, index)
                    return {
                        gameAccountID = index == 1 and handle or 100,
                        clientProgram = "WoW",
                        isOnline = true,
                        wowProjectID = 99,
                    }
                end,
                SendGameData = function(route, prefix, packet)
                    assert(prefix == "Kinward4")
                    sent[#sent + 1] = { route, packet }
                    return code
                end,
            },
        }
        for key, value in pairs(mocks) do
            rawset(env, key, value)
        end
        local t = assert(ns.NewWoWTransport(n.transports.child.family, "test"))
        assert(t.io.resolve("parent") == 41 and not t.io.resolve("stranger"))
        handle = 42
        assert(t.io.resolve("parent") == 42)
        gameCount = 2
        assert(not t.io.resolve("parent"))
        scripts.OnEvent(frame, "BN_CHAT_MSG_ADDON", "Kinward4", "F|p|1|2|x", "", 42)
        assert(next(t.incoming) == nil)
        gameCount = 1
        scripts.OnEvent(frame, "BN_CHAT_MSG_ADDON", "Kinward4", "F|p|1|2|x", "", 41)
        assert(next(t.incoming) == nil)
        scripts.OnEvent(frame, "BN_CHAT_MSG_ADDON", "Kinward4", "F|p|1|2|x", "", 42)
        assert(t.incoming["parent/p"])
        scripts.OnEvent(frame, "BN_CHAT_MSG_ADDON", secret, secret, "", secret)
        for _, expected in ipairs({
            { 0, "sent" },
            { 3, "throttled" },
            { 8, "throttled" },
            { 11, "lockdown" },
            { 12, "unreachable" },
            { 9, "send-error" },
        }) do
            code = expected[1]
            assert(t.io.send(42, "test") == expected[2])
        end
        local count = #sent
        locked = true
        assert(t.io.send(42, "test") == "lockdown" and #sent == count)
        locked, restricted = false, true
        assert(t.io.send(42, "test") == "lockdown" and #sent == count)
        handle = secret
        assert(not t.io.resolve("parent"))
        t.stop()
        assert(not scripts.OnEvent and not scripts.OnUpdate)
        for key in pairs(mocks) do
            rawset(env, key, nil)
        end
    end
)

local function withWidgets(body)
    local frames = {}
    local function widget(kind, parent)
        local obj = {
            kind = kind,
            parent = parent or false,
            scripts = {},
            value = "",
            visible = true,
            enabled = true,
        }
        local methods = {}
        for _, key in ipairs({
            "SetSize",
            "SetFrameStrata",
            "SetAllPoints",
            "SetColorTexture",
            "SetWidth",
            "SetJustifyH",
            "SetAutoFocus",
            "SetMaxLetters",
            "SetHeight",
            "ClearFocus",
        }) do
            methods[key] = function() end
        end
        function methods:SetPoint(_, x, y)
            self.x, self.y = x, y
        end
        function methods:SetEnabled(value)
            self.enabled = value
        end
        function methods:SetTextColor(r, g, b)
            self.color = { r, g, b }
        end
        function methods:SetScript(name, fn)
            self.scripts[name] = fn
        end
        function methods:SetText(value)
            self.value = value
            if self.kind == "EditBox" and self.scripts.OnTextChanged then
                self.scripts.OnTextChanged(self)
            end
        end
        function methods:GetText()
            return self.value
        end
        function methods:GetStringHeight()
            return 700
        end
        function methods:SetupMenu(generator)
            assert(self.kind == "DropdownButton")
            local entries = {}
            local root = {}
            function root:CreateRadio(caption, isSelected, setSelected)
                entries[#entries + 1] =
                    { caption = caption, isSelected = isSelected, setSelected = setSelected }
            end
            generator(self, root)
            self.menu = entries
            for _, entry in ipairs(entries) do
                if entry.isSelected() then
                    self.value = entry.caption
                end
            end
        end
        function methods:SetScrollChild(child)
            self.child = child
        end
        function methods:Show()
            local wasHidden = not self.visible
            self.visible = true
            if wasHidden and self.scripts.OnShow then
                self.scripts.OnShow(self)
            end
        end
        function methods:Hide()
            self.visible = false
        end
        function methods:CreateTexture()
            return widget("Texture", self)
        end
        function methods:CreateFontString()
            return widget("FontString", self)
        end
        setmetatable(obj, {
            __index = function(_, key)
                return assert(methods[key], "Unexpected widget API " .. key)
            end,
        })
        frames[#frames + 1] = obj
        return obj
    end
    local function visible(control)
        while control do
            if not control.visible then
                return false
            end
            control = control.parent
        end
        return true
    end
    local function find(caption)
        for _, obj in ipairs(frames) do
            if obj.kind == "Button" and obj.value == caption and visible(obj) then
                return obj
            end
        end
        error("No visible button: " .. caption)
    end
    local function click(caption)
        local control = find(caption)
        assert(control.enabled, "Disabled button: " .. caption)
        control.scripts.OnClick(control)
    end
    local function fill(x, y, value)
        for _, obj in ipairs(frames) do
            if obj.kind == "EditBox" and obj.x == x and obj.y == -y and visible(obj) then
                obj:SetText(value)
                return
            end
        end
        error("No visible input at " .. x .. "," .. y)
    end
    local function tick(seconds)
        for _, obj in ipairs(frames) do
            if obj.kind == "Frame" and obj.scripts.OnUpdate and visible(obj) then
                obj.scripts.OnUpdate(obj, seconds)
            end
        end
    end
    rawset(env, "UIParent", { visible = true, parent = false })
    rawset(env, "CreateFrame", function(kind, _, parent)
        return widget(kind, parent)
    end)
    body({
        frames = frames,
        find = find,
        click = click,
        fill = fill,
        tick = tick,
        visible = visible,
    })
    rawset(env, "CreateFrame", nil)
    rawset(env, "UIParent", nil)
end

test("visual role buttons save role and gated live controls cannot send", function()
    withWidgets(function(ui)
        local p = ns.NormalizeSettings(nil)
        local d = ns.NewDashboard(p)
        ns.ShowDashboard(d)
        ui.click("Guardian role")
        assert(p.role == "guardian" and not ui.find("Guardian role").enabled)
        ui.click("Child role")
        ui.fill(18, 26, "parent")
        assert(not ui.find("Request guardianship").enabled)
        local count = #ui.frames
        d.window:Hide()
        ns.ShowDashboard(d)
        assert(#ui.frames == count and ui.visible(d.window))
    end)
end)

test("visual permission buttons show pending then applied and isolate selected children", function()
    withWidgets(function(ui)
        local n = paired()
        pair(n, "child2", "parent")
        local d = n.dashboards.parent
        ns.ShowDashboard(d)
        assert(d.selectedChild == "child")
        ui.click("Allow") -- First row: party read.
        assert(ns.DashboardPermission(d, "child", "party", "read") == "Pending")
        advance(n)
        ui.tick(1)
        assert(ns.DashboardPermission(d, "child", "party", "read") == "Allowed")
        assert(ns.DashboardPermission(d, "child", "party", "send") == "Blocked")
        local other
        for _, obj in ipairs(ui.frames) do
            if obj.kind == "Button" and obj.value:find("child2 ·", 1, true) then
                other = obj
            end
        end
        assert(other)
        other.scripts.OnClick(other)
        assert(d.selectedChild == "child2")
        ui.click("Allow")
        advance(n)
        assert(n.sim.endpoints.child2.profile.policy.channels.party.read)
        assert(not n.sim.endpoints.child.profile.policy.channels.party.send)
        ui.click("Block")
        advance(n)
        assert(not n.sim.endpoints.child2.profile.policy.channels.party.read)
        assert(n.sim.endpoints.child.profile.policy.channels.party.read)
    end)
end)

test("public channel controls apply independent read and send grants", function()
    withWidgets(function(ui)
        local n = paired()
        local d = n.dashboards.parent
        ns.ShowDashboard(d)
        for _, spec in ipairs({
            { "channel:general", 240 },
            { "channel:lookingforgroup", 280 },
            { "channel:trade", 320 },
        }) do
            local found = false
            for _, control in ipairs(ui.frames) do
                if
                    control.kind == "Button"
                    and control.value == "Allow"
                    and control.x == 238
                    and control.y == -spec[2]
                    and ui.visible(control)
                then
                    control.scripts.OnClick(control)
                    found = true
                    break
                end
            end
            assert(found)
            advance(n)
            assert(ns.DashboardPermission(d, "child", spec[1], "read") == "Allowed")
            assert(ns.DashboardPermission(d, "child", spec[1], "send") == "Blocked")
        end
    end)
end)

test("whisper contacts are listed, editable, paginated and isolated by child", function()
    withWidgets(function(ui)
        local n = paired()
        pair(n, "child2", "parent")
        local d = n.dashboards.parent
        ns.DashboardAction(
            d,
            "policy",
            { "child", "whisper-character", "read", "indefinite", "", "", "Friend-Test Realm" }
        )
        advance(n)
        ns.ShowDashboard(d)
        ui.click("Whisper contacts")
        ui.click("friend-testrealm · Character · Allowed")
        ui.click("Block")
        assert(
            ns.DashboardPermission(d, "child", "whisper-character", "read", "friend-testrealm")
                == "Pending"
        )
        advance(n)
        ui.tick(1)
        assert(
            ns.DashboardPermission(d, "child", "whisper-character", "send", "friend-testrealm")
                == "Blocked"
        )
        ui.click("Add whisper contact")
        ui.click("Account")
        ui.fill(18, 275, "Friend#1234")
        ui.click("Allow")
        ui.click("Friend#1234 · Account · Pending")
        advance(n)
        ui.tick(1)
        assert(
            ns.DashboardPermission(d, "child", "whisper-account", "read", "Friend#1234")
                == "Allowed"
        )
        -- Exercise a full fetched list with more contacts than fit on one page.
        local view = d.profile.childProfiles.child
        for i = 1, 7 do
            view.settings["whisper-character/read/person" .. i .. "-realm"] =
                { mode = "indefinite", revision = view.revision }
        end
        ui.tick(1)
        ui.click("Next contacts")
        assert(ui.find("Previous contacts").enabled)
        d.selectedChild = "child2"
        ui.tick(1)
        assert(not ui.find("Next contacts").enabled)
        assert(not ui.find("Allow").enabled)
        for _, control in ipairs(ui.frames) do
            if ui.visible(control) then
                assert(not tostring(control.value):find("friend-testrealm", 1, true))
                assert(not tostring(control.value):find("Friend#1234", 1, true))
            end
        end
    end)
end)

test("visual membership changes require confirmation bound to the original child", function()
    withWidgets(function(ui)
        local n = paired()
        pair(n, "child2", "parent")
        local d = n.dashboards.parent
        ns.ShowDashboard(d)
        ui.click("Family & pairing")
        ui.click("Remove guardian")
        assert(n.sim.endpoints.child.profile.supervision == "paired")
        ui.click("Cancel")
        assert(n.sim.endpoints.child.profile.supervision == "paired")
        ui.click("Remove guardian")
        for _, obj in ipairs(ui.frames) do
            if obj.kind == "Button" and obj.value:find("child2 ·", 1, true) then
                obj.scripts.OnClick(obj)
                break
            end
        end
        assert(d.selectedChild == "child2")
        ui.click("Confirm action")
        advance(n)
        assert(n.sim.endpoints.child.profile.supervision == "unpaired")
        assert(n.sim.endpoints.child2.profile.supervision == "paired")
    end)
end)

test("family confirmation cannot cross a changed relationship generation", function()
    withWidgets(function(ui)
        local n = paired()
        local d = n.dashboards.parent
        ns.ShowDashboard(d)
        ui.click("Family & pairing")
        ui.click("Remove guardian")
        d.profile.childProfiles.child.generation = "new-relationship"
        local before = #d.transport.work
        ui.click("Confirm action")
        assert(#d.transport.work == before)
        assert(d.message:find("membership changed", 1, true))
        assert(n.sim.endpoints.child.profile.supervision == "paired")
    end)
end)

test("single-session visual demo pairs and edits through buttons without live state", function()
    withWidgets(function(ui)
        local live = { marker = true }
        ns.settings = live
        commands.KINWARDSIM("network-reset")
        ns.ShowNetworkDemo()
        ui.click("child")
        ui.fill(18, 26, "parent")
        ui.click("Request guardianship")
        ui.tick(2)
        ui.click("parent")
        ui.click("Guardianship requests (1)")
        ui.click("Accept child")
        ui.tick(8)
        ui.click("Permissions")
        ui.click("Allow")
        ui.tick(5)
        commands.KINWARDSIM("network-status child")
        assert(output[#output]:find("party read: true", 1, true))
        ui.click("Toggle child link")
        ui.click("Block")
        ui.click("Advance 65 sec")
        commands.KINWARDSIM("network-status parent")
        assert(output[#output]:find("expired", 1, true))
        ui.click("Toggle child link")
        ui.tick(5)
        commands.KINWARDSIM("network-status child")
        assert(output[#output]:find("party read: true", 1, true))
        assert(ns.settings == live and next(live) == "marker")
    end)
end)

test("typed UI actions preserve spaced realm targets and bidirectional whisper views", function()
    local n = paired()
    local d = n.dashboards.parent
    ns.DashboardAction(
        d,
        "policy",
        { "child", "whisper-character", "read", "indefinite", "", "", "Friend-Test Realm" }
    )
    advance(n)
    assert(
        ns.DashboardPermission(d, "child", "whisper-character", "read", "Friend-Test Realm")
            == "Allowed"
    )
    assert(
        ns.DashboardPermission(d, "child", "whisper-character", "send", "Friend-Test Realm")
            == "Allowed"
    )
    ns.DashboardAction(
        d,
        "policy",
        { "child", "whisper-character", "send", "revoke", "", "", "Friend-Test Realm" }
    )
    assert(
        ns.DashboardPermission(d, "child", "whisper-character", "read", "Friend-Test Realm")
            == "Pending"
    )
    advance(n)
    assert(
        ns.DashboardPermission(d, "child", "whisper-character", "read", "Friend-Test Realm")
            == "Blocked"
    )
    assert(
        ns.DashboardPermission(d, "child", "whisper-character", "send", "Friend-Test Realm")
            == "Blocked"
    )
end)

test(
    "bounded revision snapshots discard inconsistent pages and persisted malformed views fail closed",
    function()
        local n, t, child = paired()
        policy(n, "party", "read")
        policy(n, "party", "send")
        request(n, "policy", { "whisper-character", "read", "indefinite", "", "", "Friend-Realm" })
        advance(n, 10)
        command(n, "parent", "sync child")
        advance(n, 10)
        local view = t.family.profile.childProfiles.child
        assert(view.revision == 3 and view.settings["whisper-character/read/friend-realm"])
        assert(view.settings["party/send/"].revision == 3)
        local snap = request(n, "snapshot", { "2", "2" })
        local ok, reason = ns.FamilyReceive(
            n.transports.child.family,
            "parent",
            snap.wire,
            n.sim.now,
            { parent = true }
        )
        assert(not ok and reason == "snapshot-changed" and child.policyRevision == 3)
        assert(ns.NormalizeSettings(t.family.profile).role == "guardian")
        view.settings.bad = { mode = "duration", revision = 1 }
        assert(ns.NormalizeSettings(t.family.profile).supervision == "recovery")
    end
)

print(string.format("%d phase 4 tests passed (Lua %s)", passed, _VERSION))
