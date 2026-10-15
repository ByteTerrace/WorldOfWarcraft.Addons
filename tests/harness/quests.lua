-- Quests in the fake client: the quest log and the quest giver's dialog (see wow.lua for the rest).
--
-- State: h.questLog (the quests in the log, in order: { id, title, text, goal, objectives, header,
-- level }), h.questTitles ([questID] = title, for every quest the client has seen) and h.questDialog
-- (nil, or { panel = "detail" | "reward", quest, reward }) with the giver as the "questnpc" and
-- "npc" units while it's open. A quest spec is { id, title, text (the description), goal (the
-- objective summary), objectives = { { text, required, type ("item" unless given), uncached } },
-- header (the log's zone header), level }; missing fields get stand-ins.
--
--   h:OfferQuest(spec, giver)     the giver's offer panel: QUEST_DETAIL(0)
--   h:AcceptQuest()               accepts the offer: QUEST_ACCEPTED(id), QUEST_LOG_UPDATE, QUEST_FINISHED
--   h:AutoAcceptQuest(spec)       an area trigger's quest, straight into the log: no dialog, no text shown
--   h:OpenTurnIn(id, ender, reward)  the reward panel of a quest in the log: QUEST_COMPLETE
--   h:CompleteQuest(xp, money)    clicks Complete Quest: QUEST_TURNED_IN(id, xp, money),
--                                 QUEST_REMOVED(id, false), QUEST_LOG_UPDATE, QUEST_FINISHED
--   h:LoadQuestNames()            the client has loaded the names uncached objectives lacked:
--                                 QUEST_LOG_UPDATE
--
-- Modeling decisions ([D] documented or seen in Blizzard's Forever UI source, [P] probed in game,
-- [G] a guess where neither says):
--   Dialogs     [D] Forever loads the Mainline QuestFrame (Blizzard_UIPanels_Game's TOC, [Family]):
--               QUEST_DETAIL shows QuestFrameDetailPanel, which reads GetTitleText, GetQuestText
--               and GetObjectiveText; QUEST_COMPLETE shows QuestFrameRewardPanel (GetRewardText);
--               QUEST_FINISHED hides the frame; the frame's title is UnitName("questnpc"). An area
--               trigger's auto-accepted quest closes the dialog without showing it. [P] Those texts
--               and GetQuestID's number are plain out of combat (quest.offer, quest.turnIn,
--               quest.*Identity), and so are the questnpc and npc names. [G] Outside a dialog,
--               GetQuestID answers 0 and the texts "". [G] The accept and turn-in event orders.
--   Log         [P] GetNumQuestLogEntries answers the shown entries (zone headers included) and the
--               quests; GetInfo answers the questLog.entry fields; GetQuestObjectives answers
--               { text, type, finished, numFulfilled, numRequired }. The docs' Nilable
--               objectiveType comes with some objectives and not others (questLog.objectives saw
--               both, item objectives included); [G] which ones isn't known, so the harness sends
--               none, and nothing here reads it; GetQuestLogQuestText(index)
--               answers the description and the objective summary, and GetTitleForQuestID a title
--               (questLog.text). [G] One header per header name, in first-seen order; a header's
--               entry carries the same fields with questID 0. [G] An objective's text puts its
--               count first ("0/8 Wolf Pelt"), as the Mainline tracker shows it; probe
--               questLog.countForm records which form the client uses. [E] An objective whose
--               item or creature the client hadn't loaded yet comes without its name: "0/5 " for
--               "0/5 Duskbat Pelt", "0/10  slain" for "0/10 Scarlet Warrior slain" (seen in a
--               player's saved quest book); an uncached objective reads so until h:LoadQuestNames. [G] A turned-in
--               quest's title stays known to GetTitleForQuestID.

local QuestInfoFields = {
    difficultyLevel = 0, frequency = 0, hasLocalPOI = false, isAbandonOnDisable = false, isAutoComplete = false,
    isBounty = false, isCollapsed = false, isHidden = false, isInternalOnly = false, isOnMap = true, isScaling = false,
    isStory = false, isTask = false, overridesSortOrder = false, questClassification = 2, readyForTranslation = true,
    sortAsNormalQuest = false, startEvent = false, suggestedGroup = 0, useMinimalHeader = false,
}

local QuestSerial = 0

function Harness:InitQuests()
    self.questLog = {}
    self.questTitles = {}
    self.questDialog = nil
end

-- A quest spec with its stand-ins filled in, as a fresh table.
local function FillQuest(spec)
    QuestSerial = QuestSerial + 1
    local quest = {
        id = spec.id or 1000 + QuestSerial, title = spec.title or ("Quest " .. QuestSerial),
        text = spec.text or "Help us, hero.", goal = spec.goal or "Do what is asked.",
        header = spec.header or "Elwynn Forest", level = spec.level or 5, objectives = {},
    }
    for i, objective in ipairs(spec.objectives or {}) do
        quest.objectives[i] = { text = objective.text, required = objective.required or 1, type = objective.type or "item",
            uncached = objective.uncached == true }
    end
    return quest
end

-- The log's entries as the client lists them: each header, then its quests.
local function Entries(h)
    local entries, headers, order = {}, {}, {}
    for _, quest in ipairs(h.questLog) do
        if not headers[quest.header] then
            headers[quest.header] = {}
            order[#order + 1] = quest.header
        end
        local list = headers[quest.header]
        list[#list + 1] = quest
    end
    for _, header in ipairs(order) do
        entries[#entries + 1] = { header = header }
        for _, quest in ipairs(headers[header]) do
            entries[#entries + 1] = { quest = quest }
        end
    end
    return entries
end

local function LogQuest(h, questID)
    for _, quest in ipairs(h.questLog) do
        if quest.id == questID then
            return quest
        end
    end
end

local function Info(entry, index)
    local info = {}
    for key, value in pairs(QuestInfoFields) do
        info[key] = value
    end
    info.questLogIndex = index
    if entry.header then
        info.isHeader, info.title, info.questID, info.level = true, entry.header, 0, 0
    else
        info.isHeader, info.title, info.questID, info.level = false, entry.quest.title, entry.quest.id, entry.quest.level
    end
    return info
end

local function Objectives(quest)
    local list = {}
    for i, objective in ipairs(quest.objectives) do
        local text = objective.text
        if objective.uncached then
            text = text:sub(#text:gsub("%s+slain$", "") + 1) -- the name goes: "", or " slain"
        end
        list[i] = {
            text = ("0/%d %s"):format(objective.required, text), type = objective.type,
            finished = false, numFulfilled = 0, numRequired = objective.required,
        }
    end
    return list
end

local function SetPanel(h, panel)
    local env = h.env
    h:SetWidgetShown(rawget(env, "QuestFrame"), panel ~= nil)
    h:SetWidgetShown(rawget(env, "QuestFrameDetailPanel"), panel == "detail")
    h:SetWidgetShown(rawget(env, "QuestFrameRewardPanel"), panel == "reward")
end

local function OpenDialog(h, dialog, giver)
    h.questDialog = dialog
    local unit = Harness.FillUnit(type(giver) == "table" and giver or { name = giver or "Marshal Dughan", level = 30 })
    h.units.questnpc, h.units.npc = unit, unit
    SetPanel(h, dialog.panel)
end

local function CloseDialog(h)
    h.questDialog = nil
    h.units.questnpc, h.units.npc = nil, nil
    SetPanel(h, nil)
    h:Fire("QUEST_FINISHED")
end

--- Opens a quest giver's offer panel for spec; giver is a unit table or a name.
function Harness:OfferQuest(spec, giver)
    assert(not self.questDialog, "OfferQuest: a quest dialog is already open")
    OpenDialog(self, { panel = "detail", quest = FillQuest(spec) }, giver)
    self:Fire("QUEST_DETAIL", 0)
end

local function AddToLog(h, quest)
    assert(not LogQuest(h, quest.id), "the quest is already in the log: " .. quest.id)
    h.questLog[#h.questLog + 1] = quest
    h.questTitles[quest.id] = quest.title
    h:Fire("QUEST_ACCEPTED", quest.id)
    h:Fire("QUEST_LOG_UPDATE")
end

--- Accepts the open offer: the quest joins the log and the dialog closes.
function Harness:AcceptQuest()
    local dialog = self.questDialog
    assert(dialog and dialog.panel == "detail", "AcceptQuest: no quest offer is open")
    AddToLog(self, dialog.quest)
    CloseDialog(self)
end

--- An area trigger's quest: into the log with no dialog, so its text is only in the quest log.
function Harness:AutoAcceptQuest(spec)
    local quest = FillQuest(spec)
    AddToLog(self, quest)
    return quest.id
end

--- Opens the reward panel of a quest in the log; ender is a unit table or a name.
function Harness:OpenTurnIn(questID, ender, reward)
    assert(not self.questDialog, "OpenTurnIn: a quest dialog is already open")
    local quest = assert(LogQuest(self, questID), "OpenTurnIn: quest " .. tostring(questID) .. " isn't in the log")
    OpenDialog(self, { panel = "reward", quest = quest, reward = reward or "Well done." }, ender)
    self:Fire("QUEST_COMPLETE")
end

--- Completes the quest whose reward panel is open: it leaves the log and the dialog closes.
function Harness:CompleteQuest(xp, money)
    local dialog = self.questDialog
    assert(dialog and dialog.panel == "reward", "CompleteQuest: no reward panel is open")
    local id = dialog.quest.id
    for i, quest in ipairs(self.questLog) do
        if quest.id == id then
            table.remove(self.questLog, i)
            break
        end
    end
    self:Fire("QUEST_TURNED_IN", id, xp or 100, money or 0)
    self:Fire("QUEST_REMOVED", id, false)
    self:Fire("QUEST_LOG_UPDATE")
    CloseDialog(self)
end

-- The quest fakes, merged into the env (env.lua) before it wraps them.
-- The client has loaded the item and creature names the log's objectives lacked: they read whole,
-- and QUEST_LOG_UPDATE fires.
function Harness:LoadQuestNames()
    for _, quest in ipairs(self.questLog) do
        for _, objective in ipairs(quest.objectives) do
            objective.uncached = false
        end
    end
    self:Fire("QUEST_LOG_UPDATE")
end

function Harness:QuestFakes(uiParent)
    local h = self
    local function Dialog(panel)
        local dialog = h.questDialog
        return dialog and (not panel or dialog.panel == panel) and dialog or nil
    end
    local fakes = {
        GetQuestID = function()
            local dialog = Dialog()
            return dialog and dialog.quest.id or 0
        end,
        GetTitleText = function()
            local dialog = Dialog()
            return dialog and dialog.quest.title or ""
        end,
        GetQuestText = function()
            local dialog = Dialog("detail")
            return dialog and dialog.quest.text or ""
        end,
        GetObjectiveText = function()
            local dialog = Dialog("detail")
            return dialog and dialog.quest.goal or ""
        end,
        GetRewardText = function()
            local dialog = Dialog("reward")
            return dialog and dialog.reward or ""
        end,
        GetQuestLogQuestText = function(index)
            local entry = Entries(h)[index]
            if not (entry and entry.quest) then
                return "", ""
            end
            return entry.quest.text, entry.quest.goal
        end,
        C_QuestLog = {
            GetNumQuestLogEntries = function()
                return #Entries(h), #h.questLog
            end,
            GetInfo = function(index)
                local entry = Entries(h)[index]
                return entry and Info(entry, index) or nil
            end,
            GetQuestObjectives = function(questID)
                local quest = LogQuest(h, questID)
                return quest and Objectives(quest) or {}
            end,
            GetTitleForQuestID = function(questID)
                return h.questTitles[questID]
            end,
            GetLogIndexForQuestID = function(questID)
                for index, entry in ipairs(Entries(h)) do
                    if entry.quest and entry.quest.id == questID then
                        return index
                    end
                end
                return nil
            end,
            GetSelectedQuest = function()
                return 0
            end,
        },
    }
    local frame = h:CreateWidget("Frame", "QuestFrame", uiParent)
    Harness.State(frame).shown = false
    fakes.QuestFrame = frame
    for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameRewardPanel" }) do
        local panel = h:CreateWidget("Frame", name, frame)
        Harness.State(panel).shown = false
        fakes[name] = panel
    end
    return fakes
end
