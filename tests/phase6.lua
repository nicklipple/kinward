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
    "Channels.lua",
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
    "Activity.lua",
    "PairingPanel.lua",
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

test(
    "new and existing schema profiles gain bounded request defaults without losing supervision",
    function()
        local n, p = paired()
        assert(p.requests and p.requestPrompts and p.requestSequence == 0)
        p.requests, p.requestPrompts, p.requestSequence = nil, nil, nil
        local normalized = ns.NormalizeSettings(p)
        assert(normalized == p and p.supervision == "paired" and p.requests and p.requestPrompts)
        local r = create(n)
        assert(ns.NormalizeSettings(p).requests[r.id] == r)
    end
)
test("channel and whisper scopes are normalized and pending requests deduplicate", function()
    local n, p = paired()
    local r = create(n, "whisper-character", "read", "Friend-Test Realm")
    assert(r.target == "friend-testrealm")
    local duplicate, reason = ns.CreateRequest(
        p,
        "child",
        "whisper-character",
        "send",
        "FRIEND-TestRealm",
        "another reason",
        n.sim.now
    )
    assert(duplicate == r and reason == "already-pending")
    assert(create(n, "party", "read").id ~= create(n, "party", "send").id)
    assert(create(n, "whisper-account", "read", "Friend#123").target == "Friend#123")
end)
test("malformed scope, reasons, profiles and queue state fail closed", function()
    local n, p = paired()
    for _, spec in ipairs({
        { "whisper", "read", "Friend-Realm", "" },
        { "party", "both", "", "" },
        { "party", "read", "Friend-Realm", "" },
        { "whisper-character", "read", "", "" },
        { "party", "read", "", "bad\nreason" },
        { "party", "read", "", string.rep("a", 161) },
    }) do
        assert(not ns.CreateRequest(p, "child", spec[1], spec[2], spec[3], spec[4], n.sim.now))
    end
    p.requests = { malformed = {} }
    assert(ns.NormalizeSettings(p).supervision == "recovery")
    assert(
        not ns.CreateRequest(ns.NormalizeSettings(nil), "child", "party", "read", "", "", n.sim.now)
    )
end)
test("queues bound pending work and reuse only terminal slots with fresh durable IDs", function()
    local n, p = paired()
    local first
    for i = 1, 32 do
        local r = create(n, "whisper-character", "read", "Friend-Realm" .. i)
        first = first or r
    end
    local r, reason = ns.CreateRequest(p, "child", "party", "read", "", "", n.sim.now)
    assert(not r and reason == "request-queue-full")
    assert(ns.CancelRequest(p, first.id, n.sim.now))
    local last = create(n)
    assert(last.id ~= first.id and not p.requests[first.id] and #ns.RequestRows(p, n.sim.now) == 32)
    assert(ns.NormalizeSettings(p).requestSequence == 33)
end)
test("offline local requests survive normalization and arrive after reconnect", function()
    local n, p = paired()
    n.sim.endpoints.parent.online = false
    local r = create(n)
    advance(n, 25)
    assert(r.state == "pending" and not p.policy.channels.party)
    assert(ns.NormalizeSettings(p).requests[r.id] == r)
    n.sim.endpoints.parent.online = true
    assert(fetch(n)[r.id].reason == "Please allow")
end)
test("request pages return only to an authorized current guardian and isolate children", function()
    local n, p = paired()
    local r = create(n)
    assert(fetch(n)[r.id])
    local f = n.transports.child.family
    local spoof = ns.EncodeMessage({ "1", "request-list", "stranger:1", p.generation, "1", "1" })
    local ok, reason, reply = ns.FamilyReceive(f, "stranger", spoof, n.sim.now, { stranger = true })
    assert(not ok and reason == "unauthorized" and not reply)
    assert(not n.sim.endpoints.parent.profile.childProfiles.child2)
    local old = p.generation
    assert(ns.FamilyReset(f, true))
    assert(not next(p.requests) and p.generation ~= old)
    assert(
        not ns.FamilyReceive(
            f,
            "parent",
            ns.EncodeMessage({ "1", "request-list", "parent:99", old, "99", "1" }),
            n.sim.now,
            { parent = true }
        )
    )
end)
test("indefinite approval becomes effective only when applied and acknowledged", function()
    local n, p = paired()
    local r = create(n)
    fetch(n)
    local item = decision(n, r)
    assert(
        item.state == "pending"
            and r.state == "pending"
            and not ns.ChatDecision(n.chats.child, "party", "read", nil, 1)
    )
    advance(n)
    assert(item.state == "applied" and r.state == "approved")
    assert(ns.ChatDecision(n.chats.child, "party", "read", nil, 2))
    assert(not ns.ChatDecision(n.chats.child, "party", "send"))
    assert(p.policyRevision == 1)
end)
test("timed approval starts on child application rather than guardian queue time", function()
    local n, p = paired()
    local r = create(n)
    n.sim.delay = 2
    local before = n.sim.now
    local item = decision(n, r, "approve", "duration", "900")
    advance(n, 12)
    assert(item.state == "applied" and p.policy.channels.party.read.expiresAt >= before + 902)
    local expiry = p.policy.channels.party.read.expiresAt
    ns.NormalizeSettings(p)
    n.sim.now = expiry
    assert(not ns.ChatDecision(n.chats.child, "party", "read", nil, 101))
end)
test("until-logout approval survives reload but expires at a new simulated login", function()
    local n, p = paired()
    local r = create(n)
    assert(direct(n, r, "approve", "session"))
    local session = p.sessionId
    ns.NormalizeSettings(p)
    ns.BeginSession(p, session)
    assert(ns.ChatDecision(n.chats.child, "party", "read", nil, 1))
    ns.BeginSession(p, "next-login")
    assert(not ns.ChatDecision(n.chats.child, "party", "read", nil, 2))
end)
test("until-logout approvals cannot target an old or unresolved login", function()
    local n, p = paired()
    local r = create(n)
    ns.BeginSession(p, "next-login")
    local ok, reason = direct(n, r, "approve", "session")
    assert(not ok and reason == "request-session-changed")
    assert(not p.policy.channels.party and r.state == "pending")
end)
test("whisper approval is bound to the exact requested identity and is bidirectional", function()
    local n = paired()
    local r = create(n, "whisper-character", "send", "Friend-Test Realm")
    assert(direct(n, r, "approve", "duration", "2700"))
    local c = n.chats.child
    assert(ns.ChatDecision(c, "whisper", "read", { character = "Friend-TestRealm" }, 1))
    assert(ns.ChatDecision(c, "whisper", "send", { character = "Friend-TestRealm" }))
    assert(not ns.ChatDecision(c, "whisper", "read", { character = "Stranger-TestRealm" }, 2))
    assert(not ns.ChatDecision(c, "party", "read", nil, 3))
end)
test(
    "cancelled and expired requests cannot be approved or reopened by delayed decisions",
    function()
        local n, p = paired()
        local r = create(n)
        local item = decision(n, r)
        assert(ns.CancelRequest(p, r.id, n.sim.now))
        advance(n)
        assert(item.state == "rejected" and r.state == "cancelled" and not p.policy.channels.party)
        local timed = create(n)
        n.sim.now = timed.expires
        local ok, reason = direct(n, timed)
        assert(not ok and reason == "request-not-pending" and timed.state == "expired")
    end
)
test("denial is terminal and never grants permission", function()
    local n, p = paired()
    local r = create(n)
    local item = decision(n, r, "deny", "")
    advance(n)
    assert(item.state == "applied" and item.result == "request-denied" and r.state == "denied")
    assert(not p.policy.channels.party and not direct(n, r))
end)
test(
    "duplicate delivery and lost acknowledgements do not extend a duration or write twice",
    function()
        local n, p = paired()
        local r = create(n)
        local ok, reason, _, wire = direct(n, r, "approve", "duration", "900")
        assert(ok and reason == "applied")
        local expiry = p.policy.channels.party.read.expiresAt
        n.sim.now = n.sim.now + 10
        ok, reason = ns.FamilyReceive(
            n.transports.child.family,
            "parent",
            wire,
            n.sim.now,
            { parent = true }
        )
        assert(
            ok
                and reason == "applied"
                and p.policyRevision == 1
                and p.policy.channels.party.read.expiresAt == expiry
        )
        ns.NormalizeSettings(p)
        assert(
            ns.FamilyReceive(
                n.transports.child.family,
                "parent",
                wire,
                n.sim.now,
                { parent = true }
            )
        )
        assert(p.policyRevision == 1)
    end
)
test("two guardians racing decisions use the child's first terminal decision", function()
    local n, p = paired()
    pair(n, "child", "parent2")
    -- Refresh the original guardian after the membership generation rotated.
    ns.DashboardCommand(n.dashboards.parent, "sync child")
    advance(n)
    local r = create(n)
    assert(direct(n, r, "deny", "", "", "parent2"))
    local ok, reason = direct(n, r, "approve", "duration", "900")
    assert(not ok and reason == "request-not-pending" and not p.policy.channels.party)
end)
test("revocation racing an older approval cannot silently reopen permission", function()
    local n, p = paired()
    local r = create(n)
    local policy = assert(
        ns.FamilyRequest(
            n.transports.parent.family,
            "child",
            p.generation,
            "policy",
            { "party", "read", "revoke", "", "", "", tostring(n.sim.now + 60) }
        )
    )
    assert(
        ns.FamilyReceive(n.transports.child.family, "parent", policy, n.sim.now, { parent = true })
    )
    local ok, reason = direct(n, r)
    assert(not ok and reason == "request-policy-changed" and not p.policy.channels.party.read)
end)
test("approval before revocation is removed by that later accepted revoke", function()
    local n, p = paired()
    local r = create(n)
    assert(direct(n, r))
    local wire = assert(
        ns.FamilyRequest(
            n.transports.parent.family,
            "child",
            p.generation,
            "policy",
            { "party", "read", "revoke", "", "", "", tostring(n.sim.now + 60) }
        )
    )
    assert(
        ns.FamilyReceive(n.transports.child.family, "parent", wire, n.sim.now, { parent = true })
    )
    assert(not ns.ChatDecision(n.chats.child, "party", "read", nil, 1))
end)
test("delivery deadlines and invalid durations never mutate requests or policy", function()
    local n, p = paired()
    local r = create(n)
    assert(not direct(n, r, "approve", "duration", "900", nil, n.sim.now))
    for _, duration in ipairs({ "0", "-1", "86401", "nan", "1.5" }) do
        local ok, reason = direct(n, r, "approve", "duration", duration)
        assert(not ok and reason == "invalid-duration")
    end
    assert(r.state == "pending" and not p.policy.channels.party)
end)
test("prompt metadata excludes bodies and is deduplicated and flood limited", function()
    local n, p = paired()
    local c = n.chats.child
    assert(not ns.ChatDecision(c, "whisper", "read", { character = "Stranger-TestRealm" }, 1))
    assert(c.prompt.character == "stranger-testrealm" and not c.prompt.text)
    local first = c.prompt
    ns.ChatDecision(c, "whisper", "read", { character = "Stranger-TestRealm" }, 1)
    ns.ChatDecision(c, "whisper", "read", { character = "Other-TestRealm" }, 2)
    assert(c.prompt == first)
    n.sim.now = n.sim.now + 11
    ns.ChatDecision(c, "whisper", "read", { character = "Other-TestRealm" }, 3)
    assert(c.prompt.character == "other-testrealm")
    c.prompt = nil
    ns.ChatDecision(c, "whisper", "read", nil, 4)
    ns.ChatDecision(c, "whisper", "read", {}, 5)
    assert(not c.prompt)
    p.requestPrompts = false
    n.sim.now = n.sim.now + 61
    ns.ChatDecision(c, "whisper", "read", { character = "Stranger-TestRealm" }, 6)
    assert(not c.prompt)
end)
test("guardian prompt configuration travels through authorization and acknowledgements", function()
    local n, p = paired()
    local item =
        assert(ns.TransportRequest(n.transports.parent, "child", "request-prompts", { "false" }))
    advance(n)
    assert(item.state == "applied" and not p.requestPrompts)
    fetch(n)
    assert(n.sim.endpoints.parent.profile.childProfiles.child.requestPrompts == false)
end)
test("history is never replayed and an already hidden line keeps its decision", function()
    local n = paired()
    local c = n.chats.child
    local identity = { character = "Friend-TestRealm" }
    assert(not ns.ChatDecision(c, "whisper", "read", identity, 1))
    local r = create(n, "whisper-character", "read", "Friend-TestRealm")
    assert(direct(n, r))
    assert(not ns.ChatDecision(c, "whisper", "read", identity, 1))
    assert(ns.ChatDecision(c, "whisper", "read", identity, 2))
    assert(#n.sim.queue == 0)
end)
test(
    "pagination handles 32 requests and malformed pages cannot inject scope or identity",
    function()
        local n = paired()
        for i = 1, 32 do
            create(n, "whisper-character", "read", "Friend-Realm" .. i)
        end
        fetch(n)
        advance(n, 90)
        local cached = n.sim.endpoints.parent.profile.childProfiles.child.requests
        local count = 0
        for _ in pairs(cached) do
            count = count + 1
        end
        assert(count == 32, count)
        assert(not ns.AcceptRequestPage(n.transports.parent, "child", { "1" }, { wire = "broken" }))
    end
)
test("typed dashboard actions support spaced targets and free-text reasons", function()
    local n = paired()
    local d = n.dashboards.child
    assert(
        ns.DashboardAction(
            d,
            "request",
            { "whisper-character", "read", "Friend-Test Realm", "Please let me chat" }
        ) == "queued-locally"
    )
    local r = ns.RequestRows(d.profile, n.sim.now)[1]
    assert(r.target == "friend-testrealm" and r.reason == "Please let me chat")
    assert(ns.DashboardAction(d, "cancel-request", { r.id }) == "cancelled")
    ns.DashboardCommand(d, "request party read - Playing with my group")
    assert(ns.RequestRows(d.profile, n.sim.now)[2].reason == "Playing with my group")
end)

test("damaged request counters cannot reuse durable request IDs", function()
    for _, damage in ipairs({ "missing", "rewind" }) do
        local n, p = paired()
        create(n)
        p.requestSequence = damage == "missing" and nil or 0
        assert(ns.NormalizeSettings(p).supervision == "recovery")
    end
end)
test("an exhausted request sequence does not evict existing terminal records", function()
    local n, p = paired()
    for i = 1, 32 do
        local r = create(n, "whisper-character", "read", "Friend-Realm" .. i)
        assert(ns.CancelRequest(p, r.id, n.sim.now))
    end
    p.requestSequence = 2147483647
    assert(not ns.CreateRequest(p, "child", "party", "read", "", "", n.sim.now))
    assert(#ns.RequestRows(p, n.sim.now) == 32)
end)
test("late offline approval expires before applying even if transport packets arrive", function()
    local n, p = paired()
    local r = create(n)
    n.sim.delay = 61
    local item = decision(n, r)
    advance(n, 80)
    assert(item.state == "expired" and r.state == "pending" and not p.policy.channels.party)
end)
test("old relationship decisions cannot grant after reset and re-pair", function()
    local n, p = paired()
    local r = create(n)
    local f = n.transports.parent.family
    local old = assert(
        ns.FamilyRequest(
            f,
            "child",
            p.generation,
            "request-decision",
            { r.id, "approve", "indefinite", "", "0", tostring(n.sim.now + 60) }
        )
    )
    assert(ns.FamilyReset(n.transports.child.family, true))
    pair(n, "child", "parent")
    local ok, reason =
        ns.FamilyReceive(n.transports.child.family, "parent", old, n.sim.now, { parent = true })
    assert(
        not ok and reason == "unauthorized" and not next(p.requests) and not p.policy.channels.party
    )
end)

test("malformed inbox scope and unrelated cursors cannot replace a complete display", function()
    local n, p = paired()
    local r = create(n)
    local cached = fetch(n)
    assert(cached[r.id])
    local request =
        assert(ns.TransportRequest(n.transports.parent, "child", "request-list", { "1" }))
    local fields = assert(
        ns.DecodeMessage(
            assert(ns.RequestPage(p, assert(ns.DecodeMessage(request.wire)), n.sim.now))
        )
    )
    fields[9], fields[11] = "party", "Wrong-Realm"
    assert(not ns.AcceptRequestPage(n.transports.parent, "child", fields, request))
    assert(n.sim.endpoints.parent.profile.childProfiles.child.requests == cached)
    fields[9], fields[11], fields[6] = "party", "", "2"
    assert(not ns.AcceptRequestPage(n.transports.parent, "child", fields, request))
    assert(n.sim.endpoints.parent.profile.childProfiles.child.requests == cached)
end)

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
            function root:SetScrollMode(height)
                assert(height == 264)
            end
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

test("Requests UI creates, browses, cancels and approves exact scoped requests", function()
    local n, p = paired()
    withWidgets(function(ui)
        local child = n.dashboards.child
        ns.ShowDashboard(child)
        ui.click("Requests")
        ui.fill(274, 26, "")
        ui.fill(18, 120, "I want to play with my party")
        ui.click("Send access request")
        local r = ns.RequestRows(p, n.sim.now)[1]
        assert(r and r.channel == "party" and r.direction == "read")
        ui.click("Cancel selected request")
        assert(r.state == "cancelled")
        ui.click("Send access request")
        child.window:Hide()
        fetch(n)
        local guardian = n.dashboards.parent
        ns.ShowDashboard(guardian)
        ui.click("Requests")
        ui.click("Next")
        ui.click("15 minutes")
        assert(not p.policy.channels.party)
        advance(n)
        ui.tick(0.6)
        assert(p.policy.channels.party.read.mode == "duration")
        assert(not p.policy.channels.party.send)
        assert(ui.find("Connection"))
    end)
end)
test("blocked-whisper UI shows only sender identity and creates a bound request", function()
    local n, p = paired()
    ns.ChatDecision(n.chats.child, "whisper", "read", { character = "Friend-TestRealm" }, 1)
    withWidgets(function(ui)
        local d = n.dashboards.child
        ns.ShowDashboard(d)
        ui.click("Request whisper access")
        local r = ns.RequestRows(p, n.sim.now)[1]
        assert(
            r.channel == "whisper-character" and r.target == "friend-testrealm" and r.reason == ""
        )
        assert(not n.chats.child.prompt)
        local seen = false
        for _, w in ipairs(ui.frames) do
            if
                type(w.value) == "string"
                and w.value:find("Blocked whisper from friend-testrealm", 1, true)
            then
                seen = true
                assert(w.value:find("Message hidden", 1, true))
            end
        end
        assert(seen)
    end)
end)
test("guardian requests UI cannot approve a cached request for a different child", function()
    local n, p = paired()
    pair(n, "child2", "parent")
    local r = create(n)
    fetch(n)
    withWidgets(function(ui)
        local d = n.dashboards.parent
        d.selectedChild = "child"
        ns.ShowDashboard(d)
        ui.click("Requests")
        local approve = ui.find("Approve indefinitely")
        -- Model selection changed but the rendered row still belongs to child1.
        d.selectedChild = "child2"
        approve.scripts.OnClick(approve)
        advance(n)
        assert(r.state == "approved" and p.policy.channels.party.read)
        assert(not n.sim.endpoints.child2.profile.policy.channels.party)
    end)
end)
print(string.format("%d Phase 6 tests passed (Lua %s)", passed, _VERSION))
