-- How a Scholar riddle teaches (ScholarPuzzles.lua and Scholar.lua): the answer can't be found by its place among the
-- numbers, the mistake a riddle exists to catch is always a choice, a wrong pick says why it's wrong, the help climbs
-- from a strategy to a worked step to the answer shown with its working, and praise names the strategy or the
-- persistence.

local Kit = use("scholar")
local Banner, LoadKid, Watch = Kit.Banner, Kit.LoadKid, Kit.Watch

-- Wrong answers, in order, that aren't puzzle's answer.
local function Wrongs(puzzle)
    local out = {}

    for i = 1, 4 do
        if i ~= puzzle.answer then out[#out + 1] = i end
    end

    return out
end

test("the answer's rank among four numbers is as likely to be any of the four, and required mistakes are kept", function()
    local _, _, ns = LoadKid()
    local puzzleKit = ns.Puzzles.Kit
    local ranks = { 0, 0, 0, 0 }
    local state = { roll = math.random }

    math.randomseed(3)

    for _ = 1, 400 do
        local wrongs = puzzleKit.WrongNumbers(state, 50, {})
        local rank = 1

        for _, n in ipairs(wrongs) do
            if n < 50 then rank = (rank + 1) end
        end

        ranks[rank] = (ranks[rank] + 1)
    end

    for rank, count in ipairs(ranks) do
        truthy((count > 60) and (count < 140), ("rank %d came up %d times in 400"):format(rank, count))
    end

    for _ = 1, 50 do
        local wrongs, whys = puzzleKit.WrongNumbers(state, 49, { 61, { 51, required = true, why = "You didn't borrow." }, 40 })
        local kept

        for i, n in ipairs(wrongs) do
            if n == 51 then kept = whys[i] end
        end

        eq(kept, "You didn't borrow.", "the no-borrow answer is always a choice, with its why")
    end
end)

test("a hint is kept when it only says what the riddle shows, and replaced when it names a number the riddle doesn't", function()
    local _, _, ns = LoadKid()
    local puzzleKit = ns.Puzzles.Kit
    local state = { grade = 1, level = 1, roll = math.random, subject = "math" }
    local text = { explain = "{a} - {b} = {v}.", hint = "Start at {a} and count back {b}.", prompt = "What is {a} - {b}?" }
    local back = puzzleKit.Finish(state, "math.subtract", text, { a = 4, b = 2, v = 2 }, "2", { "3", "1", "6" })

    eq(back.hint, "Start at 4 and count back 2.", "the 2 is in the question")

    local told = puzzleKit.Finish(state, "math.subtract", { explain = "x", hint = "It's {v}.", prompt = "What is {a} - {b}?" },
        { a = 4, b = 2, v = 2 }, "2", { "3", "1", "6" })

    eq(told.hint, puzzleKit.Words.hintFallback, "the hint named the answer the question hides")

    local whys = puzzleKit.Finish(state, "math.subtract", text, { a = 4, b = 2, v = 2 }, "2",
        { { "6", why = "You added." }, "3", "1" })

    for i, choice in ipairs(whys.choices) do
        eq(whys.whys[i], ((choice == "6") and "You added.") or nil, "each wrong choice keeps its why")
    end
end)

test("each miss says why that choice is wrong and climbs the hint ladder, ending with the answer glowing", function()
    local h, _, ns = LoadKid({ ["Scholar.mode"] = "gate", ["Scholar.quests"] = false })
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")
    local puzzle = shown[#shown]

    -- The riddle on screen is the one Scholar keeps, so its fields can be set for the test.
    puzzle.step, puzzle.whys[Wrongs(puzzle)[1]] = "First, line up the tens.", "That's what adding gives."
    local wrongs = Wrongs(puzzle)

    h:Key(tostring(wrongs[1]), true)
    truthy(Banner(h):find("That's what adding gives.", 1, true), Banner(h))
    truthy(Banner(h):find("Hint:", 1, true), "the first miss gives the strategy: " .. Banner(h))
    h:Key(tostring(wrongs[2]), true)
    truthy(Banner(h):find("Try this:", 1, true) and Banner(h):find("line up the tens", 1, true), Banner(h))
    h:Key(tostring(wrongs[3]), true)
    truthy(Banner(h):find("Here's how:", 1, true), "the third miss shows the working: " .. Banner(h))
    local frame = rawget(h.env, "TheLanKrewToolKitScholar")

    eq(frame.Buttons[puzzle.answer].State, "reveal", "the right answer glows")
    h:Key(tostring(puzzle.answer), true)
    local said = Banner(h)
    local persistent = false

    for _, line in ipairs(ns.ScholarWords.persistence) do
        persistent = (persistent or (said:find(line, 1, true) ~= nil))
    end

    truthy(persistent, "after misses, the praise is for not giving up: " .. said)
end)

test("a first-try right shows the working and praises the strategy, not the child", function()
    local h, _, ns = LoadKid({ ["Scholar.quests"] = false })
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")
    local puzzle = shown[#shown]

    h:Key(tostring(puzzle.answer), true)
    truthy(Banner(h):find(puzzle.explanation, 1, true), Banner(h))
    truthy(Banner(h):find(puzzle.praise, 1, true), Banner(h))

    for _, line in ipairs(ns.ScholarWords.praise) do
        falsy(line:find("brain", 1, true) or line:find("smart", 1, true) or line:find("genius", 1, true), line)
    end
end)
