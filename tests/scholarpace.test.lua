-- The pause after a wrong answer (Scholar.lua and ScholarView.lua): the answers left wait a moment before they can be
-- picked again, longer each miss, so a child reads the hint instead of trying every answer. Each waiting answer's
-- keycap counts the seconds down. The hint, Read aloud, and Skip still work while they wait. The seconds left and the
-- misses so far are saved until a riddle is solved or skipped, so a /reload or relog doesn't get around them, and the
-- riddle itself comes back (scholarkeep.test.lua).

local Kit = use("scholar")
local Banner = Kit.Banner
local LoadKid = Kit.LoadKid
local Returned = Kit.Returned
local Watch = Kit.Watch
local WrongAnswer = Kit.WrongAnswer

-- The keycap labels of the four answers, joined.
local function Keycaps(frame)
    local caps = {}

    for i, button in ipairs(frame.Buttons) do caps[i] = button.Key:GetText() end

    return table.concat(caps, " ")
end

-- A child's riddle on screen, with the pause set to pause, and the riddle.
local function Riddle(pause)
    local h, addon, ns = LoadKid({ ["Scholar.missPause"] = pause, ["Scholar.quests"] = false })
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")

    return h, addon, ns, shown[#shown], rawget(h.env, "TheLanKrewToolKitScholar")
end

-- The keycaps while the answers wait: seconds on each, and its own key on the missed one.
local function Waiting(miss, seconds)
    local caps = {}

    for i = 1, 4 do caps[i] = (((i == miss) and tostring(i)) or seconds) end

    return table.concat(caps, " ")
end

test("after a miss the answers left wait two seconds, counting down on their keycaps, and a press then does nothing", function()
    local h, addon, _, puzzle, frame = Riddle("short")
    local miss = WrongAnswer(puzzle)

    h:Key(tostring(miss), true)
    local right = frame.Buttons[puzzle.answer]

    falsy(right:IsEnabled(), "the right answer waits too")
    eq(right.Key:GetText(), "2", "its keycap counts down")
    h:Key(tostring(puzzle.answer), true)
    falsy(addon.State:Get("Scholar.solved"), "a press while they wait does nothing")
    h:Advance(1)
    eq(right.Key:GetText(), "1")
    h:Advance(1)
    truthy(right:IsEnabled(), "then the answers wake")
    eq(right.Key:GetText(), tostring(puzzle.answer), "and show their keys again")
    falsy(frame.Buttons[miss]:IsEnabled(), "a missed answer stays out")
    h:Key(tostring(puzzle.answer), true)
    truthy(addon.State:Get("Scholar.solved"))
end)

test("each miss waits longer: 2, 4, then 6 seconds, and Long waits 4, 7, then 10", function()
    local waits = {}

    for _, pause in ipairs({ "short", "long" }) do
        local h, _, _, puzzle, frame = Riddle(pause)
        local seen = {}
        local right = frame.Buttons[puzzle.answer]

        for miss = 1, 4 do
            if miss ~= puzzle.answer then
                h:Key(tostring(miss), true)
                seen[#seen + 1] = right.Key:GetText()
                h:Advance(tonumber(right.Key:GetText()))
            end
        end

        waits[pause] = table.concat(seen, ",")
    end

    eq(waits.short, "2,4,6")
    eq(waits.long, "4,7,10")
end)

test("with the pause off, the answers never wait", function()
    local h, addon, _, puzzle = Riddle("off")

    h:Key(tostring(WrongAnswer(puzzle)), true)
    h:Key(tostring(puzzle.answer), true)
    truthy(addon.State:Get("Scholar.solved"))
end)

test("while the answers wait, Read aloud and the hint still work", function()
    local h, _, _, puzzle, frame = Riddle("long")

    h:Key(tostring(WrongAnswer(puzzle)), true)
    local spoken = #h.spoken

    h:Key("R", true)
    truthy(#h.spoken > spoken, "Read aloud speaks")
    truthy(frame.Hint:IsEnabled(), "and the hint is there")
end)

test("a fight doesn't end the wait: the riddle comes back with its hint and the seconds it had left", function()
    local h, addon, _, puzzle, frame = Riddle("long")

    h:Key(tostring(WrongAnswer(puzzle)), true)
    h:Advance(1)
    h:EnterCombat()
    h:Advance(10)
    h:LeaveCombat()
    truthy(frame:IsShown(), "the riddle came back")
    local right = frame.Buttons[puzzle.answer]

    falsy(right:IsEnabled(), "the answers still wait")
    eq(right.Key:GetText(), "3", "with the seconds they had left")
    truthy(frame.Feedback:IsShown() and Banner(h):find("Hint:", 1, true), "and the hint is back: " .. Banner(h))
    h:Key(tostring(puzzle.answer), true)
    falsy(addon.State:Get("Scholar.solved"), "a press while they wait does nothing")
    h:Advance(3)
    truthy(right:IsEnabled(), "then the answers wake")
    h:Key(tostring(puzzle.answer), true)
    truthy(addon.State:Get("Scholar.solved"))
end)

test("a wait doesn't follow the child to the next riddle", function()
    local h, addon, ns, puzzle, frame = Riddle("long")

    h:Key(tostring(WrongAnswer(puzzle)), true)
    h:Advance(4)
    h:Key(tostring(puzzle.answer), true)
    h:Advance(5)
    local shown = Watch(ns)

    addon.State:Set("Scholar.solved", false)
    h:Slash("/tlk puzzle")
    local nextOne = shown[#shown]

    truthy(nextOne and frame.Buttons[nextOne.answer]:IsEnabled(), "the next riddle's answers don't wait")
    eq(Keycaps(frame), "1 2 3 4")
end)

test("a /reload doesn't end the wait: the riddle comes back with its hint, and its answers left wait out the seconds left", function()
    local h, _, _, puzzle, frame = Riddle("long")
    local miss = WrongAnswer(puzzle)

    h:Key(tostring(miss), true)
    h:Advance(1)
    eq(frame.Buttons[puzzle.answer].Key:GetText(), "3")
    h:Reload()
    frame = rawget(h.env, "TheLanKrewToolKitScholar")
    truthy(frame:IsShown(), "the riddle is still due")
    eq(Keycaps(frame), Waiting(miss, "3"), "each answer left waits the seconds left, and the missed one stays out")
    falsy(frame.Buttons[puzzle.answer]:IsEnabled())
    truthy(frame.Feedback:IsShown(), "its hint comes with it")
    h:Advance(2)
    eq(Keycaps(frame), Waiting(miss, "1"))
    h:Advance(1)
    eq(Keycaps(frame), "1 2 3 4", "then the answers wake")
    truthy(frame.Buttons[puzzle.answer]:IsEnabled())
end)

test("after a /reload, the next miss waits as long as it would have, and the one after longer", function()
    local h, _, _, puzzle = Riddle("short")
    local first = WrongAnswer(puzzle)

    h:Key(tostring(first), true)
    h:Advance(2)
    h:Reload()
    local again, frame = Returned(h)
    local right = frame.Buttons[again.answer]
    local second = WrongAnswer(again, first)

    eq(Keycaps(frame), "1 2 3 4", "the first wait was over")
    h:Key(tostring(second), true)
    eq(right.Key:GetText(), "4", "the second miss waits 4 seconds")
    h:Advance(4)

    for i = 1, 4 do
        if (i ~= again.answer) and (i ~= first) and (i ~= second) then
            h:Key(tostring(i), true)
        end
    end

    eq(right.Key:GetText(), "6", "and the third 6")
end)

test("a relog keeps the seconds left, however long the child was away", function()
    local h, _, _, puzzle = Riddle("long")
    local miss = WrongAnswer(puzzle)

    h:Key(tostring(miss), true)
    h:Advance(3)
    h:Relog(3600)
    local frame = rawget(h.env, "TheLanKrewToolKitScholar")

    truthy(frame:IsShown(), "the riddle is still due")
    eq(Keycaps(frame), Waiting(miss, "1"), "the second it had left")
    h:Advance(1)
    eq(Keycaps(frame), "1 2 3 4")
    local again = Returned(h)

    h:Key(tostring(WrongAnswer(again, miss)), true)
    eq(frame.Buttons[again.answer].Key:GetText(), "7", "and the next miss waits the second step")
end)

test("solving or skipping ends the growing wait: after a /reload, the next riddle's first miss waits the first step", function()
    for _, style in ipairs({ "solve", "skip" }) do
        local h, addon, ns = LoadKid({ ["Scholar.missPause"] = "short", ["Scholar.quests"] = false,
            ["Scholar.style"] = "gentle" })

        local shown = Watch(ns)

        h:Slash("/tlk puzzle")
        local puzzle = shown[#shown]

        h:Key(tostring(WrongAnswer(puzzle)), true)
        h:Advance(1)
        h:Key(tostring(WrongAnswer(puzzle, WrongAnswer(puzzle))), true)

        if style == "solve" then
            h:Advance(4)
            h:Key(tostring(puzzle.answer), true)
            truthy(addon.State:Get("Scholar.solved"))
        else
            h:Key("ESCAPE", true)
        end

        h:Reload()
        shown = Watch(h.ns)
        h:Slash("/tlk puzzle")
        local frame = rawget(h.env, "TheLanKrewToolKitScholar")
        local nextOne = shown[#shown]

        eq(Keycaps(frame), "1 2 3 4", style .. ": the next riddle's answers don't wait")
        h:Key(tostring(WrongAnswer(nextOne)), true)
        eq(frame.Buttons[nextOne.answer].Key:GetText(), "2", style .. ": its first miss waits the first step")
    end
end)

test("the wait runs one timer and writes its seconds once a second on screen, and nothing while a fight has the riddle", function()
    local h, addon, _, puzzle = Riddle("long")
    local scholar = addon.Modules.Scholar

    h:Key(tostring(WrongAnswer(puzzle)), true)
    eq(scholar:PendingTimers(), 1, "one timer counts the wait down")
    local left = addon.State:Version("Scholar.pauseLeft")

    h:Advance(1)
    eq(addon.State:Version("Scholar.pauseLeft"), left + 1, "each second writes the seconds left once")
    eq(scholar:PendingTimers(), 1, "still one timer")
    h:EnterCombat()
    left = addon.State:Version("Scholar.pauseLeft")
    local misses = addon.State:Version("Scholar.pauseMisses")

    eq(scholar:PendingTimers(), 0, "no timer while the riddle is away")
    h:Advance(10)
    eq(addon.State:Version("Scholar.pauseLeft"), left, "and no writes")
    eq(addon.State:Version("Scholar.pauseMisses"), misses)
    eq(addon.State:Get("Scholar.pauseLeft"), 3)
end)
