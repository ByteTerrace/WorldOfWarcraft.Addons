-- ByteTerrace framework: state, events, commands, input, modules, settings.

local Kit = use("framework")

local NewAddOn = Kit.NewAddOn
local Start = Kit.Start
local StartRefused = Kit.StartRefused

test("state ids are sorted by name, whatever the declaration order", function()
    local h, addon = NewAddOn()

    addon:Module("Zeta", { state = { { default = 0, kind = "number", name = "b" }, { default = 0, kind = "number", name = "a" } }, toggle = false })
    Start(h)
    local state = addon.State

    truthy(state:Id("Zeta.a") < state:Id("Zeta.b"))
end)

test("compile reports every bad declaration at once", function()
    local h, addon = NewAddOn()

    addon:Module("Bad", { state = {
            { default = {}, kind = "table", name = "kind" },
            { default = "yes", kind = "boolean", name = "default" },
            { default = "c", kind = "string", name = "enum", values = { "a", "b" } },
            { default = 0, kind = "number", name = "numberEnum", values = { "a" } },
            { default = false, kind = "boolean", min = 0, name = "boundedFlag" },
            { default = 5, kind = "number", max = 1, min = 10, name = "inverted" },
            { default = "", kind = "string", name = "labels", valueLabels = { a = "A" } },
            { default = false, kind = "boolean", name = "realm", scope = "realm" },
            { default = false, kind = "boolean", lockedBy = 3, name = "lock" },
        },
        toggle = false })
    local err = tostring(StartRefused(h, addon))

    truthy(err:find("Bad.kind: unknown kind table", 1, true), "reports kind")
    truthy(err:find("Bad.default: default expects boolean", 1, true), "reports default")
    truthy(err:find("Bad.enum: default expects one of a, b", 1, true), "reports enum")
    truthy(err:find("Bad.numberEnum: values only apply to string rows", 1, true), err)
    truthy(err:find("Bad.boundedFlag: min / max / step only apply to number rows", 1, true), err)
    truthy(err:find("Bad.inverted: min must not exceed max", 1, true), err)
    truthy(err:find("Bad.labels: valueLabels needs values", 1, true), err)
    truthy(err:find("Bad.realm: unknown scope realm", 1, true), err)
    truthy(err:find("Bad.lock: lockedBy must be a row name", 1, true), err)
end)

test("writes are validated and secrets are refused", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = {
            { default = "a", kind = "string", name = "mode", values = { "a", "b" } },
            { default = 1, kind = "number", max = 10, min = 0, name = "n" },
        },
        toggle = false })
    Start(h)
    throws(function() addon.State:Set("M.mode", "c") end, "expects one of a, b")
    throws(function() addon.State:Set("M.n", 11) end, "at most 10")
    throws(function() addon.State:Set("M.n", -1) end, "at least 0")
    throws(function() addon.State:Set("M.n", "5") end, "expects number")
    throws(function() addon.State:Set("M.missing", 1) end, "unknown state row M.missing")
    throws(function() addon.State:Set(999, 1) end, "unknown state row id 999")
    throws(function() addon.State:Toggle("M.n") end, "M.n is not boolean")
    eq(addon.State:Get("M.n"), 1, "a refused write changes nothing")
    h:EnterCombat()
    throws(function() addon.State:Set("M.n", h.env.UnitHealth("player")) end, "secret")
end)

test("saved values load; invalid and renamed ones reset, undeclared ones are kept for a module that failed to load", function()
    local h, addon = NewAddOn({ harness = { saved = { TestDB = {
        ["M.flag"] = true, ["M.mode"] = "zzz", ["M.old"] = 1, ["Old.row"] = 1,
    } } } })

    addon:Module("M", { state = {
            { default = false, kind = "boolean", name = "flag" },
            { default = "a", kind = "string", name = "mode", values = { "a", "b" } },
        },
        toggle = false })
    Start(h)
    eq(addon.State:Get("M.flag"), true)
    eq(addon.State:Get("M.mode"), "a", "invalid saved value falls back to default")
    local saved = h.env.TestDB

    eq(saved["Old.row"], 1, "undeclared key kept (its module may have failed to load)")
    eq(saved["M.mode"], nil, "invalid value dropped")
    eq(saved["M.old"], nil, "a declared module's stale key (a renamed row) is dropped")
end)

test("persisted rows store only values that differ from the default", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = true, kind = "boolean", name = "flag" } }, toggle = false })
    Start(h)
    addon.State:Set("M.flag", false)
    eq(h.env.TestDB["M.flag"], false)
    addon.State:Set("M.flag", true)
    eq(h.env.TestDB["M.flag"], nil)
end)

test("a watcher runs once per publish, not per write", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "a" }, { default = 0, kind = "number", name = "b" } }, toggle = false })
    Start(h)
    local runs = 0

    addon.State:Watch({ "M.a", "M.b" }, function() runs = (runs + 1) end, true)
    addon.State:BeginBatch()
    addon.State:Set("M.a", 1)
    addon.State:Set("M.b", 1)
    addon.State:Set("M.a", 2)
    addon.State:EndBatch()
    eq(runs, 1)
end)

test("writing a value and writing it back notifies no one", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "a" } }, toggle = false })
    Start(h)
    local runs = 0

    addon.State:Watch({ "M.a" }, function() runs = (runs + 1) end, true)
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

    addon:Module("M", { state = { { default = 0, kind = "number", name = "a" }, { default = 0, kind = "number", name = "b" } }, toggle = false })
    Start(h)
    local order = {}

    addon.State:Watch({ "M.b" }, function(s) order[#order + 1] = ("b=" .. s:Get("M.b")) end, true)
    addon.State:Watch({ "M.a" }, function(s) order[#order + 1] = "a"; s:Set("M.b", s:Get("M.a") * 10) end, true)
    addon.State:Watch({ "M.a" }, function() order[#order + 1] = "a2" end, true)
    addon.State:Set("M.a", 3)
    eq(table.concat(order, ","), "a,a2,b=30")
end)

test("a publish that never settles is reported, not looped forever", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "a" } }, toggle = false })
    Start(h)
    addon.State:Watch({ "M.a" }, function(s) s:Set("M.a", s:Get("M.a") + 1) end, true)
    h:ExpectErrors(1)
    addon.State:Set("M.a", 1)
    truthy(h.errors[1]:find("did not settle", 1, true))
end)

test("a rule runs when its verdict flips, and only then", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "n" } }, toggle = false })
    Start(h)
    local flips = {}

    addon.State:Rule({ changed = function(active) flips[#flips + 1] = tostring(active) end, reads = { "M.n" },
        when = function(s) return (s:Get("M.n") > 5) end })
    for _, n in ipairs({ 1, 6, 7, 8, 2, 3, 9 }) do
        addon.State:Set("M.n", n)
    end
    eq(table.concat(flips, ","), "true,false,true")
end)

test("a watcher that errors is reported and the others still run", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "a" } }, toggle = false })
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

    addon.Events:On("UNIT_HEALTH", function(unit) seen[#seen + 1] = ("t:" .. unit) end, "target")
    addon.Events:On("UNIT_HEALTH", function(unit) seen[#seen + 1] = ("p:" .. unit) end, "player")
    eq(addon.Events:Registrations().UNIT_HEALTH, "player|target", "the same units give the same registration, in any order")
    h:Fire("UNIT_HEALTH", "player")
    h:Fire("UNIT_HEALTH", "target")
    h:Fire("UNIT_HEALTH", "focus")
    eq(table.concat(seen, ","), "p:player,t:target")
end)

test("a dispatch is one state batch", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "a" }, { default = 0, kind = "number", name = "b" } }, toggle = false })
    Start(h)
    local runs = 0

    addon.State:Watch({ "M.a", "M.b" }, function() runs = (runs + 1) end, true)
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
        OnEnable = function(module) module:On("PLAYER_TARGET_CHANGED", function() fired = (fired + 1) end) end,
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

    addon:Module("M", { commands = { { label = "Echo", name = "echo", run = function(arg) got = arg end, slash = "echo" } }, toggle = false })
    Start(h)
    h:Slash("/test echo hello world")
    eq(got, "hello world")
    h:Slash("/test")
    truthy(addon.SettingsWindow:IsShown(), "bare slash shows the settings window")
    got = nil
    falsy(h:Slash("/test bogus words"))
    eq(got, nil)
    truthy(h.printed[#h.printed]:find("Unknown command 'bogus'. Type /test help.", 1, true), h.printed[#h.printed])
end)

test("help lists every slash command", function()
    local h, addon = NewAddOn()

    addon:Module("M", { commands = { { label = "Echo things", name = "echo", run = function() end, slash = "echo" } }, toggle = false })
    Start(h)
    h:Slash("/test help")
    local text = table.concat(h.printed, "\n")

    truthy(text:find("/test echo - Echo things", 1, true))
    truthy(text:find("/test set - Set a setting", 1, true))
    h:Slash("/test version")
    truthy(h.printed[#h.printed]:find("Version 1.0", 1, true), h.printed[#h.printed])
end)

test("set and toggle change settings from text", function()
    local h, addon = NewAddOn()

    addon:Module("M", { label = "M", state = {
        { default = "a", kind = "string", label = "Mode", name = "mode", values = { "a", "b" } },
        { default = 1, kind = "number", label = "Size", max = 10, min = 0, name = "size" },
    } })
    Start(h)
    local function Last() return h.printed[#h.printed] end
    h:Slash("/test set M.mode b")
    eq(addon.State:Get("M.mode"), "b")
    h:Slash("/test set M.mode nope")
    eq(addon.State:Get("M.mode"), "b", "invalid value refused")
    h:Slash("/test toggle M.enabled")
    eq(addon.State:Get("M.enabled"), false)
    h:Slash("/test set M.enabled on")
    eq(addon.State:Get("M.enabled"), true)
    h:Slash("/test set M.enabled off")
    eq(addon.State:Get("M.enabled"), false)
    h:Slash("/test set M.enabled maybe")
    truthy(Last():find("M.enabled can't be set to 'maybe'.", 1, true), Last())
    eq(addon.State:Get("M.enabled"), false)
    h:Slash("/test set M.size 7")
    eq(addon.State:Get("M.size"), 7)
    h:Slash("/test set M.size big")
    eq(addon.State:Get("M.size"), 7, "a word isn't a number")
    h:Slash("/test toggle M.mode")
    truthy(Last():find("toggle <setting>. Settings: M.enabled, addon.debug", 1, true), "only booleans toggle: " .. Last())
    eq(addon.State:Get("M.mode"), "b")
end)

test("duplicate slash words and commands without a label are refused at compile", function()
    local h, addon = NewAddOn()

    addon:Module("M", { commands = {
            { label = "One", name = "one", run = function() end, slash = "x" },
            { label = "Two", name = "two", run = function() end, slash = "x" },
            { name = "three", run = function() end },
        },
        toggle = false })
    local err = StartRefused(h, addon)

    truthy(tostring(err):find("slash word 'x' is taken", 1, true))
    truthy(tostring(err):find("M.three: needs a label", 1, true), tostring(err))
end)

test("bound buttons run commands; while a map is active, unbound buttons are taken too", function()
    local h, addon = NewAddOn()
    local phases = {}

    addon:Module("M", { bindings = { { command = "M.hold", map = "menu", source = "gamepad.south" } },
        commands = { { held = true, label = "Hold", name = "hold", run = function(_, phase) phases[#phases + 1] = phase end } },
        toggle = false })
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

    addon:Module("M", { bindings = {
            { command = "M.a", map = "one", source = "gamepad.south" },
            { command = "M.b", map = "two", source = "gamepad.south" },
        },
        commands = {
            { held = true, label = "A", name = "a", run = function(_, phase) log[#log + 1] = ("a:" .. phase) end },
            { held = true, label = "B", name = "b", run = function(_, phase) log[#log + 1] = ("b:" .. phase) end },
        },
        toggle = false })
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

test("the settings window is generated from labeled persisted rows, in declaration order", function()
    local h, addon = NewAddOn()

    addon:Module("M", { label = "Module M", state = {
        { default = "a", kind = "string", label = "Mode", name = "mode", values = { "a", "b" } },
        { default = false, kind = "boolean", name = "hidden" },
        { default = false, kind = "boolean", label = "Runtime", name = "runtime", persist = false },
    } })
    Start(h)
    local window, state, names = addon.SettingsWindow, addon.State, {}

    window:Show()
    for _, entry in ipairs(window.Pages[1].entries) do
        if entry.name then
            names[#names + 1] = entry.name
            truthy(window.Controls[entry.id], "each setting has a control")
        end
    end
    eq(table.concat(names, ","), "M.enabled,M.mode,addon.debug")
    eq(window.Controls[state:Id("M.hidden")], nil)
    eq(window.Controls[state:Id("M.runtime")], nil)
    local button = window.Controls[state:Id("M.mode")]

    eq(button.Label:GetText(), "a")
    button:Click()
    eq(state:Get("M.mode"), "b", "window writes go through state")
    eq(button.Label:GetText(), "b")
end)

-- The settings pages, " | " between them: "Name: [Header] Module.row ...".
local function Pages(pages)
    local lines = {}

    for _, page in ipairs(pages) do
        local parts = {}

        for _, entry in ipairs(page.entries) do
            parts[#parts + 1] = ((entry.header and ("[" .. entry.header .. "]")) or entry.name)
        end
        lines[#lines + 1] = (page.name .. ": " .. table.concat(parts, " "))
    end
    return table.concat(lines, " | ")
end

test("module pages and sections organize the window; debug closes the main page", function()
    local h, addon = NewAddOn()

    addon:Module("Alpha", { label = "Alpha", state = {
        { default = "a", kind = "string", label = "Size", name = "size", values = { "a", "b" } },
        { default = false, kind = "boolean", name = "hidden" },
        { default = false, kind = "boolean", label = "Loud", name = "loud", section = "Noise" },
    } })
    addon:Module("Beta", { label = "Beta", page = "Extras" })
    addon:Module("Gamma", { page = "Other", section = "Gamma things",
        state = {
            { default = 1, kind = "number", label = "N", max = 3, min = 1, name = "n" },
        },
        toggle = false })
    addon:Module("Delta", { label = "Extras", page = "Extras" })
    addon:Module("Echo", { label = "Test AddOn" })
    addon:Module("Quiet", { state = { { default = true, kind = "boolean", label = "On", name = "on" } }, toggle = false })
    Start(h)
    local window = addon.SettingsWindow

    eq(Pages(h.env.ByteTerrace.SettingsPages(addon)), table.concat({
        "Test AddOn: [Alpha] Alpha.enabled Alpha.size [Noise] Alpha.loud Echo.enabled Quiet.on [Advanced] addon.debug",
        "Extras: [Beta] Beta.enabled Delta.enabled",
        "Other: [Gamma things] Gamma.n",
    }, " | "), "a header that repeats its page's name is left out, and a module with no label has none")
    eq(Pages(window.Pages), Pages(h.env.ByteTerrace.SettingsPages(addon)), "the window draws the schema's pages")
    window:Show(3)
    window.Controls[addon.State:Id("Gamma.n")].Plus:Click()
    eq(addon.State:Get("Gamma.n"), 2, "a control on a subpage writes through state too")
end)

test("page and section must be strings", function()
    local h, addon = NewAddOn()

    throws(function() addon:Module("M", { label = "M", page = 1 }) end, "page must be a string")
    throws(function() addon:Module("N", { label = "N", section = true }) end, "section must be a string")
    addon:Module("R", { state = { { default = false, kind = "boolean", label = "X", name = "x", section = 2 } }, toggle = false })
    truthy(StartRefused(h, addon):find("R.x: section must be a string", 1, true))
end)

test("labeled bounded numbers get steppers; a labeled number without bounds is refused", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 5, kind = "number", label = "N", max = 10, min = 1, name = "n", step = 1 } }, toggle = false })
    Start(h)
    addon.SettingsWindow:Show()
    local control = addon.SettingsWindow.Controls[addon.State:Id("M.n")]

    control.Plus:Click()
    eq(addon.State:Get("M.n"), 6)
    control.Minus:Click()
    eq(addon.State:Get("M.n"), 5)
    eq(control.Label:GetText(), "5")
    local h2, addon2 = NewAddOn()

    addon2:Module("M", { state = { { default = 1, kind = "number", label = "N", name = "n" } }, toggle = false })
    local err = StartRefused(h2, addon2)

    truthy(err:find("needs min and max", 1, true))
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

    module = addon:Module("M", { OnEnable = function(m)
            m:On("PLAYER_TARGET_CHANGED", function() module:SetEnabled(false) end)
            m:On("PLAYER_TARGET_CHANGED", function() count = (count + 1) end)
        end,
        toggle = false })
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
        m:On("PLAYER_TARGET_CHANGED", function() count = (count + 1) end)
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

    for i = 1, 9 do rows[i] = { default = 0, kind = "number", name = ("r" .. i), persist = false } end
    addon:Module("C", { state = rows, toggle = false })
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
    local m = addon:Module("M", { state = { { default = 0, kind = "number", name = "x", persist = false } }, toggle = false })

    Start(h)
    local seen, filtered = 0, 0

    m:Watch({ "x" }, function() seen = (seen + 1) end, true)
    for _, unit in ipairs({ "player", "target", "focus" }) do
        m:On("UNIT_AURA", function() filtered = (filtered + 1) end, unit)
    end
    h:Fire("UNIT_AURA", Secret("nameplate3"), {})
    eq(filtered, 0, "filtered handlers can't claim a secret unit")
    m:Set("x", 1)
    eq(seen, 1, "the batch closed, so a write publishes at once")
end)

test("module Get and Set accept a resolved id", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { state = { { default = 0, kind = "number", name = "x" } }, toggle = false })

    Start(h)
    local id = m:Id("x")

    m:Set(id, 3)
    eq(m:Get(id), 3)
    eq(addon.State:Get(id), 3, "so does the state's")
end)

test("non-finite numbers are refused", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { state = { { default = 0, kind = "number", name = "n" } }, toggle = false })

    Start(h)
    throws(function() m:Set("n", 0 / 0) end, "finite")
    throws(function() m:Set("n", math.huge) end, "finite")
    h:Slash("/test set M.n 1e999")
    eq(m:Get("n"), 0)
end)

test("slash words must be lowercase", function()
    local h, addon = NewAddOn()

    addon:Module("M", { commands = { { label = "Go", name = "go", run = function() end, slash = "Go" } }, toggle = false })
    truthy(StartRefused(h, addon):find("must be lowercase", 1, true))
end)

test("a module spec shared by two addons isn't changed by either", function()
    local spec = { commands = { { label = "Go", name = "go", run = function() end } }, toggle = false }
    local h1, a1 = NewAddOn({ name = "A1" })

    a1:Module("Lib", spec)
    local h2, a2 = NewAddOn({ name = "A2" })

    a2:Module("Lib", spec)
    h1:Fire("ADDON_LOADED", "A1", false)
    h2:Fire("ADDON_LOADED", "A2", false)
    eq(spec.commands[1].name, "go")
    truthy(a2.Commands.Ids["Lib.go"])
end)

test("row and module names must be identifiers", function()
    local _, addon = NewAddOn()

    throws(function() addon:Module("M", { state = { { default = 0, kind = "number", name = "a.b" } }, toggle = false }) end, "identifier")
    throws(function() addon:Module("Bad.Name", {}) end, "identifier")
end)

test("a command is one batch", function()
    local h, addon = NewAddOn()
    local m

    m = addon:Module("M", { commands = { { label = "Both", name = "both", run = function() m:Set("a", 1); m:Set("b", 1) end, slash = "both" } },
        state = { { default = 0, kind = "number", name = "a" }, { default = 0, kind = "number", name = "b" } },
        toggle = false })
    Start(h)
    local seen = {}

    m:Watch({ "a", "b" }, function() seen[#seen + 1] = (m:Get("a") .. m:Get("b")) end, true)
    h:Slash("/test both")
    eq(table.concat(seen, ","), "11")
end)

test("a cancel handler that switches maps wins over the switch that canceled it", function()
    local h, addon = NewAddOn()
    local phases = {}

    addon:Module("M", { bindings = { { command = "M.hold", map = "a", source = "gamepad.south" },
                     { command = "M.other", map = "b", source = "gamepad.east" } },
        commands = {
            { held = true, label = "Hold", name = "hold",
                run = function(_, phase)
                    phases[#phases + 1] = phase
                    if phase == "cancel" then addon.Input:SetActiveMaps({ "a", "b" }) end end },
            { label = "Other", name = "other", run = function() end } },
        toggle = false })
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

    addon:Module("M", { bindings = { { command = "M.go", map = "a", source = "gamepad.south" } },
        commands = { { label = "Go", name = "go", run = function() ran = (ran + 1) end } }, toggle = false })
    Start(h)
    h:EnterCombat()
    addon.Input:SetActiveMaps({ "a" })
    eq(#h.blocked, 0, "nothing blocked")
    h:Gamepad("PAD1", true)
    eq(ran, 1)
end)

test("a module that fails to start can't stop the others or wedge publication", function()
    local h, addon = NewAddOn()

    addon:Module("Broken", { active = { reads = { "Nope.row" }, when = function() return true end }, toggle = false })
    local later = addon:Module("Later", { state = { { default = 0, kind = "number", name = "x", persist = false } }, toggle = false })

    h:ExpectErrors("unknown state row Nope.row")
    Start(h)
    truthy(later.Enabled, "later modules still start")
    local seen = 0

    addon.State:Watch({ "Later.x" }, function() seen = (seen + 1) end, true)
    addon.State:Set("Later.x", 1)
    eq(seen, 1, "the start batch closed, so a write publishes at once")
end)

test("a row spec shared by two addons in one client writes to each addon's own SavedVariables", function()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.ADB, h.declared.BDB = true, true
    local shared = { state = { { default = 0, kind = "number", name = "n" } }, toggle = false }
    local a = h.env.ByteTerrace.NewAddOn({ name = "A", savedVariable = "ADB", title = "A", version = "1" })
    local b = h.env.ByteTerrace.NewAddOn({ name = "B", savedVariable = "BDB", title = "B", version = "1" })

    a:Module("S", shared)
    b:Module("S", shared)
    h:Fire("ADDON_LOADED", "A", false)
    h:Fire("ADDON_LOADED", "B", false)
    a.State:Set("S.n", 5)
    eq(h.env.ADB["S.n"], 5)
    eq(h.env.BDB["S.n"], nil)
    eq(shared.state[1].store, nil, "the caller's spec is untouched")
end)

test("a watcher registered mid-batch doesn't react to writes made before it existed", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "x", persist = false } }, toggle = false })
    local fired = 0

    addon:Module("Reader", { OnEnable = function(m)
            m:Watch({ "M.x" }, function() fired = (fired + 1) end, true)
        end,
        toggle = false })
    addon:Module("Writer", { OnEnable = function() addon.State:Set("M.x", 1) end, toggle = false })
    Start(h)
    eq(fired, 1, "the write came after the watcher: it fires")

    local h2, addon2 = NewAddOn()

    addon2:Module("M", { state = { { default = 0, kind = "number", name = "x", persist = false } }, toggle = false })
    local fired2 = 0

    addon2:Module("Writer", { OnEnable = function() addon2.State:Set("M.x", 1) end, toggle = false })
    addon2:Module("Reader", { OnEnable = function(m)
            m:Watch({ "M.x" }, function() fired2 = (fired2 + 1) end, true)
        end,
        toggle = false })
    Start(h2)
    eq(fired2, 0, "the write came before the watcher: it doesn't")
end)

test("a rule's first verdict doesn't depend on module declaration order", function()
    for _, readerFirst in ipairs({ true, false }) do
        local h, addon = NewAddOn()
        local calls = 0
        local reader = { OnEnable = function(m)
                m:Rule({ changed = function() calls = (calls + 1) end, reads = { "W.flag" }, when = function(s) return s:Get("W.flag") end })
            end,
            toggle = false }
        local writer = { OnEnable = function(m) m:Set("flag", true) end,
            state = { { default = false, kind = "boolean", name = "flag", persist = false } }, toggle = false }

        if readerFirst then
            addon:Module("R", reader); addon:Module("W", writer)
        else
            addon:Module("W", writer); addon:Module("R", reader)
        end
        Start(h)
        eq(calls, 0, (readerFirst and "reader declared first") or "writer declared first")
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

test("a module's errors for a bad value or an unknown row point at the module's caller", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { state = { { default = 0, kind = "number", name = "n" } }, toggle = false })

    Start(h)
    local _, mark = pcall(function() error("mark") end)
    local chunk = tostring(mark):match("^(.-):%d+: mark$")

    truthy(chunk, "this test's own chunk name: " .. tostring(mark))
    for _, call in ipairs({
        function() m:Set("n", "bad") end,
        function() m:Get("typo") end,
        function() m:Set("typo", 1) end,
    }) do
        local ok, err = pcall(call)

        falsy(ok)
        err = tostring(err)
        falsy(err:find("ByteTerrace_Core/", 1, true), err)
        eq(err:sub(1, #chunk + 1), chunk .. ":", "the error names the calling chunk: " .. err)
    end
end)

test("reserved module names are refused", function()
    local _, addon = NewAddOn()

    throws(function() addon:Module("addon", {}) end, "reserved")
    throws(function() addon:Module("combat", {}) end, "reserved")
end)

test("number rows honor their step", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { state = { { default = 2, kind = "number", max = 10, min = 0, name = "n", step = 2 } }, toggle = false })

    Start(h)
    throws(function() m:Set("n", 3) end, "multiple of 2")
    m:Set("n", 4)
    eq(m:Get("n"), 4)
end)

test("a stopped module's runtime rows return to their defaults", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { label = "M", OnEnable = function(mod) mod:Set("fact", true) end,
        state = { { default = false, kind = "boolean", name = "fact", persist = false } } })

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
    local m = addon:Module("M", { state = { { default = 0, kind = "number", name = "a" }, { default = 0, kind = "number", name = "b" } }, toggle = false })

    Start(h)
    local runs = 0

    addon.State:Watch({ "M.a", "M.b" }, function() runs = (runs + 1) end, true)
    addon:Batch(function() m:Set("a", 1); m:Set("b", 1) end)
    eq(runs, 1)
end)
