local addonName, ns = ...

-- QuestReader: the Owl reads a young scholar's quests aloud. When a quest dialog opens, its giver's words are read with
-- the player's text-to-speech voice: who's speaking and the quest's name, then the offer's story and what to do
-- (QUEST_DETAIL), the progress page's question (QUEST_PROGRESS), or the reward page's words (QUEST_COMPLETE). Closing
-- the dialog (QUEST_FINISHED, when it's accepted, completed, or walked away from) stops a reading it started, and so
-- does switching the reader off. Either stops only while the reading is the last thing the Owl said
-- (ns.ScholarVoice.Turn), since another voice may be talking. It's part of the Scholar's challenge: it runs while the
-- challenge is on, behind the parent's lock, and follows Read riddles aloud (ns.ScholarVoice). /tlk read reads the open
-- quest whatever that setting says. Texts lose the client's escape codes (ns.QuestBook.Plain), and a secret one is left
-- out.

local GetObjectiveText = GetObjectiveText
local GetProgressText = GetProgressText
local GetQuestText = GetQuestText
local GetRewardText = GetRewardText
local GetTitleText = GetTitleText
local UnitName = UnitName

local Addon = ns.Addon
-- The open dialog's page ("detail", "progress", or "reward"), or nil while none is open.
local Page = nil
local Plain = ns.QuestBook.Plain
-- The turn of the Owl's line reading the open dialog, or nil while none is read.
local Reading = nil

-- The dialog closed, or the reader stopped: a reading it started stops, unless the Owl has said something since.
local function Close()
    local turn = Reading

    Page, Reading = nil, nil

    if turn and (turn == ns.ScholarVoice.Turn()) then
        C_VoiceChat.StopSpeakingText()
    end
end

-- What the open dialog's page says, as the Owl reads it.
local function Words()
    local parts = {}
    -- secret: Plain checks issecretvalue and gives "" for a secret name
    local giver = Plain(UnitName("questnpc"))

    local function Add(text)
        text = Plain(text)

        if text ~= "" then
            parts[#parts + 1] = text
        end
    end

    if Page ~= "reward" then
        Add(GetTitleText() .. ".")
    end

    if Page == "detail" then
        Add(GetQuestText())
        Add(GetObjectiveText())
    elseif Page == "progress" then
        Add(GetProgressText())
    else
        Add(GetRewardText())
    end

    local text = table.concat(parts, " ")

    return (((giver ~= "") and (giver .. " says: " .. text)) or text)
end

-- Reads the open dialog aloud.
local function Read()
    Reading = ns.ScholarVoice.Say(Words())
end

-- A dialog page opened: it's read when Read riddles aloud says so.
local function Open(page)
    Page = page

    if ns.ScholarVoice.ReadsAloud() then
        Read()
    end
end

-- /tlk read: reads the open quest, whatever Read riddles aloud says.
local function ReadAgain()
    if not Page then
        Addon:Print("Open a quest first, then type the command to hear it.")
    elseif not ns.ScholarVoice.CanHear() then
        Addon:Print("There's no text-to-speech voice to read with. Add one in Windows' speech settings.")
    else
        Read()
    end
end

Addon:Module("QuestReader", {
    active = { reads = { "Scholar.enabled" }, when = function(state) return state:Get("Scholar.enabled") end },
    commands = { { label = "Read the open quest aloud", name = "read", run = ReadAgain, slash = "read" } },
    description = ("When your child opens a quest, the Owl reads it aloud: who's speaking, the quest's name, its "
        .. "story, and what to do, or the words when it's turned in. It follows Read riddles aloud."),
    label = "Read quests aloud",
    lockedBy = "Scholar.locked",
    OnDisable = Close,
    OnEnable = function(module)
        module:On("QUEST_COMPLETE", function() Open("reward") end)
        module:On("QUEST_DETAIL", function() Open("detail") end)
        module:On("QUEST_FINISHED", Close)
        module:On("QUEST_PROGRESS", function() Open("progress") end)
    end,
    page = "Scholar's challenge",
    scope = "character",
    -- With Read riddles aloud: it follows that setting.
    section = "Reading aloud",
})
