-- The Owl reads the quest aloud (QuestReader.lua): when a young scholar opens a quest dialog, its giver's words are
-- read aloud, and closing the dialog stops them.

local Kit = use("scholar")
local Accept = Kit.Accept
local LoadKid = Kit.LoadKid

local Wolves = {
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", header = "Elwynn Forest", id = 33,
    objectives = { { required = 8, text = "Tough Wolf Meat" } },
    text = "The wolves of Elwynn grow bolder every night.", title = "Wolves Across the Border",
}

local function Last(h)
    return (h.spoken[#h.spoken] and h.spoken[#h.spoken].text)
end

test("the Owl reads a quest offer aloud: who's speaking, the quest's name, its story, and what to do", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    h:OfferQuest(Wolves, "Eagan Peltskinner")

    eq(Last(h), "Eagan Peltskinner says: Wolves Across the Border. The wolves of Elwynn grow bolder every night. "
        .. "Bring 8 Tough Wolf Meat to Eagan Peltskinner.")
end)

test("closing the dialog stops the reading, and a dialog it didn't read stops nothing", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    h:AcceptQuest()
    eq(h.speechStops, 1, "accepting closes the dialog, and the reading stops")
    h:OfferQuest({ id = 40, text = "Another day.", title = "Later" }, "Eagan Peltskinner")
    h:CloseQuestDialog()
    eq(h.speechStops, 2, "so does walking away")
    local spoken = #h.spoken

    h:Slash("/tlk set Scholar.readAloud off")
    h:OfferQuest({ id = 41, text = "Quiet.", title = "Hush" }, "Eagan Peltskinner")
    h:CloseQuestDialog()
    eq(#h.spoken, spoken, "with reading aloud off, nothing is read")
    eq(h.speechStops, 2, "and nothing is stopped: another voice may be talking")
end)

test("the progress and reward pages are read too", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    Accept(h, Wolves)
    h:OpenProgress(33, "Eagan Peltskinner", "Have you got the meat?")
    eq(Last(h), "Eagan Peltskinner says: Wolves Across the Border. Have you got the meat?")
    h:CloseQuestDialog()
    h:OpenTurnIn(33, "Eagan Peltskinner", "The farmers will sleep easier tonight.")
    eq(Last(h), "Eagan Peltskinner says: The farmers will sleep easier tonight.")
end)

test("it follows Read riddles aloud, and /tlk read reads the open quest whatever the setting", function()
    local h = LoadKid({ ["Scholar.grade"] = "2" })
    local spoken = #h.spoken

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    eq(#h.spoken, spoken, "Read riddles aloud is for kindergarten and grade 1 by default")
    h:Slash("/tlk read")
    truthy(Last(h):find("^Eagan Peltskinner says: Wolves Across the Border%."), "asked, it reads: " .. tostring(Last(h)))
    h:CloseQuestDialog()
    h:Slash("/tlk read")
    truthy(h.printed[#h.printed]:find("Open a quest first", 1, true), h.printed[#h.printed])
end)

test("its own switch turns it off, it's part of the challenge, and the game's text codes aren't read", function()
    local h, addon = LoadKid({ ["Scholar.grade"] = "0" })

    h:OfferQuest({ goal = "Bring it here.", id = 42, text = "Find the |cffff0000red|r stone.|nThen come back.", title = "Stones" },
        "Old Man")

    eq(Last(h), "Old Man says: Stones. Find the red stone.\nThen come back. Bring it here.")
    h:CloseQuestDialog()
    addon.State:Set("QuestReader.enabled", false)
    local spoken = #h.spoken

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    eq(#h.spoken, spoken, "its own switch")
    h:CloseQuestDialog()
    addon.State:Set("QuestReader.enabled", true)
    addon.State:Set("Scholar.enabled", false)
    falsy(addon.Modules.QuestReader:IsRunning(), "it stops with the challenge")
end)

test("switching the reader or the challenge off mid-reading stops the reading", function()
    local h, addon = LoadKid({ ["Scholar.grade"] = "0" })

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    addon.State:Set("QuestReader.enabled", false)
    eq(h.speechStops, 1, "its own switch stops the reading")
    h:CloseQuestDialog()
    eq(h.speechStops, 1, "and the dialog closing afterward has nothing left to stop")
    addon.State:Set("QuestReader.enabled", true)
    h:OfferQuest(Wolves, "Eagan Peltskinner")
    addon.State:Set("Scholar.enabled", false)
    eq(h.speechStops, 2, "so does the challenge's")
end)

test("closing the dialog doesn't stop what the Owl said after the reading", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    Accept(h, Wolves)
    h:Advance(1)
    h:OfferQuest({ id = 40, text = "Another day.", title = "Later" }, "Eagan Peltskinner")
    local spoken = #h.spoken

    h:ProgressObjective(33, 1, 3)
    h:Advance(1)
    eq(#h.spoken, spoken + 1, "the Owl counts the objective while the dialog is open")
    local stops = h.speechStops

    h:CloseQuestDialog()
    eq(h.speechStops, stops, "the count isn't cut off")
end)

test("with no text-to-speech voice, nothing is read, and /tlk read says why", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    h.ttsVoices = {}
    h:OfferQuest(Wolves, "Eagan Peltskinner")
    eq(#h.spoken, 0)
    h:Slash("/tlk read")
    truthy(h.printed[#h.printed]:find("text-to-speech voice", 1, true), h.printed[#h.printed])
end)
