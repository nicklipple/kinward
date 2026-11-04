local addonName, ns = ...
---@cast addonName string
---@cast ns KinwardNamespace

ns.initialized = false

---The slash command and launcher always open the same local dashboard.
function ns.OpenDashboard(section, target)
    if not ns.initialized then
        return
    end
    ns.dashboard = ns.dashboard
        or ns.NewDashboard(ns.settings, nil, GetServerTime, ns.chat and ns.chat.chat)
    if target then
        ns.dashboard.pairingTarget = target
        ns.dashboard.message = ns.settings
                and ns.settings.role == "child"
                and "Review the selected guardian, then send a request."
            or (
                ns.settings
                    and ns.settings.role == "guardian"
                    and "To supervise this player, ask them to select you and request guardianship from their Child role."
                or "Choose Child role to request the selected guardian, or Guardian role to supervise someone else."
            )
    end
    ns.ShowDashboard(ns.dashboard, section)
end

SLASH_KINWARD1 = "/kinward"
SlashCmdList.KINWARD = function(message)
    if ns.initialized and message and (message == "test" or message:match("^test%s+")) then
        print(ns.LiveTestCommand(message:match("^test%s*(.*)$") or ""))
        return
    end
    if ns.initialized and message and message ~= "" then
        if message == "demo" then
            if ns.ShowNetworkDemo then
                ns.ShowNetworkDemo()
            else
                print("Kinward: stage the development simulator, reload, then /kinward demo.")
            end
            return
        end
        if message == "ui" then
            ns.OpenDashboard()
        else
            ns.dashboard = ns.dashboard
                or ns.NewDashboard(ns.settings, nil, GetServerTime, ns.chat and ns.chat.chat)
            print(ns.DashboardCommand(ns.dashboard, message))
        end
        return
    end
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "unknown"
    print(string.format("Kinward %s; initialized: %s", version, tostring(ns.initialized)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "PLAYER_LOGIN" and ns.initialized then
        ns.InstallMinimapButton()
        ns.InstallPlayerMenu()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    if event ~= "ADDON_LOADED" or loadedAddon ~= addonName then
        return
    end
    KinwardDB = ns.NormalizeSettings(KinwardDB)
    ns.PruneProfileHistory(KinwardDB, GetServerTime())
    ns.settings = KinwardDB
    ns.initialized = true
    ns.InstallPlayerMenu()
    if not ns.InstallMinimapButton() then
        self:RegisterEvent("PLAYER_LOGIN")
    end
    self:UnregisterEvent("ADDON_LOADED")
end)
