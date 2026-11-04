local _, ns = ...
---@cast ns KinwardNamespace

local function plain(value)
    return tostring(value):gsub("|", "||")
end

---@param d KinwardDashboard
---@param family Frame
---@param widgets KinwardActivityWidgets
---@param confirm KinwardFamilyConfirm
---@return KinwardPairingRefresh
function ns.NewPairingPanel(d, family, widgets, confirm)
    local label, button, input = widgets.label, widgets.button, widgets.input
    local title = label(family, 14, 14, 680, "", "GameFontNormal")
    local childForm = CreateFrame("Frame", nil, family)
    childForm:SetPoint("TOPLEFT", 0, -40)
    childForm:SetSize(716, 195)
    label(
        childForm,
        14,
        4,
        680,
        "Your guardian's character name, Name-Realm or BattleTag (a verified Battle.net friend)",
        "GameFontHighlightSmall"
    )
    local name = input(childForm, 18, 26, 405)
    local previewPeer, previewName, previewNext
    local request = button(childForm, 440, 27, 260, "Request guardianship", function()
        if d.transport then
            local _, message = ns.RequestGuardianship(d.transport, name:GetText(), previewPeer)
            d.message = message
        end
    end)
    local status = label(childForm, 14, 70, 680, "", "GameFontHighlightSmall")
    local cancel = button(childForm, 14, 132, 190, "Cancel guardianship request", function()
        if d.transport and d.transport.family.proposal then
            d.transport.family.proposal.state = "cancelled"
            d.transport.family.pending = nil
            d.message = "Guardianship request cancelled. A delayed acceptance cannot pair you."
        end
    end)
    local inbox = CreateFrame("Frame", nil, family)
    inbox:SetPoint("TOPLEFT", 0, -40)
    inbox:SetSize(716, 195)
    local page = 1
    local hint = label(inbox, 14, 0, 680, "", "GameFontHighlightSmall")
    local rows = {}
    for i = 1, 3 do
        local row = {}
        row.label = label(inbox, 14, 28 + (i - 1) * 36, 395, "", "GameFontHighlightSmall")
        row.accept = button(inbox, 422, 24 + (i - 1) * 36, 132, "Accept child", function()
            if d.transport and row.peer and row.token then
                local _, message = ns.AnswerGuardianship(d.transport, row.peer, row.token, true)
                d.message = message
            end
        end)
        row.decline = button(inbox, 564, 24 + (i - 1) * 36, 132, "Decline", function()
            if d.transport and row.peer and row.token then
                local _, message = ns.AnswerGuardianship(d.transport, row.peer, row.token, false)
                d.message = message
            end
        end)
        rows[i] = row
    end
    local previous = button(inbox, 14, 136, 92, "Previous child", function()
        page = math.max(1, page - 1)
    end)
    local nextPage = button(inbox, 114, 136, 92, "Next child", function()
        page = page + 1
    end)
    local sync = button(inbox, 216, 136, 128, "Sync child", function()
        ns.DashboardAction(d, "sync", { d.selectedChild or "" })
    end)
    local candidateLabel = label(inbox, 14, 169, 405, "", "GameFontHighlightSmall")
    local candidate
    local approve = button(inbox, 422, 169, 274, "Approve guardian", function()
        if candidate then
            confirm(
                "Add " .. candidate.peer .. " as a guardian for " .. candidate.child .. "?",
                "add",
                { candidate.child, candidate.peer, candidate.token, "confirm" }
            )
        end
    end)
    return function(canEdit, visible)
        local t, p, now = d.transport, d.profile, d.now()
        if visible and t then
            if p.role == "guardian" then
                t.pairingPolling = true
            end
            ns.TickGuardianship(t)
        end
        title:SetText(
            p.role == "child" and "Ask a parent to become your guardian"
                or "Children requesting guardianship"
        )
        if p.role == "child" then
            childForm:Show()
            inbox:Hide()
        else
            childForm:Hide()
            inbox:Show()
        end
        if d.pairingTarget and p.role == "child" then
            local target = d.pairingTarget or ""
            d.pairingTarget = nil
            name:SetText(target)
            previewName = nil
        end
        local proposal = t and t.family.proposal
        local waiting = proposal
            and (proposal.state == "pending" or proposal.state == "awaiting-approval")
            and now < proposal.expires
        if t and (previewName ~= name:GetText() or now >= (previewNext or 0)) then
            previewName, previewNext = name:GetText(), now + 5
            previewPeer = ns.ResolveGuardianPeer(t, previewName)
        end
        request:SetEnabled(
            t ~= nil
                and p.role == "child"
                and p.supervision ~= "recovery"
                and not waiting
                and previewPeer ~= nil
                and previewPeer ~= (t and t.family.id)
                and not p.guardians[previewPeer or ""]
        )
        cancel:SetEnabled(waiting == true)
        local descriptions = {
            pending = "Waiting for your guardian to accept.",
            ["awaiting-approval"] = "Accepted by your new guardian; waiting for an existing guardian to approve.",
            expired = "The request expired. Send a new request.",
            declined = "Your guardian declined this request.",
            cancelled = "The request was cancelled.",
        }
        local statusText
        if not t then
            statusText =
                "Live pairing is inactive. For a consenting two-account test, run /kinward test start on both accounts."
        elseif waiting and proposal then
            statusText = "Guardian: "
                .. proposal.peer
                .. "\n"
                .. (descriptions[proposal.state] or proposal.state)
        elseif previewPeer and p.guardians[previewPeer] then
            statusText =
                "This account already supervises you. Enter another guardian's name to request an addition."
        elseif previewPeer then
            statusText = "Send to verified account: "
                .. previewPeer
                .. "\nCheck this is your parent, then click Request guardianship."
        else
            statusText = name:GetText() ~= ""
                    and t
                    and "No unique verified friend found. Try Name-Realm or the full BattleTag."
                or "Enter your parent's name and send a request. They only need to click Accept child."
        end
        if proposal and not waiting then
            statusText = statusText
                .. "\n"
                .. (
                    now >= proposal.expires and descriptions.expired
                    or descriptions[proposal.state]
                    or proposal.state
                )
        end
        status:SetText(plain(statusText))
        local entries = {}
        for peer, r in pairs(t and t.family.guardianInbox or {}) do
            if now < r.expires and r.state ~= "accepted" and r.state ~= "declined" then
                entries[#entries + 1] = { peer = peer, record = r }
            end
        end
        table.sort(entries, function(a, b)
            return a.peer < b.peer
        end)
        local pages = math.max(1, math.ceil(#entries / 3))
        page = math.min(page, pages)
        hint:SetText(
            #entries > 0
                    and "Accept only children you recognize. Pairing applies closed permissions immediately."
                or "No pending child requests. Ask your child to enter your name and request guardianship."
        )
        for i, row in ipairs(rows) do
            local entry = entries[(page - 1) * 3 + i]
            if entry then
                row.peer, row.token = entry.peer, entry.record.token
                local states = {
                    pending = "requests guardianship",
                    accepting = "acceptance sent",
                    declining = "decline sent",
                    ["awaiting-approval"] = "waiting for an existing guardian",
                }
                row.label:SetText(
                    plain(
                        entry.peer .. " · " .. (states[entry.record.state] or entry.record.state)
                    )
                )
                row.label:Show()
                row.accept:Show()
                row.decline:Show()
                row.accept:SetEnabled(entry.record.state == "pending")
                row.decline:SetEnabled(entry.record.state == "pending")
            else
                row.peer, row.token = nil, nil
                row.label:Hide()
                row.accept:Hide()
                row.decline:Hide()
            end
        end
        previous:SetEnabled(page > 1)
        nextPage:SetEnabled(page < pages)
        sync:SetEnabled(t ~= nil and d.selectedChild ~= nil)
        local c = t and t.guardianCandidates and t.guardianCandidates[d.selectedChild or ""]
        candidate = canEdit
                and c
                and now < c.expires
                and { child = d.selectedChild, peer = c.peer, token = c.token }
            or nil
        candidateLabel:SetText(
            plain(
                candidate
                        and (candidate.peer .. " has accepted " .. candidate.child .. "'s request.")
                    or "Additional guardians appear here after they accept the child's request."
            )
        )
        approve:SetEnabled(candidate ~= nil)
    end
end
