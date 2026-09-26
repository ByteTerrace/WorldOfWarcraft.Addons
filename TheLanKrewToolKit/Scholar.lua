local addonName, ns = ...

-- Scholar's challenge: math and reading riddles for young players, set up by a parent.
--
-- Off by default and per character: a parent turns it on for a child's character, picks a grade,
-- and can lock the settings with a PIN (/tlk lock 1234; /tlk unlock 1234 for the session). While
-- locked the PIN can't be changed, and after three wrong PINs unlocking waits a minute.
--
--   When     every N minutes of play (saved per character, so relogging doesn't skip one), and
--            optionally at each level-up. Time AFK, or with both subjects off, doesn't count.
--   Where    a riddle covers the screen and holds the mouse and keyboard until it's solved; in
--            Gentle mode a Skip appears after one try. Never during combat: a riddle waits for the
--            fight to end, and one on screen steps aside if a fight starts and comes back after.
--   How      answer with 1-4, a click, or the controller's face buttons; Need a hint? is H or the
--            left shoulder, Read aloud is R or the right shoulder, Skip is Esc or Back.
--   Rewards  a star per riddle, streaks, scholar ranks, and difficulty that adapts within the grade.
--
-- Limits, honestly: a controller's sticks still move the character, and a determined child can
-- turn the addon off at character select. Blizzard's parental controls (play time limits) are the
-- place for hard limits; this is meant to be fun.

local CheckSeconds = 15
local FinishDelay = 1.8
local Ranks = { { 0, "Apprentice" }, { 10, "Journeyman" }, { 25, "Adept" }, { 50, "Sage" }, { 100, "Archmage" } }
local AnswerSources = { "gamepad.south", "gamepad.east", "gamepad.west", "gamepad.north" }
local KeyAnswers = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }
-- The screen's other actions: their controller buttons and keyboard keys.
local ActionSources = { hint = "gamepad.leftShoulder", speak = "gamepad.rightShoulder", skip = "gamepad.back" }
local ActionKeys = { hint = "H", speak = "R", skip = "Esc" }
local LockedBy = "Scholar.locked"
local MaxPinMisses = 3
local PinWaitSeconds = 60

local ByteTerrace = ByteTerrace
local C_Sound, C_TTSSettings, C_VoiceChat, GetMoney = C_Sound, C_TTSSettings, C_VoiceChat, GetMoney
local GetRealZoneText, GetServerTime, GetTime = GetRealZoneText, GetServerTime, GetTime
local SOUNDKIT, UnitClass, UnitLevel, UnitName = SOUNDKIT, UnitClass, UnitLevel, UnitName
local issecretvalue, floor, random, byte = issecretvalue, math.floor, math.random, string.byte

local Addon = ns.Addon
local Puzzles = ns.Puzzles
local ScholarView = ns.ScholarView

local GradeValues, GradeLabels = {}, {}
for _, grade in ipairs(Puzzles.Grades) do
    local id = tostring(grade.id)
    GradeValues[#GradeValues + 1] = id
    GradeLabels[id] = grade.label
end

-- The riddle on screen (or waiting out a fight) until it's solved or skipped.
local Current, Wrongs = nil, 0
local LastSubject
local SegmentStart
local Scholar -- the module, declared at the end

-- Kid-proofing, not security: a small hash so the PIN isn't sitting in the SavedVariables as-is.
local function PinHash(pin)
    local hash = 5381
    local text = "tlk:" .. pin
    for i = 1, #text do
        hash = (hash * 33 + byte(text, i)) % 2147483647
    end
    return hash
end

local function ValidPin(pin)
    return pin and pin:match("^%d%d%d%d%d?%d?%d?%d?$") ~= nil
end

local function Rank(stars)
    local name = Ranks[1][2]
    for _, rank in ipairs(Ranks) do
        if stars >= rank[1] then
            name = rank[2]
        end
    end
    return name
end

-- What the screen shows about progress: stars, rank, the next rank and how far along, the streak.
local function Progress(extra)
    local stars = Scholar:Get("stars")
    local info = { stars = stars, rank = Rank(stars), streak = Scholar:Get("streak") }
    for i, rank in ipairs(Ranks) do
        local nextRank = Ranks[i + 1]
        if stars >= rank[1] and nextRank and stars < nextRank[1] then
            info.nextRank, info.nextAt = nextRank[2], nextRank[1]
            info.progress = (stars - rank[1]) / (nextRank[1] - rank[1])
        end
    end
    for key, value in pairs(extra or {}) do
        info[key] = value
    end
    return info
end

-- Whether a controller with printed button names is connected.
local function UsingController()
    return ByteTerrace.Input.LabelStyle() ~= "Generic"
end

-- The key for answer i: 1-4, or the connected controller's face button.
local function KeyLabel(i)
    if UsingController() then
        return ByteTerrace.Input.Label(AnswerSources[i])
    end
    return tostring(i)
end

-- The key for one of the screen's other actions (hint, speak, skip).
local function ActionLabel(action)
    if UsingController() then
        return ByteTerrace.Input.Label(ActionSources[action])
    end
    return ActionKeys[action]
end

-- Shows the riddle and takes the keyboard and controller. Only ever called out of combat.
local function Open()
    local frame = ScholarView.Show(Current, Progress({
        gentle = Scholar:Get("mode") == "gentle", canSpeak = true, controller = UsingController(),
        keys = { KeyLabel(1), KeyLabel(2), KeyLabel(3), KeyLabel(4) },
        actions = { hint = ActionLabel("hint"), speak = ActionLabel("speak"), skip = ActionLabel("skip") },
    }))
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(false) -- protected: Open only runs out of combat (see the combat rule)
    Addon.Input:SetActiveMaps({ "scholar" })
    C_Sound.PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
end

-- Hides the riddle and gives input back; the riddle stays current until it's solved.
local function Close()
    if ScholarView.IsShown() then
        ScholarView.Frame():EnableKeyboard(false)
        ScholarView.Hide()
        Addon.Input:SetActiveMaps({})
    end
end

-- The child's own game, for personal word problems ("Tessa has 3 potions...").
local function Context()
    local name, class
    local rawName = UnitName("player")
    if not issecretvalue(rawName) then
        name = rawName
    end
    local _, rawClass = UnitClass("player")
    if not issecretvalue(rawClass) then
        class = rawClass
    end
    return {
        name = name,
        class = class,
        level = UnitLevel("player"),
        zone = GetRealZoneText(),
        copper = GetMoney(),
    }
end

local function HasSubject()
    return Scholar:Get("math") or Scholar:Get("reading")
end

-- The next riddle, alternating subjects when both are on; nil when neither is.
local function NextPuzzle()
    local subjects = {}
    if Scholar:Get("math") then
        subjects[#subjects + 1] = "math"
    end
    if Scholar:Get("reading") then
        subjects[#subjects + 1] = "reading"
    end
    if #subjects == 0 then
        return nil
    end
    local subject = subjects[1]
    if #subjects == 2 and LastSubject == subject then
        subject = subjects[2]
    end
    LastSubject = subject
    return Puzzles.Generate({
        subject = subject, grade = tonumber(Scholar:Get("grade")), level = Scholar:Get("level"),
        random = random, context = Context(),
    })
end

-- Ends the riddle, solved (after its celebration) or skipped; either way the timer starts over.
local function Finish(solved)
    local before = Scholar:Get("stars")
    Current, Wrongs = nil, 0
    Close()
    Scholar:Set("solved", false)
    Scholar:Set("elapsed", 0)
    Scholar:Set("pending", false)
    if solved and Rank(before - 1) ~= Rank(before) then
        ns.Cards.Show({ icon = "Interface\\Icons\\INV_Misc_Book_09", sound = SOUNDKIT.LFG_REWARDS,
            title = "New rank: " .. Rank(before) .. "!",
            body = before .. " stars of wisdom. The Owl Sage is proud of you!" })
    end
end

local function Choose(i)
    local buttons = ScholarView.IsShown() and ScholarView.Frame().Buttons
    if not Current or Scholar:Get("solved") or not buttons or (buttons[i] and not buttons[i]:IsEnabled()) then
        return
    end
    if i == Current.answer then
        -- The riddle stops being due now, so a /reload during the celebration doesn't ask another;
        -- solved holds the screen until Finish closes it.
        Scholar:Set("solved", true)
        Scholar:Set("pending", false)
        Scholar:Set("elapsed", 0)
        local streak = Scholar:Get("streak") + 1
        Scholar:Set("streak", streak)
        Scholar:Set("stars", Scholar:Get("stars") + 1)
        local levelUp = streak % 3 == 0 and Scholar:Get("level") < 3
        if levelUp then
            Scholar:Set("level", Scholar:Get("level") + 1)
        end
        ScholarView.Correct(i, Current.explanation, Progress({ earned = 1, levelUp = levelUp }))
        C_Sound.PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
        Scholar:After(FinishDelay, function() Finish(true) end)
    else
        Wrongs = Wrongs + 1
        Scholar:Set("streak", 0)
        if Wrongs == 2 and Scholar:Get("level") > 1 then
            Scholar:Set("level", Scholar:Get("level") - 1)
        end
        ScholarView.Wrong(i, Current.hint, Scholar:Get("mode") == "gentle")
    end
end

local function Skip()
    if Current and not Scholar:Get("solved") and Wrongs > 0 and Scholar:Get("mode") == "gentle" then
        Finish(false)
    end
end

-- Reads the riddle aloud with the player's text-to-speech voice, rate and volume.
local function Speak()
    if Current then
        C_VoiceChat.SpeakText(C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard), ScholarView.Spoken(Current),
            C_TTSSettings.GetSpeechRate(), C_TTSSettings.GetSpeechVolume(), false)
    end
end

local function Hint()
    if Current and not Scholar:Get("solved") then
        ScholarView.Hint(Current.hint)
    end
end

ScholarView.Init({
    choose = function(i) Addon:Batch(Choose, i) end,
    skip = function() Addon:Batch(Skip) end,
    hint = Hint,
    speak = Speak,
    key = function(key)
        if KeyAnswers[key] then
            Addon:Batch(Choose, KeyAnswers[key])
        elseif key == "ESCAPE" then
            Addon:Batch(Skip)
        elseif key == "H" then
            Hint()
        elseif key == "R" then
            Speak()
        end
    end,
})

local Rows = {
    { name = "grade", kind = "string", default = "2", values = GradeValues, valueLabels = GradeLabels,
        label = "Grade",
        description = "The school grade riddles are written for. Difficulty also adapts to how it's going.",
        scope = "character", lockedBy = LockedBy, section = "Riddles" },
    { name = "math", kind = "boolean", default = true, label = "Math riddles", scope = "character", lockedBy = LockedBy,
        description = "Counting, arithmetic, times tables, fractions and more, by grade." },
    { name = "reading", kind = "boolean", default = true, label = "Reading riddles", scope = "character",
        lockedBy = LockedBy,
        description = "Rhymes, spelling, word scrambles, vocabulary and short stories, by grade." },
    { name = "interval", kind = "number", default = 30, min = 10, max = 120, step = 5,
        label = "Minutes between riddles", description = "Minutes of play between riddles.", scope = "character",
        lockedBy = LockedBy, section = "When" },
    { name = "onLevelUp", kind = "boolean", default = true, label = "A riddle at every level-up", scope = "character",
        lockedBy = LockedBy, description = "Earn each new level with a little wisdom, too." },
    { name = "mode", kind = "string", default = "gate", values = { "gate", "gentle" },
        valueLabels = { gate = "Solve to keep playing", gentle = "Gentle (Skip after one try)" },
        label = "Riddle style", description = "Whether a riddle must be solved, or can be skipped after one try.",
        scope = "character", lockedBy = LockedBy },
    -- Progress, per character. elapsed is seconds of play toward the next riddle.
    { name = "stars", kind = "number", default = 0, scope = "character" },
    { name = "streak", kind = "number", default = 0, scope = "character" },
    { name = "level", kind = "number", default = 1, min = 1, max = 3, scope = "character" },
    { name = "elapsed", kind = "number", default = 0, scope = "character" },
    { name = "pending", kind = "boolean", default = false, scope = "character" },
    -- The riddle on screen was just solved: its celebration holds the screen until Finish.
    { name = "solved", kind = "boolean", default = false, persist = false },
    -- The parent's PIN (a hash; 0 = none), account-wide, and whether settings are locked right now.
    { name = "pin", kind = "number", default = 0, lockedBy = LockedBy },
    { name = "locked", kind = "boolean", default = false, persist = false },
    -- Wrong unlock PINs since the last wait, and the server time unlocking waits until. Saved, so a
    -- /reload doesn't buy more tries.
    { name = "pinMisses", kind = "number", default = 0 },
    { name = "pinWait", kind = "number", default = 0 },
}

local Commands = {
    { name = "status", slash = "scholar", label = "Show Scholar stars and the next riddle", run = function()
        local stars = Scholar:Get("stars")
        local left = Scholar:Get("interval") * 60 - Scholar:Get("elapsed")
        local minutes = left > 0 and math.ceil(left / 60) or 0
        Addon:Print(("Stars: %d (%s). Next riddle in about %d min."):format(stars, Rank(stars), minutes))
    end },
    { name = "practice", slash = "puzzle", label = "Solve a riddle right now", run = function()
        Scholar:Set("pending", true)
    end },
    { name = "lock", slash = "lock", label = "Parents: lock Scholar settings with a PIN (lock <pin>)", run = function(pin)
        if Scholar:Get("locked") then
            Addon:Print("Scholar settings are locked. Unlock them first to change the PIN.")
        elseif Scholar:Get("pin") ~= 0 and not pin then
            Scholar:Set("locked", true)
            Addon:Print("Scholar settings locked.")
        elseif ValidPin(pin) then
            Scholar:Set("pin", PinHash(pin))
            Scholar:Set("locked", true)
            Addon:Print("Scholar settings locked. Unlock with " .. Addon.Slash[1] .. " unlock <pin>.")
        else
            Addon:Print("Usage: " .. Addon.Slash[1] .. " lock <pin> (4 to 8 digits).")
        end
    end },
    { name = "unlock", slash = "unlock", label = "Parents: unlock Scholar settings (unlock <pin>)", run = function(pin)
        local wait = Scholar:Get("pinWait") - GetServerTime()
        if Scholar:Get("pin") == 0 then
            Addon:Print("Scholar settings aren't locked.")
        elseif wait > 0 then
            Addon:Print(("Too many wrong PINs. Try again in %d seconds."):format(wait))
        elseif not pin then
            Addon:Print("Usage: " .. Addon.Slash[1] .. " unlock <pin>.")
        elseif PinHash(pin) == Scholar:Get("pin") then
            Scholar:Set("pinMisses", 0)
            Scholar:Set("locked", false)
            Addon:Print("Scholar settings unlocked for this session.")
        elseif Scholar:Get("pinMisses") + 1 >= MaxPinMisses then
            Scholar:Set("pinMisses", 0)
            Scholar:Set("pinWait", GetServerTime() + PinWaitSeconds)
            Addon:Print(("That PIN isn't right. Try again in %d seconds."):format(PinWaitSeconds))
        else
            Scholar:Set("pinMisses", Scholar:Get("pinMisses") + 1)
            Addon:Print("That PIN isn't right.")
        end
    end },
}
for i = 1, 4 do
    Commands[#Commands + 1] = { name = "answer" .. i, label = "Choose answer " .. i, run = function() Choose(i) end }
end
Commands[#Commands + 1] = { name = "hint", label = "Show the riddle's hint", run = function() Hint() end }
Commands[#Commands + 1] = { name = "speak", label = "Read the riddle aloud", run = function() Speak() end }
Commands[#Commands + 1] = { name = "skip", label = "Skip the riddle (Gentle mode, after a try)", run = function() Skip() end }

local Bindings = {}
for i, source in ipairs(AnswerSources) do
    Bindings[i] = { map = "scholar", source = source, command = "Scholar.answer" .. i }
end
for action, source in pairs(ActionSources) do
    Bindings[#Bindings + 1] = { map = "scholar", source = source, command = "Scholar." .. action }
end

Scholar = Addon:Module("Scholar", {
    label = "Scholar's challenge",
    page = "Scholar's challenge",
    description = "Math and reading riddles for young players, every so often and at level-ups. "
        .. "Per character; off unless a parent turns it on.",
    default = false,
    scope = "character",
    lockedBy = LockedBy,
    state = Rows,
    commands = Commands,
    bindings = Bindings,
    OnEnable = function(module)
        module:Set("locked", module:Get("pin") ~= 0)
        SegmentStart = GetTime()

        -- Count play time toward the next riddle, leaving out time AFK or with no subject to ask.
        module:Every(CheckSeconds, function()
            local now = GetTime()
            local played = floor(now - SegmentStart)
            SegmentStart = now
            if module:Get("afk.active") or not HasSubject() then
                return
            end
            local elapsed = module:Get("elapsed") + played
            module:Set("elapsed", elapsed)
            if elapsed >= module:Get("interval") * 60 then
                module:Set("pending", true)
            end
        end)

        module:On("PLAYER_LEVEL_UP", function()
            if module:Get("onLevelUp") then
                module:Set("pending", true)
            end
        end)

        -- A riddle shows when one is due (or celebrating) and there's no fight; a fight sends it
        -- away until it ends. A celebration a fight cut short doesn't come back: Finish ends it.
        local pending, solved, combat = module:Id("pending"), module:Id("solved"), module:Id("combat.active")
        module:Rule({
            reads = { pending, solved, combat }, initial = true,
            when = function(state)
                return (state.Values[pending] or state.Values[solved]) and not state.Values[combat]
            end,
            changed = function(show, state)
                if show and state.Values[solved] then
                    return
                elseif show then
                    Current = Current or NextPuzzle()
                    if Current then
                        Open()
                    else
                        module:Set("pending", false) -- no subject enabled
                    end
                else
                    Close()
                end
            end,
        })
    end,
    OnDisable = function(module)
        if module:Get("solved") then
            Finish(true) -- its celebration timer stops with the module; the rank card still shows
        end
        Current, Wrongs = nil, 0
        Close()
    end,
})
