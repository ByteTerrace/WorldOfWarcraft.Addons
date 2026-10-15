local addonName, ns = ...

-- Scholar's challenge: riddles for young players about their own quests, and math and reading,
-- set up by a parent.
--
-- Off by default and per character: a parent turns it on for a child's character, picks a grade,
-- and can lock the settings with a PIN (/tlk lock 1234; /tlk unlock 1234 for the session). While
-- locked the PIN can't be changed, and after three wrong PINs unlocking waits a minute.
--
--   What     quest riddles are preferred: two in a row, then math or reading takes a turn. A quest
--            riddle asks about one the player was shown (accepted, or turned in): the newest not
--            asked about since, else an older one for review (QuestBook.lua remembers,
--            ScholarQuests.lua asks). It's an open-book test: the quest book on the riddle screen
--            shows the quest as the player saw it. With only quest riddles on and no quest yet, a
--            riddle that comes due waits for one.
--   When     every N minutes of play (saved per character, so relogging doesn't skip one), and
--            optionally at each level-up. Time AFK, or with every subject off, doesn't count. A good
--            moment brings the next riddle forward once half its minutes are played: a flight path
--            (free time), a quest turned in (asked about while it's fresh) or a death (waiting to
--            come back); each can be switched off.
--   Where    a riddle covers the screen and holds the mouse and keyboard until it's solved; in
--            Gentle mode a Skip appears after one try. Never during combat: a riddle waits for the
--            fight to end, and one on screen steps aside if a fight starts and comes back after.
--   How      answer with 1-4, a click, or the controller's face buttons; Need a hint? (the quest
--            book, on a quest riddle) is H or the left shoulder, Read aloud is R or the right
--            shoulder, Skip is Esc or Back. The open quest book scrolls with the wheel, the Up and
--            Down arrows or the D-pad.
--   Rewards  a star per riddle, streaks, scholar ranks, and difficulty that adapts within the grade.
--
-- Limits, honestly: a controller's sticks still move the character, and a determined child can
-- turn the addon off at character select. Blizzard's parental controls (play time limits) are the
-- place for hard limits; this is meant to be fun.

local FinishDelay = 1.8
local QuestShare = 2 -- quest riddles in a row before math or reading takes a turn
local Ranks = { { 0, "Apprentice" }, { 10, "Journeyman" }, { 25, "Adept" }, { 50, "Sage" }, { 100, "Archmage" } }
local AnswerSources = { "gamepad.south", "gamepad.east", "gamepad.west", "gamepad.north" }
local KeyAnswers = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }
-- The screen's other actions: their controller buttons and keyboard keys.
local ActionSources = { hint = "gamepad.leftShoulder", speak = "gamepad.rightShoulder", skip = "gamepad.back" }
local ActionKeys = { hint = "H", speak = "R", skip = "Esc" }
-- The open quest book scrolls with the arrow keys and the D-pad; held, the D-pad keeps going.
local ScrollKeys = { UP = -1, DOWN = 1 }
local ScrollSources = { scrollUp = "gamepad.dpadUp", scrollDown = "gamepad.dpadDown" }
local ScrollRepeat = 0.12 -- seconds between notches while a D-pad direction is held
local FlightCheck = 1 -- seconds after losing control to look for a flight path (UnitOnTaxi)
local TurnInDelay = 1 -- seconds after a turn-in, once QuestBook has noted it and the panel closed
local LockedBy = "Scholar.locked"
local MaxPinMisses = 3
local PinWaitSeconds = 60

local ByteTerrace = ByteTerrace
local C_Sound, C_TTSSettings, C_VoiceChat, GetMoney = C_Sound, C_TTSSettings, C_VoiceChat, GetMoney
local GetRealZoneText, GetServerTime, GetTime, IsLoggedIn = GetRealZoneText, GetServerTime, GetTime, IsLoggedIn
local UnitOnTaxi = UnitOnTaxi
local SOUNDKIT, UnitClass, UnitLevel, UnitName = SOUNDKIT, UnitClass, UnitLevel, UnitName
local issecretvalue, wipe, floor, max, min, random, byte = issecretvalue, wipe, math.floor, math.max, math.min, math.random, string.byte

local Addon = ns.Addon
local Puzzles = ns.Puzzles
local QuestBook = ns.QuestBook
local ScholarView = ns.ScholarView

local GradeValues, GradeLabels = {}, {}
for _, grade in ipairs(Puzzles.Grades) do
    local id = tostring(grade.id)
    GradeValues[#GradeValues + 1] = id
    GradeLabels[id] = grade.label
end

-- The riddle on screen (or waiting out a fight) until it's solved or skipped, how many tries
-- missed, and which answers they picked ([i] = true), so a riddle that comes back keeps them.
local Current, Wrongs, Missed = nil, 0, {}
local LastSubject
local Counting = false -- the play clock runs: no riddle is due, you're not AFK, and a subject is on
local SegmentStart     -- GetTime() the running stretch of play started at
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

-- Seconds of play toward the next riddle, the running stretch included.
local function Elapsed()
    local elapsed = Scholar:Get("elapsed")
    if Counting then
        elapsed = elapsed + floor(GetTime() - SegmentStart)
    end
    return elapsed
end

-- Saves the running stretch of play into elapsed, keeping its fraction of a second running.
local function Bank()
    if Counting then
        local played = floor(GetTime() - SegmentStart)
        SegmentStart = SegmentStart + played
        Scholar:Set("elapsed", Scholar:Get("elapsed") + played)
    end
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
        wrong = Missed, canSkip = Scholar:Get("mode") == "gentle" and Wrongs > 0,
        keys = { KeyLabel(1), KeyLabel(2), KeyLabel(3), KeyLabel(4) },
        actions = { hint = ActionLabel("hint"), speak = ActionLabel("speak"), skip = ActionLabel("skip") },
        book = Current.book ~= nil,
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

-- Whether any subject is on.
local function HasSubject()
    return Scholar:Get("math") or Scholar:Get("reading") or Scholar:Get("quests")
end

-- A riddle about a quest the player was shown, in QuestBook's order (fresh ones first, then the
-- rest for review), or nil when none is recorded. A quest no question fits counts as asked.
local function QuestPuzzle()
    local known, byKey = QuestBook.All(), {}
    for _, record in ipairs(known) do
        byKey[record.key] = record
    end
    for _, key in ipairs(QuestBook.Order()) do
        local puzzle = Puzzles.Generate({ subject = "quest", random = random, quest = byKey[key], known = known })
        if puzzle then
            puzzle.questKey = key
            return puzzle
        end
        QuestBook.Asked(key)
    end
    return nil
end

-- The next riddle. Quest riddles are preferred: QuestShare of them in a row, then math or reading
-- takes a turn (alternating when both are on), whenever any of those is on. nil when there's
-- nothing to ask.
local function NextPuzzle()
    local others = Scholar:Get("math") or Scholar:Get("reading")
    if Scholar:Get("quests") and (Scholar:Get("questRun") < QuestShare or not others) then
        local puzzle = QuestPuzzle()
        if puzzle then
            Scholar:Set("questRun", min(Scholar:Get("questRun") + 1, QuestShare))
            return puzzle
        end
    end
    Scholar:Set("questRun", 0)
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
    if Current and Current.questKey then
        QuestBook.Asked(Current.questKey)
    end
    Current, Wrongs = nil, 0
    wipe(Missed)
    Close()
    Scholar:Set("solved", false)
    Scholar:Set("elapsed", 0)
    SegmentStart = GetTime()
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
        if Current.questKey then
            QuestBook.Asked(Current.questKey) -- answered: a /reload in the celebration doesn't ask it again
        end
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
        Missed[i] = true
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

-- Need a hint? shows the hint; on a quest riddle it opens (or closes) the quest book instead.
local function Hint()
    if Current and Current.book then
        ScholarView.ToggleBook()
    elseif Current and not Scholar:Get("solved") then
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
        elseif ScrollKeys[key] then
            ScholarView.ScrollBook(ScrollKeys[key])
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
    { name = "quests", kind = "boolean", default = true, label = "Quest riddles", scope = "character",
        lockedBy = LockedBy,
        description = "Questions about the quests your child accepts and turns in: who, where, what they asked, "
            .. "and their text. Two of every three riddles are about quests, the newest first, then older ones for "
            .. "review; the quest book on the riddle screen holds every answer." },
    { name = "interval", kind = "number", default = 30, min = 10, max = 120, step = 5,
        label = "Minutes between riddles", description = "Minutes of play between riddles.", scope = "character",
        lockedBy = LockedBy, section = "When" },
    { name = "onLevelUp", kind = "boolean", default = true, label = "A riddle at every level-up", scope = "character",
        lockedBy = LockedBy, description = "Earn each new level with a little wisdom, too." },
    { name = "onFlight", kind = "boolean", default = true, label = "Riddles on flight paths", scope = "character",
        lockedBy = LockedBy, description = "A flight is free time: once half the minutes are played, it brings the next riddle." },
    { name = "onTurnIn", kind = "boolean", default = true, label = "Riddles when a quest is turned in",
        scope = "character", lockedBy = LockedBy,
        description = "Once half the minutes are played, turning in a quest brings a riddle about it, while it's fresh." },
    { name = "onDeath", kind = "boolean", default = true, label = "Riddles while dead", scope = "character",
        lockedBy = LockedBy, description = "Once half the minutes are played, a death brings the next riddle." },
    { name = "mode", kind = "string", default = "gate", values = { "gate", "gentle" },
        valueLabels = { gate = "Solve to keep playing", gentle = "Gentle (Skip after one try)" },
        label = "Riddle style", description = "Whether a riddle must be solved, or can be skipped after one try.",
        scope = "character", lockedBy = LockedBy },
    -- Progress, per character. elapsed is seconds of play toward the next riddle; questRun the quest
    -- riddles asked since math or reading last took a turn.
    { name = "stars", kind = "number", default = 0, scope = "character" },
    { name = "streak", kind = "number", default = 0, scope = "character" },
    { name = "level", kind = "number", default = 1, min = 1, max = 3, scope = "character" },
    { name = "elapsed", kind = "number", default = 0, scope = "character" },
    { name = "pending", kind = "boolean", default = false, scope = "character" },
    { name = "questRun", kind = "number", default = 0, min = 0, step = 1, scope = "character" },
    -- The riddle on screen was just solved: its celebration holds the screen until Finish.
    { name = "solved", kind = "boolean", default = false, persist = false },
    -- The parent's PIN (a hash; 0 = none), account-wide, and whether settings are locked right now.
    { name = "pin", kind = "number", default = 0, lockedBy = LockedBy },
    { name = "locked", kind = "boolean", default = false, persist = false },
    -- The parent unlocked this session: saved, so a /reload keeps it; the next login locks again.
    { name = "unlocked", kind = "boolean", default = false },
    -- Wrong unlock PINs since the last wait, and the server time unlocking waits until. Saved, so a
    -- /reload doesn't buy more tries.
    { name = "pinMisses", kind = "number", default = 0 },
    { name = "pinWait", kind = "number", default = 0 },
}

local Commands = {
    { name = "status", slash = "scholar", label = "Show Scholar stars and the next riddle", run = function()
        local stars = Scholar:Get("stars")
        local left = Scholar:Get("interval") * 60 - Elapsed()
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
            Scholar:Set("unlocked", false)
            Scholar:Set("locked", true)
            Addon:Print("Scholar settings locked.")
        elseif ValidPin(pin) then
            Scholar:Set("pin", PinHash(pin))
            Scholar:Set("unlocked", false)
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
            Scholar:Set("unlocked", true)
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

-- A held D-pad direction scrolls the open quest book a notch, then a notch every ScrollRepeat
-- seconds until it's let go.
local Scrolling
local function ScrollHeld(notches, phase)
    Scholar:Cancel(Scrolling)
    Scrolling = nil
    if phase == "down" then
        ScholarView.ScrollBook(notches)
        Scrolling = Scholar:Every(ScrollRepeat, function() ScholarView.ScrollBook(notches) end)
    end
end
Commands[#Commands + 1] = { name = "scrollUp", label = "Scroll the quest book up", held = true,
    run = function(_, phase) ScrollHeld(-1, phase) end }
Commands[#Commands + 1] = { name = "scrollDown", label = "Scroll the quest book down", held = true,
    run = function(_, phase) ScrollHeld(1, phase) end }

local Bindings = {}
for i, source in ipairs(AnswerSources) do
    Bindings[i] = { map = "scholar", source = source, command = "Scholar.answer" .. i }
end
for action, source in pairs(ActionSources) do
    Bindings[#Bindings + 1] = { map = "scholar", source = source, command = "Scholar." .. action }
end
for command, source in pairs(ScrollSources) do
    Bindings[#Bindings + 1] = { map = "scholar", source = source, command = "Scholar." .. command }
end

Scholar = Addon:Module("Scholar", {
    label = "Scholar's challenge",
    page = "Scholar's challenge",
    description = "Riddles for young players about their own quests, and math and reading, every so often and "
        .. "at level-ups. Per character; off unless a parent turns it on.",
    default = false,
    scope = "character",
    lockedBy = LockedBy,
    state = Rows,
    commands = Commands,
    bindings = Bindings,
    uses = { "QuestBook" },
    OnEnable = function(module)
        -- A parent's unlock lasts the session: a /reload keeps it, while a new login or switching
        -- the challenge back on mid-session locks again.
        if IsLoggedIn() then
            module:Set("unlocked", false)
        end
        module:Set("locked", module:Get("pin") ~= 0 and not module:Get("unlocked"))
        module:On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
            if isInitialLogin then
                module:Set("unlocked", false)
                module:Set("locked", module:Get("pin") ~= 0)
            end
        end)
        local pending, solved, combat = module:Id("pending"), module:Id("solved"), module:Id("combat.active")
        local afk, mathOn, readingOn = module:Id("afk.active"), module:Id("math"), module:Id("reading")
        local questsOn = module:Id("quests")

        -- The play clock counts toward the next riddle while none is due, you're not AFK and a
        -- subject is on. It writes nothing while it runs: one timer fires when the interval is up,
        -- and play is saved when the clock stops, at logout and as the module stops.
        local due
        local function Schedule()
            module:Cancel(due)
            due = nil
            if Counting then
                due = module:After(max(module:Get("interval") * 60 - Elapsed(), 0), function()
                    Bank()
                    module:Set("pending", true)
                end)
            end
        end
        module:Rule({
            reads = { pending, afk, mathOn, readingOn, questsOn }, initial = true,
            when = function(state)
                return not state.Values[pending] and not state.Values[afk]
                    and (state.Values[mathOn] or state.Values[readingOn] or state.Values[questsOn])
            end,
            changed = function(counting)
                Bank()
                Counting, SegmentStart = counting, GetTime()
                Schedule()
            end,
        })
        module:Watch({ "interval", "elapsed" }, Schedule, true)
        module:On("PLAYER_LOGOUT", Bank)

        module:On("PLAYER_LEVEL_UP", function()
            if module:Get("onLevelUp") then
                module:Set("pending", true)
            end
        end)

        -- A good moment brings the next riddle forward once it's half due: the play clock counting,
        -- and half the interval played.
        local function Moment(row)
            if module:Get(row) and Counting and Elapsed() * 2 >= module:Get("interval") * 60 then
                Bank()
                module:Set("pending", true)
            end
        end
        module:On("PLAYER_CONTROL_LOST", function()
            module:After(FlightCheck, function()
                if UnitOnTaxi("player") then
                    Moment("onFlight")
                end
            end)
        end)
        module:On("QUEST_TURNED_IN", function()
            module:After(TurnInDelay, function() Moment("onTurnIn") end)
        end)
        module:On("PLAYER_DEAD", function() Moment("onDeath") end)

        -- A riddle shows when one is due (or celebrating) and there's no fight; a fight sends it
        -- away until it ends. A celebration a fight cut short doesn't come back: Finish ends it.
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
                    elseif not HasSubject() then
                        module:Set("pending", false)
                    end -- else it waits for a quest to ask about
                else
                    Close()
                end
            end,
        })
        -- A riddle that came due with nothing to ask waits: a new quest, or a subject switched on,
        -- gives it one.
        module:Watch({ "QuestBook.quests", mathOn, readingOn, questsOn }, function(state)
            if state.Values[pending] and not Current and not state.Values[solved] and not state.Values[combat] then
                Current = NextPuzzle()
                if Current then
                    Open()
                elseif not HasSubject() then
                    module:Set("pending", false)
                end
            end
        end, true)
    end,
    OnDisable = function(module)
        if module:Get("solved") then
            Finish(true) -- its celebration timer stops with the module; the rank card still shows
        end
        Current, Wrongs = nil, 0
        wipe(Missed)
        Close()
        Bank()
        Counting = false
    end,
})
