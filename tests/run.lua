local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("ok - " .. name)
end

local function client(saved)
    local ns, messages, handlers, registered = {}, {}, {}, {}
    local frame = {}
    function frame:RegisterEvent(event)
        assert(event == "ADDON_LOADED" or event == "PLAYER_LOGIN")
        registered[event] = true
    end
    function frame:UnregisterEvent(event)
        assert(event == "ADDON_LOADED" or event == "PLAYER_LOGIN")
        registered[event] = nil
    end
    function frame:SetScript(script, handler)
        assert(script == "OnEvent")
        handlers[script] = handler
    end
    setmetatable(frame, {
        __index = function(_, key)
            error("Unexpected frame API: " .. key)
        end,
    })
    local minimap = {
        GetFrameLevel = function()
            return 4
        end,
    }
    local button = { scripts = {}, created = 0 }
    function button:SetSize(w, h)
        assert(w == 32 and h == 32)
    end
    function button:SetPoint(point, parent, relative, x, y)
        assert(
            point == "CENTER"
                and parent == minimap
                and relative == "CENTER"
                and x == -65
                and y == -65
        )
    end
    function button:SetFrameStrata(strata)
        assert(strata == "MEDIUM")
    end
    function button:SetFrameLevel(level)
        assert(level == 12)
    end
    function button:RegisterForClicks(click)
        assert(click == "LeftButtonUp")
    end
    function button:SetNormalTexture(path)
        assert(path:find("TinyShield", 1, true))
    end
    function button:SetHighlightTexture(path)
        assert(path:find("Highlight", 1, true))
    end
    function button:CreateTexture(name, layer)
        assert(name == nil and layer == "OVERLAY")
        return {
            SetTexture = function(_, path)
                assert(path:find("RingBorder", 1, true))
            end,
            SetSize = function(_, w, h)
                assert(w == 40 and h == 40)
            end,
            SetPoint = function(_, point)
                assert(point == "CENTER")
            end,
        }
    end
    function button:SetScript(script, callback)
        assert(script == "OnClick" or script == "OnEnter" or script == "OnLeave")
        self.scripts[script] = callback
    end
    setmetatable(button, {
        __index = function(_, key)
            error("Unexpected minimap button API: " .. key)
        end,
    })
    local tooltip = { visible = false }
    function tooltip:SetOwner(owner, anchor)
        assert(owner == button and anchor == "ANCHOR_LEFT")
    end
    function tooltip:SetText(value)
        self.text = value
    end
    function tooltip:Show()
        self.visible = true
    end
    function tooltip:Hide()
        self.visible = false
    end
    local env = {
        type = type,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        math = { huge = math.huge },
        tonumber = tonumber,
        tostring = tostring,
        string = { format = string.format },
        GuardianDB = saved,
        Minimap = minimap,
        GameTooltip = tooltip,
        GetServerTime = function()
            return 1000
        end,
        SlashCmdList = {},
        C_AddOns = {
            GetAddOnMetadata = function(name, field)
                assert(name == "Guardian" and field == "Version")
                return "0.1.0"
            end,
        },
        CreateFrame = function(kind, ...)
            if kind == "Button" then
                local name, parent = ...
                assert(select("#", ...) == 2 and name == nil and parent == minimap)
                button.created = button.created + 1
                return button
            end
            assert(kind == "Frame" and select("#", ...) == 0)
            return frame
        end,
        print = function(message)
            messages[#messages + 1] = message
        end,
    }
    for _, api in ipairs({ env.SlashCmdList, env.C_AddOns, env.string }) do
        setmetatable(api, {
            __index = function(_, key)
                error("Unexpected API field: " .. key)
            end,
        })
    end
    setmetatable(env, {
        __index = function(_, key)
            if key == "GuardianDB" then
                return nil
            end
            error("Unexpected global: " .. key)
        end,
        __newindex = function(t, key, value)
            assert(
                key == "GuardianDB" or key == "SLASH_GUARDIAN1",
                "Unexpected global write: " .. key
            )
            rawset(t, key, value)
        end,
    })
    -- Execute the actual manifest order with WoW's shared loading arguments.
    for line in io.lines("Guardian.toc") do
        if line:match("%.lua$") then
            local chunk = assert(loadfile(line))
            setfenv(chunk, env)("Guardian", ns)
        end
    end
    local function event(name, kind)
        handlers.OnEvent(frame, kind or "ADDON_LOADED", name)
    end
    return ns, env, event, messages, registered, button
end

test("default settings are fresh tables", function()
    local ns = client()
    local a, b = ns.NormalizeSettings(nil), ns.NormalizeSettings(nil)
    assert(a.enabled and b.enabled and a ~= b)
end)
test("preserves existing settings and unknown fields", function()
    local saved = { enabled = false, custom = "keep" }
    local ns = client()
    assert(ns.NormalizeSettings(saved) == saved)
    assert(saved.enabled == false and saved.custom == "keep")
end)
test("repairs malformed saved settings", function()
    local ns = client()
    for _, saved in ipairs({ false, 42, "bad", { enabled = "bad" } }) do
        assert(ns.NormalizeSettings(saved).enabled == true)
    end
    assert(ns.NormalizeSettings(nil).enabled == true)
end)
test("ignores unrelated addon events without touching saved data", function()
    local saved = { enabled = "not yet normalized" }
    local ns, env, event, _, registered = client(saved)
    event("AnotherAddon")
    assert(not ns.initialized and ns.settings == nil)
    assert(env.GuardianDB == saved and saved.enabled == "not yet normalized")
    assert(registered.ADDON_LOADED)
end)
test("initializes only on own event and unregisters", function()
    local ns, env, event, _, registered = client()
    assert(not ns.initialized and env.GuardianDB == nil)
    event("Guardian")
    assert(ns.initialized and ns.settings == env.GuardianDB and env.GuardianDB.enabled)
    assert(not registered.ADDON_LOADED)
end)
test("load initialization preserves saved disabled preference", function()
    local saved = { enabled = false }
    local ns, env, event = client(saved)
    event("Guardian")
    assert(ns.initialized and env.GuardianDB == saved and not ns.settings.enabled)
end)
test("slash command reports version and initialization state", function()
    local _, env, event, messages = client()
    assert(env.SLASH_GUARDIAN1 == "/guardian")
    env.SlashCmdList.GUARDIAN()
    assert(messages[1] == "Guardian 0.1.0; initialized: false")
    event("Guardian")
    env.SlashCmdList.GUARDIAN()
    assert(messages[2] == "Guardian 0.1.0; initialized: true")
end)
test("minimap launcher initializes once and shares the slash-command dashboard", function()
    local ns, env, event, _, _, button = client()
    assert(button.created == 0 and ns.minimapButton == nil)
    event("OtherAddon")
    assert(button.created == 0)
    event("Guardian")
    assert(button.created == 1 and ns.minimapButton == button)
    local shown = {}
    ns.ShowDashboard = function(d)
        shown[#shown + 1] = d
    end
    button.scripts.OnClick(button)
    env.SlashCmdList.GUARDIAN("ui")
    button.scripts.OnClick(button)
    assert(#shown == 3 and shown[1] == shown[2] and shown[2] == shown[3])
    assert(shown[1].profile == ns.settings and shown[1].demo == nil)
    ns.InstallMinimapButton()
    assert(button.created == 1)
    button.scripts.OnEnter(button)
    assert(env.GameTooltip.visible and env.GameTooltip.text:find("Click to open Guardian", 1, true))
    button.scripts.OnLeave(button)
    assert(not env.GameTooltip.visible)
end)
test("minimap initialization retries at login when the minimap loads later", function()
    local ns, env, event, _, registered, button = client()
    local map = env.Minimap
    env.Minimap = false
    event("Guardian")
    assert(ns.initialized and button.created == 0 and registered.PLAYER_LOGIN)
    env.Minimap = map
    event(nil, "PLAYER_LOGIN")
    assert(button.created == 1 and not registered.PLAYER_LOGIN)
end)
print(string.format("%d tests passed (Lua %s)", passed, _VERSION))
