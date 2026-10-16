-- ByteTerrace_DevTools' quest dialog listener: every QUEST_DETAIL and QUEST_COMPLETE from load keeps what the questnpc
-- GUID says it is, by the context it dispatched in and, for an offer, its source (an item's, the tracker popup's
-- reopening, or a plain one), for quest.giverKind, quest.giverKindInCombat, quest.itemGiverKind, quest.enderKind, and
-- quest.enderKindInCombat.

local Letter = { text = "The letter is addressed to the town's marshal.", title = "A Stained Letter" }
local Wolves = { text = "The wolves grow bolder each night.", title = "Wolves Across the Border" }

local function Load()
    local h = Harness.New()

    h:LoadAddon("ByteTerrace_DevTools")

    return h
end

local function Records(h)
    return h.env.ByteTerraceDevToolsDB.probes
end

local function Run(h, name)
    return h.ns.Probes.ByName[name].run()
end

test("an item's quest is kept apart from a giver's, and the popup's reopening apart from both", function()
    local h = Load()

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    h:CloseQuestDialog()
    local id = h:OfferItemQuest(Letter, { guid = "Item-4372-0-4000000012345678", name = "A Stained Letter" }, 1307)

    falsy(h.env.QuestFrameDetailPanel:IsShown(), "Blizzard's QuestFrame shows no panel for an item's offer")
    h:ReopenQuestOffer(id)
    truthy(h.env.QuestFrameDetailPanel:IsShown(), "the popup's reopening shows it")
    h:AcceptQuest()

    local plain = Run(h, "quest.giverKind")["idle/none"]

    eq(plain.plain.kind, "Creature")
    eq(plain.plain.startItem, "zero")
    eq(plain.item, nil, "the item's offer isn't a giver's")
    eq(plain.reopen, nil, "nor is the reopening")

    local items = Run(h, "quest.itemGiverKind")["idle/none"]

    eq(items.item.kind, "Item")
    eq(items.item.questID, "positive")
    eq(items.item.startItem, "positive")
    eq(items.reopen.kind, "Item", "the reopening comes from the same item")
    eq(items.reopen.startItem, "zero")
    eq(items.plain, nil, "the giver's offer isn't an item's")
    h:Slash("/btdev probe")
    truthy(Records(h)["quest.giverKind"], "recorded")
    truthy(Records(h)["quest.itemGiverKind"], "recorded")
    eq(Records(h)["quest.giverKindInCombat"], nil, "nothing was offered in combat")
end)

test("an offer in combat is kept under the combat context, and an idle one isn't in the combat probe", function()
    local h = Load()

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    h:CloseQuestDialog()
    h:EnterCombat()
    h:OfferItemQuest(Letter, nil, 1307)
    h:Slash("/btdev probe")

    local combat = Records(h)["quest.giverKindInCombat"].result

    eq(combat["combat/Combat"].item.kind, "Item", "open-world combat keeps the GUID plain in the harness")
    eq(combat["idle/none"], nil)
    eq(Run(h, "quest.giverKind")["combat/Combat"], nil, "the idle probe keeps idle offers only")
    eq(Run(h, "quest.itemGiverKind")["combat/Combat"].item.kind, "Item", "the item probe keeps every context")
end)

test("an item's quest whose QUEST_DETAIL carries no start item is a plain offer whose GUID says it's an item's", function()
    local h = Load()

    h:OfferQuest(Letter, { guid = "Item-4372-0-4000000012345678", name = "A Stained Letter" })
    eq(Run(h, "quest.giverKind")["idle/none"].plain.kind, "Item")
    eq(next(Run(h, "quest.itemGiverKind")), nil, "no start item, no item source")
end)

test("a secret questnpc GUID is kept as secret, under the restriction that made it one", function()
    local h = Load()

    h:SetRestriction("Encounter", true)
    h:OfferQuest(Wolves, "Eagan Peltskinner")
    h:CloseQuestDialog()
    eq(Run(h, "quest.giverKind")["idle/Encounter"].plain.kind, "secret")
end)

test("turn-ins are kept per context: an object's out of combat, a creature's in combat", function()
    local h = Load()
    local first = h:AutoAcceptQuest({ title = "Report to Goldshire" })
    local second = h:AutoAcceptQuest({ title = "Rest Now" })

    h:OpenTurnIn(first, { guid = "GameObject-0-4372-0-12-99-0000654321", name = "Gravestone" }, "Rest now.")
    h:CompleteQuest()
    h:EnterCombat()
    h:OpenTurnIn(second, "Marshal Dughan", "Ah, you made it.")
    eq(Run(h, "quest.enderKind")["idle/none"], "GameObject")
    eq(Run(h, "quest.enderKind")["combat/Combat"], nil)
    eq(Run(h, "quest.enderKindInCombat")["combat/Combat"], "Creature")
end)

test("an offer asks the client for the quest's ID and the questnpc's GUID once each, and nothing about restrictions", function()
    local h = Load()

    h:OfferQuest(Wolves, "Eagan Peltskinner")
    h:CloseQuestDialog()
    local before = {}

    for name, count in pairs(h.apiCalls) do before[name] = count end

    h:OfferQuest(Letter, "Marshal Dughan")
    local asked = {}

    for name, count in pairs(h.apiCalls) do
        if count ~= (before[name] or 0) then
            asked[#asked + 1] = ("%s=%d"):format(name, count - (before[name] or 0))
        end
    end

    table.sort(asked)
    eq(table.concat(asked, " "), "GetQuestID=1 InCombatLockdown=1 UnitGUID=1 issecretvalue=3")
end)
