local _, ns = ...
---@cast ns GuardianNamespace

---Created after this addon's settings initialize; never a named global frame.
---@return Button?
function ns.InstallMinimapButton()
    if ns.minimapButton then
        return ns.minimapButton
    end
    if not Minimap then
        return nil
    end
    local button = CreateFrame("Button", nil, Minimap)
    button:SetSize(32, 32)
    button:SetPoint("CENTER", Minimap, "CENTER", -65, -65)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp")
    button:SetNormalTexture("Interface\\AchievementFrame\\UI-Achievement-TinyShield")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Common\\RingBorder")
    border:SetSize(40, 40)
    border:SetPoint("CENTER")
    button:SetScript("OnClick", function()
        ns.OpenDashboard()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Guardian\nClick to open Guardian.")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    ns.minimapButton = button
    return button
end
