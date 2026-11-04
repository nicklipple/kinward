local ns, output = {}, {}
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
    SlashCmdList = {},
    print = function(s)
        output[#output + 1] = s
    end,
}
setmetatable(env, {
    __index = function(_, k)
        error("Unexpected global: " .. k)
    end,
    __newindex = function(t, k, v)
        assert(k == "SLASH_KINWARDSIM1", "Unexpected global write: " .. k)
        rawset(t, k, v)
    end,
})
for _, f in ipairs({
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
    "PlayerMenu.lua",
    "Dashboard.lua",
    "Chat.lua",
    "WoWChat.lua",
    "scripts/probes/Phase2Simulator.lua",
}) do
    setfenv(assert(loadfile(f)), env)("Kinward", ns)
end
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end
local function advance(n, seconds)
    ns.NetworkAdvance(n, seconds or 8)
end
local function pair(n, child, parent)
    local c, g = n.dashboards[child], n.dashboards[parent]
    ns.DashboardCommand(c, "invite " .. parent .. " 12345678")
    ns.DashboardCommand(g, "pair " .. child .. " 12345678")
    advance(n, 2)
    local f = n.transports[child].family
    if f.profile.supervision == "paired" then
        local peer = next(f.profile.guardians)
        assert(
            ns.TransportRequest(
                n.transports[peer],
                child,
                "add",
                { parent, f.pending.operation, "confirm" }
            )
        )
        advance(n, 3)
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
    assert(ns.TransportRequest(n.transports[parent], child, "sync", {}))
    advance(n, 4)
end
local function paired()
    local n = ns.NewNetworkSimulator()
    pair(n, "child", "parent")
    return n, n.sim.endpoints.child.profile
end
local function create(n, channel, direction, target, reason)
    local p = n.sim.endpoints.child.profile
    local r, status = ns.CreateRequest(
        p,
        "child",
        channel or "party",
        direction or "read",
        target or "",
        reason or "Please allow",
        n.sim.now
    )
    assert(r, status)
    return r
end
local function fetch(n, parent, child)
    parent, child = parent or "parent", child or "child"
    assert(ns.TransportRequest(n.transports[parent], child, "request-list", { "1" }))
    advance(n)
    return n.sim.endpoints[parent].profile.childProfiles[child].requests
end
local function decision(n, r, action, mode, seconds, parent)
    local item, status = ns.TransportRequest(
        n.transports[parent or "parent"],
        "child",
        "request-decision",
        { r.id, action or "approve", mode or "indefinite", seconds or "", tostring(r.baseRevision) }
    )
    assert(item, status)
    return item
end
local function direct(n, r, action, mode, seconds, parent, deadline)
    parent = parent or "parent"
    local f = n.transports[parent].family
    local wire = assert(
        ns.FamilyRequest(f, "child", n.sim.endpoints.child.profile.generation, "request-decision", {
            r.id,
            action or "approve",
            mode or "indefinite",
            seconds or "",
            tostring(r.baseRevision),
            tostring(deadline or n.sim.now + 60),
        })
    )
    local ok, reason, ack = ns.FamilyReceive(
        n.transports.child.family,
        parent,
        wire,
        n.sim.now,
        n.sim.endpoints.child.friends
    )
    return ok, reason, ack, wire
end

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

local function fresh()
    return ns.NewNetworkSimulator()
end
local function requestParent(n, child, name)
    child, name = child or "child", name or "parent"
    local ok, message = ns.RequestGuardianship(n.transports[child], name)
    assert(ok, message)
    advance(n, 2)
    return n.transports[child].family.proposal
end
local function acceptChild(n, parent, child)
    parent, child = parent or "parent", child or "child"
    local inbox = n.transports[parent].family.guardianInbox
    local r = assert(inbox and inbox[child])
    local ok, message = ns.AnswerGuardianship(n.transports[parent], child, r.token, true)
    assert(ok, message)
    advance(n, 8)
    return r
end

test(
    "child enters guardian name and guardian accepts without a code or second child confirmation",
    function()
        local n = fresh()
        local p = n.sim.endpoints.child.profile
        local r = requestParent(n, "child", "Parent-TestRealm")
        assert(r.peer == "parent" and p.supervision == "unpaired")
        assert(not n.sim.endpoints.parent.profile.children.child)
        acceptChild(n)
        assert(p.supervision == "paired" and p.guardians.parent)
        assert(not next(p.policy.channels) and not next(p.policy.whispers))
        assert(n.sim.endpoints.parent.profile.children.child)
        assert(n.transports.parent.family.guardianInbox.child.state == "accepted")
    end
)
test("ambiguous, unknown, self and nonfriend names never queue a request", function()
    local n = fresh()
    assert(not ns.RequestGuardianship(n.transports.child, "unknown"))
    assert(not ns.RequestGuardianship(n.transports.child, "child"))
    n.sim.endpoints.child.friends.parent = nil
    assert(not ns.RequestGuardianship(n.transports.child, "parent"))
    n.transports.child.io.findPeer = function()
        return nil
    end
    assert(not ns.RequestGuardianship(n.transports.child, "ambiguous"))
    assert(not n.transports.child.family.proposal and #n.sim.queue == 0)
end)
test("unsolicited acceptance and wrong peer/token cannot install supervision", function()
    local n = fresh()
    local f = n.transports.child.family
    local function wire(peer, token)
        return ns.EncodeMessage({
            "1",
            "guardian-accept",
            peer .. ":1",
            f.profile.generation,
            "1",
            token,
            tostring(n.sim.now + 120),
        })
    end
    assert(
        not ns.FamilyReceive(f, "parent", wire("parent", "unknown"), n.sim.now, { parent = true })
    )
    local r = requestParent(n)
    assert(
        not ns.FamilyReceive(f, "parent2", wire("parent2", r.token), n.sim.now, { parent2 = true })
    )
    assert(not ns.FamilyReceive(f, "parent", wire("parent", "wrong"), n.sim.now, { parent = true }))
    assert(f.profile.supervision == "unpaired")
end)
test("cancelled child requests reject delayed acceptance and queued sends stop", function()
    local n = fresh()
    local r = requestParent(n)
    assert(ns.AnswerGuardianship(n.transports.parent, "child", r.token, true))
    r.state = "cancelled"
    n.transports.child.family.pending = nil
    advance(n)
    assert(n.sim.endpoints.child.profile.supervision == "unpaired")
    local n2 = fresh()
    assert(ns.RequestGuardianship(n2.transports.child, "parent"))
    n2.transports.child.family.proposal.state = "cancelled"
    advance(n2)
    assert(not n2.transports.parent.family.guardianInbox)
end)
test("expired requests and declined requests do not pair", function()
    local n = fresh()
    local r = requestParent(n)
    n.sim.now = r.expires
    assert(not ns.AnswerGuardianship(n.transports.parent, "child", r.token, true))
    assert(n.sim.endpoints.child.profile.supervision == "unpaired")
    n = fresh()
    r = requestParent(n)
    assert(ns.AnswerGuardianship(n.transports.parent, "child", r.token, false))
    advance(n)
    assert(r.state == "declined" and n.sim.endpoints.child.profile.supervision == "unpaired")
    assert(n.transports.parent.family.guardianInbox.child.state == "declined")
end)
test(
    "duplicate traffic and lost final state retry cannot rotate the installed family twice",
    function()
        local n = fresh()
        n.sim.duplicate = true
        local r = requestParent(n)
        assert(ns.AnswerGuardianship(n.transports.parent, "child", r.token, true))
        local acceptance
        for _, item in ipairs(n.transports.parent.work) do
            if item.kind == "guardian-accept" then
                acceptance = item
            end
        end
        advance(n)
        local p, gen = n.sim.endpoints.child.profile, n.sim.endpoints.child.profile.generation
        local ok, result, response = ns.FamilyReceive(
            n.transports.child.family,
            "parent",
            acceptance.wire,
            n.sim.now,
            { parent = true }
        )
        assert(ok and result == "paired" and response and p.generation == gen)
        ns.NormalizeSettings(p)
        n.transports.child.family = ns.NewFamily(p, "child", function()
            error("must not rotate on retry")
        end)
        assert(
            ns.FamilyReceive(
                n.transports.child.family,
                "parent",
                acceptance.wire,
                n.sim.now,
                { parent = true }
            )
        )
        assert(p.generation == gen)
    end
)
test("reset and a replaced child request invalidate an old acceptance", function()
    local n = fresh()
    local r = requestParent(n)
    assert(ns.AnswerGuardianship(n.transports.parent, "child", r.token, true))
    local old
    for _, item in ipairs(n.transports.parent.work) do
        if item.kind == "guardian-accept" then
            old = item.wire
        end
    end
    assert(ns.FamilyReset(n.transports.child.family, true))
    assert(
        not ns.FamilyReceive(n.transports.child.family, "parent", old, n.sim.now, { parent = true })
    )
    assert(n.sim.endpoints.child.profile.supervision == "unpaired")
end)
test(
    "a second guardian requires an existing guardian's approval with an automatically fetched target",
    function()
        local n = fresh()
        requestParent(n)
        acceptChild(n)
        local r = requestParent(n, "child", "parent2")
        acceptChild(n, "parent2")
        assert(
            r.state == "awaiting-approval" and not n.sim.endpoints.child.profile.guardians.parent2
        )
        n.transports.parent.pairingPolling = true
        n.transports.parent.nextPairingPoll = 0
        advance(n, 8)
        local c = assert(n.transports.parent.guardianCandidates.child)
        assert(c.peer == "parent2" and c.token == r.token)
        assert(
            ns.TransportRequest(n.transports.parent, "child", "add", { c.peer, c.token, "confirm" })
        )
        advance(n, 12)
        assert(n.sim.endpoints.child.profile.guardians.parent2)
        assert(n.sim.endpoints.parent2.profile.children.child)
    end
)
test("duplicate and reordered requests never replace a newer guardian inbox row", function()
    local n = fresh()
    local first = requestParent(n)
    local oldWire
    for _, item in ipairs(n.transports.child.work) do
        if item.kind == "guardian-request" then
            oldWire = item.wire
        end
    end
    first.state = "cancelled"
    local newer = requestParent(n)
    local inbox = n.transports.parent.family.guardianInbox.child
    assert(inbox.token == newer.token)
    assert(
        not ns.FamilyReceive(
            n.transports.parent.family,
            "child",
            oldWire,
            n.sim.now,
            { child = true }
        )
    )
    assert(n.transports.parent.family.guardianInbox.child.token == newer.token)
end)
test("guardian replies are bound to the rendered request token", function()
    local n = fresh()
    local first = requestParent(n)
    first.state = "cancelled"
    requestParent(n)
    assert(not ns.AnswerGuardianship(n.transports.parent, "child", first.token, true))
    assert(n.sim.endpoints.child.profile.supervision == "unpaired")
end)
test("friendship loss before delivery prevents pairing", function()
    local n = fresh()
    local r = requestParent(n)
    assert(ns.AnswerGuardianship(n.transports.parent, "child", r.token, true))
    n.sim.endpoints.child.friends.parent = nil
    advance(n)
    assert(n.sim.endpoints.child.profile.supervision == "unpaired")
end)
test("pairing inbox allocation is bounded for authenticated friends", function()
    local n = fresh()
    local f = n.transports.parent.family
    local friends = {}
    for i = 1, 17 do
        local peer = "child" .. i
        friends[peer] = true
        local wire = ns.EncodeMessage({
            "1",
            "guardian-request",
            peer .. ":1",
            "initial",
            "1",
            "request-token-" .. i,
            tostring(n.sim.now + 120),
        })
        local ok, reason = ns.FamilyReceive(f, peer, wire, n.sim.now, friends)
        if i <= 16 then
            assert(ok)
        else
            assert(not ok and reason == "pairing-inbox-full")
        end
    end
end)
test("invalid persisted receipt cannot silently restore supervision", function()
    local n = fresh()
    requestParent(n)
    acceptChild(n)
    local p = n.sim.endpoints.child.profile
    assert(ns.NormalizeSettings(p) == p)
    p.pairingReceipt.peer = "stranger"
    assert(ns.NormalizeSettings(p).supervision == "recovery")
end)
test(
    "child and guardian widgets complete pairing with one typed name and one accept click",
    function()
        local n = fresh()
        withWidgets(function(ui)
            local c, g = n.dashboards.child, n.dashboards.parent
            ns.ShowDashboard(c)
            ui.fill(18, 26, "parent")
            ui.click("Request guardianship")
            assert(n.sim.endpoints.child.profile.supervision == "unpaired")
            advance(n, 2)
            c.window:Hide()
            ns.ShowDashboard(g)
            ui.click("Guardianship requests (1)")
            ui.click("Accept child")
            assert(not g.profile.children.child)
            advance(n, 8)
            ui.tick(0.6)
            assert(g.profile.children.child and n.sim.endpoints.child.profile.guardians.parent)
            for _, w in ipairs(ui.frames) do
                assert(not tostring(w.value):find("Eight-digit", 1, true))
                assert(not tostring(w.value):find("exact pending operation", 1, true))
            end
        end)
    end
)
test("additional guardian approval needs no typed peer or operation fields", function()
    local n = fresh()
    requestParent(n)
    acceptChild(n)
    requestParent(n, "child", "parent2")
    acceptChild(n, "parent2")
    withWidgets(function(ui)
        local d = n.dashboards.parent
        ns.ShowDashboard(d)
        ui.click("Family & pairing")
        advance(n, 8)
        ui.tick(0.6)
        ui.click("Approve guardian")
        ui.click("Confirm action")
        advance(n, 12)
        assert(n.sim.endpoints.child.profile.guardians.parent2)
    end)
end)
test(
    "candidate resolves unique verified friend aliases and rejects ambiguity, secrets and stale alts",
    function()
        local n = fresh()
        local secret = setmetatable({}, {
            __tostring = function()
                error("secret serialized")
            end,
        })
        local friends = {
            { tag = "Parent#123", name = "Parent", realm = "Test Realm", handle = 1 },
            { tag = "Other#456", name = "Parent", realm = "Other Realm", handle = 2 },
        }
        local count = 2
        local scripts = {}
        local frame = {}
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:SetScript(k, fn)
            scripts[k] = fn
        end
        local mocks = {
            WOW_PROJECT_ID = 99,
            BNGetNumFriends = function()
                return count
            end,
            canaccessvalue = function(v)
                return not rawequal(v, secret)
            end,
            GetServerTime = function()
                return n.sim.now
            end,
            CreateFrame = function()
                return frame
            end,
            C_ChatInfo = {
                RegisterAddonMessagePrefix = function()
                    return 0
                end,
            },
            C_BattleNet = {
                GetFriendAccountInfo = function(i)
                    return friends[i] and { isFriend = true, battleTag = friends[i].tag }
                end,
                GetFriendNumGameAccounts = function()
                    return 1
                end,
                GetFriendGameAccountInfo = function(i)
                    local r = friends[i]
                    return {
                        gameAccountID = r.handle,
                        clientProgram = "WoW",
                        wowProjectID = 99,
                        isOnline = true,
                        characterName = r.name,
                        realmName = r.realm,
                    }
                end,
            },
        }
        for k, v in pairs(mocks) do
            rawset(env, k, v)
        end
        local t = assert(ns.NewWoWTransport(n.transports.parent.family, "lookup", true))
        assert(not t.io.findPeer("Parent"))
        assert(t.io.findPeer("Parent-Test Realm") == "Parent#123")
        assert(t.io.findPeer("parent#123") == "Parent#123")
        friends[1].name = "Newalt"
        assert(t.io.findPeer("Parent") == "Other#456")
        assert(not t.io.findPeer("Parent-TestRealm"))
        assert(t.io.findPeer("Newalt-TestRealm") == "Parent#123")
        local savedSettings, savedDashboard, savedShow = ns.settings, ns.dashboard, ns.ShowDashboard
        local opened = 0
        ns.settings, ns.dashboard = n.transports.parent.family.profile, nil
        ns.ShowDashboard = function(d, section)
            assert(d.profile == ns.settings and d.transport == t and section == "family")
            opened = opened + 1
        end
        local wire = assert(ns.EncodeMessage({
            "1",
            "guardian-request",
            "Parent#123:1",
            "initial",
            "1",
            "popup-token",
            tostring(n.sim.now + 120),
        }))
        scripts.OnEvent(frame, "BN_CHAT_MSG_ADDON", "Kinward4", "F|popup|1|1|" .. wire, "", 1)
        scripts.OnEvent(frame, "BN_CHAT_MSG_ADDON", "Kinward4", "F|popup|1|1|" .. wire, "", 1)
        assert(opened == 1)
        ns.settings, ns.dashboard, ns.ShowDashboard = savedSettings, savedDashboard, savedShow
        friends[1].name = secret
        assert(not t.io.findPeer("Newalt-TestRealm"))
        assert(t.io.findPeer("Parent#123") == "Parent#123")
        count = 201
        assert(not t.io.findPeer("Parent"))
        t.stop()
        for k in pairs(mocks) do
            rawset(env, k, nil)
        end
    end
)
test("repeated token generators cannot reissue a cancelled child's request", function()
    local n = fresh()
    n.transports.child.family.freshToken = function()
        return "repeated"
    end
    local r = requestParent(n)
    r.state = "cancelled"
    assert(not ns.RequestGuardianship(n.transports.child, "parent"))
end)
test("the guardian cannot access policy or history before acceptance is applied", function()
    local n = fresh()
    requestParent(n)
    assert(not n.sim.endpoints.parent.profile.children.child)
    assert(not ns.TransportRequest(n.transports.parent, "child", "history", { "0" }))
    assert(
        not ns.TransportRequest(
            n.transports.parent,
            "child",
            "policy",
            { "party", "read", "indefinite", "", "", "" }
        )
    )
end)
test("a changed name lookup cannot swap the guardian after the child reviewed it", function()
    local n = fresh()
    assert(ns.ResolveGuardianPeer(n.transports.child, "Parent") == "parent")
    n.transports.child.io.findPeer = function()
        return "parent2"
    end
    local ok, reason = ns.RequestGuardianship(n.transports.child, "Parent", "parent")
    assert(not ok and reason:find("different account", 1, true))
    assert(not n.transports.child.family.proposal and #n.sim.queue == 0)
end)
test("the child sees the resolved account before the request button is clicked", function()
    local n = fresh()
    withWidgets(function(ui)
        ns.ShowDashboard(n.dashboards.child)
        ui.fill(18, 26, "Parent-TestRealm")
        local seen = false
        for _, w in ipairs(ui.frames) do
            if
                ui.visible(w)
                and tostring(w.value):find("Send to verified account: parent", 1, true)
            then
                seen = true
            end
        end
        assert(seen and not n.transports.child.family.proposal)
        ui.click("Request guardianship")
        assert(n.transports.child.family.proposal.peer == "parent")
    end)
end)
test(
    "selected cross-realm guardian prefills the child form without sending before consent",
    function()
        local n = fresh()
        withWidgets(function(ui)
            local d = n.dashboards.child
            d.pairingTarget = "Parent-TestRealm"
            ns.ShowDashboard(d, "family")
            assert(d.pairingTarget == nil and not d.transport.family.proposal)
            local found = false
            for _, w in ipairs(ui.frames) do
                if w.kind == "EditBox" and w.value == "Parent-TestRealm" and ui.visible(w) then
                    found = true
                end
            end
            assert(found)
            ui.click("Request guardianship")
            assert(d.transport.family.proposal.peer == "parent")
        end)
    end
)
print(string.format("%d streamlined pairing tests passed (Lua %s)", passed, _VERSION))
