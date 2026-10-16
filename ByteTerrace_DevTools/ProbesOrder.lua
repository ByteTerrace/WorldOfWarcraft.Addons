local addonName, ns = ...

-- Calibration probes about what holds as the client fires an event, for the harness guesses the addons rest on most
-- (`tlk guesses`): whether combat lockdown still holds as PLAYER_DEAD dispatches (units.lua's h:Die), what combat's
-- state is as the damage meter's current session updates (meter.lua's h:EnterCombat), whether a nameplate's frame is
-- shown and its unit exists as NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED dispatch (units.lua's h:AddNamePlate
-- and h:RemoveNamePlate), whether a quest's title stays known once it's turned in, and what a quest dialog's questnpc
-- GUID says it is as the dialog's events dispatch (quests.lua). DevTools.lua listens from load and passes each event
-- here. Each keeps the set of states it saw, so a state seen before costs a lookup.
--
-- The quest dialog's questnpc is heard from load, since Blizzard's QuestFrame (Mainline QuestFrame.lua) never shows the
-- offer panel for a QUEST_DETAIL that carries a start item: it adds the objective tracker's popup and calls CloseQuest,
-- and clicking the popup (ShowQuestOffer) fires QUEST_DETAIL again. Each offer is kept under the context it dispatched
-- in ("idle/none", "combat/Combat") and its source: "item" when it carried a start item, "reopen" when it didn't but an
-- item offered the same quest earlier since load, and "plain" otherwise. An item quest whose QUEST_DETAIL carries 0
-- shows up as a plain offer whose GUID is an item's: the GUID's type answers it, so nothing scans the bags. Only GUID
-- types and payload shapes are kept, never a GUID or an ID.
--
--   Probes.NoteDeathState()               PLAYER_DEAD, for death.combatState
--   Probes.NoteCurrentSession()           DAMAGE_METER_CURRENT_SESSION_UPDATED, for damageMeter.currentSession
--   Probes.NoteNamePlate(event, token)    NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED, for namePlates.events
--   Probes.NoteTurnIn(questID)            QUEST_TURNED_IN, for questLog.titleAfterTurnIn
--   Probes.NoteQuestDetail(startItemID)   QUEST_DETAIL, for quest.giverKind, quest.giverKindInCombat, and
--                                         quest.itemGiverKind
--   Probes.NoteQuestComplete()            QUEST_COMPLETE, for quest.enderKind and quest.enderKindInCombat

local C_NamePlate = C_NamePlate
local C_QuestLog = C_QuestLog
local C_RestrictedActions = C_RestrictedActions
local GetQuestID = GetQuestID
local InCombatLockdown = InCombatLockdown
local pcall = pcall
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local UnitGUID = UnitGUID

local Probes = ns.Probes
local Flag = Probes.Flag
local Joined = Probes.Joined
local JoinSets = Probes.JoinSets
local Note = Probes.Note
local Restricted = Probes.Restricted
local Text = Probes.Text

-- The combat states PLAYER_DEAD dispatched in, as a set (NoteDeathState).
local DeathStates = {}
-- The quests an item offered since load, as a set of their IDs, so the popup's QUEST_DETAIL is known (NoteQuestDetail).
local ItemQuests = {}
-- [context][source] = { kind, questID, startItem }, each the set of shapes QUEST_DETAIL showed (NoteQuestDetail).
local Offers = {}
-- [event] = the set of "shown=... exists=..." states each nameplate event dispatched in (NoteNamePlate).
local PlateStates = {}
-- The combat states DAMAGE_METER_CURRENT_SESSION_UPDATED dispatched in, as a set (NoteCurrentSession).
local SessionStates = {}
-- The last quest turned in since load (NoteTurnIn): its ID, or nil.
local TurnedIn = { questID = nil }
-- [context] = the set of questnpc GUID types QUEST_COMPLETE showed (NoteQuestComplete).
local TurnIns = {}

-- Returns combat's state as one item, as combat.edges writes it: lockdown, the player's combat flag, and the Combat
-- restriction.
local function CombatState()
    local restricted = C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)

    return ("lockdown=%s affecting=%s restricted=%s"):format(Flag(InCombatLockdown()), Flag(UnitAffectingCombat("player")),
        Flag(restricted))
end

-- Returns the context an event dispatched in, as Probes.Context writes it, from the restrictions DevTools follows.
local function Context()
    return (((InCombatLockdown() and "combat/") or "idle/") .. Restricted.text)
end

-- Returns whether a context's offers or turn-ins were heard: in a state ("idle" or "combat", any when nil) and from a
-- source (any when nil).
local function Heard(sets, state, source)
    for context, sources in pairs(sets) do
        if (not state or (context:match("^(%a+)/") == state)) and (not source or sources[source]) then
            return true
        end
    end

    return false
end

local function NoteCurrentSession()
    SessionStates[CombatState()] = true
end

local function NoteDeathState()
    DeathStates[CombatState()] = true
end

-- A plate this code can't read is "none" (GetNamePlateForUnit gives insecure code no forbidden plate) or "forbidden"
-- (IsShown refused).
local function NoteNamePlate(event, token)
    local plate = C_NamePlate.GetNamePlateForUnit(token)
    local shown = "none"

    if plate then
        local ok, visible = pcall(plate.IsShown, plate)

        shown = ((ok and Flag(visible)) or "forbidden")
    end

    Note(PlateStates, event, ("shown=%s exists=%s"):format(shown, Flag(UnitExists(token))))
end

local function NoteTurnIn(questID)
    if not issecretvalue(questID) and (type(questID) == "number") then
        TurnedIn.questID = questID
    end
end

-- Returns a number's shape as a set item: "secret", "positive", "zero", or its type.
local function NumberShape(value)
    if issecretvalue(value) then
        return "secret"
    elseif type(value) ~= "number" then
        return type(value)
    end

    return (((value > 0) and "positive") or "zero")
end

-- Returns the type the questnpc GUID starts with ("Creature", "Item", and so on), "other", its type when it isn't a
-- string ("nil"), or "secret".
local function QuestNpcKind()
    local guid = UnitGUID("questnpc")

    if issecretvalue(guid) then
        return "secret"
    elseif type(guid) ~= "string" then
        return type(guid)
    end

    return (guid:match("^(%a+)%-") or "other")
end

local function NoteQuestComplete()
    Note(TurnIns, Context(), QuestNpcKind())
end

local function NoteQuestDetail(startItemID)
    local questID = GetQuestID()
    local idShape = NumberShape(questID)
    local startItem = NumberShape(startItemID)
    local known = (idShape == "positive")
    local source = "plain"

    if startItem == "positive" then
        source = "item"

        if known then
            ItemQuests[questID] = true
        end
    elseif known and ItemQuests[questID] then
        source = "reopen"
    end

    local context = Context()
    local bySource = Offers[context]

    if not bySource then
        bySource = {}
        Offers[context] = bySource
    end

    local fields = bySource[source]

    if not fields then
        fields = {}
        bySource[source] = fields
    end

    Note(fields, "kind", QuestNpcKind())
    Note(fields, "questID", idShape)
    Note(fields, "startItem", startItem)
end

-- Returns the offers or turn-ins heard in a state ("idle" or "combat", any when nil) as a record holds them, each
-- context's from the sources listed (all when nil).
local function Slice(sets, state, sources)
    local out = {}

    for context, bySource in pairs(sets) do
        if not state or (context:match("^(%a+)/") == state) then
            local kept = bySource

            if sources then
                kept = {}

                for _, source in ipairs(sources) do
                    kept[source] = bySource[source]
                end
            end

            if next(kept) ~= nil then
                out[context] = kept
            end
        end
    end

    return JoinSets(out)
end

Probes.NoteCurrentSession, Probes.NoteDeathState = NoteCurrentSession, NoteDeathState
Probes.NoteNamePlate, Probes.NoteTurnIn = NoteNamePlate, NoteTurnIn
Probes.NoteQuestComplete, Probes.NoteQuestDetail = NoteQuestComplete, NoteQuestDetail

-- The item, quests, and giver the needs' harness setups use.
local SetupItem = { guid = "Item-4372-0-4000000012345678", name = "A Stained Letter" }
local SetupItemID = 1307
local SetupItemQuest = { text = "The letter is addressed to the town's marshal.", title = "A Stained Letter" }

local SetupOffer = { goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", text = "The wolves grow bolder each night.",
    title = "Wolves Across the Border" }

local SetupTurnIn = { title = "Report to Goldshire" }

Probes.AddNeeds({
    diedSinceLoad = {
        check = function() return (next(DeathStates) ~= nil) end,
        label = "died",
        setup = function(h)
            h:EnterCombat()
            h:Die()
        end,
        step = 5,
        text = "you died since DevTools loaded (let a mob kill you)",
    },
    namePlateCameAndWent = {
        check = function()
            return ((PlateStates.NAME_PLATE_UNIT_ADDED ~= nil) and (PlateStates.NAME_PLATE_UNIT_REMOVED ~= nil))
        end,
        label = "nameplate came and went",
        setup = function(h)
            h:RemoveNamePlate(h:AddNamePlate({ canAttack = true, classFile = "WARRIOR", level = 2, name = "Kobold Vermin" }))
        end,
        step = 4,
        text = "a nameplate appeared and went away since DevTools loaded (V shows enemy nameplates; walk past a mob)",
    },
    questCompletedIdle = {
        check = function() return Heard(TurnIns, "idle") end,
        label = "turn-in heard",
        setup = function(h)
            h:OpenTurnIn(h:AutoAcceptQuest(SetupTurnIn), "Marshal Dughan", "Ah, you made it.")
        end,
        step = 2,
        text = "a quest turn-in's reward panel opened out of combat since DevTools loaded",
    },
    questCompletedInCombat = {
        check = function() return Heard(TurnIns, "combat") end,
        label = "turn-in heard in combat",
        setup = function(h)
            local id = h:AutoAcceptQuest(SetupTurnIn)

            h:EnterCombat()
            h:OpenTurnIn(id, "Marshal Dughan", "Ah, you made it.")
        end,
        step = 4,
        text = "a quest turn-in's reward panel opened in combat since DevTools loaded (talk to its ender mid-fight)",
    },
    questItemOffered = {
        check = function() return Heard(Offers, nil, "item") end,
        label = "item quest heard",
        setup = function(h)
            h:ReopenQuestOffer(h:OfferItemQuest(SetupItemQuest, SetupItem, SetupItemID))
        end,
        step = 4,
        text = ("an item began a quest since DevTools loaded (right-click one that says This Item Begins a Quest, then"
            .. " click the tracker's popup)"),
    },
    questOfferedIdle = {
        check = function() return Heard(Offers, "idle", "plain") end,
        label = "offer heard",
        setup = function(h)
            h:OfferQuest(SetupOffer, "Eagan Peltskinner")
        end,
        step = 2,
        text = "a quest giver offered a quest out of combat since DevTools loaded (open one you haven't accepted)",
    },
    questOfferedInCombat = {
        check = function() return Heard(Offers, "combat") end,
        label = "offer heard in combat",
        setup = function(h)
            h:EnterCombat()
            h:OfferItemQuest(SetupItemQuest, SetupItem, SetupItemID)
        end,
        step = 4,
        text = "a quest was offered in combat since DevTools loaded (right-click an item that begins a quest mid-fight)",
    },
    sessionUpdated = {
        check = function() return (next(SessionStates) ~= nil) end,
        label = "meter session",
        setup = function(h)
            h:EnterCombat()
            h:LeaveCombat()
        end,
        step = 4,
        text = "the damage meter started a session since DevTools loaded (fight a mob)",
    },
    turnedInQuest = {
        check = function() return (TurnedIn.questID ~= nil) end,
        label = "quest turned in",
        setup = function(h)
            h:OpenTurnIn(h:AutoAcceptQuest({ title = "Report to Goldshire" }), "Marshal Dughan", "Ah, you made it.")
            h:CompleteQuest()
        end,
        step = 2,
        text = "turned in a quest since DevTools loaded (click Complete Quest)",
    },
})

Probes.Define({
    {
        accumulates = true,
        -- The combat states PLAYER_DEAD dispatched in: the harness's h:Die fires it while lockdown still holds and only
        -- then ends combat, which FactsDeath.lua, Kombat.lua, and WarbandDeaths.lua read as one fight's end.
        name = "death.combatState",
        needs = { "diedSinceLoad" },
        run = function() return { atDeath = Joined(DeathStates) } end,
    },
    {
        accumulates = true,
        -- The combat states DAMAGE_METER_CURRENT_SESSION_UPDATED dispatched in: the harness starts a session as
        -- h:EnterCombat's PLAYER_REGEN_DISABLED leaves lockdown in force, and nowhere else. Kombat.lua and Facts.lua
        -- follow the current session.
        name = "damageMeter.currentSession",
        needs = { "sessionUpdated" },
        run = function() return { updatedIn = Joined(SessionStates) } end,
    },
    {
        accumulates = true,
        -- Whether a nameplate's frame is shown and its unit exists as NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED
        -- dispatch: the harness shows the plate before ADDED, and keeps the unit readable through REMOVED and hides the
        -- plate after it. Warband.lua and WarbandBadges.lua draw on plates in those handlers.
        name = "namePlates.events",
        needs = { "namePlateCameAndWent" },
        run = function()
            return { added = Joined(PlateStates.NAME_PLATE_UNIT_ADDED), removed = Joined(PlateStates.NAME_PLATE_UNIT_REMOVED) }
        end,
    },
    {
        accumulates = true,
        -- What offers a quest out of combat, as each plain QUEST_DETAIL's questnpc GUID says while it dispatches (see
        -- the header): per context, its type ("Creature", "GameObject", "Item", "Player", and so on), "nil", or
        -- "secret", with the shapes of GetQuestID and the start item. QuestBook.lua's KindOf and ScholarQuests.lua's
        -- IsPerson rest on it.
        name = "quest.giverKind",
        needs = { "questOfferedIdle" },
        run = function() return Slice(Offers, "idle", { "plain" }) end,
        version = 2,
    },
    {
        accumulates = true,
        -- The same in combat, from every source: whether the questnpc GUID that QuestBook.lua's KindOf reads is secret
        -- in open-world combat.
        name = "quest.giverKindInCombat",
        needs = { "questOfferedInCombat" },
        run = function() return Slice(Offers, "combat") end,
    },
    {
        accumulates = true,
        -- What gives a quest an item starts, in any context: the item's own QUEST_DETAIL and the popup's ("item" and
        -- "reopen"), each with the questnpc GUID's type and the shapes of GetQuestID and the start item. A reopen means
        -- the quest's offer fires twice, and QuestBook.lua and QuestReader.lua hear both.
        name = "quest.itemGiverKind",
        needs = { "questItemOffered" },
        run = function() return Slice(Offers, nil, { "item", "reopen" }) end,
    },
    {
        accumulates = true,
        -- What takes a quest in out of combat, as each QUEST_COMPLETE's questnpc GUID says while it dispatches (see
        -- quest.giverKind), per context. QuestBook.lua's enderKind rests on it.
        name = "quest.enderKind",
        needs = { "questCompletedIdle" },
        run = function() return Slice(TurnIns, "idle") end,
        version = 2,
    },
    {
        accumulates = true,
        -- The same in combat.
        name = "quest.enderKindInCombat",
        needs = { "questCompletedInCombat" },
        run = function() return Slice(TurnIns, "combat") end,
    },
    {
        -- Whether C_QuestLog.GetTitleForQuestID still names the last quest turned in: the harness keeps a turned-in
        -- quest's title known, which QuestBook.lua relies on to name the quest it records at the turn-in.
        name = "questLog.titleAfterTurnIn",
        needs = { "turnedInQuest" },
        run = function()
            local title = C_QuestLog.GetTitleForQuestID(TurnedIn.questID)

            return { title = ((issecretvalue(title) and "secret") or Text(title)) }
        end,
    },
})
