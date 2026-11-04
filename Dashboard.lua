local _, ns = ...
---@cast ns KinwardNamespace

---@param profile KinwardSettings
---@param transport? KinwardTransport
---@param now? fun(): number
---@param chat? KinwardChat
---@return KinwardDashboard
function ns.NewDashboard(profile, transport, now, chat)
    return {
        profile = profile,
        chat = chat,
        transport = transport,
        now = now or (transport and transport.io.now) or function()
            return math.huge
        end,
        message = "Ready. Live routing and chat enforcement remain client-gated.",
    }
end

---@param d KinwardDashboard
---@param message string
---@return string
function ns.DashboardCommand(d, message)
    local w = {}
    for word in message:gmatch("%S+") do
        w[#w + 1] = word
    end
    local p, t = d.profile, d.transport
    local result =
        "Commands: role guardian|child; request-guardian NAME; accept-child CHILD; decline-child CHILD; sync CHILD; inspect CHILD CHANNEL read|send [TARGET]; allow|deny CHILD CHANNEL read|send [TARGET]; add CHILD PEER OP confirm; remove CHILD PEER confirm|stop; stop confirm"
    if w[1] == "role" then
        if
            p.supervision == "unpaired"
            and not next(p.children)
            and not next(p.guardians)
            and (w[2] == "child" or w[2] == "guardian")
        then
            p.role, result = w[2], "Role saved: " .. w[2]
        else
            result = "Role change unavailable while relationships exist."
        end
    elseif w[1] == "request-guardian" then
        result = "Verified connection required. Use the single-session demo."
        if t then
            local _, feedback = ns.RequestGuardianship(t, table.concat(w, " ", 2))
            result = feedback
        end
        d.message = result
        return result
    elseif w[1] == "accept-child" or w[1] == "decline-child" then
        result = "No current request from that child."
        local r = t and t.family.guardianInbox and t.family.guardianInbox[w[2] or ""]
        if t and r then
            local _, feedback = ns.AnswerGuardianship(t, w[2], r.token, w[1] == "accept-child")
            result = feedback
        end
        d.message = result
        return result
    elseif w[1] == "request" then
        return ns.DashboardAction(
            d,
            "request",
            { w[2] or "", w[3] or "", w[4] == "-" and "" or w[4] or "", table.concat(w, " ", 5) }
        )
    elseif w[1] == "cancel-request" then
        return ns.DashboardAction(d, "cancel-request", { w[2] or "" })
    elseif w[1] == "requests" then
        return ns.DashboardAction(d, "request-list", { w[2] or "", "1" })
    elseif w[1] == "decide" then
        local child = p.childProfiles[w[2] or ""]
        local r = child and child.requests and child.requests[w[3] or ""]
        if not r then
            d.message = "Fetch and select the exact request first."
            return d.message
        end
        return ns.DashboardAction(d, "request-decision", {
            w[2],
            r.id,
            w[4] or "",
            w[5] == "-" and "" or w[5] or "",
            w[6] == "-" and "" or w[6] or "",
            tostring(r.baseRevision),
        })
    elseif not t then
        result = "Live routing/identity gate is open. Use the staged /kinwardsim network harness. "
            .. result
    elseif w[1] == "invite" and w[2] and w[3] then
        result = ns.FamilyInvite(t.family, w[2], w[3], t.io.now())
                and "Invitation created (120 seconds). Confirm the exact peer and operation locally."
            or "Invitation rejected."
    elseif w[1] == "confirm" then
        local _, reason =
            ns.FamilyConfirm(t.family, w[2], w[3], w[4] == "confirm", t.io.now(), t.io.friends())
        result = reason
    elseif w[1] == "stop" then
        local _, reason = ns.FamilyReset(t.family, w[2] == "confirm")
        result = reason
    elseif w[2] then
        local kind, args = w[1], {}
        if kind == "pair" then
            args = { w[3] or "" }
        elseif kind == "allow" or kind == "deny" then
            args = {
                w[3] or "",
                w[4] or "",
                kind == "allow" and "indefinite" or "revoke",
                "",
                "",
                w[5] or "",
            }
            kind = "policy"
        elseif kind == "inspect" then
            args = { w[3] or "", w[4] or "", w[5] or "" }
        elseif kind == "add" then
            args = { w[3] or "", w[4] or "", w[5] or "" }
        elseif kind == "remove" then
            args = { w[3] or "", w[4] or "" }
        end
        if
            kind == "pair"
            or kind == "sync"
            or kind == "policy"
            or kind == "inspect"
            or kind == "add"
            or kind == "remove"
        then
            local item, reason = ns.TransportRequest(t, w[2], kind, args, 60)
            result = item
                    and ("Pending " .. item.operation .. "; delivery deadline " .. item.deadline)
                or reason
        end
    end
    d.message = result
    return result
end

---@param d KinwardDashboard
---@return string
function ns.DashboardText(d)
    local p, t = d.profile, d.transport
    local lines = {
        "Kinward — " .. p.role .. "; supervision: " .. p.supervision,
        t and "Connected. Saved permissions are applied by the child's addon."
            or (d.connectionStatus or "Connecting to Battle.net."),
        "Player text chat routes are monitored; inaccessible/secret content creates coverage gaps.",
        d.message,
    }
    local traffic = t and t.traffic
    if traffic then
        lines[#lines + 1] = "Network: sent "
            .. traffic.sent
            .. "; received "
            .. traffic.received
            .. "; unknown senders "
            .. traffic.unmapped
            .. "; last send result "
            .. traffic.lastSend
            .. "; last receive result "
            .. traffic.lastReceive
    end
    if t and t.family.pending then
        lines[#lines + 1] = "Pair confirmation: "
            .. t.family.pending.peer
            .. " "
            .. t.family.pending.operation
    end
    for peer in pairs(p.guardians) do
        lines[#lines + 1] = "Guardian: " .. peer
    end
    for peer in pairs(p.children) do
        local child = p.childProfiles[peer]
        local status, last = "unreachable", nil
        if t then
            status, last = ns.TransportPresence(t, peer)
        end
        lines[#lines + 1] = "Child "
            .. peer
            .. ": "
            .. status
            .. "; last contact "
            .. tostring(last or "never")
            .. "; revision "
            .. tostring(child and child.revision or "unknown")
        if child then
            for member in pairs(child.members or {}) do
                lines[#lines + 1] = "  Guardian: " .. member
            end
            for key, setting in pairs(child.settings or {}) do
                lines[#lines + 1] = "  "
                    .. key
                    .. ": "
                    .. setting.mode
                    .. "; revision "
                    .. setting.revision
            end
        end
    end
    if p.role == "child" then
        for _, channel in ipairs({ "party", "whisper" }) do
            for _, direction in ipairs({ "read", "send" }) do
                local allowed, reason = ns.Evaluate(
                    p,
                    channel,
                    direction,
                    nil,
                    { now = d.now(), sessionId = p.sessionId or "missing", accounts = {} }
                )
                lines[#lines + 1] = channel
                    .. " "
                    .. direction
                    .. ": "
                    .. tostring(allowed)
                    .. " "
                    .. reason
            end
        end
        for key, grant in pairs(p.policy.whispers) do
            local active = ns.GrantActive(
                grant,
                { now = d.now(), sessionId = p.sessionId or "missing", accounts = {} }
            )
            lines[#lines + 1] = key
                .. ": "
                .. tostring(active)
                .. " "
                .. grant.mode
                .. " (read/send)"
        end
    end
    if t then
        for i = math.max(1, #t.work - 10), #t.work do
            local item = t.work[i]
            if not item.reply then
                lines[#lines + 1] = item.peer
                    .. " "
                    .. item.operation
                    .. ": "
                    .. item.state
                    .. "; "
                    .. item.result
                    .. "; deadline "
                    .. item.deadline
                    .. "; applied order "
                    .. tostring(item.revision or "unknown")
            end
        end
    end
    return table.concat(lines, "\n")
end

-- Button actions keep input fields separate; spaces in realm names are never
-- reinterpreted as command delimiters. Destructive confirmations capture args.
---@param d KinwardDashboard
---@param kind string
---@param args string[]
---@return string
function ns.DashboardAction(d, kind, args)
    if kind == "role" then
        return ns.DashboardCommand(d, "role " .. (args[1] or ""))
    end
    local t = d.transport
    local result = "Live connection unavailable. Use the single-session demo."
    if kind == "request" then
        if not t or (args[2] ~= "read" and args[2] ~= "send") then
            result = "Verified endpoint and request scope required."
        else
            local _, reason = ns.CreateRequest(
                d.profile,
                t.family.id,
                args[1],
                args[2],
                args[3] or "",
                args[4] or "",
                d.now()
            )
            result = reason
        end
    elseif kind == "cancel-request" then
        local _, reason = ns.CancelRequest(d.profile, args[1], d.now())
        result = reason
    elseif t then
        if kind == "invite" then
            result = ns.FamilyInvite(t.family, args[1], args[2] or "", d.now())
                    and "Invitation ready for the intended guardian (120 seconds)."
                or "Invitation rejected. Check role, peer and eight-digit code."
        elseif kind == "confirm" then
            local _, reason = ns.FamilyConfirm(
                t.family,
                args[1],
                args[2],
                args[3] == "confirm",
                d.now(),
                t.io.friends()
            )
            result = reason
        elseif kind == "stop" then
            local _, reason = ns.FamilyReset(t.family, args[1] == "confirm")
            result = reason
        elseif args[1] and args[1] ~= "" then
            local values = {}
            for i = 2, #args do
                values[#values + 1] = args[i]
            end
            local item, reason = ns.TransportRequest(t, args[1], kind, values, 60)
            result = item
                    and ("Pending " .. item.operation .. "; delivery deadline " .. item.deadline)
                or reason
        else
            result = "Enter the intended peer first."
        end
    end
    local requestMessages = {
        ["queued-locally"] = "Request saved. It will be shared when a guardian connects.",
        ["already-pending"] = "That request is already waiting for a guardian.",
        ["invalid-request"] = "Check the access and target, and use a short reason without line breaks.",
        ["request-queue-full"] = "Too many pending requests. Cancel one before creating another.",
        ["supervision-required"] = "Access requests are available while supervised.",
        ["cancelled"] = "Request cancelled.",
        ["request-not-pending"] = "This request is no longer pending.",
    }
    d.message = requestMessages[result] or result
    return result
end

local channels = ns.ChannelCatalog

---@param d KinwardDashboard
---@param child? string
---@param channel string
---@param direction 'read'|'send'
---@param target? string
---@return string, number, number, number
function ns.DashboardPermission(d, child, channel, direction, target)
    local t, p = d.transport, d.profile
    target = target or ""
    if channel == "whisper-character" then
        target = ns.CharacterKey(target) or target
    end
    if t and child and p.role == "guardian" then
        local latest
        for _, item in ipairs(t.work) do
            if
                not item.reply
                and item.peer == child
                and item.kind == "policy"
                and (item.state == "pending" or item.state == "delivered")
            then
                local fields = ns.DecodeMessage(item.wire)
                local requestedTarget = fields and fields[11]
                if fields and fields[6] == "whisper-character" then
                    requestedTarget = ns.CharacterKey(requestedTarget)
                end
                if
                    fields
                    and fields[6] == channel
                    and (fields[7] == direction or channel:find("^whisper%-"))
                    and requestedTarget == target
                    and (not latest or tonumber(item.sequence) > tonumber(latest.sequence))
                then
                    latest = item
                end
            end
        end
        if latest then
            return latest.state == "delivered" and "Delivered" or "Pending", 1, 0.76, 0.25
        end
        local view = p.childProfiles[child]
        local setting = view
            and view.settings
            and view.settings[channel .. "/" .. direction .. "/" .. target]
        if not setting and view and view.settings and ns.ChannelCategory(channel) ~= channel then
            setting = view.settings[ns.ChannelCategory(channel) .. "/" .. direction .. "/"]
        end
        -- Whisper grants are bidirectional even when inspected using send.
        if not setting and view and view.settings and channel:find("^whisper%-") then
            setting = view.settings[channel .. "/read/" .. target]
                or view.settings[channel .. "/send/" .. target]
        end
        if setting then
            if setting.mode == "session" then
                return "Until logout", 0.7, 0.8, 1
            end
            if
                setting.mode == "indefinite"
                or (
                    setting.mode == "duration"
                    and setting.expiresAt
                    and setting.expiresAt > d.now()
                )
            then
                return "Allowed", 0.35, 0.9, 0.65
            end
            return "Blocked", 1, 0.5, 0.45
        end
        if
            view
            and view.settings
            and t.completedSnapshots[child] == view.generation .. "/" .. tostring(view.revision)
        then
            return "Blocked", 1, 0.5, 0.45
        end
        return "Unknown", 0.7, 0.75, 0.8
    end
    if p.role == "child" then
        local context = { now = d.now(), sessionId = p.sessionId or "missing", accounts = {} }
        local allowed
        if channel:find("^whisper%-") then
            local grant = p.policy.whispers[channel .. ":" .. target]
            allowed = p.supervision == "unpaired"
                or (p.supervision == "paired" and ns.GrantActive(grant, context))
        else
            allowed = ns.Evaluate(p, channel, direction, nil, context)
        end
        if allowed then
            return "Allowed", 0.35, 0.9, 0.65
        end
        return "Blocked", 1, 0.5, 0.45
    end
    return "Unknown", 0.7, 0.75, 0.8
end

local function plain(value)
    return tostring(value):gsub("|", "||")
end

-- Lazy construction keeps widgets out of loading/SavedVariables setup. One
-- window is retained per model; hidden frames do not run OnUpdate in WoW.
---@param d KinwardDashboard
---@param section? string
function ns.ShowDashboard(d, section)
    if d.window then
        if section and d.focusSection then
            d.focusSection(section)
        end
        d.window:Show()
        return
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    d.window = frame
    frame:SetSize(960, 730)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    local function background(parent, r, g, b)
        local texture = parent:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetColorTexture(r, g, b, 0.98)
    end
    local function label(parent, x, y, width, value, font)
        local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        text:SetPoint("TOPLEFT", x, -y)
        text:SetWidth(width)
        text:SetJustifyH("LEFT")
        text:SetText(plain(value))
        return text
    end
    local refresh = function() end
    local function button(parent, x, y, width, caption, callback)
        local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        control:SetSize(width, 24)
        control:SetPoint("TOPLEFT", x, -y)
        control:SetText(plain(caption))
        control:SetScript("OnClick", function()
            callback()
            refresh()
        end)
        return control
    end
    local function input(parent, x, y, width)
        local control = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        control:SetSize(width, 26)
        control:SetPoint("TOPLEFT", x, -y)
        control:SetAutoFocus(false)
        control:SetMaxLetters(128)
        control:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        control:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            refresh()
        end)
        control:SetScript("OnTextChanged", function()
            refresh()
        end)
        return control
    end
    local function panel(x, y, width, height)
        local child = CreateFrame("Frame", nil, frame)
        child:SetPoint("TOPLEFT", x, -y)
        child:SetSize(width, height)
        background(child, 0.055, 0.075, 0.105)
        return child
    end
    background(frame, 0.025, 0.035, 0.055)
    label(frame, 20, 18, 150, "KINWARD", "GameFontNormal")
    local identity = label(frame, 180, 18, 650, "")
    button(frame, 866, 12, 74, "Close", function()
        frame:Hide()
    end)
    local banner = label(frame, 20, 48, 920, "", "GameFontHighlightSmall")
    local roleGuardian = button(frame, 20, 82, 145, "Guardian role", function()
        ns.DashboardAction(d, "role", { "guardian" })
    end)
    local roleChild = button(frame, 174, 82, 125, "Child role", function()
        ns.DashboardAction(d, "role", { "child" })
    end)
    local syncSelected = button(frame, 320, 82, 170, "Sync selected child", function()
        ns.DashboardAction(d, "sync", { d.selectedChild or "" })
    end)
    local demo = button(frame, 720, 82, 220, "Single-session demo", function()
        frame:Hide()
        if ns.ShowNetworkDemo then
            ns.ShowNetworkDemo()
        end
    end)
    local sidebar = panel(16, 124, 192, 488)
    label(sidebar, 12, 12, 170, "CHILDREN", "GameFontNormal")
    local empty = label(
        sidebar,
        12,
        46,
        170,
        "No children paired yet.\nOpen Family to pair a child.",
        "GameFontHighlightSmall"
    )
    local childButtons = {}
    for i = 1, 16 do
        local row = { peer = "" }
        row.control = button(sidebar, 8, 40 + (i - 1) * 27, 176, "", function()
            d.selectedChild = row.peer
        end)
        childButtons[i] = row
    end
    local tab = section
        or (d.profile.role == "guardian" and next(d.profile.children) and "permissions" or "family")
    local pendingAction
    local function confirmAction(caption, kind, args)
        local child = (kind == "add" or kind == "remove") and d.profile.childProfiles[args[1]]
        pendingAction = {
            caption = caption,
            kind = kind,
            args = args,
            generation = child and child.generation or d.profile.generation,
        }
    end
    local tabs = {}
    for i, spec in ipairs({
        { "permissions", "Permissions" },
        { "family", "Family & pairing" },
        { "requests", "Requests" },
        { "activity", "Activity" },
        { "connection", "Connection" },
    }) do
        local key = spec[1]
        tabs[key] = button(frame, 224 + (i - 1) * 144, 124, 136, spec[2], function()
            tab = key
        end)
    end
    local permissions, family, connection, requests, activity =
        panel(224, 162, 716, 450),
        panel(224, 162, 716, 450),
        panel(224, 162, 716, 450),
        panel(224, 162, 716, 450),
        panel(224, 162, 716, 450)
    local selection = label(permissions, 14, 12, 680, "", "GameFontNormal")
    local permissionUI =
        { section = "channels", page = 1, contacts = {}, peer = "", generation = "" }
    permissionUI.channels = CreateFrame("Frame", nil, permissions)
    permissionUI.channels:SetPoint("TOPLEFT", 0, -76)
    permissionUI.channels:SetSize(716, 370)
    permissionUI.whispers = CreateFrame("Frame", nil, permissions)
    permissionUI.whispers:SetPoint("TOPLEFT", 0, -76)
    permissionUI.whispers:SetSize(716, 370)
    permissionUI.channelTab = button(permissions, 14, 40, 160, "Chat channels", function()
        permissionUI.section = "channels"
    end)
    permissionUI.whisperTab = button(permissions, 184, 40, 190, "Whisper contacts", function()
        permissionUI.section = "whispers"
    end)
    label(permissionUI.channels, 150, 0, 190, "READ incoming", "GameFontHighlightSmall")
    label(permissionUI.channels, 410, 0, 260, "SEND outgoing", "GameFontHighlightSmall")
    permissionUI.scroll =
        CreateFrame("ScrollFrame", nil, permissionUI.channels, "UIPanelScrollFrameTemplate")
    permissionUI.scroll:SetPoint("TOPLEFT", 0, -26)
    permissionUI.scroll:SetSize(682, 286)
    permissionUI.body = CreateFrame("Frame", nil, permissionUI.scroll)
    permissionUI.body:SetSize(674, #channels * 40)
    permissionUI.scroll:SetScrollChild(permissionUI.body)
    local rows = {}
    for i = 1, 64 do
        local y = (i - 1) * 40
        local caption = label(permissionUI.body, 14, y + 5, 130, "")
        for j, direction in ipairs({ "read", "send" }) do
            local x = 150 + (j - 1) * 260
            local row = { channel = "", direction = direction, caption = caption, buttons = {} }
            row.state = label(permissionUI.body, x, y + 5, 85, "Unknown", "GameFontHighlightSmall")
            for k, verb in ipairs({ "Allow", "Block" }) do
                local mode = k == 1 and "indefinite" or "revoke"
                row.buttons[k] = button(
                    permissionUI.body,
                    x + 88 + (k - 1) * 59,
                    y,
                    56,
                    verb,
                    function()
                        ns.DashboardAction(
                            d,
                            "policy",
                            { d.selectedChild or "", row.channel, direction, mode, "", "", "" }
                        )
                    end
                )
            end
            rows[#rows + 1] = row
        end
    end
    label(permissionUI.channels, 14, 323, 300, "Named custom channel", "GameFontHighlightSmall")
    permissionUI.customTarget = input(permissionUI.channels, 18, 340, 300)
    permissionUI.customTarget:SetMaxLetters(48)
    permissionUI.customState =
        label(permissionUI.channels, 334, 323, 360, "", "GameFontHighlightSmall")
    permissionUI.customButtons = {}
    for i, spec in ipairs({
        { "Allow read", "read", "indefinite" },
        { "Block read", "read", "revoke" },
        { "Allow send", "send", "indefinite" },
        { "Block send", "send", "revoke" },
    }) do
        permissionUI.customButtons[i] = button(
            permissionUI.channels,
            334 + (i - 1) * 92,
            340,
            88,
            spec[1],
            function()
                local channel = ns.CustomChannelKey(permissionUI.customTarget:GetText())
                if channel then
                    ns.DashboardAction(
                        d,
                        "policy",
                        { d.selectedChild or "", channel, spec[2], spec[3], "", "", "" }
                    )
                end
            end
        )
    end
    label(
        permissionUI.whispers,
        14,
        226,
        680,
        "WHISPERS · permission applies to both read and send",
        "GameFontNormal"
    )
    label(
        permissionUI.whispers,
        14,
        253,
        260,
        "Character-Realm or verified BattleTag",
        "GameFontHighlightSmall"
    )
    local whisperTarget = input(permissionUI.whispers, 18, 275, 245)
    local whisperKind = "whisper-character"
    local characterButton = button(permissionUI.whispers, 280, 276, 100, "Character", function()
        whisperKind = "whisper-character"
    end)
    local accountButton = button(permissionUI.whispers, 386, 276, 100, "Account", function()
        whisperKind = "whisper-account"
    end)
    local whisperButtons = {}
    for i, verb in ipairs({ "Allow", "Block" }) do
        local mode = i == 1 and "indefinite" or "revoke"
        whisperButtons[i] = button(
            permissionUI.whispers,
            506 + (i - 1) * 90,
            276,
            84,
            verb,
            function()
                ns.DashboardAction(d, "policy", {
                    d.selectedChild or "",
                    whisperKind,
                    "read",
                    mode,
                    "",
                    "",
                    whisperTarget:GetText(),
                })
            end
        )
    end
    local whisperState = label(
        permissionUI.whispers,
        14,
        316,
        680,
        "Enter a whisper target.",
        "GameFontHighlightSmall"
    )
    label(
        permissionUI.whispers,
        14,
        344,
        680,
        "Current guardians always have whisper access through their verified account.",
        "GameFontHighlightSmall"
    )
    permissionUI.summary = label(permissionUI.whispers, 14, 0, 680, "", "GameFontHighlightSmall")
    permissionUI.contactRows = {}
    for i = 1, 5 do
        local row = { channel = "", target = "" }
        row.control = button(permissionUI.whispers, 14, 28 + (i - 1) * 30, 680, "", function()
            whisperKind = row.channel
            whisperTarget:SetText(row.target)
        end)
        permissionUI.contactRows[i] = row
    end
    permissionUI.previous = button(
        permissionUI.whispers,
        14,
        184,
        110,
        "Previous contacts",
        function()
            permissionUI.page = math.max(1, permissionUI.page - 1)
        end
    )
    permissionUI.next = button(permissionUI.whispers, 134, 184, 110, "Next contacts", function()
        permissionUI.page = permissionUI.page + 1
    end)
    button(permissionUI.whispers, 514, 184, 180, "Add whisper contact", function()
        whisperTarget:SetText("")
    end)
    local refreshPairing = ns.NewPairingPanel(
        d,
        family,
        { button = button, input = input, label = label },
        confirmAction
    )
    local pairingNotice = button(frame, 500, 82, 210, "Guardianship requests", function()
        tab = "family"
    end)
    label(family, 14, 245, 680, "CURRENT GUARDIANS", "GameFontNormal")
    local memberRows = {}
    for i = 1, 8 do
        local row = { peer = "" }
        row.text = label(family, 14, 272 + (i - 1) * 19, 520, "", "GameFontHighlightSmall")
        row.remove = button(family, 560, 267 + (i - 1) * 20, 140, "Remove guardian", function()
            local child = d.profile.childProfiles[d.selectedChild or ""]
            local count = 0
            for _ in pairs(child and child.members or {}) do
                count = count + 1
            end
            local last = count == 1
            confirmAction(
                (last and "Stop supervision of " or "Remove " .. row.peer .. " from ")
                    .. (d.selectedChild or "no child")
                    .. "?",
                "remove",
                { d.selectedChild or "", row.peer, last and "stop" or "confirm" }
            )
        end)
        memberRows[i] = row
    end
    local stopButton = button(family, 14, 420, 240, "Stop supervision / recover", function()
        confirmAction(
            "Stop supervision locally and clear guardians and permissions?",
            "stop",
            { "confirm" }
        )
    end)
    local scroll = CreateFrame("ScrollFrame", nil, connection, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -14)
    scroll:SetSize(666, 422)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(656, 422)
    scroll:SetScrollChild(body)
    local connectionText = label(body, 0, 0, 646, "", "GameFontHighlightSmall")
    local refreshActivity =
        ns.NewActivityPanel(d, activity, { button = button, input = input, label = label })
    local requestIndex, selectedRequest, requestChild = 1, nil, nil
    local requestGeneration
    local requestDetails = label(requests, 14, 46, 680, "", "GameFontHighlightSmall")
    label(requests, 14, 14, 680, "ACCESS REQUESTS", "GameFontNormal")
    button(requests, 14, 190, 110, "Previous", function()
        requestIndex = math.max(1, requestIndex - 1)
    end)
    button(requests, 132, 190, 110, "Next", function()
        requestIndex = requestIndex + 1
    end)
    local fetchRequests = button(requests, 250, 190, 150, "Refresh requests", function()
        ns.DashboardAction(d, "request-list", { d.selectedChild or "", "1" })
    end)
    local promptSetting = button(requests, 408, 190, 288, "Stranger prompts: unknown", function()
        local view = d.profile.childProfiles[d.selectedChild or ""]
        if view and view.requestPrompts ~= nil then
            ns.DashboardAction(
                d,
                "request-prompts",
                { d.selectedChild, tostring(not view.requestPrompts) }
            )
        end
    end)
    local decisionButtons = {}
    for i, spec in ipairs({
        { "Approve indefinitely", "indefinite", "" },
        { "Until logout", "session", "" },
        { "15 minutes", "duration", "900" },
        { "45 minutes", "duration", "2700" },
        { "Deny", "", "" },
    }) do
        decisionButtons[i] = button(requests, 14 + (i - 1) * 138, 224, 132, spec[1], function()
            if selectedRequest and requestChild then
                -- Bind exact request, child, revision and relationship shown on this row.
                local view = d.profile.childProfiles[requestChild]
                if view and view.generation == requestGeneration then
                    ns.DashboardAction(d, "request-decision", {
                        requestChild,
                        selectedRequest.id,
                        i == 5 and "deny" or "approve",
                        spec[2],
                        spec[3],
                        tostring(selectedRequest.baseRevision),
                    })
                end
            end
        end)
    end
    local requestTiming = label(
        requests,
        14,
        256,
        680,
        "Durations start on child application. Delivery deadline: 60 seconds.\nApproval takes effect only after the child applies it; expired/changed requests are rejected.",
        "GameFontHighlightSmall"
    )
    local childForm = CreateFrame("Frame", nil, requests)
    childForm:SetPoint("TOPLEFT", 0, -224)
    childForm:SetSize(716, 220)
    label(
        childForm,
        14,
        4,
        680,
        "Choose access and enter a character-realm or BattleTag for whispers",
        "GameFontHighlightSmall"
    )
    local requestScopes = {
        { "party", "Party" },
        { "whisper-character", "Whisper character" },
        { "whisper-account", "Battle.net friend" },
        { "say", "Say" },
        { "yell", "Yell" },
        { "guild", "Guild" },
        { "raid", "Raid" },
        { "instance", "Instance" },
    }
    local requestScope = 1
    local scopeButton
    scopeButton = button(childForm, 14, 26, 240, "Access: Party", function()
        requestScope = requestScope % #requestScopes + 1
        scopeButton:SetText("Access: " .. requestScopes[requestScope][2])
    end)
    local requestTarget = input(childForm, 274, 26, 420)
    local requestDirection = "read"
    local directionButton
    directionButton = button(childForm, 14, 64, 160, "Direction: read", function()
        requestDirection = requestDirection == "read" and "send" or "read"
        directionButton:SetText("Direction: " .. requestDirection)
    end)
    label(
        childForm,
        186,
        70,
        500,
        "Whisper permission always covers read and send.",
        "GameFontHighlightSmall"
    )
    label(
        childForm,
        14,
        98,
        680,
        "Optional short reason; queued locally for up to 24 hours",
        "GameFontHighlightSmall"
    )
    local requestReason = input(childForm, 18, 120, 676)
    requestReason:SetMaxLetters(160)
    local createRequest = button(childForm, 14, 160, 190, "Send access request", function()
        ns.DashboardAction(d, "request", {
            requestScopes[requestScope][1],
            requestDirection,
            requestTarget:GetText(),
            requestReason:GetText(),
        })
    end)
    local cancelRequest = button(childForm, 214, 160, 190, "Cancel selected request", function()
        if selectedRequest then
            ns.DashboardAction(d, "cancel-request", { selectedRequest.id })
        end
    end)
    local whisperPrompt = label(frame, 224, 695, 510, "", "GameFontHighlightSmall")
    local promptRequest = button(frame, 744, 688, 196, "Request whisper access", function()
        local prompt = d.chat and d.chat.prompt
        if
            prompt
            and prompt.expires > d.now()
            and prompt.generation == d.profile.generation
            and d.profile.requestPrompts ~= false
        then
            ns.DashboardAction(d, "request", { "whisper-character", "read", prompt.character, "" })
            if d.chat then
                d.chat.prompt = nil
            end
            tab = "requests"
        end
    end)
    local confirmation = label(frame, 20, 627, 640, "", "GameFontNormal")
    local confirmButton = button(frame, 688, 621, 120, "Confirm action", function()
        local action = pendingAction
        pendingAction = nil
        if action then
            local child = (action.kind == "add" or action.kind == "remove")
                and d.profile.childProfiles[action.args[1]]
            local generation = child and child.generation or d.profile.generation
            if generation ~= action.generation then
                d.message =
                    "Family membership changed. Review the current family and confirm again."
            else
                ns.DashboardAction(d, action.kind, action.args)
            end
        end
    end)
    local cancelButton = button(frame, 818, 621, 120, "Cancel", function()
        pendingAction = nil
    end)
    local message = label(frame, 20, 664, 920, "", "GameFontHighlightSmall")
    local demoButtons = {}
    if d.demo then
        for i, id in ipairs({ "parent", "child", "parent2", "child2" }) do
            demoButtons[i] = button(frame, 20 + (i - 1) * 112, 621, 106, id, function()
                frame:Hide()
                ns.ShowDashboard(d.demo.dashboards[id])
            end)
        end
        demoButtons[5] = button(frame, 478, 621, 150, "Toggle child link", function()
            local endpoint = d.demo.sim.endpoints[d.selectedChild or "child"]
            if endpoint then
                endpoint.online = not endpoint.online
            end
        end)
        demoButtons[6] = button(frame, 638, 621, 145, "Toggle packet loss", function()
            d.demo.sim.loss = not d.demo.sim.loss
        end)
        demoButtons[7] = button(frame, 794, 621, 145, "Advance 65 sec", function()
            ns.NetworkAdvance(d.demo, 65)
        end)
    end
    refresh = function()
        local p, t = d.profile, d.transport
        local children = {}
        for child in pairs(p.children) do
            children[#children + 1] = child
        end
        table.sort(children)
        if d.selectedChild and not p.children[d.selectedChild] then
            d.selectedChild = nil
        end
        if not d.selectedChild then
            d.selectedChild = children[1]
        end
        local view = d.selectedChild and p.childProfiles[d.selectedChild]
        local canEdit = t ~= nil
            and p.role == "guardian"
            and view ~= nil
            and view.members ~= nil
            and view.members[t.family.id] == true
        local mutableRole = p.supervision == "unpaired"
            and not next(p.children)
            and not next(p.guardians)
        identity:SetText(
            plain(
                (d.demo and "SIMULATION · " .. (t and t.family.id or "") .. " · " or "")
                    .. p.role
                    .. " · "
                    .. p.supervision
            )
        )
        banner:SetText(
            d.demo
                    and ("Single-session fixtures · saved live profiles untouched · loss " .. (d.demo.sim.loss and "ON" or "off") .. " · simulation time " .. math.floor(
                        d.demo.sim.now
                    ))
                or (
                    t and "Connected · Family pairing and chat permissions are active."
                    or (
                        d.connectionStatus
                        or "Connecting to Battle.net. Pairing reconnects automatically."
                    )
                )
        )
        roleGuardian:SetEnabled(mutableRole and p.role ~= "guardian")
        roleChild:SetEnabled(mutableRole and p.role ~= "child")
        demo:SetEnabled(ns.ShowNetworkDemo ~= nil)
        syncSelected:SetEnabled(t ~= nil and p.role == "guardian" and d.selectedChild ~= nil)
        if #children == 0 then
            empty:Show()
        else
            empty:Hide()
        end
        if p.role == "child" then
            empty:SetText("Your saved permissions appear here. Family shows your guardians.")
        end
        for i, row in ipairs(childButtons) do
            local child = children[i]
            if child then
                row.peer = child
                local status = t and ns.TransportPresence(t, child) or "unreachable"
                row.control:SetText(
                    plain((d.selectedChild == child and "> " or "") .. child .. " · " .. status)
                )
                row.control:Show()
            else
                row.control:Hide()
            end
        end
        for name, control in pairs(tabs) do
            control:SetEnabled(tab ~= name)
        end
        if tab == "permissions" then
            permissions:Show()
        else
            permissions:Hide()
        end
        if tab == "family" then
            family:Show()
        else
            family:Hide()
        end
        if tab == "requests" then
            requests:Show()
        else
            requests:Hide()
        end
        if t then
            ns.PollRequests(t)
        end
        local requestRows = {}
        if p.role == "child" then
            requestRows = ns.RequestRows(p, d.now())
        elseif view then
            for _, r in pairs(view.requests or {}) do
                requestRows[#requestRows + 1] = r
            end
            table.sort(requestRows, function(a, b)
                return a.id < b.id
            end)
        end
        requestIndex = math.max(1, math.min(requestIndex, #requestRows))
        selectedRequest, requestChild = requestRows[requestIndex], d.selectedChild
        requestGeneration = view and view.generation
        local request = selectedRequest
        local detail =
            "No requests available. Refresh after pairing. Child requests remain queued while disconnected."
        if request then
            local names = {
                party = "Party",
                say = "Say",
                yell = "Yell",
                guild = "Guild",
                raid = "Raid",
                instance = "Instance",
                ["whisper-character"] = "Whisper character",
                ["whisper-account"] = "Battle.net friend",
            }
            local state = request.state
            if state == "pending" and d.now() >= request.expires then
                state = "expired"
            end
            detail = (p.role == "guardian" and (requestChild or "Child") .. " · " or "")
                .. "Request "
                .. requestIndex
                .. "/"
                .. #requestRows
                .. "\nAccess: "
                .. (names[request.channel] or request.channel)
                .. " / "
                .. (request.channel:find("^whisper%-") and "read + send" or request.direction)
                .. "\nTarget: "
                .. (request.target ~= "" and request.target or "Everyone in this channel")
                .. "\nReason: "
                .. (request.reason ~= "" and request.reason or "None")
                .. "\nState: "
                .. state
                .. (p.role == "guardian" and " (last fetched)" or "")
                .. " · request expires in "
                .. math.max(0, math.ceil((request.expires - d.now()) / 60))
                .. " minutes"
            local latest
            for _, item in ipairs(t and t.work or {}) do
                if
                    item.kind == "request-decision"
                    and item.peer == requestChild
                    and not item.reply
                then
                    local fields = ns.DecodeMessage(item.wire)
                    if
                        fields
                        and fields[6] == request.id
                        and (not latest or tonumber(item.sequence) > tonumber(latest.sequence))
                    then
                        latest = item
                    end
                end
            end
            if latest then
                local delivery = {
                    pending = "Awaiting delivery",
                    delivered = "Received; awaiting child application",
                    applied = "Applied on child",
                    expired = "Delivery expired; refresh requests",
                    rejected = "Rejected by child; refresh requests",
                    cancelled = "Delivery cancelled",
                }
                detail = detail .. "\nDecision: " .. (delivery[latest.state] or latest.state)
                if latest.result == "request-policy-changed" then
                    detail = detail
                        .. " — permissions changed; cancel and create a fresh request."
                end
            end
        end
        requestDetails:SetText(plain(detail))
        if p.role == "guardian" then
            fetchRequests:Show()
            promptSetting:Show()
        else
            fetchRequests:Hide()
            promptSetting:Hide()
        end
        fetchRequests:SetEnabled(canEdit)
        promptSetting:SetEnabled(canEdit and view ~= nil and view.requestPrompts ~= nil)
        promptSetting:SetText(
            "Stranger prompts: "
                .. (
                    view
                        and view.requestPrompts ~= nil
                        and (view.requestPrompts and "on" or "off")
                    or "unknown"
                )
        )
        for _, control in ipairs(decisionButtons) do
            if p.role == "guardian" then
                control:Show()
            else
                control:Hide()
            end
            control:SetEnabled(
                canEdit
                    and request ~= nil
                    and request.state == "pending"
                    and d.now() < request.expires
            )
        end
        if p.role == "child" then
            childForm:Show()
            requestTiming:Hide()
        else
            childForm:Hide()
            requestTiming:Show()
        end
        createRequest:SetEnabled(t ~= nil and p.supervision == "paired")
        cancelRequest:SetEnabled(request ~= nil and request.state == "pending")
        local prompt = d.chat and d.chat.prompt
        if
            p.role == "child"
            and prompt
            and prompt.expires > d.now()
            and prompt.generation == p.generation
            and p.requestPrompts ~= false
        then
            whisperPrompt:SetText(
                plain("Blocked whisper from " .. prompt.character .. ". Message hidden.")
            )
            whisperPrompt:Show()
            promptRequest:Show()
        else
            whisperPrompt:Hide()
            promptRequest:Hide()
        end
        if tab == "connection" then
            connection:Show()
        else
            connection:Hide()
        end
        local summary = p.role == "child" and "Your saved permissions"
            or (
                d.selectedChild
                    and (d.selectedChild .. " · last known policy revision " .. tostring(
                        view and view.revision or "unknown"
                    ))
                or "Select a child, or pair one in Family"
            )
        selection:SetText(plain(summary))
        local displayed = {}
        local joined = t and t.joinedChannels and t.joinedChannels[d.selectedChild or ""]
        for _, spec in ipairs(channels) do
            if (not joined and not (t and t.family.channels)) or not spec[1]:find("^channel:") then
                displayed[#displayed + 1] = spec
            end
        end
        for _, spec in ipairs(joined or {}) do
            displayed[#displayed + 1] = spec
        end
        permissionUI.body:SetHeight(math.max(286, #displayed * 40))
        for i, row in ipairs(rows) do
            local spec = displayed[math.ceil(i / 2)]
            if spec then
                row.channel = spec[1]
                row.caption:SetText(plain(spec[2]))
                row.caption:Show()
                row.state:Show()
                local value, r, g, b =
                    ns.DashboardPermission(d, d.selectedChild, row.channel, row.direction)
                row.state:SetText(value)
                row.state:SetTextColor(r, g, b)
                for _, control in ipairs(row.buttons) do
                    control:Show()
                    control:SetEnabled(canEdit)
                end
            else
                row.caption:Hide()
                row.state:Hide()
                for _, control in ipairs(row.buttons) do
                    control:Hide()
                end
            end
        end
        permissionUI.channelTab:SetEnabled(permissionUI.section ~= "channels")
        permissionUI.whisperTab:SetEnabled(permissionUI.section ~= "whispers")
        if permissionUI.section == "channels" then
            permissionUI.channels:Show()
            permissionUI.whispers:Hide()
        else
            permissionUI.channels:Hide()
            permissionUI.whispers:Show()
        end
        if
            permissionUI.peer ~= (d.selectedChild or "")
            or permissionUI.generation ~= (view and view.generation or p.generation)
        then
            permissionUI.peer = d.selectedChild or ""
            permissionUI.generation = view and view.generation or p.generation
            permissionUI.page = 1
            whisperTarget:SetText("")
        end
        local contacts = {}
        if p.role == "guardian" then
            for key in pairs(view and view.settings or {}) do
                local channel, target = key:match("^(whisper%-[^/]+)/[^/]+/(.+)$")
                if channel and target then
                    contacts[channel .. ":" .. target] = { channel = channel, target = target }
                end
            end
            for _, item in ipairs(t and t.work or {}) do
                if
                    item.peer == d.selectedChild
                    and item.kind == "policy"
                    and not item.reply
                    and (item.state == "pending" or item.state == "delivered")
                then
                    local fields = ns.DecodeMessage(item.wire)
                    if fields and fields[6]:find("^whisper%-") then
                        local target = fields[6] == "whisper-character"
                                and ns.CharacterKey(fields[11])
                            or fields[11]
                        if target then
                            contacts[fields[6] .. ":" .. target] =
                                { channel = fields[6], target = target }
                        end
                    end
                end
            end
        else
            for _, grant in pairs(p.policy.whispers) do
                contacts[grant.kind .. ":" .. grant.target] =
                    { channel = "whisper-" .. grant.kind, target = grant.target }
            end
        end
        local contactList = {}
        for _, contact in pairs(contacts) do
            contactList[#contactList + 1] = contact
        end
        table.sort(contactList, function(a, b)
            return a.target == b.target and a.channel < b.channel or a.target < b.target
        end)
        local pages = math.max(1, math.ceil(#contactList / 5))
        permissionUI.page = math.min(permissionUI.page, pages)
        permissionUI.summary:SetText(
            plain(
                #contactList > 0
                        and (#contactList .. " saved contacts · page " .. permissionUI.page .. "/" .. pages .. " · select a contact to edit")
                    or "No saved whisper contacts. Sync the child to fetch their permissions."
            )
        )
        for i, row in ipairs(permissionUI.contactRows) do
            local contact = contactList[(permissionUI.page - 1) * 5 + i]
            if contact then
                row.channel, row.target = contact.channel, contact.target
                local state =
                    ns.DashboardPermission(d, d.selectedChild, row.channel, "read", row.target)
                row.control:SetText(
                    plain(
                        row.target
                            .. " · "
                            .. (row.channel == "whisper-account" and "Account" or "Character")
                            .. " · "
                            .. state
                    )
                )
                row.control:Show()
            else
                row.control:Hide()
            end
        end
        local custom = ns.CustomChannelKey(permissionUI.customTarget:GetText())
        for _, control in ipairs(permissionUI.customButtons) do
            control:SetEnabled(canEdit and custom ~= nil)
        end
        if custom then
            local read = ns.DashboardPermission(d, d.selectedChild, custom, "read")
            local send = ns.DashboardPermission(d, d.selectedChild, custom, "send")
            permissionUI.customState:SetText("Read: " .. read .. " · Send: " .. send)
        else
            permissionUI.customState:SetText("Named settings override Custom channels.")
        end
        permissionUI.previous:SetEnabled(permissionUI.page > 1)
        permissionUI.next:SetEnabled(permissionUI.page < pages)
        characterButton:SetEnabled(whisperKind ~= "whisper-character")
        accountButton:SetEnabled(whisperKind ~= "whisper-account")
        local target = whisperTarget:GetText()
        local validTarget = whisperKind == "whisper-character" and ns.CharacterKey(target) ~= nil
            or whisperKind == "whisper-account" and ns.ValidIdentifier(target)
        for _, control in ipairs(whisperButtons) do
            control:SetEnabled(canEdit and validTarget)
        end
        if target ~= "" then
            local value, r, g, b =
                ns.DashboardPermission(d, d.selectedChild, whisperKind, "read", target)
            whisperState:SetText(
                "Read & send: " .. value .. " · party access never grants whispers."
            )
            whisperState:SetTextColor(r, g, b)
        else
            whisperState:SetText("Enter a target to review or change bidirectional whisper access.")
        end
        refreshPairing(canEdit, tab == "family")
        local pendingCount = 0
        for _, r in pairs(t and t.family.guardianInbox or {}) do
            if r.state == "pending" and d.now() < r.expires then
                pendingCount = pendingCount + 1
            end
        end
        if p.role == "guardian" and pendingCount > 0 then
            pairingNotice:SetText("Guardianship requests (" .. pendingCount .. ")")
            pairingNotice:Show()
        else
            pairingNotice:Hide()
        end
        local members, names =
            p.role == "child" and p.guardians or (view and view.members or {}), {}
        for member in pairs(members) do
            names[#names + 1] = member
        end
        table.sort(names)
        for i, row in ipairs(memberRows) do
            local member = names[i]
            if member then
                row.peer = member
                row.text:SetText(plain(member))
                row.text:Show()
                if p.role == "guardian" then
                    row.remove:Show()
                else
                    row.remove:Hide()
                end
                row.remove:SetEnabled(canEdit)
            else
                row.text:Hide()
                row.remove:Hide()
            end
        end
        if p.role == "child" then
            stopButton:Show()
        else
            stopButton:Hide()
        end
        stopButton:SetEnabled(t ~= nil and p.supervision ~= "unpaired")
        if p.role == "guardian" then
            tabs.activity:Show()
        else
            tabs.activity:Hide()
        end
        refreshActivity(p.role == "guardian" and tab == "activity", canEdit)
        if p.role == "child" then
            local monitoring = d.chat and d.chat.monitoring and p.supervision == "paired"
            banner:SetText(
                plain(
                    (d.demo and "SIMULATION · " or "")
                        .. (
                            monitoring
                                and "Chat monitoring is active on supported routes. Your guardians can review captured chat."
                            or "Chat monitoring is connecting."
                        )
                )
            )
        end
        connectionText:SetText(plain(ns.DashboardText(d)))
        body:SetHeight(math.max(422, connectionText:GetStringHeight() + 10))
        message:SetText(plain(d.message))
        if pendingAction then
            confirmation:SetText(plain(pendingAction.caption))
            confirmation:Show()
            confirmButton:Show()
            cancelButton:Show()
            for _, control in ipairs(demoButtons) do
                control:Hide()
            end
        else
            confirmation:Hide()
            confirmButton:Hide()
            cancelButton:Hide()
            for _, control in ipairs(demoButtons) do
                control:Show()
            end
        end
    end
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then
            elapsed = 0
            refresh()
        end
    end)
    d.focusSection = function(value)
        tab = value
        refresh()
    end
    frame:SetScript("OnShow", refresh)
    refresh()
    frame:Show()
end
