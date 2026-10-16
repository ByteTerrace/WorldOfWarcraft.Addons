-- How Scholar's quest riddles teach from the open quest book (ScholarQuests.lua): each kind's step walks to the line,
-- each wrong choice says why (naming the other quest it came from, or the mix-up of start and end), a title never gives
-- the answer away, a missing word's wrong answers are words of its kind, and praise names the strategy.

local Kit = use("scholar")
local Banner = Kit.Banner

local Accept = Kit.Accept
local LoadKid = Kit.LoadKid
local Watch = Kit.Watch

local Wolves = {
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", header = "Elwynn Forest", id = 33,
    objectives = { { required = 8, text = "Tough Wolf Meat" } },
    text = ("The wolves of Elwynn grow bolder every night. Yesterday they carried off a sheep from the Stonefield farm. "
        .. "Bring me their meat, and the farmers will sleep easier."),
    title = "Wolves Across the Border",
}

-- A quest puzzle about quest, as Scholar asks it: an enUS Alliance player's.
local function Ask(h, ns, quest, known)
    return ns.Puzzles.Generate({ context = { faction = "Alliance", locale = "enUS" }, known = known, quest = quest,
        random = h.env.math.random, subject = "quest" })
end

-- A turned-in quest with everything to ask about, and two more the player has seen.
local Turned = {
    ender = "Marshal McBride", endPlace = "Eastvale Logging Camp", giver = "Eagan Peltskinner", goal = Wolves.goal,
    key = "33", objective1 = "Tough Wolf Meat", objective2 = "Wolf Fang", place = "Goldshire", required1 = 8,
    required2 = 3, seen = 10, text = Wolves.text, title = "Wolves Across the Border", turnedIn = true, type1 = "item",
    type2 = "item", zone = "Elwynn Forest",
}

local Seen = { Turned,
    { giver = "Marshal Dughan", key = "40", objective1 = "Kobold Vermin", place = "Fargodeep Mine", required1 = 10, seen = 9,
        title = "The Fargodeep Mine", type1 = "monster" },
    { giver = "Billy Maclure", key = "41", objective1 = "Billy's Pie", place = "Maclure Vineyards", required1 = 1, seen = 8,
        title = "Lost Necklace", type1 = "item" },
}

-- Turned without its text or objectives, so who and where are asked.
local function Plain()
    local plain = {}

    for key, value in pairs(Turned) do plain[key] = value end

    plain.text, plain.objective1, plain.objective2 = nil, nil, nil

    return plain
end

-- Every puzzle about quest across seeds, as Ask gives them.
local function Puzzles(h, ns, quest, known)
    local puzzles = {}

    for seed = 1, 300 do
        h:SeedRandom(seed)
        puzzles[#puzzles + 1] = Ask(h, ns, quest, known)
    end

    return puzzles
end

test("every quest riddle teaches from the book: a step, a why for each wrong choice, and the strategy praised", function()
    local h, _, ns = LoadKid()
    local kinds = {}

    for _, quest in ipairs({ Turned, Plain(), Seen[2] }) do
        for _, puzzle in ipairs(Puzzles(h, ns, quest, Seen)) do
            local answer = puzzle.choices[puzzle.answer]
            local named = (tonumber(answer) == nil)

            kinds[puzzle.kind] = true
            truthy(puzzle.step, puzzle.kind .. " has a worked step")
            falsy(named and puzzle.step:find(answer, 1, true), puzzle.kind .. "'s step doesn't name it: " .. puzzle.step)
            falsy(named and puzzle.hint:find(answer, 1, true), puzzle.kind .. "'s hint doesn't name it: " .. puzzle.hint)
            truthy(puzzle.explanation:find("quest book", 1, true), "the explanation points into the book: " .. puzzle.explanation)
            truthy(puzzle.explanation:find(answer, 1, true), "and says the answer: " .. puzzle.explanation)
            falsy(puzzle.explanation:lower():find("wrong", 1, true), puzzle.explanation)
            truthy(puzzle.praise:find("quest", 1, true), puzzle.kind .. " praises the strategy: " .. puzzle.praise)

            for i, choice in ipairs(puzzle.choices) do
                if i ~= puzzle.answer then
                    truthy((puzzle.whys[i] or "") ~= "", ("%s says why %q is wrong"):format(puzzle.kind, choice))
                end
            end
        end
    end

    for _, kind in ipairs({ "quest.giver", "quest.ender", "quest.place", "quest.endPlace", "quest.count", "quest.objective",
        "quest.blank", "quest.title" }) do
        truthy(kinds[kind], kind .. " was asked")
    end
end)

test("a wrong choice from another quest names that quest, and who or where at the other end is the first mix-up", function()
    local h, _, ns = LoadKid()
    local asked = {}

    for _, puzzle in ipairs(Puzzles(h, ns, Plain(), Seen)) do
        local whys = {}

        for i, choice in ipairs(puzzle.choices) do whys[choice] = puzzle.whys[i] end

        asked[puzzle.kind] = true

        if puzzle.kind == "quest.giver" then
            eq(whys["Marshal McBride"], "You turned this quest in to Marshal McBride, but someone else gave it to you.",
                "who took it is always a choice for who gave it")

            if whys["Marshal Dughan"] then
                eq(whys["Marshal Dughan"], 'Marshal Dughan gave you a different quest: "The Fargodeep Mine".')
            end
        elseif puzzle.kind == "quest.ender" then
            eq(whys["Eagan Peltskinner"], "Eagan Peltskinner gave you this quest, but you turned it in to someone else.")
        elseif puzzle.kind == "quest.place" then
            eq(whys["Eastvale Logging Camp"], "You turned this quest in at Eastvale Logging Camp, but it began somewhere else.")

            if whys["Maclure Vineyards"] then
                eq(whys["Maclure Vineyards"], 'You took a different quest in Maclure Vineyards: "Lost Necklace".')
            end
        elseif puzzle.kind == "quest.endPlace" then
            eq(whys.Goldshire, "Goldshire is where this quest began, but you finished somewhere else.")
        elseif (puzzle.kind == "quest.title") and whys["The Fargodeep Mine"] then
            eq(whys["The Fargodeep Mine"], '"The Fargodeep Mine" is a quest from Marshal Dughan.')
        end
    end

    for _, kind in ipairs({ "quest.giver", "quest.ender", "quest.place", "quest.endPlace", "quest.title" }) do
        truthy(asked[kind], kind .. " was asked")
    end
end)

test("a title that holds the answer's words isn't shown beside it, unless every choice shares them", function()
    local h, _, ns = LoadKid()

    local wolves = { giver = "Eagan Peltskinner", key = "1", objective1 = "Tough Wolf Meat", required1 = 1, seen = 3,
        title = "Wolves Across the Border", type1 = "item" }

    local asked = 0

    for _, puzzle in ipairs(Puzzles(h, ns, wolves, { wolves })) do
        if puzzle.kind == "quest.objective" then
            asked = (asked + 1)
            eq(puzzle.prompt, "What did the quest in your quest book ask you to bring?", "too few wolf things to offer")
        end
    end

    truthy(asked > 0)
    local known = { wolves }

    for i, item in ipairs({ "Wolf Pelt", "Wolf Heart", "Large Wolf Paw" }) do
        known[#known + 1] = { key = tostring(i + 1), objective1 = item, required1 = 1, seen = 1, title = ("Hunt " .. i), type1 = "item" }
    end

    asked = 0

    for _, puzzle in ipairs(Puzzles(h, ns, wolves, known)) do
        if puzzle.kind == "quest.objective" then
            asked = (asked + 1)
            truthy(puzzle.prompt:find("Wolves Across the Border", 1, true), puzzle.prompt)

            for _, choice in ipairs(puzzle.choices) do
                truthy(choice:find("Wolf", 1, true), "every choice is a wolf thing: " .. choice)
            end
        end
    end

    truthy(asked > 0)
    local galgar = { giver = "Galgar", key = "1", place = "Valley of Trials", seen = 1, title = "Galgar's Cactus Apple Surprise" }

    for _, puzzle in ipairs(Puzzles(h, ns, galgar, { galgar })) do
        falsy(puzzle.kind == "quest.title", "Galgar's name would give his quest away")
        eq(puzzle.prompt:find("Galgar's", 1, true) ~= nil, puzzle.kind ~= "quest.giver", puzzle.prompt)
    end
end)

-- Whether every one of choices matches pattern.
local function All(choices, pattern)
    for _, choice in ipairs(choices) do
        if not choice:find(pattern) then return false end
    end

    return true
end

test("a missing word's wrong answers are words of its kind, and its step quotes the words beside it", function()
    local h, _, ns = LoadKid()
    local quest = { key = "1", seen = 1, text = Wolves.text, title = "Wolves Across the Border" }
    local asked = {}

    for _, puzzle in ipairs(Puzzles(h, ns, quest, { quest })) do
        local answer = puzzle.choices[puzzle.answer]
        local choices = puzzle.choices
        local listed = table.concat(choices, ", ")

        asked[answer] = true

        if (answer == "bolder") or (answer == "easier") then
            truthy(All(choices, "er$"), "comparing words: " .. listed)
        elseif answer == "carried" then
            truthy(All(choices, "ed$"), "past doings: " .. listed)
        elseif (answer == "wolves") or (answer == "farmers") then
            truthy(All(choices, "^%l+s$"), "plural nouns: " .. listed)
            eq(puzzle.prompt:find(quest.title, 1, true) ~= nil, answer == "farmers", "\"Wolves\" in the title would give wolves away")
        elseif (answer == "Elwynn") or (answer == "Stonefield") then
            truthy(All(choices, "^%u%l+$"), "places: " .. listed)
        else
            truthy((answer == "night") or (answer == "sheep"), "only words of a known kind are asked: " .. answer)
            truthy(All(choices, "^%l+[^s]$"), "singular nouns: " .. listed)
        end

        for _, choice in ipairs(choices) do
            falsy((choice == "sleep") or (choice == "Yesterday") or (choice == "Bring"), "a word of no known kind: " .. choice)
        end

        local lead = puzzle.step:match('find "(.-)"')

        truthy(lead and puzzle.prompt:find(lead, 1, true), "the step quotes the words beside the blank: " .. puzzle.step)
    end

    for _, word in ipairs({ "bolder", "carried", "wolves", "Elwynn", "night" }) do
        truthy(asked[word], word .. " was asked")
    end
end)

test("a count's working reads as a sentence, and another objective's number is always a choice", function()
    local h, _, ns = LoadKid()

    local pelts = { giver = "Gretchen Dedmar", key = "1", objective1 = "Duskbat Pelt", objective2 = "Coarse Thread",
        required1 = 5, required2 = 3, seen = 1, title = "The Chill of Death", type1 = "item", type2 = "item" }

    local kobolds = { giver = "Marshal Dughan", key = "2", objective1 = "Kobold Vermin", required1 = 10, seen = 2,
        title = "The Fargodeep Mine", type1 = "monster" }

    local counted = {}

    for _, quest in ipairs({ pelts, kobolds }) do
        for _, puzzle in ipairs(Puzzles(h, ns, quest, { pelts, kobolds })) do
            if puzzle.kind == "quest.count" then
                counted[puzzle.explanation] = true

                if puzzle.choices[puzzle.answer] == "5" then
                    local three

                    for i, choice in ipairs(puzzle.choices) do
                        if choice == "3" then three = puzzle.whys[i] end
                    end

                    eq(three, "That's the number after Coarse Thread, not after Duskbat Pelt.", "the thread's 3 is a choice")
                end
            end
        end
    end

    truthy(counted['The quest book shows "Duskbat Pelt (5)": it asked you to bring 5 Duskbat Pelt.'])
    truthy(counted['The quest book shows "Kobold Vermin (10)": it asked you to defeat 10 Kobold Vermin.'])
end)

test("a quest nobody saw given is never a wrong answer to which quest a giver gave", function()
    local h, _, ns = LoadKid()
    local mine = { giver = "Marshal McBride", key = "1", seen = 3, title = "Kobold Camp Cleanup" }
    -- The log alone recorded it, so McBride might have given it too.
    local known = { mine, { key = "2", seen = 2, title = "Mystery Crate" } }

    local asked = 0

    for _, puzzle in ipairs(Puzzles(h, ns, mine, known)) do
        if puzzle.kind == "quest.title" then
            asked = (asked + 1)

            for _, choice in ipairs(puzzle.choices) do
                truthy(choice ~= "Mystery Crate", "a quest of unknown giver is never offered")
            end
        end
    end

    truthy(asked > 0, "which quest McBride gave was asked")
end)

test("on the riddle screen, a quest riddle's miss says why and its next miss walks to the line in the book", function()
    local h, _, ns = LoadKid({ ["Scholar.math"] = false, ["Scholar.style"] = "gate", ["Scholar.reading"] = false })
    local shown = Watch(ns)

    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local puzzle = shown[1]
    local wrongs = {}

    for i = 1, 4 do
        if i ~= puzzle.answer then wrongs[#wrongs + 1] = i end
    end

    h:Key(tostring(wrongs[1]), true)
    truthy(Banner(h):find(puzzle.whys[wrongs[1]], 1, true), Banner(h))
    h:Key(tostring(wrongs[2]), true)
    truthy(Banner(h):find(puzzle.step, 1, true), "the second miss gives the step: " .. Banner(h))
    local first, _, firstNs = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })

    shown = Watch(firstNs)
    Accept(first, Wolves)
    first:Slash("/tlk puzzle")
    first:Key(tostring(shown[1].answer), true)
    truthy(Banner(first):find(shown[1].explanation .. " " .. shown[1].praise, 1, true), Banner(first))
end)
