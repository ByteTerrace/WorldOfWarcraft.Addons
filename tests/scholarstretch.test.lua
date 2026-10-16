-- Scholar's stretch riddles and memory (Scholar.lua, ScholarMemory.lua): now and then a riddle from a grade or two
-- above, at its easiest, with its help a rung sooner and two stars for solving it, never moving the child's own
-- difficulty; and the recent riddles, which the next one doesn't repeat.

local Kit = use("scholar")
local Banner = Kit.Banner
local LoadKid = Kit.LoadKid
local Watch = Kit.Watch
local WrongAnswer = Kit.WrongAnswer

-- Asks riddles (answering each right) until one is a stretch, or tries runs out. The stretch riddle stays on screen.
local function UntilStretch(h, shown, tries)
    for _ = 1, tries do
        h:Slash("/tlk puzzle")
        local puzzle = shown[#shown]

        if puzzle.stretch then
            return puzzle
        end

        h:Key(tostring(puzzle.answer), true)
        h:Advance(2)
    end

    return nil
end

test("a stretch riddle asks a kind from a grade or two up, says so, and its help comes a rung sooner", function()
    local h, addon, ns = LoadKid({ ["Scholar.grade"] = "0", ["Scholar.quests"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)
    local puzzle = UntilStretch(h, shown, 60)

    truthy(puzzle, "one riddle in five or so is a stretch")
    local own = {}

    for _, kind in ipairs(ns.Puzzles.Kinds("math", 0, true, true)) do own[kind] = true end

    falsy(own[puzzle.kind], puzzle.kind .. " isn't one grade 0 asks")
    local frame = rawget(h.env, "TheLanKrewToolKitScholar")

    truthy(Harness.State(frame.Tag).text:find("STRETCH", 1, true), "the tag says it's a stretch")
    local level = addon.State:Get("Scholar.mathLevel")
    local stars = addon.State:Get("Scholar.stars")
    local first = WrongAnswer(puzzle)

    h:Key(tostring(first), true)

    if puzzle.step then
        truthy(Banner(h):find("Try this:", 1, true), "the first miss already gives the worked step: " .. Banner(h))
    end

    h:Key(tostring(WrongAnswer(puzzle, first)), true)
    truthy(Banner(h):find("Here's how:", 1, true), "the second miss shows the working: " .. Banner(h))
    eq(frame.Buttons[puzzle.answer].State, "reveal")
    h:Key(tostring(puzzle.answer), true)
    eq(addon.State:Get("Scholar.stars"), stars + 2, "a stretch solved is two stars")
    eq(addon.State:Get("Scholar.mathLevel"), level, "and its misses don't make riddles easier")
end)

test("the next riddle doesn't repeat one of the recent ones", function()
    local _, _, ns = LoadKid()
    local first = ns.Puzzles.Generate({ grade = 0, kind = "reading.rhyme", random = math.random, subject = "reading" })
    local avoid = { [ns.Puzzles.Signature(first)] = true }

    for _ = 1, 20 do
        local next = ns.Puzzles.Generate({ avoid = avoid, grade = 0, kind = "reading.rhyme", random = math.random, subject = "reading" })

        truthy(not avoid[ns.Puzzles.Signature(next)], "a recent riddle is drawn again")
    end

    local h, addon = LoadKid({ ["Scholar.quests"] = false })
    local shown = Watch(h.ns)

    for _ = 1, 12 do Kit.Solve(h, shown) end

    eq(#addon.Modules.Scholar.Records.recent:Keys(), 12, "every riddle shown is remembered")
    local seen = {}

    for _, puzzle in ipairs(shown) do
        local signature = ns.Puzzles.Signature(puzzle)

        falsy(seen[signature], "repeated: " .. signature)
        seen[signature] = true
    end
end)

test("kinds built from the player's quests are left out while the quest book is empty", function()
    local _, _, ns = LoadKid()
    local words = ns.ScholarWords

    for kind in pairs(words.fromQuests) do
        for grade = 0, 6 do
            for _, listed in ipairs(ns.Puzzles.Kinds("math", grade, true, false)) do
                truthy(listed ~= kind, kind .. " needs a quest")
            end
        end
    end
end)
