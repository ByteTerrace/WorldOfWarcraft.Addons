-- Scholar's quest riddles: what the quest book records, what it asks, and the open book.

local Kit = use("scholar")

local Accept = Kit.Accept
local LoadKid = Kit.LoadKid
local Showing = Kit.Showing
local Solve = Kit.Solve
local Watch = Kit.Watch

local Wolves = {
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", header = "Elwynn Forest", id = 33,
    objectives = { { required = 8, text = "Tough Wolf Meat" } },
    text = ("The wolves of Elwynn grow bolder every night. Yesterday they carried off a sheep from the Stonefield farm. "
        .. "Bring me their meat, and the farmers will sleep easier."),
    title = "Wolves Across the Border",
}

-- A quest puzzle about quest, as Scholar asks it: an enUS Alliance player's unless context says.
local function Ask(h, ns, quest, known, context)
    return ns.Puzzles.Generate({ context = (context or { faction = "Alliance", locale = "enUS" }), known = known,
        quest = quest, random = h.env.math.random, subject = "quest" })
end

local function Quests(addon)
    return addon.Modules.QuestBook.Records.quests
end

test("an accepted quest is recorded as its offer showed it, objectives from the log", function()
    local h, addon = LoadKid()

    h:SetLocation({ subZone = "Goldshire", zone = "Elwynn Forest" })
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

    h:SetLocation({ subZone = "Goldshire", zone = "Elwynn Forest" })
    Accept(h, Wolves)
    Quests(addon):Set("33", { fresh = false })
    h:SetLocation({ subZone = "Eastvale Logging Camp", zone = "Elwynn Forest" })
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

    h:SetLocation({ subZone = "Goldshire", zone = "Elwynn Forest" })

    local id = h:AutoAcceptQuest({ goal = "Speak with Marshal McBride.",
        objectives = { { text = "Report to Marshal McBride", type = "log" } },
        text = "Report to Marshal McBride in Northshire Abbey.", title = "A Threat Within" })

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

    -- an escort that starts inside a boss encounter
    h:SetRestriction("Encounter", true)
    Accept(h, Wolves)
    eq(Quests(addon):Field("33", "title"), "Wolves Across the Border")
    eq(Quests(addon):Field("33", "giver"), "", "the giver's name was secret")
end)

test("a quest the client can't name isn't recorded", function()
    local h, addon = LoadKid()

    -- not in the log, so GetTitleForQuestID has no title for it
    h:Fire("QUEST_ACCEPTED", 4242)
    falsy(Quests(addon):Has("4242"))
end)

test("a quest the book never saw is recorded when turned in, from its reward panel", function()
    local h, addon = LoadKid({ ["Scholar.enabled"] = false })

    Accept(h, Wolves)
    addon.State:Set("Scholar.enabled", true)
    h:SetLocation({ subZone = "Eastvale Logging Camp", zone = "Elwynn Forest" })
    h:OpenTurnIn(33, "Marshal McBride", "The farmers thank you.")
    h:CompleteQuest()
    local record = Quests(addon):Get("33")

    eq(record.title, "Wolves Across the Border", "the reward panel named it")
    eq(record.ender, "Marshal McBride")
    eq(record.endPlace, "Eastvale Logging Camp")
    truthy(record.turnedIn)
    eq(record.giver, "", "nobody saw who gave it")
    -- a hidden tracking quest: no panel named it
    h:Fire("QUEST_TURNED_IN", 9001, 0, 0)
    falsy(Quests(addon):Has("9001"))
end)

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

    truthy((third == "math") or (third == "reading"), "then math or reading takes a turn: " .. third)
    eq(Solve(h, shown).subject, "quest", "and quests again")
    eq(Solve(h, shown).subject, "quest")
    eq(Solve(h, shown).subject, ((third == "math") and "reading") or "math", "math and reading take turns")
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

    Accept(h, { id = 40, objectives = { { required = 10, text = "Kobold Vermin", type = "monster" } },
        text = "Kobolds have overrun the Fargodeep Mine.", title = "The Fargodeep Mine" }, "Marshal Dughan")

    h:Slash("/tlk puzzle")
    eq(shown[1].questKey, "40", "the newest")
end)

test("every kind asks what the quest holds, with the right answer among four", function()
    local h, _, ns = LoadKid()

    local quest = {
        ender = "Marshal McBride", endPlace = "Eastvale Logging Camp", giver = "Eagan Peltskinner", goal = Wolves.goal,
        key = "33", objective1 = "Tough Wolf Meat", place = "Goldshire", required1 = 8, seen = 10, text = Wolves.text,
        title = "Wolves Across the Border", turnedIn = true, type1 = "item",
    }

    local known = { quest,
        { giver = "Marshal Dughan", key = "40", objective1 = "Kobold Candle", place = "Fargodeep Mine", required1 = 8, seen = 9, title = "The Fargodeep Mine", type1 = "item" },
        { giver = "Billy Maclure", key = "41", objective1 = "Billy's Pie", place = "Maclure Vineyards", required1 = 1, seen = 8, title = "Lost Necklace", type1 = "item" },
    }

    local expected = {
        ["quest.giver"] = "Eagan Peltskinner", ["quest.ender"] = "Marshal McBride", ["quest.place"] = "Goldshire",
        ["quest.endPlace"] = "Eastvale Logging Camp", ["quest.count"] = "8", ["quest.objective"] = "Tough Wolf Meat",
        ["quest.title"] = "Wolves Across the Border",
    }

    -- What it asked for comes first; without objectives or text, who and where.
    local plain = {}

    for key, value in pairs(quest) do plain[key] = value end

    plain.text, plain.objective1, plain.required1, plain.type1 = nil, nil, nil, nil
    local seen = {}

    for seed = 1, 120 do
        h:SeedRandom(seed)
        local puzzle = Ask(h, ns, (((seed % 2) == 0) and quest) or plain, known)

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

        for _ in pairs(distinct) do count = (count + 1) end

        eq(count, 4, "four different choices")
        truthy(((seed % 2) == 1) or puzzle.book:find(Wolves.text, 1, true), "the book holds the text")
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

    -- a title and nothing else
    Quests(addon):Set("99", { fresh = true, seen = 1, title = "Hmm" })

    -- Everything to ask about, but a title too long to show in a riddle.
    Quests(addon):Set("98", { fresh = true, giver = "Eagan Peltskinner", place = "Goldshire", seen = 2,
        title = "The Long and Winding Road to the Edge of the Known World Today" })

    eq(ns.Puzzles.Generate({ quest = Quests(addon):Get("99"), random = h.env.math.random, subject = "quest" }), nil)
    eq(ns.Puzzles.Generate({ quest = Quests(addon):Get("98"), random = h.env.math.random, subject = "quest" }), nil)
    h:Slash("/tlk puzzle")
    truthy(shown[1].subject ~= "quest", shown[1].subject)
    falsy(Quests(addon):Field("99", "fresh"))
    falsy(Quests(addon):Field("98", "fresh"))
end)

test("the quest book names who gave a quest and where, whichever the record holds", function()
    local h, _, ns = LoadKid()

    local function Book(quest)
        h:SeedRandom(1)

        return Ask(h, ns, quest, { quest }).book
    end

    local both = Book({ giver = "Eagan Peltskinner", key = "1", place = "Goldshire", seen = 1, title = "Wolves" })

    truthy(both:find("From Eagan Peltskinner, in Goldshire.", 1, true), both)
    local giver = Book({ giver = "Eagan Peltskinner", key = "1", seen = 1, title = "Wolves" })

    truthy(giver:find("From Eagan Peltskinner.", 1, true), giver)
    local place = Book({ key = "1", place = "Goldshire", seen = 1, title = "Wolves" })

    truthy(place:find("Taken in Goldshire.", 1, true), place)
end)

test("the quest book asks fresh quests newest first, then the rest, the one asked longest ago first", function()
    local h, addon, ns = LoadKid()
    local quests = Quests(addon)

    quests:Set("1", { fresh = true, seen = 5, title = "Old Fresh" })
    quests:Set("2", { fresh = true, seen = 10, title = "New Fresh" })
    quests:Set("3", { askedAt = 30, seen = 7, title = "Asked Lately" })
    quests:Set("5", { askedAt = 20, seen = 7, title = "Asked Long Ago B" })
    quests:Set("4", { askedAt = 20, seen = 8, title = "Asked Long Ago A" })
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

    local long = { goal = "Bring wolf meat.", header = "Elwynn Forest", id = 35, objectives = {},
        text = (sentence:rep(30) .. "Help us."), title = "Long Nights" }

    Accept(h, long)
    eq(Quests(addon):Field("35", "text"), long.text, "every word of it")
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")
    truthy(shown[1].book:find("Help us.", 1, true), "the book ends as the quest does")
end)

test("a quest book too long for the screen scrolls, by wheel, arrow keys and D-pad, and the riddle fits", function()
    local h, _, ns = LoadKid()

    -- a controller is connected
    h.labelStyle = "Letters"
    -- a short screen: the harness's 14 px lines are shorter than the real font's
    h.env.UIParent:SetSize(1366, 600)

    local paragraph = ("Greetings, rogue. I can see you've got the look of an adventurer about you. This is good. "
        .. "The world needs more of us restless souls, seeking fortune and glory. ")

    local long = {
        goal = "Sit near Eleanor's Basic Campfire and wait until you receive the Boosted Rest buff.",
        header = "Tirisfal Glades", id = 34,
        objectives = { { required = 1, text = "Sit near the campfire", type = "log" }, { required = 1, text = "Gain the Boosted Rest buff", type = "log" } },
        text = (paragraph:rep(20) .. "Have a seat near the fire and get comfortable."), title = "The Great Outdoors",
    }

    Accept(h, long, "Eleanor Shackleton")
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local book = overlay.Book
    local screen = h.env.UIParent:GetHeight()

    local function Fits(what)
        truthy(overlay.Panel:GetHeight() <= (screen - 40), ("%s: the panel (%d) fits the screen (%d)"):format(what,
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
    truthy(Offset() > (2 * step), "held, it keeps scrolling")
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

test("on a tall screen the quest book is a page of at most BookHeight, scrolling the rest, not the screen's height", function()
    local h, _, ns = LoadKid()

    -- a small UI scale: far more room than the book needs
    h.env.UIParent:SetSize(2560, 1440)

    Accept(h, { goal = "Read it all.", header = "Tirisfal Glades", id = 36, objectives = {},
        text = ("The Scourge gathers in the north, and the Magistrate needs every agent he can find. "):rep(30), title = "Every Word" })

    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local closed = overlay.Panel:GetHeight()

    h:Key("H", true)
    eq(overlay.Book:GetHeight(), 240, "a page's worth in view")
    truthy(overlay.BookCase:IsShown() and overlay.Book:IsShown(), "the book opens on its page")
    truthy(overlay.Book:GetVerticalScrollRange() > 0, "and the rest scrolls")

    truthy(overlay.Panel:GetHeight() < (closed + 300), ("the panel grows by about a page, not the screen: %d, then %d")
        :format(closed, overlay.Panel:GetHeight()))
end)

test("feedback too long for its row grows the footer down to fit, and the panel with it", function()
    local h, _, ns = LoadKid()
    local shown = Watch(ns)

    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local before = overlay.Panel:GetHeight()

    ns.ScholarView.Wrong(Kit.WrongAnswer(shown[1]), ('"details" is in the quest, but in another sentence. '):rep(3),
        "Hint", "Open the quest book and find that sentence.", false)

    local banner = overlay.Feedback
    local text = banner.Text:GetStringHeight()

    truthy(text > 44, "the message takes more than one row: " .. text)
    eq(banner:GetHeight(), text + 20, "the banner fits it")
    eq(overlay.Panel:GetHeight(), (before + (text + 20)) - 44, "and the panel grows by what the footer did")
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
local function WrongChoices(h, ns, kind, quest, known, context)
    local wrongs = {}
    local asked = 0

    for seed = 1, 300 do
        h:SeedRandom(seed)
        local puzzle = Ask(h, ns, quest, known, context)

        if puzzle.kind == kind then
            asked = (asked + 1)

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
    h:Key(tostring(((shown[1].answer == 1) and 2) or 1), true)
    truthy(overlay.Hint:IsShown(), "the book is still a click away")
    truthy(overlay.Feedback:IsShown(), "beside the hint")
end)

test("a giver's other quests are never wrong answers to which quest they gave", function()
    local h, _, ns = LoadKid()
    local mine = { giver = "Marshal McBride", key = "1", place = "Northshire", seen = 3, title = "Wolves Across the Border" }

    local known = { mine,
        { giver = "Marshal McBride", key = "2", place = "Northshire", seen = 2, title = "Kobold Camp Cleanup" },
        { giver = "Billy Maclure", key = "3", place = "Maclure Vineyards", seen = 1, title = "Lost Necklace" },
    }

    falsy(WrongChoices(h, ns, "quest.title", mine, known)["Kobold Camp Cleanup"], "McBride gave that one too")
end)

test("the zone a quest began in is never a wrong answer to where it began", function()
    local h, _, ns = LoadKid()
    local mine = { giver = "Eagan", key = "1", place = "Northshire Abbey", seen = 3, title = "Wolves", zone = "Elwynn Forest" }
    local known = { mine, { giver = "Marshal", key = "2", place = "Elwynn Forest", seen = 2, title = "Other", zone = "Elwynn Forest" } }

    falsy(WrongChoices(h, ns, "quest.place", mine, known)["Elwynn Forest"], "that's true too")
end)

test("wrong answers come from the player's own quests before the bank", function()
    local h, _, ns = LoadKid()
    local mine = { giver = "Gornek", key = "1", place = "Valley of Trials", seen = 9, title = "Sting of the Scorpid" }
    local known = { mine }

    for i, giver in ipairs({ "Foreman Thazz'ril", "Zureetha Fargaze", "Hana'zua", "Galgar" }) do
        known[#known + 1] = { giver = giver, key = tostring(i + 1), place = "Durotar", seen = i, title = ("Quest " .. i) }
    end

    local wrongs = WrongChoices(h, ns, "quest.giver", mine, known)

    for name in pairs(wrongs) do
        truthy(({ ["Foreman Thazz'ril"] = 1, ["Zureetha Fargaze"] = 1, ["Hana'zua"] = 1, Galgar = 1 })[name], name .. " came from the bank")
    end
end)

test("a fill-in-the-blank never leaves the missing word elsewhere in the sentence", function()
    local h, _, ns = LoadKid()

    local mine = { key = "1", seen = 1,
        text = "The wolves raided the farm, and the wolves fled north. Hunters, traders, farmers and miners watched closely.",
        title = "Boars" }

    local asked = 0

    for seed = 1, 200 do
        h:SeedRandom(seed)
        local puzzle = Ask(h, ns, mine, { mine })

        if puzzle and (puzzle.kind == "quest.blank") then
            asked = (asked + 1)
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

    truthy((third == "math") or (third == "reading"), "math or reading's turn, reload or not: " .. third)
end)

test("quest text keeps its words and line breaks, and loses the client's links and textures", function()
    local h, addon = LoadKid()

    h:OfferQuest({ id = 50,
        text = "|TInterface\Icons\INV_Misc_Food_14:0|t Kill |cffff0000ten|r boars.|nThen see |Hitem:123|h[Boar Ribs]|h.",
        title = "Boar Hunt" },
        "Eagan Peltskinner")

    h:AcceptQuest()
    eq(Quests(addon):Field("50", "text"), "Kill ten boars.\nThen see [Boar Ribs].")
end)

-- Every quest.objective puzzle about quest across seeds: { [prompt] = true }, and every choice.
local function ObjectivePuzzles(h, ns, quest, known)
    local prompts = {}
    local choices = {}
    local answers = {}

    for seed = 1, 300 do
        h:SeedRandom(seed)
        local puzzle = Ask(h, ns, quest, known)

        if puzzle and ((puzzle.kind == "quest.objective") or (puzzle.kind == "quest.count")) then
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
        header = "Tirisfal Glades", id = 70,
        objectives = {
            { required = 5, text = "Duskbat Pelt", uncached = true },
            { required = 1, text = "Coarse Thread" },
            { required = 10, text = "Scarlet Warrior", type = "monster", uncached = true },
        },
        title = "The Chill of Death",
    }, "Gretchen Dedmar")

    local quests = Quests(addon)

    eq(quests:Field("70", "objective1"), "Coarse Thread", "a nameless \"0/5\" isn't an objective")
    eq(quests:Field("70", "objective2"), "", "nor is a nameless \"slain\"")
    h:LoadQuestNames()
    eq(quests:Field("70", "objective1") .. "|" .. quests:Field("70", "type1"), "Duskbat Pelt|item")
    eq(quests:Field("70", "objective2") .. "|" .. quests:Field("70", "type2"), "Coarse Thread|item")
    eq(quests:Field("70", "objective3") .. "|" .. quests:Field("70", "type3"), "Scarlet Warrior|monster", "a foe is named without \"slain\"")
    h:Reload()
    local calls = h:CountApiCalls("C_QuestLog.GetQuestObjectives")

    h:Fire("QUEST_LOG_UPDATE")
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), calls, "a named book reads nothing on log updates")
end)

test("an objective riddle asks about one kind of objective, with wrong answers of that kind", function()
    local h, _, ns = LoadKid()

    local function Quest(key, title, objectives)
        local record = { giver = "Gretchen Dedmar", key = key, seen = tonumber(key), title = title }

        for i, objective in ipairs(objectives) do
            record["objective" .. i], record["required" .. i], record["type" .. i] = objective[1], objective[2], objective[3]
        end

        return record
    end

    local pelts = Quest("1", "The Chill of Death", { { "Duskbat Pelt", 5, "item" }, { "Coarse Thread", 1, "item" } })
    local warriors = Quest("2", "At War With The Scarlet Crusade", { { "Scarlet Warrior", 10, "monster" } })
    local campfire = Quest("3", "The Great Outdoors", { { "Sit near the campfire", 1, "log" } })
    local known = { pelts, warriors, campfire }
    local prompts, choices, answers = ObjectivePuzzles(h, ns, pelts, known)

    truthy(prompts['What did the quest "The Chill of Death" ask you to bring?'], "items are brought")
    falsy(choices["Scarlet Warrior"] or choices["Sit near the campfire"], "no foes or tasks among items")
    truthy(answers["Duskbat Pelt"] or answers["Coarse Thread"])
    prompts, choices, answers = ObjectivePuzzles(h, ns, warriors, known)
    -- "Scarlet" in the title would give Scarlet Warrior away, so the riddle names the quest as the book's.
    truthy(prompts["Which enemy did the quest in your quest book ask you to defeat?"], "foes are defeated")
    truthy(answers["Scarlet Warrior"], "the foe by name, without \"slain\"")

    for choice in pairs(choices) do
        falsy(choice:find("slain", 1, true) or (choice == "Duskbat Pelt"), "only foes: " .. choice)
    end

    prompts = ObjectivePuzzles(h, ns, campfire, known)
    truthy(prompts['What did the quest "The Great Outdoors" ask you to do?'], "the rest are things to do")
end)

test("objectives saved without a name or a kind are never asked about or offered", function()
    local h, _, ns = LoadKid()

    local junk = { giver = "Executor Zygand", key = "1", objective1 = "slain", objective2 = "0/5", required1 = 10,
        required2 = 5, seen = 1, title = "At War With The Scarlet Crusade" }

    local untyped = { giver = "Gretchen Dedmar", key = "2", objective1 = "Coarse Thread", required1 = 1, seen = 2,
        title = "The Chill of Death" }

    local good = { giver = "Junior Apothecary Holland", key = "3", objective1 = "Doom Weed", required1 = 10, seen = 3,
        title = "Doom Weed", type1 = "item" }

    local known = { junk, untyped, good }

    for _, quest in ipairs(known) do
        local _, choices = ObjectivePuzzles(h, ns, quest, known)

        for choice in pairs(choices) do
            falsy((choice == "slain") or choice:find("^%d+/%d+$") or (choice == "Coarse Thread"),
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

test("a giver's quests in the bank are never wrong answers to which quest they gave", function()
    local h, _, ns = LoadKid()
    local mine = { giver = "Marshal McBride", key = "1", seen = 1, title = "Wolves in the Abbey" }
    local wrongs = WrongChoices(h, ns, "quest.title", mine, { mine })

    falsy(wrongs["Kobold Camp Cleanup"] or wrongs["Report to Goldshire"], "McBride gave those")
    truthy(wrongs["The Fargodeep Mine"] or wrongs["Lost Necklace"], "others gave these")
end)

-- Names only Alliance players meet in their first quests.
local AllianceNames = {
    ["Marshal McBride"] = true, ["Marshal Dughan"] = true, ["Eagan Peltskinner"] = true, ["Deputy Willem"] = true,
    ["Northshire Abbey"] = true, ["Goldshire"] = true, ["Fargodeep Mine"] = true, ["Kobold Camp Cleanup"] = true,
    ["Report to Goldshire"] = true, ["Tough Wolf Meat"] = true, ["Kobold Vermin"] = true, ["Defias Thug"] = true,
}

test("a Horde player's wrong answers come from Horde lands", function()
    local h, _, ns = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })

    h.player.faction = "Horde"
    local shown = Watch(ns)

    h:SetLocation({ subZone = "Valley of Trials", zone = "Durotar" })

    Accept(h, { id = 788, objectives = { { required = 10, text = "Mottled Boar", type = "monster" } },
        text = "Prove your mettle. Thin the boars that roam the valley.", title = "Cutting Teeth" }, "Gornek")

    for _ = 1, 8 do
        local puzzle = Solve(h, shown)

        for _, choice in ipairs(puzzle.choices) do
            falsy(AllianceNames[choice], ("%s offered %q"):format(puzzle.kind, choice))
        end
    end

    local wrongs = WrongChoices(h, ns, "quest.giver", { giver = "Hana'zua", key = "1", seen = 1, title = "Sarkoth" }, nil,
        { faction = "Horde", locale = "enUS" })

    for name in pairs(wrongs) do
        falsy(AllianceNames[name], name)
    end
end)

-- The kinds asked about quest across seeds, as a set.
local function KindsAsked(h, ns, quest, context)
    local kinds = {}

    for seed = 1, 200 do
        h:SeedRandom(seed)
        local puzzle = Ask(h, ns, quest, { quest }, context)

        if puzzle then kinds[puzzle.kind] = true end
    end

    return kinds
end

local Full = {
    giver = "Eagan Peltskinner", key = "33", objective1 = "Tough Wolf Meat", place = "Goldshire", required1 = 8,
    seen = 1, text = Wolves.text, title = "Wolves Across the Border", type1 = "item",
}

test("what a quest asked for comes before who and where", function()
    local h, _, ns = LoadKid()
    local kinds = KindsAsked(h, ns, Full)

    for kind in pairs(kinds) do
        truthy((kind == "quest.count") or (kind == "quest.objective") or (kind == "quest.blank"), kind .. " was asked")
    end
end)

test("the kind last asked about a quest isn't asked about it next, and who gave it and which it was are one kind", function()
    local h, addon, ns = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })
    local count = {}

    for key, value in pairs(Full) do count[key] = value end

    count.askedKind = "quest.count"
    falsy(KindsAsked(h, ns, count)["quest.count"], "a count was asked last time")
    local who = { askedKind = "quest.giver", giver = "Eagan Peltskinner", key = "1", place = "Goldshire", seen = 1, title = "Wolves" }
    local kinds = KindsAsked(h, ns, who)

    falsy(kinds["quest.giver"] or kinds["quest.title"], "who gave it, either way round")
    truthy(kinds["quest.place"])
    local only = { askedKind = "quest.giver", giver = "Eagan Peltskinner", key = "1", seen = 1, title = "Wolves" }

    truthy(next(KindsAsked(h, ns, only)), "with nothing else to ask, the same kind again")
    local shown = Watch(ns)

    Accept(h, Wolves)
    local first = Solve(h, shown)

    truthy(Quests(addon):Field("33", "askedKind"):find("^quest%."), "the book remembers the kind")
    local second = Solve(h, shown)
    local Family = { ["quest.title"] = "quest.giver" }

    truthy((Family[first.kind] or first.kind) ~= (Family[second.kind] or second.kind), first.kind .. " then " .. second.kind)
end)

-- A harness client of another locale: GetLocale and the quest log's GlobalStrings, from
-- Ketho/BlizzardInterfaceResources (forever branch).
local Locales = {
    koKR = { QUEST_ITEMS_NEEDED = "%2$d/%3$d %1$s", QUEST_MONSTERS_KILLED = "%2$d/%3$d %1$s 처치",
        QUEST_OBJECTS_FOUND = "%2$d/%3$d %1$s" },
    ruRU = { QUEST_ITEMS_NEEDED = "%1$s: %2$d/%3$d", QUEST_MONSTERS_KILLED = "%1$s – убито: %2$d/%3$d",
        QUEST_OBJECTS_FOUND = "%1$s: %2$d/%3$d" },
}

local function LoadLocale(locale)
    local h = Harness.New({ saved = { TheLanKrewToolKitCharDB = { ["Scholar.enabled"] = true } } })

    h.locale = locale

    for name, value in pairs(Locales[locale]) do rawset(h.env, name, value) end

    h:SeedRandom(7)
    local ns = h:LoadAddon("TheLanKrewToolKit")

    return h, ns.Addon, ns
end

test("objectives are named in every locale, with the client's own formats", function()
    for locale, names in pairs({ koKR = { "박쥐 가죽", "해골 전사" }, ruRU = { "Шкура летучей мыши", "Скелет-воин" } }) do
        local h, addon = LoadLocale(locale)

        Accept(h, { id = 70,
            objectives = {
                { required = 5, text = names[1] }, { required = 10, text = names[2], type = "monster" },
                { required = 2, text = names[1], uncached = true } },
            title = ("Locale " .. locale) })

        local quests = Quests(addon)

        eq(quests:Field("70", "objective1"), names[1], locale .. " item")
        eq(quests:Field("70", "objective2") .. "|" .. quests:Field("70", "type2"), names[2] .. "|monster", locale .. " foe")
        eq(quests:Field("70", "objective3"), "", locale .. ": an unloaded name still waits")
        h:LoadQuestNames()
        eq(quests:Field("70", "objective3"), names[1], locale .. ": then it's named")
        local calls = h:CountApiCalls("C_QuestLog.GetQuestObjectives")

        h:Fire("QUEST_LOG_UPDATE")
        eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), calls, locale .. ": a named book reads nothing")
    end
end)

test("a quest whose names never load stops being read after a few log updates", function()
    local h, addon = LoadKid()

    Accept(h, { id = 71, objectives = { { required = 5, text = "Duskbat Pelt", uncached = true } }, title = "The Chill of Death" })
    local calls = h:CountApiCalls("C_QuestLog.GetQuestObjectives")

    for _ = 1, 100 do h:Fire("QUEST_LOG_UPDATE") end

    local tried = (h:CountApiCalls("C_QuestLog.GetQuestObjectives") - calls)

    truthy((tried > 0) and (tried <= 20), "tried " .. tried .. " times")
    calls = h:CountApiCalls("C_QuestLog.GetQuestObjectives")
    h:Fire("QUEST_LOG_UPDATE")
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), calls, "then it gives up")
    eq(Quests(addon):Field("71", "title"), "The Chill of Death", "and keeps the quest")
end)

test("a missing word is asked only on an English client", function()
    local h, _, ns = LoadKid()

    local text = { key = "1", seen = 1,
        text = "The wolves raided the farm at night. Hunters, traders, farmers and miners watched closely.",
        title = "Boars" }

    truthy(KindsAsked(h, ns, text)["quest.blank"], "enUS")
    eq(next(KindsAsked(h, ns, text, { faction = "Alliance", locale = "deDE" })), nil, "deDE: nothing else to ask")
    local ru, _, ruNs = LoadLocale("ruRU")
    local shown = Watch(ruNs)

    ru:SetLocation({ subZone = "", zone = "" })
    ru:AutoAcceptQuest({ text = text.text, title = "Boars" })
    ru:Slash("/tlk puzzle")
    truthy(shown[1].subject ~= "quest", "Scholar asks a ruRU client nothing about a text alone: " .. shown[1].subject)
end)

test("quests already in the log are recorded when the challenge starts, for review", function()
    local h, addon, ns = LoadKid({ ["Scholar.enabled"] = false, ["Scholar.math"] = false, ["Scholar.reading"] = false })

    h:SetLocation({ subZone = "Goldshire", zone = "Elwynn Forest" })
    Accept(h, Wolves)

    local id = h:AutoAcceptQuest({ goal = "Speak with Marshal Dughan.",
        objectives = { { required = 4, text = "Gold Dust" } }, text = "Marshal Dughan waits in Goldshire.",
        title = "Report to Goldshire" })

    addon.State:Set("Scholar.enabled", true)
    local record = Quests(addon):Get("33")

    eq(record.title, Wolves.title)
    eq(record.text, Wolves.text, "its text, as the log shows it")
    eq(record.goal, Wolves.goal)
    eq(record.objective1 .. "|" .. record.required1, "Tough Wolf Meat|8")
    eq(record.giver .. "|" .. record.place, "|", "nobody saw who gave it, or where")
    falsy(record.fresh, "not fresh: it's for review")
    eq(Quests(addon):Field(tostring(id), "objective1"), "Gold Dust")
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")
    eq(shown[1].subject, "quest", "something to ask about straight away")
end)
