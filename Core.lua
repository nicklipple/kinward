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
        or ns.NewDashboard(ns.settings, ns.transport, GetServerTime, ns.chat and ns.chat.chat)
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
    if ns.initialized and message and message ~= "" then
        if message == "status" then
            print(ns.RuntimeStatus())
            return
        end
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
                or ns.NewDashboard(
                    ns.settings,
                    ns.transport,
                    GetServerTime,
                    ns.chat and ns.chat.chat
                )
            print(ns.DashboardCommand(ns.dashboard, message))
        end
        return
    end
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "unknown"
    print(string.format("Kinward %s; initialized: %s", version, tostring(ns.initialized)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
local retryElapsed = 0
local function connect()
    if ns.StartRuntime() then
        frame:SetScript("OnUpdate", nil)
    else
        frame:SetScript("OnUpdate", function(_, delta)
            retryElapsed = retryElapsed + delta
            if retryElapsed >= 2 then
                retryElapsed = 0
                connect()
            end
        end)
    end
end
frame:SetScript("OnEvent", function(self, event, initial, reload)
    if event == "PLAYER_ENTERING_WORLD" and ns.initialized then
        ns.runtimeWorldReady = true
        if canaccessvalue(initial) and canaccessvalue(reload) then
            ns.runtimeReload = reload == true and initial == false
        end
        connect()
        return
    end
    if event == "BN_CONNECTED" and ns.initialized then
        connect()
        return
    end
    if event == "PLAYER_LOGIN" and ns.initialized then
        ns.InstallMinimapButton()
        ns.InstallPlayerMenu()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    if event ~= "ADDON_LOADED" or initial ~= addonName then
        return
    end
    KinwardDB = ns.NormalizeSettings(KinwardDB)
    ns.PruneProfileHistory(KinwardDB, GetServerTime())
    ns.settings = KinwardDB
    ns.initialized = true
    ns.InstallPlayerMenu()
    ns.InstallMinimapButton()
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("BN_CONNECTED")
    self:UnregisterEvent("ADDON_LOADED")
end)
