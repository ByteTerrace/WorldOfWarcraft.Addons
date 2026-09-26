-- ByteTerrace framework: state, events, commands, input, modules, settings.

-- A harness with the framework loaded and a bare addon, not yet started.
local function NewAddOn(options)
    local h = Harness.New(options and options.harness)
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
    falsy(addon.Started, "addon must not start")
    return h.errors[1] or ""
end


test("state ids are sorted by name, whatever the declaration order", function()
    local h, addon = NewAddOn()
    addon:Module("Zeta", { toggle = false, state = { { name = "b", kind = "number", default = 0 }, { name = "a", kind = "number", default = 0 } } })
    Start(h)
    local state = addon.State
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
    throws(function() addon.State:Set("M.mode", "c") end, "expects one of a, b")
    throws(function() addon.State:Set("M.n", 11) end, "at most 10")
    throws(function() addon.State:Set("M.n", "5") end, "expects number")
    h:EnterCombat()
    throws(function() addon.State:Set("M.n", h.env.UnitHealth("player")) end, "secret")
end)

test("saved values load; invalid ones reset, undeclared ones are kept for a module that failed to load", function()
    local h, addon = NewAddOn({ harness = { saved = { TestDB = { ["M.flag"] = true, ["M.mode"] = "zzz", ["Old.row"] = 1 } } } })
    addon:Module("M", { toggle = false, state = {
        { name = "flag", kind = "boolean", default = false },
        { name = "mode", kind = "string", default = "a", values = { "a", "b" } },
    } })
    Start(h)
    eq(addon.State:Get("M.flag"), true)
    eq(addon.State:Get("M.mode"), "a", "invalid saved value falls back to default")
    local saved = h.env.TestDB
    eq(saved["Old.row"], 1, "undeclared key kept (its module may have failed to load)")
    eq(saved["M.mode"], nil, "invalid value dropped")
end)

test("persisted rows store only values that differ from the default", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "flag", kind = "boolean", default = true } } })
    Start(h)
    addon.State:Set("M.flag", false)
    eq(h.env.TestDB["M.flag"], false)
    addon.State:Set("M.flag", true)
    eq(h.env.TestDB["M.flag"], nil)
end)

test("a watcher runs once per publish, not per write", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.State:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    addon.State:BeginBatch()
    addon.State:Set("M.a", 1)
    addon.State:Set("M.b", 1)
    addon.State:Set("M.a", 2)
    addon.State:EndBatch()
    eq(runs, 1)
end)

test("writing a value and writing it back notifies no one", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.State:Watch({ "M.a" }, function() runs = runs + 1 end, true)
    local version = addon.State:Version("M.a")
    addon.State:BeginBatch()
    addon.State:Set("M.a", 5)
    addon.State:Set("M.a", 0)
    addon.State:EndBatch()
    eq(runs, 0)
    eq(addon.State:Version("M.a"), version, "version only moves on a real change")
end)

test("watchers run in registration order and their writes publish in the next round", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local order = {}
    addon.State:Watch({ "M.b" }, function(s) order[#order + 1] = "b=" .. s:Get("M.b") end, true)
    addon.State:Watch({ "M.a" }, function(s) order[#order + 1] = "a"; s:Set("M.b", s:Get("M.a") * 10) end, true)
    addon.State:Watch({ "M.a" }, function() order[#order + 1] = "a2" end, true)
    addon.State:Set("M.a", 3)
    eq(table.concat(order, ","), "a,a2,b=30")
end)

test("a publish that never settles is reported, not looped forever", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 } } })
    Start(h)
    addon.State:Watch({ "M.a" }, function(s) s:Set("M.a", s:Get("M.a") + 1) end, true)
    h:ExpectErrors(1)
    addon.State:Set("M.a", 1)
    truthy(h.errors[1]:find("did not settle", 1, true))
end)

test("a rule runs when its verdict flips, and only then", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    local flips = {}
    addon.State:Rule({ reads = { "M.n" }, when = function(s) return s:Get("M.n") > 5 end,
        changed = function(active) flips[#flips + 1] = tostring(active) end })
    for _, n in ipairs({ 1, 6, 7, 8, 2, 3, 9 }) do
        addon.State:Set("M.n", n)
    end
    eq(table.concat(flips, ","), "true,false,true")
end)

test("a watcher that errors is reported and the others still run", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 } } })
    Start(h)
    local ran = false
    addon.State:Watch({ "M.a" }, function() error("boom") end, true)
    addon.State:Watch({ "M.a" }, function() ran = true end, true)
    h:ExpectErrors(1)
    addon.State:Set("M.a", 1)
    truthy(ran)
end)


test("events register with the client only while handled", function()
    local h, addon = NewAddOn()
    Start(h)
    local frame = addon.Events.Frame
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    local handle = addon.Events:On("PLAYER_TARGET_CHANGED", function() end)
    truthy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    addon.Events:Off(handle)
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
end)

test("unit handlers only receive their unit", function()
    local h, addon = NewAddOn()
    Start(h)
    local seen = {}
    addon.Events:On("UNIT_HEALTH", function(unit) seen[#seen + 1] = "p:" .. unit end, "player")
    addon.Events:On("UNIT_HEALTH", function(unit) seen[#seen + 1] = "t:" .. unit end, "target")
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
    addon.State:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    addon.Events:On("PLAYER_TARGET_CHANGED", function() addon.State:Set("M.a", 1) end)
    addon.Events:On("PLAYER_TARGET_CHANGED", function() addon.State:Set("M.b", 1) end)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(runs, 1)
end)

test("a handler that errors doesn't stop the others", function()
    local h, addon = NewAddOn()
    Start(h)
    local ran = false
    addon.Events:On("PLAYER_TARGET_CHANGED", function() error("boom") end)
    addon.Events:On("PLAYER_TARGET_CHANGED", function() ran = true end)
    h:ExpectErrors(1)
    h:Fire("PLAYER_TARGET_CHANGED")
    truthy(ran)
end)


test("a disabled module registers nothing, and disabling removes what it owned", function()
    local h, addon = NewAddOn()
    local fired = 0
    addon:Module("M", {
        label = "M",
        OnEnable = function(module) module:On("PLAYER_TARGET_CHANGED", function() fired = fired + 1 end) end,
    })
    Start(h)
    local frame = addon.Events.Frame
    truthy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"), "enabled by default")
    addon.State:Set("M.enabled", false)
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"), "unregistered on disable")
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(fired, 0)
    addon.State:Set("M.enabled", true)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(fired, 1)
end)

test("declaring after start is refused", function()
    local h, addon = NewAddOn()
    Start(h)
    throws(function() addon:Module("Late", {}) end, "after start")
end)


test("slash words run their commands with the rest as the argument", function()
    local h, addon = NewAddOn()
    local got
    addon:Module("M", { toggle = false, commands = { { name = "echo", slash = "echo", label = "Echo", run = function(arg) got = arg end } } })
    Start(h)
    h:Slash("/test echo hello world")
    eq(got, "hello world")
    h:Slash("/test")
    truthy(addon.SettingsWindow:IsShown(), "bare slash shows the settings window")
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
    eq(addon.State:Get("M.mode"), "b")
    h:Slash("/test set M.mode nope")
    eq(addon.State:Get("M.mode"), "b", "invalid value refused")
    h:Slash("/test toggle M.enabled")
    eq(addon.State:Get("M.enabled"), false)
    h:Slash("/test set M.enabled on")
    eq(addon.State:Get("M.enabled"), true)
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


test("labels follow the connected controller family", function()
    local h = Harness.New()
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

test("bound buttons run commands; while a map is active, unbound buttons are taken too", function()
    local h, addon = NewAddOn()
    local phases = {}
    addon:Module("M", { toggle = false,
        commands = { { name = "hold", label = "Hold", held = true, run = function(_, phase) phases[#phases + 1] = phase end } },
        bindings = { { map = "menu", source = "gamepad.south", command = "M.hold" } } })
    Start(h)
    h:Gamepad("PAD1", true)
    eq(#phases, 0, "inactive map captures nothing")
    eq(h.propagated[1], "PAD1")
    addon.Input:SetActiveMaps({ "menu" })
    h:Gamepad("PAD1", true)
    h:Gamepad("PAD1", false)
    h:Gamepad("PAD2", true)
    eq(table.concat(phases, ","), "down,up")
    eq(#h.propagated, 1, "PAD2 is unbound but taken: the client ignores the script's return value")
    addon.Input:SetActiveMaps({})
    h:Gamepad("PAD2", true)
    eq(h.propagated[2], "PAD2", "with no active map, nothing is captured")
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
    addon.Input:SetActiveMaps({ "one" })
    h:Gamepad("PAD1", true)
    addon.Input:SetActiveMaps({ "one", "two" }) -- "two" overrides south, so a's hold is canceled
    h:Gamepad("PAD1", false)
    eq(table.concat(log, ","), "a:down,a:cancel")
    addon.Input:SetActiveMaps({ "two" })
    h:Gamepad("PAD1", true)
    addon.Input:SetActiveMaps({ "two" })
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
    eq(addon.State:Get("M.mode"), "b", "panel writes go through state")
end)

-- The settings pages, " | " between them: "Name < Parent: [Header] Module.row ...".
local function Pages(h)
    local lines = {}
    for _, page in ipairs(h.settingsPages) do
        local parts = {}
        for _, entry in ipairs(page.entries) do
            parts[#parts + 1] = entry.header and ("[" .. entry.header .. "]") or entry.variable:gsub("^TestApp_", "")
        end
        lines[#lines + 1] = page.name .. (page.parent and (" < " .. page.parent) or "") .. ": " .. table.concat(parts, " ")
    end
    return table.concat(lines, " | ")
end

test("module pages and sections organize the panel; debug closes the main page", function()
    local h, addon = NewAddOn()
    addon:Module("Alpha", { label = "Alpha", state = {
        { name = "size", kind = "string", default = "a", values = { "a", "b" }, label = "Size" },
        { name = "hidden", kind = "boolean", default = false },
        { name = "loud", kind = "boolean", default = false, label = "Loud", section = "Noise" },
    } })
    addon:Module("Beta", { label = "Beta", page = "Extras" })
    addon:Module("Gamma", { toggle = false, page = "Other", section = "Gamma things", state = {
        { name = "n", kind = "number", default = 1, min = 1, max = 3, label = "N" },
    } })
    addon:Module("Delta", { label = "Extras", page = "Extras" })
    addon:Module("Echo", { label = "Test AddOn" })
    addon:Module("Quiet", { toggle = false, state = { { name = "on", kind = "boolean", default = true, label = "On" } } })
    Start(h)
    eq(Pages(h), table.concat({
        "Test AddOn: [Alpha] Alpha.enabled Alpha.size [Noise] Alpha.loud Echo.enabled Quiet.on [Advanced] addon.debug",
        "Extras < Test AddOn: [Beta] Beta.enabled Delta.enabled",
        "Other < Test AddOn: [Gamma things] Gamma.n",
    }, " | "), "a header that repeats its page's name is left out, and a module with no label has none")
    eq(h.category.name, "Test AddOn", "only the main page is the addon's category")
    h.settings["TestApp_Gamma.n"]:SetValue(2)
    eq(addon.State:Get("Gamma.n"), 2, "a control on a subcategory writes through state too")
end)

test("page and section must be strings", function()
    local h, addon = NewAddOn()
    throws(function() addon:Module("M", { label = "M", page = 1 }) end, "page must be a string")
    throws(function() addon:Module("N", { label = "N", section = true }) end, "section must be a string")
    addon:Module("R", { toggle = false, state = { { name = "x", kind = "boolean", default = false, label = "X", section = 2 } } })
    truthy(StartRefused(h, addon):find("R.x: section must be a string", 1, true))
end)

test("labeled bounded numbers get sliders; a labeled number without bounds is refused", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 5, min = 1, max = 10, step = 1, label = "N" } } })
    Start(h)
    eq(h.settings["TestApp_M.n"].control, "slider")
    local h2, addon2 = NewAddOn()
    addon2:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 1, label = "N" } } })
    local err = StartRefused(h2, addon2)
    truthy(err:find("needs min and max", 1, true))
end)

test("a control refreshes when its row changes elsewhere", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M" })
    Start(h)
    h:Slash("/test toggle M.enabled")
    eq(h.notified["TestApp_M.enabled"], 1)
end)

test("a handler removed mid-dispatch doesn't receive the rest of that dispatch", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false })
    Start(h)
    local ran, second = {}, nil
    m:On("PLAYER_TARGET_CHANGED", function() ran[#ran + 1] = "a"; m:Off(second) end)
    second = m:On("PLAYER_TARGET_CHANGED", function() ran[#ran + 1] = "b" end)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(table.concat(ran, ","), "a")
end)

test("a module stopped directly inside its own handler runs no more of that dispatch", function()
    local h, addon = NewAddOn()
    local count = 0
    local module
    module = addon:Module("M", { toggle = false, OnEnable = function(m)
        m:On("PLAYER_TARGET_CHANGED", function() module:SetEnabled(false) end)
        m:On("PLAYER_TARGET_CHANGED", function() count = count + 1 end)
    end })
    Start(h)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(count, 0)
    falsy(module.Enabled)
end)

test("switching a module off through its row takes effect when the batch publishes", function()
    local h, addon = NewAddOn()
    local count = 0
    local module = addon:Module("M", { label = "M", OnEnable = function(m)
        m:On("PLAYER_TARGET_CHANGED", function() addon.State:Set("M.enabled", false) end)
        m:On("PLAYER_TARGET_CHANGED", function() count = count + 1 end)
    end })
    Start(h)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(count, 1, "the rest of the dispatch that wrote the row still runs, like any other write")
    falsy(module.Enabled, "stopped at publish")
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(count, 1, "and nothing after it")
end)

test("a long watcher chain that settles isn't reported, and every version moves", function()
    local h, addon = NewAddOn()
    local rows = {}
    for i = 1, 9 do rows[i] = { name = "r" .. i, kind = "number", default = 0, persist = false } end
    addon:Module("C", { toggle = false, state = rows })
    Start(h)
    local s = addon.State
    for i = 1, 8 do
        local from, to = s:Id("C.r" .. i), s:Id("C.r" .. (i + 1))
        s:Watch({ from }, function(st) st:Set(to, st.Values[from]) end, true)
    end
    s:Set("C.r1", 5)
    eq(s:Get("C.r9"), 5)
    eq(s:Version("C.r9"), 1)
end)

test("a secret unit token in a payload can't break publication", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false, state = { { name = "x", kind = "number", default = 0, persist = false } } })
    Start(h)
    local seen, filtered = 0, 0
    m:Watch({ "x" }, function() seen = seen + 1 end, true)
    for _, unit in ipairs({ "player", "target", "focus" }) do
        m:On("UNIT_AURA", function() filtered = filtered + 1 end, unit)
    end
    h:Fire("UNIT_AURA", Secret("nameplate3"))
    eq(filtered, 0, "filtered handlers can't claim a secret unit")
    m:Set("x", 1)
    eq(seen, 1, "the batch closed, so a write publishes at once")
end)

test("module Get and Set accept a resolved id", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false, state = { { name = "x", kind = "number", default = 0 } } })
    Start(h)
    local id = m:Id("x")
    m:Set(id, 3)
    eq(m:Get(id), 3)
end)

test("non-finite numbers are refused", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    throws(function() m:Set("n", 0 / 0) end, "finite")
    throws(function() m:Set("n", math.huge) end, "finite")
    h:Slash("/test set M.n 1e999")
    eq(m:Get("n"), 0)
end)

test("slash words must be lowercase", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, commands = { { name = "go", slash = "Go", label = "Go", run = function() end } } })
    truthy(StartRefused(h, addon):find("must be lowercase", 1, true))
end)

test("a module spec shared by two addons isn't changed by either", function()
    local spec = { toggle = false, commands = { { name = "go", label = "Go", run = function() end } } }
    local h1, a1 = NewAddOn({ name = "A1" })
    a1:Module("Lib", spec)
    local h2, a2 = NewAddOn({ name = "A2" })
    a2:Module("Lib", spec)
    h1:Fire("ADDON_LOADED", "A1")
    h2:Fire("ADDON_LOADED", "A2")
    eq(spec.commands[1].name, "go")
    truthy(a2.Commands.Ids["Lib.go"])
end)

test("row and module names must be identifiers", function()
    local h, addon = NewAddOn()
    throws(function() addon:Module("M", { toggle = false, state = { { name = "a.b", kind = "number", default = 0 } } }) end, "identifier")
    throws(function() addon:Module("Bad.Name", {}) end, "identifier")
end)

test("a command is one batch", function()
    local h, addon = NewAddOn()
    local m
    m = addon:Module("M", { toggle = false,
        state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } },
        commands = { { name = "both", slash = "both", label = "Both", run = function() m:Set("a", 1); m:Set("b", 1) end } } })
    Start(h)
    local seen = {}
    m:Watch({ "a", "b" }, function() seen[#seen + 1] = m:Get("a") .. m:Get("b") end, true)
    h:Slash("/test both")
    eq(table.concat(seen, ","), "11")
end)

test("a cancel handler that switches maps wins over the switch that canceled it", function()
    local h, addon = NewAddOn()
    local phases = {}
    addon:Module("M", { toggle = false,
        commands = {
            { name = "hold", label = "Hold", held = true, run = function(_, phase)
                phases[#phases + 1] = phase
                if phase == "cancel" then addon.Input:SetActiveMaps({ "a", "b" }) end end },
            { name = "other", label = "Other", run = function() end } },
        bindings = { { map = "a", source = "gamepad.south", command = "M.hold" },
                     { map = "b", source = "gamepad.east", command = "M.other" } } })
    Start(h)
    addon.Input:SetActiveMaps({ "a" })
    h:Gamepad("PAD1", true)
    addon.Input:SetActiveMaps({ "b" })
    h:Gamepad("PAD1", false)
    h:Gamepad("PAD1", true)
    eq(table.concat(phases, ","), "down,cancel,down", "map a is active again, so south still reaches hold")
end)

test("registration changes only when the wanted registration does", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M", OnEnable = function(m)
        for _ = 1, 5 do m:On("PLAYER_TARGET_CHANGED", function() end) end
    end })
    Start(h)
    local frame = addon.Events.Frame
    Harness.State(frame).calls = {}
    addon.State:Set("M.enabled", false)
    eq(Harness.State(frame).calls.UnregisterEvent, 1, "one unregister for five handlers")
    eq(Harness.State(frame).calls.RegisterEvent, nil)
end)

test("an unbalanced EndBatch is an error", function()
    local h, addon = NewAddOn()
    Start(h)
    throws(function() addon.State:EndBatch() end, "without BeginBatch")
end)

test("controller capture works in combat: the capture frame isn't a protected frame", function()
    local h, addon = NewAddOn()
    local ran = 0
    addon:Module("M", { toggle = false, commands = { { name = "go", label = "Go", run = function() ran = ran + 1 end } },
        bindings = { { map = "a", source = "gamepad.south", command = "M.go" } } })
    Start(h)
    h:EnterCombat()
    addon.Input:SetActiveMaps({ "a" })
    eq(#h.blocked, 0, "nothing blocked")
    h:Gamepad("PAD1", true)
    eq(ran, 1)
end)


test("a module that fails to start can't stop the others or wedge publication", function()
    local h, addon = NewAddOn()
    addon:Module("Broken", { toggle = false, active = { reads = { "Nope.row" }, when = function() return true end } })
    local later = addon:Module("Later", { toggle = false, state = { { name = "x", kind = "number", default = 0, persist = false } } })
    h:ExpectErrors("unknown state row Nope.row")
    Start(h)
    truthy(later.Enabled, "later modules still start")
    local seen = 0
    addon.State:Watch({ "Later.x" }, function() seen = seen + 1 end, true)
    addon.State:Set("Later.x", 1)
    eq(seen, 1, "the start batch closed, so a write publishes at once")
end)

test("a row spec shared by two addons in one client writes to each addon's own SavedVariables", function()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.ADB, h.declared.BDB = true, true
    local shared = { toggle = false, state = { { name = "n", kind = "number", default = 0 } } }
    local a = h.env.ByteTerrace.NewAddOn({ name = "A", title = "A", version = "1", savedVariable = "ADB" })
    local b = h.env.ByteTerrace.NewAddOn({ name = "B", title = "B", version = "1", savedVariable = "BDB" })
    a:Module("S", shared)
    b:Module("S", shared)
    h:Fire("ADDON_LOADED", "A")
    h:Fire("ADDON_LOADED", "B")
    a.State:Set("S.n", 5)
    eq(h.env.ADB["S.n"], 5)
    eq(h.env.BDB["S.n"], nil)
    eq(shared.state[1].store, nil, "the caller's spec is untouched")
end)

test("a watcher registered mid-batch doesn't react to writes made before it existed", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "x", kind = "number", default = 0, persist = false } } })
    local fired = 0
    addon:Module("Reader", { toggle = false, OnEnable = function(m)
        m:Watch({ "M.x" }, function() fired = fired + 1 end, true)
    end })
    addon:Module("Writer", { toggle = false, OnEnable = function() addon.State:Set("M.x", 1) end })
    Start(h)
    eq(fired, 1, "the write came after the watcher: it fires")

    local h2, addon2 = NewAddOn()
    addon2:Module("M", { toggle = false, state = { { name = "x", kind = "number", default = 0, persist = false } } })
    local fired2 = 0
    addon2:Module("Writer", { toggle = false, OnEnable = function() addon2.State:Set("M.x", 1) end })
    addon2:Module("Reader", { toggle = false, OnEnable = function(m)
        m:Watch({ "M.x" }, function() fired2 = fired2 + 1 end, true)
    end })
    Start(h2)
    eq(fired2, 0, "the write came before the watcher: it doesn't")
end)

test("a rule's first verdict doesn't depend on module declaration order", function()
    for _, readerFirst in ipairs({ true, false }) do
        local h, addon = NewAddOn()
        local calls = 0
        local reader = { toggle = false, OnEnable = function(m)
            m:Rule({ reads = { "W.flag" }, when = function(s) return s:Get("W.flag") end, changed = function() calls = calls + 1 end })
        end }
        local writer = { toggle = false, state = { { name = "flag", kind = "boolean", default = false, persist = false } },
            OnEnable = function(m) m:Set("flag", true) end }
        if readerFirst then
            addon:Module("R", reader); addon:Module("W", writer)
        else
            addon:Module("W", writer); addon:Module("R", reader)
        end
        Start(h)
        eq(calls, 0, readerFirst and "reader declared first" or "writer declared first")
    end
end)

test("a taken slash alias is reported and skipped; the addon still starts", function()
    local h, addon = NewAddOn()
    rawset(h.env, "SLASH_SOMEONEELSE1", "/other")
    rawset(h.env, "SLASH_SOMEONEELSE2", "/TEST")
    h.env.SlashCmdList.SOMEONEELSE = function() end
    h:ExpectErrors("already taken by SLASH_SOMEONEELSE2")
    Start(h)
    truthy(addon.Started)
end)

test("errors from module Set point at the caller", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    local ok, err = pcall(function() m:Set("n", "bad") end)
    falsy(ok)
    falsy(tostring(err):find("AddOn.lua", 1, true), tostring(err))
end)

test("reserved module names are refused", function()
    local h, addon = NewAddOn()
    throws(function() addon:Module("addon", {}) end, "reserved")
    throws(function() addon:Module("combat", {}) end, "reserved")
end)

test("number rows honor their step", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 2, min = 0, max = 10, step = 2 } } })
    Start(h)
    throws(function() m:Set("n", 3) end, "multiple of 2")
    m:Set("n", 4)
    eq(m:Get("n"), 4)
end)

test("a renamed row's stale key is dropped; a failed module's keys are kept", function()
    local h, addon = NewAddOn({ harness = { saved = { TestDB = { ["M.old"] = 1, ["Gone.row"] = 2 } } } })
    addon:Module("M", { toggle = false, state = { { name = "new", kind = "number", default = 0 } } })
    Start(h)
    eq(h.env.TestDB["M.old"], nil, "stale key under a declared module")
    eq(h.env.TestDB["Gone.row"], 2, "module that didn't load keeps its key")
end)

test("a panel write doesn't notify the panel back; other writes do", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M" })
    Start(h)
    h.settings["TestApp_M.enabled"]:SetValue(false)
    eq(h.notified["TestApp_M.enabled"], nil)
    h:Slash("/test toggle M.enabled")
    eq(h.notified["TestApp_M.enabled"], 1)
end)

test("a stopped module's runtime rows return to their defaults", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { label = "M", state = { { name = "fact", kind = "boolean", default = false, persist = false } },
        OnEnable = function(mod) mod:Set("fact", true) end })
    Start(h)
    eq(m:Get("fact"), true)
    addon.State:Set("M.enabled", false)
    eq(m:Get("fact"), false)
end)

test("a handler for an unknown event leaves no trace", function()
    local h, addon = NewAddOn()
    Start(h)
    local ran = false
    throws(function() addon.Events:On("NOT_A_REAL_EVENT", function() ran = true end) end)
    addon.Events:Dispatch("NOT_A_REAL_EVENT")
    falsy(ran, "the refused handler is gone")
end)

test("addon:Batch publishes once", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { toggle = false, state = { { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.State:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    addon:Batch(function() m:Set("a", 1); m:Set("b", 1) end)
    eq(runs, 1)
end)
