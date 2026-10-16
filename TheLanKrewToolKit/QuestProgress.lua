local addonName, ns = ...

-- QuestProgress: what the player's quests gain, read from the quest log, for the features that cheer it on. Two
-- modules:
--
--   QuestProgress  a demand module, run while a feature below uses it. It reads the log's objectives
--                  on QUEST_LOG_UPDATE, once for a burst of them (ReadDelay), as Blizzard's objective
--                  tracker redraws, and compares them with its last reading. A count that rises is
--                  progress, and a quest that becomes ready to turn in (C_QuestLog.ReadyForTurnIn) is
--                  ready. It never reads the log in combat: the fight's updates wait for it to end, so
--                  one reading covers the whole fight. A quest it hasn't read before (when it starts,
--                  after a /reload, or just accepted) counts from where it is and is never announced.
--   QuestCount     the Owl says a young scholar's progress aloud: "Tough Wolf Meat: 3 of 8. 5 more
--                  to go!", with "That fight got you 2 more!" first after a fight, and "Wolves Across
--                  the Border is ready to turn in!". It's part of the Scholar's challenge (it runs
--                  while the challenge is on, behind the parent's lock), follows Read riddles aloud
--                  (ns.ScholarVoice), and keeps quiet while a riddle is on screen.
--
-- The QuestReady sound (Sounds.lua) and the light bar's gold flash and the rumble (Controller.lua) follow
-- QuestProgress.ready. Its rows are runtime: gained and ready count the steps gained and the quests made ready; have,
-- need, objective, and title describe the biggest gain of the last reading that gained anything, and fought what the
-- fight that just ended gained (0 for a reading outside a fight); readyTitle names the last quest made ready.

-- Seconds a burst of QUEST_LOG_UPDATEs gathers before one reading.
local ReadDelay = 0.2

local C_QuestLog = C_QuestLog
local concat = table.concat
local ipairs = ipairs
local issecretvalue = issecretvalue
local pairs = pairs
local type = type
local wipe = wipe

local ObjectiveName = ns.QuestBook.ObjectiveName

-- The last reading, as [questID] = { counts = { [objective index] = how many are done }, ready = boolean }.
local Known = {}

-- A plain number, else nil.
local function Count(value)
    if issecretvalue(value) or (type(value) ~= "number") then
        return nil
    end

    return value
end

-- What the Owl says about the last reading's biggest gain: the count and how many are left, or that it's done, after
-- what a fight gained.
local function ProgressText(state)
    local name = state:Get("QuestProgress.objective")
    local have = state:Get("QuestProgress.have")
    local need = state:Get("QuestProgress.need")
    local fought = state:Get("QuestProgress.fought")
    local text = nil

    if name == "" then
        name = state:Get("QuestProgress.title")
    end

    if have < need then
        text = ("%s: %d of %d. %d more to go!"):format(name, have, need, need - have)
    elseif need == 1 then
        text = (name .. ": done!")
    else
        text = ("%s: all %d. Done!"):format(name, need)
    end

    if fought > 0 then
        text = (("That fight got you %d more! "):format(fought) .. text)
    end

    return text
end

-- A plain string, else "".
local function Text(value)
    if issecretvalue(value) or (type(value) ~= "string") then
        return ""
    end

    return value
end

-- Reads the log and compares it with the last reading. With announce, progress and ready quests are written to the rows
-- (fought says the reading follows a fight); without, the reading only becomes where counting starts.
local function Read(module, announce, fought)
    local seen = {}
    local readied = {}
    local gained = 0
    local best = nil

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local questID = (info and not info.isHeader and Count(info.questID))

        if questID then
            local objectives = (C_QuestLog.GetQuestObjectives(questID) or {})
            local ready = C_QuestLog.ReadyForTurnIn(questID)
            local known = Known[questID]
            local counts = {}

            ready = (not issecretvalue(ready) and (ready == true))

            for j, objective in ipairs(objectives) do
                counts[j] = (Count(objective.numFulfilled) or 0)
                local step = ((known and known.counts[j] and (counts[j] - known.counts[j])) or 0)

                if announce and (step > 0) then
                    gained = (gained + step)

                    if not best or (step > best.step) then
                        best = { objective = objective, questID = questID, step = step }
                    end
                end
            end

            if announce and known and ready and not known.ready then
                readied[#readied + 1] = questID
            end

            seen[questID] = true
            Known[questID] = { counts = counts, ready = ready }
        end
    end

    for questID in pairs(Known) do
        if not seen[questID] then
            Known[questID] = nil
        end
    end

    if best then
        local objective = best.objective

        module:Set("objective", ObjectiveName(Text(objective.text), Text(objective.type)))
        module:Set("have", Count(objective.numFulfilled) or 0)
        module:Set("need", Count(objective.numRequired) or 0)
        module:Set("title", Text(C_QuestLog.GetTitleForQuestID(best.questID)))
        module:Set("fought", (fought and gained) or 0)
        module:Set("gained", module:Get("gained") + gained)
    end

    for _, questID in ipairs(readied) do
        module:Set("readyTitle", Text(C_QuestLog.GetTitleForQuestID(questID)))
        module:Set("ready", module:Get("ready") + 1)
    end
end

ns.Addon:Module("QuestProgress", {
    demand = true,
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        local state = module.Addon.State
        local timer = nil
        -- Whether the log changed during the fight in progress.
        local waiting = false

        wipe(Known)

        local function ReadSoon()
            if state.Values[combat] then
                waiting = true
            elseif not timer then
                timer = module:After(ReadDelay, function()
                    timer = nil

                    -- A fight that started while this reading waited gets it in the fight's sum instead.
                    if state.Values[combat] then
                        waiting = true
                    else
                        Read(module, true, false)
                    end
                end)
            end
        end

        module:On("QUEST_LOG_UPDATE", ReadSoon)

        module:Rule({
            changed = function(active)
                if not active and waiting then
                    waiting = false
                    Read(module, true, true)
                end
            end,
            reads = { combat }, when = function(values) return values.Values[combat] end,
        })

        if state.Values[combat] then
            waiting = true
        else
            Read(module, false, false)
        end
    end,
    state = {
        { default = 0, kind = "number", min = 0, name = "fought", persist = false, step = 1 },
        { default = 0, kind = "number", min = 0, name = "gained", persist = false, step = 1 },
        { default = 0, kind = "number", min = 0, name = "have", persist = false, step = 1 },
        { default = 0, kind = "number", min = 0, name = "need", persist = false, step = 1 },
        { default = "", kind = "string", name = "objective", persist = false },
        { default = 0, kind = "number", min = 0, name = "ready", persist = false, step = 1 },
        { default = "", kind = "string", name = "readyTitle", persist = false },
        { default = "", kind = "string", name = "title", persist = false },
    },
    toggle = false,
})

ns.Addon:Module("QuestCount", {
    active = { reads = { "Scholar.enabled" }, when = function(state) return state:Get("Scholar.enabled") end },
    description = ("When your child's quest objectives go up, the Owl says the new count and how many are left, and "
        .. "when a quest is ready to turn in. It follows Read riddles aloud."),
    label = "Count quest progress aloud",
    lockedBy = "Scholar.locked",
    OnEnable = function(module)
        local said = {}
        local timer = nil

        -- What one reading gained and made ready is said as one sentence, the moment the reading is done.
        local function Queue(text)
            said[#said + 1] = text

            if not timer then
                timer = module:After(0, function()
                    local all = concat(said, " ")

                    timer = nil
                    wipe(said)

                    if ns.ScholarVoice.ReadsAloud() and not ns.ScholarView.IsShown() then
                        ns.ScholarVoice.Say(all)
                    end
                end)
            end
        end

        module:OnIncrease("QuestProgress.gained", function(state) Queue(ProgressText(state)) end)

        module:OnIncrease("QuestProgress.ready", function(state)
            Queue(state:Get("QuestProgress.readyTitle") .. " is ready to turn in!")
        end)
    end,
    page = "Scholar's challenge",
    scope = "character",
    -- With Read riddles aloud: it follows that setting.
    section = "Reading aloud",
    uses = { "QuestProgress" },
})
