local _, ns = ...
---@cast ns KinwardNamespace

local function text(value)
    return canaccessvalue(value)
        and type(value) == "string"
        and #value > 0
        and #value <= 128
        and not value:find("[|\r\n]")
end

-- Menu data is a selection hint, never proof of account ownership.
---@param context table
---@return string?
function ns.PlayerMenuTarget(context)
    if not canaccessvalue(context) then
        return nil
    end
    local account = context.accountInfo
    if canaccessvalue(account) and type(account) == "table" and text(account.battleTag) then
        return account.battleTag
    end
    if text(context.unit) then
        local player, self = UnitIsPlayer(context.unit), UnitIsUnit(context.unit, "player")
        if not canaccessvalue(player) or not canaccessvalue(self) or not player or self then
            return nil
        end
        local name, realm = UnitFullName(context.unit)
        if text(name) then
            if not text(realm) then
                realm = GetNormalizedRealmName()
            end
            if text(realm) then
                return name .. "-" .. realm
            end
        end
        return nil
    end
    if text(context.name) then
        if ns.CharacterKey(context.name) or context.name:find("#", 1, true) then
            return context.name
        end
        if text(context.surname) then
            return context.name .. "-" .. context.surname
        end
        return context.name -- The resolver must still reject ambiguous short names.
    end
    return nil
end

function ns.InstallPlayerMenu()
    if ns.playerMenuInstalled or not Menu or not Menu.ModifyMenu then
        return
    end
    for _, kind in ipairs({
        "PLAYER",
        "PARTY",
        "RAID_PLAYER",
        "FRIEND",
        "FRIEND_OFFLINE",
        "BN_FRIEND",
        "BN_FRIEND_OFFLINE",
        "CHAT_ROSTER",
    }) do
        Menu.ModifyMenu("MENU_UNIT_" .. kind, function(_, root, context)
            if not ns.initialized or type(context) ~= "table" then
                return
            end
            local target = ns.PlayerMenuTarget(context)
            if target then
                root:CreateButton("Kinward: Pair with player", function()
                    ns.OpenDashboard("family", target)
                end)
            end
        end)
    end
    ns.playerMenuInstalled = true
end
