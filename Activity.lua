local _, ns = ...
---@cast ns KinwardNamespace

local function plain(value)
    return tostring(value):gsub("|", "||")
end

-- Escape captured content before adding our own chat colors. Captured text must
-- never introduce links, textures, color escapes or additional forged chat lines.
local function chatText(value)
    return (plain(value):gsub("[\r\n]+", " "))
end

local chatChannels = {
    whisper = { "Whisper", "ffff80ff" },
    party = { "Party", "ffaaaaff" },
    say = { "Say", "ffffffff" },
    yell = { "Yell", "ffff4040" },
    guild = { "Guild", "ff40ff40" },
    raid = { "Raid", "ffff7f00" },
    instance = { "Instance", "ffff7f00" },
    ["channel:general"] = { "General", "ffffc0c0" },
    ["channel:lookingforgroup"] = { "Looking For Group", "ffffc0c0" },
    ["channel:trade"] = { "Trade", "ffffc0c0" },
}
local outcomes = {
    allowed = "",
    blocked = "|cffff6060[Blocked incoming]|r ",
    ["blocked-attempt"] = "|cffff6060[Blocked send attempt]|r ",
    attempted = "|cffffcc66[Send attempted]|r ",
    output = "|cffaaaaaa[Local output]|r ",
    gap = "|cffffcc66[Capture gap]|r ",
}

---@param record KinwardHistoryRecord
---@return string
local function chatLine(record)
    local spec = chatChannels[record.channel] or { record.channel, "ffffcc66" }
    local who = record.character ~= "" and record.character
        or record.account ~= "" and record.account
        or "Unknown identity"
    local prefix = record.disposition == "gap" and ""
        or ((record.direction == "send" and "To " or "") .. "[" .. chatText(who) .. "]: ")
    local suffix = (record.truncated and " |cffaaaaaa[Text truncated]|r" or "")
        .. (
            record.endedAt > record.time
                and (" |cffaaaaaa[Until " .. date("%H:%M:%S", record.endedAt) .. "]|r")
            or ""
        )
    return "|cff999999["
        .. date("%H:%M:%S", record.time)
        .. "]|r "
        .. (outcomes[record.disposition] or "")
        .. "|c"
        .. spec[2]
        .. "["
        .. chatText(spec[1])
        .. "] "
        .. prefix
        .. chatText(record.text)
        .. "|r"
        .. suffix
end

---A separate closure keeps the dashboard under Lua 5.1's 60-upvalue limit.
---@param d KinwardDashboard
---@param activity Frame
---@param widgets KinwardActivityWidgets
---@return KinwardActivityRefresh
function ns.NewActivityPanel(d, activity, widgets)
    local button, input, label = widgets.button, widgets.input, widgets.label
    ---@type KinwardHistoryFilters
    local historyFilters = {}
    local historyPage, historyPeer = 1, nil
    local historyChannel, historyDirection, historyDisposition, historyWindow = 1, 1, 1, 1
    local historyChannels = {
        { "", "All channels" },
        { "whisper", "Whispers" },
        { "party", "Party" },
        { "monitoring", "Monitoring gaps" },
        { "say", "Say" },
        { "guild", "Guild" },
        { "raid", "Raid" },
        { "instance", "Instance" },
    }
    local historyDirections = {
        { "", "Both directions" },
        { "read", "Incoming" },
        { "send", "Outgoing" },
        { "system", "System" },
    }
    local historyDispositions = {
        { "", "All outcomes" },
        { "allowed", "Allowed reads" },
        { "blocked", "Blocked reads" },
        { "blocked-attempt", "Blocked sends" },
        { "attempted", "Send attempts" },
        { "output", "Local output" },
        { "gap", "Capture gaps" },
    }
    local historyWindows = {
        { 0, "All retained time" },
        { 900, "Last 15 minutes" },
        { 3600, "Last hour" },
        { 86400, "Last 24 hours" },
        { 604800, "Last 7 days" },
    }
    local channelFilter = CreateFrame("DropdownButton", nil, activity, "WowStyle1DropdownTemplate")
    ---@cast channelFilter DropdownButton
    channelFilter:SetPoint("TOPLEFT", 14, -12)
    channelFilter:SetSize(166, 24)
    channelFilter:SetupMenu(function(_, rootDescription)
        for index, spec in ipairs(historyChannels) do
            rootDescription:CreateRadio(spec[2], function()
                return historyChannel == index
            end, function()
                historyChannel = index
                historyFilters.channel = spec[1] ~= "" and spec[1] or nil
                historyPage = 1
            end)
        end
    end)
    local directionFilter, outcomeFilter, timeFilter
    directionFilter = button(activity, 190, 12, 162, "Both directions", function()
        historyDirection = historyDirection % #historyDirections + 1
        local spec = historyDirections[historyDirection]
        historyFilters.direction = spec[1] ~= "" and spec[1] or nil
        directionFilter:SetText(spec[2])
        historyPage = 1
    end)
    outcomeFilter = button(activity, 362, 12, 160, "All outcomes", function()
        historyDisposition = historyDisposition % #historyDispositions + 1
        local spec = historyDispositions[historyDisposition]
        historyFilters.disposition = spec[1] ~= "" and spec[1] or nil
        outcomeFilter:SetText(spec[2])
        historyPage = 1
    end)
    timeFilter = button(activity, 532, 12, 166, "All retained time", function()
        historyWindow = historyWindow % #historyWindows + 1
        local spec = historyWindows[historyWindow]
        historyFilters.seconds = spec[1] > 0 and spec[1] or nil
        timeFilter:SetText(spec[2])
        historyPage = 1
    end)
    label(
        activity,
        14,
        46,
        340,
        "Character / BattleTag conversation filter",
        "GameFontHighlightSmall"
    )
    local conversationFilter = input(activity, 18, 64, 310)
    local refreshHistory = button(activity, 344, 65, 166, "Refresh history", function()
        if d.transport and ns.WatchHistory(d.transport, d.selectedChild or "") then
            ns.PollHistory(d.transport)
        end
    end)
    local sampleHistory = button(activity, 520, 65, 178, "Add sample chat", function()
        if d.demo and d.selectedChild then
            ns.SimHistorySamples(d.demo, d.selectedChild)
        end
    end)
    local historyStatus = label(activity, 14, 102, 680, "", "GameFontHighlightSmall")
    local historyScroll = CreateFrame("ScrollFrame", nil, activity, "UIPanelScrollFrameTemplate")
    historyScroll:SetPoint("TOPLEFT", 14, -158)
    historyScroll:SetSize(666, 232)
    local historyBody = CreateFrame("Frame", nil, historyScroll)
    historyBody:SetSize(656, 232)
    historyScroll:SetScrollChild(historyBody)
    local chatBackground = historyScroll:CreateTexture(nil, "BACKGROUND")
    chatBackground:SetAllPoints()
    chatBackground:SetColorTexture(0, 0, 0, 0.65)
    local historyText = label(historyBody, 8, 6, 630, "", "ChatFontNormal")
    local newerHistory = button(activity, 14, 408, 110, "Newer", function()
        historyPage = math.max(1, historyPage - 1)
    end)
    local olderHistory = button(activity, 132, 408, 110, "Older", function()
        historyPage = historyPage + 1
    end)
    label(activity, 256, 398, 148, "Keep days / max rows", "GameFontHighlightSmall")
    local retentionInput, countInput = input(activity, 260, 420, 64), input(activity, 338, 420, 76)
    retentionInput:SetText("7")
    countInput:SetText("10000")
    local configureHistory = button(activity, 432, 410, 266, "Apply history retention", function()
        local days, count = tonumber(retentionInput:GetText()), tonumber(countInput:GetText())
        if days and count then
            ns.DashboardAction(
                d,
                "history-config",
                { d.selectedChild or "", tostring(days * 86400), tostring(count) }
            )
        end
    end)
    return function(visible, canEdit)
        local p, t = d.profile, d.transport
        local view = d.selectedChild and p.childProfiles[d.selectedChild]
        if visible and p.role == "guardian" then
            activity:Show()
            if historyPeer ~= d.selectedChild then
                historyPeer, historyPage = d.selectedChild, 1
            end
            if t and d.selectedChild then
                ns.WatchHistory(t, d.selectedChild)
                ns.PollHistory(t)
            end
            historyFilters.identity = conversationFilter:GetText()
            local matched = ns.HistoryView(p, d.selectedChild or "", historyFilters, d.now())
            local pages = math.max(1, math.ceil(#matched / 20))
            historyPage = math.min(historyPage, pages)
            local lines, lastDay = {}, nil
            -- Pages are selected newest first, but each page reads top to bottom
            -- in chat order, with the most recent message at the bottom.
            for i = math.min(#matched, historyPage * 20), (historyPage - 1) * 20 + 1, -1 do
                local record = matched[i]
                local day = date("%Y-%m-%d", record.time)
                if day ~= lastDay then
                    lines[#lines + 1] = "|cffffd100[" .. day .. "]|r"
                    lastDay = day
                end
                lines[#lines + 1] = chatLine(record)
            end
            historyText:SetText(
                #lines > 0 and table.concat(lines, "\n")
                    or "No matching captured chat. Choose another channel/time, or refresh when the child is reachable."
            )
            historyBody:SetHeight(math.max(232, historyText:GetStringHeight() + 10))
            newerHistory:SetEnabled(historyPage > 1)
            olderHistory:SetEnabled(historyPage < pages)
            local h = view and view.history
            local presence = t and d.selectedChild and ns.TransportPresence(t, d.selectedChild)
                or "unreachable"
            historyStatus:SetText(
                plain(
                    (d.selectedChild or "Select a child")
                        .. " · "
                        .. presence
                        .. " · page "
                        .. historyPage
                        .. "/"
                        .. pages
                        .. " · "
                        .. #matched
                        .. " matching records\n"
                        .. (h and ("Received through " .. (h.cursor or 0) .. " of " .. h.high .. " · lost to count limit " .. h.pruned .. " · expired " .. h.expired .. " · " .. math.floor(
                            h.retention / 86400
                        ) .. " day retention / " .. h.maxRecords .. " rows") or "History has not been fetched yet.")
                        .. "\nCoverage: ordinary whispers/party only. Other surfaces and secret states may be missing. Local output does not prove receipt."
                )
            )
            refreshHistory:SetEnabled(canEdit)
            configureHistory:SetEnabled(canEdit)
            if d.demo then
                sampleHistory:Show()
            else
                sampleHistory:Hide()
            end
            sampleHistory:SetEnabled(canEdit)
        else
            activity:Hide()
            historyText:SetText("")
        end
    end
end
