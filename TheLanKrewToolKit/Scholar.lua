local addonName, ns = ...

-- Scholar's challenge: riddles for young players about their own quests, and math and reading, set up by a parent.
--
-- Off by default and per character: a parent turns it on for a child's character, picks a grade, and can lock the
-- settings with a PIN (/tlk lock 1234; /tlk unlock 1234 for the session). While locked the PIN can't be changed, and
-- after three wrong PINs unlocking waits a minute.
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
--            Never over Blizzard's windows either: one that comes due while a quest dialog,
--            gossip, a vendor, the mailbox, a bank, the auction house, a trainer or the flight
--            map is open waits for it to close (a quest chain's next offer included). One already
--            on screen when such a window opens stays.
--   How      answer with 1-4, a click, or the controller's face buttons; Need a hint? (the quest
--            book, on a quest riddle) is H or the left shoulder, Read aloud is R or the right
--            shoulder, Skip is Esc or Back. The open quest book scrolls with the wheel, the Up and
--            Down arrows or the D-pad. Read aloud reads what the screen shows: the riddle, the
--            open quest book, or the feedback after an answer or a hint.
--   Aloud    the readAloud setting says riddles as they appear (kindergarten and grade 1 by
--            default), each choice with the key that picks it, and a hovered choice again. A heard
--            riddle (ScholarWords.heard) always says its word, and its button is Hear it again.
--            With no text-to-speech voice, nothing speaks and no heard riddle is asked.
--   Rewards  a star per riddle, streaks, scholar ranks, and difficulty that adapts within the
--            grade (math and reading only: a quest riddle never changes it).
--
-- Limits, honestly: a controller's sticks still move the character, and a determined child can turn the addon off at
-- character select. Blizzard's parental controls (play time limits) are the place for hard limits; this is meant to be
-- fun.

-- The screen's other actions: their controller buttons and keyboard keys.
local ActionKeys = { hint = "H", skip = "Esc", speak = "R" }
local ActionSources = { hint = "gamepad.leftShoulder", skip = "gamepad.back", speak = "gamepad.rightShoulder" }
local AnswerSources = { "gamepad.south", "gamepad.east", "gamepad.west", "gamepad.north" }
local FinishDelay = 1.8
-- How long, in seconds, after losing control to look for a flight path (UnitOnTaxi).
local FlightCheck = 1
-- The windows Blizzard's interaction manager opens that a riddle waits for (by Enum.PlayerInteractionType name); the
-- quest dialog and gossip have their own events.
local HeldInteractions = {}
local KeyAnswers = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }
local LockedBy = "Scholar.locked"
local MaxPinMisses = 3
-- How many recent misses the report shows.
local MissesKept = 5
-- The longest prompt, in bytes, a recent miss keeps, on one line.
local MissPrompt = 160
local PinWaitSeconds = 60
-- How many quest riddles come in a row before math or reading takes a turn.
local QuestShare = 2
local Ranks = { { 0, "Apprentice" }, { 10, "Journeyman" }, { 25, "Adept" }, { 50, "Sage" }, { 100, "Archmage" } }
-- The open quest book scrolls with the arrow keys and the D-pad; held, the D-pad keeps going.
local ScrollKeys = { DOWN = 1, UP = -1 }
-- How long, in seconds, between notches while a D-pad direction is held.
local ScrollRepeat = 0.12
local ScrollSources = { scrollDown = "gamepad.dpadDown", scrollUp = "gamepad.dpadUp" }
-- How long, in seconds, after a turn-in the onTurnIn moment waits, so QuestBook has noted it and the panel closed.
local TurnInDelay = 1

for _, name in ipairs({ "Merchant", "MailInfo", "Banker", "CharacterBanker", "AccountBanker", "GuildBanker",
    "Auctioneer", "Trainer", "TaxiNode" }) do
    HeldInteractions[Enum.PlayerInteractionType[name]] = true
end

-- The events that open (true) and close (false) the quest dialog and gossip, as Blizzard's QuestFrame and gossip frame
-- read them.
local DialogEvents = {
    GOSSIP_CLOSED = { "gossip", false }, GOSSIP_SHOW = { "gossip", true }, QUEST_COMPLETE = { "quest", true },
    QUEST_DETAIL = { "quest", true }, QUEST_FINISHED = { "quest", false }, QUEST_GREETING = { "quest", true },
    QUEST_PROGRESS = { "quest", true },
}

-- The taxi node's map also closes with TAXIMAP_CLOSED.
local TaxiNode = Enum.PlayerInteractionType.TaxiNode

local byte, floor, issecretvalue, max, min, random, wipe = string.byte, math.floor, issecretvalue, math.max, math.min, math.random, wipe
local ByteTerrace = ByteTerrace
local C_Sound, C_TTSSettings, C_VoiceChat, GetMoney = C_Sound, C_TTSSettings, C_VoiceChat, GetMoney
local GetLocale, GetRealZoneText, GetServerTime, GetTime = GetLocale, GetRealZoneText, GetServerTime, GetTime
local IsLoggedIn, UnitFactionGroup, UnitOnTaxi = IsLoggedIn, UnitFactionGroup, UnitOnTaxi
local next = next
local SOUNDKIT, UnitClass, UnitLevel, UnitName = SOUNDKIT, UnitClass, UnitLevel, UnitName

local Addon = ns.Addon
local Puzzles = ns.Puzzles
local QuestBook = ns.QuestBook
local ScholarView = ns.ScholarView
local Skills = ns.ScholarSkills

local GradeLabels, GradeValues = {}, {}

for _, grade in ipairs(Puzzles.Grades) do
    local id = tostring(grade.id)

    GradeValues[#GradeValues + 1] = id
    GradeLabels[id] = grade.label
end

-- Whether the play clock runs, which it does while no riddle is due, you're not AFK, and a subject is on.
local Counting = false
-- The riddle on screen (or waiting out a fight) until it's solved or skipped, how many tries missed, and which answers
-- they picked ([i] = true), so a riddle that comes back keeps them.
local Current, Missed, Wrongs = nil, {}, 0
local LastSubject
-- The module is assigned at the end of the file.
local Scholar
-- The GetTime() the running stretch of play started at.
local SegmentStart
-- Blizzard's windows open now that a riddle waits for: "quest", "gossip" and interaction types.
local Windows = {}

-- Saves the running stretch of play into elapsed, keeping its fraction of a second running.
local function Bank()
    if Counting then
        local played = floor(GetTime() - SegmentStart)

        SegmentStart = (SegmentStart + played)
        Scholar:Set("elapsed", Scholar:Get("elapsed") + played)
    end
end

-- Whether the client has a text-to-speech voice to say a riddle with (probe tts.voices).
local function CanHear()
    return (next(C_VoiceChat.GetTtsVoices() or {}) ~= nil)
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

-- Need a hint? shows the hint; on a quest riddle it opens (or closes) the quest book instead.
local function Hint()
    if Current and Current.book then
        ScholarView.ToggleBook()
    elseif Current and not Scholar:Get("solved") then
        ScholarView.Hint(Current.hint)
    end
end

-- Kid-proofing, not security: a small hash so the PIN isn't sitting in the SavedVariables as-is.
local function PinHash(pin)
    local hash = 5381
    local text = ("tlk:" .. pin)

    for i = 1, #text do
        hash = (((hash * 33) + byte(text, i)) % 2147483647)
    end

    return hash
end

-- A riddle about a quest the player was shown, in QuestBook's order (fresh ones first, then the rest for review), or
-- nil when none is recorded. A quest no question fits counts as asked.
local function QuestPuzzle()
    local known, byKey, context = QuestBook.All(), {}, Context()

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

-- Ends the riddle, solved (after its celebration) or skipped; either way the timer starts over.
local function Finish(solved)
    local before = Scholar:Get("stars")

    if Current and Current.questKey then
        QuestBook.Asked(Current.questKey, Current.kind)
    end

    Current, Wrongs = nil, 0
    wipe(Missed)
    Close()
    Scholar:Set("solved", false)
    Scholar:Set("elapsed", 0)
    SegmentStart = GetTime()
    Scholar:Set("pending", false)

    if solved and (Rank(before - 1) ~= Rank(before)) then
        ns.Cards.Show({ body = (before .. " stars of wisdom. The Owl Sage is proud of you!"),
            icon = "Interface\\Icons\\INV_Misc_Book_09", sound = SOUNDKIT.LFG_REWARDS,
            title = ("New rank: " .. Rank(before) .. "!") })
    end
end

-- What the screen shows about progress: stars, rank, the next rank and how far along, the streak.
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

-- Whether riddles are said aloud as they appear: the readAloud setting ("young" means kindergarten and grade 1), when
-- the client has a voice.
local function ReadsAloud()
    local mode = Scholar:Get("readAloud")

    return (CanHear() and ((mode == "always") or ((mode == "young") and (tonumber(Scholar:Get("grade")) <= 1))))
end

-- Reads what the screen shows aloud (the riddle, the open quest book, or the feedback) with the player's text-to-speech
-- voice, rate and volume. Says text with the player's text-to-speech voice, rate and volume.
local function Say(text)
    C_VoiceChat.SpeakText(C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard), text, C_TTSSettings.GetSpeechRate(),
        C_TTSSettings.GetSpeechVolume(), false)
end

-- A Blizzard window opened (open) or closed: window is whether any a riddle waits for is open.
local function SetWindow(name, open)
    Windows[name] = (open or nil)
    Scholar:Set("window", next(Windows) ~= nil)
end

local function OnInteractionHidden(interaction)
    SetWindow(interaction, false)
end

local function OnInteractionShown(interaction)
    if HeldInteractions[interaction] then
        SetWindow(interaction, true)
    end
end

-- A skill's record (ScholarSkills), with every field filled in.
local function SkillOf(kind)
    return (Scholar.Records.skills:Get(kind) or { asked = 0, box = 1, due = 0, firstTry = 0, lastAt = 0, recent = "" })
end

-- The next riddle. Quest riddles are preferred: QuestShare of them in a row, then math or reading takes a turn
-- (alternating when both are on), whenever any of those is on. nil when there's nothing to ask.
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
    local kind = Skills.Choose(Puzzles.Kinds(subject, grade, CanHear()), SkillOf, Scholar:Get(subject .. "Count"), random)

    return Puzzles.Generate({
        context = Context(), grade = grade, kind = kind, level = Scholar:Get(subject .. "Level"), random = random,
        subject = subject,
    })
end

-- Records the riddle's first try, once: its skill's record moves (ScholarSkills.Next), a math or reading riddle counts
-- toward its subject's due clock, and a miss joins the report's recent misses. Returns whether this was the first try.
local function RecordFirstTry(i)
    if Current.recorded then
        return false
    end

    Current.recorded = true
    local right, count = (i == Current.answer), 0

    if Current.subject ~= "quest" then
        count = (Scholar:Get(Current.subject .. "Count") + 1)
        Scholar:Set(Current.subject .. "Count", count)
    end

    local now = GetServerTime()

    Scholar.Records.skills:Set(Current.kind, Skills.Next(SkillOf(Current.kind), right, count, now))

    if not right then
        local seq = (Scholar:Get("missCount") + 1)

        Scholar:Set("missCount", seq)

        Scholar.Records.misses:Set(tostring(seq), {
            at = now, chosen = (Current.choices[i] or ""), kind = Current.kind,
            prompt = Current.prompt:gsub("%s+", " "):sub(1, MissPrompt), right = Current.choices[Current.answer], seq = seq,
        })
    end

    return true
end

local function Choose(i)
    local buttons = (ScholarView.IsShown() and ScholarView.Frame().Buttons)

    if not Current or Scholar:Get("solved") or not buttons or (buttons[i] and not buttons[i]:IsEnabled()) then
        return
    end

    -- Each subject's level row is the difficulty its riddles are written at: a quest riddle never changes one.
    local adapts = (Current.questKey == nil)
    local firstTry = RecordFirstTry(i)
    local levelRow, runRow = (Current.subject .. "Level"), (Current.subject .. "Run")

    if i == Current.answer then
        -- The riddle stops being due now, so a /reload during the celebration doesn't ask another; solved holds the
        -- screen until Finish closes it.
        Scholar:Set("solved", true)
        Scholar:Set("pending", false)
        Scholar:Set("elapsed", 0)

        if Current.questKey then
            -- Marked answered, so a /reload in the celebration doesn't ask it again.
            QuestBook.Asked(Current.questKey, Current.kind)
        end

        local streak = (Scholar:Get("streak") + 1)

        Scholar:Set("streak", streak)
        Scholar:Set("stars", Scholar:Get("stars") + 1)
        local levelUp = false

        if adapts and firstTry then
            local run = (Scholar:Get(runRow) + 1)

            Scholar:Set(runRow, run)
            levelUp = (((run % 3) == 0) and (Scholar:Get(levelRow) < 3))

            if levelUp then
                Scholar:Set(levelRow, Scholar:Get(levelRow) + 1)
            end
        end

        ScholarView.Correct(i, Current.explanation, Progress({ earned = 1, levelUp = levelUp }))
        C_Sound.PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
        Scholar:After(FinishDelay, function() Finish(true) end)
    else
        Wrongs = (Wrongs + 1)
        Missed[i] = true
        Scholar:Set("streak", 0)

        if adapts then
            Scholar:Set(runRow, 0)
        end

        if adapts and (Wrongs == 2) and (Scholar:Get(levelRow) > 1) then
            Scholar:Set(levelRow, Scholar:Get(levelRow) - 1)
        end

        ScholarView.Wrong(i, Current.hint, Scholar:Get("mode") == "gentle")
    end
end

local function Skip()
    if Current and not Scholar:Get("solved") and (Wrongs > 0) and (Scholar:Get("mode") == "gentle") then
        Finish(false)
    end
end

local function Speak()
    if Current and ScholarView.IsShown() then
        Say(ScholarView.Speech())
    end
end

-- Whether a controller with printed button names is connected.
local function UsingController()
    return (ByteTerrace.Input.LabelStyle() ~= "Generic")
end

-- The key for one of the screen's other actions (hint, speak, skip).
local function ActionLabel(action)
    if UsingController() then
        return ByteTerrace.Input.Label(ActionSources[action])
    end

    return ActionKeys[action]
end

-- The key for answer i: 1-4, or the connected controller's face button.
local function KeyLabel(i)
    if UsingController() then
        return ByteTerrace.Input.Label(AnswerSources[i])
    end

    return tostring(i)
end

-- Shows the riddle and takes the keyboard and controller. Only ever called out of combat.
local function Open()
    local frame = ScholarView.Show(Current, Progress({
        actions = { hint = ActionLabel("hint"), skip = ActionLabel("skip"), speak = ActionLabel("speak") },
        book = (Current.book ~= nil), canSkip = ((Scholar:Get("mode") == "gentle") and (Wrongs > 0)), canSpeak = CanHear(),
        controller = UsingController(), gentle = (Scholar:Get("mode") == "gentle"),
        keys = { KeyLabel(1), KeyLabel(2), KeyLabel(3), KeyLabel(4) }, wrong = Missed,
    }))

    frame:EnableKeyboard(true)
    -- protected: Open only runs out of combat (see the combat rule)
    frame:SetPropagateKeyboardInput(false)
    Addon.Input:SetActiveMaps({ "scholar" })
    C_Sound.PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)

    -- A heard riddle always speaks; any other as readAloud says.
    if Current.speech or ReadsAloud() then
        Speak()
    end
end

local function ValidPin(pin)
    return (pin and (pin:match("^%d%d%d%d%d?%d?%d?%d?$") ~= nil))
end

ScholarView.Init({
    choose = function(i) Addon:Batch(Choose, i) end,
    hint = Hint,
    hover = function(i)
        local said = (ReadsAloud() and ScholarView.SpokenChoice(i))

        if said then
            Say(said)
        end
    end,
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
    skip = function() Addon:Batch(Skip) end,
    speak = Speak,
})

local Rows = {
    { default = "2",
        description = "The school grade riddles are written for. Difficulty also adapts to how it's going.",
        kind = "string", label = "Grade", lockedBy = LockedBy, name = "grade", scope = "character", section = "Riddles",
        valueLabels = GradeLabels, values = GradeValues },
    { default = true, description = "Counting, arithmetic, times tables, fractions and more, by grade.",
        kind = "boolean", label = "Math riddles", lockedBy = LockedBy, name = "math", scope = "character" },
    { default = true, description = "Rhymes, spelling, word scrambles, vocabulary and short stories, by grade.",
        kind = "boolean", label = "Reading riddles", lockedBy = LockedBy, name = "reading", scope = "character" },
    { default = true,
        description = ("Questions about the quests your child accepts and turns in: who, where, what they asked, "
            .. "and their text. Two of every three riddles are about quests, the newest first, then older ones for "
            .. "review; the quest book on the riddle screen holds every answer."),
        kind = "boolean", label = "Quest riddles", lockedBy = LockedBy, name = "quests", scope = "character" },
    { default = "young",
        description = ("Says each riddle and its choices aloud as it appears, with your text-to-speech voice, for a child "
            .. "still learning to read. Hovering a choice says it again. Riddles you only hear always speak."),
        kind = "string", label = "Read riddles aloud", lockedBy = LockedBy, name = "readAloud", scope = "character",
        valueLabels = { always = "Always", off = "Only when asked", young = "For kindergarten and grade 1" },
        values = { "young", "always", "off" } },
    { default = 30, description = "Minutes of play between riddles.", kind = "number",
        label = "Minutes between riddles", lockedBy = LockedBy, max = 120, min = 10, name = "interval",
        scope = "character", section = "When", step = 5 },
    { default = true, description = "Earn each new level with a little wisdom, too.", kind = "boolean",
        label = "A riddle at every level-up", lockedBy = LockedBy, name = "onLevelUp", scope = "character" },
    { default = true,
        description = "A flight is free time: once half the minutes are played, it brings the next riddle.",
        kind = "boolean", label = "Riddles on flight paths", lockedBy = LockedBy, name = "onFlight", scope = "character" },
    { default = true,
        description = "Once half the minutes are played, turning in a quest brings a riddle about it, while it's fresh.",
        kind = "boolean", label = "Riddles when a quest is turned in", lockedBy = LockedBy, name = "onTurnIn",
        scope = "character" },
    { default = true, description = "Once half the minutes are played, a death brings the next riddle.",
        kind = "boolean", label = "Riddles while dead", lockedBy = LockedBy, name = "onDeath", scope = "character" },
    { default = "gate", description = "Whether a riddle must be solved, or can be skipped after one try.",
        kind = "string", label = "Riddle style", lockedBy = LockedBy, name = "mode", scope = "character",
        valueLabels = { gate = "Solve to keep playing", gentle = "Gentle (Skip after one try)" },
        values = { "gate", "gentle" } },
    -- Progress, per character. elapsed is seconds of play toward the next riddle; questRun the quest riddles asked
    -- since math or reading last took a turn.
    { default = 0, kind = "number", name = "stars", scope = "character" },
    { default = 0, kind = "number", name = "streak", scope = "character" },
    -- Each subject's difficulty (1 to 3), its first-try rights in a row (every third makes it harder), and how many of
    -- its riddles were answered (the clock its skills come due by, ScholarSkills).
    { default = 1, kind = "number", max = 3, min = 1, name = "mathLevel", scope = "character" },
    { default = 0, kind = "number", min = 0, name = "mathRun", scope = "character", step = 1 },
    { default = 0, kind = "number", min = 0, name = "mathCount", scope = "character", step = 1 },
    { default = 1, kind = "number", max = 3, min = 1, name = "readingLevel", scope = "character" },
    { default = 0, kind = "number", min = 0, name = "readingRun", scope = "character", step = 1 },
    { default = 0, kind = "number", min = 0, name = "readingCount", scope = "character", step = 1 },
    -- How many first tries have missed, which numbers the report's recent misses.
    { default = 0, kind = "number", min = 0, name = "missCount", scope = "character", step = 1 },
    { default = 0, kind = "number", name = "elapsed", scope = "character" },
    { default = false, kind = "boolean", name = "pending", scope = "character" },
    { default = 0, kind = "number", min = 0, name = "questRun", scope = "character", step = 1 },
    -- The riddle on screen was just solved: its celebration holds the screen until Finish.
    { default = false, kind = "boolean", name = "solved", persist = false },
    -- One of Blizzard's windows a riddle waits for is open (Windows).
    { default = false, kind = "boolean", name = "window", persist = false },
    -- The parent's PIN (a hash; 0 = none), account-wide, and whether settings are locked right now.
    { default = 0, kind = "number", lockedBy = LockedBy, name = "pin" },
    { default = false, kind = "boolean", name = "locked", persist = false },
    -- The parent unlocked this session: saved, so a /reload keeps it; the next login locks again.
    { default = false, kind = "boolean", name = "unlocked" },
    -- Wrong unlock PINs since the last wait, and the server time unlocking waits until. Saved, so a /reload doesn't buy
    -- more tries.
    { default = 0, kind = "number", name = "pinMisses" },
    { default = 0, kind = "number", name = "pinWait" },
}

-- What Scholar remembers per character for the report and the review schedule (ScholarSkills): a record per skill, and
-- the last MissesKept first tries that missed.
local Records = {
    {
        evict = "lastAt",
        fields = {
            { default = 0, kind = "number", min = 0, name = "asked", step = 1 },
            { default = 1, kind = "number", max = Skills.Boxes, min = 1, name = "box", step = 1 },
            { default = 0, kind = "number", min = 0, name = "due", step = 1 },
            { default = 0, kind = "number", min = 0, name = "firstTry", step = 1 },
            { default = 0, kind = "number", min = 0, name = "lastAt" },
            { default = "", kind = "string", name = "recent" },
        },
        limit = 64, name = "skills", scope = "character",
    },
    {
        evict = "seq",
        fields = {
            { default = 0, kind = "number", min = 0, name = "at" },
            { default = "", kind = "string", name = "chosen" },
            { default = "", kind = "string", name = "kind" },
            { default = "", kind = "string", name = "prompt" },
            { default = "", kind = "string", name = "right" },
            { default = 0, kind = "number", min = 0, name = "seq", step = 1 },
        },
        limit = MissesKept, name = "misses", scope = "character",
    },
}

-- The parent's report card, as chat lines (ScholarSkills.Report): each subject's skills by their records, the levels,
-- and the recent misses, newest first.
local function ReportLines()
    local skills = Scholar.Records.skills

    local sections = {
        { label = "Math", level = Scholar:Get("mathLevel"), records = {}, subject = "math" },
        { label = "Reading", level = Scholar:Get("readingLevel"), records = {}, subject = "reading" },
        { label = "Quests", records = {}, subject = "quest" },
    }

    for _, kind in ipairs(skills:Keys()) do
        for _, section in ipairs(sections) do
            if kind:find(section.subject .. ".", 1, true) == 1 then
                section.records[kind] = skills:Get(kind)
            end
        end
    end

    local misses = {}

    for _, key in ipairs(Scholar.Records.misses:Keys()) do
        misses[#misses + 1] = Scholar.Records.misses:Get(key)
    end

    table.sort(misses, function(a, b) return (a.seq > b.seq) end)

    return Skills.Report(ByteTerrace.Names.Mine(), sections, misses)
end

local Commands = {
    { label = "Show Scholar stars and the next riddle", name = "status",
        run = function()
            local stars = Scholar:Get("stars")
            local left = ((Scholar:Get("interval") * 60) - Elapsed())
            local minutes = (((left > 0) and math.ceil(left / 60)) or 0)

            Addon:Print(("Stars: %d (%s). Next riddle in about %d min."):format(stars, Rank(stars), minutes))
        end,
        slash = "scholar" },
    { label = "Parents: show Scholar's report card", name = "report",
        run = function()
            for _, line in ipairs(ReportLines()) do
                Addon:Print(line)
            end
        end,
        slash = "report" },
    { label = "Solve a riddle right now", name = "practice",
        run = function()
            Scholar:Set("pending", true)
        end,
        slash = "puzzle" },
    { label = "Parents: lock Scholar settings with a PIN (lock <pin>)", name = "lock",
        run = function(pin)
            if Scholar:Get("locked") then
                Addon:Print("Scholar settings are locked. Unlock them first to change the PIN.")
            elseif (Scholar:Get("pin") ~= 0) and not pin then
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
        end,
        slash = "lock" },
    { label = "Parents: unlock Scholar settings (unlock <pin>)", name = "unlock",
        run = function(pin)
            local wait = (Scholar:Get("pinWait") - GetServerTime())

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
            elseif (Scholar:Get("pinMisses") + 1) >= MaxPinMisses then
                Scholar:Set("pinMisses", 0)
                Scholar:Set("pinWait", GetServerTime() + PinWaitSeconds)
                Addon:Print(("That PIN isn't right. Try again in %d seconds."):format(PinWaitSeconds))
            else
                Scholar:Set("pinMisses", Scholar:Get("pinMisses") + 1)
                Addon:Print("That PIN isn't right.")
            end
        end,
        slash = "unlock" },
}

for i = 1, 4 do
    Commands[#Commands + 1] = { label = ("Choose answer " .. i), name = ("answer" .. i), run = function() Choose(i) end }
end

Commands[#Commands + 1] = { label = "Show the riddle's hint", name = "hint", run = function() Hint() end }
Commands[#Commands + 1] = { label = "Read the riddle aloud", name = "speak", run = function() Speak() end }
Commands[#Commands + 1] = { label = "Skip the riddle (Gentle mode, after a try)", name = "skip", run = function() Skip() end }

-- A held D-pad direction scrolls the open quest book a notch, then a notch every ScrollRepeat seconds until it's let
-- go.
local Scrolling

local function ScrollHeld(notches, phase)
    Scholar:Cancel(Scrolling)
    Scrolling = nil

    if phase == "down" then
        ScholarView.ScrollBook(notches)
        Scrolling = Scholar:Every(ScrollRepeat, function() ScholarView.ScrollBook(notches) end)
    end
end

Commands[#Commands + 1] = { held = true, label = "Scroll the quest book up", name = "scrollUp",
    run = function(_, phase) ScrollHeld(-1, phase) end }

Commands[#Commands + 1] = { held = true, label = "Scroll the quest book down", name = "scrollDown",
    run = function(_, phase) ScrollHeld(1, phase) end }

local Bindings = {}

for i, source in ipairs(AnswerSources) do
    Bindings[i] = { command = ("Scholar.answer" .. i), map = "scholar", source = source }
end

for action, source in pairs(ActionSources) do
    Bindings[#Bindings + 1] = { command = ("Scholar." .. action), map = "scholar", source = source }
end

for command, source in pairs(ScrollSources) do
    Bindings[#Bindings + 1] = { command = ("Scholar." .. command), map = "scholar", source = source }
end

Scholar = Addon:Module("Scholar", {
    bindings = Bindings,
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

        Current, Wrongs = nil, 0
        wipe(Missed)
        wipe(Windows)
        Close()
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

        module:On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
            if isInitialLogin then
                module:Set("unlocked", false)
                module:Set("locked", module:Get("pin") ~= 0)
            end

            -- A loading screen closes them all.
            wipe(Windows)
            module:Set("window", false)
        end)

        local pending, solved, combat = module:Id("pending"), module:Id("solved"), module:Id("combat.active")
        local afk, mathOn, readingOn = module:Id("afk.active"), module:Id("math"), module:Id("reading")
        local questsOn, window = module:Id("quests"), module:Id("window")

        -- Blizzard's windows a riddle waits for (see the header).
        for event, dialog in pairs(DialogEvents) do
            module:On(event, function() SetWindow(dialog[1], dialog[2]) end)
        end

        module:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", OnInteractionShown)
        module:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", OnInteractionHidden)
        module:On("TAXIMAP_CLOSED", function() SetWindow(TaxiNode, false) end)

        -- The play clock counts toward the next riddle while none is due, you're not AFK and a subject is on. It writes
        -- nothing while it runs: one timer fires when the interval is up, and play is saved when the clock stops, at
        -- logout and as the module stops.
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

                Current = (Current or NextPuzzle())

                if Current then
                    Open()
                elseif not HasSubject() then
                    module:Set("pending", false)
                -- Otherwise the riddle waits for a quest to ask about.
                end
            end,
            initial = true, reads = { pending, solved, combat, window },
            when = function(state)
                return ((state.Values[pending] or state.Values[solved]) and not state.Values[combat]
                    and not state.Values[window])
            end,
        })

        -- A fight sends the riddle away until it ends.
        module:Rule({
            changed = function(allowed)
                if not allowed then
                    Close()
                end
            end,
            reads = { pending, solved, combat },
            when = function(state)
                return ((state.Values[pending] or state.Values[solved]) and not state.Values[combat])
            end,
        })

        -- A riddle that came due with nothing to ask waits: a new quest, or a subject switched on, gives it one.
        module:Watch({ "QuestBook.quests", mathOn, readingOn, questsOn }, function(state)
            if state.Values[pending] and not Current and not state.Values[solved] and not state.Values[combat]
                and not state.Values[window] then
                Current = NextPuzzle()

                if Current then
                    Open()
                elseif not HasSubject() then
                    module:Set("pending", false)
                end
            end
        end, true)
    end,
    page = "Scholar's challenge",
    records = Records,
    scope = "character",
    state = Rows,
    uses = { "QuestBook" },
})
