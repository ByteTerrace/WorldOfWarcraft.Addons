local addonName, ns = ...

-- QuestBook: every quest the player has been shown, remembered per character so the Scholar's
-- challenge can ask about it (ScholarQuests.lua writes the riddles). A demand module: it records
-- while the challenge runs (Scholar uses it).
--
-- A quest is recorded when it's accepted, from what the client showed: the giver's offer
-- (QUEST_DETAIL: the title, the quest's text and goal, the giver's name), or the quest log alone
-- for a quest an area trigger accepted, whose text the player reads by opening the log. Its
-- objectives come from the log (each with its kind: item, monster, ...), and where it began from
-- the subzone (with the zone around it, never a wrong answer for where). Turning it in
-- (QUEST_COMPLETE, then QUEST_TURNED_IN) adds who took it, where, and the reward text. Each
-- exposure, accepting and turning in, makes the quest fresh: something new to ask about. Only
-- these events read the quest APIs, out of combat as quests are, and a secret answer is left out
-- rather than stored.
--
-- When the book starts (the challenge switched on mid-game, or a login), the quests already in
-- the log are recorded as the log shows them: title, text and objectives, not fresh, with no
-- giver or place, since nobody saw them given. The log may still be empty at login, so the first
-- QUEST_LOG_UPDATE after the start looks again.
--
-- An objective is named in the client's own words: its text is read with the locale's
-- GlobalStrings (QUEST_ITEMS_NEEDED, QUEST_MONSTERS_KILLED, QUEST_OBJECTS_FOUND), so "0/8 Wolf
-- Pelt" names "Wolf Pelt" and "0/10 Kobold Vermin slain" names "Kobold Vermin" on enUS, and the
-- same on any other client. One the client hasn't named yet (its item or creature not loaded:
-- "0/5 " for "0/5 Duskbat Pelt") isn't recorded: the quest waits (unnamed) and its objectives are
-- read again on QUEST_LOG_UPDATE until every one has a name, it leaves the log, or MaxNameReads
-- updates pass, when the book gives up on the missing names. A named book reads no objectives then.
--
--   ns.QuestBook.Order()            every key in the order to ask about them: fresh quests, newest
--                                   first, then the rest for review, the one asked longest ago first
--   ns.QuestBook.Asked(key, kind)   the quest has been asked about (now) since its last exposure,
--                                   with a riddle of kind (askedKind, "" for none)
--   ns.QuestBook.All()              every record, as copies with their key, newest first
--
-- Records are QuestBook.quests, keyed by the quest ID as text, up to Limit of them (the oldest
-- seen go first). Texts are whole, keep their line breaks and lose the client's escape codes (a
-- link keeps its text, a texture goes); an objective is what it names, with its required count
-- beside it ("0/8 Wolf Pelt" is "Wolf Pelt", with 8 its required count).

local Limit = 30
local MaxLine = 120     -- characters kept of a title, name, place, goal or objective
local MaxNameReads = 20 -- QUEST_LOG_UPDATEs an unnamed quest's objectives are read on before the book gives up
local MaxObjectives = 3

local C_QuestLog, GetQuestID, GetQuestLogQuestText = C_QuestLog, GetQuestID, GetQuestLogQuestText
local concat = table.concat
local GetObjectiveText, GetQuestText, GetRewardText, GetTitleText = GetObjectiveText, GetQuestText, GetRewardText, GetTitleText
local GetRealZoneText, GetServerTime, GetSubZoneText, UnitName = GetRealZoneText, GetServerTime, GetSubZoneText, UnitName
local gmatch, gsub, match, sub = string.gmatch, string.gsub, string.match, string.sub
local ipairs, issecretvalue, tostring, type = ipairs, issecretvalue, tostring, type
local next, pairs, tonumber, wipe = next, pairs, tonumber, wipe
local QUEST_ITEMS_NEEDED, QUEST_MONSTERS_KILLED, QUEST_OBJECTS_FOUND = QUEST_ITEMS_NEEDED, QUEST_MONSTERS_KILLED, QUEST_OBJECTS_FOUND

-- A format's literal text as a pattern: punctuation escaped, and any run of spaces optional, since
-- an unloaded name leaves its spaces at the trimmed ends ("0/5 " reads "0/5").
local function Literal(text)
    return (gsub(gsub(text, "%p", "%%%0"), "%s+", "%%s*"))
end

-- A Lua pattern that reads a quest objective GlobalString's text ("%2$d/%3$d %1$s slain"): the
-- counts match digits and the name is its one capture.
local function CountPattern(format)
    local parts, position = { "^" }, 1

    for start, conversion, finish in gmatch(format, "()%%%d*%$?([sd])()") do
        parts[#parts + 1] = Literal(sub(format, position, start - 1))
        parts[#parts + 1] = (((conversion == "s") and "(.-)") or "%d+")
        position = finish
    end
    parts[#parts + 1] = Literal(sub(format, position))
    parts[#parts + 1] = "$"
    return concat(parts)
end

local KillPattern, ObjectPattern, ItemPattern = CountPattern(QUEST_MONSTERS_KILLED), CountPattern(QUEST_OBJECTS_FOUND),
    CountPattern(QUEST_ITEMS_NEEDED)
-- The forms an objective's text is read with, by its log type: its own form first.
local AnyCountPatterns = { ItemPattern, ObjectPattern, KillPattern }
local CountPatterns = {
    monster = { KillPattern, ItemPattern, ObjectPattern },
    object = { ObjectPattern, ItemPattern, KillPattern },
}

local Addon = ns.Addon

local LookAgain = false -- the first QUEST_LOG_UPDATE since the start records the log again
local Offer  -- what the open offer showed: { id, title, text, goal, giver }
local QuestBookModule
local TurnIn -- what the open reward panel showed: { id, title, ender, reward }
-- The keys of quests whose objectives wait for their names (ObjectiveFields' unnamed), each with
-- the reads it has left.
local Unnamed = {}

-- A text the client gave, plain: "" for a secret or a non-string; its escape codes undone (a
-- link keeps its text, a texture goes, |n is a line break), other control characters but line
-- breaks removed and trimmed. With length (a one-line field), it's cut to length characters, at
-- the last whole sentence (else word) that fits; a quest's text is kept whole, as the log shows it.
local function Plain(text, length)
    if issecretvalue(text) or (type(text) ~= "string") then
        return ""
    end
    text = gsub(gsub(gsub(text, "|T.-|t", ""), "|H.-|h(.-)|h", "%1"), "|n", "\n")
    text = gsub(gsub(gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""), "|", "")
    text = gsub(gsub(text, "\r", ""), "[%z\1-\9\11-\31]", "")
    text = gsub(gsub(text, "^%s+", ""), "%s+$", "")
    if not length or (#text <= length) then
        return text
    end
    -- Too long: it ends at the last whole sentence that fits, else the last whole word.
    local cut = sub(text, 1, length + 1)

    return (cut:match("^(.*[%.!%?])%s") or cut:match("^(.*%S)%s") or sub(text, 1, length))
end

-- What an objective names (its item, creature or task), from the log's text in the client's own
-- forms; a text without a count is its own name. "" while the client hasn't loaded the name.
local function ObjectiveName(text, kind)
    text = Plain(text, MaxLine)
    for _, pattern in ipairs(CountPatterns[kind] or AnyCountPatterns) do
        local name = match(text, pattern)

        if name then
            return (gsub(gsub(name, "^%s+", ""), "%s+$", ""))
        end
    end
    return text
end

-- A unit's name, or "" while it's secret or missing.
local function NameOf(unit)
    local name = UnitName(unit)

    if issecretvalue(name) or (type(name) ~= "string") then
        return ""
    end
    return Plain(name, MaxLine)
end

-- Where you are: the subzone, else the zone; and the zone.
local function Place()
    local subZone, zone = Plain(GetSubZoneText(), MaxLine), Plain(GetRealZoneText(), MaxLine)

    return (((subZone ~= "") and subZone) or zone), zone
end

-- The quest log's objectives for questID, as record fields (objective1, required1, type1, ...):
-- the named ones, the rest of the slots cleared, and unnamed when one still lacks its name.
local function ObjectiveFields(questID, values)
    local count, unnamed = 0, false

    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        local required, kind = objective.numRequired, objective.type

        kind = ((not issecretvalue(kind) and (type(kind) == "string") and kind) or "")
        if not issecretvalue(required) and (type(required) == "number") and (required >= 1) and ((required % 1) == 0) then
            local name = ObjectiveName(objective.text, kind)

            if name == "" then
                unnamed = true
            elseif count < MaxObjectives then
                count = (count + 1)
                values["objective" .. count], values["required" .. count], values["type" .. count] = name, required, kind
            end
        end
    end
    for i = count + 1, MaxObjectives do
        values["objective" .. i], values["required" .. i], values["type" .. i] = "", 0, ""
    end
    values.unnamed = unnamed
    return values
end

-- Records a quest with its objectives, and remembers it waits for names when one lacks its own.
local function Record(questID, values)
    local key = tostring(questID)

    QuestBookModule.Records.quests:Set(key, ObjectiveFields(questID, values))
    if values.unnamed then
        Unnamed[key] = MaxNameReads
    end
end

-- Records the quests in the log the book doesn't hold yet (see the header).
local function RecordLog()
    local quests = QuestBookModule.Records.quests

    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        local questID = (info and not info.isHeader and not info.isHidden and info.questID)

        if (type(questID) == "number") and not issecretvalue(questID) and (questID > 0) and not quests:Has(tostring(questID)) then
            local text, goal = GetQuestLogQuestText(index)
            local values = { title = Plain(info.title, MaxLine), text = Plain(text), goal = Plain(goal, MaxLine),
                seen = GetServerTime(), fresh = false }

            if values.title ~= "" then
                Record(questID, values)
            end
        end
    end
end

-- The client loaded more names: each waiting quest still in the log reads its objectives again,
-- until its reads run out. The first update since the start also records the log again.
local function OnLogUpdate()
    if LookAgain then
        LookAgain = false
        RecordLog()
    end
    if next(Unnamed) == nil then
        return
    end
    local quests = QuestBookModule.Records.quests

    for key, reads in pairs(Unnamed) do
        local questID = tonumber(key)

        if quests:Has(key) and C_QuestLog.GetLogIndexForQuestID(questID) then
            local values = ObjectiveFields(questID, {})

            if values.unnamed and (reads <= 1) then
                values.unnamed = false -- the names never came: the named objectives are all it has
            end
            quests:Set(key, values)
            Unnamed[key] = ((values.unnamed and (reads - 1)) or nil)
        else
            Unnamed[key] = nil -- turned in or abandoned: its log entry, and the names, are gone
        end
    end
end

-- GetQuestID and the quest events' IDs are plain numbers (the snapshot flags none of them; probes
-- quest.offerIdentity and quest.turnInIdentity).
local function OnOffer()
    Offer = {
        id = GetQuestID(), title = Plain(GetTitleText(), MaxLine), text = Plain(GetQuestText()),
        goal = Plain(GetObjectiveText(), MaxLine), giver = NameOf("questnpc"),
    }
end

local function OnAccepted(questID)
    local offer = ((Offer and (Offer.id == questID) and Offer) or nil)

    Offer = nil
    local place, zone = Place()
    local values = { place = place, zone = zone, seen = GetServerTime(), fresh = true, turnedIn = false }

    if offer then
        values.title, values.text, values.goal, values.giver = offer.title, offer.text, offer.goal, offer.giver
    else
        -- An area trigger's quest: no dialog showed it, so it's what the quest log shows.
        local index = C_QuestLog.GetLogIndexForQuestID(questID)
        local text, goal = "", ""

        if index then
            text, goal = GetQuestLogQuestText(index)
        end
        values.title = Plain(C_QuestLog.GetTitleForQuestID(questID), MaxLine)
        values.text, values.goal = Plain(text), Plain(goal, MaxLine)
    end
    if values.title == "" then
        return -- nothing to name it by
    end
    Record(questID, values)
end

local function OnTurnInPanel()
    TurnIn = { id = GetQuestID(), title = Plain(GetTitleText(), MaxLine), ender = NameOf("questnpc"),
        reward = Plain(GetRewardText()) }
end

local function OnTurnedIn(questID)
    local turnIn = ((TurnIn and (TurnIn.id == questID) and TurnIn) or nil)

    TurnIn = nil
    local quests, key = QuestBookModule.Records.quests, tostring(questID)
    local endPlace, endZone = Place()
    local values = { turnedIn = true, endPlace = endPlace, endZone = endZone, seen = GetServerTime(), fresh = true }

    if turnIn then
        values.ender, values.reward = turnIn.ender, turnIn.reward
    end
    if not quests:Has(key) then
        -- Accepted before the book was open: the reward panel named it.
        values.title = ((turnIn and turnIn.title) or "")
        if values.title == "" then
            return
        end
    end
    quests:Set(key, values)
end

--- Every quest's key in the order to ask about them: the fresh ones (shown and not asked about
--- since), newest first, then the others for review, the one asked longest ago first.
---@return string[]
local function Order()
    local quests = QuestBookModule.Records.quests
    local keys = quests:Keys()

    table.sort(keys, function(a, b)
        local freshA, freshB = quests:Field(a, "fresh"), quests:Field(b, "fresh")

        if freshA ~= freshB then
            return freshA
        end
        local byA, byB

        if freshA then
            byA, byB = -quests:Field(a, "seen"), -quests:Field(b, "seen")
        else
            byA, byB = quests:Field(a, "askedAt"), quests:Field(b, "askedAt")
        end
        if byA ~= byB then
            return (byA < byB)
        end
        return (a < b)
    end)
    return keys
end

--- Marks a quest asked about now, with a riddle of kind: it's fresh again at its next exposure,
--- and waits its turn for review.
---@param key string
---@param kind string? the riddle's kind ("quest.count"), or nil when none was asked
local function Asked(key, kind)
    local quests = QuestBookModule.Records.quests

    if quests:Has(key) then
        quests:Set(key, { fresh = false, askedAt = GetServerTime(), askedKind = (kind or "") })
    end
end

--- Every record, newest first, each a copy with its key.
---@return table[]
local function All()
    local quests, list = QuestBookModule.Records.quests, {}

    for _, key in ipairs(quests:Keys()) do
        local record = quests:Get(key)

        record.key = key
        list[#list + 1] = record
    end
    table.sort(list, function(a, b)
        if a.seen ~= b.seen then
            return (a.seen > b.seen)
        end
        return (a.key < b.key)
    end)
    return list
end

local Fields = {
    { default = "", kind = "string", name = "title" },
    { default = "", kind = "string", name = "giver" },
    { default = "", kind = "string", name = "place" },
    { default = "", kind = "string", name = "zone" },
    { default = "", kind = "string", name = "text" },
    { default = "", kind = "string", name = "goal" },
    { default = false, kind = "boolean", name = "turnedIn" },
    { default = "", kind = "string", name = "ender" },
    { default = "", kind = "string", name = "endPlace" },
    { default = "", kind = "string", name = "endZone" },
    { default = "", kind = "string", name = "reward" },
    { default = 0, kind = "number", min = 0, name = "seen" },
    { default = false, kind = "boolean", name = "fresh" },
    { default = 0, kind = "number", min = 0, name = "askedAt" },
    { default = "", kind = "string", name = "askedKind" },
}

for i = 1, MaxObjectives do
    Fields[#Fields + 1] = { default = "", kind = "string", name = ("objective" .. i) }
    Fields[#Fields + 1] = { default = 0, kind = "number", min = 0, name = ("required" .. i), step = 1 }
    Fields[#Fields + 1] = { default = "", kind = "string", name = ("type" .. i) }
end
Fields[#Fields + 1] = { default = false, kind = "boolean", name = "unnamed" }

QuestBookModule = Addon:Module("QuestBook", {
    demand = true,
    OnDisable = function()
        Offer, TurnIn, LookAgain = nil, nil, false
        wipe(Unnamed)
    end,
    OnEnable = function(module)
        module:On("QUEST_DETAIL", OnOffer)
        module:On("QUEST_ACCEPTED", OnAccepted)
        module:On("QUEST_COMPLETE", OnTurnInPanel)
        module:On("QUEST_TURNED_IN", OnTurnedIn)
        module:On("QUEST_LOG_UPDATE", OnLogUpdate)
        local quests = module.Records.quests

        for _, key in ipairs(quests:Keys()) do
            if quests:Field(key, "unnamed") then
                Unnamed[key] = MaxNameReads
            end
        end
        RecordLog()
        LookAgain = true
    end,
    records = { { evict = "seen", fields = Fields, limit = Limit, name = "quests", scope = "character" } },
    toggle = false,
})

ns.QuestBook = { All = All, Asked = Asked, MaxObjectives = MaxObjectives, Order = Order }
