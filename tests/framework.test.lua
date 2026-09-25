-- ByteTerrace framework: state, events, commands, input, modules, settings.

-- A harness with the framework loaded and a bare addon, not yet started.
local function NewAddOn(options)
    local h = Harness.new(options and options.harness)
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local spec = { name = "TestApp", title = "Test AddOn", version = "1.0", savedVariable = "TestDB", slash = { "/test" } }
    for key, value in pairs(options or {}) do
        if key ~= "harness" then spec[key] = value end
    end
    local addon = h.env.ByteTerrace.NewAddOn(spec)
    return h, addon
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp")
end

-- Starts an addon whose declarations are invalid. Compile refuses; the refusal reaches the error
-- handler (the ADDON_LOADED dispatch isolates it) and the addon never starts.
local function StartRefused(h, addon)
    h:ExpectErrors(1)
    Start(h)
    falsy(addon.started, "addon must not start")
    return h.errors[1] or ""
end

-- State --------------------------------------------------------------------

test("state ids are sorted by name, whatever the declaration order", function()
    local h, addon = NewAddOn()
    addon:Module("Zeta", { toggle = false, state = { { name = "b", kind = "number", default = 0 }, { name = "a", kind = "number", default = 0 } } })
    Start(h)
    local state = addon.state
    truthy(state:Id("Zeta.a") < state:Id("Zeta.b"))
end)

test("compile reports every bad declaration at once", function()
    local h, addon = NewAddOn()
    addon:Module("Bad", { toggle = false, state = {
        { name = "kind", kind = "table", default = {} },
        { name = "default", kind = "boolean", default = "yes" },
        { name = "enum", kind = "string", default = "c", values = { "a", "b" } },
    } })
    local err = StartRefused(h, addon)
    truthy(tostring(err):find("Bad.kind: unknown kind table", 1, true), "reports kind")
    truthy(tostring(err):find("Bad.default: default expects boolean", 1, true), "reports default")
    truthy(tostring(err):find("Bad.enum: default expects one of a, b", 1, true), "reports enum")
end)

test("writes are validated and secrets are refused", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = {
        { name = "mode", kind = "string", default = "a", values = { "a", "b" } },
        { name = "n", kind = "number", default = 1, min = 0, max = 10 },
    } })
    Start(h)
    throws(function() addon.state:Set("M.mode", "c") end, "expects one of a, b")
    throws(function() addon.state:Set("M.n", 11) end, "at most 10")
    throws(function() addon.state:Set("M.n", "5") end, "expects number")
    h:EnterCombat()
    throws(function() addon.state:Set("M.n", h.env.UnitHealth("player")) end, "secret")
end)

test("saved values load, and undeclared or invalid ones are dropped", function()
    local h, addon = NewAddOn({ harness = { saved = { TestDB = { ["M.flag"] = true, ["M.mode"] = "zzz", ["Old.row"] = 1 } } } })
    addon:Module("M", { toggle = false, state = {
        { name = "flag", kind = "boolean", default = false },
        { name = "mode", kind = "string", default = "a", values = { "a", "b" } },
    } })
    Start(h)
    eq(addon.state:Get("M.flag"), true)
    eq(addon.state:Get("M.mode"), "a", "invalid saved value falls back to default")
    local saved = h.env.TestDB
    eq(saved["Old.row"], nil, "undeclared row dropped")
    eq(saved["M.mode"], nil, "invalid value dropped")
end)

test("persisted rows store only values that differ from the default", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "flag", kind = "boolean", default = true } } })
    Start(h)
    addon.state:Set("M.flag", false)
    eq(h.env.TestDB["M.flag"], false)
    addon.state:Set("M.flag", true)
    eq(h.env.TestDB["M.flag"], nil)
end)

test("a watcher runs once per publish, not per write", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.state:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    addon.state:BeginBatch()
    addon.state:Set("M.a", 1)
    addon.state:Set("M.b", 1)
    addon.state:Set("M.a", 2)
    addon.state:EndBatch()
    eq(runs, 1)
end)

test("writing a value and writing it back notifies no one", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.state:Watch({ "M.a" }, function() runs = runs + 1 end, true)
    local version = addon.state:Version("M.a")
    addon.state:BeginBatch()
    addon.state:Set("M.a", 5)
    addon.state:Set("M.a", 0)
    addon.state:EndBatch()
    eq(runs, 0)
    eq(addon.state:Version("M.a"), version, "version only moves on a real change")
end)

test("watchers run in registration order and their writes publish in the next round", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local order = {}
    addon.state:Watch({ "M.b" }, function(s) order[#order + 1] = "b=" .. s:Get("M.b") end, true)
    addon.state:Watch({ "M.a" }, function(s) order[#order + 1] = "a"; s:Set("M.b", s:Get("M.a") * 10) end, true)
    addon.state:Watch({ "M.a" }, function() order[#order + 1] = "a2" end, true)
    addon.state:Set("M.a", 3)
    eq(table.concat(order, ","), "a,a2,b=30")
end)

test("a publish that never settles is reported, not looped forever", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 } } })
    Start(h)
    addon.state:Watch({ "M.a" }, function(s) s:Set("M.a", s:Get("M.a") + 1) end, true)
    h:ExpectErrors(1)
    addon.state:Set("M.a", 1)
    truthy(h.errors[1]:find("did not settle", 1, true))
end)

test("a rule runs when its verdict flips, and only then", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    local flips = {}
    addon.state:Rule({ reads = { "M.n" }, when = function(s) return s:Get("M.n") > 5 end,
        changed = function(active) flips[#flips + 1] = tostring(active) end })
    for _, n in ipairs({ 1, 6, 7, 8, 2, 3, 9 }) do
        addon.state:Set("M.n", n)
    end
    eq(table.concat(flips, ","), "true,false,true")
end)

test("a watcher that errors is reported and the others still run", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 } } })
    Start(h)
    local ran = false
    addon.state:Watch({ "M.a" }, function() error("boom") end, true)
    addon.state:Watch({ "M.a" }, function() ran = true end, true)
    h:ExpectErrors(1)
    addon.state:Set("M.a", 1)
    truthy(ran)
end)

-- Events -------------------------------------------------------------------

test("events register with the client only while handled", function()
    local h, addon = NewAddOn()
    Start(h)
    local frame = addon.events.frame
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    local handle = addon.events:On("PLAYER_TARGET_CHANGED", function() end)
    truthy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    addon.events:Off(handle)
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
end)

test("unit handlers only receive their unit", function()
    local h, addon = NewAddOn()
    Start(h)
    local seen = {}
    addon.events:On("UNIT_HEALTH", function(unit) seen[#seen + 1] = "p:" .. unit end, "player")
    addon.events:On("UNIT_HEALTH", function(unit) seen[#seen + 1] = "t:" .. unit end, "target")
    h:Fire("UNIT_HEALTH", "player")
    h:Fire("UNIT_HEALTH", "target")
    h:Fire("UNIT_HEALTH", "focus")
    eq(table.concat(seen, ","), "p:player,t:target")
end)

test("a dispatch is one state batch", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.state:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    addon.events:On("PLAYER_TARGET_CHANGED", function() addon.state:Set("M.a", 1) end)
    addon.events:On("PLAYER_TARGET_CHANGED", function() addon.state:Set("M.b", 1) end)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(runs, 1)
end)

test("a handler that errors doesn't stop the others", function()
    local h, addon = NewAddOn()
    Start(h)
    local ran = false
    addon.events:On("PLAYER_TARGET_CHANGED", function() error("boom") end)
    addon.events:On("PLAYER_TARGET_CHANGED", function() ran = true end)
    h:ExpectErrors(1)
    h:Fire("PLAYER_TARGET_CHANGED")
    truthy(ran)
end)

-- Modules ------------------------------------------------------------------

test("a disabled module registers nothing, and disabling removes what it owned", function()
    local h, addon = NewAddOn()
    local fired = 0
    addon:Module("M", {
        label = "M",
        OnEnable = function(module) module:On("PLAYER_TARGET_CHANGED", function() fired = fired + 1 end) end,
    })
    Start(h)
    local frame = addon.events.frame
    truthy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"), "enabled by default")
    addon.state:Set("M.enabled", false)
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"), "unregistered on disable")
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(fired, 0)
    addon.state:Set("M.enabled", true)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(fired, 1)
end)

test("declaring after start is refused", function()
    local h, addon = NewAddOn()
    Start(h)
    throws(function() addon:Module("Late", {}) end, "after start")
end)

-- Commands -----------------------------------------------------------------

test("slash words run their commands with the rest as the argument", function()
    local h, addon = NewAddOn()
    local got
    addon:Module("M", { toggle = false, commands = { { name = "echo", slash = "echo", label = "Echo", run = function(arg) got = arg end } } })
    Start(h)
    h:Slash("/test echo hello world")
    eq(got, "hello world")
    h:Slash("/test")
    eq(#h.opened, 1, "bare slash opens settings")
end)

test("help lists every slash command", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, commands = { { name = "echo", slash = "echo", label = "Echo things", run = function() end } } })
    Start(h)
    h:Slash("/test help")
    local text = table.concat(h.printed, "\n")
    truthy(text:find("/test echo - Echo things", 1, true))
    truthy(text:find("/test set - Set a setting", 1, true))
end)

test("set and toggle change settings from text", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M", state = { { name = "mode", kind = "string", default = "a", values = { "a", "b" }, label = "Mode" } } })
    Start(h)
    h:Slash("/test set M.mode b")
    eq(addon.state:Get("M.mode"), "b")
    h:Slash("/test set M.mode nope")
    eq(addon.state:Get("M.mode"), "b", "invalid value refused")
    h:Slash("/test toggle M.enabled")
    eq(addon.state:Get("M.enabled"), false)
    h:Slash("/test set M.enabled on")
    eq(addon.state:Get("M.enabled"), true)
end)

test("duplicate slash words are refused at compile", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, commands = {
        { name = "one", slash = "x", label = "One", run = function() end },
        { name = "two", slash = "x", label = "Two", run = function() end },
    } })
    local err = StartRefused(h, addon)
    truthy(tostring(err):find("slash word 'x' is taken", 1, true))
end)

-- Input --------------------------------------------------------------------

test("labels follow the connected controller family", function()
    local h = Harness.new()
    h:LoadFiles("ByteTerrace_Core")
    local Input = h.env.ByteTerrace.Input
    eq(Input.Label("gamepad.south"), "South", "no controller: positional")
    h.labelStyle = "Letters"
    eq(Input.Label("gamepad.south"), "A")
    h.labelStyle = "Shapes"
    eq(Input.Label("gamepad.south"), "Cross")
    h.labelStyle = "Reverse"
    eq(Input.Label("gamepad.south"), "B")
    eq(Input.Label("gamepad.dpadUp"), "D-pad Up")
end)

test("bound buttons run commands; unbound buttons propagate", function()
    local h, addon = NewAddOn()
    local phases = {}
    addon:Module("M", { toggle = false,
        commands = { { name = "hold", label = "Hold", held = true, run = function(_, phase) phases[#phases + 1] = phase end } },
        bindings = { { map = "menu", source = "gamepad.south", command = "M.hold" } } })
    Start(h)
    h:Gamepad("PAD1", true)
    eq(#phases, 0, "inactive map captures nothing")
    eq(h.propagated[1], "PAD1")
    addon.input:SetActiveMaps({ "menu" })
    h:Gamepad("PAD1", true)
    h:Gamepad("PAD1", false)
    h:Gamepad("PAD2", true)
    eq(table.concat(phases, ","), "down,up")
    eq(h.propagated[2], "PAD2")
end)

test("a release goes to its press's command; a held command whose map goes away is canceled", function()
    local h, addon = NewAddOn()
    local log = {}
    addon:Module("M", { toggle = false,
        commands = {
            { name = "a", label = "A", held = true, run = function(_, phase) log[#log + 1] = "a:" .. phase end },
            { name = "b", label = "B", held = true, run = function(_, phase) log[#log + 1] = "b:" .. phase end },
        },
        bindings = {
            { map = "one", source = "gamepad.south", command = "M.a" },
            { map = "two", source = "gamepad.south", command = "M.b" },
        } })
    Start(h)
    addon.input:SetActiveMaps({ "one" })
    h:Gamepad("PAD1", true)
    addon.input:SetActiveMaps({ "one", "two" }) -- "two" overrides south, so a's hold is canceled
    h:Gamepad("PAD1", false)
    eq(table.concat(log, ","), "a:down,a:cancel")
    addon.input:SetActiveMaps({ "two" })
    h:Gamepad("PAD1", true)
    addon.input:SetActiveMaps({ "two" })
    h:Gamepad("PAD1", false)
    eq(table.concat(log, ","), "a:down,a:cancel,b:down,b:up")
end)

test("bindings to unknown sources or commands are refused at compile", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, bindings = {
        { map = "menu", source = "gamepad.nope", command = "M.missing" },
    } })
    local err = StartRefused(h, addon)
    truthy(tostring(err):find("unknown source gamepad.nope", 1, true))
    truthy(tostring(err):find("unknown command M.missing", 1, true))
end)

-- Settings -----------------------------------------------------------------

test("the settings panel is generated from labeled persisted rows, in declaration order", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "Module M", state = {
        { name = "mode", kind = "string", default = "a", values = { "a", "b" }, label = "Mode" },
        { name = "hidden", kind = "boolean", default = false },
        { name = "runtime", kind = "boolean", default = false, label = "Runtime", persist = false },
    } })
    Start(h)
    eq(table.concat(h.settingsOrder, ","), "TestApp_M.enabled,TestApp_M.mode,TestApp_addon.debug")
    eq(h.settings["TestApp_M.mode"].control, "dropdown")
    h.settings["TestApp_M.mode"]:SetValue("b")
    eq(addon.state:Get("M.mode"), "b", "panel writes go through state")
end)
