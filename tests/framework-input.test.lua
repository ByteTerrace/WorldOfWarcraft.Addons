-- ByteTerrace framework: controller labels and maps (a map belongs to its module, and held commands keep their phases
-- in order, whatever their own handlers do to the maps).

local Kit = use("framework")

local NewAddOn = Kit.NewAddOn
local Start = Kit.Start

test("a stopping module's maps stop capturing: a stopped feature never keeps the controller", function()
    local h, addon = NewAddOn()

    addon:Module("Menu", { bindings = { { command = "Menu.pick", map = "menu", source = "gamepad.south" } },
        commands = { { label = "Pick", name = "pick", run = function() end } }, label = "Menu",
        OnDisable = function() error("OnDisable broke before it gave the controller back") end })

    local picks = 0

    addon:Module("Pad", { bindings = { { command = "Pad.pick", map = "pad", source = "gamepad.east" } },
        commands = { { label = "Pick", name = "pick", run = function() picks = (picks + 1) end } }, label = "Pad" })

    Start(h)
    throws(function() addon.Input:SetActiveMaps({ "menu", "nope" }) end, "unknown input map nope")
    addon.Input:SetActiveMaps({ "menu", "pad" })
    h:Gamepad("PAD3", true)
    eq(#h.propagated, 0, "captured while the menu runs")
    h:ExpectErrors("OnDisable broke")
    addon.State:Set("Menu.enabled", false)
    h:Gamepad("PAD2", true)
    eq(picks, 1, "another module's map stays active")
    addon.State:Set("Pad.enabled", false)
    h:Gamepad("PAD3", true)
    eq(h.propagated[1], "PAD3", "the controller is the player's again")
end)

test("a map that binds two modules' commands is refused: a map belongs to one module", function()
    local h, addon = NewAddOn()

    addon:Module("A", { commands = { { label = "Go", name = "go", run = function() end } }, toggle = false })

    addon:Module("B", { bindings = {
            { command = "A.go", map = "shared", source = "gamepad.south" },
            { command = "B.go", map = "shared", source = "gamepad.east" },
        },
        commands = { { label = "Go", name = "go", run = function() end } }, toggle = false })

    h:ExpectErrors("shared: binds commands of more than one module")
    Start(h)
    falsy(addon.Started)
end)

test("a held command that changes maps in its own down gets cancel after that down, not inside it", function()
    local h, addon = NewAddOn()
    local log, holding = {}, false

    addon:Module("M", { bindings = { { command = "M.enter", map = "menu", source = "gamepad.south" } },
        commands = { { held = true, label = "Enter", name = "enter",
            run = function(_, phase)
                log[#log + 1] = phase

                if phase == "down" then
                    addon.Input:SetActiveMaps({})
                    holding = true
                else
                    holding = false
                end
            end } },
        toggle = false })

    Start(h)
    addon.Input:SetActiveMaps({ "menu" })
    h:Gamepad("PAD1", true)
    eq(table.concat(log, ","), "down,cancel")
    falsy(holding, "the cancel came last, so the hold ended")
end)

test("a held command can't have a slash word: slash text only ever presses it", function()
    local h, addon = NewAddOn()

    addon:Module("M", { commands = { { held = true, label = "Hold", name = "hold", run = function() end, slash = "hold" } },
        toggle = false })

    h:ExpectErrors("held command can't have a slash word")
    Start(h)
    falsy(addon.Started)
end)

test("a message number that wouldn't survive as text is refused rather than sent wrong", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { comms = { prefix = "TestApp1" }, label = "Chat" })

    Start(h)
    h:JoinGroup("party", { "Bob" })
    throws(function() module.Comms:Send("N", 123456789012345678) end, "TestApp: message field number")
    throws(function() module.Comms:Send("N", { (0.1 + 0.2) }) end, "doesn't survive as text")
    module.Comms:Send("N", { 42, 2.5 })
    eq(h.addonMessages[#h.addonMessages].message, "N:42\t2.5")
end)

test("a transport faster than the client's throttle regains messages, or without a queue, is refused", function()
    local _, addon = NewAddOn()

    throws(function() addon:Module("Chat", { comms = { interval = 0.05, prefix = "TestApp1" }, label = "Chat" }) end,
        "interval must be at least 1 second")

    throws(function() addon:Module("Chat", { comms = { prefix = "TestApp1", queue = 0 }, label = "Chat" }) end,
        "queue must be a positive whole number")
end)

test("a prefix the client won't register is reported", function()
    local h, addon = NewAddOn()

    addon:Module("Chat", { comms = { prefix = "TestApp1" }, label = "Chat" })

    for i = 1, Harness.MAX_PREFIXES do
        h.env.C_ChatInfo.RegisterAddonMessagePrefix("Other" .. i)
    end

    h:ExpectErrors("TestApp1 can't be registered: MaxPrefixes")
    Start(h)
end)

test("a label for a style no controller has reads as the generic one, not an error", function()
    local h = NewAddOn()

    eq(h.env.ByteTerrace.Input.Label("gamepad.south", "Bogus"), "South")
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
    eq(Input.Label("gamepad.paddle"), nil, "an unknown source has no label")
end)

test("bindings to unknown sources or commands, or a source bound twice in a map, are refused at compile", function()
    local h, addon = NewAddOn()

    addon:Module("M", { bindings = {
            { command = "M.missing", map = "menu", source = "gamepad.nope" },
            { command = "M.go", map = "menu", source = "gamepad.south" },
            { command = "M.go", map = "menu", source = "gamepad.south" },
        },
        commands = { { label = "Go", name = "go", run = function() end } }, toggle = false })

    h:ExpectErrors(1)
    Start(h)
    falsy(addon.Started)
    local err = h.errors[1]

    truthy(tostring(err):find("unknown source gamepad.nope", 1, true))
    truthy(tostring(err):find("unknown command M.missing", 1, true))
    truthy(tostring(err):find("menu: gamepad.south is bound twice", 1, true), tostring(err))
end)
