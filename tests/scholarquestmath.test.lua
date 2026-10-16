-- Math from the player's own quests (ScholarNumbers.lua's math.quest): its riddles count with what the quest book
-- recorded (an objective's count, name and giver, two objectives' total, a vendor's copper, the quests turned in), each
-- answer is what its prompt works out to, and Scholar asks it only while the quest book holds a quest.

local Kit = use("scholar")
local Accept = Kit.Accept
local LoadKid = Kit.LoadKid
local Numbers = Kit.Numbers
local Watch = Kit.Watch

local Candles = {
    goal = "Bring 6 Kobold Candles to Marshal Dughan.", header = "Elwynn Forest", id = 60,
    objectives = { { required = 6, text = "Kobold Candle" } }, text = "The kobolds hoard candles in the mine.",
    title = "Kobold Candles",
}

local Vermin = {
    goal = "Defeat 10 Kobold Vermin.", header = "Elwynn Forest", id = 7,
    objectives = { { required = 10, text = "Kobold Vermin", type = "monster" } }, text = "Kobolds have overrun the woods.",
    title = "Kobold Camp Cleanup",
}

local Wolves = {
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", header = "Elwynn Forest", id = 33,
    objectives = { { required = 8, text = "Tough Wolf Meat" } }, text = "The wolves grow bolder every night.",
    title = "Wolves Across the Border",
}

-- options.random for Generate: the test Lua's own generator, refusing ranges the client's random would.
local function Roll(m, n)
    assert((m == math.floor(m)) and (n == math.floor(n)) and (m <= n), ("random(%s, %s) is not a valid range"):format(tostring(m), tostring(n)))

    return math.random(m, n)
end

-- Every math.quest riddle for seeds at grade and level, with the player's quest book and context.
local function Riddles(ns, grade, level, seeds, context)
    local out = {}
    local known = ns.QuestBook.All()

    for seed = 1, seeds do
        math.randomseed((grade * 1000) + seed)

        out[seed] = ns.Puzzles.Generate({ context = context, grade = grade, kind = "math.quest", known = known, level = level, random = Roll,
            subject = "math" })
    end

    return out
end

-- The answer a quest riddle's prompt works out to, as its choice reads.
local function Worked(prompt)
    local held, turned = prompt:match("holds (%d+) quests, and you've turned in (%d+)")

    if held then
        return tostring(held - turned)
    end

    local p = tonumber(prompt:match("pays (%d+) copper") or "")

    if p then
        local mine = tonumber(prompt:match("You have (%d+) copper") or "0")
        local r = tonumber(prompt:match("all (%d+) bring") or prompt:match("you sell (%d+)"))

        return ((mine + (r * p)) .. " copper")
    end

    local n = Numbers(prompt)

    if prompt:find("in all") then
        return tostring(n[1] + n[2])
    end

    return tostring(n[1] - n[2])
end

test("a quest riddle counts with the quest book's own objectives, and its answer is what they work out to", function()
    local h, _, ns = LoadKid()

    Accept(h, Wolves)
    Accept(h, Candles, "Marshal Dughan")
    Accept(h, Vermin, "Marshal McBride")
    local seen = {}

    for _, grade in ipairs({ 0, 1, 2, 3, 4, 6 }) do
        for _, p in ipairs(Riddles(ns, grade, 2, 40, { copper = 30, faction = "Alliance" })) do
            local where = ("grade %d: %q"):format(grade, p.prompt)

            eq(p.choices[p.answer], Worked(p.prompt), where)
            truthy(#p.prompt <= 240, where)

            if p.prompt:find("Tough Wolf Meat", 1, true) and p.prompt:find("Eagan Peltskinner", 1, true) then
                seen.giver = true
            end

            seen.defeat = (seen.defeat or (p.prompt:find("10 Kobold Vermin defeated", 1, true) ~= nil))

            seen.total = (seen.total or ((p.prompt:find("asks for 8 Tough Wolf Meat and 6 Kobold Candle", 1, true)
                or p.prompt:find("asks for 6 Kobold Candle and 8 Tough Wolf Meat", 1, true)) ~= nil))

            seen.vendor = (seen.vendor or ((grade >= 3) and (p.prompt:find("pays (%d+) copper for each") ~= nil)))
            seen.purse = (seen.purse or (p.prompt:find("You have 30 copper", 1, true) ~= nil))
            seen.stock = (seen.stock or (p.prompt:find("has a quest:", 1, true) ~= nil) or (p.prompt:find("has two quests:", 1, true) ~= nil))

            for i = 1, 4 do
                truthy((i == p.answer) or (p.whys[i] ~= nil), "every wrong choice says why at " .. where)
            end
        end
    end

    truthy(seen.giver, "how many more an objective needs, naming its giver")
    truthy(seen.defeat, "a foe objective is counted as foes to defeat")
    truthy(seen.total, "two items' total, both from the book")
    truthy(seen.vendor and seen.purse, "a vendor's copper, sometimes with the player's own")
    falsy(seen.stock, "with quests in the book, no riddle is about a stock hero")
end)

test("the quests turned in are counted, and a quest riddle without a fitting record tells a stock one", function()
    local h, _, ns = LoadKid()

    Accept(h, Wolves)
    Accept(h, Candles, "Marshal Dughan")
    h:OpenTurnIn(60, "Marshal Dughan", "Thank you.")
    h:CompleteQuest()
    local book = false

    for _, p in ipairs(Riddles(ns, 1, 1, 60)) do
        if p.prompt:find("holds 2 quests, and you've turned in 1 of them", 1, true) then
            book = true
            eq(p.choices[p.answer], "1")
        end
    end

    truthy(book, "the book's own counts make a riddle")
    local _, _, fresh = LoadKid()

    for _, p in ipairs(Riddles(fresh, 2, 2, 30)) do
        eq(p.choices[p.answer], Worked(p.prompt), p.prompt)

        truthy(p.prompt:find("has a quest:", 1, true) or p.prompt:find("has two quests:", 1, true) or p.prompt:find("gathers", 1, true),
            "a stock riddle without a quest book: " .. p.prompt)
    end
end)

test("Scholar asks math from quests only while the quest book holds a quest", function()
    local h, _, ns = LoadKid({ ["Scholar.grade"] = "1", ["Scholar.quests"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)

    for _ = 1, 25 do Kit.Solve(h, shown) end

    for _, puzzle in ipairs(shown) do
        truthy(puzzle.kind ~= "math.quest", "no quest math with an empty quest book")
    end

    Accept(h, Wolves)
    local asked

    for _ = 1, 40 do
        local puzzle = Kit.Solve(h, shown)

        if puzzle.kind == "math.quest" then
            asked = puzzle

            break
        end
    end

    truthy(asked, "a quest in the book brings quest math")
    truthy(asked.prompt:find("Tough Wolf Meat", 1, true) or asked.prompt:find("1 quests", 1, true), "it counts with the book: " .. asked.prompt)
end)
