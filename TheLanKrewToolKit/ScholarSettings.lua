local addonName, ns = ...

-- ScholarSettings: the Scholar's challenge module's rows (Scholar.lua declares the module with them): the parent's
-- settings, on the Scholar's challenge page and behind the parent's lock (LockedBy), and the challenge's own saved and
-- runtime state. Data only: Scholar.lua owns what the rows mean.
--
--   ns.ScholarSettings.Rows       the module's state rows
--   ns.ScholarSettings.LockedBy   the row that locks the parent's settings

local LockedBy = "Scholar.locked"

local Puzzles = ns.Puzzles

local GradeLabels = {}
local GradeValues = {}

for _, grade in ipairs(Puzzles.Grades) do
    local id = tostring(grade.id)

    GradeValues[#GradeValues + 1] = id
    GradeLabels[id] = grade.label
end

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
        section = "Reading aloud",
        valueLabels = { always = "Always", off = "Only when asked", young = "For kindergarten and grade 1" },
        values = { "young", "always", "off" } },
    { default = 30, description = "Minutes of play between riddles.", kind = "number",
        label = "Minutes between riddles", lockedBy = LockedBy, max = 120, min = 10, name = "interval",
        scope = "character", section = "When riddles come", step = 5 },
    { default = true, description = "Earn each new level with a little wisdom, too.", kind = "boolean",
        label = "At every level-up", lockedBy = LockedBy, name = "onLevelUp", scope = "character" },
    { default = true,
        description = "A flight is free time: once half the minutes are played, it brings the next riddle.",
        kind = "boolean", label = "On flight paths", lockedBy = LockedBy, name = "onFlight", scope = "character" },
    { default = true,
        description = "Once half the minutes are played, turning in a quest brings a riddle about it, while it's fresh.",
        kind = "boolean", label = "When a quest is turned in", lockedBy = LockedBy, name = "onTurnIn",
        scope = "character" },
    { default = true, description = "Once half the minutes are played, a death brings the next riddle.",
        kind = "boolean", label = "While dead", lockedBy = LockedBy, name = "onDeath", scope = "character" },
    { default = "short",
        description = ("After a wrong answer, the answers left wait a moment before they can be picked, longer each "
            .. "miss, so your child reads the hint instead of trying every answer."),
        kind = "string", label = "Pause after a wrong answer", lockedBy = LockedBy, name = "missPause", scope = "character",
        section = "Answers",
        valueLabels = { long = "Long (4, 7, then 10 seconds)", off = "Off", short = "Short (2, 4, then 6 seconds)" },
        values = { "short", "long", "off" } },
    { default = "gate", description = "Whether a riddle must be solved, or can be skipped after one try.",
        kind = "string", label = "Riddle style", lockedBy = LockedBy, name = "style", scope = "character",
        valueLabels = { gate = "Solve to keep playing", gentle = "Gentle (Skip after one try)" },
        values = { "gate", "gentle" } },
    -- Progress, per character. elapsed is seconds of play toward the next riddle, and questRun is the quest riddles
    -- asked since math or reading last took a turn.
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
    -- How many riddles were shown, which numbers the recent ones the next won't repeat.
    { default = 0, kind = "number", min = 0, name = "shownCount", scope = "character", step = 1 },
    -- How many first tries have missed, which numbers the report's recent misses.
    { default = 0, kind = "number", min = 0, name = "missCount", scope = "character", step = 1 },
    { default = 0, kind = "number", name = "elapsed", scope = "character" },
    -- The pause after a wrong answer: the seconds the answers still wait, counted down only while a riddle shows, and
    -- the misses since a riddle was last solved or skipped, which lengthen each pause. Saved, so a /reload or relog
    -- neither ends the wait nor starts it over.
    { default = 0, kind = "number", min = 0, name = "pauseLeft", scope = "character", step = 1 },
    { default = 0, kind = "number", min = 0, name = "pauseMisses", scope = "character", step = 1 },
    { default = false, kind = "boolean", name = "pending", scope = "character" },
    { default = 0, kind = "number", min = 0, name = "questRun", scope = "character", step = 1 },
    -- The riddle on screen was just solved: its celebration holds the screen until Finish.
    { default = false, kind = "boolean", name = "solved", persist = false },
    -- One of Blizzard's windows a riddle waits for is open (Windows).
    { default = false, kind = "boolean", name = "window", persist = false },
    -- The parent's PIN (a hash; 0 = none), account-wide, and whether settings are locked right now.
    { default = 0, kind = "number", lockedBy = LockedBy, name = "pin" },
    { default = false, kind = "boolean", name = "locked", persist = false },
    -- The parent unlocked this session: it's saved, so a /reload keeps it. The next login locks again.
    { default = false, kind = "boolean", name = "unlocked" },
    -- Wrong unlock PINs since the last wait, and the server time unlocking waits until. Saved, so a /reload doesn't buy
    -- more tries.
    { default = 0, kind = "number", name = "pinMisses" },
    { default = 0, kind = "number", name = "pinWait" },
}

ns.ScholarSettings = { LockedBy = LockedBy, Rows = Rows }
