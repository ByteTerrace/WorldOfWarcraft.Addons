local addonName, ns = ...

-- ScholarSkills: what Scholar remembers about each skill (a puzzle kind such as "math.add") and how it picks the next
-- one, the way flash cards are reviewed: a skill answered right on the first try moves up a box, a miss sends it back
-- to box 1, and a skill comes back after more riddles the higher its box (Interval). Scholar.lua keeps the records.
-- This file only decides, so the harness drives it with plain tables.
--
-- A skill's record (Scholar.lua's skills collection): asked (riddles of it answered), firstTry (of those, right on the
-- first try), box (1 to Boxes), due (the subject's riddle count at which it's due again), recent (its last RecentLength
-- first tries, "1" right and "0" missed, oldest first), and lastAt (GetServerTime of its last riddle).
--
--   ns.ScholarSkills.Choose(kinds, recordOf, count, random) -> kind
--   ns.ScholarSkills.Next(record, rightFirst, count, now) -> the record's new fields
--   ns.ScholarSkills.Mastered(record), Struggling(record) -> boolean
--   ns.ScholarSkills.Name(kind) -> a parent's name for the skill ("adding")
--   ns.ScholarSkills.Report(name, sections, misses) -> the parent's report card, as lines of text
--   ns.ScholarSkills.Boxes, Interval, RecentLength

local Boxes = 5
-- How many more of its subject's riddles a skill in each box waits before it's due again: a missed skill (box 1) is due
-- at the next one.
local Interval = { 1, 2, 4, 8, 16 }

-- The skills' names, for the parent's report.
local Names = {
    ["math.add"] = "adding", ["math.coins"] = "counting coins", ["math.compare"] = "comparing numbers",
    ["math.count"] = "counting", ["math.decimal"] = "decimals", ["math.divide"] = "dividing", ["math.fraction"] = "fractions",
    ["math.groups"] = "equal groups", ["math.missing"] = "missing numbers", ["math.money"] = "money",
    ["math.multiply"] = "multiplying", ["math.multistep"] = "multi-step problems", ["math.numberLine"] = "the number line",
    ["math.order"] = "order of operations", ["math.percent"] = "percents", ["math.placeValue"] = "place value",
    ["math.quest"] = "math from quests", ["math.ratio"] = "ratios", ["math.remainder"] = "remainders",
    ["math.skip"] = "skip counting", ["math.subtract"] = "subtracting", ["math.time"] = "telling time",
    ["quest.blank"] = "a quest's missing word",
    ["quest.count"] = "how many a quest asked for", ["quest.endPlace"] = "where a quest ended", ["quest.ender"] = "who ended a quest",
    ["quest.giver"] = "who gave a quest", ["quest.objective"] = "what a quest asked for", ["quest.place"] = "where a quest began",
    ["quest.title"] = "a quest's title", ["reading.antonym"] = "opposites", ["reading.blank"] = "filling in the blank",
    ["reading.blend"] = "consonant blends", ["reading.cvc"] = "short words", ["reading.digraph"] = "letter teams (sh and ch)",
    ["reading.listen"] = "hearing words", ["reading.listenSound"] = "hearing first sounds",
    ["reading.listenStory"] = "listening to a story", ["reading.rhyme"] = "rhymes", ["reading.sight"] = "sight words",
    ["reading.sound"] = "first sounds", ["reading.spelling"] = "spelling", ["reading.story"] = "reading a story",
    ["reading.synonym"] = "same meanings", ["reading.unscramble"] = "unscrambling words", ["reading.vocab"] = "vocabulary",
}

local RecentLength = 5

--- Returns whether a skill is mastered: in box 4 or above.
---@param record table
---@return boolean
local function Mastered(record)
    return (record.box >= 4)
end

--- Returns a parent's name for a skill, or the kind itself for one without a name.
---@param kind string
---@return string
local function Name(kind)
    return (Names[kind] or kind)
end

-- The names of the skills that pass test, sorted and joined, or none.
local function Listed(records, test, none)
    local names = {}

    for kind, record in pairs(records) do
        if test(record) then
            names[#names + 1] = Name(kind)
        end
    end

    table.sort(names)

    return (((#names > 0) and table.concat(names, ", ")) or none)
end

--- Returns a skill's fields after a riddle of it: rightFirst is whether its first try was right, count the subject's
--- riddles answered including this one, and now the GetServerTime it was answered at.
---@param record table
---@param rightFirst boolean
---@param count number
---@param now number
---@return table
local function Next(record, rightFirst, count, now)
    local box = ((rightFirst and math.min(record.box + 1, Boxes)) or 1)

    return {
        asked = (record.asked + 1), box = box, due = ((count + Interval[box]) - 1),
        firstTry = (record.firstTry + ((rightFirst and 1) or 0)), lastAt = now,
        recent = (record.recent .. ((rightFirst and "1") or "0")):sub(-RecentLength),
    }
end

-- A whole percentage of part in whole.
local function Percent(part, whole)
    return math.floor((((part * 100) / whole) + 0.5))
end

--- Returns whether a skill is being worked on: its last first try missed (it comes right back), or it has been asked at
--- least three times and fewer than half of its recent first tries were right.
---@param record table
---@return boolean
local function Struggling(record)
    local _, right = record.recent:gsub("1", "")

    return ((record.recent:sub(-1) == "0") or ((record.asked >= 3) and ((right * 2) < #record.recent)))
end

--- Returns the parent's report card, as lines of text. It starts with a summary, then gives each section's level,
--- riddles, first-try rate, skills mastered, and skills being worked on, then the recent misses with the answer chosen
--- and the right one.
---@param name string? the character's name
---@param sections table[] { label, level (nil for none), records = { [kind] = a skill's record } } each
---@param misses table[] the recent misses, newest first: { kind, prompt, chosen, right } each
---@return string[]
local function Report(name, sections, misses)
    local lines = {}
    local asked = 0
    local right = 0

    for _, section in ipairs(sections) do
        local sectionAsked = 0
        local sectionRight = 0

        for _, record in pairs(section.records) do
            sectionAsked, sectionRight = (sectionAsked + record.asked), (sectionRight + record.firstTry)
        end

        asked, right = (asked + sectionAsked), (right + sectionRight)
        local level = ((section.level and (" (level %d of 3)"):format(section.level)) or "")

        if sectionAsked == 0 then
            lines[#lines + 1] = ("%s%s: no riddles yet."):format(section.label, level)
        else
            lines[#lines + 1] = ("%s%s: %d riddles, %d%% right on the first try. Mastered: %s. Working on: %s."):format(
                section.label, level, sectionAsked, Percent(sectionRight, sectionAsked),
                Listed(section.records, Mastered, "none yet"), Listed(section.records, Struggling, "nothing right now"))
        end
    end

    local who = ((name and (" for " .. name)) or "")

    if asked == 0 then
        table.insert(lines, 1, ("Scholar's report card%s: no riddles answered yet."):format(who))
    else
        table.insert(lines, 1, ("Scholar's report card%s: %d riddles, %d%% right on the first try."):format(who, asked,
            Percent(right, asked)))
    end

    if #misses > 0 then
        lines[#lines + 1] = "Recent misses, newest first:"

        for _, miss in ipairs(misses) do
            lines[#lines + 1] = ("  %s: %s (answered %s; the answer is %s)"):format(Name(miss.kind), miss.prompt,
                miss.chosen, miss.right)
        end
    end

    return lines
end

-- How likely a skill is to come next: a due one first, the lower its box the likelier (a missed one, in box 1,
-- outweighs a new one), then a new one. One in box 3 or above that isn't due yet sits out.
local function Weight(record, count)
    if record.asked == 0 then
        return 6
    end

    if record.due <= count then
        return (2 + (2 * (Boxes - record.box)))
    end

    return (((record.box <= 2) and 1) or 0)
end

--- Returns the next skill to ask, from kinds (one subject's at one grade): a weighted pick (Weight). When every skill
--- sits out, it returns the one due soonest.
---@param kinds string[]
---@param recordOf fun(kind: string): table a skill's record, with every field filled in
---@param count number the subject's riddles answered so far
---@param random fun(m: integer, n: integer): integer
---@return string
local function Choose(kinds, recordOf, count, random)
    local weights = {}
    local total = 0

    for i, kind in ipairs(kinds) do
        weights[i] = Weight(recordOf(kind), count)
        total = (total + weights[i])
    end

    if total == 0 then
        local soonest = kinds[1]

        for _, kind in ipairs(kinds) do
            if recordOf(kind).due < recordOf(soonest).due then
                soonest = kind
            end
        end

        return soonest
    end

    local roll = random(1, total)

    for i, kind in ipairs(kinds) do
        roll = (roll - weights[i])

        if roll <= 0 then
            return kind
        end
    end

    return kinds[#kinds]
end

ns.ScholarSkills = {
    Boxes = Boxes, Choose = Choose, Interval = Interval, Mastered = Mastered, Name = Name, Next = Next,
    RecentLength = RecentLength, Report = Report, Struggling = Struggling,
}
