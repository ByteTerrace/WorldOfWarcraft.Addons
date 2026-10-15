local addonName, ns = ...

-- QuestBook: every quest the player has been shown, remembered per character so the Scholar's
-- challenge can ask about it (ScholarQuests.lua writes the riddles). A demand module: it records
-- while the challenge runs (Scholar uses it).
--
-- A quest is recorded when it's accepted, from what the client showed: the giver's offer
-- (QUEST_DETAIL: the title, the quest's text and goal, the giver's name), or the quest log alone
-- for a quest an area trigger accepted, whose text the player reads by opening the log. Its
-- objectives come from the log, and where it began from the subzone (with the zone around it,
-- never a wrong answer for where). Turning it in (QUEST_COMPLETE, then QUEST_TURNED_IN) adds who
-- took it, where, and the reward text. Each exposure, accepting and turning in, makes the quest
-- fresh: something new to ask about. Only these events read the quest APIs, out of combat as
-- quests are, and a secret answer is left out rather than stored.
--
--   ns.QuestBook.Order()      every key in the order to ask about them: fresh quests, newest
--                             first, then the rest for review, the one asked longest ago first
--   ns.QuestBook.Asked(key)   the quest has been asked about (now) since its last exposure
--   ns.QuestBook.All()        every record, as copies with their key, newest first
--
-- Records are QuestBook.quests, keyed by the quest ID as text, up to Limit of them (the oldest
-- seen go first). Texts keep their line breaks and lose the client's escape codes (a link keeps
-- its text, a texture goes); objectives lose their counts ("0/8 Wolf Pelt" is "Wolf Pelt", with
-- 8 its required count).

local Limit = 30
local MaxText = 1200    -- characters kept of a quest's text
local MaxLine = 120     -- characters kept of a title, name, place, goal or objective
local MaxObjectives = 3

local C_QuestLog, GetQuestID, GetQuestLogQuestText = C_QuestLog, GetQuestID, GetQuestLogQuestText
local GetObjectiveText, GetQuestText, GetRewardText, GetTitleText = GetObjectiveText, GetQuestText, GetRewardText, GetTitleText
local GetRealZoneText, GetServerTime, GetSubZoneText, UnitName = GetRealZoneText, GetServerTime, GetSubZoneText, UnitName
local issecretvalue, ipairs, tostring, type = issecretvalue, ipairs, tostring, type
local gsub, sub = string.gsub, string.sub

local Addon = ns.Addon

local QuestBookModule
local Offer  -- what the open offer showed: { id, title, text, goal, giver }
local TurnIn -- what the open reward panel showed: { id, title, ender, reward }

-- A text the client gave, plain: "" for a secret or a non-string; its escape codes undone (a
-- link keeps its text, a texture goes, |n is a line break), other control characters but line
-- breaks removed, trimmed, and cut to length characters.
local function Plain(text, length)
    if issecretvalue(text) or type(text) ~= "string" then
        return ""
    end
    text = gsub(gsub(gsub(text, "|T.-|t", ""), "|H.-|h(.-)|h", "%1"), "|n", "\n")
    text = gsub(gsub(gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""), "|", "")
    text = gsub(gsub(text, "\r", ""), "[%z\1-\9\11-\31]", "")
    text = gsub(gsub(text, "^%s+", ""), "%s+$", "")
    return sub(text, 1, length)
end

-- An objective's text without its count: "0/8 Wolf Pelt" and "Wolf Pelt: 0/8" are "Wolf Pelt".
local function Objective(text)
    text = gsub(gsub(Plain(text, MaxLine), "^%d+/%d+%s+", ""), "%s*:%s*%d+/%d+$", "")
    return text
end

-- A unit's name, or "" while it's secret or missing.
local function NameOf(unit)
    local name = UnitName(unit)
    if issecretvalue(name) or type(name) ~= "string" then
        return ""
    end
    return Plain(name, MaxLine)
end

-- Where you are: the subzone, else the zone; and the zone.
local function Place()
    local subZone, zone = Plain(GetSubZoneText(), MaxLine), Plain(GetRealZoneText(), MaxLine)
    return subZone ~= "" and subZone or zone, zone
end

-- The quest log's objectives for questID, as record fields (objective1, required1, ...).
local function ObjectiveFields(questID, values)
    local count = 0
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        local text, required = Objective(objective.text), objective.numRequired
        if count < MaxObjectives and text ~= "" and not issecretvalue(required) and type(required) == "number"
            and required >= 1 and required % 1 == 0 then
            count = count + 1
            values["objective" .. count], values["required" .. count] = text, required
        end
    end
    return values
end

local function OnOffer()
    local id = GetQuestID()
    if issecretvalue(id) or type(id) ~= "number" or id <= 0 then
        Offer = nil
        return
    end
    Offer = {
        id = id, title = Plain(GetTitleText(), MaxLine), text = Plain(GetQuestText(), MaxText),
        goal = Plain(GetObjectiveText(), MaxLine), giver = NameOf("questnpc"),
    }
end

local function OnAccepted(questID)
    if issecretvalue(questID) or type(questID) ~= "number" then
        return
    end
    local offer = Offer and Offer.id == questID and Offer or nil
    Offer = nil
    local place, zone = Place()
    local values = { place = place, zone = zone, seen = GetServerTime(), fresh = true, turnedIn = false }
    if offer then
        values.title, values.text, values.goal, values.giver = offer.title, offer.text, offer.goal, offer.giver
    else
        -- An area trigger's quest: no dialog showed it, so it's what the quest log shows.
        local index = C_QuestLog.GetLogIndexForQuestID(questID)
        local text, goal = "", ""
        if not issecretvalue(index) and type(index) == "number" then
            text, goal = GetQuestLogQuestText(index)
        end
        values.title = Plain(C_QuestLog.GetTitleForQuestID(questID), MaxLine)
        values.text, values.goal = Plain(text, MaxText), Plain(goal, MaxLine)
    end
    if values.title == "" then
        return -- nothing to name it by
    end
    QuestBookModule.Records.quests:Set(tostring(questID), ObjectiveFields(questID, values))
end

local function OnTurnInPanel()
    local id = GetQuestID()
    if issecretvalue(id) or type(id) ~= "number" or id <= 0 then
        TurnIn = nil
        return
    end
    TurnIn = { id = id, title = Plain(GetTitleText(), MaxLine), ender = NameOf("questnpc"),
        reward = Plain(GetRewardText(), MaxText) }
end

local function OnTurnedIn(questID)
    if issecretvalue(questID) or type(questID) ~= "number" then
        return
    end
    local turnIn = TurnIn and TurnIn.id == questID and TurnIn or nil
    TurnIn = nil
    local quests, key = QuestBookModule.Records.quests, tostring(questID)
    local endPlace, endZone = Place()
    local values = { turnedIn = true, endPlace = endPlace, endZone = endZone, seen = GetServerTime(), fresh = true }
    if turnIn then
        values.ender, values.reward = turnIn.ender, turnIn.reward
    end
    if not quests:Has(key) then
        -- Accepted before the book was open: the reward panel named it.
        values.title = turnIn and turnIn.title or ""
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
            return byA < byB
        end
        return a < b
    end)
    return keys
end

--- Marks a quest asked about now: it's fresh again at its next exposure, and waits its turn for
--- review.
---@param key string
local function Asked(key)
    local quests = QuestBookModule.Records.quests
    if quests:Has(key) then
        quests:Set(key, { fresh = false, askedAt = GetServerTime() })
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
            return a.seen > b.seen
        end
        return a.key < b.key
    end)
    return list
end

local Fields = {
    { name = "title", kind = "string", default = "" },
    { name = "giver", kind = "string", default = "" },
    { name = "place", kind = "string", default = "" },
    { name = "zone", kind = "string", default = "" },
    { name = "text", kind = "string", default = "" },
    { name = "goal", kind = "string", default = "" },
    { name = "turnedIn", kind = "boolean", default = false },
    { name = "ender", kind = "string", default = "" },
    { name = "endPlace", kind = "string", default = "" },
    { name = "endZone", kind = "string", default = "" },
    { name = "reward", kind = "string", default = "" },
    { name = "seen", kind = "number", default = 0, min = 0 },
    { name = "fresh", kind = "boolean", default = false },
    { name = "askedAt", kind = "number", default = 0, min = 0 },
}
for i = 1, MaxObjectives do
    Fields[#Fields + 1] = { name = "objective" .. i, kind = "string", default = "" }
    Fields[#Fields + 1] = { name = "required" .. i, kind = "number", default = 0, min = 0, step = 1 }
end

QuestBookModule = Addon:Module("QuestBook", {
    toggle = false,
    demand = true,
    records = { { name = "quests", fields = Fields, limit = Limit, evict = "seen", scope = "character" } },
    OnEnable = function(module)
        module:On("QUEST_DETAIL", OnOffer)
        module:On("QUEST_ACCEPTED", OnAccepted)
        module:On("QUEST_COMPLETE", OnTurnInPanel)
        module:On("QUEST_TURNED_IN", OnTurnedIn)
    end,
    OnDisable = function()
        Offer, TurnIn = nil, nil
    end,
})

ns.QuestBook = { Order = Order, Asked = Asked, All = All, MaxObjectives = MaxObjectives }
