local addonName, ns = ...
---@cast addonName string
---@cast ns GuardianNamespace

ns.initialized = false

---The slash command and launcher always open the same local dashboard.
function ns.OpenDashboard()
    if not ns.initialized then
        return
    end
    ns.dashboard = ns.dashboard
        or ns.NewDashboard(ns.settings, nil, GetServerTime, ns.chat and ns.chat.chat)
    ns.ShowDashboard(ns.dashboard)
end

SLASH_GUARDIAN1 = "/guardian"
SlashCmdList.GUARDIAN = function(message)
    if ns.initialized and message and message ~= "" then
        if message == "demo" then
            if ns.ShowNetworkDemo then
                ns.ShowNetworkDemo()
            else
                print("Guardian: stage the development simulator, reload, then /guardian demo.")
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
    print(string.format("Guardian %s; initialized: %s", version, tostring(ns.initialized)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "PLAYER_LOGIN" and ns.initialized then
        ns.InstallMinimapButton()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    if event ~= "ADDON_LOADED" or loadedAddon ~= addonName then
        return
    end
    GuardianDB = ns.NormalizeSettings(GuardianDB)
    ns.PruneProfileHistory(GuardianDB, GetServerTime())
    ns.settings = GuardianDB
    ns.initialized = true
    if not ns.InstallMinimapButton() then
        self:RegisterEvent("PLAYER_LOGIN")
    end
    self:UnregisterEvent("ADDON_LOADED")
end)
