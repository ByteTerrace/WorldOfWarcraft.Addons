local addonName, ns = ...

-- Scholar's challenge: riddles for young players about their own quests, and math and reading, set up by a parent.
--
-- It's off by default and per character: a parent turns it on for a child's character, picks a grade, and can lock the
-- settings with a PIN (ScholarLock.lua).
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
--            (free time), a quest turned in (asked about while it's fresh), or a death (waiting to
--            come back). Each can be switched off.
--   Where    a riddle shows its panel over a light shade, and only its own keys and its panel are
--            the riddle's: the player can still walk, chat, click the world, and fight. Later puts
--            it off into a pill (ScholarLater.lua). In Gentle mode, a Skip appears after one try.
--            Never during combat: a riddle waits for the fight to end, and one on screen steps
--            aside if a fight starts and comes back after.
--            Never over Blizzard's windows either: one that comes due while a quest dialog,
--            gossip, a vendor, the mailbox, a bank, the auction house, a trainer, or the flight
--            map is open waits for it to close (a quest chain's next offer included). One already
--            on screen when such a window opens stays.
--   How      answer with 1-4, the mouse, or the controller's face buttons. Need a hint? (the
--            quest book, on a quest riddle) is H or the left shoulder, Read aloud is R or the right
--            shoulder, Later is L or D-pad left, and Skip is Backspace or Back. The riddle's buttons
--            are summons, so nothing captures the controller: every other button, Start included, is
--            the game's, as it would be without the addon. Esc steps the riddle aside into its pill
--            and still reaches the game, and the riddle sits under the game menu's strata, so Esc and
--            Start open the menu with one press. The open quest book scrolls with the wheel, the Up
--            and Down arrows, or the D-pad, a notch a press. Read aloud reads what the screen shows:
--            the riddle, the open quest book, or the feedback after an answer or a hint.
--   Aloud    the readAloud setting says riddles as they appear (kindergarten and grade 1 by
--            default), each choice with the key that picks it, and a hovered choice again. A heard
--            riddle (ScholarWords.heard) always says its word, and its button is Hear it again.
--            With no text-to-speech voice, nothing speaks and no heard riddle is asked.
--   Pause    after a miss, the answers left wait (the missPause setting: Pauses seconds, longer
--            each miss), their keycaps counting down, so the hint gets read before the next try. The
--            count runs only while the riddle shows: a fight that takes it away stops the count, and
--            it comes back with its hint and the seconds left. The seconds left and the misses that
--            lengthen each pause are saved (pauseLeft, pauseMisses) until a riddle is solved or
--            skipped, and so is the riddle itself, with its missed answers (the riddle row,
--            ScholarKeep.lua). A /reload, a relog, or the challenge switched off and on brings back
--            the same riddle, its hint, and the seconds left, so a child can't trade away a hard one.
--   Rewards  a star per riddle, streaks, scholar ranks, and difficulty that adapts within the
--            grade (math and reading only: a quest riddle never changes it).
--
-- Limits, honestly: it's a gate a child can step around, by design. It keeps what they do honest instead: a riddle put
-- off, or brought back by a /reload, is the same riddle, and the parent's report counts both. A determined child can
-- turn the addon off at character select. Blizzard's parental controls (play time limits) are the place for hard
-- limits. This is meant to be fun.

-- The screen's other actions: their controller buttons and keyboard keys.
local ActionKeys = { hint = "H", later = "L", skip = "Backspace", speak = "R" }

local ActionSources = { hint = "gamepad.leftShoulder", later = "gamepad.dpadLeft", skip = "gamepad.back",
    speak = "gamepad.rightShoulder", wishes = "gamepad.dpadRight" }

local AnswerSources = { "gamepad.south", "gamepad.east", "gamepad.west", "gamepad.north" }
local FinishDelay = 1.8
-- How long, in seconds, after losing control to look for a flight path (UnitOnTaxi).
local FlightCheck = 1
local KeyAnswers = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }
-- How many quest riddles come in a row before math or reading takes a turn.
local QuestShare = 2
local Ranks = { { 0, "Apprentice" }, { 10, "Journeyman" }, { 25, "Adept" }, { 50, "Sage" }, { 100, "Archmage" } }
-- The open quest book scrolls with the arrow keys and the D-pad, a notch a press.
local ScrollKeys = { DOWN = 1, UP = -1 }
local ScrollSources = { scrollDown = "gamepad.dpadDown", scrollUp = "gamepad.dpadUp" }
-- One math or reading riddle in StretchOdds is a stretch: a kind from a grade or two above, with extra help.
local StretchOdds = 5
-- Each riddle subject's switch row.
local SubjectRows = { math = "math", quest = "quests", reading = "reading" }
-- How long, in seconds, after a turn-in the onTurnIn moment waits, so QuestBook has noted it and the panel closed.
local TurnInDelay = 1

local ByteTerrace = ByteTerrace
local C_Sound = C_Sound
local C_TTSSettings = C_TTSSettings
local C_VoiceChat = C_VoiceChat
local floor = math.floor
local GetLocale = GetLocale
local GetMoney = GetMoney
local GetRealZoneText = GetRealZoneText
local GetTime = GetTime
local IsLoggedIn = IsLoggedIn
local issecretvalue = issecretvalue
local max = math.max
local min = math.min
local next = next
local random = math.random
local SOUNDKIT = SOUNDKIT
local UnitClass = UnitClass
local UnitFactionGroup = UnitFactionGroup
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitOnTaxi = UnitOnTaxi
local wipe = wipe

local Addon = ns.Addon
local Keep = ns.ScholarKeep
local Later = ns.ScholarLater
local Memory = ns.ScholarMemory
local Puzzles = ns.Puzzles
local QuestBook = ns.QuestBook
local ScholarSettings = ns.ScholarSettings
local LockedBy = ScholarSettings.LockedBy
local ScholarView = ns.ScholarView
local Skills = ns.ScholarSkills
local Windows = ns.ScholarWindows
local Words = ns.ScholarWords

-- Whether the play clock runs, which it does while no riddle is due, you're not AFK, and a subject is on.
local Counting = false
-- The riddle on screen (or waiting out a fight) until it's solved or skipped, how many of its tries missed (the hint's
-- rung), and which answers they picked ([i] = true), so a riddle that comes back keeps them.
local Current = nil
local LastSubject
local Missed = {}
-- The seconds the answers left wait after the first, second, and third miss, by the missPause setting.
local Pauses = { long = { 4, 7, 10 }, short = { 2, 4, 6 } }
-- The end of the file assigns the module.
local Scholar
-- The GetTime() the running stretch of play started at.
local SegmentStart
-- How many lines Say has said since load: the last one's turn.
local Turns = 0
-- The timer counting down the pause after a miss (the pauseLeft row) while the riddle shows.
local WaitTimer
-- What the Owl says as the riddle opens, once: a wink at a riddle a /reload or relog brought back (ScholarKeep.Winks).
local Wink = nil
local Wrongs = 0

-- Saves the running stretch of play into elapsed, keeping its fraction of a second running.
local function Bank()
    if Counting then
        local played = floor(GetTime() - SegmentStart)

        SegmentStart = (SegmentStart + played)
        Scholar:Set("elapsed", Scholar:Get("elapsed") + played)
    end
end

--- Returns whether the client has a text-to-speech voice to say a riddle with (probe tts.voices).
local function CanHear()
    return (next(C_VoiceChat.GetTtsVoices() or {}) ~= nil)
end

-- The child's own game, for personal word problems ("Tessa has 3 potions...").
local function Context()
    local name
    local class
    local rawName = UnitName("player")

    if not issecretvalue(rawName) then
        name = rawName
    end

    local _, rawClass = UnitClass("player")

    if not issecretvalue(rawClass) then
        class = rawClass
    end

    local faction = UnitFactionGroup("player")

    return {
        class = class,
        copper = GetMoney(),
        faction = ((not issecretvalue(faction) and faction) or nil),
        level = UnitLevel("player"),
        locale = GetLocale(),
        name = name,
        zone = GetRealZoneText(),
    }
end

-- The stars the current riddle is worth: two for a stretch.
local function Earned()
    return ((Current.stretch and 2) or 1)
end

-- Seconds of play toward the next riddle, the running stretch included.
local function Elapsed()
    local elapsed = Scholar:Get("elapsed")

    if Counting then
        elapsed = (elapsed + floor(GetTime() - SegmentStart))
    end

    return elapsed
end

-- Whether any subject is on.
local function HasSubject()
    return (Scholar:Get("math") or Scholar:Get("reading") or Scholar:Get("quests"))
end

-- The rung of the hint ladder the riddle is on, after Wrongs wrong tries: the strategy, then a worked first step, then
-- the answer with its working, whose button glows (its index is the third return). A stretch riddle starts a rung up.
local function Help()
    local rung = (Wrongs + ((Current.stretch and 1) or 0))

    if rung >= 3 then
        return "Here's how", Current.explanation, Current.answer
    elseif (rung == 2) and Current.step then
        return "Try this", Current.step
    end

    return "Hint", Current.hint
end

-- Need a hint? shows the rung the riddle is on. On a quest riddle, it opens (or closes) the quest book instead.
local function Hint()
    if Current and Current.book then
        ScholarView.ToggleBook()
    elseif Current and not Scholar:Get("solved") then
        ScholarView.Hint(Help())
    end
end

-- A riddle about a quest the player was shown, in QuestBook's order (fresh ones first, then the rest for review), or
-- nil when none is recorded. A quest no question fits counts as asked.
local function QuestPuzzle()
    local known = QuestBook.All()
    local byKey = {}
    local context = Context()

    for _, record in ipairs(known) do
        byKey[record.key] = record
    end

    for _, key in ipairs(QuestBook.Order()) do
        local puzzle = Puzzles.Generate({ context = context, known = known, quest = byKey[key], random = random,
            subject = "quest" })

        if puzzle then
            puzzle.questKey = key

            return puzzle
        end

        QuestBook.Asked(key)
    end

    return nil
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

-- What the screen shows about progress: stars, rank, the next rank and how far along, and the streak.
local function Progress(extra)
    local stars = Scholar:Get("stars")
    local info = { rank = Rank(stars), stars = stars, streak = Scholar:Get("streak") }

    for i, rank in ipairs(Ranks) do
        local nextRank = Ranks[i + 1]

        if (stars >= rank[1]) and nextRank and (stars < nextRank[1]) then
            info.nextRank, info.nextAt = nextRank[2], nextRank[1]
            info.progress = ((stars - rank[1]) / (nextRank[1] - rank[1]))
        end
    end

    for key, value in pairs(extra or {}) do
        info[key] = value
    end

    return info
end

--- Returns whether riddles are said aloud as they appear: the readAloud setting ("young" means kindergarten and grade
--- 1), when the client has a voice.
local function ReadsAloud()
    local mode = Scholar:Get("readAloud")

    return (CanHear() and ((mode == "always") or ((mode == "young") and (tonumber(Scholar:Get("grade")) <= 1))))
end

--- Says text aloud (what the screen shows: the riddle, the open quest book, or the feedback) with the player's
--- text-to-speech voice, rate, and volume.
---@return number turn this line's turn, which Turn() reports until something else is said
local function Say(text)
    Turns = (Turns + 1)

    C_VoiceChat.SpeakText(C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard), text, C_TTSSettings.GetSpeechRate(),
        C_TTSSettings.GetSpeechVolume(), false)

    return Turns
end

-- Summons one of the riddle's buttons, or dismisses it.
local function SetButton(active, source, command)
    if active then
        Addon.Input:Summon(Scholar, source, command)
    else
        Addon.Input:Dismiss(Scholar, source, command)
    end
end

-- Summons the riddle's own controller buttons (Input:Summon), or dismisses them. Nothing captures the controller, so
-- every other button, Start included, stays the game's, as it would without the addon. A focused question card would
-- capture them all, so the riddle lets go of it first: the card stays up, and Back focuses it again after.
local function SetButtons(active)
    if active then
        ns.Cards.Unfocus()
    end

    for i, source in ipairs(AnswerSources) do
        SetButton(active, source, "Scholar.answer" .. i)
    end

    for action, source in pairs(ActionSources) do
        SetButton(active, source, "Scholar." .. action)
    end

    for command, source in pairs(ScrollSources) do
        SetButton(active, source, "Scholar." .. command)
    end
end

-- Hides the riddle and gives input back, stopping the pause's count where it is. The riddle stays current until it's
-- solved.
local function Close()
    if ScholarView.IsShown() then
        Scholar:Cancel(WaitTimer)
        WaitTimer = nil
        ScholarView.Frame():EnableKeyboard(false)
        ScholarView.Hide()
        SetButtons(false)
    end
end

-- Ends the riddle, solved (after its celebration) or skipped. Either way, the timer and the pause start over.
local function Finish(solved)
    local before = Scholar:Get("stars")
    local earned = ((Current and Earned()) or 1)

    if Current and Current.questKey then
        QuestBook.Asked(Current.questKey, Current.kind)
    end

    Current, Wrongs = nil, 0
    wipe(Missed)
    Close()
    Scholar:Set("collapsed", false)
    Scholar:Set("riddle", "")
    Scholar:Set("pauseLeft", 0)
    Scholar:Set("pauseMisses", 0)
    Scholar:Set("solved", false)
    Scholar:Set("elapsed", 0)
    SegmentStart = GetTime()
    Scholar:Set("pending", false)

    -- A stretch's two stars can land past a rank's first star, so the rank before them is what counts.
    if solved and (Rank(before - earned) ~= Rank(before)) then
        ns.Cards.Show({ body = (before .. " stars of wisdom. The Owl Sage is proud of you!"),
            icon = "Interface\\Icons\\INV_Misc_Book_09", sound = SOUNDKIT.LFG_REWARDS,
            title = ("New rank: " .. Rank(before) .. "!") })
    end
end

local function Skip()
    if Current and not Scholar:Get("solved") and (Wrongs > 0) and (Scholar:Get("style") == "gentle") then
        Finish(false)
    end
end

local function Speak()
    if Current and ScholarView.IsShown() then
        Say(ScholarView.Speech())
    end
end

--- Returns the turn of the last line Say said, so a feature stops the voice only while its own line is the last.
local function Turn()
    return Turns
end

-- Whether a kept riddle can still be asked: its subject is on, and a heard one has a voice to hear it with.
local function Usable(puzzle)
    local row = SubjectRows[puzzle.subject]

    return ((row ~= nil) and Scholar:Get(row) and ((puzzle.speech == nil) or CanHear()))
end

-- Whether a controller with printed button names is connected.
local function UsingController()
    return (ByteTerrace.Input.LabelStyle() ~= "Generic")
end

-- The key for one of the screen's other actions (hint, speak, skip): its key, or its button's glyph, as the controller
-- UI draws it.
local function ActionLabel(action)
    if UsingController() then
        return ByteTerrace.Input.Prompt(ActionSources[action], 18)
    end

    return ActionKeys[action]
end

-- The key for answer i: 1-4, or the connected controller's face button's glyph.
local function KeyLabel(i)
    if UsingController() then
        return ByteTerrace.Input.Prompt(AnswerSources[i], 32)
    end

    return tostring(i)
end

-- The answers left on screen wait left seconds, counted down a second at a time on their keycaps and in pauseLeft.
-- Close stops the count where it is, for Open to take up again.
local function Wait(left)
    Scholar:Cancel(WaitTimer)
    WaitTimer = nil
    Scholar:Set("pauseLeft", left)
    ScholarView.Wait(left)

    if left > 0 then
        WaitTimer = Scholar:After(1, function()
            WaitTimer = nil
            Wait(left - 1)
        end)
    end
end

local function Choose(i)
    local buttons = (ScholarView.IsShown() and ScholarView.Frame().Buttons)

    if not Current or Scholar:Get("solved") or not buttons or (buttons[i] and not buttons[i]:IsEnabled()) then
        return
    end

    -- Each subject's level row is the difficulty its riddles are written at: a quest riddle never changes one.
    local adapts = ((Current.questKey == nil) and not Current.stretch)
    local firstTry = Memory.Record(Scholar, Current, i)
    local earned = Earned()
    local levelRow = (Current.subject .. "Level")
    local runRow = (Current.subject .. "Run")

    if i == Current.answer then
        -- The riddle stops being due now, so a /reload during the celebration doesn't ask another. The solved row holds
        -- the screen until Finish closes it.
        Scholar:Set("solved", true)
        Scholar:Set("pending", false)
        Scholar:Set("elapsed", 0)
        Scholar:Set("pauseMisses", 0)
        Scholar:Set("riddle", "")

        if Current.questKey then
            -- Marked answered, so a /reload in the celebration doesn't ask it again.
            QuestBook.Asked(Current.questKey, Current.kind)
        end

        local streak = (Scholar:Get("streak") + 1)

        Scholar:Set("streak", streak)
        Scholar:Set("stars", Scholar:Get("stars") + earned)
        local levelUp = false

        if adapts and firstTry then
            local run = (Scholar:Get(runRow) + 1)

            Scholar:Set(runRow, run)
            levelUp = (((run % 3) == 0) and (Scholar:Get(levelRow) < 3))

            if levelUp then
                Scholar:Set(levelRow, Scholar:Get(levelRow) + 1)
            end
        end

        -- Praise names the strategy on a first try, and the persistence after a miss.
        local praise = (((Wrongs == 0) and Current.praise) or Words.persistence[random(1, #Words.persistence)])

        ScholarView.Correct(i, (Current.explanation .. " " .. praise), Progress({ earned = earned, levelUp = levelUp }))
        C_Sound.PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
        Scholar:After(FinishDelay, function() Finish(true) end)
    else
        Wrongs = (Wrongs + 1)
        Missed[i] = true
        Keep.Save(Scholar, Current, Wrongs, Missed)
        Scholar:Set("streak", 0)

        if adapts then
            Scholar:Set(runRow, 0)
        end

        if adapts and (Wrongs == 2) and (Scholar:Get(levelRow) > 1) then
            Scholar:Set(levelRow, Scholar:Get(levelRow) - 1)
        end

        local label, help, reveal = Help()

        ScholarView.Wrong(i, Current.whys[i], label, help, Scholar:Get("style") == "gentle", reveal)
        -- The answers left wait, longer each miss since a riddle was last solved or skipped, so the hint gets read
        -- before the next try.
        local misses = (Scholar:Get("pauseMisses") + 1)

        Scholar:Set("pauseMisses", misses)
        Wait((Pauses[Scholar:Get("missPause")] or {})[min(misses, 3)] or 0)
    end
end

-- Shows the riddle and takes its keys (the rest reach the game) and the controller. Only ever called out of combat. A
-- riddle that comes back after a miss (from a fight, a /reload, or a relog) shows its hint's rung again, and its
-- answers wait out the pause's seconds left (pauseLeft).
local function Open()
    local frame = ScholarView.Show(Current, Progress({
        actions = { hint = ActionLabel("hint"), later = ActionLabel("later"), skip = ActionLabel("skip"),
            speak = ActionLabel("speak"), wishes = ActionLabel("wishes") },
        book = (Current.book ~= nil), canSkip = ((Scholar:Get("style") == "gentle") and (Wrongs > 0)), canSpeak = CanHear(),
        controller = UsingController(), gentle = (Scholar:Get("style") == "gentle"),
        keys = { KeyLabel(1), KeyLabel(2), KeyLabel(3), KeyLabel(4) }, reveal = (select(3, Help())), wrong = Missed,
    }))

    frame:EnableKeyboard(true)
    -- protected: Open only runs out of combat (see the combat rule)
    frame:SetPropagateKeyboardInput(false)
    SetButtons(true)
    C_Sound.PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)

    if Wrongs > 0 then
        ScholarView.Hint(Help())
    end

    -- The Owl's wink takes the banner. The hint is one press of H away.
    if Wink then
        ScholarView.Note(Wink)
        Wink = nil
    end

    if Scholar:Get("pauseLeft") > 0 then
        Wait(Scholar:Get("pauseLeft"))
    end

    -- A heard riddle always speaks. Any other speaks as readAloud says.
    if Current.speech or ReadsAloud() then
        Speak()
    end
end

-- The kinds in list that aren't in except.
local function Without(list, except)
    local skip = {}
    local out = {}

    for _, kind in ipairs(except) do
        skip[kind] = true
    end

    for _, kind in ipairs(list) do
        if not skip[kind] then
            out[#out + 1] = kind
        end
    end

    return out
end

-- The next riddle, or nil when there's nothing to ask. It prefers quest riddles: QuestShare of them in a row, then math
-- or reading takes a turn (alternating when both are on), whenever any of those is on.
local function NextPuzzle()
    local others = (Scholar:Get("math") or Scholar:Get("reading"))

    if Scholar:Get("quests") and ((Scholar:Get("questRun") < QuestShare) or not others) then
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

    if (#subjects == 2) and (LastSubject == subject) then
        subject = subjects[2]
    end

    LastSubject = subject
    local grade = tonumber(Scholar:Get("grade"))
    local known = QuestBook.All()
    local canHear = CanHear()
    local hasQuests = (#known > 0)
    -- A stretch asks a kind from a grade or two up that the child's own grade doesn't, at its easiest level.
    local stretch = ((grade < 6) and (random(1, StretchOdds) == 1))
    local asked = ((stretch and min(grade + random(1, 2), 6)) or grade)
    local kinds = Puzzles.Kinds(subject, asked, canHear, hasQuests)

    if stretch then
        local beyond = Without(kinds, Puzzles.Kinds(subject, grade, canHear, hasQuests))

        if #beyond == 0 then
            stretch, asked, kinds = false, grade, Puzzles.Kinds(subject, grade, canHear, hasQuests)
        else
            kinds = beyond
        end
    end

    local count = Scholar:Get(subject .. "Count")
    local kind = Skills.Choose(kinds, function(skill) return Memory.SkillOf(Scholar, skill) end, count, random)

    local puzzle = Puzzles.Generate({
        avoid = Memory.Recent(Scholar), context = Context(), fact = Memory.DueFact(Scholar, kind, count), grade = asked, kind = kind,
        known = known, level = ((stretch and 1) or Scholar:Get(subject .. "Level")), random = random, subject = subject,
    })

    puzzle.stretch = (stretch or nil)
    Memory.Remember(Scholar, puzzle)

    return puzzle
end

-- Asks the next riddle and keeps it (ScholarKeep), so a /reload brings back the same one.
local function Ask()
    local puzzle = NextPuzzle()

    if puzzle then
        Keep.Save(Scholar, puzzle, 0, Missed)
    end

    return puzzle
end

ScholarView.Init({
    choose = function(i) Addon:Batch(Choose, i) end,
    hint = Hint,
    hover = function(i)
        local said = ((ReadsAloud() or (Current and Current.speakChoices)) and ScholarView.SpokenChoice(i))

        if said then
            Say(said)
        end
    end,
    key = function(key)
        if KeyAnswers[key] then
            Addon:Batch(Choose, KeyAnswers[key])
        elseif key == "BACKSPACE" then
            Addon:Batch(Skip)
        elseif key == "ESCAPE" then
            -- Esc is the game's: the riddle steps out of the game menu's way, and the key goes on to open it.
            Addon.Commands:Run("Scholar.later")

            return false
        elseif key == "H" then
            Hint()
        elseif key == "L" then
            Addon.Commands:Run("Scholar.later")
        elseif key == "R" then
            Speak()
        elseif ScrollKeys[key] then
            ScholarView.ScrollBook(ScrollKeys[key])
        else
            return false
        end

        return true
    end,
    later = function() Addon.Commands:Run("Scholar.later") end,
    skip = function() Addon:Batch(Skip) end,
    speak = Speak,
    wishes = function() ns.ScholarWishes.Open() end,
})

local Commands = {
    { label = "Show Scholar stars and the next riddle", name = "status",
        run = function()
            local stars = Scholar:Get("stars")
            local left = ((Scholar:Get("interval") * 60) - Elapsed())
            local due = "The Owl Sage has a riddle for you right now!"

            if not Scholar:Get("pending") then
                due = ("Next riddle in about %d min."):format(max(math.ceil(left / 60), 1))
            end

            Addon:Print(("Stars: %d (%s). %d to spend. %s"):format(stars, Rank(stars), ns.ScholarWishes.Balance(), due))
        end,
        slash = "scholar" },
    { label = "Parents: show Scholar's report card", name = "report",
        run = function()
            for _, line in ipairs(Memory.Report(Scholar)) do
                Addon:Print(line)
            end
        end,
        slash = "report" },
    { label = "Solve a riddle right now", name = "practice",
        run = function()
            Scholar:Set("collapsed", false)
            Scholar:Set("pending", true)
        end,
        slash = "puzzle" },
}

for _, command in ipairs(ns.ScholarLock.Commands) do
    Commands[#Commands + 1] = command
end

for _, command in ipairs(Later.Commands) do
    Commands[#Commands + 1] = command
end

-- D-pad right on the riddle screen and its waiting pill (ScholarWishes.lua loads after this file).
Commands[#Commands + 1] = { label = "Open the wishes window", name = "wishes", run = function() ns.ScholarWishes.Open() end }

for i = 1, 4 do
    Commands[#Commands + 1] = { label = ("Choose answer " .. i), name = ("answer" .. i), run = function() Choose(i) end }
end

Commands[#Commands + 1] = { label = "Show the riddle's hint", name = "hint", run = function() Hint() end }
Commands[#Commands + 1] = { label = "Read the riddle aloud", name = "speak", run = function() Speak() end }
Commands[#Commands + 1] = { label = "Skip the riddle (Gentle mode, after a try)", name = "skip", run = function() Skip() end }

Commands[#Commands + 1] = { label = "Scroll the quest book up", name = "scrollUp",
    run = function() ScholarView.ScrollBook(-1) end }

Commands[#Commands + 1] = { label = "Scroll the quest book down", name = "scrollDown",
    run = function() ScholarView.ScrollBook(1) end }

Scholar = Addon:Module("Scholar", {
    commands = Commands,
    default = false,
    description = ("Riddles for young players about their own quests, and math and reading, every so often and "
        .. "at level-ups. Per character; off unless a parent turns it on."),
    label = "Scholar's challenge",
    lockedBy = LockedBy,
    OnDisable = function(module)
        if module:Get("solved") then
            -- The celebration's timer stops with the module, but the rank card still shows.
            Finish(true)
        end

        -- A riddle still due when the challenge comes back on keeps its pause (pauseLeft, pauseMisses), and the riddle
        -- itself comes back from the riddle row.
        Current, Wrongs, WaitTimer = nil, 0, nil
        wipe(Missed)
        Windows.Clear(module)
        Close()
        Later.Stop()
        module:Set("collapsed", false)
        Bank()
        Counting = false
    end,
    OnEnable = function(module)
        -- A parent's unlock lasts the session: a /reload keeps it, while a new login or switching the challenge back on
        -- mid-session locks again.
        if IsLoggedIn() then
            module:Set("unlocked", false)
        end

        module:Set("locked", (module:Get("pin") ~= 0) and not module:Get("unlocked"))

        -- The riddle kept when the challenge last stopped (a /reload, a relog, or switched off) comes back the same
        -- while it's still due, unless its subject was switched off or it's heard and there's no voice.
        local kept, wrongs, missed = Keep.Take(module)

        if kept and module:Get("pending") and Usable(kept) then
            Current, Wrongs, Missed = kept, wrongs, missed

            -- Before login is a /reload or a relog. After it, the challenge was switched back on.
            if not IsLoggedIn() then
                module:Set("returnCount", module:Get("returnCount") + 1)
                Wink = Keep.Winks[random(1, #Keep.Winks)]
            end
        elseif kept then
            module:Set("riddle", "")
        end

        module:On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
            if isInitialLogin then
                module:Set("unlocked", false)
                module:Set("locked", module:Get("pin") ~= 0)
            end

            -- A loading screen closes them all.
            Windows.Clear(module)
        end)

        local pending = module:Id("pending")
        local solved = module:Id("solved")
        local combat = module:Id("combat.active")
        local afk = module:Id("afk.active")
        local mathOn = module:Id("math")
        local readingOn = module:Id("reading")
        local questsOn = module:Id("quests")
        local window = module:Id("window")
        local collapsed = module:Id("collapsed")

        Later.Start(module)

        -- Blizzard's windows a riddle waits for (see the header).
        Windows.Start(module)

        -- The play clock counts toward the next riddle while none is due, you're not AFK, and a subject is on. It
        -- writes nothing while it runs: one timer fires when the interval is up, and play is saved when the clock
        -- stops, at logout, and as the module stops.
        local due

        local function Schedule()
            module:Cancel(due)
            due = nil

            if Counting then
                due = module:After(max((module:Get("interval") * 60) - Elapsed(), 0), function()
                    Bank()
                    module:Set("pending", true)
                end)
            end
        end

        module:Rule({
            changed = function(counting)
                Bank()
                Counting, SegmentStart = counting, GetTime()
                Schedule()
            end,
            initial = true, reads = { pending, afk, mathOn, readingOn, questsOn },
            when = function(state)
                return (not state.Values[pending] and not state.Values[afk]
                    and (state.Values[mathOn] or state.Values[readingOn] or state.Values[questsOn]))
            end,
        })

        module:Watch({ "interval", "elapsed" }, Schedule, true)
        module:On("PLAYER_LOGOUT", Bank)

        module:On("PLAYER_LEVEL_UP", function()
            if module:Get("onLevelUp") then
                module:Set("pending", true)
            end
        end)

        -- A good moment brings the next riddle forward once it's half due: the play clock counting, and half the
        -- interval played.
        local function Moment(row)
            if module:Get(row) and Counting and ((Elapsed() * 2) >= (module:Get("interval") * 60)) then
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

        -- A riddle shows when one is due and there's no fight and none of Blizzard's windows is open. A celebration a
        -- fight cut short doesn't come back: Finish ends it. One already on screen stays when a window opens: only the
        -- rule below closes it.
        module:Rule({
            changed = function(show, state)
                if not show or state.Values[solved] or ScholarView.IsShown() then
                    return
                end

                Current = (Current or Ask())

                if Current then
                    Open()
                elseif not HasSubject() then
                    module:Set("pending", false)
                -- Otherwise the riddle waits for a quest to ask about.
                end
            end,
            initial = true, reads = { pending, solved, combat, window, collapsed },
            when = function(state)
                return ((state.Values[pending] or state.Values[solved]) and not state.Values[combat]
                    and not state.Values[window] and not state.Values[collapsed])
            end,
        })

        -- A fight sends the riddle away until it ends, and Later until it's opened again.
        module:Rule({
            changed = function(allowed)
                if not allowed then
                    Close()
                end
            end,
            reads = { pending, solved, combat, collapsed },
            when = function(state)
                return ((state.Values[pending] or state.Values[solved]) and not state.Values[combat]
                    and not state.Values[collapsed])
            end,
        })

        -- A riddle that came due with nothing to ask waits: a new quest, or a subject switched on, gives it one.
        module:Watch({ "QuestBook.quests", mathOn, readingOn, questsOn }, function(state)
            if state.Values[pending] and not Current and not state.Values[solved] and not state.Values[combat]
                and not state.Values[window] then
                Current = Ask()

                if Current then
                    Open()
                elseif not HasSubject() then
                    module:Set("pending", false)
                end
            end
        end, true)
    end,
    page = "Scholar's challenge",
    records = Memory.Records,
    scope = "character",
    state = ScholarSettings.Rows,
    uses = { "QuestBook" },
})

-- Scholar's voice, for the other features that speak to a young scholar (QuestProgress.lua's QuestCount and
-- QuestReader.lua).
ns.ScholarVoice = { CanHear = CanHear, ReadsAloud = ReadsAloud, Say = Say, Turn = Turn }
