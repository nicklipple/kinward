local _, ns = ...
---@cast ns GuardianNamespace

---Normalize only owned fields; preserve valid settings and unknown user data.
---@param saved unknown
---@return GuardianSettings
function ns.NormalizeSettings(saved)
    local settings = type(saved) == "table" and saved or {}
    if type(settings.enabled) ~= "boolean" then
        settings.enabled = true
    end
    return settings
end
