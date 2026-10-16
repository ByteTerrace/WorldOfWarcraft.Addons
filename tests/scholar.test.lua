-- Scholar puzzles (TheLanKrewToolKit/ScholarWords.lua, ScholarPuzzles.lua, ScholarMathWords.lua, ScholarMath.lua,
-- ScholarReadingWords.lua and ScholarReading.lua): property tests across seeds, every grade, every level and both
-- subjects. The reading banks' own checks are in scholarreading.test.lua.
--
-- The puzzle files load on their own, not with the whole addon, so concurrent edits to other files can't break these
-- tests. Their sources come from the runner (tools/lib/test-worker.mjs passes every TOC-listed file's source as
-- __addons), and Harness.DefineAddOn wraps them as a test-only addon that runs in the harness's strict environment
-- (reading an undefined global errors). A seeded LCG is the only randomness, and it rejects malformed ranges.

-- The largest number a grade's math may use, in its answers and calculations (copper for money).
local Band = { [0] = 10, 20, 100, 100, 9999, 1000, 1000 }
local Context = { class = "MAGE", copper = 4567, level = 12, name = "Tessa", zone = "Duskwood" }

local Files = {
    "ScholarWords.lua", "ScholarPuzzles.lua", "ScholarMathWords.lua", "ScholarMath.lua", "ScholarReadingWords.lua",
    "ScholarReading.lua",
}

local Kinds = {
    math = {
        [0] = { "math.count", "math.add", "math.subtract", "math.compare" },
        { "math.add", "math.subtract", "math.missing" },
        { "math.add", "math.subtract", "math.skip", "math.coins" },
        { "math.multiply", "math.divide", "math.groups" },
        { "math.multiply", "math.remainder", "math.money" },
        { "math.fraction", "math.multistep", "math.decimal" },
        { "math.percent", "math.ratio", "math.order" },
    },
    reading = {
        [0] = { "reading.rhyme", "reading.sound", "reading.sight", "reading.cvc", "reading.listen", "reading.listenSound" },
        { "reading.rhyme", "reading.sound", "reading.sight", "reading.cvc", "reading.listen", "reading.listenSound" },
        { "reading.unscramble", "reading.synonym", "reading.antonym", "reading.spelling" },
        { "reading.unscramble", "reading.synonym", "reading.antonym", "reading.spelling" },
        { "reading.vocab", "reading.blank", "reading.story" },
        { "reading.vocab", "reading.blank", "reading.story" },
        { "reading.vocab", "reading.blank", "reading.story" },
    },
}

local Subjects = { "math", "reading" }
local Unkind = { "kill", "killed", "blood", "bloody", "dead", "death", "die", "dies", "stupid", "dumb", "idiot", "loser" }

local function Escape(s)
    return (s:gsub("%p", "%%%0"))
end

local function Fold(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""):lower())
end

local function HasWord(text, word)
    return (text:lower():find("%f[%w]" .. Escape(word:lower()) .. "%f[%W]") ~= nil)
end

-- Park and Miller's minimal standard LCG; every product stays exact in a double.
local function Rng(seed)
    local state = ((seed % 2147483646) + 1)

    return function(m, n)
        if (type(m) ~= "number") or (type(n) ~= "number") or (m ~= math.floor(m)) or (n ~= math.floor(n)) or (m > n) then
            error(("random(%s, %s) is not a valid range"):format(tostring(m), tostring(n)), 2)
        end

        state = ((state * 48271) % 2147483647)

        return (m + (state % ((n - m) + 1)))
    end
end

local function Options(subject, grade, level, seed, context)
    local mix = ((((seed * 7919) + (grade * 104729)) + (level * 1299709)) + (((subject == "math") and 0) or 15485863))

    return { context = context, grade = grade, level = level, random = Rng(mix), subject = subject }
end

local function Sources()
    local addon = assert(__addons.TheLanKrewToolKit, "TheLanKrewToolKit isn't an addon")
    local sources, at = {}, {}

    for i, name in ipairs(Files) do
        for j, file in ipairs(addon.files) do
            if file == name then
                sources[i], at[i] = addon.sources[j], j
            end
        end

        assert(sources[i], name .. " isn't listed in TheLanKrewToolKit_Camelot.toc (ScholarWords.lua goes right before ScholarPuzzles.lua)")
    end

    return sources, at
end

local function Load()
    Harness.DefineAddOn("ScholarOnly", { as = "TheLanKrewToolKit", files = Files, sources = (Sources()) })
    local h = Harness.New()

    return h:LoadFiles("ScholarOnly"), h
end

-- Calls fn(puzzle, options) for seeds 1..seeds of every subject, grade and level.
local function Sweep(puzzles, seeds, context, fn)
    for _, subject in ipairs(Subjects) do
        for grade = 0, 6 do
            for level = 1, 3 do
                for seed = 1, seeds do
                    local options = Options(subject, grade, level, seed, context)

                    fn(puzzles.Generate(options), options)
                end
            end
        end
    end
end

local function Where(p, options)
    return ("%s grade %d level %d (%s): %q"):format(options.subject, options.grade, options.level, tostring(p.kind), tostring(p.prompt))
end

-- Fails with message (formatted with ...) and the puzzle it's about. The message is only built on a failure: the sweeps
-- check tens of thousands of facts.
local function Expect(ok, p, options, message, ...)
    if not ok then
        error(message:format(...) .. " at " .. Where(p, options), 2)
    end
end

local UnkindPatterns = {}

for i, word in ipairs({ "nil", unpack(Unkind) }) do
    UnkindPatterns[i] = { pattern = ("%f[%w]" .. word .. "%f[%W]"), word = word }
end

local function Contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end

    return false
end

-- An independent evaluator for expressions: numbers (with decimals), + - x / and parentheses.
local function Evaluate(text)
    local tokens, i = {}, 1

    while i <= #text do
        local c = text:sub(i, i)

        if c == " " then
            i = (i + 1)
        elseif c:match("%d") then
            local number = text:match("^%d+%.?%d*", i)

            tokens[#tokens + 1], i = tonumber(number), (i + #number)
        else
            assert(c:match("[%+%-x/%(%)]"), "unexpected " .. c .. " in " .. text)
            tokens[#tokens + 1], i = c, (i + 1)
        end
    end

    local at, Sum = 1, nil

    local function Atom()
        local t = tokens[at]

        at = (at + 1)

        if t == "(" then
            local v = Sum()

            assert(tokens[at] == ")", "unbalanced " .. text)
            at = (at + 1)

            return v
        end

        assert(type(t) == "number", "number expected in " .. text)

        return t
    end

    local function Product()
        local v = Atom()

        while (tokens[at] == "x") or (tokens[at] == "/") do
            local op = tokens[at]

            at = (at + 1)
            local r = Atom()

            v = (((op == "x") and (v * r)) or (v / r))
        end

        return v
    end

    Sum = function()
        local v = Product()

        while (tokens[at] == "+") or (tokens[at] == "-") do
            local op = tokens[at]

            at = (at + 1)
            local r = Product()

            v = (((op == "+") and (v + r)) or (v - r))
        end

        return v
    end

    local v = Sum()

    assert(at == (#tokens + 1), "trailing tokens in " .. text)

    return v
end

local Numbers = use("scholar").Numbers

-- A choice's value: copper for money, { quotient, remainder } for remainders, else its number.
local function ChoiceValue(kind, choice)
    if kind == "math.money" then
        return ((tonumber(choice:match("(%d+) silver") or 0) * 100) + tonumber(choice:match("(%d+) copper") or 0))
    elseif kind == "math.remainder" then
        local q, r = choice:match("^(%d+), with (%d+) left over$")

        return { tonumber(q), tonumber(r) }
    end

    return Numbers(choice)[1]
end

local function Same(a, b)
    if type(a) == "table" then
        return ((a[1] == b[1]) and (a[2] == b[2]))
    end

    return ((a ~= nil) and (b ~= nil) and (math.abs(a - b) < 1e-9))
end

-- What keeps text from being plain, or nil: empty, a byte outside printable ASCII (a line break only with
-- allowNewline), template braces or escape codes, "nil", or an unkind word.
local function Unplain(text, allowNewline)
    if (type(text) ~= "string") or (text == "") then
        return "empty text"
    end

    local at = text:find((allowNewline and "[^\n -~]") or "[^ -~]")

    if at then
        return ("byte %d in %q"):format(text:byte(at), text)
    end

    if text:find("[{}|]") then
        return ("template braces or escape codes in %q"):format(text)
    end

    local lowered = text:lower()

    for _, unkind in ipairs(UnkindPatterns) do
        if lowered:find(unkind.pattern) then
            return ("%q in %q"):format(unkind.word, text)
        end
    end

    return nil
end

local function ExpectPlain(text, allowNewline, p, options)
    local problem = Unplain(text, allowNewline)

    Expect(problem == nil, p, options, "plain text, not %s", problem)
end

-- The shape every puzzle has, whatever its kind.
local function CheckShape(p, options)
    Expect(p.subject == options.subject, p, options, "subject %s", tostring(p.subject))
    Expect(Contains(Kinds[options.subject][options.grade], p.kind), p, options, "kind belongs to the grade")
    ExpectPlain(p.title, false, p, options)
    Expect(#p.title <= 40, p, options, "short title")
    ExpectPlain(p.prompt, true, p, options)
    Expect(#p.prompt <= 240, p, options, "prompt within 240 chars (%d)", #p.prompt)
    Expect((#p.choices == 4) and (p.choices[5] == nil), p, options, "exactly four choices")
    local seen = {}

    for _, choice in ipairs(p.choices) do
        ExpectPlain(choice, false, p, options)
        Expect(#choice <= 40, p, options, "choice %q within 40 chars", choice)
        Expect(not seen[Fold(choice)], p, options, "distinct choice %q", choice)
        seen[Fold(choice)] = true
    end

    Expect((type(p.answer) == "number") and (p.answer >= 1) and (p.answer <= 4) and ((p.answer % 1) == 0), p, options, "answer in 1..4")
    ExpectPlain(p.hint, false, p, options)
    ExpectPlain(p.explanation, false, p, options)
    local correct = p.choices[p.answer]

    Expect(not (tonumber(correct) and HasWord(p.hint, correct) and not HasWord(p.prompt, correct)), p, options,
        "hint %q doesn't give away %q", p.hint, correct)

    Expect(not (p.explanation:lower():find("wrong") or p.title:lower():find("wrong")), p, options, "encouraging words")
end

-- Kinds whose prompt shows every number of the calculation.
local Shown = {
    ["math.add"] = true, ["math.subtract"] = true, ["math.missing"] = true, ["math.multiply"] = true, ["math.divide"] = true,
    ["math.groups"] = true, ["math.fraction"] = true, ["math.multistep"] = true, ["math.ratio"] = true, ["math.order"] = true,
    ["math.coins"] = true, ["math.decimal"] = true,
}

-- Kind-specific checks for the grade bands that the shape can't see.
local function CheckBand(p, options)
    local e = p.expression

    if (options.grade == 3) and ((p.kind == "math.multiply") or (p.kind == "math.groups")) then
        local a, b = e:match("^(%d+) x (%d+)$")

        Expect((tonumber(a) <= 10) and (tonumber(b) <= 10), p, options, "facts to 10 x 10")
    elseif (options.grade == 3) and (p.kind == "math.divide") then
        local _, b = e:match("^(%d+) / (%d+)$")

        Expect((tonumber(b) <= 10) and (p.value <= 10), p, options, "division facts")
    elseif (options.grade == 4) and (p.kind == "math.multiply") then
        local a, b = e:match("^(%d+) x (%d+)$")

        Expect((tonumber(a) >= 10) and (tonumber(a) <= 99) and (tonumber(b) >= 2) and (tonumber(b) <= 9), p, options, "2-digit x 1-digit")
    elseif p.kind == "math.decimal" then
        Expect(math.abs((p.value * 10) - math.floor((p.value * 10) + 0.5)) < 1e-9, p, options, "tenths")
    end
end

local function CheckMath(p, options)
    local band = Band[options.grade]

    Expect(type(p.value) == "number", p, options, "numeric value")
    local expected = (((p.kind == "math.remainder") and { p.value, p.remainder }) or p.value)
    local correct = ChoiceValue(p.kind, p.choices[p.answer])

    Expect(Same(correct, expected), p, options, "the correct choice %q is the value %s", p.choices[p.answer], tostring(p.value))

    for i, choice in ipairs(p.choices) do
        local value = ChoiceValue(p.kind, choice)

        Expect((value ~= nil) and ((type(value) ~= "table") or value[1]), p, options, "choice %q has a number", choice)

        if i ~= p.answer then
            Expect(not Same(value, expected), p, options, "distractor %q isn't also correct", choice)
        end

        if p.value > 0 then
            Expect((((type(value) == "table") and value[1]) or value) > 0, p, options, "distractor %q is positive", choice)
        end
    end

    Expect((p.value >= 0) and (p.value <= band), p, options, "value %s within grade band %d", tostring(p.value), band)

    if p.expression then
        Expect(Same(Evaluate(p.expression), p.value), p, options, "%s = %s", p.expression, tostring(p.value))

        for _, n in ipairs(Numbers(p.expression)) do
            Expect(n <= band, p, options, "%s stays within grade band %d", p.expression, band)

            if Shown[p.kind] then
                Expect(p.prompt:find("%f[%d]" .. Escape(tostring(n)) .. "%f[%D]"), p, options, "the prompt shows %s", tostring(n))
            end
        end
    elseif p.kind == "math.count" then
        local row = p.prompt:match("\n([^\n]+)\n")
        local counted = select(2, row:gsub("[^ ]", ""))

        Expect(counted == p.value, p, options, "%d symbols to count, not %d", counted, p.value)
    elseif p.kind == "math.remainder" then
        local n, d = p.terms[1], p.terms[2]

        Expect(p.value == math.floor(n / d), p, options, "quotient")
        Expect(p.remainder == (n % d), p, options, "remainder")
        Expect((p.remainder >= 1) and (n <= 200) and (d <= 9), p, options, "a small remainder")
    else
        Expect((p.kind == "math.compare") or (p.kind == "math.decimal"), p, options, "only comparisons lack an expression")
        local best = p.terms[1]

        for _, n in ipairs(p.terms) do
            best = ((p.prompt:find("biggest") and math.max(best, n)) or math.min(best, n))
        end

        Expect(p.value == best, p, options, "the extreme of the four")

        for _, n in ipairs(p.terms) do
            Expect(n <= band, p, options, "compared numbers within band")
        end
    end
end

local function Serialize(p)
    return table.concat({ p.subject, p.kind, p.title, p.prompt, table.concat(p.choices, "|"), p.answer, p.hint,
        p.explanation, tostring(p.value), tostring(p.expression), tostring(p.remainder) }, "\n")
end

local function Sorted(word)
    local letters = {}

    for letter in word:gmatch("%a") do
        letters[#letters + 1] = letter
    end

    table.sort(letters)

    return table.concat(letters)
end

-- The stock careful-work praise, which a reading riddle never falls back to: each kind praises its own strategy.
local StockPraise

-- Every reading riddle teaches: each wrong choice has a why that never names the answer (a single letter aside), there
-- is a worked step, and the praise names the kind's strategy. A heard riddle's help never names its word.
local function CheckTeaching(p, options, heard)
    local correct = p.choices[p.answer]

    if not StockPraise then
        StockPraise = {}

        for _, line in ipairs(Load().ScholarWords.praise) do
            StockPraise[line] = true
        end
    end

    for i = 1, 4 do
        if i ~= p.answer then
            ExpectPlain(p.whys[i], false, p, options)
            Expect((#correct == 1) or not HasWord(p.whys[i], correct), p, options, "why %q doesn't name %q", p.whys[i], correct)
            Expect(not (heard and HasWord(p.whys[i], heard)), p, options, "why %q doesn't name the heard word", p.whys[i])
        end
    end

    ExpectPlain(p.step, false, p, options)
    ExpectPlain(p.praise, false, p, options)
    Expect(not StockPraise[p.praise], p, options, "praise %q names the strategy", p.praise)
    Expect(not (heard and (HasWord(p.hint, heard) or HasWord(p.step, heard))), p, options, "the help doesn't name %q", tostring(heard))
end

local function CheckReading(p, options)
    local correct = p.choices[p.answer]
    -- A heard riddle's speech ends with its word.
    local heard = (p.speech and p.speech:match("(%a+)%.$"))

    CheckTeaching(p, options, heard)

    if p.kind == "reading.rhyme" then
        local target = p.prompt:match("rhymes with \"(%a+)\"")
        local rime = p.explanation:match("end with \"(%a+)\"")

        Expect((correct ~= target) and (correct:sub(-2) == target:sub(-2)), p, options, "the answer rhymes")
        Expect((correct:sub(-#rime) == rime) and (target:sub(-#rime) == rime), p, options, "both end with %q", rime)

        for i, choice in ipairs(p.choices) do
            Expect((i == p.answer) or (choice:sub(-2) ~= target:sub(-2)), p, options, "distractor %q doesn't look like a rhyme", choice)
        end
    elseif p.kind == "reading.sound" then
        local target = p.prompt:match("same sound as \"(%a+)\"")
        -- C and k spell one sound, so neither is ever the other's wrong choice.
        local same = ({ c = "k", k = "c" })[target:sub(1, 1)]

        for i, choice in ipairs(p.choices) do
            Expect((choice:sub(1, 1) == target:sub(1, 1)) == (i == p.answer), p, options, "first sound of %q", choice)
            Expect(choice:sub(1, 1) ~= same, p, options, "%q starts with the same sound, spelled %s", choice, tostring(same))
        end
    elseif p.kind == "reading.sight" then
        Expect(p.explanation:find(("\"%s\""):format(correct), 1, true) ~= nil, p, options, "the working names %q", correct)
    elseif p.kind == "reading.cvc" then
        local sounds = p.prompt:match("\n(%a %- %a %- %a)\n")
        local was, from, now = p.prompt:match("Change the \"(%a)\" in \"(%a+)\" to \"(%a)\"")
        local expected = ((sounds and sounds:gsub(" %- ", "")) or (from and from:gsub(was, now)))

        Expect(correct == expected, p, options, "the built word %q, not %q", tostring(expected), correct)

        if from then
            local having = 0

            for _, choice in ipairs(p.choices) do
                having = (having + (((choice:find(now, 1, true) ~= nil) and 1) or 0))
            end

            Expect(Contains(p.choices, from), p, options, "the unchanged %q is a choice", from)
            Expect(having >= 2, p, options, "a wrong choice has the new %q too, so it alone doesn't decide", now)
        end
    elseif p.kind == "reading.listen" then
        Expect(correct == heard, p, options, "the answer is the word said aloud, %q", tostring(heard))
        Expect(not p.prompt:lower():find("%f[%a]" .. heard .. "%f[%a]"), p, options, "the prompt doesn't show the word")
    elseif p.kind == "reading.listenSound" then
        for i, choice in ipairs(p.choices) do
            Expect((choice == heard:sub(1, 1)) == (i == p.answer), p, options, "first letter of %q: %q", heard, choice)
        end

        Expect(not p.prompt:lower():find("%f[%a]" .. heard .. "%f[%a]"), p, options, "the prompt doesn't show the word")
    elseif p.kind == "reading.unscramble" then
        local letters = p.prompt:match("\n([A-Z][A-Z ]+)")

        Expect(letters:gsub(" ", "") ~= correct, p, options, "the letters are scrambled")
        Expect(not p.prompt:find("Clue"), p, options, "the clue waits for the step")

        for i, choice in ipairs(p.choices) do
            Expect((Sorted(choice) == Sorted(letters)) == (i == p.answer), p, options, "anagram check for %q", choice)
            Expect(#choice == #correct, p, options, "%q is as long as the answer", choice)
        end
    end
end

local function CheckAll(p, options)
    CheckShape(p, options)

    if p.subject == "math" then
        CheckMath(p, options)
        CheckBand(p, options)
    else
        CheckReading(p, options)
    end
end

test("the TOC lists ScholarWords.lua right before ScholarPuzzles.lua, and the generators after it", function()
    local _, at = Sources()

    eq(at[2], at[1] + 1, "ScholarWords.lua loads right before ScholarPuzzles.lua")

    for i = 3, #Files do
        truthy(at[i] > at[2], Files[i] .. " loads after ScholarPuzzles.lua")
    end
end)

test("loads standalone and defines ns.Puzzles, ns.ScholarWords and no globals", function()
    Harness.DefineAddOn("ScholarOnly", { as = "TheLanKrewToolKit", files = Files, sources = (Sources()) })
    local h = Harness.New()
    local before = {}

    for key in pairs(h.env) do
        before[key] = true
    end

    local ns = h:LoadFiles("ScholarOnly")

    for key in pairs(h.env) do
        truthy(before[key], "no new global " .. tostring(key))
    end

    eq(type(ns.Puzzles.Generate), "function")
    eq(type(ns.ScholarWords), "table")
    local keys = {}

    for key in pairs(ns.Puzzles) do
        keys[#keys + 1] = key
    end

    table.sort(keys)
    eq(table.concat(keys, ","), "Generate,Grades,Kinds,Kit,MaxChoice", "exactly the contract's fields")
end)

test("Grades runs from Kindergarten to Grade 6 in order", function()
    local puzzles = Load().Puzzles

    eq(#puzzles.Grades, 7)
    eq(puzzles.Grades[1].id, 0)
    eq(puzzles.Grades[1].label, "Kindergarten")

    for i = 2, 7 do
        eq(puzzles.Grades[i].id, i - 1)
        eq(puzzles.Grades[i].label, "Grade " .. (i - 1))
    end
end)

test("randomness comes only from options.random", function()
    local sources = Sources()
    local addon = __addons.TheLanKrewToolKit

    for i, file in ipairs(addon.files) do
        -- ScholarQuests.lua needs the whole addon to load, so it isn't in Files, but it is just as pure.
        if file == "ScholarQuests.lua" then
            sources[#sources + 1] = addon.sources[i]
        end
    end

    eq(#sources, #Files + 1, "ScholarQuests.lua is listed")

    for _, source in ipairs(sources) do
        -- Whole words: BlankCandidate( isn't date(.
        for _, banned in ipairs({ "math.random", "%f[%w]os%.", "%f[%w]time%(", "GetTime", "%f[%w]date%(", "%f[%w]random%(" }) do
            falsy(source:find(banned), "the source doesn't use " .. banned)
        end
    end
end)

test("bad options fail loudly instead of guessing", function()
    local puzzles = Load().Puzzles

    throws(function() puzzles.Generate({ grade = 1, level = 1, subject = "math" }) end, "random")
    throws(function() puzzles.Generate({ grade = 1, level = 1, random = Rng(1), subject = "art" }) end, "subject")
    local p = puzzles.Generate({ grade = "3", level = "9", random = Rng(5), subject = "math" })

    truthy(Contains(Kinds.math[3], p.kind), "grade and level strings are read and clamped")
    CheckShape(p, { grade = 3, level = 3, subject = "math" })
    local text = { explain = "1 + 2 = 3.", hint = "Count on.", prompt = "What is 1 + 2?" }

    throws(function()
        puzzles.Kit.Finish({ grade = 1, roll = Rng(1), subject = "math" }, "math.add", text, {}, "3", { "4", " 4 ", "3", "" })
    end, "too few distractors", "a generator without three distinct wrong answers is refused")
end)

test("every puzzle is well formed and correct, without context", function()
    Sweep(Load().Puzzles, 150, nil, CheckAll)
end)

test("every puzzle is well formed and correct, with a full context", function()
    Sweep(Load().Puzzles, 100, Context, CheckAll)
end)

test("every puzzle fits its limits with the longest context the generator admits", function()
    -- A 12-character name and a 24-character zone are the most SafeContext keeps.
    for _, class in ipairs({ "WARRIOR", "PALADIN", "WARLOCK" }) do
        Sweep(Load().Puzzles, 40, { class = class, copper = 999999999, level = 99, name = "Maximilianus",
            zone = "Swamp of Sorrows Outpost" }, CheckAll)
    end
end)

test("the same options and random sequence give the same puzzle", function()
    local puzzles = Load().Puzzles

    for _, context in ipairs({ false, Context }) do
        for _, subject in ipairs(Subjects) do
            for grade = 0, 6 do
                for level = 1, 3 do
                    for seed = 1, 3 do
                        local first = Serialize(puzzles.Generate(Options(subject, grade, level, seed, context or nil)))

                        eq(Serialize(puzzles.Generate(Options(subject, grade, level, seed, context or nil))), first)
                    end
                end
            end
        end
    end
end)

test("every kind appears across seeds, and the answer lands in every position", function()
    local seen, positions, total = { math = {}, reading = {} }, { 0, 0, 0, 0 }, 0

    Sweep(Load().Puzzles, 60, nil, function(p, options)
        seen[options.subject][options.grade .. p.kind] = true
        positions[p.answer], total = (positions[p.answer] + 1), (total + 1)
    end)

    for _, subject in ipairs(Subjects) do
        for grade = 0, 6 do
            for _, kind in ipairs(Kinds[subject][grade]) do
                truthy(seen[subject][grade .. kind], ("%s appears in grade %d"):format(kind, grade))
            end
        end
    end

    for i = 1, 4 do
        truthy(positions[i] > (total * 0.18), ("answer position %d is used often enough (%d of %d)"):format(i, positions[i], total))
    end
end)

test("each variant of a kind turns up", function()
    local found = {}

    local variants = {
        "Count back by", "Which number is the biggest", "Which number is the smallest", "left over", "Change the",
        "Say each sound", "gears in inches", "100 copper", "in all%?", "%)", "%% off",
    }

    Sweep(Load().Puzzles, 60, nil, function(p)
        for _, pattern in ipairs(variants) do
            found[pattern] = (found[pattern] or (p.prompt:find(pattern) ~= nil))
        end
    end)

    for _, pattern in ipairs(variants) do
        truthy(found[pattern], "some prompt matches " .. pattern)
    end
end)

test("context personalizes some puzzles, never all, and only where it fits the grade", function()
    local counts, total = {}, 0

    local function Seen(label, yes)
        counts[label] = ((counts[label] or 0) + ((yes and 1) or 0))
    end

    Sweep(Load().Puzzles, 80, Context, function(p, options)
        total = (total + 1)
        local text = p.prompt

        Seen("name", text:find("Tessa"))
        Seen("class", text:find("Tessa the mage"))
        Seen("zone", text:find("Duskwood"))
        Seen("class item", text:find("magic muffin"))
        Seen("level", (options.grade == 1) and text:find("You are level 12!"))
        Seen("silver", (options.grade == 4) and text:find("You have 45 silver 67 copper right now!"))
        Seen("reading name", (options.subject == "reading") and text:find("Tessa"))
        falsy((options.grade ~= 4) and text:find("45 silver 67 copper"), "their purse only in grade 4 silver math")
        falsy((options.grade == 0) and text:find("magic muffin"), "kindergarten keeps to simple items")
    end)

    for _, label in ipairs({ "name", "class", "zone", "class item", "level", "silver", "reading name" }) do
        truthy(counts[label] > 0, label .. " appears sometimes")
    end

    truthy(counts.name < (total / 2), "the name appears only sometimes")
end)

test("small purses, far levels and gold personalize the grades they suit", function()
    local puzzles = Load().Puzzles

    local function Any(grade, context, pattern)
        for seed = 1, 60 do
            for level = 1, 3 do
                if puzzles.Generate(Options("math", grade, level, seed, context)).prompt:find(pattern) then
                    return true
                end
            end
        end

        return false
    end

    truthy(Any(2, { copper = 45 }, "You have 45 copper right now!"), "grade 2 uses a purse under 90 copper")
    falsy(Any(2, { copper = 150 }, "You have 150 copper"), "grade 2 skips a purse over 100 copper")
    truthy(Any(2, { level = 12 }, "until you reach level 60%?"), "grade 2 counts levels to 60")
    falsy(Any(1, { level = 25 }, "You are level"), "grade 1 skips levels past 20")
    truthy(Any(6, { copper = 400000 }, "You have 40 gold!"), "grade 6 uses gold for percents")
    falsy(Any(4, { copper = 123456 }, "right now"), "grade 4 skips a purse of 100 silver or more")
end)

test("a missing or odd context falls back gracefully", function()
    local puzzles = Load().Puzzles

    local odd = {
        false, {}, { name = "" }, { name = "Tessa-Stormrage" }, { name = "Maximilianusz" }, { name = "|cffff0000Red" },
        { class = "NOTACLASS", copper = -5, level = 0.5, name = 42, zone = {} }, { copper = 1e15, zone = string.rep("x", 100) },
        { class = "mage", copper = 0, level = 99 }, "not a table",
    }

    for _, context in ipairs(odd) do
        for _, subject in ipairs(Subjects) do
            for grade = 0, 6 do
                for level = 1, 3 do
                    for seed = 1, 8 do
                        local options = Options(subject, grade, level, seed, context or nil)
                        local p = puzzles.Generate(options)

                        CheckAll(p, options)
                        falsy(p.prompt:find("Stormrage") or p.prompt:find("Maximilianusz") or p.prompt:find("xxxx"), "odd context text stays out")
                    end
                end
            end
        end
    end
end)

test("no context never mentions the player", function()
    Sweep(Load().Puzzles, 40, nil, function(p, options)
        falsy(p.prompt:find("You have") or p.prompt:find("You are level"), "no personal money or level at " .. Where(p, options))
    end)
end)

test("pictures always match the math, and only small numbers in the early grades get one", function()
    local puzzles = Load().Puzzles
    local seen = {}

    Sweep(puzzles, 30, Context, function(p, options)
        local picture = p.picture

        if not picture then
            return
        end

        local where = ("%s grade %d: %s"):format(p.kind, options.grade, p.prompt)

        truthy(options.grade <= 3, "no pictures above grade 3 at " .. where)

        if picture.item then
            truthy(p.prompt:lower():find(picture.item, 1, true), "the picture draws the item the riddle counts at " .. where)
            seen.item = true
        end

        seen[picture.kind] = true

        if picture.kind == "groups" then
            eq(picture.groups * picture.each, p.value, where)
            truthy((picture.groups * picture.each) <= 30, where)
        elseif picture.kind == "join" then
            eq(picture.a + picture.b, p.value, where)
            truthy((picture.a + picture.b) <= 20, where)
        elseif picture.kind == "take" then
            eq(picture.a - picture.b, p.value, where)
            truthy(picture.a <= 20, where)
        elseif picture.kind == "count" then
            eq(picture.n, p.value, where)
            truthy(p.prompt:find(picture.row, 1, true), "the row the picture replaces is in the prompt at " .. where)
        else
            error("unknown picture kind " .. tostring(picture.kind))
        end
    end)

    truthy(seen.groups and seen.join and seen.take and seen.count, "every picture kind shows up")
    truthy(seen.item, "pictures carry the item they draw")
end)

test("unscramble riddles carry their letters as tiles, in the prompt's order", function()
    local puzzles = Load().Puzzles
    local found = 0

    Sweep(puzzles, 10, Context, function(p)
        if p.kind == "reading.unscramble" then
            found = (found + 1)
            eq(table.concat(p.tiles, " "), p.prompt:match("\n([A-Z][A-Z ]+)"))
            truthy(p.prompt:match("%?$"), "ends with its question")
        end
    end)

    truthy(found > 0)
end)
