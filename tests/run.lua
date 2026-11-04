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
        assert(event == "ADDON_LOADED")
        registered[event] = true
    end
    function frame:UnregisterEvent(event)
        assert(event == "ADDON_LOADED")
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
        SlashCmdList = {},
        C_AddOns = {
            GetAddOnMetadata = function(name, field)
                assert(name == "Guardian" and field == "Version")
                return "0.1.0"
            end,
        },
        CreateFrame = function(kind, ...)
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
    local function event(name)
        handlers.OnEvent(frame, "ADDON_LOADED", name)
    end
    return ns, env, event, messages, registered
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
print(string.format("%d tests passed (Lua %s)", passed, _VERSION))
