local addonName, ns = ...

-- ScholarMemory: what Scholar's challenge remembers about a child's riddles, per character, in the Scholar module's
-- records (declared in Records, which Scholar.lua's module spec uses): a record per skill and per math fact, reviewed
-- like flash cards (ScholarSkills), the recent misses the report shows, and the recent riddles the next one won't
-- repeat. Each function takes the Scholar module (its records and rows), so this file holds no state of its own.
--
--   ns.ScholarMemory.Records                     the module's records spec
--   ns.ScholarMemory.SkillOf(module, kind)        a skill's record, with every field filled in
--   ns.ScholarMemory.DueFact(module, kind, count) the fact of kind most due again, as { a, b }, or nil
--   ns.ScholarMemory.Recent(module)               the recent riddles' Signatures, as a set
--   ns.ScholarMemory.Remember(module, puzzle)     remembers a riddle shown
--   ns.ScholarMemory.Record(module, puzzle, i)    records the riddle's first try, once; whether this was it
--   ns.ScholarMemory.Report(module)               the parent's report card, as lines

-- How many recent misses the report shows.
local MissesKept = 5
-- The longest prompt, in bytes, a recent miss keeps, on one line.
local MissPrompt = 160
-- How many recent riddles the next one won't repeat.
local RecentRiddles = 40

local ByteTerrace, GetServerTime, ipairs = ByteTerrace, GetServerTime, ipairs

local Puzzles = ns.Puzzles
local Skills = ns.ScholarSkills

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
    -- A math fact a riddle asked (its kind's key, then a and b), reviewed like a skill, so a missed 7 x 8 comes back.
    {
        evict = "lastAt",
        fields = {
            { default = 0, kind = "number", name = "a" },
            { default = 0, kind = "number", min = 0, name = "asked", step = 1 },
            { default = 0, kind = "number", name = "b" },
            { default = 1, kind = "number", max = Skills.Boxes, min = 1, name = "box", step = 1 },
            { default = 0, kind = "number", min = 0, name = "due", step = 1 },
            { default = 0, kind = "number", min = 0, name = "firstTry", step = 1 },
            { default = "", kind = "string", name = "kind" },
            { default = 0, kind = "number", min = 0, name = "lastAt" },
            { default = "", kind = "string", name = "recent" },
        },
        limit = 64, name = "facts", scope = "character",
    },
    -- The last RecentRiddles riddles shown, by their Signature, so the next one doesn't repeat them.
    {
        evict = "seq",
        fields = {
            { default = 0, kind = "number", min = 0, name = "seq", step = 1 },
            { default = "", kind = "string", name = "signature" },
        },
        limit = RecentRiddles, name = "recent", scope = "character",
    },
}

-- The fact of kind most due again by count (the lowest box among the due), as { a, b }, or nil.
local function DueFact(module, kind, count)
    local facts, best = module.Records.facts, nil

    for _, key in ipairs(facts:Keys()) do
        local fact = facts:Get(key)

        if (fact.kind == kind) and (fact.due <= count) and ((best == nil) or (fact.box < best.box)) then
            best = fact
        end
    end

    return ((best and { a = best.a, b = best.b }) or nil)
end

-- The key a math fact is remembered by: its kind, then a and b.
local function FactKey(kind, fact)
    return ("%s:%sx%s"):format(kind, tostring(fact.a), tostring(fact.b))
end

-- The recent riddles' Signatures, as a set.
local function Recent(module)
    local recent, set = module.Records.recent, {}

    for _, key in ipairs(recent:Keys()) do
        set[recent:Field(key, "signature")] = true
    end

    return set
end

-- Remembers a riddle shown, so the next RecentRiddles don't repeat it.
local function Remember(module, puzzle)
    local seq = (module:Get("shownCount") + 1)

    module:Set("shownCount", seq)
    module.Records.recent:Set(tostring(seq), { seq = seq, signature = Puzzles.Signature(puzzle) })
end

-- The parent's report card, as chat lines (ScholarSkills.Report): each subject's skills by their records, the levels,
-- and the recent misses, newest first.
local function Report(module)
    local skills = module.Records.skills

    local sections = {
        { label = "Math", level = module:Get("mathLevel"), records = {}, subject = "math" },
        { label = "Reading", level = module:Get("readingLevel"), records = {}, subject = "reading" },
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

    for _, key in ipairs(module.Records.misses:Keys()) do
        misses[#misses + 1] = module.Records.misses:Get(key)
    end

    table.sort(misses, function(a, b) return (a.seq > b.seq) end)

    return Skills.Report(ByteTerrace.Names.Mine(), sections, misses)
end

-- A skill's record (ScholarSkills), with every field filled in.
local function SkillOf(module, kind)
    return (module.Records.skills:Get(kind) or { asked = 0, box = 1, due = 0, firstTry = 0, lastAt = 0, recent = "" })
end

-- Records the riddle's first try, once: its skill's record moves (ScholarSkills.Next), a math or reading riddle counts
-- toward its subject's due clock, and a miss joins the report's recent misses. Returns whether this was the first try.
local function Record(module, puzzle, i)
    if puzzle.recorded then
        return false
    end

    puzzle.recorded = true
    local right, count = (i == puzzle.answer), 0

    if puzzle.subject ~= "quest" then
        count = (module:Get(puzzle.subject .. "Count") + 1)
        module:Set(puzzle.subject .. "Count", count)
    end

    local now = GetServerTime()

    module.Records.skills:Set(puzzle.kind, Skills.Next(SkillOf(module, puzzle.kind), right, count, now))

    if puzzle.fact and (puzzle.subject ~= "quest") then
        local key, facts = FactKey(puzzle.kind, puzzle.fact), module.Records.facts
        local record = (facts:Get(key) or { asked = 0, box = 1, due = 0, firstTry = 0, lastAt = 0, recent = "" })
        local fields = Skills.Next(record, right, count, now)

        fields.a, fields.b, fields.kind = puzzle.fact.a, puzzle.fact.b, puzzle.kind
        facts:Set(key, fields)
    end

    if not right then
        local seq = (module:Get("missCount") + 1)

        module:Set("missCount", seq)

        module.Records.misses:Set(tostring(seq), {
            at = now, chosen = (puzzle.choices[i] or ""), kind = puzzle.kind,
            prompt = puzzle.prompt:gsub("%s+", " "):sub(1, MissPrompt), right = puzzle.choices[puzzle.answer], seq = seq,
        })
    end

    return true
end

ns.ScholarMemory = {
    DueFact = DueFact, Recent = Recent, Record = Record, Records = Records, Remember = Remember, Report = Report,
    SkillOf = SkillOf,
}
