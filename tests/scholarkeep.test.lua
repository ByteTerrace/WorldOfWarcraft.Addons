-- Keeping the riddle on screen (ScholarKeep.lua and Scholar.lua): a riddle still unsolved comes back the same after a
-- /reload, a relog, or the challenge switched off and on, with its missed answers and its hint. Only solving or
-- skipping it ends it, so a child can't trade away a hard riddle. A saved riddle that can't be read, whose subject a
-- parent switched off, or that's heard with no voice to hear it gives way to a fresh one.

local Kit = use("scholar")
local LoadKid = Kit.LoadKid
local Returned = Kit.Returned
local Watch = Kit.Watch
local WrongAnswer = Kit.WrongAnswer

-- A child's riddle on screen, with the short pause and no quest riddles, and the riddle.
local function Riddle(settings)
    local saved = { ["Scholar.missPause"] = "short", ["Scholar.quests"] = false }

    for key, value in pairs(settings or {}) do saved[key] = value end

    local h, addon, ns = LoadKid(saved)
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")

    return h, addon, shown[#shown], rawget(h.env, "TheLanKrewToolKitScholar")
end

-- Whether two riddles ask the same: the same prompt, the same choices in the same order, and the same answer.
local function Same(a, b)
    return ((a ~= nil) and (b ~= nil) and (a.prompt == b.prompt) and (a.answer == b.answer)
        and (table.concat(a.choices, "|") == table.concat(b.choices, "|")))
end

test("a /reload brings back the same riddle, with its missed answer out and its hint showing", function()
    local h, _, puzzle = Riddle()
    local miss = WrongAnswer(puzzle)

    h:Key(tostring(miss), true)
    h:Reload()
    local again, frame = Returned(h)

    truthy(Same(again, puzzle), "the same riddle comes back")
    falsy(frame.Buttons[miss]:IsEnabled(), "the missed answer stays out")
    truthy(frame.Feedback:IsShown(), "and its hint shows")
    h:Advance(2)
    h:Key(tostring(again.answer), true)
    truthy(h.ns.Addon.State:Get("Scholar.solved"), "and its right answer solves it")
end)

test("the Owl winks at a riddle a /reload or relog brought back, and H still shows its hint", function()
    local h, _, puzzle = Riddle()

    h:Key(tostring(WrongAnswer(puzzle)), true)
    h:Reload()
    local winked = {}

    for _, line in ipairs(h.ns.ScholarKeep.Winks) do winked[line] = true end

    truthy(winked[Kit.Banner(h)], "the Owl says one of its winks: " .. Kit.Banner(h))
    h:Key("H", true)
    falsy(winked[Kit.Banner(h)], "then H shows the hint: " .. Kit.Banner(h))
end)

test("a relog, or switching the challenge off and on, brings back the same riddle too", function()
    for _, way in ipairs({ "relog", "switch" }) do
        local h, addon, puzzle = Riddle()

        h:Key(tostring(WrongAnswer(puzzle)), true)

        if way == "relog" then
            h:Relog(3600)
        else
            addon.State:Set("Scholar.enabled", false)
            addon.State:Set("Scholar.enabled", true)
        end

        truthy(Same(Returned(h), puzzle), way)
    end
end)

test("a riddle's first try counts once, even when a /reload comes between it and the right answer", function()
    local h, addon, puzzle = Riddle()
    local row = ("Scholar." .. puzzle.subject .. "Count")

    h:Key(tostring(WrongAnswer(puzzle)), true)
    local count = addon.State:Get(row)

    h:Reload()
    local again = Returned(h)

    h:Advance(2)
    h:Key(tostring(again.answer), true)
    truthy(h.ns.Addon.State:Get("Scholar.solved"))
    eq(h.ns.Addon.State:Get(row), count, "the miss before the /reload was its first try")
end)

test("solving or skipping ends the riddle: the next one after a /reload is a new one", function()
    for _, style in ipairs({ "solve", "skip" }) do
        local h, _, puzzle = Riddle({ ["Scholar.style"] = "gentle" })

        h:Key(tostring(WrongAnswer(puzzle)), true)
        h:Advance(2)

        if style == "solve" then
            h:Key(tostring(puzzle.answer), true)
            h:Advance(5)
        else
            h:Key("ESCAPE", true)
        end

        eq(h.ns.Addon.State:Get("Scholar.riddle"), "", style .. ": nothing is kept")
        h:Reload()
        local shown = Watch(h.ns)

        h:Slash("/tlk puzzle")
        truthy(shown[#shown] and not Same(shown[#shown], puzzle), style .. ": the next riddle is a new one")
    end
end)

test("a riddle whose subject a parent switched off gives way to a fresh one", function()
    local h, addon, puzzle = Riddle()

    h:Key(tostring(WrongAnswer(puzzle)), true)
    addon.State:Set("Scholar." .. puzzle.subject, false)
    h:Reload()
    local again = Returned(h)

    truthy(again, "a riddle is still due")
    truthy(again.subject ~= puzzle.subject, "and it's from the subject still on")
end)

test("a saved riddle that can't be read gives way to a fresh one", function()
    for _, saved in ipairs({ "{s3:abc", "{s6:prompts2:hi}", "n1;" }) do
        local h, addon, puzzle = Riddle()

        h:Key(tostring(WrongAnswer(puzzle)), true)
        addon.State:Set("Scholar.riddle", saved)
        h:Reload()
        local again = Returned(h)

        truthy(again and not Same(again, puzzle), saved .. ": a fresh riddle shows")
        truthy(h.ns.Addon.State:Get("Scholar.riddle") ~= saved, saved .. ": and is kept in its place")
    end
end)

test("the riddle is saved when it's asked and at each miss, and nothing is written while its answers wait", function()
    local h, addon, puzzle = Riddle()
    local version = addon.State:Version("Scholar.riddle")

    h:Key(tostring(WrongAnswer(puzzle)), true)
    eq(addon.State:Version("Scholar.riddle"), version + 1, "a miss saves it once")
    h:Advance(2)
    eq(addon.State:Version("Scholar.riddle"), version + 1, "the wait writes nothing")
end)

test("the codec reads back what it wrote, and refuses anything else", function()
    local _, _, ns = LoadKid()
    local keep = ns.ScholarKeep
    local value = { answer = 2, choices = { "a", "b|c", "", "d:e" }, deep = { { 1.5, true }, { false } }, prompt = "7 x 8?" }
    local back = keep.Decode(keep.Encode(value))

    eq(back.answer, 2)
    eq(table.concat(back.choices, "/"), "a/b|c//d:e")
    eq(back.deep[1][1], 1.5)
    eq(back.deep[1][2], true)
    eq(back.deep[2][1], false)
    eq(back.prompt, "7 x 8?")

    for _, bad in ipairs({ "", "{", "{s9:short}", "{n1;}", "{s1:an1;", "{s1:ax}", "{}trailing", "s99999999:x", "n1e999;" }) do
        eq(keep.Decode(bad), nil, bad)
    end

    local mixed = keep.Decode(keep.Encode({ "first", "second", name = "Owl" }))

    eq(mixed[1] .. " " .. mixed[2] .. " " .. mixed.name, "first second Owl", "number and string keys mix")

    for name, unplain in pairs({ ["a function"] = { print }, ["a table key"] = { [{}] = 1 }, ["inf"] = { (1 / 0) },
        ["NaN"] = { (0 / 0) } }) do
        eq(keep.Encode(unplain), nil, name .. " isn't plain data")
    end
end)

test("a riddle holding a secret isn't kept, and one without four choices isn't taken back", function()
    local h, addon, puzzle = Riddle()

    h:EnterCombat()
    addon.State:Set("Scholar.riddle", "x")
    eq(h.ns.ScholarKeep.Encode({ health = h.env.UnitHealth("player") }), nil, "a secret is never written")
    h:LeaveCombat()
    h:Key(tostring(WrongAnswer(puzzle)), true)
    local keep = h.ns.ScholarKeep
    local kept = keep.Decode(addon.State:Get("Scholar.riddle"))

    kept.puzzle.choices[1] = 5
    addon.State:Set("Scholar.riddle", keep.Encode(kept))
    h:Reload()
    local again = Returned(h)

    eq(type(again.choices[1]), "string", "a riddle with a number for a choice gives way to a fresh one")
end)
