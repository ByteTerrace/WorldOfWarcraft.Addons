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

test("capture changes only when whether anything's bound does", function()
    local h, addon = NewAddOn()

    addon:Module("Pad", { bindings = { { command = "Pad.pick", map = "pad", source = "gamepad.east" } },
        commands = { { label = "Pick", name = "pick", run = function() end } }, label = "Pad" })

    addon:Module("Note", { commands = { { label = "Focus", name = "focus", run = function() end } }, label = "Note" })
    Start(h)
    h:ResetCalls()

    for _ = 1, 5 do
        addon.Input:SetActiveMaps({ "pad" })
    end

    eq(h:CountCalls("EnableGamePadButton"), 1, "capture turns on once")

    for _ = 1, 5 do
        addon.Input:SetActiveMaps({})
    end

    eq(h:CountCalls("EnableGamePadButton"), 2, "and off once")
    h:ResetCalls()
    addon.State:Set("Note.enabled", false)
    eq(h:CountCalls("EnableGamePadButton") + h:CountCalls("ClearOverrideBindings"), 0, "a module with no summons stops quietly")
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
    local log = {}
    local holding = false

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

test("a button's glyph is the controller UI's own art for the connected family, and its prompt falls back to text", function()
    local h = NewAddOn()
    local Input = h.env.ByteTerrace.Input

    h.labelStyle = "Shapes"
    eq(Input.Glyph("gamepad.south"), "|A:gamepad-ps-pad1-normal:20:20:0:0|a", "PlayStation art, inline")
    eq(Input.Glyph("gamepad.dpadLeft", 14), "|A:gamepad-ps-paddleft-normal:14:14:0:0|a", "at the size asked")
    eq(Input.Prompt("gamepad.south"), Input.Glyph("gamepad.south"), "the prompt is the glyph")
    eq(Input.Glyph("gamepad.nope"), nil, "an unknown source has none")
    h.env.InputIconTextureSetUtility.GetActiveInputIconButtonTextures = function() return nil end
    eq(Input.Glyph("gamepad.south"), nil, "nor does a button the client has no art for")
    eq(Input.Prompt("gamepad.south"), "Cross", "and then the prompt is its printed name")
end)

test("a summon binds one controller button to a command without capturing the rest", function()
    local h, addon = NewAddOn()
    local focused = 0

    addon:Module("Note", { commands = { { label = "Focus", name = "focus", run = function() focused = (focused + 1) end } },
        label = "Note" })

    Start(h)
    local module = addon.Modules.Note

    truthy(addon.Input:Summon(module, "gamepad.back", "Note.focus"))
    h:Gamepad("PADBACK", true)
    h:Gamepad("PADBACK", false)
    eq(focused, 1, "the press runs the command, once")
    h:Gamepad("PAD1", true)
    eq(h.propagated[1], "PAD1", "every other button is still the player's")
    addon.Input:Dismiss(module, "gamepad.back", "Note.focus")
    h:Gamepad("PADBACK", true)
    eq(focused, 1, "dismissed, the button is the game's again")
    eq(h.propagated[2], "PADBACK")
    throws(function() addon.Input:Summon(module, "gamepad.nope", "Note.focus") end, "unknown source gamepad.nope")
end)

test("summons of one button stack: the latest wins, and dismissing it gives the button back to the one before", function()
    local h, addon = NewAddOn()
    local ran = {}

    local function Run(name) return function() ran[#ran + 1] = name end end

    addon:Module("Card", { commands = { { label = "Focus", name = "focus", run = Run("focus") } }, label = "Card" })

    addon:Module("Riddle", {
        commands = {
            { label = "Skip", name = "skip", run = Run("skip") }, { label = "Later", name = "later", run = Run("later") },
            { label = "Reopen", name = "reopen", run = Run("reopen") },
        },
        label = "Riddle",
    })

    Start(h)
    local card = addon.Modules.Card
    local riddle = addon.Modules.Riddle

    local function Press(key)
        h:Gamepad(key, true)
        h:Gamepad(key, false)
    end

    addon.Input:Summon(card, "gamepad.back", "Card.focus")
    addon.Input:Summon(riddle, "gamepad.back", "Riddle.skip")
    Press("PADBACK")
    addon.Input:Dismiss(riddle, "gamepad.back", "Riddle.skip")
    Press("PADBACK")
    eq(table.concat(ran, " "), "skip focus", "the riddle's Back wins, and the card's comes back after it")
    addon.Input:Summon(riddle, "gamepad.dpadLeft", "Riddle.reopen")
    addon.Input:Summon(riddle, "gamepad.dpadLeft", "Riddle.later")
    addon.Input:Dismiss(riddle, "gamepad.dpadLeft", "Riddle.reopen")
    Press("PADDLEFT")
    eq(ran[#ran], "later", "dismissing a summon under the top one leaves the top one")
    addon.Input:Dismiss(riddle, "gamepad.dpadLeft", "Riddle.later")
    addon.Input:Dismiss(riddle, "gamepad.dpadLeft", "Riddle.later")
    Press("PADDLEFT")
    eq(h.propagated[#h.propagated], "PADDLEFT", "with none left, the button is the game's, and a second dismiss is harmless")
    addon.Input:Summon(riddle, "gamepad.back", "Riddle.skip")
    addon.State:Set("Riddle.enabled", false)
    Press("PADBACK")
    eq(ran[#ran], "focus", "a module that stops gives its buttons back to the ones before")
end)

test("a summon is for its own module's commands that only press: anything else is an error", function()
    local h, addon = NewAddOn()

    addon:Module("Note", {
        commands = {
            { label = "Focus", name = "focus", run = function() end },
            { held = true, label = "Hold", name = "hold", run = function() end },
        },
        label = "Note",
    })

    addon:Module("Other", { commands = { { label = "Go", name = "go", run = function() end } }, label = "Other" })
    Start(h)
    local module = addon.Modules.Note

    throws(function() addon.Input:Summon(module, "gamepad.back", "Note.nope") end, "unknown command Note.nope")
    throws(function() addon.Input:Summon(module, "gamepad.back", "Note.hold") end, "a summon can't be held: Note.hold")
    throws(function() addon.Input:Summon(module, "gamepad.back", "Other.go") end, "Note can't summon Other.go")
    eq(next(h.overrideBindings), nil, "nothing was bound")
end)

test("a summon asked for as combat starts, before lockdown, is refused rather than outliving it", function()
    local h, addon = NewAddOn()
    local took

    addon:Module("Note", {
        commands = { { label = "Focus", name = "focus", run = function() end } },
        label = "Note",
        OnEnable = function(module)
            module:On("PLAYER_REGEN_DISABLED", function() took = addon.Input:Summon(module, "gamepad.back", "Note.focus") end)
        end,
    })

    Start(h)
    h:EnterCombat()
    eq(took, false)
    eq(next(h.overrideBindings), nil)
end)

test("a summon ends as combat starts, before lockdown, is refused in combat, and ends with its module", function()
    local h, addon = NewAddOn()

    addon:Module("Note", { commands = { { label = "Focus", name = "focus", run = function() end } }, label = "Note" })
    Start(h)
    local module = addon.Modules.Note

    addon.Input:Summon(module, "gamepad.back", "Note.focus")
    h:EnterCombat()
    eq(next(h.overrideBindings), nil, "combat starting ends it")
    falsy(addon.Input:Summon(module, "gamepad.back", "Note.focus"), "refused in combat")
    eq(#h.blocked, 0, "and nothing was blocked: it never tried")
    h:LeaveCombat()
    truthy(addon.Input:Summon(module, "gamepad.back", "Note.focus"))
    addon.State:Set("Note.enabled", false)
    eq(next(h.overrideBindings), nil, "a stopped feature never keeps a summon")
    falsy(addon.Input:Summon(module, "gamepad.back", "Note.focus"), "and a stopped module can't summon")
end)
