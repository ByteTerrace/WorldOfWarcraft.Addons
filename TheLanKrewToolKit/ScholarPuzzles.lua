local addonName, ns = ...

-- Scholar puzzles: math and reading questions for kids, kindergarten to grade 6, and questions about
-- their own quests. Pure: no UI, no WoW API, and no randomness but options.random, so the same
-- options and random sequence give the same puzzle. Every puzzle's text and the word banks live in ScholarWords.lua (ns.ScholarWords),
-- which loads first. The generators live in ScholarMath.lua, ScholarReading.lua and
-- ScholarQuests.lua, which load after this file and register themselves in Kit.Generators; the
-- "quest" subject asks through Kit.AskQuest (ScholarQuests.lua) about one of the player's quests.
--
--   ns.Puzzles.Grades     { id, label } from { 0, "Kindergarten" } to { 6, "Grade 6" }, in order.
--   ns.Puzzles.Generate   see Generate below.
--   ns.Puzzles.Kit        the building blocks, for the generators (Journal.lua also borrows Count).
--                         Kit.Generators[kind] is function(state) -> puzzle.
--
-- A generator's state is one generation's record: roll (options.random), subject, grade, level and
-- a sanitized context. The Kit functions that only draw (Pick, Chance, Shuffle, WrongNumbers) read
-- nothing but state.roll.

local MaxPrompt, MaxChoice = 240, 40

local floor, max, min = math.floor, math.max, math.min
local insert = table.insert
local find, gsub, lower, upper = string.find, string.gsub, string.lower, string.upper
local error, ipairs, pairs, tonumber, tostring, type = error, ipairs, pairs, tonumber, tostring, type

local ScholarWords = ns.ScholarWords

local Grades = { { id = 0, label = "Kindergarten" } }
for grade = 1, 6 do
    Grades[grade + 1] = { id = grade, label = "Grade " .. grade }
end

local Generators = {}

--- One entry of list, drawn with state.roll.
local function Pick(state, list)
    return list[state.roll(1, #list)]
end

--- True one time in n.
local function Chance(state, n)
    return state.roll(1, n) == 1
end

--- A shuffled copy of list; list itself is left alone.
local function Shuffle(state, list)
    local out = {}
    for i, value in ipairs(list) do
        out[i] = value
    end
    for i = #out, 2, -1 do
        local j = state.roll(1, i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

--- text without leading or trailing whitespace.
local function Trim(text)
    return (gsub(gsub(text, "^%s+", ""), "%s+$", ""))
end

--- Replaces each {key} in text with vars[key]; a key vars doesn't have stays as it is.
local function Fill(text, vars)
    return (gsub(text, "{(%w+)}", function(key)
        return vars[key] ~= nil and tostring(vars[key]) or nil
    end))
end

--- "1 apple" or "3 apples".
---@param item table { one, many }
local function Count(n, item)
    return n .. " " .. (n == 1 and item[1] or item[2])
end

--- An amount of copper as it's spoken: "45 copper", "2 silver", "1 silver 5 copper".
local function Coins(copper)
    local silver, rest = floor(copper / 100), copper % 100
    return silver == 0 and rest .. " copper" or silver .. " silver" .. (rest > 0 and " " .. rest .. " copper" or "")
end

--- Whether text contains word as a whole word, ignoring case.
local function Mentions(text, word)
    return find(lower(text), "%f[%w]" .. gsub(lower(word), "%p", "%%%0") .. "%f[%W]") ~= nil
end

--- text, trimmed, when it's plain and at most maxLength long: no control characters, escape
--- codes or template braces. Anything else is nil.
local function Clean(text, maxLength)
    text = type(text) == "string" and Trim(text) or ""
    return text ~= "" and #text <= maxLength and not find(text, "[%c|{}\\]") and text or nil
end

--- n as a number when it's a whole number from lo to hi (a numeric string counts), else nil.
local function WholeNumber(n, lo, hi)
    n = tonumber(n)
    return n and n == floor(n) and n >= lo and n <= hi and n or nil
end

-- Only the fields a generator uses, each dropped unless it's plain and in range.
local function SafeContext(context)
    if type(context) ~= "table" then
        return {}
    end
    local class = type(context.class) == "string" and upper(context.class) or nil
    return {
        name = type(context.name) == "string" and Clean((gsub(context.name, "%-.*$", "")), 12) or nil,
        zone = Clean(context.zone, 24),
        class = class and ScholarWords.classNouns[class] and class or nil,
        level = WholeNumber(context.level, 1, 100),
        copper = WholeNumber(context.copper, 0, 1e12),
    }
end

-- { first mention, later mentions }: sometimes the player ("Tessa the mage"), else a stock hero.
local function Hero(state)
    local name = state.context.name
    if name and Chance(state, 2) then
        local noun = state.context.class and ScholarWords.classNouns[state.context.class]
        return { noun and (name .. " the " .. noun) or name, name }
    end
    return Pick(state, ScholarWords.heroes)
end

local function Place(state)
    return state.context.zone and Chance(state, 3) and state.context.zone or Pick(state, ScholarWords.places)
end

local function Item(state)
    local items = ScholarWords.items
    if state.grade == 0 then
        return Pick(state, items.small)
    elseif state.context.class and Chance(state, 3) then
        return ScholarWords.classItems[state.context.class]
    end
    return Pick(state, state.grade == 1 and items.small or items.adventure)
end

--- Word problem variables: a copy of vars plus {Hero} (first mention), {hero}, {place}, {item}
--- and {items}. Each number {a} also comes counted with the item as {A} ("3 apples").
local function Vars(state, vars)
    local hero, item = Hero(state), Item(state)
    local out = { Hero = hero[1], hero = hero[2], place = Place(state), item = item[1], items = item[2] }
    for key, value in pairs(vars) do
        out[key] = value
        if type(value) == "number" then
            out[upper(key)] = Count(value, item)
        end
    end
    return out
end

--- Places the correct choice at a random position among three distinct distractors. Raises an
--- error when wrongs has fewer than three that differ from correct and each other.
---@return table choices four strings
---@return integer answer correct's position, 1 to 4
local function Arrange(state, correct, wrongs)
    local seen, pool = { [lower(Trim(correct))] = true }, {}
    for _, wrong in ipairs(wrongs) do
        local key = lower(Trim(wrong))
        if key ~= "" and not seen[key] then
            seen[key], pool[#pool + 1] = true, wrong
        end
    end
    if #pool < 3 then
        error("ScholarPuzzles: too few distractors for " .. correct)
    end
    local answer, choices = state.roll(1, 4), Shuffle(state, pool)
    insert(choices, answer, correct)
    return { choices[1], choices[2], choices[3], choices[4] }, answer
end

-- Pictures for small numbers in the early grades: what ScholarPictures draws as icons of item. a
-- and b are the riddle's two numbers; groups riddles put a groups of b.
local Pictures = {
    ["math.add"] = function(vars, item)
        return vars.a + vars.b <= 20 and { kind = "join", a = vars.a, b = vars.b, item = item } or nil
    end,
    ["math.subtract"] = function(vars, item)
        return vars.a <= 20 and { kind = "take", a = vars.a, b = vars.b, item = item } or nil
    end,
    ["math.groups"] = function(vars, item)
        return vars.a * vars.b <= 30 and vars.a <= 6
            and { kind = "groups", groups = vars.a, each = vars.b, item = item } or nil
    end,
}

-- The item a riddle counts (vars.item) when its prompt names it; nil for a bare sum ("What is
-- 5 - 2?"), which is drawn with stars.
local function Counted(prompt, vars)
    if vars.item and (Mentions(prompt, vars.item) or Mentions(prompt, vars.items)) then
        return vars.item
    end
end

--- Builds a puzzle of kind from its text entry (prompt or prompts, hint, explain, expr) and
--- variables. vars.v (or vars.report) becomes the puzzle's value; vars.r and vars.terms its
--- remainder and terms. A hint that would give the answer away is replaced by a stock one.
local function Finish(state, kind, text, vars, correct, wrongs)
    local choices, answer = Arrange(state, correct, wrongs)
    local hint = Fill(text.hint, vars)
    if Mentions(hint, correct) then
        hint = ScholarWords.hintFallback
    end
    local title = Pick(state, ScholarWords.titles[kind])
    local prompt = Fill(text.prompt or Pick(state, text.prompts), vars)
    return {
        subject = state.subject, kind = kind, title = title, prompt = prompt, choices = choices, answer = answer,
        hint = hint, explanation = Fill(text.explain, vars) .. " " .. Pick(state, ScholarWords.praise),
        value = vars.report or vars.v, expression = text.expr and Fill(text.expr, vars), remainder = vars.r,
        terms = vars.terms,
        picture = state.grade <= 3 and Pictures[kind] and type(vars.a) == "number" and type(vars.b) == "number"
            and Pictures[kind](vars, Counted(prompt, vars)) or nil,
    }
end

--- Three distinct plausible wrong numbers from lo to hi: the shuffled candidates first, then near
--- misses. lo defaults to 1 (0 when value is 0); hi to the larger of value * 2 and value + 10,
--- and never less than lo + 6.
local function WrongNumbers(state, value, candidates, lo, hi)
    lo = lo or (value > 0 and 1 or 0)
    hi = max(hi or max(value * 2, value + 10), lo + 6)
    local out, seen = {}, { [value] = true }
    local function Add(n)
        if #out < 3 and n == floor(n) and n >= lo and n <= hi and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    for _, n in ipairs(Shuffle(state, candidates)) do
        Add(n)
    end
    local step, down = 1, Chance(state, 2)
    while #out < 3 do
        Add(down and value - step or value + step)
        Add(down and value + step or value - step)
        step = step + 1
    end
    return out
end

local function Fits(puzzle)
    local choices = puzzle.choices
    return #puzzle.prompt <= MaxPrompt and max(#choices[1], #choices[2], #choices[3], #choices[4]) <= MaxChoice
end

-- n as a whole number clamped to lo..hi; default when it isn't a number (or is NaN).
local function Clamp(n, lo, hi, default)
    n = tonumber(n)
    return (n and n == n) and max(lo, min(hi, floor(n))) or default
end

--- Generates a puzzle. Every math and reading puzzle fits the length limits, with any context
--- SafeContext admits. Bad options (no random, an unknown subject) raise an error; grade and level
--- are read as numbers and clamped. A quest puzzle ignores grade and level, and is nil when no
--- question fits the quest.
---@param options table subject ("math" | "reading" | "quest"), grade (0..6), level (1..3, easiest
--- first), random (function(m, n) returning an integer from m to n), an optional context { name,
--- class, level, zone, copper } of plain values, and for "quest" the quest (a QuestBook record)
--- and known (every record)
---@return table? puzzle { subject, kind, title, prompt, choices (4 distinct strings), answer (1..4),
--- hint, explanation }, plus value, expression, remainder and terms on math puzzles and book (the
--- quest book's text) on quest puzzles
local function Generate(options)
    if type(options) ~= "table" or type(options.random) ~= "function" then
        error("ScholarPuzzles.Generate: options.random must be a function", 2)
    end
    local state = {
        roll = options.random, subject = options.subject,
        grade = Clamp(options.grade, 0, 6, 0), level = Clamp(options.level, 1, 3, 1),
        context = SafeContext(options.context),
    }
    if options.subject == "quest" then
        return ns.Puzzles.Kit.AskQuest(state, options.quest, options.known)
    end
    local kinds = ScholarWords.kinds[options.subject]
    if not kinds then
        error("ScholarPuzzles.Generate: unknown subject " .. tostring(options.subject), 2)
    end
    return Generators[Pick(state, kinds[state.grade])](state)
end

local Kit = {
    Pick = Pick, Chance = Chance, Shuffle = Shuffle, Trim = Trim, Fill = Fill, Count = Count, Coins = Coins,
    Vars = Vars, Finish = Finish, WrongNumbers = WrongNumbers, Fits = Fits, Words = ScholarWords, Generators = Generators,
}
ns.Puzzles = { Grades = Grades, Generate = Generate, Kit = Kit }
