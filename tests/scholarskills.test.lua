-- Scholar's learning engine (TheLanKrewToolKit/ScholarSkills.lua and its records in Scholar.lua): a skill moves up a
-- box on a first-try right and back to box 1 on a miss, the next riddle favors new and due skills, math and reading
-- keep their own difficulty, and /tlk report shows a parent how it's going.

local Kit = use("scholar")
local LoadKid, Solve, Watch, WrongAnswer = Kit.LoadKid, Kit.Solve, Kit.Watch, Kit.WrongAnswer

-- Asks a riddle now and misses its first try, then answers it right; shown is Watch's list. Returns the riddle.
local function MissThenSolve(h, shown)
    h:Slash("/tlk puzzle")
    local puzzle = shown[#shown]

    h:Key(tostring(WrongAnswer(puzzle)), true)
    h:Key(tostring(puzzle.answer), true)
    h:Advance(2)

    return puzzle
end

-- A fresh skill's record, with fields on top.
local function Record(fields)
    local record = { asked = 0, box = 1, due = 0, firstTry = 0, lastAt = 0, recent = "" }

    for key, value in pairs(fields or {}) do
        record[key] = value
    end

    return record
end

test("a first-try right moves a skill up a box and a miss sends it back, due again after its box's interval", function()
    local _, _, ns = LoadKid()
    local skills = ns.ScholarSkills
    local right = skills.Next(Record({ asked = 2, box = 2, firstTry = 1, recent = "01" }), true, 7, 100)

    eq(right.box, 3)
    eq(right.due, (7 + skills.Interval[3]) - 1, "due after box 3's interval")
    eq(right.asked, 3)
    eq(right.firstTry, 2)
    eq(right.recent, "011")
    eq(right.lastAt, 100)
    local missed = skills.Next(Record({ asked = 5, box = 4, firstTry = 5, recent = "11111" }), false, 9, 200)

    eq(missed.box, 1, "a miss starts the skill over")
    eq(missed.due, 9, "due at the very next riddle of its subject")
    eq(missed.firstTry, 5)
    eq(missed.recent, "11110", "only the last five first tries are kept")
    eq(skills.Next(Record({ box = skills.Boxes }), true, 1, 0).box, skills.Boxes, "the top box is the top")
end)

test("the next skill is a new or due one, the lower its box the likelier; when all sit out, the one due soonest", function()
    local _, _, ns = LoadKid()
    local skills = ns.ScholarSkills

    local records = {
        a = Record({ asked = 3, box = 5, due = 40 }), b = Record({ asked = 2, box = 1, due = 10 }),
        c = Record({ asked = 4, box = 4, due = 30 }),
    }

    local function RecordOf(kind) return records[kind] end

    local function Picks(count)
        local seen = {}

        for roll = 1, 20 do
            local kind = skills.Choose({ "a", "b", "c" }, RecordOf, count, function(m, n) return math.min(n, (m + roll) - 1) end)

            seen[kind] = true
        end

        local list = {}

        for kind in pairs(seen) do list[#list + 1] = kind end

        table.sort(list)

        return table.concat(list, ",")
    end

    eq(Picks(10), "b", "the missed skill is due; the mastered ones sit out")
    eq(Picks(5), "b", "before it's due, a skill in a low box still gets extra practice")
    records.b.box = 3
    eq(Picks(5), "b", "when every skill rests, the one due soonest is asked")
    records.b.due = 35
    eq(Picks(5), "c", "and that follows the due dates")
    records.b = Record({ asked = 2, box = 1, due = 10 })
    records.c = Record()
    eq(Picks(10), "b,c", "a new skill joins the due one")
    eq(skills.Choose({ "a", "c" }, RecordOf, 10, function(m) return m end), "c", "a new skill outweighs a resting one")
end)

test("a skill is mastered from box 4, and worked on when its last first try missed or most recent ones did", function()
    local _, _, ns = LoadKid()
    local skills = ns.ScholarSkills

    truthy(skills.Mastered(Record({ box = 4 })))
    falsy(skills.Mastered(Record({ box = 3 })))
    truthy(skills.Struggling(Record({ asked = 2, recent = "10" })), "the last first try missed")
    truthy(skills.Struggling(Record({ asked = 5, recent = "00011" })), "two of five right")
    falsy(skills.Struggling(Record({ asked = 5, recent = "01011" })), "three of five right")
    truthy(skills.Struggling(Record({ asked = 1, recent = "0" })), "one miss is being worked on: it comes right back")
    falsy(skills.Struggling(Record({ asked = 2, recent = "01" })), "two riddles say too little about the rest")
    eq(skills.Name("math.skip"), "skip counting")
end)

test("a math riddle's missed first try is recorded and brings its skill back as the next math riddle", function()
    local _, addon, ns = LoadKid({ ["Scholar.quests"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)
    local missed = MissThenSolve(_, shown)
    local skills = addon.Modules.Scholar.Records.skills
    local record = skills:Get(missed.kind)

    eq(record.asked, 1)
    eq(record.firstTry, 0, "the right second try doesn't count as a first try")
    eq(record.box, 1)
    eq(record.recent, "0")
    eq(addon.State:Get("Scholar.mathCount"), 1)
    local miss = addon.Modules.Scholar.Records.misses:Get("1")

    eq(miss.kind, missed.kind)
    eq(miss.right, missed.choices[missed.answer])
    truthy(miss.prompt ~= "", "it keeps the question")

    -- The grade's other skills rest (mastered, not due), so only the missed one is due.
    for _, kind in ipairs(ns.Puzzles.Kinds("math", 2, true)) do
        if kind ~= missed.kind then
            skills:Set(kind, { asked = 3, box = 5, due = 99, firstTry = 3, recent = "111" })
        end
    end

    eq(Solve(_, shown).kind, missed.kind, "the missed skill comes right back")
end)

test("math and reading keep their own difficulty: three first-try rights in a row raise only their subject's", function()
    local h, addon, ns = LoadKid({ ["Scholar.quests"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)

    for _ = 1, 3 do Solve(h, shown) end

    eq(addon.State:Get("Scholar.mathLevel"), 2, "math got harder")
    eq(addon.State:Get("Scholar.readingLevel"), 1, "reading didn't")
    eq(addon.State:Get("Scholar.mathRun"), 3)
    MissThenSolve(h, shown)
    eq(addon.State:Get("Scholar.mathRun"), 0, "a miss starts the run over")
    eq(addon.State:Get("Scholar.mathLevel"), 2, "one miss doesn't make it easier")
    eq(shown[#shown].subject, "math")
end)

test("/tlk report gives each subject's level, first-try rate, mastered skills and recent misses", function()
    local h, _, ns = LoadKid({ ["Scholar.quests"] = false })
    local shown = Watch(ns)
    local from = (#h.printed + 1)

    h:Slash("/tlk report")
    local empty = table.concat(h.printed, "\n", from)

    truthy(empty:find("no riddles answered yet", 1, true), empty)
    truthy(empty:find("Math (level 1 of 3): no riddles yet.", 1, true), empty)

    for _ = 1, 3 do Solve(h, shown) end

    local missed = MissThenSolve(h, shown)

    from = (#h.printed + 1)
    h:Slash("/tlk report")
    local report = table.concat(h.printed, "\n", from)

    truthy(report:find("4 riddles, 75% right on the first try.", 1, true), report)
    truthy(report:find("Recent misses, newest first:", 1, true), report)
    truthy(report:find(ns.ScholarSkills.Name(missed.kind), 1, true), report)
    truthy(report:find(("the answer is %s)"):format(missed.choices[missed.answer]), 1, true), report)

    -- Every printed line starts with the addon's colored name, so a miss that spilled over would leave one without it.
    for line in report:gmatch("[^\n]+") do
        truthy(line:find("^|c"), "each miss on one line: " .. line)
    end
end)

test("Generate asks the kind it's given, and refuses a kind the grade doesn't ask", function()
    local _, _, ns = LoadKid()
    local Puzzles = ns.Puzzles
    local kinds = Puzzles.Kinds("math", 2)

    eq(table.concat(kinds, ","), "math.add,math.subtract,math.skip,math.coins")
    kinds[1] = "changed"
    eq(Puzzles.Kinds("math", 2)[1], "math.add", "a fresh array each time")
    local puzzle = Puzzles.Generate({ grade = 2, kind = "math.coins", random = math.random, subject = "math" })

    eq(puzzle.kind, "math.coins")

    throws(function() Puzzles.Generate({ grade = 0, kind = "math.ratio", random = math.random, subject = "math" }) end,
        "isn't a math kind at grade 0")
end)
