local addonName, ns = ...

-- Scholar puzzles: math and reading questions for kids, kindergarten to grade 6, and questions about their own quests.
-- Pure: no UI, no WoW API, and no randomness but options.random, so the same options and random sequence give the same
-- puzzle. The shared text (kinds by grade, titles, praise, and the quest riddles' text and banks) lives in
-- ScholarWords.lua (ns.ScholarWords), which loads first; each subject's own text and banks live in
-- ScholarMathWords.lua, ScholarNumberWords.lua, ScholarReadingWords.lua and ScholarStoryWords.lua, which load before
-- the generators that read them. The generators live in ScholarMath.lua, ScholarReading.lua and ScholarQuests.lua,
-- which load after this file and register themselves in Kit.Generators; the "quest" subject asks through Kit.AskQuest
-- (ScholarQuests.lua) about one of the player's quests.
--
--   ns.Puzzles.Grades     { id, label } from { 0, "Kindergarten" } to { 6, "Grade 6" }, in order.
--   ns.Puzzles.Generate   see Generate below.
--   ns.Puzzles.Kinds      Kinds(subject, grade): the puzzle kinds a grade asks, which Generate's kind option takes.
--   ns.Puzzles.Signature  Signature(puzzle): what the no-repeat window remembers of a riddle.
--   ns.Puzzles.Kit        the building blocks, for the generators (Journal.lua also borrows Count).
--   ns.Puzzles.MaxChoice  the longest choice, in bytes, a riddle may offer (ScholarQuests.lua cuts its lines to it).
--                         Kit.Generators[kind] is function(state) -> puzzle.
--
-- A generator's state is one generation's record: roll (options.random), subject, grade, level and a sanitized context.
-- The Kit functions that only draw (Pick, Chance, Shuffle, WrongNumbers) read nothing but state.roll.

-- The factions a context may name, as UnitFactionGroup names them.
local Factions = { Alliance = true, Horde = true }
local MaxChoice, MaxPrompt = 40, 240
-- How many times Generate draws again to avoid a riddle the child saw recently.
local MaxRedraws = 8

local error, ipairs, pairs, tonumber, tostring, type = error, ipairs, pairs, tonumber, tostring, type
local find, gmatch, gsub, lower, upper = string.find, string.gmatch, string.gsub, string.lower, string.upper
local floor, max, min = math.floor, math.max, math.min
local insert = table.insert

local ScholarWords = ns.ScholarWords

local Grades = { { id = 0, label = "Kindergarten" } }

for grade = 1, 6 do
    Grades[grade + 1] = { id = grade, label = ("Grade " .. grade) }
end

local Generators = {}

--- True one time in n.
local function Chance(state, n)
    return (state.roll(1, n) == 1)
end

--- An amount of copper as it's spoken: "45 copper", "2 silver", "1 silver 5 copper".
local function Coins(copper)
    local silver, rest = floor(copper / 100), (copper % 100)

    return (((silver == 0) and (rest .. " copper")) or (silver .. " silver" .. (((rest > 0) and (" " .. rest .. " copper")) or "")))
end

--- "1 apple" or "3 apples".
---@param item table { one, many }
local function Count(n, item)
    return (n .. " " .. (((n == 1) and item[1]) or item[2]))
end

--- Replaces each {key} in text with vars[key]; a key vars doesn't have stays as it is.
local function Fill(text, vars)
    return (gsub(text, "{(%w+)}", function(key)
        return (((vars[key] ~= nil) and tostring(vars[key])) or nil)
    end))
end

--- Whether text contains word as a whole word, ignoring case.
local function Mentions(text, word)
    return (find(lower(text), "%f[%w]" .. gsub(lower(word), "%p", "%%%0") .. "%f[%W]") ~= nil)
end

--- One entry of list, drawn with state.roll.
local function Pick(state, list)
    return list[state.roll(1, #list)]
end

-- { first mention, later mentions }: sometimes the player ("Tessa the mage"), else a stock hero.
local function Hero(state)
    local name = state.context.name

    if name and Chance(state, 2) then
        local noun = (state.context.class and ScholarWords.classNouns[state.context.class])

        return { ((noun and (name .. " the " .. noun)) or name), name, mine = true }
    end

    return Pick(state, ScholarWords.heroes)
end

-- An item for the riddle: the player's class item now and then when the hero is the player (mine), never a stock hero.
local function Item(state, mine)
    local items = ScholarWords.items

    if state.grade == 0 then
        return Pick(state, items.small)
    elseif mine and state.context.class and Chance(state, 3) then
        return ScholarWords.classItems[state.context.class]
    end

    return Pick(state, ((state.grade == 1) and items.small) or items.adventure)
end

local function Place(state)
    return ((state.context.zone and Chance(state, 3) and state.context.zone) or Pick(state, ScholarWords.places))
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

--- Returns text without leading or trailing whitespace.
local function Trim(text)
    return (gsub(gsub(text, "^%s+", ""), "%s+$", ""))
end

--- Places the correct choice at a random position among three distinct distractors. Raises an error when wrongs has
--- fewer than three that differ from correct and each other.
---@return table choices four strings
---@return integer answer correct's position, 1 to 4
local function Arrange(state, correct, wrongs)
    local seen, pool = { [lower(Trim(correct))] = true }, {}

    for _, wrong in ipairs(wrongs) do
        local text = (((type(wrong) == "table") and wrong[1]) or wrong)
        local key = lower(Trim(text))

        if (key ~= "") and not seen[key] then
            seen[key], pool[#pool + 1] = true, { text, (((type(wrong) == "table") and wrong.why) or nil) }
        end
    end

    if #pool < 3 then
        error("ScholarPuzzles: too few distractors for " .. correct)
    end

    local answer, picked = state.roll(1, 4), Shuffle(state, pool)

    insert(picked, answer, { correct })
    local choices, whys = {}, {}

    for i = 1, 4 do
        choices[i], whys[i] = picked[i][1], picked[i][2]
    end

    return choices, answer, whys
end

--- Returns text, trimmed, when it's plain and at most maxLength long: no control characters, escape codes or template
--- braces. Anything else is nil.
local function Clean(text, maxLength)
    text = (((type(text) == "string") and Trim(text)) or "")

    return (((text ~= "") and (#text <= maxLength) and not find(text, "[%c|{}\\]") and text) or nil)
end

-- Whether a hint template gives the answer away on its own: it names a variable the prompt doesn't show whose value is
-- the answer, or the answer is a number the filled hint names and the filled prompt doesn't. A hint may say anything
-- the riddle already shows, even when it equals the answer ("count back 2" when 4 - 2 is asked), and a word of its own
-- that happens to be the answer ("picture the word" when the answer is "the").
local function GivesAway(template, prompt, vars, correct)
    if not template then
        return false
    end

    if tonumber(correct) and Mentions(Fill(template, vars), correct) and not Mentions(Fill(prompt, vars), correct) then
        return true
    end

    local shown = {}

    for name in gmatch(prompt, "{(%w+)}") do
        shown[lower(name)] = true
    end

    for name in gmatch(template, "{(%w+)}") do
        if not shown[lower(name)] and (vars[name] ~= nil) and (lower(Trim(tostring(vars[name]))) == lower(Trim(correct))) then
            return true
        end
    end

    return false
end

--- Word problem variables: a copy of vars plus {Hero} (first mention), {hero}, {place}, {item} and {items}. Each number
--- {a} also comes counted with the item as {A} ("3 apples").
local function Vars(state, vars)
    local hero = Hero(state)
    local item = Item(state, hero.mine)
    local out = { Hero = hero[1], hero = hero[2], item = item[1], items = item[2], place = Place(state) }

    for key, value in pairs(vars) do
        out[key] = value

        if type(value) == "number" then
            out[upper(key)] = Count(value, item)
        end
    end

    return out
end

--- Returns n as a number when it's a whole number from lo to hi (a numeric string counts), else nil.
local function WholeNumber(n, lo, hi)
    n = tonumber(n)

    return ((n and (n == floor(n)) and (n >= lo) and (n <= hi) and n) or nil)
end

-- Only the fields a generator uses, each dropped unless it's plain and in range.
local function SafeContext(context)
    if type(context) ~= "table" then
        return {}
    end

    local class = (((type(context.class) == "string") and upper(context.class)) or nil)

    return {
        class = ((class and ScholarWords.classNouns[class] and class) or nil),
        copper = WholeNumber(context.copper, 0, 1e12),
        faction = ((Factions[context.faction] and context.faction) or nil),
        level = WholeNumber(context.level, 1, 100),
        locale = (((type(context.locale) == "string") and find(context.locale, "^%l%l%u%u$") and context.locale) or nil),
        name = (((type(context.name) == "string") and Clean((gsub(context.name, "%-.*$", "")), 12)) or nil),
        zone = Clean(context.zone, 24),
    }
end

-- Pictures for small numbers in the early grades: what ScholarPictures draws as icons of item. a and b are the riddle's
-- two numbers; groups riddles put a groups of b.
local Pictures = {
    ["math.add"] = function(vars, item)
        return ((((vars.a + vars.b) <= 20) and { a = vars.a, b = vars.b, item = item, kind = "join" }) or nil)
    end,
    ["math.subtract"] = function(vars, item)
        return (((vars.a <= 20) and { a = vars.a, b = vars.b, item = item, kind = "take" }) or nil)
    end,
    ["math.groups"] = function(vars, item)
        return ((((vars.a * vars.b) <= 30) and (vars.a <= 6)
            and { each = vars.b, groups = vars.a, item = item, kind = "groups" }) or nil)
    end,
}

-- Returns n as a whole number clamped to lo..hi, or default when it isn't a number (or is NaN).
local function Clamp(n, lo, hi, default)
    n = tonumber(n)

    return (((n and (n == n)) and max(lo, min(hi, floor(n)))) or default)
end

-- The item a riddle counts (vars.item) when its prompt names it; nil for a bare sum ("What is 5 - 2?"), which is drawn
-- with stars.
local function Counted(prompt, vars)
    if vars.item and (Mentions(prompt, vars.item) or Mentions(prompt, vars.items)) then
        return vars.item
    end
end

--- Builds a puzzle of kind from its text entry (prompt or prompts, hint, explain, expr) and variables. vars.v (or
--- vars.report) becomes the puzzle's value; vars.r and vars.terms its remainder and terms. A hint that would give the
--- answer away is replaced by a stock one.
local function Finish(state, kind, text, vars, correct, wrongs)
    local choices, answer, whys = Arrange(state, correct, wrongs)
    local promptText = (text.prompt or Pick(state, text.prompts))
    local hint = Fill(text.hint, vars)

    if GivesAway(text.hint, promptText, vars, correct) then
        hint = ScholarWords.hintFallback
    end

    -- A wrong choice without its own why gets the kind's, which may name it as {choice}.
    for i, choice in ipairs(choices) do
        if (i ~= answer) and not whys[i] and text.wrong then
            local named = setmetatable({ choice = choice }, { __index = vars })

            whys[i] = Fill(text.wrong, named)
        end
    end

    local title = Pick(state, ScholarWords.titles[kind])
    local prompt = Fill(promptText, vars)
    local step = (text.step and Fill(text.step, vars))

    return {
        answer = answer,
        choices = choices,
        explanation = Fill(text.explain, vars),
        expression = (text.expr and Fill(text.expr, vars)),
        hint = hint,
        kind = kind,
        picture = (((state.grade <= 3) and Pictures[kind] and (type(vars.a) == "number") and (type(vars.b) == "number")
            and Pictures[kind](vars, Counted(prompt, vars))) or nil),
        praise = ((text.praise and Fill(text.praise, vars)) or Pick(state, ScholarWords.praise)),
        prompt = prompt,
        remainder = vars.r,
        speakChoices = (text.speakChoices or nil),
        speech = (text.speech and Fill(text.speech, vars)),
        step = ((((step ~= nil) and not GivesAway(text.step, promptText, vars, correct)) and step) or nil),
        subject = state.subject,
        terms = vars.terms,
        title = title,
        value = (vars.report or vars.v),
        whys = whys,
    }
end

local function Fits(puzzle)
    local choices = puzzle.choices

    return ((#puzzle.prompt <= MaxPrompt) and (max(#choices[1], #choices[2], #choices[3], #choices[4]) <= MaxChoice))
end

--- The puzzle kinds of a subject ("math" or "reading") at a grade (clamped to 0..6), in a fresh array. Without canHear,
--- the kinds that are heard rather than read (ScholarWords.heard) are left out, and without hasQuests the kinds built
--- from the player's quests (ScholarWords.fromQuests).
---@param subject string
---@param grade number
---@param canHear boolean whether the client can say a riddle aloud
---@param hasQuests boolean whether the quest book holds a quest to build a riddle from
---@return string[]
local function Kinds(subject, grade, canHear, hasQuests)
    local kinds = ScholarWords.kinds[subject]

    if not kinds then
        error("ScholarPuzzles.Kinds: unknown subject " .. tostring(subject), 2)
    end

    local out = {}

    for _, kind in ipairs(kinds[Clamp(grade, 0, 6, 0)]) do
        if (canHear or not ScholarWords.heard[kind]) and (hasQuests or not ScholarWords.fromQuests[kind]) then
            out[#out + 1] = kind
        end
    end

    return out
end

--- What makes two riddles the same to a child: the kind and the prompt (its numbers and words).
---@param puzzle table
---@return string
local function Signature(puzzle)
    return (puzzle.kind .. "|" .. puzzle.prompt)
end

--- Generates a puzzle. Every math and reading puzzle fits the length limits, with any context SafeContext admits. Bad
--- options (no random, an unknown subject) raise an error; grade and level are read as numbers and clamped. A quest
--- puzzle ignores grade and level, and is nil when no question fits the quest.
---@param options table subject ("math" | "reading" | "quest"), grade (0..6), level (1..3, easiest first), random
---                     (function(m, n) returning an integer from m to n), an optional context { name, class, level,
---                     zone, copper, faction ("Alliance" or "Horde"), locale (GetLocale's "enUS") } of plain values,
---                     an optional kind (one of Kinds(subject, grade); a random one otherwise), avoid (a set of
---                     Signatures not to repeat), fact (a math fact to ask again, { a, b }, for the kinds that ask
---                     facts), known (every QuestBook record, for "quest" and the math kinds built from quests), and
---                     for "quest" the quest (a QuestBook record)
---@return table? puzzle { subject, kind, title, prompt, choices (4 distinct strings), answer (1..4), hint,
---                      explanation, speech (what's said aloud for a heard riddle, whose prompt never shows the word) }, plus value, expression, remainder and terms on math puzzles and book (the quest
---                      book's text) on quest puzzles
local function Generate(options)
    if (type(options) ~= "table") or (type(options.random) ~= "function") then
        error("ScholarPuzzles.Generate: options.random must be a function", 2)
    end

    local state = {
        context = SafeContext(options.context), fact = options.fact, grade = Clamp(options.grade, 0, 6, 0),
        known = options.known, level = Clamp(options.level, 1, 3, 1), roll = options.random, subject = options.subject,
    }

    if options.subject == "quest" then
        return ns.Puzzles.Kit.AskQuest(state, options.quest, options.known)
    end

    local kinds = ScholarWords.kinds[options.subject]

    if not kinds then
        error("ScholarPuzzles.Generate: unknown subject " .. tostring(options.subject), 2)
    end

    local kind, known = options.kind, false

    for _, listed in ipairs(kinds[state.grade]) do
        known = (known or (listed == kind))
    end

    if kind == nil then
        kind = Pick(state, kinds[state.grade])
    elseif not known then
        error(("ScholarPuzzles.Generate: %s isn't a %s kind at grade %d"):format(tostring(kind), options.subject, state.grade), 2)
    end

    -- A riddle the child saw recently (options.avoid holds their Signatures) is drawn again, a few times at most.
    local puzzle = Generators[kind](state)

    for _ = 1, MaxRedraws do
        if not (options.avoid and options.avoid[Signature(puzzle)]) then
            break
        end

        puzzle = Generators[kind](state)
    end

    return puzzle
end

--- Three distinct plausible wrong numbers from lo to hi, and each one's why (or nil). A candidate is a number or { n,
--- why = text, required = true }: required ones always come first (the misconception a riddle exists to catch), then
--- the other candidates and near misses, chosen so the answer's rank among the four values is as even as the required
--- ones allow. lo defaults to 1 (0 when value is 0); hi to twice value or value plus 10, whichever is larger, and never
--- less than lo plus 6.
---@return number[] wrongs
---@return table whys by index into wrongs
local function WrongNumbers(state, value, candidates, lo, hi)
    lo = (lo or (((value > 0) and 1) or 0))
    hi = max(hi or max(value * 2, value + 10), lo + 6)
    local out, whys, seen = {}, {}, { [value] = true }
    local required, optional = {}, {}

    for _, candidate in ipairs(candidates) do
        local entry = (((type(candidate) == "table") and candidate) or { candidate })

        if entry.required then
            required[#required + 1] = entry
        else
            optional[#optional + 1] = entry
        end
    end

    local function Allowed(n)
        return ((n == floor(n)) and (n >= lo) and (n <= hi) and not seen[n])
    end

    local function Add(n, why)
        if (#out < 3) and Allowed(n) then
            seen[n] = true
            out[#out + 1] = n
            whys[#out] = why
        end
    end

    for _, entry in ipairs(required) do
        Add(entry[1], entry.why)
    end

    -- How many of the four values sit below the answer: 0 to 3, each as likely, as far as lo and hi allow.
    local below, above = 0, 0

    for _, n in ipairs(out) do
        if n < value then below = (below + 1) else above = (above + 1) end
    end

    local wantBelow = state.roll(below, 3 - above)

    if (wantBelow - below) > max(0, value - lo) then
        wantBelow = (below + max(0, value - lo))
    end

    local function Wanted(n)
        if n < value then
            return (below < wantBelow)
        end

        return (above < (3 - wantBelow))
    end

    local function Take(n, why)
        if Allowed(n) and Wanted(n) and (#out < 3) then
            if n < value then below = (below + 1) else above = (above + 1) end

            Add(n, why)
        end
    end

    for _, entry in ipairs(Shuffle(state, optional)) do
        Take(entry[1], entry.why)
    end

    for step = 1, (hi - lo) + 1 do
        if #out >= 3 then
            break
        end

        Take(value - step)
        Take(value + step)
    end

    -- The bounds left too little room on one side: any fitting near miss.
    for step = 1, (hi - lo) + 1 do
        if #out >= 3 then
            break
        end

        Add(value - step)
        Add(value + step)
    end

    return out, whys
end

local Kit = {
    Chance = Chance, Coins = Coins, Count = Count, Fill = Fill, Finish = Finish, Fits = Fits, Generators = Generators,
    Pick = Pick, Shuffle = Shuffle, Trim = Trim, Vars = Vars, Words = ScholarWords, WrongNumbers = WrongNumbers,
}

ns.Puzzles = { Generate = Generate, Grades = Grades, Kinds = Kinds, Kit = Kit, MaxChoice = MaxChoice, Signature = Signature }
