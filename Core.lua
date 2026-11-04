local addonName, ns = ...
---@cast addonName string
---@cast ns GuardianNamespace

ns.initialized = false

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
        ns.dashboard = ns.dashboard or ns.NewDashboard(ns.settings, nil, GetServerTime)
        if message == "ui" then
            ns.ShowDashboard(ns.dashboard)
        else
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
    if event ~= "ADDON_LOADED" or loadedAddon ~= addonName then
        return
    end
    GuardianDB = ns.NormalizeSettings(GuardianDB)
    ns.settings = GuardianDB
    ns.initialized = true
    self:UnregisterEvent("ADDON_LOADED")
end)
