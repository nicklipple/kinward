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
    date = os.date,
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
        assert(k == "SLASH_GUARDIANSIM1", "Unexpected global write: " .. k)
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
    "Activity.lua",
    "PairingPanel.lua",
    "Dashboard.lua",
    "Chat.lua",
    "WoWChat.lua",
    "scripts/probes/Phase2Simulator.lua",
}) do
    setfenv(assert(loadfile(f)), env)("Guardian", ns)
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
    n.sim.now = 1700000000
    pair(n, "child", "parent")
    n.sim.endpoints.child.profile.history = ns.NewHistory(n.sim.endpoints.child.profile.generation)
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

local function append(n, body, channel, disposition, time, direction, name)
    return assert(
        ns.AppendHistory(
            n.sim.endpoints.child.profile,
            time or n.sim.now,
            direction or "read",
            channel or "whisper",
            { character = name or "friend-testrealm", account = "friend-account" },
            disposition or "allowed",
            body
        )
    )
end
local function fetchHistory(n, seconds, parent, child)
    parent, child = parent or "parent", child or "child"
    assert(ns.WatchHistory(n.transports[parent], child))
    ns.PollHistory(n.transports[parent])
    advance(n, seconds or 18)
    return n.sim.endpoints[parent].profile.childProfiles[child].history
end
local function batch(n, cursor)
    local t = n.transports.parent
    local item = assert(ns.TransportRequest(t, "child", "history", { tostring(cursor or 0) }))
    local wire = assert(
        ns.HistoryBatch(
            n.sim.endpoints.child.profile,
            assert(ns.DecodeMessage(item.wire)),
            n.sim.now
        )
    )
    return assert(ns.DecodeMessage(wire)), item, wire
end

test("history is an additive bounded migration; damaged source/caches fail closed", function()
    local n, p = paired()
    append(n, "message")
    assert(ns.NormalizeSettings(p) == p)
    local h = fetchHistory(n)
    assert(h and ns.NormalizeSettings(n.sim.endpoints.parent.profile).role == "guardian")
    p.history.high = p.history.high + 1
    assert(ns.NormalizeSettings(p).supervision == "recovery")
    h.records[1].text = false
    assert(ns.NormalizeSettings(n.sim.endpoints.parent.profile).supervision == "recovery")
end)
test("accessible allowed and blocked incoming messages are captured once across frames", function()
    local n, p = paired()
    local c, id = n.chats.child, { character = "stranger-testrealm" }
    local allowed = ns.ChatDecision(c, "whisper", "read", id, 1)
    ns.CaptureRead(c, "whisper", id, "PRIVATE BLOCKED BODY", allowed, 1)
    ns.CaptureRead(c, "whisper", id, "PRIVATE BLOCKED BODY", allowed, 1)
    assert(#p.history.records == 1 and p.history.records[1].disposition == "blocked")
    assert(
        p.history.records[1].text == "PRIVATE BLOCKED BODY"
            and p.history.records[1].character == "stranger-testrealm"
    )
    ns.CaptureRead(c, "party", id, "Accessible party line", true, 2)
    assert(p.history.records[2].disposition == "allowed")
end)
test(
    "missing line IDs and inaccessible text create bounded gaps without text or guesses",
    function()
        local n, p = paired()
        local c = n.chats.child
        ns.CaptureRead(c, "whisper", nil, nil, false, 1)
        ns.CaptureRead(c, "whisper", nil, nil, false, 1)
        for _ = 1, 100 do
            ns.CaptureRead(c, "whisper", nil, "do not capture unidentifiable text", false, nil)
        end
        assert(#p.history.records == 2)
        for _, r in ipairs(p.history.records) do
            assert(r.disposition == "gap" and not r.text:find("do not capture", 1, true))
        end
    end
)
test("blocked sends record attempts and allowed sends await output or timeout", function()
    local n, p = paired()
    local c, id = n.chats.child, { character = "friend-testrealm" }
    ns.CaptureSend(c, "whisper", id, "Blocked attempt", false)
    ns.CaptureSend(c, "whisper", id, "Allowed attempt", true)
    assert(#p.history.records == 1 and p.history.records[1].disposition == "blocked-attempt")
    n.sim.now = n.sim.now + 3
    ns.FlushHistorySends(c)
    assert(#p.history.records == 2 and p.history.records[2].disposition == "attempted")
end)
test("unique echo correlates to one send without a duplicate history record", function()
    local n, p = paired()
    local c, id = n.chats.child, { character = "friend-testrealm" }
    ns.CaptureSend(c, "whisper", id, "Same message", true)
    ns.CaptureOutput(c, "whisper", id, "Same message", 1)
    ns.CaptureOutput(c, "whisper", id, "Same message", 1)
    n.sim.now = n.sim.now + 3
    ns.FlushHistorySends(c)
    assert(#p.history.records == 1 and p.history.records[1].disposition == "output")
end)
test("ambiguous or late echoes report a gap and never invent confirmed sends", function()
    local n, p = paired()
    local c = n.chats.child
    ns.CaptureSend(c, "party", nil, "Repeated text", true)
    ns.CaptureSend(c, "party", nil, "Repeated text", true)
    ns.CaptureOutput(c, "party", nil, "Repeated text", 1)
    n.sim.now = n.sim.now + 3
    ns.FlushHistorySends(c)
    ns.CaptureOutput(c, "party", nil, "Repeated text", 2)
    local attempts, gaps = 0, 0
    for _, r in ipairs(p.history.records) do
        assert(r.disposition ~= "output")
        if r.disposition == "attempted" then
            attempts = attempts + 1
        else
            gaps = gaps + 1
        end
    end
    assert(attempts == 2 and gaps == 2)
end)
test(
    "unmatched local output events are captured once as observations, not remote receipts",
    function()
        local n, p = paired()
        ns.CaptureOutput(
            n.chats.child,
            "whisper",
            { character = "friend-testrealm" },
            "Uncovered route",
            1
        )
        ns.CaptureOutput(
            n.chats.child,
            "whisper",
            { character = "friend-testrealm" },
            "Uncovered route",
            1
        )
        assert(#p.history.records == 1 and p.history.records[1].disposition == "output")
    end
)
test(
    "pending capture buffers and line caches are bounded; long messages are marked truncated",
    function()
        local n, p = paired()
        for i = 1, 1000 do
            ns.CaptureRead(n.chats.child, "party", nil, "message", true, i)
        end
        assert(#n.chats.child.captureOrder == 256)
        for _ = 1, 100 do
            ns.CaptureSend(n.chats.child, "party", nil, string.rep("z", 300), true)
        end
        assert(#n.chats.child.pendingCaptures <= 64 and #n.chats.child.recentCaptures <= 64)
        ns.FlushHistorySends(n.chats.child, true)
        local r = p.history.records[#p.history.records]
        assert(#r.text == 256 and r.truncated)
    end
)
test("count limits drop oldest records and retain monotonic sequence/loss metadata", function()
    local n, p = paired()
    assert(ns.ConfigureHistory(p, 604800, 3, n.sim.now))
    for i = 1, 8 do
        append(n, "message" .. i)
    end
    assert(#p.history.records == 3 and p.history.records[1].seq == 6)
    assert(
        p.history.high == 8 and p.history.pruned == 5 and ns.ValidHistory(p.history, p.generation)
    )
end)
test("offline retention expiry survives normalization and reports expired records", function()
    local n, p = paired()
    assert(ns.ConfigureHistory(p, 60, 100, n.sim.now))
    append(n, "old")
    n.sim.now = n.sim.now + 61
    ns.NormalizeSettings(p)
    ns.PruneHistory(p.history, n.sim.now)
    assert(#p.history.records == 0 and p.history.expired == 1 and p.history.high == 1)
end)
test("invalid limits do not modify valid retained data", function()
    local n, p = paired()
    append(n, "preserve")
    for _, spec in ipairs({ { 0, 100 }, { 2592001, 100 }, { 60, 0 }, { 60, 10001 }, { 60, 1.5 } }) do
        assert(not ns.ConfigureHistory(p, spec[1], spec[2], n.sim.now))
    end
    assert(p.history.records[1].text == "preserve" and p.history.maxRecords == 10000)
end)
test(
    "binary/control characters round trip through bounded history-only protocol extension",
    function()
        local n = paired()
        local body = "Body\nwith\tcontrols\0and |Hmarkup|h and UTF8: \195\169"
        append(n, body)
        local fields, item, wire = batch(n)
        assert(#fields > 16 and #fields <= 46 and #wire <= 2048)
        assert(ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
        local h = n.sim.endpoints.parent.profile.childProfiles.child.history
        assert(h.records[1].text == body)
        local bad = { "1", "unknown", "parent:999", "gen", "999" }
        for _ = 1, 12 do
            bad[#bad + 1] = "x"
        end
        assert(not ns.EncodeMessage(bad))
    end
)
test(
    "batch limits, cursors and complete validation prevent duplicate or malformed insertion",
    function()
        local n = paired()
        for i = 1, 8 do
            append(n, "message " .. i)
        end
        local fields, item = batch(n)
        assert((#fields - 13) / 11 <= 3)
        local last = tonumber(fields[7])
        assert(ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
        assert(not ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
        local nextFields, nextItem = batch(n, last)
        nextFields[21] = "not-hex"
        assert(not ns.AcceptHistoryBatch(n.transports.parent, "child", nextFields, nextItem))
        assert(n.sim.endpoints.parent.profile.childProfiles.child.history.cursor == last)
    end
)
test(
    "history replies must match exact child, operation, sequence and current authorization",
    function()
        local n = paired()
        append(n, "PRIVATE")
        local fields, item = batch(n)
        fields[3] = "parent:999"
        assert(not ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
        fields[3] = item.operation
        fields[5] = "999"
        assert(not ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
        fields[5] = item.sequence
        assert(not ns.AcceptHistoryBatch(n.transports.parent, "child2", fields, item))
        n.sim.endpoints.parent.profile.childProfiles.child.members.parent = nil
        assert(not ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
    end
)
test("only a current guardian can request a batch, with no content for strangers", function()
    local n, p = paired()
    append(n, "PRIVATE")
    local wire = ns.EncodeMessage({ "1", "history", "stranger:1", p.generation, "1", "0" })
    local ok, reason, reply = ns.FamilyReceive(
        n.transports.child.family,
        "stranger",
        wire,
        n.sim.now,
        { stranger = true }
    )
    assert(not ok and reason == "unauthorized" and not reply)
end)
test(
    "network catchup transfers actual records and resumes from persisted cursor after reload",
    function()
        local n, p = paired()
        for i = 1, 10 do
            append(n, "message " .. i)
        end
        local h = fetchHistory(n, 35)
        assert(h and h.cursor == p.history.high and #h.records == 10)
        local savedCursor = h.cursor
        assert(
            ns.NormalizeSettings(n.sim.endpoints.parent.profile).childProfiles.child.history.cursor
                == savedCursor
        )
        n.transports.parent = ns.NewTransport(n.transports.parent.family, n.transports.parent.io)
        append(n, "after reload")
        h = fetchHistory(n)
        assert(h.cursor == savedCursor + 1 and #h.records == 11)
    end
)
test("offline loss and duplicate fragments recover without duplicate history records", function()
    local n, p = paired()
    n.sim.endpoints.parent.online = false
    for i = 1, 7 do
        append(n, "offline " .. i)
    end
    ns.WatchHistory(n.transports.parent, "child")
    advance(n, 15)
    assert(not n.sim.endpoints.parent.profile.childProfiles.child.history)
    n.sim.endpoints.parent.online, n.sim.duplicate = true, true
    n.sim.loss = true
    advance(n, 5)
    n.sim.loss = false
    local h = fetchHistory(n, 40)
    assert(h.cursor == p.history.high and #h.records == 7)
end)
test(
    "retention truncation is visible to a guardian even when all missed records expired",
    function()
        local n, p = paired()
        ns.ConfigureHistory(p, 60, 2, n.sim.now)
        for i = 1, 5 do
            append(n, "old " .. i)
        end
        n.sim.now = n.sim.now + 61
        local h = fetchHistory(n)
        assert(h.cursor == 5 and #h.records == 0 and h.pruned == 3 and h.expired == 2)
    end
)
test("membership removal cancels queued private fragments before the next send", function()
    local n, p = paired()
    pair(n, "child", "parent2")
    ns.DashboardCommand(n.dashboards.parent, "sync child")
    advance(n)
    append(n, "PRIVATE queued history")
    local t = n.transports.child
    local item = assert(ns.TransportRequest(n.transports.parent, "child", "history", { "0" }))
    ns.TransportTick(n.transports.parent)
    -- Deliver the request directly so the private reply is queued without a send.
    local packet = table.remove(n.sim.queue, 1)
    assert(packet and ns.TransportReceive(t, packet.sender, packet.wire))
    local reply
    for _, work in ipairs(t.work) do
        if work.kind == "history-batch" then
            reply = work
        end
    end
    assert(reply and reply.state == "pending")
    local removal = assert(
        ns.FamilyRequest(
            n.transports.parent2.family,
            "child",
            p.generation,
            "remove",
            { "parent", "confirm" }
        )
    )
    assert(
        ns.FamilyReceive(t.family, "parent2", removal, n.sim.now, { parent = true, parent2 = true })
    )
    ns.TransportTick(t)
    assert(reply.state == "cancelled" and item.generation ~= p.generation)
end)
test("stop/re-pair cannot restore old history or accept an old batch", function()
    local n, p = paired()
    append(n, "old private history")
    local fields, item = batch(n)
    assert(ns.FamilyReset(n.transports.child.family, true))
    assert(#p.history.records == 0)
    pair(n, "child", "parent")
    assert(not ns.AcceptHistoryBatch(n.transports.parent, "child", fields, item))
    assert(not ns.HistoryView(p, "child", {}, n.sim.now)[1])
end)
test("policy and request traffic preempts an existing history backlog", function()
    local n = paired()
    for i = 1, 30 do
        append(n, string.rep("h", 256))
    end
    ns.WatchHistory(n.transports.parent, "child")
    ns.PollHistory(n.transports.parent)
    local edit = assert(
        ns.TransportRequest(
            n.transports.parent,
            "child",
            "policy",
            { "party", "read", "indefinite", "", "", "" }
        )
    )
    ns.TransportTick(n.transports.parent)
    local packet = n.sim.queue[#n.sim.queue]
    local operationWire = assert(ns.DecodeMessage(edit.wire))
    assert(packet.wire:find(edit.id, 1, true) and operationWire[2] == "policy")
    advance(n, 15)
    assert(edit.state == "applied")
end)
test("history queues reserve capacity for control operations", function()
    local n = paired()
    local t = n.transports.parent
    for _ = 1, 30 do
        ns.TransportRequest(t, "child", "history", { "0" })
    end
    local active = 0
    for _, item in ipairs(t.work) do
        if item.kind == "history" and item.state == "pending" then
            active = active + 1
        end
    end
    assert(active <= 16)
    assert(ns.TransportRequest(t, "child", "policy", { "party", "read", "revoke", "", "", "" }))
end)
test(
    "guardian viewer filters channel, time, identity, direction and disposition chronologically",
    function()
        local n = paired()
        append(n, "old", "party", "allowed", n.sim.now - 4000)
        append(n, "blocked", "whisper", "blocked", n.sim.now, "read", "stranger-testrealm")
        append(n, "attempt", "party", "attempted", n.sim.now - 10, "send")
        fetchHistory(n)
        local p = n.sim.endpoints.parent.profile
        local all = ns.HistoryView(p, "child", {}, n.sim.now)
        assert(#all == 3 and all[1].text == "blocked" and all[3].text == "old")
        assert(#ns.HistoryView(p, "child", { channel = "party", seconds = 3600 }, n.sim.now) == 1)
        assert(
            #ns.HistoryView(
                    p,
                    "child",
                    { identity = "STRANGER", disposition = "blocked", direction = "read" },
                    n.sim.now
                ) == 1
        )
        assert(
            #ns.HistoryView(
                    p,
                    "child",
                    { from = n.sim.now - 100, to = n.sim.now - 60 },
                    n.sim.now
                ) == 0
        )
    end
)
test("child and debug views never expose retained blocked text", function()
    local n, p = paired()
    append(n, "NEVER-CHILD-OR-DEBUG")
    assert(#ns.HistoryView(p, "child", {}, n.sim.now) == 0)
    assert(not ns.DashboardText(n.dashboards.child):find("NEVER-CHILD-OR-DEBUG", 1, true))
    fetchHistory(n)
    assert(not ns.DashboardText(n.dashboards.parent):find("NEVER-CHILD-OR-DEBUG", 1, true))
end)
test(
    "monitoring records restricted and unavailable intervals without any inaccessible value",
    function()
        local n, p = paired()
        local c = n.chats.child
        p.history.lastSeen, c.captureStarted = math.floor(n.sim.now - 100), false
        ns.HistoryHeartbeat(c, true)
        n.sim.now = n.sim.now + 5
        ns.HistoryHeartbeat(c, false)
        local records = p.history.records
        assert(#records == 3 and records[1].disposition == "gap")
        assert(records[3].endedAt > records[3].time)
    end
)
test("unpaired and inactive chat models cannot record private data", function()
    local n, p = paired()
    n.chats.child.monitoring = false
    ns.CaptureRead(n.chats.child, "whisper", nil, "inactive", false, 1)
    assert(#p.history.records == 0)
    n.chats.child.monitoring = true
    assert(ns.FamilyReset(n.transports.child.family, true))
    ns.CaptureRead(n.chats.child, "whisper", nil, "unpaired", true, 2)
    ns.CaptureSend(n.chats.child, "whisper", nil, "unpaired", true)
    assert(#p.history.records == 0)
end)
test("authorized history settings apply with a deadline and prune bounded source state", function()
    local n, p = paired()
    for i = 1, 5 do
        append(n, "message" .. i)
    end
    local item = assert(
        ns.TransportRequest(n.transports.parent, "child", "history-config", { "86400", "2" })
    )
    advance(n)
    assert(
        item.state == "applied"
            and p.history.retention == 86400
            and #p.history.records == 2
            and p.history.pruned == 3
    )
end)
test("Activity is a guardian-only browser while Connection keeps diagnostics", function()
    local n, p = paired()
    append(n, "HIDDEN-BODY-ONLY-FOR-GUARDIAN", "whisper", "blocked")
    fetchHistory(n)
    withWidgets(function(ui)
        local child = n.dashboards.child
        ns.ShowDashboard(child)
        for _, w in ipairs(ui.frames) do
            assert(not tostring(w.value):find("HIDDEN-BODY-ONLY-FOR-GUARDIAN", 1, true))
            if w.kind == "Button" and w.value == "Activity" then
                assert(not ui.visible(w))
            end
        end
        assert(child.chat.monitoring and p.supervision == "paired")
        child.window:Hide()
        ns.ShowDashboard(n.dashboards.parent)
        ui.click("Activity")
        local seen = false
        for _, w in ipairs(ui.frames) do
            if
                ui.visible(w) and tostring(w.value):find("HIDDEN-BODY-ONLY-FOR-GUARDIAN", 1, true)
            then
                seen = true
            end
        end
        assert(seen and ui.find("Connection"))
        ui.click("All channels")
        ui.fill(18, 64, "different-person")
        ui.tick(0.6)
        for _, w in ipairs(ui.frames) do
            if ui.visible(w) then
                assert(not tostring(w.value):find("HIDDEN-BODY-ONLY-FOR-GUARDIAN", 1, true))
            end
        end
        ui.click("Connection")
        for _, w in ipairs(ui.frames) do
            if ui.visible(w) then
                assert(not tostring(w.value):find("HIDDEN-BODY-ONLY-FOR-GUARDIAN", 1, true))
            end
        end
    end)
end)
test("Activity switches between children without leaking rows and pages older history", function()
    local n = paired()
    pair(n, "child2", "parent")
    for i = 1, 24 do
        append(n, "child-one-" .. i)
    end
    fetchHistory(n, 60)
    withWidgets(function(ui)
        local d = n.dashboards.parent
        d.selectedChild = "child"
        ns.ShowDashboard(d)
        ui.click("Activity")
        ui.click("Older")
        d.selectedChild = "child2"
        ui.tick(0.6)
        for _, w in ipairs(ui.frames) do
            if ui.visible(w) then
                assert(not tostring(w.value):find("child-one-", 1, true))
            end
        end
    end)
end)
test("synthetic sample injection shares production history and cannot access live state", function()
    local n, p = paired()
    ns.SimHistorySamples(n, "child")
    local h = fetchHistory(n)
    assert(h.cursor == p.history.high and #h.records >= 5)
    assert(not ns.settings)
end)
local function withClientMocks(body)
    local n, p = paired()
    local now, locked, sent = n.sim.now, false, 0
    local secret = setmetatable({}, {
        __tostring = function()
            error("secret serialized")
        end,
        __eq = function()
            error("secret compared")
        end,
        __index = function()
            error("secret indexed")
        end,
        __concat = function()
            error("secret concatenated")
        end,
    })
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end
    function frame:SetScript(script, callback)
        self.scripts[script] = callback
    end
    local filters = {}
    local original = function()
        sent = sent + 1
        return "send-result"
    end
    local chatInfo = {
        SendChatMessage = original,
        InChatMessagingLockdown = function()
            return locked
        end,
    }
    local mocks = {
        canaccessvalue = function(v)
            return not rawequal(v, secret)
        end,
        GetServerTime = function()
            return now
        end,
        GetNormalizedRealmName = function()
            return "Test Realm"
        end,
        CreateFrame = function(kind)
            assert(kind == "Frame")
            return frame
        end,
        C_ChatInfo = chatInfo,
        ChatFrameUtil = {
            AddMessageEventFilter = function(e, f)
                assert(not filters[e])
                filters[e] = f
            end,
            RemoveMessageEventFilter = function(e, f)
                assert(filters[e] == f)
                filters[e] = nil
            end,
        },
    }
    for k, v in pairs(mocks) do
        rawset(env, k, v)
    end
    local io = {
        account = function()
            return nil
        end,
        freshSession = function()
            return "runtime:new"
        end,
        selfCharacter = function()
            return "child-testrealm"
        end,
    }
    local adapter = assert(ns.NewWoWChat(p, io, true))
    p.history = ns.NewHistory(p.generation)
    local ctx = {
        profile = p,
        adapter = adapter,
        frame = frame,
        io = io,
        secret = secret,
        send = function(...)
            return chatInfo.SendChatMessage(...)
        end,
        sent = function()
            return sent
        end,
        incoming = function(event, sender, text, line)
            return filters[event]({}, event, text, sender, "", "", "", "", 0, 0, "", 0, line)
        end,
        output = function(sender, text, line)
            frame.scripts.OnEvent(
                frame,
                "CHAT_MSG_WHISPER_INFORM",
                text,
                sender,
                "",
                "",
                "",
                "",
                0,
                0,
                "",
                0,
                line
            )
        end,
        tick = function(seconds, restriction)
            now = now + seconds
            locked = restriction
            frame.scripts.OnUpdate(frame, seconds)
        end,
    }
    local ok, reason = pcall(body, ctx)
    adapter.stop()
    assert(not frame.scripts.OnUpdate and chatInfo.SendChatMessage == original)
    for k in pairs(mocks) do
        rawset(env, k, nil)
    end
    assert(ok, reason)
end

test(
    "candidate filters capture accessible blocked text once without leaking into child diagnostics",
    function()
        withClientMocks(function(c)
            assert(c.incoming("CHAT_MSG_WHISPER", "Stranger", "BOUNDARY-PRIVATE-BODY", 1))
            assert(c.incoming("CHAT_MSG_WHISPER", "Stranger", "BOUNDARY-PRIVATE-BODY", 1))
            assert(#c.profile.history.records == 1)
            assert(c.profile.history.records[1].text == "BOUNDARY-PRIVATE-BODY")
            assert(
                not ns.DashboardText(ns.NewDashboard(c.profile))
                    :find("BOUNDARY-PRIVATE-BODY", 1, true)
            )
            for _, message in ipairs(output) do
                assert(not message:find("BOUNDARY-PRIVATE-BODY", 1, true))
            end
        end)
    end
)
test(
    "candidate pre-send capture and whisper output share one record and preserve return values",
    function()
        withClientMocks(function(c)
            c.profile.policy.whispers.friend =
                { mode = "indefinite", kind = "character", target = "friend-testrealm" }
            assert(c.send("one send", "WHISPER", nil, "Friend") == "send-result")
            c.output("Friend", "one send", 1)
            c.output("Friend", "one send", 1)
            c.tick(3, false)
            assert(c.sent() == 1 and #c.profile.history.records == 1)
            assert(c.profile.history.records[1].disposition == "output")
        end)
    end
)
test(
    "candidate party self echo is outgoing output even when incoming party permission is closed",
    function()
        withClientMocks(function(c)
            c.profile.policy.channels.party = { send = { mode = "indefinite" } }
            c.send("party send", "PARTY")
            assert(c.incoming("CHAT_MSG_PARTY", "Child-TestRealm", "party send", 1))
            assert(
                #c.profile.history.records == 1
                    and c.profile.history.records[1].disposition == "output"
            )
            assert(c.profile.history.records[1].direction == "send")
            assert(c.incoming("CHAT_MSG_PARTY_LEADER", "Friend-TestRealm", "their party line", 2))
            assert(
                c.profile.history.records[2].direction == "read"
                    and c.profile.history.records[2].disposition == "blocked"
            )
        end)
    end
)
test(
    "secret text, identities and line IDs never enter capture serialization or comparison",
    function()
        withClientMocks(function(c)
            c.incoming("CHAT_MSG_WHISPER", c.secret, c.secret, 1)
            c.incoming("CHAT_MSG_WHISPER", c.secret, c.secret, c.secret)
            c.send(c.secret, "WHISPER", nil, c.secret)
            c.output(c.secret, c.secret, 2)
            c.tick(3, c.secret)
            for _, r in ipairs(c.profile.history.records) do
                assert(
                    r.disposition == "gap"
                        and type(r.text) == "string"
                        and r.character == ""
                        and r.account == ""
                )
            end
            assert(ns.ValidHistory(c.profile.history, c.profile.generation))
        end)
    end
)
test("party capture with unresolved local identity reports its exact coverage gap", function()
    withClientMocks(function(c)
        c.io.selfCharacter = nil
        c.incoming("CHAT_MSG_PARTY", "Friend-TestRealm", "must not misclassify as incoming", 1)
        assert(
            #c.profile.history.records == 1 and c.profile.history.records[1].disposition == "gap"
        )
        assert(c.profile.history.records[1].text:find("local/sender identity", 1, true))
    end)
end)
test(
    "default count and retention settings stay bounded at the proposed release defaults",
    function()
        local n, p = paired()
        assert(p.history.maxRecords == 10000 and p.history.retention == 604800)
        for i = 1, 10001 do
            append(n, "record " .. i)
        end
        assert(
            #p.history.records == 10000 and p.history.pruned == 1 and p.history.records[1].seq == 2
        )
        assert(ns.ValidHistory(p.history, p.generation))
    end
)

test(
    "offline profile maintenance prunes source and guardian caches without opening a viewer",
    function()
        local n, p = paired()
        ns.ConfigureHistory(p, 60, 100, n.sim.now)
        append(n, "expires")
        local h = fetchHistory(n)
        assert(#h.records == 1)
        n.sim.now = n.sim.now + 61
        ns.PruneProfileHistory(p, n.sim.now)
        ns.PruneProfileHistory(n.sim.endpoints.parent.profile, n.sim.now)
        assert(#p.history.records == 0 and #h.records == 0)
        assert(p.history.expired == 1 and h.cacheRemoved == 1)
    end
)
test(
    "long monitoring intervals overlap time filters and do not delete newer retained chat",
    function()
        local n, p = paired()
        ns.ConfigureHistory(p, 60, 100, n.sim.now)
        append(n, "fresh")
        ns.HistoryGap(n.chats.child, "Long outage ended now.", n.sim.now - 1000)
        assert(#p.history.records == 2)
        fetchHistory(n)
        local rows =
            ns.HistoryView(n.sim.endpoints.parent.profile, "child", { seconds = 60 }, n.sim.now)
        assert(#rows == 2)
    end
)
test(
    "revocation after the first private fragment cancels the remainder and leaves no completed batch",
    function()
        local n, p = paired()
        pair(n, "child", "parent2")
        ns.DashboardCommand(n.dashboards.parent, "sync child")
        advance(n)
        append(n, string.rep("P", 256))
        local guardian, child = n.transports.parent, n.transports.child
        assert(ns.TransportRequest(guardian, "child", "history", { "0" }))
        ns.TransportTick(guardian)
        local packet = table.remove(n.sim.queue, 1)
        assert(packet and ns.TransportReceive(child, packet.sender, packet.wire))
        local reply
        for _, item in ipairs(child.work) do
            if item.kind == "history-batch" then
                reply = item
            end
        end
        assert(reply)
        local first = false
        for _ = 1, 40 do
            n.sim.now = n.sim.now + 0.2
            ns.TransportTick(child)
            while #n.sim.queue > 0 do
                local part = table.remove(n.sim.queue, 1)
                ns.TransportReceive(guardian, part.sender, part.wire)
                if part.wire:find("F|" .. reply.id .. "|1|", 1, true) then
                    first = true
                end
            end
            if first then
                break
            end
        end
        assert(first and guardian.incoming["child/" .. reply.id])
        local removal = assert(
            ns.FamilyRequest(
                n.transports.parent2.family,
                "child",
                p.generation,
                "remove",
                { "parent", "confirm" }
            )
        )
        assert(
            ns.FamilyReceive(
                child.family,
                "parent2",
                removal,
                n.sim.now,
                { parent = true, parent2 = true }
            )
        )
        ns.TransportTick(child)
        assert(reply.state == "cancelled")
        assert(not guardian.family.profile.childProfiles.child.history)
        n.sim.now = n.sim.now + 16
        ns.TransportTick(guardian)
        assert(not guardian.incoming["child/" .. reply.id])
    end
)
test(
    "policy application acknowledgements preempt private response fragments at the source",
    function()
        local n = paired()
        append(n, string.rep("H", 256))
        local guardian, child = n.transports.parent, n.transports.child
        assert(ns.TransportRequest(guardian, "child", "history", { "0" }))
        ns.TransportTick(guardian)
        local packet = table.remove(n.sim.queue, 1)
        assert(ns.TransportReceive(child, packet.sender, packet.wire))
        local reply
        for _, item in ipairs(child.work) do
            if item.kind == "history-batch" then
                reply = item
            end
        end
        assert(reply)
        local policy = assert(
            ns.TransportRequest(
                guardian,
                "child",
                "policy",
                { "party", "read", "revoke", "", "", "" }
            )
        )
        n.sim.now = n.sim.now + 0.2
        ns.TransportTick(guardian)
        packet = table.remove(n.sim.queue, 1)
        assert(packet.wire:find(policy.id, 1, true))
        assert(ns.TransportReceive(child, packet.sender, packet.wire))
        ns.TransportTick(child)
        local nextPacket = table.remove(n.sim.queue, 1)
        assert(nextPacket.wire == "D|" .. policy.id and reply.cursor == 1)
    end
)
test(
    "normal logout flushes pending attempts before persistence and reports a monitoring pause",
    function()
        withClientMocks(function(c)
            c.profile.policy.channels.party = { send = { mode = "indefinite" } }
            c.send("last outgoing before logout", "PARTY")
            assert(#c.profile.history.records == 0)
            c.frame.scripts.OnEvent(c.frame, "PLAYER_LOGOUT")
            assert(c.profile.history.records[1].disposition == "attempted")
            assert(c.profile.history.records[1].text == "last outgoing before logout")
            assert(c.profile.history.records[2].disposition == "gap")
        end)
    end
)
print(string.format("%d Phase 7 tests passed (Lua %s)", passed, _VERSION))
