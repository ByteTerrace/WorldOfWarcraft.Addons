-- Quests in the fake client: the quest log, the quest giver's dialog, and the other NPC windows (gossip, and those
-- Blizzard's interaction manager opens). See wow.lua for the rest.
--
-- State: h.questLog (the quests in the log, in order: { id, title, text, goal, objectives, header, level }),
-- h.objectiveHave ([questID] = { [objective index] = how many are done }, from h:ProgressObjective), h.questTitles
-- ([questID] = title, for every quest the client has seen), and h.questDialog (nil, or { panel = "detail" | "progress"
-- | "reward", quest, progress, reward }) with the giver as the "questnpc" and "npc" units while it's open. A quest spec
-- is { id, title, text (the description), goal (the objective summary), objectives = { { text (what the objective
-- names: an item, a creature, a task), required, have (how many are done, 0 unless given), type ("item" unless given),
-- uncached } }, header (the log's zone header), level }. Missing fields get stand-ins. h.gossip is the open gossip
-- window's NPC (or nil), and h.interactions the open interaction manager windows ([Enum.PlayerInteractionType value] =
-- true).
--
--   h:OfferQuest(spec, giver)     the giver's offer panel: QUEST_DETAIL(0)
--   h:AcceptQuest()               accepts the offer: QUEST_ACCEPTED(id), QUEST_LOG_UPDATE, QUEST_FINISHED
--   h:AutoAcceptQuest(spec)       an area trigger's quest, straight into the log: no dialog, no text shown
--   h:OpenProgress(id, ender, text)  the progress panel of a quest in the log, before its
--                                 objectives are done ("Have you got them?"): QUEST_PROGRESS
--   h:OpenTurnIn(id, ender, reward)  the reward panel of a quest in the log: QUEST_COMPLETE
--   h:CloseQuestDialog()          walks away from the open dialog: QUEST_FINISHED
--   h:CompleteQuest(xp, money)    selects Complete Quest: QUEST_TURNED_IN(id, xp, money),
--                                 QUEST_REMOVED(id, false), QUEST_LOG_UPDATE, QUEST_FINISHED
--   h:LoadQuestNames()            the client has loaded the names uncached objectives lacked:
--                                 QUEST_LOG_UPDATE
--   h:ProgressObjective(id, i, have)  objective i of a quest in the log now has have done:
--                                 QUEST_WATCH_UPDATE(id), QUEST_LOG_UPDATE
--   h:OpenGossip(npc) / h:CloseGossip()   an NPC's gossip window: GOSSIP_SHOW(nil), GOSSIP_CLOSED(false)
--   h:OpenInteraction(name) / h:CloseInteraction(name)   a window the interaction manager opens, by
--                                 its Enum.PlayerInteractionType name ("Merchant", "MailInfo", ...):
--                                 PLAYER_INTERACTION_MANAGER_FRAME_SHOW / _HIDE(type)
--
-- Modeling decisions ([D] documented or seen in Blizzard's Forever UI source, [E] observed in the client, [G] a guess
-- where neither says):
--   Dialogs     [D] Forever loads the Mainline QuestFrame (Blizzard_UIPanels_Game's TOC, [Family]):
--               QUEST_DETAIL shows QuestFrameDetailPanel, which reads GetTitleText, GetQuestText,
--               and GetObjectiveText; QUEST_PROGRESS shows QuestFrameProgressPanel
--               (GetProgressText); QUEST_COMPLETE shows QuestFrameRewardPanel (GetRewardText);
--               QUEST_FINISHED hides the frame; the frame's title is UnitName("questnpc"). An area
--               trigger's auto-accepted quest closes the dialog without showing it. [E] Those texts
--               and GetQuestID's number are plain out of combat (quest.offer, quest.turnIn,
--               quest.*Identity), and so are the questnpc and npc names. [G] The questnpc unit's GUID is a
--               Creature's unless a test gives the giver one: an item's "Item-...", an object's
--               "GameObject-..." (quest.giverKind and quest.enderKind ask the client). [G] Outside a dialog,
--               GetQuestID answers 0 and the texts "". [G] The accept and turn-in event orders.
--   Log         [E] GetNumQuestLogEntries answers the shown entries (zone headers included) and the
--               quests; GetInfo answers the questLog.entry fields; GetQuestObjectives answers
--               { text, type, finished, numFulfilled, numRequired }. The docs' Nilable
--               objectiveType comes with some objectives and not others (questLog.objectives saw
--               both, item objectives included); [G] which ones isn't known, so the harness sends
--               none, and nothing here reads it. [E] GetQuestLogQuestText(index) answers the
--               description and the objective summary, and GetTitleForQuestID a title
--               (questLog.text). [G] One header per header name, in first-seen order; a header's
--               entry carries the same fields with questID 0. [G] An objective's text puts its
--               count first ("0/8 Wolf Pelt"), as the Mainline tracker shows it; probe
--               questLog.countForm records which forms the client uses (leading, and none).
--               [G] The client writes an objective's text with its locale's GlobalStrings, as the
--               harness does with the env's: QUEST_MONSTERS_KILLED for a monster, QUEST_OBJECTS_FOUND
--               for an object, QUEST_ITEMS_NEEDED for the rest (the enUS forms, world.lua, put the
--               count first); the "none" form, a text without its count, isn't modeled. [E] An
--               objective whose item or creature the client hadn't loaded yet comes without its
--               name: "0/5 " for "0/5 Duskbat Pelt", "0/10  slain" for "0/10 Scarlet Warrior
--               slain" (seen in a player's saved quest book); an uncached objective reads so until
--               h:LoadQuestNames. [G] A turned-in quest's title stays known to GetTitleForQuestID (questLog.titleAfterTurnIn asks the client).
--   Progress    [D] An objective's numFulfilled is how many are done, and finished whether that
--               reaches numRequired; its text shows the new count. Blizzard's Forever objective
--               tracker redraws on QUEST_LOG_UPDATE (Blizzard_QuestObjectiveTracker.lua).
--               [G] Progress fires QUEST_WATCH_UPDATE(questID), then QUEST_LOG_UPDATE, and no
--               UNIT_QUEST_LOG_CHANGED. [E] ReadyForTurnIn is true when every objective is finished
--               and false while one isn't; a quest without objectives can be either (questLog.readyForTurnIn).
--               [G] The harness answers true for one, and nil for a quest not in the log.
--   Windows     [D] Blizzard's Forever UI shows the gossip frame on GOSSIP_SHOW(textureKit) and
--               hides it on GOSSIP_CLOSED(interactionIsContinuing) (CustomGossipFrameBase.lua).
--               The merchant, mailbox, bank, auction house, trainer, and other windows register
--               with PlayerInteractionFrameManager, which shows each on
--               PLAYER_INTERACTION_MANAGER_FRAME_SHOW(type) and hides it on _HIDE(type).
--               [G] The flight master's map (TaxiNode) is shown the same way: no Forever UI file
--               handles TAXIMAP_OPENED, while TaxiFrame and FlightMapFrame hide on TAXIMAP_CLOSED,
--               so closing it fires _HIDE(TaxiNode) and then TAXIMAP_CLOSED. The windows' frames
--               and contents aren't modeled.

local QuestInfoFields = {
    difficultyLevel = 0, frequency = 0, hasLocalPOI = false, isAbandonOnDisable = false, isAutoComplete = false,
    isBounty = false, isCollapsed = false, isHidden = false, isInternalOnly = false, isOnMap = true, isScaling = false,
    isStory = false, isTask = false, overridesSortOrder = false, questClassification = 2, readyForTranslation = true,
    sortAsNormalQuest = false, startEvent = false, suggestedGroup = 0, useMinimalHeader = false,
}

local QuestSerial = 0

-- The log's entries as the client lists them: each header, then its quests.
local function Entries(h)
    local entries = {}
    local headers = {}
    local order = {}

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

-- A quest spec with its stand-ins filled in, as a fresh table.
local function FillQuest(spec)
    QuestSerial = (QuestSerial + 1)

    local quest = {
        goal = (spec.goal or "Do what is asked."), header = (spec.header or "Elwynn Forest"),
        id = (spec.id or (1000 + QuestSerial)), level = (spec.level or 5), objectives = {},
        text = (spec.text or "Help us, hero."), title = (spec.title or ("Quest " .. QuestSerial)),
    }

    for i, objective in ipairs(spec.objectives or {}) do
        quest.objectives[i] = { required = (objective.required or 1), text = objective.text,
            type = (objective.type or "item"), uncached = (objective.uncached == true) }
    end

    return quest
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

local function LogQuest(h, questID)
    for _, quest in ipairs(h.questLog) do
        if quest.id == questID then
            return quest
        end
    end
end

function Harness:InitQuests()
    self.questLog = {}
    self.objectiveHave = {}
    self.questTitles = {}
    self.questDialog = nil
    self.gossip = nil
    self.interactions = {}
end

-- The GlobalString an objective's text is written with, by its type (see the header).
local ObjectiveFormats = { monster = "QUEST_MONSTERS_KILLED", object = "QUEST_OBJECTS_FOUND" }

local function AddToLog(h, quest)
    assert(not LogQuest(h, quest.id), "the quest is already in the log: " .. quest.id)
    h.questLog[#h.questLog + 1] = quest
    h.questTitles[quest.id] = quest.title
    h:Fire("QUEST_ACCEPTED", quest.id)
    h:Fire("QUEST_LOG_UPDATE")
end

-- The format string with its positional conversions ("%2$d/%3$d %1$s") filled from the arguments.
local function FormatPositional(format, ...)
    local args = { ... }
    local position = 0

    return (format:gsub("%%(%d*)%$?([sd])", function(index)
        position = (position + 1)

        return tostring(args[tonumber(index) or position])
    end))
end

-- How many of objective i of quest are done: h:ProgressObjective's count, else the spec's have, else 0.
local function Have(h, quest, i)
    local progress = h.objectiveHave[quest.id]

    return ((progress and progress[i]) or quest.objectives[i].have or 0)
end

-- An Enum.PlayerInteractionType value by name.
local function InteractionType(name)
    local value = __snapshot.enums.PlayerInteractionType[name]

    assert(value, "unknown Enum.PlayerInteractionType " .. tostring(name))

    return value
end

local function Objectives(h, quest)
    local list = {}

    for i, objective in ipairs(quest.objectives) do
        local format = rawget(h.env, ObjectiveFormats[objective.type] or "QUEST_ITEMS_NEEDED")
        -- An uncached objective's name is empty.
        local name = ((objective.uncached and "") or objective.text)

        local have = Have(h, quest, i)

        list[i] = {
            finished = (have >= objective.required), numFulfilled = have, numRequired = objective.required,
            text = FormatPositional(format, name, have, objective.required), type = objective.type,
        }
    end

    return list
end

local function SetPanel(h, panel)
    local env = h.env

    h:SetWidgetShown(rawget(env, "QuestFrame"), panel ~= nil)
    h:SetWidgetShown(rawget(env, "QuestFrameDetailPanel"), panel == "detail")
    h:SetWidgetShown(rawget(env, "QuestFrameProgressPanel"), panel == "progress")
    h:SetWidgetShown(rawget(env, "QuestFrameRewardPanel"), panel == "reward")
end

local function CloseDialog(h)
    h.questDialog = nil
    h.units.questnpc, h.units.npc = nil, nil
    SetPanel(h, nil)
    h:Fire("QUEST_FINISHED")
end

local function OpenDialog(h, dialog, giver)
    h.questDialog = dialog
    local unit = Harness.FillUnit(((type(giver) == "table") and giver) or { level = 30, name = (giver or "Marshal Dughan") })

    h.units.questnpc, h.units.npc = unit, unit
    SetPanel(h, dialog.panel)
end

--- Accepts the open offer: the quest joins the log and the dialog closes.
function Harness:AcceptQuest()
    local dialog = self.questDialog

    assert(dialog and (dialog.panel == "detail"), "AcceptQuest: no quest offer is open")
    AddToLog(self, dialog.quest)
    CloseDialog(self)
end

--- An area trigger's quest: into the log with no dialog, so its text is only in the quest log.
function Harness:AutoAcceptQuest(spec)
    local quest = FillQuest(spec)

    AddToLog(self, quest)

    return quest.id
end

--- Closes the open gossip window.
function Harness:CloseGossip()
    assert(self.gossip, "CloseGossip: no gossip window is open")
    self.gossip = nil
    self.units.npc = nil
    self:Fire("GOSSIP_CLOSED", false)
end

--- Closes a window the interaction manager showed. The flight master's map also fires TAXIMAP_CLOSED.
function Harness:CloseInteraction(name)
    local value = InteractionType(name)

    assert(self.interactions[value], "CloseInteraction: " .. name .. " isn't open")
    self.interactions[value] = nil
    self:Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", value)

    if name == "TaxiNode" then
        self:Fire("TAXIMAP_CLOSED")
    end
end

--- Opens the reward panel of a quest in the log; ender is a unit table or a name. Walks away from the open quest
--- dialog.
function Harness:CloseQuestDialog()
    assert(self.questDialog, "CloseQuestDialog: no quest dialog is open")
    CloseDialog(self)
end

--- Completes the quest whose reward panel is open: it leaves the log and the dialog closes.
function Harness:CompleteQuest(xp, money)
    local dialog = self.questDialog

    assert(dialog and (dialog.panel == "reward"), "CompleteQuest: no reward panel is open")
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

-- The client has loaded the item and creature names the log's objectives lacked: they read whole, and QUEST_LOG_UPDATE
-- fires.
function Harness:LoadQuestNames()
    for _, quest in ipairs(self.questLog) do
        for _, objective in ipairs(quest.objectives) do
            objective.uncached = false
        end
    end

    self:Fire("QUEST_LOG_UPDATE")
end

--- Opens a quest giver's offer panel for spec; giver is a unit table or a name.
function Harness:OfferQuest(spec, giver)
    assert(not self.questDialog, "OfferQuest: a quest dialog is already open")
    OpenDialog(self, { panel = "detail", quest = FillQuest(spec) }, giver)
    self:Fire("QUEST_DETAIL", 0)
end

--- Opens an NPC's gossip window; npc is a unit table or a name (the "npc" unit while it's open).
function Harness:OpenGossip(npc)
    assert(not self.gossip, "OpenGossip: a gossip window is already open")
    self.gossip = Harness.FillUnit(((type(npc) == "table") and npc) or { level = 30, name = (npc or "Innkeeper Farley") })
    self.units.npc = self.gossip
    self:Fire("GOSSIP_SHOW", nil)
end

--- Opens a window the interaction manager shows, by its Enum.PlayerInteractionType name.
function Harness:OpenInteraction(name)
    local value = InteractionType(name)

    assert(not self.interactions[value], "OpenInteraction: " .. name .. " is already open")
    self.interactions[value] = true
    self:Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", value)
end

--- Opens the progress panel of a quest in the log, as its ender asks for what it needs.
function Harness:OpenProgress(questID, ender, text)
    assert(not self.questDialog, "OpenProgress: a quest dialog is already open")
    local quest = assert(LogQuest(self, questID), "OpenProgress: quest " .. tostring(questID) .. " isn't in the log")

    OpenDialog(self, { panel = "progress", progress = (text or "Have you got them?"), quest = quest }, ender)
    self:Fire("QUEST_PROGRESS")
end

function Harness:OpenTurnIn(questID, ender, reward)
    assert(not self.questDialog, "OpenTurnIn: a quest dialog is already open")
    local quest = assert(LogQuest(self, questID), "OpenTurnIn: quest " .. tostring(questID) .. " isn't in the log")

    OpenDialog(self, { panel = "reward", quest = quest, reward = (reward or "Well done.") }, ender)
    self:Fire("QUEST_COMPLETE")
end

--- Objective index of the quest in the log with questID now has have done, and the client says so.
function Harness:ProgressObjective(questID, index, have)
    local quest = LogQuest(self, questID)

    assert(quest and quest.objectives[index], "ProgressObjective: no such objective in the log")
    self.objectiveHave[questID] = (self.objectiveHave[questID] or {})
    self.objectiveHave[questID][index] = have
    self:Fire("QUEST_WATCH_UPDATE", questID)
    self:Fire("QUEST_LOG_UPDATE")
end

-- The quest fakes, merged into the env (env.lua) before it wraps them.
function Harness:QuestFakes(uiParent)
    local h = self

    local function Dialog(panel)
        local dialog = h.questDialog

        return ((dialog and (not panel or (dialog.panel == panel)) and dialog) or nil)
    end

    local fakes = {
        C_QuestLog = {
            GetInfo = function(index)
                local entry = Entries(h)[index]

                return ((entry and Info(entry, index)) or nil)
            end,
            GetLogIndexForQuestID = function(questID)
                for index, entry in ipairs(Entries(h)) do
                    if entry.quest and (entry.quest.id == questID) then
                        return index
                    end
                end

                return nil
            end,
            GetNumQuestLogEntries = function()
                return #Entries(h), #h.questLog
            end,
            GetQuestObjectives = function(questID)
                local quest = LogQuest(h, questID)

                return ((quest and Objectives(h, quest)) or {})
            end,
            GetSelectedQuest = function()
                return 0
            end,
            GetTitleForQuestID = function(questID)
                return h.questTitles[questID]
            end,
            ReadyForTurnIn = function(questID)
                local quest = LogQuest(h, questID)

                if not quest then
                    return nil
                end

                for i, objective in ipairs(quest.objectives) do
                    if Have(h, quest, i) < objective.required then
                        return false
                    end
                end

                return true
            end,
        },
        GetObjectiveText = function()
            local dialog = Dialog("detail")

            return ((dialog and dialog.quest.goal) or "")
        end,
        GetProgressText = function()
            local dialog = Dialog("progress")

            return ((dialog and dialog.progress) or "")
        end,
        GetQuestID = function()
            local dialog = Dialog()

            return ((dialog and dialog.quest.id) or 0)
        end,
        GetQuestLogQuestText = function(index)
            local entry = Entries(h)[index]

            if not (entry and entry.quest) then
                return "", ""
            end

            return entry.quest.text, entry.quest.goal
        end,
        GetQuestText = function()
            local dialog = Dialog("detail")

            return ((dialog and dialog.quest.text) or "")
        end,
        GetRewardText = function()
            local dialog = Dialog("reward")

            return ((dialog and dialog.reward) or "")
        end,
        GetTitleText = function()
            local dialog = Dialog()

            return ((dialog and dialog.quest.title) or "")
        end,
    }

    local frame = h:CreateWidget("Frame", "QuestFrame", uiParent)

    Harness.State(frame).shown = false
    fakes.QuestFrame = frame

    for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do
        local panel = h:CreateWidget("Frame", name, frame)

        Harness.State(panel).shown = false
        fakes[name] = panel
    end

    return fakes
end
