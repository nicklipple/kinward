local addonName, ns = ...
---@cast addonName string
---@cast ns GuardianNamespace

ns.initialized = false

SLASH_GUARDIAN1 = "/guardian"
SlashCmdList.GUARDIAN = function()
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
