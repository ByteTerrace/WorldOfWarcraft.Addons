-- Scholar's riddle screen in play: when a riddle waits for Blizzard's windows, what Read aloud
-- says, and the difficulty quest riddles leave alone.

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
    id = 33, title = "Wolves Across the Border",
    text = "The wolves of Elwynn grow bolder every night. Bring me their meat, and the farmers will sleep easier.",
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.",
    objectives = { { text = "Tough Wolf Meat", required = 8 } },
}

local function Accept(h, spec, giver)
    h:OfferQuest(spec, giver or "Eagan Peltskinner")
    h:AcceptQuest()
end

-- Asks a riddle now and answers it right.
local function Solve(h, shown)
    h:Slash("/tlk puzzle")
    h:Key(tostring(shown[#shown].answer), true)
    h:Advance(2)
    return shown[#shown]
end

-- An answer other than the right one.
local function WrongAnswer(puzzle)
    return puzzle.answer == 1 and 2 or 1
end

-- Answers the riddle on screen wrong, twice when it can.
local function MissTwice(h, puzzle)
    local missed = 0
    for i = 1, 4 do
        if i ~= puzzle.answer and missed < 2 then
            h:Key(tostring(i), true)
            missed = missed + 1
        end
    end
end

test("quest riddles never change the difficulty math and reading use", function()
    local h, addon, ns = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false, ["Scholar.level"] = 2 })
    local shown = Watch(ns)
    Accept(h, Wolves)
    for _ = 1, 3 do Solve(h, shown) end
    eq(addon.State:Get("Scholar.streak"), 3, "three right in a row")
    eq(addon.State:Get("Scholar.level"), 2, "and quest riddles are no harder")
    h:Slash("/tlk puzzle")
    MissTwice(h, shown[#shown])
    eq(addon.State:Get("Scholar.level"), 2, "nor two misses on one any easier")
end)

-- Opens and closes each window a riddle waits for, by its name in these tests.
local Windows = {
    quest = { function(h) h:OfferQuest({ id = 90, title = "Lost Necklace" }, "Billy Maclure") end,
        function(h) h:AcceptQuest() end },
    gossip = { function(h) h:OpenGossip("Innkeeper Farley") end, function(h) h:CloseGossip() end },
}
for _, name in ipairs({ "Merchant", "MailInfo", "Banker", "Auctioneer", "Trainer", "TaxiNode" }) do
    Windows[name] = { function(h) h:OpenInteraction(name) end, function(h) h:CloseInteraction(name) end }
end

test("a riddle that comes due over a quest dialog, gossip, vendor, mailbox, bank, auction house, trainer or flight map waits for it to close", function()
    for _, name in ipairs({ "quest", "gossip", "Merchant", "MailInfo", "Banker", "Auctioneer", "Trainer", "TaxiNode" }) do
        local h = LoadKid()
        Windows[name][1](h)
        h:Slash("/tlk puzzle")
        falsy(Showing(h), name .. ": held while the window is open")
        Windows[name][2](h)
        truthy(Showing(h), name .. ": shown once it closes")
    end
end)

test("a riddle a turn-in brings waits while the next quest of the chain is offered", function()
    local h, _, ns = LoadKid()
    local shown = Watch(ns)
    Accept(h, Wolves)
    h:Advance(16 * 60)
    h:OpenTurnIn(Wolves.id, "Eagan Peltskinner", "Well done.")
    h:CompleteQuest()
    h:Advance(0.5)
    h:OfferQuest({ id = 34, title = "Wolves in the Fields", text = "The pack is regrouping." }, "Eagan Peltskinner")
    h:Advance(2)
    falsy(Showing(h), "the next quest's offer is open")
    h:AcceptQuest()
    truthy(Showing(h), "it comes once the dialog closes")
    eq(#shown, 1)
end)

test("a riddle on screen stays when a window opens, and a fight still sends it away", function()
    local h = LoadKid()
    h:Slash("/tlk puzzle")
    truthy(Showing(h))
    h:OpenInteraction("Merchant")
    truthy(Showing(h), "it stays over the vendor")
    h:EnterCombat()
    falsy(Showing(h), "a fight sends it away")
    h:LeaveCombat()
    falsy(Showing(h), "and with the vendor open, it waits")
    h:CloseInteraction("Merchant")
    truthy(Showing(h), "then comes back")
end)

test("Blizzard's windows cost nothing while the challenge is off, and a loading screen forgets them", function()
    local h, addon = LoadKid({ ["Scholar.enabled"] = false })
    local frame = addon.Events.Frame
    for _, event in ipairs({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "GOSSIP_SHOW", "QUEST_FINISHED", "TAXIMAP_CLOSED" }) do
        falsy(frame:IsEventRegistered(event), event)
    end
    addon.State:Set("Scholar.enabled", true)
    truthy(frame:IsEventRegistered("PLAYER_INTERACTION_MANAGER_FRAME_SHOW"), "registered while it runs")
    h:OpenInteraction("Merchant")
    h:Fire("PLAYER_ENTERING_WORLD", false, false) -- zoning closes every window without a word
    h:Slash("/tlk puzzle")
    truthy(Showing(h), "nothing holds the riddle after a loading screen")
end)

-- The text Read aloud speaks for puzzle, from the screen's own reading of it.
local function Says(puzzle)
    local _, _, ns = LoadKid()
    return ns.ScholarView.Spoken(puzzle)
end

test("Read aloud says a blank as \"blank\", in reading and math riddles alike", function()
    local sight = Says({ kind = "reading.sight", prompt = "Which word fits?\n\"Look at ___ big dragon!\"",
        choices = { "the", "teh", "hte", "tha" } })
    truthy(sight:find("Look at blank big dragon", 1, true), sight)
    local missing = Says({ kind = "math.missing", prompt = "What number goes in the blank?\n3 + __ = 7",
        choices = { "4", "5", "3", "10" } })
    truthy(missing:find("3 + blank = 7", 1, true), missing)
    falsy((sight .. missing):find("_", 1, true), "no underscores are read out")
end)

test("Read aloud spells a spelling riddle's choices letter by letter", function()
    for _, kind in ipairs({ "reading.spelling", "reading.sight" }) do
        local said = Says({ kind = kind, prompt = "Only one word is spelled right. Which one fits?\n\"I ___ in you!\"",
            choices = { "believe", "beleive", "belive", "beleve" } })
        truthy(said:find("B, E, L, E, I, V, E", 1, true), kind .. ": " .. said)
        truthy(said:find("B, E, L, I, V, E", 1, true), kind .. ": " .. said)
        falsy(said:find("beleive", 1, true), kind .. ": a misspelling is never said as a word")
    end
    local rhyme = Says({ kind = "reading.rhyme", prompt = "Which word rhymes with \"cat\"?", choices = { "hat", "dog", "sun", "pig" } })
    truthy(rhyme:find("hat, dog, sun, or pig", 1, true), "other riddles say their choices as words: " .. rhyme)
end)

test("Read aloud reads the open quest book, and after an answer the feedback shown", function()
    local h, _, ns = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })
    local shown = Watch(ns)
    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local puzzle = shown[#shown]
    h:Key("H", true)
    h:Key("R", true)
    eq(h.spoken[#h.spoken].text, puzzle.book, "the book, while it's open")
    h:Key("H", true)
    h:Key("R", true)
    truthy(h.spoken[#h.spoken].text:find(" Is it ", 1, true), "the riddle, once it's closed")
    h:Key(tostring(WrongAnswer(puzzle)), true)
    h:Key("R", true)
    local said = h.spoken[#h.spoken].text
    truthy(said:find(puzzle.hint, 1, true) and said:find("Not quite", 1, true), "the hint shown: " .. said)
    h:Key(tostring(puzzle.answer), true)
    h:Key("R", true)
    said = h.spoken[#h.spoken].text
    truthy(said:find(puzzle.explanation, 1, true) and said:find("Correct", 1, true), "the working shown: " .. said)
    local other = LoadKid({ ["Scholar.pending"] = true })
    other:Key("H", true)
    other:Key("R", true)
    truthy(other.spoken[#other.spoken].text:find("Hint:", 1, true), "a hint asked for is read too")
end)
