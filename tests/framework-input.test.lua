-- ByteTerrace framework: controller maps belong to their module, and held commands keep their
-- phases in order, whatever their own handlers do to the maps.

local function NewAddOn()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    return h, h.env.ByteTerrace.NewAddOn({ name = "TestApp", title = "Test AddOn", savedVariable = "TestDB", slash = { "/test" } })
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp")
end

test("a stopping module's maps stop capturing: a stopped feature never keeps the controller", function()
    local h, addon = NewAddOn()
    addon:Module("Menu", { label = "Menu",
        commands = { { name = "pick", label = "Pick", run = function() end } },
        bindings = { { map = "menu", source = "gamepad.south", command = "Menu.pick" } },
        OnDisable = function() error("OnDisable broke before it gave the controller back") end })
    Start(h)
    addon.Input:SetActiveMaps({ "menu" })
    h:Gamepad("PAD2", true)
    eq(#h.propagated, 0, "captured while the menu runs")
    h:ExpectErrors("OnDisable broke")
    addon.State:Set("Menu.enabled", false)
    h:Gamepad("PAD2", true)
    eq(h.propagated[1], "PAD2", "the controller is the player's again")
end)

test("a map that binds two modules' commands is refused: a map belongs to one module", function()
    local h, addon = NewAddOn()
    addon:Module("A", { toggle = false, commands = { { name = "go", label = "Go", run = function() end } } })
    addon:Module("B", { toggle = false, commands = { { name = "go", label = "Go", run = function() end } },
        bindings = {
            { map = "shared", source = "gamepad.south", command = "A.go" },
            { map = "shared", source = "gamepad.east", command = "B.go" },
        } })
    h:ExpectErrors("shared: binds commands of more than one module")
    Start(h)
    falsy(addon.Started)
end)

test("a held command that changes maps in its own down gets cancel after that down, not inside it", function()
    local h, addon = NewAddOn()
    local log, holding = {}, false
    addon:Module("M", { toggle = false,
        commands = { { name = "enter", label = "Enter", held = true, run = function(_, phase)
            log[#log + 1] = phase
            if phase == "down" then
                addon.Input:SetActiveMaps({})
                holding = true
            else
                holding = false
            end
        end } },
        bindings = { { map = "menu", source = "gamepad.south", command = "M.enter" } } })
    Start(h)
    addon.Input:SetActiveMaps({ "menu" })
    h:Gamepad("PAD1", true)
    eq(table.concat(log, ","), "down,cancel")
    falsy(holding, "the cancel came last, so the hold ended")
end)

test("a held command can't have a slash word: slash text only ever presses it", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false,
        commands = { { name = "hold", label = "Hold", held = true, slash = "hold", run = function() end } } })
    h:ExpectErrors("held command can't have a slash word")
    Start(h)
    falsy(addon.Started)
end)

test("a message number that wouldn't survive as text is refused rather than sent wrong", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    throws(function() module.Comms:Send("N", 123456789012345678) end, "TestApp: message field number")
    throws(function() module.Comms:Send("N", { 0.1 + 0.2 }) end, "doesn't survive as text")
    module.Comms:Send("N", { 42, 2.5 })
    eq(h.addonMessages[#h.addonMessages].message, "N:42\t2.5")
end)

test("a transport faster than the client's throttle regains messages is refused", function()
    local h, addon = NewAddOn()
    throws(function() addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1", interval = 0.05 } }) end,
        "interval must be at least 1 second")
end)

test("a prefix the client won't register is reported", function()
    local h, addon = NewAddOn()
    addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
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
