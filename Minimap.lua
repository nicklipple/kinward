local _, ns = ...
---@cast ns KinwardNamespace

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
    local angle = ns.settings and ns.settings.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or angle <= -math.huge or angle >= math.huge then
        angle = -3 * math.pi / 4
    end
    local function place()
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 92, math.sin(angle) * 92)
    end
    local function followCursor()
        local x, y = GetCursorPosition()
        local cx, cy = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        if not cx or not cy or scale <= 0 then
            return
        end
        x, y = x / scale - cx, y / scale - cy
        if x ~= 0 or y ~= 0 then
            angle = math.atan2(y, x)
            place()
        end
    end
    place()
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetNormalTexture("Interface\\AddOns\\Kinward\\KinwardIcon.tga")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Common\\RingBorder")
    border:SetSize(40, 40)
    border:SetPoint("CENTER")
    local dragging, dragged = false, false
    button:SetScript("OnDragStart", function(self)
        dragging, dragged = true, true
        GameTooltip:Hide()
        followCursor()
        self:SetScript("OnUpdate", followCursor)
    end)
    local function stopDrag(self)
        if dragging then
            followCursor()
            dragging = false
            self:SetScript("OnUpdate", nil)
            if ns.settings then
                ns.settings.minimapAngle = angle
            end
        end
    end
    button:SetScript("OnDragStop", stopDrag)
    button:SetScript("OnHide", stopDrag)
    button:SetScript("OnMouseDown", function()
        dragged = false
    end)
    button:SetScript("OnClick", function()
        if not dragged then
            ns.OpenDashboard()
        end
    end)
    button:SetScript("OnEnter", function(self)
        if dragging then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Kinward\nClick to open Kinward.\nHold left click and drag to move.")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    ns.minimapButton = button
    return button
end
