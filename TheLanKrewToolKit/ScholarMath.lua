local addonName, ns = ...

-- The math generators: one function per math kind in ScholarWords.kinds, registered in Kit.Generators for Generate
-- (ScholarPuzzles.lua, which loads first). Pure like ScholarPuzzles.lua.
--
-- Every puzzle here is numeric: it carries value (the answer as a number; copper for money, tenths as a decimal) and,
-- for calculations, expression (ASCII: + - x / and parentheses), so callers and tests can recompute it.

-- Times-table factor ranges per level: { first from, first to, second from, second to }.
local FactRanges = { { 2, 5, 2, 5 }, { 2, 10, 2, 5 }, { 3, 10, 3, 10 } }

-- Order of operations, per level: forms returning the text, its value and the classic slips (working left to right, or
-- ignoring the parentheses). Every form stays positive.
local OrderForms = {
    {
        function(a, b, c) return ((a + 4) .. " + " .. b .. " x " .. c), ((a + 4) + (b * c)), (((a + 4) + b) * c) end,
        function(a, b, c) return (((b * c) + a) .. " - " .. b .. " x " .. c), a, ((((b * c) + a) - b) * c) end,
    },
    {
        function(a, b, c) return ("(" .. a .. " + " .. b .. ") x " .. c), ((a + b) * c), (a + (b * c)) end,
        function(a, b, c, d)
            return ((a + 5) .. " + " .. b .. " x " .. c .. " - " .. d), (((a + 5) + (b * c)) - d), ((((a + 5) + b) * c) - d)
        end,
        function(a, b, _, d) return (a .. " x (" .. (b + d) .. " - " .. d .. ")"), (a * b), ((a * (b + d)) - d) end,
    },
    {
        function(a, b, c, d)
            return (a .. " + " .. b .. " x (" .. (c + d) .. " - " .. d .. ")"), (a + (b * c)), ((a + b) * c), ((a + (b * (c + d))) - d)
        end,
        function(a, b, c, d)
            return ("(" .. a .. " + " .. b .. ") x (" .. (c + d) .. " - " .. c .. ")"), ((a + b) * d), ((a + (b * (c + d))) - c)
        end,
        function(_, b, c, d)
            return ((c + d) .. " x " .. (b + 1) .. " - " .. c .. " x " .. b), (((c + d) * (b + 1)) - (c * b)),
                ((((c + d) * (b + 1)) - c) * b)
        end,
    },
}

-- The largest sum or starting number, per grade (0 and 1) and level.
local SmallCap = { [0] = { 5, 7, 10 }, { 12, 16, 20 } }

local concat = table.concat
local floor, max, min = math.floor, math.max, math.min
local ipairs, tostring = ipairs, tostring
local rep = string.rep

local Kit = ns.Puzzles.Kit
local Chance, Fill, Pick, Shuffle, Trim = Kit.Chance, Kit.Fill, Kit.Pick, Kit.Shuffle, Kit.Trim
local Coins, Count, Finish, Vars, WrongNumbers = Kit.Coins, Kit.Count, Kit.Finish, Kit.Vars, Kit.WrongNumbers
local Generators, Words = Kit.Generators, Kit.Words

-- Four distinct numbers from lo to hi.
local function FourOf(state, lo, hi)
    local pool = {}

    for n = lo, hi do
        pool[#pool + 1] = n
    end

    pool = Shuffle(state, pool)

    return { pool[1], pool[2], pool[3], pool[4] }
end

-- A math puzzle whose choices are numbers. vars.v is the answer; Words.math[key] is the text; options = { lo, hi,
-- format } bounds and formats the distractors.
local function Numeric(state, kind, key, vars, wrong, options)
    options = (options or {})
    local format = (options.format or tostring)
    local wrongs = {}

    for i, n in ipairs(WrongNumbers(state, vars.v, wrong, options.lo, options.hi)) do
        wrongs[i] = format(n)
    end

    return Finish(state, kind, Words.math[key], Vars(state, vars), format(vars.v), wrongs)
end

-- Two-digit addition: level 1 never regroups, level 3 always does.
local function AddBig(state)
    local a, b

    if state.level == 2 then
        a = state.roll(10, 60)
        b = state.roll(5, 99 - a)
    else
        local tensA, onesA = state.roll(1, 7), state.roll(((state.level == 3) and 1) or 0, 8)
        local tensB = state.roll(1, 8 - tensA)
        local onesB = (((state.level == 3) and state.roll(10 - onesA, 9)) or state.roll(0, 9 - onesA))

        a, b = ((10 * tensA) + onesA), ((10 * tensB) + onesB)
    end

    local v = (a + b)

    return Numeric(state, "math.add", "addBig", { a = a, b = b, v = v },
        { (v + 10), (v - 10), (v + 1), (v - 1), (v + 11) }, { hi = 110 })
end

local function AddSmall(state)
    local cap, low = SmallCap[state.grade][state.level], (((state.grade == 0) and 1) or 2)
    local a = state.roll(low, cap - low)
    local b = state.roll(low, cap - a)
    local v = (a + b)

    return Numeric(state, "math.add", "addSmall", { a = a, b = b, v = v },
        { (v + 1), (v - 1), (v + 2), (v - 2), (a - b), (b - a) }, { hi = (cap + 2) })
end

-- Grade 1 and 2 subtraction sometimes counts the player's levels to a milestone.
local function LevelsToGo(state, goal)
    local level = state.context.level

    if level and (level < goal) and Chance(state, 3) then
        local v = (goal - level)

        return Numeric(state, "math.subtract", "levels", { a = goal, b = level, v = v },
            { (v + 1), (v - 1), (v + 10), (v - 10), goal }, { hi = goal })
    end
end

-- Two-digit subtraction: level 1 never borrows, level 3 always does.
local function SubtractBig(state)
    local a, b

    if state.level == 2 then
        a = state.roll(20, 99)
        b = state.roll(5, a - 1)
    else
        local tensA = state.roll(2, 9)
        local tensB, onesB = state.roll(1, tensA - 1), state.roll(((state.level == 3) and 1) or 0, 9)
        local onesA = (((state.level == 3) and state.roll(0, onesB - 1)) or state.roll(onesB, 9))

        a, b = ((10 * tensA) + onesA), ((10 * tensB) + onesB)
    end

    local v = (a - b)
    local noBorrow = (((floor(a / 10) - floor(b / 10)) * 10) + ((b % 10) - (a % 10)))

    return Numeric(state, "math.subtract", "subtractBig", { a = a, b = b, v = v },
        { noBorrow, (v + 10), (v - 10), (v + 1), (v - 1) }, { hi = 100 })
end

local function SubtractSmall(state)
    local cap = SmallCap[state.grade][state.level]
    local a = state.roll(((state.grade == 0) and 2) or 5, cap)
    local b = state.roll(1, (((state.grade == 0) and (state.level == 3)) and a) or (a - 1))
    local v = (a - b)

    return Numeric(state, "math.subtract", "subtractSmall", { a = a, b = b, v = v },
        { (v + 1), (v - 1), (a + b), (v + 2), b }, { hi = (cap + 2) })
end

-- A number of tenths as a decimal: 35 is "3.5".
local function Tenths(tenths)
    return (floor(tenths / 10) .. "." .. (tenths % 10))
end

-- Which of four numbers is biggest or smallest; decimals come in tenths.
local function Extreme(state, kind, key, four, biggest, tenths)
    local best = ((biggest and max(four[1], four[2], four[3], four[4])) or min(four[1], four[2], four[3], four[4]))
    local format, wrongs, terms = ((tenths and Tenths) or tostring), {}, {}

    for i, n in ipairs(four) do
        terms[i] = ((tenths and (n / 10)) or n)

        if n ~= best then
            wrongs[#wrongs + 1] = format(n)
        end
    end

    local vars = { report = ((tenths and (best / 10)) or best), terms = terms, v = format(best),
        when = ((biggest and "last") or "first"), word = ((biggest and "biggest") or "smallest") }

    return Finish(state, kind, Words.math[key], vars, format(best), wrongs)
end

Generators["math.add"] = function(state)
    return (((state.grade >= 2) and AddBig(state)) or AddSmall(state))
end

Generators["math.subtract"] = function(state)
    if state.grade == 0 then
        return SubtractSmall(state)
    end

    return (LevelsToGo(state, ((state.grade == 1) and 20) or 60)
        or (((state.grade == 1) and SubtractSmall(state)) or SubtractBig(state)))
end

Generators["math.count"] = function(state)
    local n = state.roll(({ 1, 3, 5 })[state.level], ({ 5, 8, 10 })[state.level])
    local thing = Pick(state, Words.countables)

    local vars = { counted = Count(n, { thing[2], thing[3] }), row = Trim(rep(thing[1] .. " ", n)), things = thing[3],
        v = n }

    local puzzle = Numeric(state, "math.count", "count", vars, { (n + 1), (n - 1), (n + 2), (n - 2) }, { hi = 12 })
    -- vars.row is the prompt's text version of the picture.
    puzzle.picture = { item = thing[2], kind = "count", n = n, row = vars.row }

    return puzzle
end

Generators["math.compare"] = function(state)
    local lo = (((state.level == 3) and state.roll(1, 5)) or 1)

    return Extreme(state, "math.compare", "compare", FourOf(state, lo, ((state.level == 3) and (lo + 5)) or 10), Chance(state, 2))
end

Generators["math.missing"] = function(state)
    local c = state.roll(({ 5, 10, 14 })[state.level], ({ 10, 15, 20 })[state.level])
    local a = state.roll(1, c - 1)
    local v = (c - a)

    return Numeric(state, "math.missing", "missing", { a = a, c = c, v = v }, { (v + 1), (v - 1), (c + a), c, (v + 2) }, { hi = 22 })
end

Generators["math.skip"] = function(state)
    local step, start

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

    local vars = { n = (((step < 0) and -step) or step), shown = concat(shown, ", "), start = start,
        terms = { start, step }, v = v }

    return Numeric(state, "math.skip", ((step < 0) and "skipBack") or "skip", vars,
        { (v + 1), (v - 1), (v + step), (v - (2 * step)), (v + 10), (v - 10) }, { hi = 110, lo = 1 })
end

-- Copper within 100; sometimes the player's own copper when they have less than 90.
Generators["math.coins"] = function(state)
    local mine, key, a, b = state.context.copper, nil, nil, nil

    if mine and (mine >= 1) and (mine <= 90) and Chance(state, 2) then
        key, a = "coinsMine", mine
        b = state.roll(1, min(50, 100 - a))
    elseif state.level < 3 then
        key = "coinsAdd"
        a = (((state.level == 1) and (10 * state.roll(1, 5))) or state.roll(11, 60))
        b = (((state.level == 1) and (10 * state.roll(1, 9 - (a / 10)))) or state.roll(5, 100 - a))
    else
        key, a, b = "coinsChange", 100, state.roll(5, 95)
    end

    local v = (((key == "coinsChange") and (a - b)) or (a + b))

    return Numeric(state, "math.coins", key, { a = a, b = b, v = v }, { (v + 10), (v - 10), (v + 1), (v - 1), (100 - v) },
        { format = function(n) return (n .. " copper") end, hi = 100, lo = 1 })
end

local function Factors(state)
    local range = FactRanges[state.level]
    local a, b = state.roll(range[1], range[2]), state.roll(range[3], range[4])

    if Chance(state, 2) then
        return b, a
    end

    return a, b
end

local function Facts(state, kind, key)
    local a, b = Factors(state)
    local v = (a * b)

    return Numeric(state, kind, key, { a = a, b = b, v = v },
        { (v + a), (v - a), (v + b), (v - b), (a + b), (v + 1), (v - 1) }, { hi = 110 })
end

-- Two digits times one digit; a classic slip is forgetting to carry.
local function MultiplyBig(state)
    local range = ({ { 11, 25, 2, 5 }, { 12, 60, 3, 9 }, { 25, 99, 6, 9 } })[state.level]
    local a, b = state.roll(range[1], range[2]), state.roll(range[3], range[4])
    local v = (a * b)
    local noCarry = (((floor(a / 10) * b) * 10) + (((a % 10) * b) % 10))

    return Numeric(state, "math.multiply", "bigMultiply", { a = a, b = b, v = v },
        { noCarry, (v + 10), (v - 10), (v + b), (v - b), (a * (b + 1)) }, { hi = 1000 })
end

Generators["math.multiply"] = function(state)
    return (((state.grade >= 4) and MultiplyBig(state)) or Facts(state, "math.multiply", "multiply"))
end

Generators["math.groups"] = function(state)
    return Facts(state, "math.groups", "groups")
end

Generators["math.divide"] = function(state)
    local b, q = Factors(state)

    return Numeric(state, "math.divide", "divide", { a = (b * q), b = b, v = q },
        { (q + 1), (q - 1), (q + 2), (q - 2), (b + q) }, { hi = 20 })
end

Generators["math.remainder"] = function(state)
    local d = state.roll(({ 2, 3, 6 })[state.level], ({ 5, 9, 9 })[state.level])
    local q = state.roll(({ 2, 3, 5 })[state.level], ({ 9, 12, 15 })[state.level])
    local r = state.roll(1, d - 1)
    local Say = function(quotient, remainder) return (quotient .. ", with " .. remainder .. " left over") end
    local wrongs = {}

    for _, wrong in ipairs({ { (q + 1), r }, { (q - 1), r }, { q, (r + 1) }, { q, (r - 1) }, { r, q }, { q, 0 } }) do
        if (wrong[1] >= 1) and (wrong[2] >= 0) and ((wrong[1] ~= q) or (wrong[2] ~= r)) then
            wrongs[#wrongs + 1] = Say(wrong[1], wrong[2])
        end
    end

    local vars = Vars(state, { a = ((q * d) + r), b = d, bv = (q * d), r = r, terms = { ((q * d) + r), d }, v = q })

    return Finish(state, "math.remainder", Words.math.remainder, vars, Say(q, r), wrongs)
end

-- Silver and copper; sometimes the player's own purse when it's under 100 silver.
Generators["math.money"] = function(state)
    local mine = state.context.copper

    mine = ((mine and (mine >= 100) and (mine <= 9999) and Chance(state, 2) and mine) or nil)
    local key, a, b, v, wrong

    if (state.level == 3) or (mine and (mine > 9000)) then
        a = (mine or ((100 * state.roll(3, 9)) + state.roll(0, 49)))
        local copper = ((((a % 100) < 99) and state.roll((a % 100) + 1, 99)) or state.roll(0, 98))

        b = ((100 * state.roll(1, max(1, floor(a / 100) - 1))) + copper)
        b = (((b < a) and b) or state.roll(1, a - 1))
        key, v = "moneySubtract", (a - b)
        wrong = { (((floor(a / 100) - floor(b / 100)) * 100) + ((b % 100) - (a % 100))), (v + 100), (v - 100), (v + 10), (v - 10) }
    elseif (state.level == 2) or mine then
        a, b = (mine or state.roll(101, 599)), state.roll(101, 599)
        key, v = "moneyAdd", (a + b)
        wrong = { (v - 100), (v + 100), (v + 10), (v - 10), (v - (v % 100)) }
    else
        a = state.roll(101, 999)
        key, v = "moneyConvert", a
        wrong = { ((floor(a / 10) * 100) + (a % 10)), (a + 100), (a - 100), ((floor(a / 100) * 100) + floor((a % 100) / 10)), (a + 1) }
    end

    local vars = { a = a, b = b, ca = Coins(a), cb = (b and Coins(b)), cv = Coins(v), v = v }

    return Numeric(state, "math.money", (mine and (key .. "Mine")) or key, vars, wrong, { format = Coins, hi = 9999, lo = 1 })
end

Generators["math.fraction"] = function(state)
    local d = state.roll(({ 2, 2, 3 })[state.level], ({ 4, 10, 8 })[state.level])
    local n = (((state.level == 3) and state.roll(2, d - 1)) or 1)
    local t = (d * state.roll(2, ({ 6, 6, 12 })[state.level]))
    local v = ((t / d) * n)

    return Numeric(state, "math.fraction", "fraction", { d = d, n = n, part = (t / d), t = t, v = v },
        { (t - v), (t / d), (v + d), (v * 2), (t - d), (v - 1) }, { hi = t })
end

local function Change(state)
    local n = state.roll(2, 5)

    local p = (((state.level == 1) and (5 * state.roll(1, 4)))
        or state.roll(((state.level == 2) and 6) or 11, ((state.level == 2) and 25) or 45))

    local m = (50 * (floor((n * p) / 50) + 1))
    local v = (m - (n * p))

    return "change", { m = m, n = n, np = (n * p), p = p, v = v }, { (n * p), (m - p), (v + 10), (v - 10), (v + p) }
end

local function Packs(state)
    local a, b, c = state.roll(5, (10 * state.level) + 10), state.roll(2, 6), state.roll(4, 4 + (3 * state.level))
    local v = (a + (b * c))

    return "packs", { a = a, b = b, bc = (b * c), c = c, v = v }, { ((a + b) * c), ((a + b) + c), (b * c), (v + c), (v - c) }
end

local function Share(state)
    local n, q, e = state.roll(2, 6), state.roll(2, 3 + (2 * state.level)), state.roll(2, 9)
    local v = (q + e)

    return "share", { e = e, n = n, q = q, t = (n * q), v = v }, { q, ((n * q) + e), (v + 1), (v - 1), (((n * q) - n) + e) }
end

Generators["math.multistep"] = function(state)
    local key, vars, wrong = Pick(state, { Change, Packs, Share })(state)

    return Numeric(state, "math.multistep", key, vars, wrong, { hi = 1000 })
end

-- Tenths: adding (level 1 stays under 1), subtracting at level 3, comparing at level 2.
Generators["math.decimal"] = function(state)
    if (state.level == 2) and Chance(state, 2) then
        local base = (10 * state.roll(1, 5))

        return Extreme(state, "math.decimal", "decimalCompare", FourOf(state, base, base + 19), true, true)
    end

    local a = (((state.level == 1) and state.roll(1, 8)) or state.roll(11, 59))
    local b = (((state.level == 1) and state.roll(1, 9 - a)) or state.roll(11, 49))
    local subtract = ((state.level == 3) and Chance(state, 2))

    if subtract then
        a, b = (max(a, b) + (((a == b) and 11) or 0)), min(a, b)
    end

    local v = ((subtract and (a - b)) or (a + b))
    local unit = ((subtract and " cups") or " miles")

    return Numeric(state, "math.decimal", (subtract and "decimalSubtract") or "decimalAdd",
        { da = Tenths(a), db = Tenths(b), dv = Tenths(v), report = (v / 10), v = v }, { (v + 1), (v - 1), (v + 10), (v - 10), (v + 2) },
        { format = function(tenths) return (Tenths(tenths) .. unit) end, hi = 200, lo = 1 })
end

-- A price and a percent that divide evenly; sometimes the player's own gold.
local function PercentPlan(state)
    local mine = (state.context.copper and floor(state.context.copper / 10000))

    if mine and (mine >= 10) and (mine <= 1000) and Chance(state, 2) then
        for _, percent in ipairs(Shuffle(state, { 10, 20, 25, 50 })) do
            if ((mine * percent) % 100) == 0 then
                return mine, percent, true
            end
        end
    end

    local percent = Pick(state, ({ { 10, 50 }, { 10, 20, 25, 50 }, { 15, 30, 40, 60, 75 } })[state.level])

    return (({ 10, 20, 20 })[state.level] * state.roll(2, ({ 20, 10, 15 })[state.level])), percent, false
end

Generators["math.percent"] = function(state)
    local n, p, mine = PercentPlan(state)
    local off = ((n * p) / 100)
    local key = ((mine and "percentMine") or ((state.level == 1) and "percentOf") or "percentSale")
    local sale = (key == "percentSale")
    local v = ((sale and (n - off)) or off)
    local wrong = ((sale and { off, (n - p), (n + off), (v + 5), (v - 5) }) or { (n - off), p, (off * 2), (off + 10), (n / 5) })

    return Numeric(state, "math.percent", key, { gear = Pick(state, Words.gear), n = n, off = off, p = p, v = v }, wrong,
        { format = function(gold) return (gold .. " gold") end, hi = (n * 2) })
end

Generators["math.ratio"] = function(state)
    local x = (((state.level == 1) and 1) or state.roll(2, 4))
    local y, m = state.roll(x + 1, ((x == 1) and 5) or 7), state.roll(2, 6)
    local v = (y * m)

    if state.level == 3 then
        local group, t = Pick(state, Words.ratioGroups), ((x + y) * m)
        local vars = { first = group[1], m = m, second = group[2], t = t, v = v, x = x, xy = (x + y), y = y }

        return Numeric(state, "math.ratio", "ratioPart", vars, { (x * m), (t - y), (t / y), (v + y), (v - y) }, { hi = t })
    end

    local pair, h = Pick(state, Words.ratios), (x * m)

    local vars = {
        h = h, have = Count(h, pair[1]), m = m, second = pair[2][2],
        sentence = Fill(pair[3], { X = Count(x, pair[1]), Y = Count(y, pair[2]) }), v = v, x = x, y = y,
    }

    return Numeric(state, "math.ratio", "ratio", vars, { ((h + y) - x), (h * y), (h + y), (v + y), (v - y) }, { hi = ((h * y) + 10) })
end

Generators["math.order"] = function(state)
    local form = Pick(state, OrderForms[state.level])
    local a, b, c, d = state.roll(2, 6), state.roll(2, 6), state.roll(2, 6), state.roll(2, 6)
    local text, v, slip, other = form(a, b, c, d)

    return Numeric(state, "math.order", "order", { text = text, v = v },
        { slip, (other or (v + 3)), (v + 1), (v - 1), (v + 2) }, { hi = 10000, lo = 1 })
end
