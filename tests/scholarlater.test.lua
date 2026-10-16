-- A riddle that doesn't trap the player (Scholar.lua, ScholarLater.lua, and ScholarFrame.lua): while it shows, only its
-- own keys and its panel are the riddle's, so the player can still walk, type, and fight. Later (L, the Later button,
-- or D-pad left) folds it into a pill at the top of the screen and gives the keyboard, mouse, and controller back. The
-- pill, D-pad left, or /tlk puzzle opens it again. In "Solve to keep playing" a riddle put off comes back by itself
-- after a minute, once it's safe; in Gentle mode it waits to be opened. Either way it's the same riddle, still due, and
-- the parent's report says how often riddles were put off.

local Kit = use("scholar")
local LoadKid = Kit.LoadKid
local Watch = Kit.Watch
local WrongAnswer = Kit.WrongAnswer

local function Pill(h)
    return rawget(h.env, "TheLanKrewToolKitScholarPill")
end

-- Whether key reached the game's bindings when pressed.
local function Reaches(h, key)
    local before = #h.propagatedKeys

    h:Key(key, true)
    h:Key(key, false)

    return (#h.propagatedKeys > before)
end

-- A child's riddle on screen, with the short pause and no quest riddles, and the riddle.
local function Riddle(settings)
    local saved = { ["Scholar.missPause"] = "short", ["Scholar.quests"] = false }

    for key, value in pairs(settings or {}) do saved[key] = value end

    local h, addon, ns = LoadKid(saved)
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")

    return h, addon, shown[#shown], rawget(h.env, "TheLanKrewToolKitScholar")
end

test("while a riddle shows, keys it doesn't use reach the game, and its own don't", function()
    local h = Riddle()

    for _, key in ipairs({ "W", "SPACE", "ENTER", "5", "TAB" }) do
        truthy(Reaches(h, key), key .. " reaches the game")
    end

    for _, key in ipairs({ "H", "R", "UP", "DOWN" }) do
        falsy(Reaches(h, key), key .. " is the riddle's")
    end
end)

test("while a riddle shows, only its panel takes the mouse, so the world can still be clicked", function()
    local h, _, _, frame = Riddle()

    falsy(frame:IsMouseEnabled(), "the screen around the panel lets clicks through")
    falsy(h:WorldClickBlocked(), "so the world can be clicked")
    truthy(frame.Panel:IsMouseEnabled(), "the panel takes them")
end)

test("Esc puts the riddle away and still reaches the game, so it opens the game menu as it always does", function()
    local h, _, _, frame = Riddle()

    truthy(Reaches(h, "ESCAPE"), "the game gets Esc")
    falsy(frame:IsShown(), "and the riddle is out of the menu's way")
    truthy(Pill(h):IsShown(), "waiting in its pill")
    truthy(Reaches(h, "ESCAPE"), "and every Esc after is the game's")
end)

test("Start on a controller is the game's, as it would be without the addon, and its menu shows over the riddle", function()
    local h, _, _, frame = Riddle()
    local before = #h.propagated

    h:Gamepad("PADFORWARD", true)
    eq(h.propagated[before + 1], "PADFORWARD", "the first press of Start reaches the game, for its menu")
    truthy(frame:IsShown(), "the riddle stays")
    eq(frame:GetFrameStrata(), "HIGH", "under the game menu's DIALOG strata, so the menu shows over it")
end)

test("while a riddle shows, it takes only its own controller buttons, and every other one is the game's", function()
    local h, addon, puzzle, frame = Riddle()

    for _, key in ipairs({ "PADLTRIGGER", "PADRTRIGGER", "PADDRIGHT", "PADLSTICK", "PADRSTICK" }) do
        local before = #h.propagated

        h:Gamepad(key, true)
        eq(h.propagated[before + 1], key, key .. " reaches the game")
    end

    eq(table.concat(addon.Input:ActiveMaps(), ","), "", "nothing captures the controller")
    h:Gamepad(({ "PAD1", "PAD2", "PAD3", "PAD4" })[puzzle.answer], true)
    truthy(addon.State:Get("Scholar.solved"), "a face button still answers")
    truthy(frame:IsShown())
end)

test("Start opens the radial menu, and the riddle steps aside into its pill, as it does for Esc", function()
    local h, addon, _, frame = Riddle()

    h:OpenRadial()
    falsy(frame:IsShown(), "out of the radial's way")
    truthy(Pill(h):IsShown(), "waiting in its pill")
    h:CloseRadial()
    addon.State:Set("Scholar.enabled", false)
    h:OpenRadial()
    eq(#h.errors, 0, "and with the challenge off, the radial hears nothing from it")
end)

test("with a controller, the riddle's keys, its pills, and the waiting pill show the controller UI's own glyphs", function()
    local h, addon, ns = LoadKid({ ["Scholar.missPause"] = "short", ["Scholar.quests"] = false })
    local shown = Watch(ns)

    h.labelStyle = "Letters"
    h:Slash("/tlk puzzle")
    local frame = rawget(h.env, "TheLanKrewToolKitScholar")

    eq(frame.Buttons[1].Key:GetText(), "|A:gamepad-xbox1-pad1-normal:22:22:0:0|a", "an answer's keycap is A's glyph")
    truthy(frame.Later.Label:GetText():find("|A:gamepad-xbox1-paddleft-normal", 1, true), frame.Later.Label:GetText())
    h:Key("L", true)
    truthy(Pill(h).Label:GetText():find("|A:gamepad-xbox1-paddleft-normal:18:18:0:0|a", 1, true), "the pill says which button")
    h:Gamepad("PADDLEFT", true)
    truthy(frame:IsShown(), "and that button opens it")
    truthy(shown[#shown])
    eq(addon.State:Get("Scholar.collapsed"), false)
end)

test("Later puts the riddle away into a pill, gives the keyboard and controller back, and keeps it due", function()
    for _, way in ipairs({ "key", "button", "pad" }) do
        local h, addon, _, frame = Riddle()
        local riddle = addon.State:Get("Scholar.riddle")

        if way == "key" then
            h:Key("L", true)
        elseif way == "button" then
            h:Click(frame.Later)
        else
            h:Gamepad("PADDLEFT", true)
            h:Gamepad("PADDLEFT", false)
        end

        falsy(frame:IsShown(), way .. ": the riddle is put away")
        truthy(Pill(h) and Pill(h):IsShown(), way .. ": a pill says it's waiting")
        falsy(frame:IsKeyboardEnabled(), way .. ": the keyboard is the player's")
        truthy(Reaches(h, "H"), way .. ": every key reaches the game")
        eq(table.concat(addon.Input:ActiveMaps(), ","), "", way .. ": and the controller")
        truthy(addon.State:Get("Scholar.pending"), way .. ": it's still due")
        eq(addon.State:Get("Scholar.riddle"), riddle, way .. ": and still the same riddle")
    end
end)

test("the pill, D-pad left, or /tlk puzzle opens it again, and its pause waits where it was", function()
    for _, way in ipairs({ "pill", "pad", "slash" }) do
        local h, _, puzzle, frame = Riddle()

        h:Key(tostring(WrongAnswer(puzzle)), true)
        h:Advance(1)
        h:Key("L", true)
        h:Advance(30)

        if way == "pill" then
            h:Click(Pill(h))
        elseif way == "pad" then
            h:Gamepad("PADDLEFT", true)
        else
            h:Slash("/tlk puzzle")
        end

        truthy(frame:IsShown(), way .. ": the riddle is back")
        falsy(Pill(h):IsShown(), way .. ": and the pill is gone")
        eq(frame.Buttons[puzzle.answer].Key:GetText(), "1", way .. ": its answers still wait the second they had left")
    end
end)

test("in Solve to keep playing, a riddle put off comes back by itself after a minute, once no fight is on", function()
    local h, _, _, frame = Riddle()

    h:Key("L", true)
    h:Advance(59)
    falsy(frame:IsShown(), "not before the minute")
    h:Advance(1)
    truthy(frame:IsShown(), "then it's back")
    h:Key("L", true)
    h:Advance(30)
    h:EnterCombat()
    h:Advance(60)
    falsy(frame:IsShown(), "not during a fight")
    h:LeaveCombat()
    truthy(frame:IsShown(), "but as soon as it ends")
end)

test("in Gentle mode, a riddle put off waits to be opened, and nothing runs while it waits", function()
    local h, addon, _, frame = Riddle({ ["Scholar.style"] = "gentle" })

    h:Key("L", true)
    eq(addon.Modules.Scholar:PendingTimers(), 0, "no timer waits to bring it back")
    h:Advance(600)
    falsy(frame:IsShown(), "it waits")
    truthy(Pill(h):IsShown(), "with its pill")
end)

test("a fight while a riddle waits keeps its pill, and D-pad left opens it again once the fight is over", function()
    local h, _, _, frame = Riddle({ ["Scholar.style"] = "gentle" })

    h:Key("L", true)
    h:EnterCombat()
    truthy(Pill(h):IsShown(), "the pill stays through the fight")
    h:LeaveCombat()
    h:Gamepad("PADDLEFT", true)
    truthy(frame:IsShown(), "D-pad left opens it after the fight")
end)

test("a riddle can't be put away while it celebrates a right answer", function()
    local h, addon, puzzle, frame = Riddle()

    h:Key(tostring(puzzle.answer), true)
    h:Key("L", true)
    truthy(frame:IsShown(), "the celebration stays")
    falsy(Pill(h) and Pill(h):IsShown(), "and no pill shows")
    truthy(addon.State:Get("Scholar.solved"))
end)

test("the parent's report says how many riddles were put off, and how many came back after a /reload", function()
    local h, _, puzzle = Riddle({ ["Scholar.style"] = "gentle" })

    h:Key("L", true)
    h:Click(Pill(h))
    h:Key("L", true)
    h:Click(Pill(h))
    h:Key(tostring(WrongAnswer(puzzle)), true)
    h.ns.Addon.State:Set("Scholar.enabled", false)
    h.ns.Addon.State:Set("Scholar.enabled", true)
    eq(h.ns.Addon.State:Get("Scholar.returnCount"), 0, "a parent switching the challenge off and on isn't a reload")
    h:Reload()
    h:Slash("/tlk report")
    local report = table.concat(h.printed, "\n")

    truthy(report:find("Put off 2 riddles with Later.", 1, true), report)
    truthy(report:find("1 riddle came back after a reload or relog.", 1, true), report)
    falsy(report:find("1 riddles", 1, true), "one riddle is a riddle")
end)
