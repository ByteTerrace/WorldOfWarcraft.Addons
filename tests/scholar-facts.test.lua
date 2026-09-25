-- Riddles made from the player's own game (TheLanKrewToolKit/ScholarFacts.lua). Like
-- scholar.test.lua, the puzzle files load on their own, so other files' edits can't break these.

local FILES = { "ScholarWords.lua", "ScholarPuzzles.lua", "ScholarFacts.lua" }

local function Load()
    local addon = assert(__addons.TheLanKrewToolKit, "TheLanKrewToolKit isn't an addon")
    local sources = {}
    for i, name in ipairs(FILES) do
        for j, file in ipairs(addon.files) do
            if file == name then
                sources[i] = addon.sources[j]
            end
        end
        assert(sources[i], name .. " isn't listed in TheLanKrewToolKit_Camelot.toc")
    end
    Harness.DefineAddOn("ScholarFacts", { sources = sources })
    return Harness.new():LoadFiles("ScholarFacts").Puzzles
end

local function Rng(seed)
    local state = seed % 2147483646 + 1
    return function(m, n)
        assert(m == math.floor(m) and n == math.floor(n) and m <= n, "bad range")
        state = state * 48271 % 2147483647
        return m + state % (n - m + 1)
    end
end

local function Valid(p, where)
    eq(#p.choices, 4, where)
    local seen = {}
    for _, choice in ipairs(p.choices) do
        falsy(seen[choice:lower()], "distinct choices at " .. where)
        seen[choice:lower()] = true
    end
    truthy(p.answer >= 1 and p.answer <= 4, where)
    truthy(#p.prompt <= 240, where)
    falsy(p.hint:find(p.choices[p.answer], 1, true) and #p.choices[p.answer] > 1, "the hint doesn't give it away at " .. where)
end

local OBJECTIVE = { type = "objective", quest = "The Fargodeep Mine", item = "Gnoll Paw", have = 5, need = 8 }

test("quest objectives make subtraction riddles with the real numbers", function()
    local puzzles = Load()
    for seed = 1, 50 do
        local p = puzzles.FromFact(OBJECTIVE, { grade = 1, random = Rng(seed) })
        Valid(p, "seed " .. seed)
        eq(p.kind, "math.objective")
        eq(p.choices[p.answer], "3")
        truthy(p.prompt:find("\"The Fargodeep Mine\" needs Gnoll Paw x8. You have 5.", 1, true), p.prompt)
    end
end)

test("numbers too big for the grade are skipped, not simplified wrongly", function()
    local puzzles = Load()
    eq(puzzles.FromFact({ type = "objective", quest = "Q", item = "Paw", have = 3, need = 15 }, { grade = 0, random = Rng(1) }), nil)
    truthy(puzzles.FromFact({ type = "objective", quest = "Q", item = "Paw", have = 3, need = 15 }, { grade = 1, random = Rng(1) }))
    eq(puzzles.FromFact({ type = "objective", quest = "Q", item = "Paw", have = 8, need = 8 }, { grade = 3, random = Rng(1) }), nil, "nothing left to find")
end)

test("reading your quest log: the answer is the item, other quests' items are the distractors", function()
    local puzzles = Load()
    local fact = { type = "questRead", quest = "The Fargodeep Mine", item = "Gnoll Paw", others = { "Linen Cloth", "Wolf Meat", "Gnoll Paw", "Candle" } }
    for seed = 1, 30 do
        local p = puzzles.FromFact(fact, { grade = 2, random = Rng(seed) })
        Valid(p, "seed " .. seed)
        eq(p.subject, "reading")
        eq(p.choices[p.answer], "Gnoll Paw")
    end
    local few = puzzles.FromFact({ type = "questRead", quest = "Q", item = "Gnoll Paw", others = {} }, { grade = 2, random = Rng(3) })
    Valid(few, "stock distractors")
    eq(puzzles.FromFact(fact, { grade = 0, random = Rng(1) }), nil, "kindergarten doesn't read quest logs")
end)

test("stacks: repeated addition in grade 2, multiplication from grade 3", function()
    local puzzles = Load()
    local fact = { type = "stacks", item = "arrows", stacks = 3, size = 20 }
    local two = puzzles.FromFact(fact, { grade = 2, random = Rng(4) })
    eq(two.choices[two.answer], "60")
    truthy(two.explanation:find("20 + 20 + 20 = 60", 1, true), two.explanation)
    local three = puzzles.FromFact(fact, { grade = 3, random = Rng(4) })
    truthy(three.explanation:find("3 x 20 = 60", 1, true), three.explanation)
    eq(puzzles.FromFact({ type = "stacks", item = "arrows", stacks = 5, size = 20 }, { grade = 2, random = Rng(1) }), nil)
end)

test("selling to a merchant counts real coins", function()
    local puzzles = Load()
    local p = puzzles.FromFact({ type = "sell", item = "Linen Cloth", count = 4, price = 35 }, { grade = 4, random = Rng(9) })
    Valid(p, "sell")
    eq(p.choices[p.answer], "1 silver 40 copper")
    eq(puzzles.FromFact({ type = "sell", item = "Linen Cloth", count = 4, price = 35 }, { grade = 3, random = Rng(9) }), nil,
        "grade 3 stays under a silver")
    local small = puzzles.FromFact({ type = "sell", item = "Linen Cloth", count = 4, price = 5 }, { grade = 3, random = Rng(9) })
    eq(small.choices[small.answer], "20 copper")
end)

test("XP to the next level rounds up: a leftover needs one more quest", function()
    local puzzles = Load()
    local p = puzzles.FromFact({ type = "xp", need = 1400, per = 350 }, { grade = 5, random = Rng(2) })
    eq(p.choices[p.answer], "4")
    truthy(p.explanation:find("exactly", 1, true))
    local q = puzzles.FromFact({ type = "xp", need = 1500, per = 350 }, { grade = 5, random = Rng(2) })
    eq(q.choices[q.answer], "5")
    truthy(q.explanation:find("with 100 XP left over, so 5 quests", 1, true), q.explanation)
    eq(puzzles.FromFact({ type = "xp", need = 1500, per = 350 }, { grade = 3, random = Rng(2) }), nil)
end)

test("text that isn't plain is refused: no escape codes from the game reach the screen", function()
    local puzzles = Load()
    eq(puzzles.FromFact({ type = "objective", quest = "|cffff0000Evil|r", item = "Paw", have = 1, need = 5 }, { grade = 2, random = Rng(1) }), nil)
    eq(puzzles.FromFact({ type = "objective", quest = "Q", item = ("x"):rep(31), have = 1, need = 5 }, { grade = 2, random = Rng(1) }), nil)
    eq(puzzles.FromFact({ type = "nope" }, { grade = 2, random = Rng(1) }), nil)
    eq(puzzles.FromFact(OBJECTIVE, { grade = 2 }), nil, "no random, no riddle")
end)

test("every fact type across every grade gives a valid riddle or none", function()
    local puzzles = Load()
    local facts = {
        OBJECTIVE,
        { type = "objective", quest = "Q", item = "Paw", have = 12, need = 90 },
        { type = "questRead", quest = "Q", item = "Paw", others = { "Fang" } },
        { type = "stacks", item = "arrows", stacks = 4, size = 25 },
        { type = "sell", item = "Cloth", count = 12, price = 80 },
        { type = "xp", need = 2250, per = 400 },
    }
    for _, fact in ipairs(facts) do
        for grade = 0, 6 do
            for seed = 1, 20 do
                local p = puzzles.FromFact(fact, { grade = grade, random = Rng(seed * 31 + grade) })
                if p then
                    Valid(p, fact.type .. " grade " .. grade .. " seed " .. seed)
                end
            end
        end
    end
end)
