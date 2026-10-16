-- The pause after a wrong answer (Scholar.lua and ScholarView.lua): the answers left wait a moment before they can be
-- picked again, longer each miss, so a child reads the hint instead of trying every answer. Each waiting answer's
-- keycap counts the seconds down. The hint, Read aloud, and Skip still work while they wait.

local Kit = use("scholar")
local LoadKid = Kit.LoadKid
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
