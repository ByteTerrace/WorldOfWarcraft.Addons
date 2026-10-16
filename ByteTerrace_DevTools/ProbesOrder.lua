local addonName, ns = ...

-- Calibration probes about what holds as the client fires an event, for the harness guesses the addons rest on most
-- (`tlk guesses`): whether combat lockdown still holds as PLAYER_DEAD dispatches (units.lua's h:Die), what combat's
-- state is as the damage meter's current session updates (meter.lua's h:EnterCombat), whether a nameplate's frame is
-- shown and its unit exists as NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED dispatch (units.lua's h:AddNamePlate
-- and h:RemoveNamePlate), and whether a quest's title stays known once it's turned in (quests.lua). DevTools.lua
-- listens from load and passes each event here. Each keeps the set of states it saw, so a state seen before costs a
-- lookup.
--
--   Probes.NoteDeathState()               PLAYER_DEAD, for death.combatState
--   Probes.NoteCurrentSession()           DAMAGE_METER_CURRENT_SESSION_UPDATED, for damageMeter.currentSession
--   Probes.NoteNamePlate(event, token)    NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED, for namePlates.events
--   Probes.NoteTurnIn(questID)            QUEST_TURNED_IN, for questLog.titleAfterTurnIn

local C_NamePlate = C_NamePlate
local C_QuestLog = C_QuestLog
local C_RestrictedActions = C_RestrictedActions
local InCombatLockdown = InCombatLockdown
local pcall = pcall
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists

local Probes = ns.Probes
local Flag = Probes.Flag
local Joined = Probes.Joined
local Note = Probes.Note
local Text = Probes.Text

-- The combat states PLAYER_DEAD dispatched in, as a set (NoteDeathState).
local DeathStates = {}
-- [event] = the set of "shown=... exists=..." states each nameplate event dispatched in (NoteNamePlate).
local PlateStates = {}
-- The combat states DAMAGE_METER_CURRENT_SESSION_UPDATED dispatched in, as a set (NoteCurrentSession).
local SessionStates = {}
-- The last quest turned in since load (NoteTurnIn): its ID, or nil.
local TurnedIn = { questID = nil }

-- Returns combat's state as one item, as combat.edges writes it: lockdown, the player's combat flag, and the Combat
-- restriction.
local function CombatState()
    local restricted = C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)

    return ("lockdown=%s affecting=%s restricted=%s"):format(Flag(InCombatLockdown()), Flag(UnitAffectingCombat("player")),
        Flag(restricted))
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

Probes.NoteCurrentSession, Probes.NoteDeathState = NoteCurrentSession, NoteDeathState
Probes.NoteNamePlate, Probes.NoteTurnIn = NoteNamePlate, NoteTurnIn

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
