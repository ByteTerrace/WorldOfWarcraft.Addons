-- Fact-level practice (ScholarMath.lua's fact riddles and ScholarMemory.lua's fact records): a riddle that asks one
-- fact names it on puzzle.fact, Generate's fact option asks exactly that fact again in any story, and through the real
-- addon a missed fact is remembered and comes back as the next riddle of its kind once it's due.

local Kit = use("scholar")
local LoadKid = Kit.LoadKid
local Numbers = Kit.Numbers
local Watch = Kit.Watch
local WrongAnswer = Kit.WrongAnswer

-- Each fact kind, a grade that asks it, and facts to ask again with the expression each must show.
local Asked = {
    { expression = "7 + 8", fact = { a = 7, b = 8 }, grade = 0, kind = "math.add" },
    { expression = "3 + 9", fact = { a = 3, b = 9 }, grade = 2, kind = "math.add" },
    { expression = "13 - 6", fact = { a = 13, b = 6 }, grade = 1, kind = "math.subtract" },
    { expression = "17 - 9", fact = { a = 17, b = 9 }, grade = 2, kind = "math.subtract" },
    { expression = "7 x 8", fact = { a = 7, b = 8 }, grade = 3, kind = "math.multiply" },
    { expression = "8 x 7", fact = { a = 8, b = 7 }, grade = 4, kind = "math.multiply" },
    { expression = "56 / 7", fact = { a = 56, b = 7 }, grade = 3, kind = "math.divide" },
}

-- Asks riddles (answering each right) until one of kind is up, or tries runs out. That riddle stays on screen.
local function Until(h, shown, test, tries)
    for _ = 1, tries do
        h:Slash("/tlk puzzle")
        local puzzle = shown[#shown]

        if test(puzzle) then
            return puzzle
        end

        h:Key(tostring(puzzle.answer), true)
        h:Advance(2)
    end

    return nil
end

test("a fact riddle names its fact, and the fact option asks exactly that fact in any story", function()
    local _, _, ns = LoadKid()

    for _, case in ipairs(Asked) do
        local prompts = {}

        for seed = 1, 30 do
            math.randomseed(seed)

            local p = ns.Puzzles.Generate({ fact = case.fact, grade = case.grade, kind = case.kind, level = (1 + (seed % 3)),
                random = math.random, subject = "math" })

            eq(p.expression, case.expression, case.kind .. " at grade " .. case.grade)
            eq(p.fact.a, case.fact.a)
            eq(p.fact.b, case.fact.b)
            prompts[p.prompt] = true
        end

        local stories = 0

        for _ in pairs(prompts) do stories = (stories + 1) end

        truthy(stories > 1, case.kind .. " tells the fact in more than one story")
    end

    for _, kind in ipairs({ "math.add", "math.subtract" }) do
        local p = ns.Puzzles.Generate({ grade = 0, kind = kind, level = 2, random = math.random, subject = "math" })
        local n = Numbers(p.expression)

        eq(p.fact.a, n[1], kind .. " names the fact it asked")
        eq(p.fact.b, n[2])
    end
end)

test("a fact that doesn't fit its riddle is ignored, and the riddle asks its own", function()
    local _, _, ns = LoadKid()

    local odd = {
        { fact = { a = 15, b = 9 }, kind = "math.add" }, { fact = { a = 4, b = 9 }, kind = "math.subtract" },
        { fact = { a = 13, b = 2 }, kind = "math.multiply" }, { fact = { a = 50, b = 7 }, kind = "math.divide" },
        { fact = { a = 8, b = 0 }, kind = "math.divide" }, { fact = { a = 2.5, b = 1 }, kind = "math.add" },
        { fact = { a = "7", b = "8" }, kind = "math.multiply" }, { fact = "7+8", kind = "math.add" },
    }

    for _, case in ipairs(odd) do
        local grade = ((((case.kind == "math.multiply") or (case.kind == "math.divide")) and 3) or 1)

        for seed = 1, 10 do
            math.randomseed(seed)
            local p = ns.Puzzles.Generate({ fact = case.fact, grade = grade, kind = case.kind, level = 2, random = math.random, subject = "math" })
            local n = Numbers(p.expression)

            truthy(type(p.fact.a) == "number", "a riddle of its own names its own fact")
            truthy((n[1] ~= case.fact.a) or (n[2] ~= case.fact.b), ("%s doesn't ask %s"):format(case.kind, tostring(p.expression)))
        end
    end
end)

test("a missed fact is remembered, and the next riddle of its kind asks it again once it's due", function()
    local h, addon, ns = LoadKid({ ["Scholar.grade"] = "0", ["Scholar.quests"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)
    local missed = Until(h, shown, function(puzzle) return (puzzle.fact ~= nil) end, 60)

    truthy(missed, "a small sum or difference comes up")
    h:Key(tostring(WrongAnswer(missed)), true)
    h:Key(tostring(missed.answer), true)
    h:Advance(2)
    local facts = addon.Modules.Scholar.Records.facts
    local record = facts:Get(("%s:%dx%d"):format(missed.kind, missed.fact.a, missed.fact.b))

    truthy(record, "the missed fact has a record")
    eq(record.kind, missed.kind)
    eq(record.a, missed.fact.a)
    eq(record.b, missed.fact.b)
    eq(record.box, 1, "a miss sends it to box 1")
    eq(record.recent, "0")
    eq(record.due, addon.State:Get("Scholar.mathCount"), "and it's due at the very next riddle")
    local again = Until(h, shown, function(puzzle) return (puzzle.kind == missed.kind) end, 60)

    truthy(again, "the missed kind comes back")
    eq(again.fact.a, missed.fact.a, "the same fact: " .. again.prompt)
    eq(again.fact.b, missed.fact.b)
    eq(Numbers(again.expression)[1], missed.fact.a)
    eq(Numbers(again.expression)[2], missed.fact.b)
    h:Key(tostring(again.answer), true)
    h:Advance(2)
    eq(facts:Get(("%s:%dx%d"):format(missed.kind, missed.fact.a, missed.fact.b)).box, 2, "answered right, it moves up a box")
end)
