local _, ns = ...
---@cast ns GuardianNamespace

local function plain(value)
    return tostring(value):gsub("|", "||")
end

---A separate closure keeps the dashboard under Lua 5.1's 60-upvalue limit.
---@param d GuardianDashboard
---@param activity Frame
---@param widgets GuardianActivityWidgets
---@return GuardianActivityRefresh
function ns.NewActivityPanel(d, activity, widgets)
    local button, input, label = widgets.button, widgets.input, widgets.label
    ---@type GuardianHistoryFilters
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
    local channelFilter, directionFilter, outcomeFilter, timeFilter
    channelFilter = button(activity, 14, 12, 166, "All channels", function()
        historyChannel = historyChannel % #historyChannels + 1
        local spec = historyChannels[historyChannel]
        historyFilters.channel = spec[1] ~= "" and spec[1] or nil
        channelFilter:SetText(spec[2])
        historyPage = 1
    end)
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
    local historyText = label(historyBody, 0, 0, 646, "", "GameFontHighlightSmall")
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
            local lines = {}
            for i = (historyPage - 1) * 20 + 1, math.min(#matched, historyPage * 20) do
                local record = matched[i]
                local who = record.character ~= "" and record.character
                    or record.account ~= "" and record.account
                    or "Unknown identity"
                local status = {
                    allowed = "Allowed incoming",
                    blocked = "Blocked incoming",
                    ["blocked-attempt"] = "Blocked send attempt",
                    attempted = "Send attempted",
                    output = "Local output observed",
                    gap = "Capture gap",
                }
                lines[#lines + 1] = date("%Y-%m-%d %H:%M:%S", record.time)
                    .. " · "
                    .. record.channel
                    .. " · "
                    .. who
                    .. "\n"
                    .. (status[record.disposition] or record.disposition)
                    .. (record.truncated and " · text truncated" or "")
                    .. (record.endedAt > record.time and (" · until " .. date(
                        "%H:%M:%S",
                        record.endedAt
                    )) or "")
                    .. "\n"
                    .. record.text
                    .. "\n"
            end
            historyText:SetText(
                plain(
                    #lines > 0 and table.concat(lines, "\n")
                        or "No matching captured chat. Choose another channel/time, or refresh when the child is reachable."
                )
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
