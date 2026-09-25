local addonName, ns = ...

-- Journal: a session journal that celebrates what you did, per character.
--
--   Welcome back   at login after 30+ minutes away, a card recalls your last session (where you
--                  were, how long, what you got done) and the rested XP you built up while away.
--   Ding!          at level-up, a card sums up the level you just finished, with a milestone line
--                  every tenth level and at max level.
--   /tlk journal   this session's highlights so far.
--
-- Cards come from ns.Cards (Cards.lua): they wait out combat, hold on hover, dismiss on click.
--
-- The session lives in per-character rows. A /reload continues it; the next login looks back on
-- it. Played time is summed from GetTime deltas while the journal runs; time away is server time.

local MinAwaySeconds = 30 * 60
local MinRestedPercent = 1
local ContinueWindowSeconds = 120
local JournalIcon = "Interface\\Icons\\INV_Misc_Book_09"
local DingIcon = "Interface\\Icons\\Spell_Holy_SurgeOfLight"

local Rows = {
    { name = "welcome", kind = "boolean", default = true, label = "Welcome-back card",
        description = "At login after 30 minutes or more away, a card recalls your last session and the rested XP you built up." },
    { name = "ding", kind = "boolean", default = true, label = "Level-up card",
        description = "When you level up, a card sums up the level you just finished." },
}
for _, name in ipairs({
    "sessionStart", "sessionSeen", "sessionPlayed", "sessionStartLevel", "sessionEndLevel",
    "sessionStartMoney", "sessionEndMoney", "sessionQuests", "sessionDeaths", "sessionRested",
    "levelPlayed", "levelQuests", "levelDeaths",
}) do
    Rows[#Rows + 1] = { name = name, kind = "number", default = 0, scope = "character" }
end
-- -1: no baseline yet (a new character's 0 copper is a real baseline).
Rows[#Rows + 1] = { name = "levelStartMoney", kind = "number", default = -1, scope = "character" }
-- Whether the level's counters began at a ding (false: since the journal started).
Rows[#Rows + 1] = { name = "levelFromDing", kind = "boolean", default = false, scope = "character" }
Rows[#Rows + 1] = { name = "sessionZone", kind = "string", default = "", scope = "character" }

local GetMaxPlayerLevel, GetMoney = GetMaxPlayerLevel, GetMoney
local GetMoneyString, GetRealZoneText, GetServerTime, GetTime, GetXPExhaustion = GetMoneyString, GetRealZoneText, GetServerTime, GetTime, GetXPExhaustion
local IsLoggedIn, SecondsToTime, SOUNDKIT, UnitLevel, UnitName, UnitXPMax = IsLoggedIn, SecondsToTime, SOUNDKIT, UnitLevel, UnitName, UnitXPMax
local issecretvalue, floor, abs, concat = issecretvalue, math.floor, math.abs, table.concat

local Addon = ns.Addon
local ShowCard = ns.Cards.Show

local Journal -- the Journal module, declared last

-- Played time since the last checkpoint is folded into the session and level totals.
local SegmentStart = GetTime()

-- Set once this UI load has begun (or continued) a session, so disabling and re-enabling the
-- journal within one load keeps the session.
local BegunThisLoad = false

local function Duration(seconds)
    if seconds < 60 then
        return "under a minute"
    end
    return SecondsToTime(seconds, true, true, 2)
end

local function Money(copper)
    if copper == 0 then
        return nil
    end
    return (copper > 0 and "+" or "-") .. GetMoneyString(abs(copper), true)
end

local function Count(number, one, many)
    if number == 0 then
        return nil
    end
    return number == 1 and ("1 " .. one) or (number .. " " .. many)
end

-- Joins the non-nil parts with a middle dot.
local function Line(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part then
            parts[#parts + 1] = part
        end
    end
    return concat(parts, " · ")
end

local function Deaths(count)
    return Count(count, "trip to the spirit healer", "trips to the spirit healer")
end

local function PlayerName()
    local name = UnitName("player")
    if issecretvalue(name) or not name then
        return "adventurer"
    end
    return name
end

-- Rested XP as a percentage of the current level's XP (0 at max level or when XP is off).
local function RestedPercent(rested)
    local needed = UnitXPMax("player")
    if needed <= 0 then
        return 0
    end
    return rested * 100 / needed
end

local function Get(row)
    return Journal:Get(row)
end

local function Add(row, amount)
    Journal:Set(row, Journal:Get(row) + amount)
end

local function Checkpoint()
    local elapsed = floor(GetTime() - SegmentStart)
    SegmentStart = SegmentStart + elapsed
    Add("sessionPlayed", elapsed)
    Add("levelPlayed", elapsed)
end

local function SaveSeen()
    Checkpoint()
    Journal:Set("sessionSeen", GetServerTime())
    Journal:Set("sessionEndLevel", UnitLevel("player"))
    Journal:Set("sessionEndMoney", GetMoney())
    Journal:Set("sessionZone", GetRealZoneText() or "")
    Journal:Set("sessionRested", GetXPExhaustion() or 0)
end

local function StartSession()
    local level, money = UnitLevel("player"), GetMoney()
    Journal:Set("sessionStart", GetServerTime())
    Journal:Set("sessionPlayed", 0)
    Journal:Set("sessionStartLevel", level)
    Journal:Set("sessionStartMoney", money)
    Journal:Set("sessionQuests", 0)
    Journal:Set("sessionDeaths", 0)
    if Get("levelStartMoney") < 0 then
        Journal:Set("levelStartMoney", money)
    end
    SaveSeen()
end

-- The welcome card for the previous session, or nil when there's nothing worth a card.
local function WelcomeCard()
    local away = GetServerTime() - Get("sessionSeen")
    if Get("sessionStart") == 0 or away < MinAwaySeconds then
        return nil
    end
    local restedGain = RestedPercent((GetXPExhaustion() or 0) - Get("sessionRested"))
    local levels = Get("sessionEndLevel") - Get("sessionStartLevel")
    local zone = Get("sessionZone")
    local first = "You were away " .. Duration(away) .. "."
    if restedGain >= MinRestedPercent then
        first = first .. " Rested up: +" .. floor(restedGain) .. "% of a level."
    end
    local last = (zone ~= "" and ("Last time in " .. zone .. ": ") or "Last time: ") .. Line(
        Duration(Get("sessionPlayed")),
        Count(Get("sessionQuests"), "quest", "quests"),
        Money(Get("sessionEndMoney") - Get("sessionStartMoney")),
        levels > 0 and ("reached level " .. Get("sessionEndLevel")) or nil)
    return { icon = JournalIcon, sound = SOUNDKIT.IG_SPELLBOOK_OPEN,
        title = "Welcome back, " .. PlayerName() .. "!", body = first .. "\n" .. last }
end

local function SessionCard()
    Checkpoint()
    local levels = UnitLevel("player") - Get("sessionStartLevel")
    local summary = Line(
        Duration(Get("sessionPlayed")),
        Count(Get("sessionQuests"), "quest", "quests"),
        Count(levels, "level", "levels"),
        Money(GetMoney() - Get("sessionStartMoney")),
        Deaths(Get("sessionDeaths")))
    local rested = RestedPercent(GetXPExhaustion() or 0)
    if rested >= MinRestedPercent then
        summary = summary .. "\nRested XP banked: " .. floor(rested) .. "% of a level."
    end
    return { icon = JournalIcon, sound = SOUNDKIT.IG_SPELLBOOK_OPEN, title = "This session", body = summary }
end

local function Milestone(level)
    if level >= GetMaxPlayerLevel() then
        return "Max level. Legendary."
    elseif level % 10 == 0 then
        return "Level " .. level .. " is a milestone!"
    end
end

local function DingCard(level)
    Checkpoint()
    local deaths = Get("levelDeaths")
    local lead = Get("levelFromDing") and ("Level " .. (level - 1) .. " took " .. Duration(Get("levelPlayed")))
        or ("Since the journal started: " .. Duration(Get("levelPlayed")))
    local body = Line(
        lead,
        Count(Get("levelQuests"), "quest", "quests"),
        Money(GetMoney() - Get("levelStartMoney")),
        deaths == 0 and "not a single death!" or Deaths(deaths))
    local milestone = Milestone(level)
    if milestone then
        body = body .. "\n" .. milestone
    end
    Journal:Set("levelPlayed", 0)
    Journal:Set("levelQuests", 0)
    Journal:Set("levelDeaths", 0)
    Journal:Set("levelStartMoney", GetMoney())
    Journal:Set("levelFromDing", true)
    return { icon = DingIcon, sound = SOUNDKIT.LFG_REWARDS, title = "Ding! Level " .. level, body = body }
end

Journal = Addon:Module("Journal", {
    label = "Session journal",
    description = "Celebrates your play: a welcome-back card at login, a Ding! card at level-up, and /tlk journal for this session's highlights.",
    state = Rows,
    commands = {
        { name = "show", slash = "journal", label = "Show this session's journal", run = function() ShowCard(SessionCard()) end },
    },
    OnEnable = function(module)
        SegmentStart = GetTime()

        local function Begin(isInitialLogin, isReload)
            if isInitialLogin then
                local welcome = Get("welcome") and WelcomeCard()
                StartSession()
                if welcome then
                    ShowCard(welcome)
                end
            elseif not (BegunThisLoad or (isReload and Get("sessionStart") ~= 0)
                or (Get("sessionStart") ~= 0 and GetServerTime() - Get("sessionSeen") < ContinueWindowSeconds)) then
                StartSession() -- enabled late with an older session on file: start fresh, no card
            end
            BegunThisLoad = true
        end

        module:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
            if not BegunThisLoad then
                Begin(isInitialLogin, isReloadingUi)
            end
        end)
        if IsLoggedIn() and not BegunThisLoad then
            Begin(false, false) -- enabled mid-session
        end
        module:On("QUEST_TURNED_IN", function()
            Add("sessionQuests", 1)
            Add("levelQuests", 1)
        end)
        module:On("PLAYER_DEAD", function()
            Add("sessionDeaths", 1)
            Add("levelDeaths", 1)
        end)
        module:On("PLAYER_LEVEL_UP", function(level)
            local ding = DingCard(level)
            if Get("ding") then
                ShowCard(ding)
            end
        end)
        module:On("PLAYER_LOGOUT", SaveSeen)
    end,
    OnDisable = function()
        SaveSeen() -- keep the played time so far
    end,
})
