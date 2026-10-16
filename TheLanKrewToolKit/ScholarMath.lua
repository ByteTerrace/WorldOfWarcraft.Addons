local addonName, ns = ...

-- The math generators: one function per math kind in ScholarWords.kinds, registered in Kit.Generators for Generate
-- (ScholarPuzzles.lua, which loads first), except the ones in ScholarMoney.lua and ScholarNumbers.lua, which load after
-- this file and build with the functions it lends through Kit (below). Pure like ScholarPuzzles.lua. Their text and
-- banks are ns.ScholarMathWords (ScholarMathWords.lua, which loads right before this file).
--
-- Every puzzle here is numeric: it carries value (the answer as a number; copper for money, tenths as a decimal) and,
-- for calculations, expression (ASCII: + - x / and parentheses), so callers and tests can recompute it.
--
-- Each riddle lists the mistakes its kind invites, most telling first, as { n, why = name }: name is one of its text's
-- whys. The first that fits is required, so the mistake the riddle exists to catch is always a choice; the others are
-- kept, with their whys, when WrongNumbers draws them. Plain numbers are near misses.
--
-- The riddles that ask one fact (a small sum or difference, a times-table or division fact) set puzzle.fact = { a, b },
-- the numbers in the order asked (a division's a is the number shared), and ask state.fact (Generate's fact option)
-- again, any story, when it fits the riddle: a small sum or difference to 20, factors to 12.
--
--   Kit.AddParts(a, b), Kit.AddMistakes(parts)              two-digit addition's parts, and the mistakes it invites
--   Kit.Numeric(state, kind, text, vars, candidates, options)  a numeric puzzle (Numeric below); text is a
--                                                              ScholarMathWords key or a text of that shape
--   Kit.Text(text, cases)                                      that text with its cases laid over it
--   Kit.Why(template, vars, extra), Kit.With(list, ...)        a why filled in; near misses appended

-- The factors multiplication's first level mixes in: the rules for 0, 1 and 10, and the doubles and fives.
local EasyFactors = { 0, 1, 2, 5, 10 }

-- Times-table factor ranges per level: { first from, first to, second from, second to }.
local FactRanges = { { 2, 5, 2, 5 }, { 2, 10, 2, 5 }, { 3, 10, 3, 10 } }

-- What a price must divide by for a percent's steps (a tenth, a twentieth, a quarter, a half) to stay whole.
local PercentDivisors = { [10] = 10, [15] = 20, [20] = 10, [25] = 4, [30] = 10, [40] = 10, [50] = 2, [60] = 10, [75] = 4 }

-- A count of tens or tenths, as Count names it: "1 ten", "3 tenths".
local Tens = { "ten", "tens" }
local TenthWords = { "tenth", "tenths" }

-- The largest sum or starting number, per grade (0 and 1) and level.
local SmallCap = { [0] = { 5, 7, 10 }, { 12, 16, 20 } }

local concat = table.concat
local floor = math.floor
local insert = table.insert
local ipairs = ipairs
local max = math.max
local min = math.min
local pairs = pairs
local rep = string.rep
local setmetatable = setmetatable
local sort = table.sort
local tostring = tostring
local type = type

local Kit = ns.Puzzles.Kit
local Chance = Kit.Chance
local Count = Kit.Count
local Fill = Kit.Fill
local Finish = Kit.Finish
local Generators = Kit.Generators
local MathWords = ns.ScholarMathWords
local Pick = Kit.Pick
local Shuffle = Kit.Shuffle
local Trim = Kit.Trim
local Vars = Kit.Vars
local WrongNumbers = Kit.WrongNumbers

-- The mistakes two-digit addition invites, most telling first: leaving out the carry, adding only the tens, or adding
-- the tens as if they were ones.
local function AddMistakes(parts)
    local mistakes = { { (10 * (parts.ta + parts.tb)), why = "tens" }, { (parts.ta + parts.tb), why = "digits" } }

    if parts.ones >= 10 then
        insert(mistakes, 1, { (parts.v - 10), why = "carry" })
    end

    return mistakes
end

-- The place-value parts the addition texts name: each number's ones and tens, the ones' sum and its last digit, and the
-- answer's tens.
local function AddParts(a, b)
    local oa = (a % 10)
    local ob = (b % 10)

    return {
        a = a, b = b, oa = oa, ob = ob, od = ((oa + ob) % 10), ones = (oa + ob), ta = floor(a / 10), tb = floor(b / 10),
        tens = floor((a + b) / 10), tensA = Count(floor(a / 10), Tens), tensB = Count(floor(b / 10), Tens), v = (a + b),
    }
end

-- The fact state asks again (state.fact) as a, b, when both are whole numbers from 0 to 144 that fits(a, b) admits; nil
-- otherwise, and the riddle rolls its own.
local function AskedFact(state, fits)
    local fact = (((type(state.fact) == "table") and state.fact) or {})
    local a = fact.a
    local b = fact.b

    if (type(a) ~= "number") or (type(b) ~= "number") or (a ~= floor(a)) or (b ~= floor(b)) then
        return nil
    end

    if (a >= 0) and (b >= 0) and (a <= 144) and (b <= 144) and fits(a, b) then
        return a, b
    end
end

-- Change from a round price: if the change came out equal to the cost, stopping after the first step would be right, so
-- the coins paid go up by 50.
local function Change(state)
    local n = state.roll(2, 5)

    local p = (((state.level == 1) and (5 * state.roll(1, 4)))
        or state.roll(((state.level == 2) and 6) or 11, ((state.level == 2) and 25) or 45))

    local m = (50 * (floor((n * p) / 50) + 1))

    if (m - (n * p)) == (n * p) then
        m = (m + 50)
    end

    local v = (m - (n * p))

    return "change", { m = m, n = n, np = (n * p), p = p, v = v },
        { { (n * p), why = "cost" }, { (m - p), why = "one" }, (v + 10), (v - 10), (v + p) }
end

-- Times-table factors from FactRanges, in either order.
local function Factors(state)
    local range = FactRanges[state.level]
    local a = state.roll(range[1], range[2])
    local b = state.roll(range[3], range[4])

    if Chance(state, 2) then
        return b, a
    end

    return a, b
end

-- Which facts each fact riddle asks again: small sums and differences within 20, and factors to 12.
local function FitsDivision(a, b)
    return ((b >= 2) and (b <= 12) and (a >= b) and ((a % b) == 0) and ((a / b) <= 12))
end

local function FitsSmallDifference(a, b)
    return ((b >= 1) and (b <= a) and (a <= 20))
end

local function FitsSmallSum(a, b)
    return ((a >= 1) and (b >= 1) and ((a + b) <= 20))
end

local function FitsTimes(a, b)
    return ((a <= 12) and (b <= 12))
end

-- Four distinct numbers from lo to hi.
local function FourOf(state, lo, hi)
    local pool = {}

    for n = lo, hi do
        pool[#pool + 1] = n
    end

    pool = Shuffle(state, pool)

    return { pool[1], pool[2], pool[3], pool[4] }
end

local function Packs(state)
    local a = state.roll(5, (10 * state.level) + 10)
    local b = state.roll(2, 6)
    local c = state.roll(4, 4 + (3 * state.level))
    local v = (a + (b * c))

    return "packs", { a = a, b = b, bc = (b * c), c = c, v = v },
        { { (b * c), why = "packs" }, { ((a + b) * c), why = "leftToRight" }, { ((a + b) + c), why = "allAdded" }, (v + c), (v - c) }
end

-- A price and a percent whose steps stay whole; sometimes the player's own gold.
local function PercentPlan(state)
    local mine = (state.context.copper and floor(state.context.copper / 10000))

    if mine and (mine >= 10) and (mine <= 1000) and Chance(state, 2) then
        for _, percent in ipairs(Shuffle(state, { 10, 20, 25, 50 })) do
            if (mine % PercentDivisors[percent]) == 0 then
                return mine, percent, true
            end
        end
    end

    local percent = Pick(state, ({ { 10, 50 }, { 10, 20, 25, 50 }, { 15, 30, 40, 60, 75 } })[state.level])

    return (({ 10, 20, 20 })[state.level] * state.roll(2, ({ 20, 10, 15 })[state.level])), percent, false
end

local function Share(state)
    local n = state.roll(2, 6)
    local q = state.roll(2, 3 + (2 * state.level))
    local e = state.roll(2, 9)
    local v = (q + e)

    return "share", { e = e, n = n, q = q, t = (n * q), v = v },
        { { q, why = "shareOnly" }, { ((n * q) + e), why = "notShared" }, (v + 1), (v - 1), (((n * q) - n) + e) }
end

-- Skip counting by step, times times: "3, 6, 9, 12".
local function Skips(step, times)
    local out = {}

    for i = 1, times do
        out[i] = (step * i)
    end

    return concat(out, ", ")
end

-- A number of tenths as a decimal: 35 is "3.5".
local function Tenths(tenths)
    return (floor(tenths / 10) .. "." .. (tenths % 10))
end

-- MathWords[key] (or key itself, a text of that shape) with each case named in cases laid over it, in order: a case's
-- fields replace the text's, and its whys add to the text's.
local function Text(key, cases)
    local base = (((type(key) == "table") and key) or MathWords[key])
    local layers = { base }
    local text = {}
    local whys = {}

    for _, name in ipairs(cases or {}) do
        layers[#layers + 1] = base.cases[name]
    end

    for _, layer in ipairs(layers) do
        for field, value in pairs(layer) do
            text[field] = value
        end

        for mistake, why in pairs(layer.whys or {}) do
            whys[mistake] = why
        end
    end

    text.whys = whys

    return text
end

-- A number of hundredths with both decimal places: 340 is "3.40", 305 is "3.05".
local function TwoPlaces(hundredths)
    return (floor(hundredths / 100) .. "." .. ((((hundredths % 100) < 10) and "0") or "") .. (hundredths % 100))
end

-- A number of hundredths as a decimal with the places it needs: 340 is "3.4", 312 is "3.12".
local function Hundredths(hundredths)
    if (hundredths % 10) == 0 then
        return Tenths(hundredths / 10)
    end

    return TwoPlaces(hundredths)
end

-- A why template filled with the riddle's variables and extra (choice: the wrong answer it's about).
local function Why(template, vars, extra)
    return Fill(template, setmetatable(extra, { __index = vars }))
end

-- Which of four numbers is biggest or smallest. options: format (a number's text), places (its text with every decimal
-- place, for the working), scale (the terms are n / scale), trap (the number with the longer-is-bigger why), and x and
-- y (the two numbers the step compares; by default, the first two that aren't the answer). The opposite extreme always
-- gets its why.
local function Extreme(state, kind, key, four, biggest, options)
    local format = (options.format or tostring)
    local scale = (options.scale or 1)
    local sorted = { four[1], four[2], four[3], four[4] }

    sort(sorted)
    local best = ((biggest and sorted[4]) or sorted[1])
    local opposite = ((biggest and sorted[1]) or sorted[4])
    local listed = {}
    local others = {}
    local terms = {}

    for i, n in ipairs(four) do
        terms[i] = (n / scale)

        if n ~= best then
            others[#others + 1] = n
        end
    end

    for i, n in ipairs(sorted) do
        listed[i] = (options.places or format)(n)
    end

    local x = (options.x or others[1])
    local y = (options.y or others[2])

    local vars = {
        listed = concat(listed, ", "), opposite = ((biggest and "smallest") or "biggest"),
        other = ((biggest and "smaller") or "bigger"), out = format((biggest and min(x, y)) or max(x, y)), report = (best / scale),
        terms = terms, v = format(best), when = ((biggest and "last") or "first"), word = ((biggest and "biggest") or "smallest"),
        x = format(x), y = format(y),
    }

    local text = Text(key)
    local wrongs = {}

    for _, n in ipairs(four) do
        if n ~= best then
            local why = (((n == options.trap) and text.whys.longer) or ((n == opposite) and text.whys.opposite) or nil)

            wrongs[#wrongs + 1] = { format(n), why = (why and Why(why, vars, { choice = format(n) })) }
        end
    end

    return Finish(state, kind, text, vars, format(best), wrongs)
end

-- Hundredths that end in a tenth, beside the trap that's longer but smaller ("3.12" against "3.4"), the tenth below and
-- a number with a smaller whole part. The step compares the trap with the tenth below.
local function DecimalCompare(state)
    local whole = state.roll(1, 5)
    local tenth = state.roll(2, 9)
    local best = ((100 * whole) + (10 * tenth))
    local trap = (((100 * whole) + (10 * state.roll(1, tenth - 1))) + state.roll(1, 9))
    local four = { best, trap, (best - 10), ((100 * (whole - 1)) + (10 * state.roll(5, 9))) }

    return Extreme(state, "math.decimal", "decimalCompare", four, true,
        { format = Hundredths, places = TwoPlaces, scale = 100, trap = trap, x = trap, y = (best - 10) })
end

-- A math puzzle whose choices are numbers. vars.v is the answer and MathWords[key] the text, with the cases in
-- options.cases laid over it. candidates are the riddle's named mistakes and near misses (see the header). options = {
-- lo, hi, format, cases } bounds and formats the wrong answers. hi defaults to 10 past the biggest candidate:
-- WrongNumbers walks every number from lo to hi, so a far bound costs time.
local function Numeric(state, kind, key, vars, candidates, options)
    local format = (options.format or tostring)
    local lo = (options.lo or (((vars.v > 0) and 1) or 0))
    local hi = options.hi

    if not hi then
        hi = vars.v

        for _, candidate in ipairs(candidates) do
            hi = max(hi, (((type(candidate) == "table") and candidate[1]) or candidate))
        end

        hi = (hi + 10)
    end

    local text = Text(key, options.cases)
    local filled = Vars(state, vars)
    local marked = {}
    local required = false

    for i, candidate in ipairs(candidates) do
        local named = (type(candidate) == "table")
        local n = ((named and candidate[1]) or candidate)

        if named and not required and (n == floor(n)) and (n ~= vars.v) and (n >= lo) and (n <= hi) then
            marked[i], required = { n, required = true, why = candidate.why }, true
        else
            marked[i] = candidate
        end
    end

    local numbers, whys = WrongNumbers(state, vars.v, marked, options.lo, hi)
    local wrongs = {}

    for i, n in ipairs(numbers) do
        wrongs[i] = { format(n), why = (whys[i] and Why(text.whys[whys[i]], filled, { choice = format(n) })) }
    end

    return Finish(state, kind, text, filled, format(vars.v), wrongs)
end

-- Grade 1 and 2 subtraction sometimes counts the player's levels to a milestone.
local function LevelsToGo(state, goal)
    local level = state.context.level

    if level and (level < goal) and Chance(state, 6) then
        local v = (goal - level)

        return Numeric(state, "math.subtract", "levels", { a = goal, b = level, b1 = (level + 1), v = v },
            { { (goal + level), why = "added" }, { goal, why = "goal" }, (v + 1), (v - 1), (v + 10), (v - 10) },
            {})
    end
end

-- Subtraction within the grade's cap: counting back a few, counting up a short gap, or thinking of the addition.
local function SubtractSmall(state)
    local a, b = AskedFact(state, FitsSmallDifference)

    if not a then
        a = state.roll(((state.grade == 0) and 2) or 5, SmallCap[min(state.grade, 1)][state.level])
        b = state.roll(1, (((state.grade == 0) and (state.level == 3)) and a) or (a - 1))
    end

    local v = (a - b)
    local counts = {}
    local case = nil

    if (b <= 5) or (v == 0) then
        for n = a - 1, v, -1 do
            counts[#counts + 1] = n
        end
    elseif v <= 5 then
        case = "up"

        for n = b + 1, a do
            counts[#counts + 1] = n
        end
    else
        case = "think"
    end

    local puzzle = Numeric(state, "math.subtract", "subtractSmall", { a = a, b = b, counts = concat(counts, ", "), v = v },
        { { (a + b), why = "added" }, { (v + 1), why = "start" }, (v - 1), (v + 2), b },
        { cases = ((case and { case }) or nil) })

    puzzle.fact = { a = a, b = b }

    return puzzle
end

-- Appends each of ... to list, the near misses after a riddle's named mistakes, and returns list.
local function With(list, ...)
    for _, n in ipairs({ ... }) do
        list[#list + 1] = n
    end

    return list
end

-- Two-digit addition: level 1 never regroups, level 3 always does.
local function AddBig(state)
    local a
    local b

    if state.level == 2 then
        a = state.roll(10, 60)
        b = state.roll(5, 99 - a)
    else
        local tensA = state.roll(1, 7)
        local onesA = state.roll(((state.level == 3) and 1) or 0, 8)
        local tensB = state.roll(1, 8 - tensA)
        local onesB = (((state.level == 3) and state.roll(10 - onesA, 9)) or state.roll(0, 9 - onesA))

        a, b = ((10 * tensA) + onesA), ((10 * tensB) + onesB)
    end

    local parts = AddParts(a, b)
    local v = parts.v

    return Numeric(state, "math.add", "addBig", parts, With(AddMistakes(parts), (v + 10), (v + 1), (v - 1), (v + 11)),
        { cases = (((parts.ones >= 10) and { "carry" }) or nil) })
end

-- Addition within the grade's cap: the sum is rolled first and then split, so every sum and split is as likely. A sum
-- past 10 from two numbers under 10 makes a ten first; the rest count on from the bigger number.
local function AddSmall(state)
    local cap = SmallCap[min(state.grade, 1)][state.level]
    local low = (((state.grade == 0) and 1) or 2)
    local a, b = AskedFact(state, FitsSmallSum)

    if not a then
        local sum = state.roll(2 * low, cap)

        a = state.roll(low, sum - low)
        b = (sum - a)
    end

    local v = (a + b)
    local big = max(a, b)
    local small = min(a, b)
    local ten = ((big < 10) and (v > 10))
    local counts = {}

    for n = big + 1, v do
        counts[#counts + 1] = n
    end

    local vars = { a = a, b = b, big = big, counts = concat(counts, ", "), fill = (10 - big), rest = (v - 10), small = small, v = v }
    local named = { { (v - 1), why = "start" }, { (big - small), why = "takeAway" } }

    if ten then
        insert(named, 1, { 10, why = "ten" })
    end

    local puzzle = Numeric(state, "math.add", "addSmall", vars, With(named, (v + 1), (v + 2), (v - 2)),
        { cases = ((ten and { "ten" }) or nil), hi = (max(cap, v) + 2) })

    puzzle.fact = { a = a, b = b }

    return puzzle
end

-- Two-digit times one-digit, worked as partial products; the classic slip is leaving out the carry.
local function MultiplyBig(state)
    local range = ({ { 11, 25, 2, 5 }, { 12, 60, 3, 9 }, { 25, 99, 6, 9 } })[state.level]
    local a = state.roll(range[1], range[2])
    local b = state.roll(range[3], range[4])
    local v = (a * b)
    local ones = (a % 10)
    local tens = floor(a / 10)
    local carry = floor((ones * b) / 10)

    local vars = {
        a = a, b = b, carried = Count(carry, Tens), o = ones, po = (ones * b), pt = ((10 * tens) * b), t0 = (10 * tens),
        ta = tens, tensA = Count(tens, Tens), v = v,
    }

    local named = {
        { (a + b), why = "added" }, { ((tens * b) + (ones * b)), why = "tensAsOnes" }, { (v + a), why = "more" },
        { (v - a), why = "fewer" },
    }

    if carry > 0 then
        insert(named, 1, { (v - (10 * carry)), why = "noCarry" })
    end

    return Numeric(state, "math.multiply", "bigMultiply", vars, With(named, (v + 10), (v - 10), (v + b), (v - b)),
        { cases = (((carry > 0) and { "carry" }) or nil) })
end

-- Times-table facts. Level 1 mixes the rules for 0, 1 and 10 with the doubles and fives, either factor first.
local function MultiplyFacts(state)
    local a, b = AskedFact(state, FitsTimes)

    if (a == nil) and (state.level == 1) then
        a, b = Pick(state, EasyFactors), state.roll(1, 10)

        if Chance(state, 2) then
            a, b = b, a
        end
    elseif a == nil then
        a, b = Factors(state)
    end

    local v = (a * b)
    local big = max(a, b)
    local small = min(a, b)
    local case = ((((small == 0) and "zero") or ((small == 1) and "one") or ((big == 10) and "ten")) or nil)
    local other = (((case == "ten") and small) or big)
    local named

    if case == "zero" then
        named = { { other, why = "kept" } }
    elseif case == "one" then
        named = { { (other + 1), why = "added" }, { 1, why = "one" } }
    elseif case == "ten" then
        named = { { (other + 10), why = "added" } }
    else
        named = { { (a + b), why = "added" }, { (v + big), why = "more" }, { (v - big), why = "fewer" } }
    end

    local vars = { a = a, b = b, big = big, other = other, skips = Skips(big, small), small = small, v = v }

    local puzzle = Numeric(state, "math.multiply", "multiply", vars, With(named, (v + small), (v - small), (v + 1), (v - 1)),
        { cases = ((case and { case }) or nil) })

    puzzle.fact = { a = a, b = b }

    return puzzle
end

-- Two-digit subtraction: level 1 never trades a ten, level 3 always does.
local function SubtractBig(state)
    local a
    local b

    if state.level == 2 then
        a = state.roll(20, 99)
        -- The tens of b stay below a's, so the tens never cancel out.
        b = state.roll(5, (10 * floor(a / 10)) - 1)
    else
        local tensA = state.roll(2, 9)
        local tensB = state.roll(1, tensA - 1)
        local onesB = state.roll(((state.level == 3) and 1) or 0, 9)
        local onesA = (((state.level == 3) and state.roll(0, onesB - 1)) or state.roll(onesB, 9))

        a, b = ((10 * tensA) + onesA), ((10 * tensB) + onesB)
    end

    local v = (a - b)
    local oa = (a % 10)
    local ob = (b % 10)
    local ta = floor(a / 10)
    local tb = floor(b / 10)
    local trade = (ob > oa)

    local vars = {
        a = a, b = b, oa = oa, oa10 = (oa + 10), ob = ob, od = (v % 10), ta = ta, ta1 = (ta - 1), tb = tb, td = floor(v / 10),
        v = v,
    }

    local named = { { (a + b), why = "added" } }

    if trade then
        insert(named, 1, { (((ta - tb) * 10) + (ob - oa)), why = "noTrade" })
    end

    return Numeric(state, "math.subtract", "subtractBig", vars, With(named, (v + 10), (v - 10), (v + 1), (v - 1)),
        { cases = ((trade and { "trade" }) or nil) })
end

-- A small sum asked again is asked as one at any grade.
Generators["math.add"] = function(state)
    return ((((state.grade >= 2) and not AskedFact(state, FitsSmallSum)) and AddBig(state)) or AddSmall(state))
end

Generators["math.compare"] = function(state)
    local lo = (((state.level == 3) and state.roll(1, 5)) or 1)

    return Extreme(state, "math.compare", "compare", FourOf(state, lo, ((state.level == 3) and (lo + 5)) or 10), Chance(state, 2), {})
end

Generators["math.count"] = function(state)
    local n = state.roll(({ 2, 3, 5 })[state.level], ({ 5, 8, 10 })[state.level])
    local thing = Pick(state, MathWords.countables)
    local counting = {}

    for i = 1, n do
        counting[i] = i
    end

    local vars = {
        counted = Count(n, { thing[2], thing[3] }), counting = concat(counting, ", "), row = Trim(rep(thing[1] .. " ", n)),
        thing = thing[2], things = thing[3], v = n,
    }

    local named = { { (n + 1), why = "extra" }, { (n - 1), why = "missed" } }

    if Chance(state, 2) then
        named[1], named[2] = named[2], named[1]
    end

    local puzzle = Numeric(state, "math.count", "count", vars, With(named, (n + 2), (n - 2)), { hi = 12 })
    -- vars.row is the prompt's text version of the picture.
    puzzle.picture = { item = thing[2], kind = "count", n = n, row = vars.row }

    return puzzle
end

-- Tenths: adding (level 1 stays under 1), subtracting at level 3, comparing at level 2.
Generators["math.decimal"] = function(state)
    if (state.level == 2) and Chance(state, 2) then
        return DecimalCompare(state)
    end

    local a = (((state.level == 1) and state.roll(1, 8)) or state.roll(11, 59))
    local b = (((state.level == 1) and state.roll(1, 9 - a)) or state.roll(11, 49))
    local subtract = ((state.level == 3) and Chance(state, 2))

    if subtract then
        a, b = (max(a, b) + (((a == b) and 11) or 0)), min(a, b)
    end

    local v = ((subtract and (a - b)) or (a + b))
    local unit = ((subtract and " cups") or " miles")
    local named = { { (10 * v), why = "point" } }

    if subtract and ((b % 10) > (a % 10)) then
        insert(named, 1, { (((floor(a / 10) - floor(b / 10)) * 10) + ((b % 10) - (a % 10))), why = "noTrade" })
    elseif not subtract and (((a % 10) + (b % 10)) >= 10) then
        named[#named + 1] = { (v - 10), why = "carry" }
    end

    With(named, (v + 1), (v - 1), (v + 2))

    -- A whole one off is a slip worth showing only once the numbers pass 1.
    if state.level > 1 then
        With(named, (v + 10))
    end

    return Numeric(state, "math.decimal", (subtract and "decimalSubtract") or "decimalAdd",
        {
            a = a, b = b, da = Tenths(a), db = Tenths(b), dv = Tenths(v), report = (v / 10), tenthsA = Count(a, TenthWords),
            tenthsB = Count(b, TenthWords), tenthsV = Count(v, TenthWords), v = v,
        }, named,
        { format = function(tenths) return (Tenths(tenths) .. unit) end, lo = 1 })
end

Generators["math.divide"] = function(state)
    local a, b = AskedFact(state, FitsDivision)

    if a == nil then
        local q

        b, q = Factors(state)
        a = (b * q)
    end

    local q = (a / b)

    local puzzle = Numeric(state, "math.divide", "divide", { a = a, b = b, skips = Skips(b, q), v = q },
        { { (a * b), why = "multiplied" }, { (a - b), why = "subtracted" }, (q + 1), (q - 1), (q + 2), (q - 2), (b + q) },
        {})

    puzzle.fact = { a = a, b = b }

    return puzzle
end

Generators["math.fraction"] = function(state)
    local d = state.roll(({ 2, 2, 3 })[state.level], ({ 4, 10, 8 })[state.level])
    local n = (((state.level == 3) and state.roll(2, d - 1)) or 1)
    local t = (d * state.roll(2, ({ 6, 6, 12 })[state.level]))
    local part = (t / d)
    local v = (part * n)
    local named = { { d, why = "bottom" }, { n, why = "top" }, { part, why = "onePart" }, { (t - v), why = "rest" } }

    return Numeric(state, "math.fraction", "fraction", { d = d, n = n, part = part, t = t, v = v },
        With(named, (v + d), (v * 2), (v + 1), (v - 1)), { cases = (((n == 1) and { "unit" }) or nil), hi = (t + d) })
end

Generators["math.groups"] = function(state)
    local a, b = Factors(state)
    local v = (a * b)

    return Numeric(state, "math.groups", "groups", { a = a, b = b, skips = Skips(b, a), v = v },
        { { (a + b), why = "added" }, { b, why = "oneGroup" }, (v + a), (v - a), (v + b), (v - b), (v + 1), (v - 1) }, {})
end

Generators["math.missing"] = function(state)
    local c = state.roll(({ 5, 10, 14 })[state.level], ({ 10, 15, 20 })[state.level])
    local a = state.roll(1, c - 1)
    local v = (c - a)

    return Numeric(state, "math.missing", "missing", { a = a, c = c, v = v },
        { { (c + a), why = "added" }, { (v + 1), why = "start" }, (v - 1), (v + 2), (v - 2) }, {})
end

-- A times-table fact asked again is asked as one at any grade.
Generators["math.multiply"] = function(state)
    return ((((state.grade >= 4) and not AskedFact(state, FitsTimes)) and MultiplyBig(state)) or MultiplyFacts(state))
end

Generators["math.multistep"] = function(state)
    local key, vars, wrong = Pick(state, { Change, Packs, Share })(state)

    return Numeric(state, "math.multistep", key, vars, wrong, {})
end

-- Of a price, or off it; the steps build the percent from a tenth, a half or a quarter.
Generators["math.percent"] = function(state)
    local n, p, mine = PercentPlan(state)
    local off = ((n * p) / 100)
    local sale = (not mine and (state.level > 1))
    local v = ((sale and (n - off)) or off)
    local named

    local vars = {
        five = (n / 20), gear = Pick(state, MathWords.gear), half = (n / 2), n = n, off = off, p = p, quarter = (n / 4),
        ten = (n / 10), v = v,
    }

    local way = MathWords.percent.ways[p]

    vars.how, vars.strategy, vars.way, vars.work = Fill(way.how, vars), Fill(way.strategy, vars), Fill(way.way, vars), Fill(way.work, vars)

    if sale then
        named = { { off, why = "discount" }, { (n - p), why = "gold" } }

        if p ~= 10 then
            named[#named + 1] = { (n - (n / 10)), why = "tenth" }
        end

        With(named, (v + 5), (v - 5), (n + off))
    else
        named = { { p, why = "percent" } }

        if p ~= 10 then
            named[#named + 1] = { (n / 10), why = "tenth" }
        end

        With(named, { (n - off), why = "rest" }, { n, why = "whole" }, (off + 10), (off + 5))
    end

    return Numeric(state, "math.percent", "percent", vars, named, {
        cases = (((mine and { "mine" }) or (sale and { "sale" })) or nil), format = function(gold) return (gold .. " gold") end,
        hi = max(n * 2, p + 10),
    })
end

Generators["math.ratio"] = function(state)
    local x = (((state.level == 1) and 1) or state.roll(2, 4))
    local y = state.roll(x + 1, ((x == 1) and 5) or 7)
    local m = state.roll(2, 6)
    local v = (y * m)

    if state.level == 3 then
        local group = Pick(state, MathWords.ratioGroups)
        local t = ((x + y) * m)
        local vars = { first = group[1], m = m, second = group[2], t = t, v = v, x = x, xy = (x + y), y = y }

        return Numeric(state, "math.ratio", "ratioPart", vars,
            { { (x * m), why = "other" }, { (t - y), why = "takeAway" }, { m, why = "groups" }, (v + y), (v - y), (t / y) }, { hi = t })
    end

    local pair = Pick(state, MathWords.ratios)
    local h = (x * m)

    local vars = {
        d = (y - x), firstMany = pair[1][2], firstOne = pair[1][1], h = h, have = Count(h, pair[1]), m = m, second = pair[2][2],
        sentence = Fill(pair[3], { X = Count(x, pair[1]), Y = Count(y, pair[2]) }), v = v, x = x, y = y,
    }

    return Numeric(state, "math.ratio", "ratio", vars,
        { { (h + (y - x)), why = "added" }, { (h * y), why = "multiplied" }, (h + y), (v + y), (v - y) },
        { cases = (((x == 1) and { "one" }) or nil), hi = ((h * y) + 10) })
end

-- The mistakes are one group short (always a choice), then two of the others, so neither number of the answer repeats
-- among the choices: it can't be found as the most common one.
Generators["math.remainder"] = function(state)
    local d = state.roll(({ 2, 3, 6 })[state.level], ({ 5, 9, 9 })[state.level])
    local q = state.roll(({ 2, 3, 5 })[state.level], ({ 9, 12, 15 })[state.level])
    local r = state.roll(1, d - 1)
    local a = ((q * d) + r)
    local Say = function(quotient, remainder) return (quotient .. ", with " .. remainder .. " left over") end
    local text = Text("remainder")
    local vars = Vars(state, { a = a, b = d, bq = (d * (q + 1)), bv = (q * d), q1 = (q + 1), r = r, terms = { a, d }, v = q })
    local short = Say(q - 1, r + d)
    local wrongs = { { short, why = Why(text.whys.short, vars, { choice = short, left = (r + d) }) } }
    local seen = { [Say(q, r)] = true, [short] = true }

    local others = {
        { (q + 1), (d - r), "over" }, { r, q, "swapped" }, { (q + r), 0, "leftovers" }, { (q + 1), 0, "roundedUp" },
        { (q - 2), (r + (2 * d)), "shortTwo" },
    }

    for _, mistake in ipairs(Shuffle(state, others)) do
        local said = Say(mistake[1], mistake[2])

        if (#wrongs < 3) and (mistake[1] >= 1) and (mistake[1] ~= q) and (mistake[2] ~= r) and not seen[said] then
            seen[said] = true
            wrongs[#wrongs + 1] = { said, why = Why(text.whys[mistake[3]], vars, { choice = said, left = mistake[2] }) }
        end
    end

    return Finish(state, "math.remainder", text, vars, Say(q, r), wrongs)
end

Generators["math.skip"] = function(state)
    local step
    local start

    if state.level == 1 then
        step = Pick(state, { 2, 5, 10 })
        start = (step * state.roll(1, min(10, (100 - (4 * step)) / step)))
    elseif state.level == 2 then
        step = Pick(state, { 3, 4, 5, 10 })
        start = state.roll(1, min(40, 100 - (4 * step)))
    else
        step = -Pick(state, { 2, 5, 10 })
        start = state.roll(1 - (4 * step), 100)
    end

    local shown = { start, (start + step), (start + (2 * step)), (start + (3 * step)) }
    local v = (start + (4 * step))

    local vars = {
        last = shown[4], n = (((step < 0) and -step) or step), shown = concat(shown, ", "), start = start, terms = { start, step },
        v = v,
    }

    return Numeric(state, "math.skip", "skip", vars,
        { { (shown[4] + (((step < 0) and -1) or 1)), why = "ones" }, { (v + step), why = "twice" }, (v + 1), (v - 1), (v - (2 * step)),
            (v + 10), (v - 10) }, { cases = (((step < 0) and { "back" }) or nil), hi = 110, lo = 1 })
end

-- A small difference asked again is asked as one at any grade, never as levels to go.
Generators["math.subtract"] = function(state)
    if (state.grade == 0) or AskedFact(state, FitsSmallDifference) then
        return SubtractSmall(state)
    end

    return (LevelsToGo(state, ((state.grade == 1) and 20) or 60)
        or (((state.grade == 1) and SubtractSmall(state)) or SubtractBig(state)))
end

Kit.AddMistakes = AddMistakes
Kit.AddParts = AddParts
Kit.Numeric = Numeric
Kit.Text = Text
Kit.Why = Why
Kit.With = With
