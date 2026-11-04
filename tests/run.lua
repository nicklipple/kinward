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
        GetCenter = function()
            return 100, 100
        end,
        GetEffectiveScale = function()
            return 2
        end,
    }
    local button = { scripts = {}, created = 0 }
    function button:SetSize(w, h)
        assert(w == 32 and h == 32)
    end
    function button:ClearAllPoints() end
    function button:SetPoint(point, parent, relative, x, y)
        assert(point == "CENTER" and parent == minimap and relative == "CENTER")
        self.x, self.y = x, y
        assert(math.abs(x * x + y * y - 92 * 92) < 0.001)
    end
    function button:RegisterForDrag(mouseButton)
        assert(mouseButton == "LeftButton")
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
        assert(path == "Interface\\AddOns\\Kinward\\KinwardIcon.tga")
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
        assert(
            script == "OnClick"
                or script == "OnEnter"
                or script == "OnLeave"
                or script == "OnDragStart"
                or script == "OnDragStop"
                or script == "OnUpdate"
                or script == "OnHide"
                or script == "OnMouseDown"
        )
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
        math = {
            huge = math.huge,
            pi = math.pi,
            cos = math.cos,
            sin = math.sin,
            atan2 = math.atan2,
        },
        tonumber = tonumber,
        tostring = tostring,
        string = { format = string.format },
        KinwardDB = saved,
        Minimap = minimap,
        GameTooltip = tooltip,
        GetCursorPosition = function()
            return 400, 200
        end,
        GetServerTime = function()
            return 1000
        end,
        SlashCmdList = {},
        C_AddOns = {
            GetAddOnMetadata = function(name, field)
                assert(name == "Kinward" and field == "Version")
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
            if key == "KinwardDB" then
                return nil
            end
            error("Unexpected global: " .. key)
        end,
        __newindex = function(t, key, value)
            assert(
                key == "KinwardDB" or key == "SLASH_KINWARD1",
                "Unexpected global write: " .. key
            )
            rawset(t, key, value)
        end,
    })
    -- Execute the actual manifest order with WoW's shared loading arguments.
    for line in io.lines("Kinward.toc") do
        if line:match("%.lua$") then
            local chunk = assert(loadfile(line))
            setfenv(chunk, env)("Kinward", ns)
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
    assert(env.KinwardDB == saved and saved.enabled == "not yet normalized")
    assert(registered.ADDON_LOADED)
end)
test("initializes only on own event and unregisters", function()
    local ns, env, event, _, registered = client()
    assert(not ns.initialized and env.KinwardDB == nil)
    event("Kinward")
    assert(ns.initialized and ns.settings == env.KinwardDB and env.KinwardDB.enabled)
    assert(not registered.ADDON_LOADED)
end)
test("load initialization preserves saved disabled preference", function()
    local saved = { enabled = false }
    local ns, env, event = client(saved)
    event("Kinward")
    assert(ns.initialized and env.KinwardDB == saved and not ns.settings.enabled)
end)
test("slash command reports version and initialization state", function()
    local _, env, event, messages = client()
    assert(env.SLASH_KINWARD1 == "/kinward")
    env.SlashCmdList.KINWARD()
    assert(messages[1] == "Kinward 0.1.0; initialized: false")
    event("Kinward")
    env.SlashCmdList.KINWARD()
    assert(messages[2] == "Kinward 0.1.0; initialized: true")
end)
test("minimap launcher initializes once and shares the slash-command dashboard", function()
    local ns, env, event, _, _, button = client()
    assert(button.created == 0 and ns.minimapButton == nil)
    event("OtherAddon")
    assert(button.created == 0)
    event("Kinward")
    assert(button.created == 1 and ns.minimapButton == button)
    local shown = {}
    ns.ShowDashboard = function(d)
        shown[#shown + 1] = d
    end
    button.scripts.OnClick(button)
    env.SlashCmdList.KINWARD("ui")
    button.scripts.OnClick(button)
    assert(#shown == 3 and shown[1] == shown[2] and shown[2] == shown[3])
    assert(shown[1].profile == ns.settings and shown[1].demo == nil)
    ns.InstallMinimapButton()
    assert(button.created == 1)
    button.scripts.OnEnter(button)
    assert(env.GameTooltip.visible and env.GameTooltip.text:find("Click to open Kinward", 1, true))
    button.scripts.OnLeave(button)
    assert(not env.GameTooltip.visible)
end)
test("left drag follows the scaled cursor, persists position and suppresses opening", function()
    local ns, env, event, _, _, button = client()
    event("Kinward")
    local shown = 0
    ns.ShowDashboard = function()
        shown = shown + 1
    end
    button.scripts.OnMouseDown(button)
    button.scripts.OnDragStart(button)
    assert(button.x == 92 and button.y == 0)
    assert(not env.GameTooltip.visible)
    env.GetCursorPosition = function()
        return 200, 400
    end
    button.scripts.OnUpdate(button)
    assert(math.abs(button.x) < 0.001 and button.y == 92)
    button.scripts.OnDragStop(button)
    assert(not button.scripts.OnUpdate and ns.settings.minimapAngle == math.pi / 2)
    button.scripts.OnClick(button)
    assert(shown == 0)
    button.scripts.OnMouseDown(button)
    button.scripts.OnClick(button)
    assert(shown == 1)
    local _, _, reload, _, _, restored = client(env.KinwardDB)
    reload("Kinward")
    assert(math.abs(restored.x) < 0.001 and restored.y == 92)
end)
test("invalid saved minimap positions fall back and hiding stops dragging", function()
    for _, value in ipairs({ "bad", math.huge, -math.huge, 0 / 0 }) do
        local ns, _, event, _, _, button = client({ minimapAngle = value })
        event("Kinward")
        assert(button.x < 0 and button.y < 0)
        button.scripts.OnDragStart(button)
        button.scripts.OnHide(button)
        assert(not button.scripts.OnUpdate and ns.settings.minimapAngle == 0)
    end
end)
test("minimap initialization retries at login when the minimap loads later", function()
    local ns, env, event, _, registered, button = client()
    local map = env.Minimap
    env.Minimap = false
    event("Kinward")
    assert(ns.initialized and button.created == 0 and registered.PLAYER_LOGIN)
    env.Minimap = map
    event(nil, "PLAYER_LOGIN")
    assert(button.created == 1 and not registered.PLAYER_LOGIN)
end)
print(string.format("%d tests passed (Lua %s)", passed, _VERSION))
