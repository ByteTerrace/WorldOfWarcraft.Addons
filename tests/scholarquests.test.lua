-- Scholar's quest riddles: what the quest book records, what it asks, and the open book.

local function LoadKid(extra)
    local char = { ["Scholar.enabled"] = true }
    for key, value in pairs(extra or {}) do char[key] = value end
    local h = Harness.New({ saved = { TheLanKrewToolKitCharDB = char } })
    h:SeedRandom(7)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon, ns
end

-- Every puzzle the screen shows, in order.
local function Watch(ns)
    local shown = {}
    local view = ns.ScholarView
    local show = view.Show
    view.Show = function(puzzle, info)
        shown[#shown + 1] = puzzle
        return show(puzzle, info)
    end
    return shown
end

local function Showing(h)
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    return overlay ~= nil and overlay:IsShown()
end

local Wolves = {
    id = 33, title = "Wolves Across the Border", header = "Elwynn Forest",
    text = "The wolves of Elwynn grow bolder every night. Yesterday they carried off a sheep from the Stonefield farm. "
        .. "Bring me their meat, and the farmers will sleep easier.",
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.",
    objectives = { { text = "Tough Wolf Meat", required = 8 } },
}

local function Accept(h, spec, giver)
    h:OfferQuest(spec, giver or "Eagan Peltskinner")
    h:AcceptQuest()
end

local function Quests(addon)
    return addon.Modules.QuestBook.Records.quests
end

test("an accepted quest is recorded as its offer showed it, objectives from the log", function()
    local h, addon = LoadKid()
    h:SetLocation({ zone = "Elwynn Forest", subZone = "Goldshire" })
    Accept(h, Wolves)
    local record = Quests(addon):Get("33")
    eq(record.title, "Wolves Across the Border")
    eq(record.giver, "Eagan Peltskinner")
    eq(record.place, "Goldshire")
    eq(record.goal, "Bring 8 Tough Wolf Meat to Eagan Peltskinner.")
    truthy(record.text:find("Stonefield farm", 1, true))
    eq(record.objective1, "Tough Wolf Meat", "the count is left out")
    eq(record.required1, 8)
    truthy(record.fresh)
    falsy(record.turnedIn)
end)

test("a turned-in quest adds who took it, where, and the reward text, and is fresh again", function()
    local h, addon = LoadKid()
    h:SetLocation({ zone = "Elwynn Forest", subZone = "Goldshire" })
    Accept(h, Wolves)
    Quests(addon):Set("33", { fresh = false })
    h:SetLocation({ zone = "Elwynn Forest", subZone = "Eastvale Logging Camp" })
    h:OpenTurnIn(33, "Marshal McBride", "The farmers thank you.")
    h:CompleteQuest()
    local record = Quests(addon):Get("33")
    truthy(record.turnedIn)
    eq(record.ender, "Marshal McBride")
    eq(record.endPlace, "Eastvale Logging Camp")
    eq(record.reward, "The farmers thank you.")
    truthy(record.fresh, "turning it in is a new exposure")
end)

test("an area trigger's quest is recorded from the quest log, the player's open book", function()
    local h, addon, ns = LoadKid()
    h:SetLocation({ zone = "Elwynn Forest", subZone = "Goldshire" })
    local id = h:AutoAcceptQuest({ title = "A Threat Within", text = "Report to Marshal McBride in Northshire Abbey.",
        goal = "Speak with Marshal McBride.", objectives = { { text = "Report to Marshal McBride", type = "log" } } })
    local record = Quests(addon):Get(tostring(id))
    eq(record.title, "A Threat Within")
    eq(record.text, "Report to Marshal McBride in Northshire Abbey.")
    eq(record.goal, "Speak with Marshal McBride.")
    eq(record.giver, "", "no dialog named a giver")
    local shown = Watch(ns)
    h:Slash("/tlk puzzle")
    eq(shown[1].subject, "quest")
    truthy(shown[1].book:find("Taken in Goldshire.", 1, true), "the book says where it began: " .. shown[1].book)
end)

test("a quest giver whose name is secret is left out, and the quest is still recorded", function()
    local h, addon = LoadKid()
    h:SetRestriction("Encounter", true) -- an escort that starts inside a boss encounter
    Accept(h, Wolves)
    eq(Quests(addon):Field("33", "title"), "Wolves Across the Border")
    eq(Quests(addon):Field("33", "giver"), "", "the giver's name was secret")
end)

test("a quest the client can't name isn't recorded", function()
    local h, addon = LoadKid()
    h:Fire("QUEST_ACCEPTED", 4242) -- not in the log, so GetTitleForQuestID has no title for it
    falsy(Quests(addon):Has("4242"))
end)

test("a quest the book never saw is recorded when turned in, from its reward panel", function()
    local h, addon = LoadKid({ ["Scholar.enabled"] = false })
    Accept(h, Wolves)
    addon.State:Set("Scholar.enabled", true)
    h:SetLocation({ zone = "Elwynn Forest", subZone = "Eastvale Logging Camp" })
    h:OpenTurnIn(33, "Marshal McBride", "The farmers thank you.")
    h:CompleteQuest()
    local record = Quests(addon):Get("33")
    eq(record.title, "Wolves Across the Border", "the reward panel named it")
    eq(record.ender, "Marshal McBride")
    eq(record.endPlace, "Eastvale Logging Camp")
    truthy(record.turnedIn)
    eq(record.giver, "", "nobody saw who gave it")
    h:Fire("QUEST_TURNED_IN", 9001, 0, 0) -- a hidden tracking quest: no panel named it
    falsy(Quests(addon):Has("9001"))
end)

-- Asks a riddle now and answers it right.
local function Solve(h, shown)
    h:Slash("/tlk puzzle")
    h:Key(tostring(shown[#shown].answer), true)
    h:Advance(2)
    return shown[#shown]
end

test("quest riddles are preferred, two to every math or reading riddle: fresh quests first, then review", function()
    local h, addon, ns = LoadKid()
    local shown = Watch(ns)
    Accept(h, Wolves)
    local first = Solve(h, shown)
    eq(first.subject, "quest")
    truthy(first.book:find("Wolves Across the Border", 1, true), "the quest book is the quest")
    falsy(Quests(addon):Field("33", "fresh"), "asked")
    eq(Solve(h, shown).subject, "quest", "an older quest, for review")
    local third = Solve(h, shown).subject
    truthy(third == "math" or third == "reading", "then math or reading takes a turn: " .. third)
    eq(Solve(h, shown).subject, "quest", "and quests again")
    eq(Solve(h, shown).subject, "quest")
    eq(Solve(h, shown).subject, third == "math" and "reading" or "math", "math and reading take turns")
end)

test("with only quest riddles on, older quests come back for review", function()
    local h, _, ns = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)
    Accept(h, Wolves)
    for i = 1, 4 do
        eq(Solve(h, shown).subject, "quest", "riddle " .. i)
    end
end)

test("a quest riddle comes first over math and reading, newest quest first", function()
    local h, _, ns = LoadKid()
    local shown = Watch(ns)
    Accept(h, Wolves)
    h:Advance(5)
    Accept(h, { id = 40, title = "The Fargodeep Mine", text = "Kobolds have overrun the Fargodeep Mine.",
        objectives = { { text = "Kobold Vermin slain", required = 10, type = "monster" } } }, "Marshal Dughan")
    h:Slash("/tlk puzzle")
    eq(shown[1].questKey, "40", "the newest")
end)

test("every kind asks what the quest holds, with the right answer among four", function()
    local h, _, ns = LoadKid()
    local quest = {
        key = "33", title = "Wolves Across the Border", giver = "Eagan Peltskinner", place = "Goldshire",
        turnedIn = true, ender = "Marshal McBride", endPlace = "Eastvale Logging Camp", seen = 10,
        text = Wolves.text, goal = Wolves.goal, objective1 = "Tough Wolf Meat", required1 = 8, type1 = "item",
    }
    local known = { quest,
        { key = "40", title = "The Fargodeep Mine", giver = "Marshal Dughan", place = "Fargodeep Mine", objective1 = "Kobold Candle", required1 = 8, type1 = "item", seen = 9 },
        { key = "41", title = "Lost Necklace", giver = "Billy Maclure", place = "Maclure Vineyards", objective1 = "Billy's Pie", required1 = 1, type1 = "item", seen = 8 },
    }
    local expected = {
        ["quest.giver"] = "Eagan Peltskinner", ["quest.ender"] = "Marshal McBride", ["quest.place"] = "Goldshire",
        ["quest.endPlace"] = "Eastvale Logging Camp", ["quest.count"] = "8", ["quest.objective"] = "Tough Wolf Meat",
        ["quest.title"] = "Wolves Across the Border",
    }
    local seen = {}
    for seed = 1, 60 do
        h:SeedRandom(seed)
        local puzzle = ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = quest, known = known })
        seen[puzzle.kind] = true
        local answer = puzzle.choices[puzzle.answer]
        if puzzle.kind == "quest.blank" then
            truthy(puzzle.prompt:find("___", 1, true), "a word is missing")
            truthy(Wolves.text:find(answer, 1, true), "and it's the quest's own")
            for i, choice in ipairs(puzzle.choices) do
                if i ~= puzzle.answer then
                    falsy(puzzle.prompt:find("%f[%a]" .. choice .. "%f[%A]"), choice .. " isn't already in the sentence")
                end
            end
        else
            eq(answer, expected[puzzle.kind], puzzle.kind)
        end
        local distinct = {}
        for _, choice in ipairs(puzzle.choices) do distinct[choice:lower()] = true end
        local count = 0
        for _ in pairs(distinct) do count = count + 1 end
        eq(count, 4, "four different choices")
        truthy(puzzle.book:find(Wolves.text, 1, true), "the book holds the text")
        truthy(puzzle.book:find(answer, 1, true), puzzle.kind .. "'s answer is in the book")
    end
    for kind in pairs(expected) do
        truthy(seen[kind], kind .. " was asked")
    end
    truthy(seen["quest.blank"], "quest.blank was asked")
end)

test("a quest nothing can be asked about counts as asked, and the riddle falls back", function()
    local h, addon, ns = LoadKid()
    local shown = Watch(ns)
    Quests(addon):Set("99", { title = "Hmm", fresh = true, seen = 1 }) -- a title and nothing else
    -- Everything to ask about, but a title too long to show in a riddle.
    Quests(addon):Set("98", { title = "The Long and Winding Road to the Edge of the Known World Today",
        giver = "Eagan Peltskinner", place = "Goldshire", fresh = true, seen = 2 })
    eq(ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = Quests(addon):Get("99") }), nil)
    eq(ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = Quests(addon):Get("98") }), nil)
    h:Slash("/tlk puzzle")
    truthy(shown[1].subject ~= "quest", shown[1].subject)
    falsy(Quests(addon):Field("99", "fresh"))
    falsy(Quests(addon):Field("98", "fresh"))
end)

test("the quest book names who gave a quest and where, whichever the record holds", function()
    local h, _, ns = LoadKid()
    local function Book(quest)
        h:SeedRandom(1)
        return ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = quest, known = { quest } }).book
    end
    local both = Book({ key = "1", title = "Wolves", giver = "Eagan Peltskinner", place = "Goldshire", seen = 1 })
    truthy(both:find("From Eagan Peltskinner, in Goldshire.", 1, true), both)
    local giver = Book({ key = "1", title = "Wolves", giver = "Eagan Peltskinner", seen = 1 })
    truthy(giver:find("From Eagan Peltskinner.", 1, true), giver)
    local place = Book({ key = "1", title = "Wolves", place = "Goldshire", seen = 1 })
    truthy(place:find("Taken in Goldshire.", 1, true), place)
end)

test("the quest book asks fresh quests newest first, then the rest, the one asked longest ago first", function()
    local h, addon, ns = LoadKid()
    local quests = Quests(addon)
    quests:Set("1", { title = "Old Fresh", fresh = true, seen = 5 })
    quests:Set("2", { title = "New Fresh", fresh = true, seen = 10 })
    quests:Set("3", { title = "Asked Lately", seen = 7, askedAt = 30 })
    quests:Set("5", { title = "Asked Long Ago B", seen = 7, askedAt = 20 })
    quests:Set("4", { title = "Asked Long Ago A", seen = 8, askedAt = 20 })
    eq(table.concat(ns.QuestBook.Order(), ","), "2,1,4,5,3", "a tie goes by key")
    local all = {}
    for i, record in ipairs(ns.QuestBook.All()) do
        all[i] = record.key
    end
    eq(table.concat(all, ","), "2,4,3,5,1", "every record, newest seen first; a tie goes by key")
end)

test("the quest book opens in the riddle's place with the quest's text, and closes the same way", function()
    local h, _, ns = LoadKid()
    Watch(ns)
    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    truthy(Reveal(Harness.State(overlay.Hint.Label).text):find("Quest book", 1, true), "the hint is the book")
    h:Key("H", true)
    truthy(ns.ScholarView.BookOpen())
    truthy(Reveal(Harness.State(overlay.BookText).text):find("Stonefield", 1, true), "the quest's text")
    truthy(overlay.Book:IsShown())
    h:Key("H", true)
    falsy(ns.ScholarView.BookOpen())
end)

test("a long quest's text is kept whole, as the quest log shows it, through to the book", function()
    local h, addon, ns = LoadKid()
    local sentence = "The wolves grow bolder every night, and the farmers lie awake listening. "
    local long = { id = 35, title = "Long Nights", header = "Elwynn Forest", text = sentence:rep(30) .. "Help us.",
        goal = "Bring wolf meat.", objectives = {} }
    Accept(h, long)
    eq(Quests(addon):Field("35", "text"), long.text, "every word of it")
    local shown = Watch(ns)
    h:Slash("/tlk puzzle")
    truthy(shown[1].book:find("Help us.", 1, true), "the book ends as the quest does")
end)

test("a quest book too long for the screen scrolls, by wheel, arrow keys and D-pad, and the riddle fits", function()
    local h, _, ns = LoadKid()
    h.labelStyle = "Letters" -- a controller is connected
    h.env.UIParent:SetSize(1366, 600) -- a short screen: the harness's 14 px lines are shorter than the real font's
    local paragraph = "Greetings, rogue. I can see you've got the look of an adventurer about you. This is good. "
        .. "The world needs more of us restless souls, seeking fortune and glory. "
    local long = {
        id = 34, title = "The Great Outdoors", header = "Tirisfal Glades",
        text = paragraph:rep(20) .. "Have a seat near the fire and get comfortable.",
        goal = "Sit near Eleanor's Basic Campfire and wait until you receive the Boosted Rest buff.",
        objectives = { { text = "Sit near the campfire", required = 1, type = "log" }, { text = "Gain the Boosted Rest buff", required = 1, type = "log" } },
    }
    Accept(h, long, "Eleanor Shackleton")
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local book, screen = overlay.Book, h.env.UIParent:GetHeight()
    local function Fits(what)
        truthy(overlay.Panel:GetHeight() <= screen - 40, ("%s: the panel (%d) fits the screen (%d)"):format(what,
            overlay.Panel:GetHeight(), screen))
    end
    Fits("the riddle")
    falsy(book:IsShown(), "the book waits to be opened")
    local hadStory = overlay.Story:IsShown()
    h:Key("H", true)
    truthy(ns.ScholarView.BookOpen())
    truthy(book:IsShown() and not overlay.Story:IsShown(), "the book scrolls in the story's place")
    Fits("the open book")
    local text = Reveal(Harness.State(overlay.BookText).text)
    truthy(text:find("Eleanor Shackleton", 1, true) and text:find("get comfortable.", 1, true), "the whole quest, scrolled")
    truthy(Reveal(Harness.State(overlay.Hint.Label).text):find("Close book", 1, true), "the button closes it")
    local range = book:GetVerticalScrollRange()
    truthy(range > 0, "more text than room")
    eq(book:GetVerticalScroll(), 0, "it opens at the top")
    local function Offset() return book:GetVerticalScroll() end
    truthy(h:MouseWheel(book, -1), "the book takes the wheel")
    local step = Offset()
    truthy(step > 0, "the wheel scrolls down")
    h:MouseWheel(book, 1)
    eq(Offset(), 0, "and back up")
    h:MouseWheel(book, 1)
    eq(Offset(), 0, "never above the top")
    h:Key("DOWN", true)
    eq(Offset(), step, "the Down arrow scrolls like a notch")
    h:Key("UP", true)
    eq(Offset(), 0)
    h:Gamepad("PADDDOWN", true)
    h:Gamepad("PADDDOWN", false)
    eq(Offset(), step, "a D-pad press scrolls a notch")
    h:Gamepad("PADDDOWN", true)
    h:Advance(1)
    truthy(Offset() > 2 * step, "held, it keeps scrolling")
    h:Gamepad("PADDDOWN", false)
    local held = Offset()
    h:Advance(1)
    eq(Offset(), held, "let go, it stops")
    for _ = 1, 100 do h:MouseWheel(book, -1) end
    eq(Offset(), range, "never below the end")
    h:Key("H", true)
    falsy(ns.ScholarView.BookOpen())
    falsy(book:IsShown(), "closed")
    eq(overlay.Story:IsShown(), hadStory, "the riddle is as it was")
    Fits("the riddle again")
    h:Key("H", true)
    eq(Offset(), 0, "opened again, it starts at the top")
end)

test("with only quest riddles on, a riddle that comes due waits for a quest", function()
    local h = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })
    h:Advance(31 * 60)
    falsy(Showing(h), "nothing to ask yet")
    Accept(h, Wolves)
    truthy(Showing(h), "the quest gives it one")
end)

test("a riddle waiting for a quest is dropped when quest riddles are switched off too", function()
    local h, addon = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })
    h:Advance(31 * 60)
    eq(addon.State:Get("Scholar.pending"), true, "it waits")
    addon.State:Set("Scholar.quests", false)
    eq(addon.State:Get("Scholar.pending"), false, "with no subject on, nothing is due")
    addon.State:Set("Scholar.math", true)
    falsy(Showing(h), "so a subject switched back on asks nothing yet")
    h:Advance(31 * 60)
    truthy(Showing(h), "only after an interval of play")
end)

test("quest riddles are behind the parent's PIN like every Scholar setting", function()
    local h, addon = LoadKid()
    h:Slash("/tlk lock 2468")
    h:Slash("/tlk set Scholar.quests off")
    eq(addon.State:Get("Scholar.quests"), true)
    truthy(addon.State:IsLocked("Scholar.quests"))
    for _, name in ipairs(addon.State.Order) do
        if name:find("^Scholar%.") and addon.State.Specs[addon.State.Ids[name]].label then
            truthy(addon.State:IsLocked(name), name .. " is locked")
        end
    end
end)

test("quests aren't recorded while the challenge is off", function()
    local h, addon = LoadKid({ ["Scholar.enabled"] = false })
    Accept(h, Wolves)
    falsy(Quests(addon):Has("33"))
    falsy(addon.Events.Frame:IsEventRegistered("QUEST_ACCEPTED"), "no quest events")
end)

-- The choices of puzzles of kind over many seeds, all wrong ones, as a set.
local function WrongChoices(h, ns, kind, quest, known)
    local wrongs, asked = {}, 0
    for seed = 1, 300 do
        h:SeedRandom(seed)
        local puzzle = ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = quest, known = known })
        if puzzle.kind == kind then
            asked = asked + 1
            for i, choice in ipairs(puzzle.choices) do
                if i ~= puzzle.answer then wrongs[choice] = true end
            end
        end
    end
    truthy(asked > 0, kind .. " was asked")
    return wrongs
end

test("a quest riddle is headed QUEST, and a wrong answer leaves the quest book's button", function()
    local h, _, ns = LoadKid()
    local shown = Watch(ns)
    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    truthy(Reveal(Harness.State(overlay.Tag).text):find("QUEST", 1, true), Reveal(Harness.State(overlay.Tag).text))
    h:Key(tostring(shown[1].answer == 1 and 2 or 1), true)
    truthy(overlay.Hint:IsShown(), "the book is still a click away")
    truthy(overlay.Feedback:IsShown(), "beside the hint")
end)

test("a giver's other quests are never wrong answers to which quest they gave", function()
    local h, _, ns = LoadKid()
    local mine = { key = "1", title = "Wolves Across the Border", giver = "Marshal McBride", place = "Northshire", seen = 3 }
    local known = { mine,
        { key = "2", title = "Kobold Camp Cleanup", giver = "Marshal McBride", place = "Northshire", seen = 2 },
        { key = "3", title = "Lost Necklace", giver = "Billy Maclure", place = "Maclure Vineyards", seen = 1 },
    }
    falsy(WrongChoices(h, ns, "quest.title", mine, known)["Kobold Camp Cleanup"], "McBride gave that one too")
end)

test("the zone a quest began in is never a wrong answer to where it began", function()
    local h, _, ns = LoadKid()
    local mine = { key = "1", title = "Wolves", giver = "Eagan", place = "Northshire Abbey", zone = "Elwynn Forest", seen = 3 }
    local known = { mine, { key = "2", title = "Other", giver = "Marshal", place = "Elwynn Forest", zone = "Elwynn Forest", seen = 2 } }
    falsy(WrongChoices(h, ns, "quest.place", mine, known)["Elwynn Forest"], "that's true too")
end)

test("wrong answers come from the player's own quests before the bank", function()
    local h, _, ns = LoadKid()
    local mine = { key = "1", title = "Sting of the Scorpid", giver = "Gornek", place = "Valley of Trials", seen = 9 }
    local known = { mine }
    for i, giver in ipairs({ "Foreman Thazz'ril", "Zureetha Fargaze", "Hana'zua", "Galgar" }) do
        known[#known + 1] = { key = tostring(i + 1), title = "Quest " .. i, giver = giver, place = "Durotar", seen = i }
    end
    local wrongs = WrongChoices(h, ns, "quest.giver", mine, known)
    for name in pairs(wrongs) do
        truthy(({ ["Foreman Thazz'ril"] = 1, ["Zureetha Fargaze"] = 1, ["Hana'zua"] = 1, Galgar = 1 })[name], name .. " came from the bank")
    end
end)

test("a fill-in-the-blank never leaves the missing word elsewhere in the sentence", function()
    local h, _, ns = LoadKid()
    local mine = { key = "1", title = "Boars", seen = 1,
        text = "The wolves raided the farm, and the wolves fled north. Hunters, traders, farmers and miners watched closely." }
    local asked = 0
    for seed = 1, 200 do
        h:SeedRandom(seed)
        local puzzle = ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = mine, known = { mine } })
        if puzzle and puzzle.kind == "quest.blank" then
            asked = asked + 1
            local word = puzzle.choices[puzzle.answer]
            falsy(puzzle.prompt:find("%f[%a]" .. word .. "%f[%A]"), word .. " shows in: " .. puzzle.prompt)
        end
    end
    truthy(asked > 0, "a blank was asked")
end)

test("a /reload during a quest riddle's celebration doesn't ask that quest again", function()
    local h, addon, ns = LoadKid()
    local shown = Watch(ns)
    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    h:Key(tostring(shown[1].answer), true)
    h:Reload()
    falsy(Quests(h.ns.Addon):Field("33", "fresh"), "answered is asked")
end)

test("the two-to-one mix keeps its place across a /reload", function()
    local h, _, ns = LoadKid()
    local shown = Watch(ns)
    Accept(h, Wolves)
    Solve(h, shown)
    Solve(h, shown)
    h:Reload()
    shown = Watch(h.ns)
    local third = Solve(h, shown).subject
    truthy(third == "math" or third == "reading", "math or reading's turn, reload or not: " .. third)
end)

test("quest text keeps its words and line breaks, and loses the client's links and textures", function()
    local h, addon = LoadKid()
    h:OfferQuest({ id = 50, title = "Boar Hunt",
        text = "|TInterface\Icons\INV_Misc_Food_14:0|t Kill |cffff0000ten|r boars.|nThen see |Hitem:123|h[Boar Ribs]|h." },
        "Eagan Peltskinner")
    h:AcceptQuest()
    eq(Quests(addon):Field("50", "text"), "Kill ten boars.\nThen see [Boar Ribs].")
end)

-- Every quest.objective puzzle about quest across seeds: { [prompt] = true }, and every choice.
local function ObjectivePuzzles(h, ns, quest, known)
    local prompts, choices, answers = {}, {}, {}
    for seed = 1, 300 do
        h:SeedRandom(seed)
        local puzzle = ns.Puzzles.Generate({ subject = "quest", random = h.env.math.random, quest = quest, known = known })
        if puzzle and (puzzle.kind == "quest.objective" or puzzle.kind == "quest.count") then
            prompts[puzzle.prompt] = true
            answers[puzzle.choices[puzzle.answer]] = true
            for _, choice in ipairs(puzzle.choices) do choices[choice] = true end
        end
    end
    return prompts, choices, answers
end

test("objectives the client hasn't named yet wait in the book until it names them", function()
    local h, addon = LoadKid()
    Accept(h, {
        id = 70, title = "The Chill of Death", header = "Tirisfal Glades",
        objectives = {
            { text = "Duskbat Pelt", required = 5, uncached = true },
            { text = "Coarse Thread", required = 1 },
            { text = "Scarlet Warrior slain", required = 10, type = "monster", uncached = true },
        },
    }, "Gretchen Dedmar")
    local quests = Quests(addon)
    eq(quests:Field("70", "objective1"), "Coarse Thread", "a nameless \"0/5\" isn't an objective")
    eq(quests:Field("70", "objective2"), "", "nor is a nameless \"slain\"")
    h:LoadQuestNames()
    eq(quests:Field("70", "objective1") .. "|" .. quests:Field("70", "type1"), "Duskbat Pelt|item")
    eq(quests:Field("70", "objective2") .. "|" .. quests:Field("70", "type2"), "Coarse Thread|item")
    eq(quests:Field("70", "objective3") .. "|" .. quests:Field("70", "type3"), "Scarlet Warrior slain|monster")
    h:Reload()
    local calls = h:CountApiCalls("C_QuestLog.GetQuestObjectives")
    h:Fire("QUEST_LOG_UPDATE")
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), calls, "a named book reads nothing on log updates")
end)

test("an objective riddle asks about one kind of objective, with wrong answers of that kind", function()
    local h, _, ns = LoadKid()
    local function Quest(key, title, objectives)
        local record = { key = key, title = title, giver = "Gretchen Dedmar", seen = tonumber(key) }
        for i, objective in ipairs(objectives) do
            record["objective" .. i], record["required" .. i], record["type" .. i] = objective[1], objective[2], objective[3]
        end
        return record
    end
    local pelts = Quest("1", "The Chill of Death", { { "Duskbat Pelt", 5, "item" }, { "Coarse Thread", 1, "item" } })
    local warriors = Quest("2", "At War With The Scarlet Crusade", { { "Scarlet Warrior slain", 10, "monster" } })
    local campfire = Quest("3", "The Great Outdoors", { { "Sit near the campfire", 1, "log" } })
    local known = { pelts, warriors, campfire }
    local prompts, choices, answers = ObjectivePuzzles(h, ns, pelts, known)
    truthy(prompts['What did the quest "The Chill of Death" ask you to bring?'], "items are brought")
    falsy(choices["Scarlet Warrior"] or choices["Sit near the campfire"], "no foes or tasks among items")
    truthy(answers["Duskbat Pelt"] or answers["Coarse Thread"])
    prompts, choices, answers = ObjectivePuzzles(h, ns, warriors, known)
    truthy(prompts['Which enemy did the quest "At War With The Scarlet Crusade" ask you to defeat?'], "foes are defeated")
    truthy(answers["Scarlet Warrior"], "the foe by name, without \"slain\"")
    for choice in pairs(choices) do
        falsy(choice:find("slain", 1, true) or choice == "Duskbat Pelt", "only foes: " .. choice)
    end
    prompts = ObjectivePuzzles(h, ns, campfire, known)
    truthy(prompts['What did the quest "The Great Outdoors" ask you to do?'], "the rest are things to do")
end)

test("objectives saved without a name or a kind are never asked about or offered", function()
    local h, _, ns = LoadKid()
    local junk = { key = "1", title = "At War With The Scarlet Crusade", giver = "Executor Zygand", seen = 1,
        objective1 = "slain", required1 = 10, objective2 = "0/5", required2 = 5 }
    local untyped = { key = "2", title = "The Chill of Death", giver = "Gretchen Dedmar", seen = 2,
        objective1 = "Coarse Thread", required1 = 1 }
    local good = { key = "3", title = "Doom Weed", giver = "Junior Apothecary Holland", seen = 3,
        objective1 = "Doom Weed", required1 = 10, type1 = "item" }
    local known = { junk, untyped, good }
    for _, quest in ipairs(known) do
        local _, choices = ObjectivePuzzles(h, ns, quest, known)
        for choice in pairs(choices) do
            falsy(choice == "slain" or choice:find("^%d+/%d+$") or choice == "Coarse Thread",
                ("%s offers %q"):format(quest.title, choice))
        end
    end
end)

test("a flight, a quest turned in or a death brings the next riddle once it's half due", function()
    -- Under half the interval (30 minutes), the moment passes; over it, a riddle comes.
    local h = LoadKid()
    Accept(h, Wolves)
    h:Advance(10 * 60)
    h:TakeFlight()
    h:Advance(2)
    falsy(Showing(h), "a third of the way: the flight is just a flight")
    h:Land()
    h:Advance(6 * 60)
    h:TakeFlight()
    h:Advance(2)
    truthy(Showing(h), "over half due: a riddle for the flight")

    local turnIn, _, ns = LoadKid()
    local shown = Watch(ns)
    Accept(turnIn, Wolves)
    turnIn:Advance(16 * 60)
    turnIn:OpenTurnIn(Wolves.id, "Marshal McBride", "Well done.")
    turnIn:CompleteQuest()
    turnIn:Advance(2)
    truthy(Showing(turnIn), "a riddle for the quest just turned in")
    eq(shown[#shown].book:match('^"([^"]+)"'), Wolves.title, "about that quest")

    local death = LoadKid()
    Accept(death, Wolves)
    death:Advance(16 * 60)
    death:Die()
    death:Advance(1)
    truthy(Showing(death), "a riddle while you're dead")

    local off = LoadKid({ ["Scholar.onFlight"] = false, ["Scholar.onTurnIn"] = false, ["Scholar.onDeath"] = false })
    Accept(off, Wolves)
    off:Advance(16 * 60)
    off:TakeFlight()
    off:Advance(2)
    off:Land()
    off:OpenTurnIn(Wolves.id, "Marshal McBride", "Well done.")
    off:CompleteQuest()
    off:Die()
    off:Advance(2)
    falsy(Showing(off), "each moment can be switched off")
end)
