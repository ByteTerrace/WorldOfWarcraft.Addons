-- How Scholar's math riddles teach (ScholarMath.lua and ScholarMathWords.lua): every riddle offers the answer its
-- kind's known mistake produces, with a why that names the mistake; it has a worked first step, praise that names the
-- strategy, and an explanation that shows the working; the answer's place among the numbers gives nothing away; and
-- hints fit the riddle they're on. The mistakes below are an independent list of what each kind invites, most telling
-- first: a riddle must offer the first one that's a fair choice (a whole number, not the answer, positive unless the
-- answer is 0).

local Context = { class = "MAGE", copper = 4567, level = 12, name = "Tessa", zone = "Duskwood" }
local Kit = use("scholar")
local Numbers = Kit.Numbers

-- The mistakes two-digit addition invites: leaving out the carry, adding only the tens, adding the tens as ones.
local function AddMistakes(a, b)
    local tens, out = (math.floor(a / 10) + math.floor(b / 10)), {}

    if ((a % 10) + (b % 10)) >= 10 then
        out[1] = ((a + b) - 10)
    end

    out[#out + 1] = (10 * tens)
    out[#out + 1] = tens

    return out
end

-- A clock time's minutes, its hour times 60 plus its minutes, or nil for text that isn't one.
local function ClockMinutes(text)
    local hour, minutes = text:match("^(%d+):(%d%d)$")

    return ((hour and ((tonumber(hour) * 60) + tonumber(minutes))) or nil)
end

-- Evaluates text strictly from left to right (parentheses kept), or with the parentheses dropped, by precedence or not.
local function Evaluate(text, keepParens, precedence)
    local flat = text:gsub("%s", "")

    if not keepParens then
        flat = flat:gsub("[%(%)]", "")
    end

    local at = 1
    local Sum

    local function Atom()
        local open = flat:match("^%(", at)

        if open then
            at = (at + 1)
            local v = Sum()

            at = (at + 1)

            return v
        end

        local number = flat:match("^%d+", at)

        at = (at + #number)

        return tonumber(number)
    end

    local function Product()
        local v = Atom()

        while precedence and ((flat:sub(at, at) == "x") or (flat:sub(at, at) == "/")) do
            local op = flat:sub(at, at)

            at = (at + 1)
            v = (((op == "x") and (v * Atom())) or (v / Atom()))
        end

        return v
    end

    Sum = function()
        local v = Product()

        while (flat:sub(at, at) ~= "") and (flat:sub(at, at) ~= ")") do
            local op = flat:sub(at, at)

            at = (at + 1)
            local r = Product()

            v = (((op == "+") and (v + r)) or ((op == "-") and (v - r)) or ((op == "x") and (v * r)) or (v / r))
        end

        return v
    end

    return Sum()
end

-- The hour before hour on a clock face.
local function LastHour(hour)
    return (((hour + 10) % 12) + 1)
end

local function Same(a, b)
    if type(a) == "table" then
        return ((type(b) == "table") and (a[1] == b[1]) and (a[2] == b[2]))
    end

    return ((type(b) == "number") and (math.abs(a - b) < 1e-9))
end

-- The answer's own numbers: copper for money, { quotient, remainder } for remainders, minutes for a clock time, else
-- its number.
local function Value(p, choice)
    if ClockMinutes(choice) then
        return ClockMinutes(choice)
    elseif p.kind == "math.money" then
        return ((tonumber(choice:match("(%d+) silver") or 0) * 100) + tonumber(choice:match("(%d+) copper") or 0))
    elseif p.kind == "math.remainder" then
        local q, r = choice:match("^(%d+), with (%d+) left over$")

        return { tonumber(q), tonumber(r) }
    end

    return Numbers(choice)[1]
end

-- Each kind's mistakes, most telling first, as values a choice would have; any = true when any of them will do (the
-- kind picks one at random).
local Mistakes = {
    ["math.add"] = function(p, options)
        local a, b = unpack(Numbers(p.expression))
        local v, big = p.value, math.max(a, b)

        if options.grade >= 2 then
            return AddMistakes(a, b)
        end

        return ((((big < 10) and (v > 10)) and { 10, (v - 1) }) or { (v - 1) })
    end,
    ["math.coins"] = function(p)
        local a, b = unpack(Numbers(p.expression))

        if p.expression:find("-", 1, true) then
            return ((((b % 10) > 0) and { (p.value + 10) }) or { b, (a + b) })
        end

        return AddMistakes(a, b)
    end,
    ["math.compare"] = function(p)
        local opposite = p.terms[1]

        for _, n in ipairs(p.terms) do
            opposite = ((p.prompt:find("biggest") and math.min(opposite, n)) or math.max(opposite, n))
        end

        return { opposite }
    end,
    ["math.count"] = function(p) return { (p.value + 1), (p.value - 1), any = true } end,
    ["math.decimal"] = function(p)
        if not p.expression then
            local any = { any = true }

            for _, choice in ipairs(p.choices) do
                if choice:match("^%d+%.%d%d$") and (tonumber(choice) < p.value) then
                    any[#any + 1] = tonumber(choice)
                end
            end

            return any
        end

        local a, b = unpack(Numbers(p.expression))
        local ta, tb = math.floor((a * 10) + 0.5), math.floor((b * 10) + 0.5)

        if p.expression:find("-", 1, true) and ((tb % 10) > (ta % 10)) then
            return { ((((math.floor(ta / 10) - math.floor(tb / 10)) * 10) + ((tb % 10) - (ta % 10))) / 10), (p.value * 10) }
        end

        return { (p.value * 10) }
    end,
    ["math.divide"] = function(p)
        local a, b = unpack(Numbers(p.expression))

        return { (a * b) }
    end,
    ["math.fraction"] = function(p)
        local t, n, d = unpack(Numbers(p.expression))

        return { d, n, (t / d), (t - p.value) }
    end,
    ["math.groups"] = function(p)
        local a, b = unpack(Numbers(p.expression))

        return { (a + b), b }
    end,
    ["math.missing"] = function(p)
        local c, a = unpack(Numbers(p.expression))

        return { (c + a) }
    end,
    ["math.money"] = function(p)
        local a, b = unpack(Numbers(p.expression))

        if not b then
            return { ((math.floor(a / 10) * 100) + (a % 10)) }
        elseif p.expression:find("+", 1, true) then
            local silver = ((math.floor(a / 100) + math.floor(b / 100)) * 100)

            return (((((a % 100) + (b % 100)) >= 100) and { (p.value - 100) }) or { silver, (p.value + 100) })
        elseif (b % 100) > (a % 100) then
            return { (((math.floor(a / 100) - math.floor(b / 100)) * 100) + ((b % 100) - (a % 100))) }
        end

        return { (a + b) }
    end,
    -- The trap shares the target's first digit but sits farther off; a halfway riddle's is half the gap; a star's is
    -- the jumps counted; a fraction of the way's is its number of parts.
    ["math.numberLine"] = function(p)
        local n = Numbers(p.expression)

        if p.prompt:find("closest") then
            local t, any = Numbers(p.prompt)[1], { any = true }
            local gap = math.abs(p.value - t)

            for i, choice in ipairs(p.choices) do
                local x = tonumber(choice)

                if (i ~= p.answer) and (tostring(x):sub(1, 1) == tostring(t):sub(1, 1)) and (math.abs(x - t) > gap) then
                    any[#any + 1] = x
                end
            end

            return any
        elseif p.expression:find("(", 1, true) then
            return { ((n[2] - n[1]) / 2) }
        elseif p.prompt:find("\n0 ") then
            return { n[3] }
        end

        return { n[2] }
    end,
    -- A digit's face value; the ones left over, or the tens digit alone; one more or less; the digits in the order they
    -- were said, backwards in place order, or without the empty tens place.
    ["math.placeValue"] = function(p)
        local e, n = p.expression, Numbers(p.expression)

        if e:match("^%d+ x %d+$") then
            return { n[1] }
        elseif e:find("/ 10", 1, true) then
            return (((n[1] >= 100) and { (math.floor(n[1] / 10) % 10) }) or { n[2] })
        elseif e:match("^%d+ [%+%-] %d+$") then
            return { (n[1] + ((e:find("-", 1, true) and -1) or 1)) }
        end

        local said, places = {}, { hundred = 3, hundreds = 3, one = 1, ones = 1, ten = 2, tens = 2 }
        local inOrder, last, zero = true, 4, (p.prompt:find("hundred") and not p.prompt:find("%d tens?%f[%A]"))

        for digit, place in p.prompt:gmatch("(%d+) (%a+)") do
            if places[place] then
                said[#said + 1] = digit
                inOrder, last = (inOrder and (places[place] < last)), places[place]
            end
        end

        if zero then
            return { ((10 * tonumber(p.prompt:match("(%d+) hundreds?"))) + tonumber(p.prompt:match("(%d+) ones?"))) }
        elseif not inOrder then
            return { tonumber(table.concat(said)) }
        end

        return { tonumber(table.concat(said):reverse()) }
    end,
    -- Quest riddles' mistakes: adding the count done to the count wanted, or one of two counts alone.
    ["math.multiply"] = function(p, options)
        local a, b = unpack(Numbers(p.expression))
        local v, big, small = p.value, math.max(a, b), math.min(a, b)

        if options.grade >= 4 then
            local carry = math.floor(((a % 10) * b) / 10)

            return (((carry > 0) and { (v - (10 * carry)) }) or { (a + b) })
        elseif small == 0 then
            return { big }
        elseif small == 1 then
            return { (big + 1), 1 }
        elseif big == 10 then
            return { (small + 10) }
        end

        return { (a + b), (v + big) }
    end,
    ["math.multistep"] = function(p)
        local n = Numbers(p.expression)

        if p.expression:find("-", 1, true) then
            return { (n[2] * n[3]) }
        elseif p.expression:find("/", 1, true) then
            return { (n[1] / n[2]) }
        end

        return { (n[2] * n[3]) }
    end,
    ["math.order"] = function(p)
        local text = p.expression

        return { Evaluate(text, true, false), Evaluate(text, false, false), Evaluate(text, false, true), any = true }
    end,
    ["math.percent"] = function(p)
        local n = Numbers(p.expression)
        local price, percent = n[1], n[#n - 1]
        local off = ((price * percent) / 100)

        if p.expression:find("-", 1, true) then
            return { off, (price - percent), (((percent ~= 10) and (price - (price / 10))) or off) }
        end

        return { percent, (((percent ~= 10) and (price / 10)) or percent), (price - off) }
    end,
    ["math.ratio"] = function(p)
        local n = Numbers(p.expression)

        if p.expression:find("(", 1, true) then
            local t, x, y = n[1], n[2], n[3]

            return { (x * (t / (x + y))) }
        end

        local h, x, y = n[1], n[2], n[3]

        return { ((h + y) - x) }
    end,
    ["math.remainder"] = function(p)
        local d = p.terms[2]

        return { { (p.value - 1), (p.remainder + d) } }
    end,
    ["math.skip"] = function(p)
        local start, step = p.terms[1], p.terms[2]

        return { ((start + (3 * step)) + (((step < 0) and -1) or 1)) }
    end,
    -- Words: reading the minutes like money, or quarter to as quarter past. Hands: the long hand's number as minutes. A
    -- trip: forgetting the new hour, or going back; how long: taking times away as if an hour had 100 minutes.
    ["math.time"] = function(p)
        local prompt = p.prompt
        local h = tonumber(prompt:match("half past (%d+)") or prompt:match("quarter past (%d+)") or "")

        if h then
            return { ((h * 60) + ((prompt:find("half") and 50) or 25)) }
        elseif prompt:match("quarter to (%d+)") then
            return { ((tonumber(prompt:match("quarter to (%d+)")) * 60) + 15) }
        elseif prompt:match("(%d+) minutes past (%d+)") then
            local m, hour = prompt:match("(%d+) minutes past (%d+)")

            return { ((LastHour(tonumber(hour)) * 60) + (60 - tonumber(m))) }
        elseif prompt:match("(%d+) minutes to (%d+)") then
            local k, hour = prompt:match("(%d+) minutes to (%d+)")

            return { ((tonumber(hour) * 60) + tonumber(k)) }
        elseif prompt:find("short hand") then
            local hand = tonumber(prompt:match("long hand [%a ]*the (%d+)"))
            local hour = tonumber(prompt:match("short hand [%a ]*the (%d+)"))

            return { ((hour * 60) + hand) }
        end

        local times = {}

        for hour, minutes in prompt:gmatch("(%d+):(%d%d)") do
            times[#times + 1] = ((tonumber(hour) * 60) + tonumber(minutes))
        end

        if #times == 2 then
            local m1, m2 = (times[1] % 60), (times[2] % 60)

            if math.floor(times[2] / 60) > math.floor(times[1] / 60) then
                return { (p.value + 40) }
            end

            return { (m1 + m2) }
        end

        local dur = tonumber(prompt:match("(%d+) minutes"))

        if ((times[1] % 60) + dur) >= 60 then
            return { (p.value - 60) }
        end

        return { ((((times[1] - dur) >= 60) and (times[1] - dur)) or (p.value + 60)) }
    end,
    ["math.subtract"] = function(p, options)
        local a, b = unpack(Numbers(p.expression))

        if (options.grade >= 2) and not p.prompt:find("You are level") and ((b % 10) > (a % 10)) then
            return { (((math.floor(a / 10) - math.floor(b / 10)) * 10) + ((b % 10) - (a % 10))) }
        end

        return { (a + b) }
    end,
}

-- The first of the kind's mistakes that's a fair choice, or every fair one when any will do.
local function Expected(p, options)
    local list, out = Mistakes[p.kind](p, options), {}

    -- Decimals count in tenths, so their least fair choice is 0.1.
    local least = (((p.value == 0) and 0) or ((p.kind == "math.decimal") and 0.1) or 1)

    for _, n in ipairs(list) do
        local fair = ((type(n) == "table")
            or (not Same(n, p.value) and (n >= least) and ((n == math.floor(n)) or (p.kind == "math.decimal"))))

        if fair then
            out[#out + 1] = n

            if not list.any then
                break
            end
        end
    end

    return out
end

-- Plain text a child sees: non-empty printable ASCII with no template braces and no "wrong".
local function Plain(text)
    return ((type(text) == "string") and (text ~= "") and not text:find("[^ -~]") and not text:find("[{}]")
        and not text:lower():find("wrong"))
end

-- options.random for Generate: the test Lua's own generator, refusing ranges the client's random would.
local function Roll(m, n)
    assert((m == math.floor(m)) and (n == math.floor(n)) and (m <= n), ("random(%s, %s) is not a valid range"):format(tostring(m), tostring(n)))

    return math.random(m, n)
end

-- Calls fn(puzzle, options) for seeds riddles of every math kind at each grade that asks it and every level, every
-- other one with a context.
local function Sample(puzzles, seeds, fn)
    for grade = 0, 6 do
        for _, kind in ipairs(puzzles.Kinds("math", grade)) do
            for level = 1, 3 do
                for seed = 1, seeds do
                    math.randomseed(((grade * 100000) + (level * 10000)) + seed)

                    local options = {
                        context = ((((seed % 2) == 0) and Context) or nil), grade = grade, kind = kind, level = level, random = Roll,
                        subject = "math",
                    }

                    fn(puzzles.Generate(options), options)
                end
            end
        end
    end
end

-- The answer, as text an explanation would show.
local function Shows(p)
    local correct = p.choices[p.answer]

    return (((p.kind == "math.remainder") and correct) or correct:gsub(" copper$", ""):gsub(" gold$", ""):gsub(" miles$", ""):gsub(" cups$", ""))
end

local function Where(p, options)
    return ("%s grade %d level %d: %q"):format(p.kind, options.grade, options.level, p.prompt)
end

test("every math riddle offers its kind's known mistake, with a why that names it kindly", function()
    local _, _, ns = Kit.LoadKid()

    Sample(ns.Puzzles, 30, function(p, options)
        local expected, found = Expected(p, options), false

        truthy(#expected > 0, "the kind invites a mistake that fits at " .. Where(p, options))

        for i, choice in ipairs(p.choices) do
            if i ~= p.answer then
                local why = p.whys[i]

                truthy((why == nil) or Plain(why), ("plain, kind why %q at %s"):format(tostring(why), Where(p, options)))

                for _, n in ipairs(expected) do
                    found = (found or (Same(n, Value(p, choice)) and Plain(why)))
                end
            end
        end

        truthy(found, ("a choice is the mistake %s, with its why, at %s (choices %s)"):format(tostring(expected[1]),
            Where(p, options), table.concat(p.choices, " | ")))
    end)
end)

test("every math riddle has a worked first step, strategy praise and an explanation that shows the working", function()
    local _, _, ns = Kit.LoadKid()
    local generic = {}

    for _, line in ipairs(ns.ScholarWords.praise) do
        generic[line] = true
    end

    Sample(ns.Puzzles, 30, function(p, options)
        local where = Where(p, options)

        truthy(Plain(p.step), "a step at " .. where)
        truthy(Plain(p.praise) and not generic[p.praise], ("the kind's own praise, not %q, at %s"):format(tostring(p.praise), where))

        for _, word in ipairs({ "smart", "genius", "brain", "best", "greatest", "amazing", "perfect" }) do
            falsy(p.praise:lower():find(word, 1, true), ("praise %q names the strategy, not the child, at %s"):format(p.praise, where))
        end

        local explanation = p.explanation

        truthy(explanation:find(Shows(p), 1, true), ("the explanation %q reaches the answer at %s"):format(explanation, where))
        truthy(#Numbers(explanation) >= 4, ("the explanation %q shows the working at %s"):format(explanation, where))
        falsy(explanation:find(p.praise, 1, true), "the explanation carries no praise at " .. where)
        local n = ((p.expression and Numbers(p.expression)) or {})

        if (p.kind == "math.add") and (options.grade >= 2) and (((n[1] % 10) + (n[2] % 10)) >= 10) then
            truthy(explanation:find("carry"), "regrouping shows the carry at " .. where)
        elseif (p.kind == "math.subtract") and (options.grade >= 2) and not p.prompt:find("You are level") and ((n[2] % 10) > (n[1] % 10)) then
            truthy(explanation:find("trade a ten"), "regrouping shows the trade at " .. where)
        elseif (p.kind == "math.multiply") and (options.grade >= 4) then
            local a, b = n[1], n[2]

            truthy(explanation:find(tostring((a - (a % 10)) * b), 1, true) and explanation:find(tostring((a % 10) * b), 1, true),
                "partial products at " .. where)
        elseif p.kind == "math.remainder" then
            truthy(explanation:find(tostring(p.value * p.terms[2]), 1, true), "the division and what's left at " .. where)
        elseif p.kind == "math.percent" then
            truthy(explanation:find("10%", 1, true) or explanation:find("half") or explanation:find("quarter"),
                "the easy parts of the percent at " .. where)
        elseif p.kind == "math.order" then
            truthy(explanation:find(", then ", 1, true), "each step in order at " .. where)
        elseif (p.kind == "math.add") and (options.grade <= 1) then
            truthy(explanation:find("count on") or explanation:find("makes 10"), "counting on or making ten at " .. where)
        end
    end)
end)

test("the answer's place among the numbers gives nothing away", function()
    local _, _, ns = Kit.LoadKid()
    local middle, total, over = { all = 0 }, { all = 0 }, {}

    Sample(ns.Puzzles, 120, function(p)
        -- Comparisons ask for an end by design, and remainders aren't one number. An answer needs three whole numbers
        -- below it (in tenths for decimals) to be the biggest of four at all.
        local v = Value(p, p.choices[p.answer])
        local scale = (((p.kind == "math.decimal") and 10) or 1)

        if not p.expression or (p.kind == "math.remainder") or ((v * scale) < 4) then
            return
        end

        local below = 0

        for i, choice in ipairs(p.choices) do
            if (i ~= p.answer) and (Value(p, choice) < v) then
                below = (below + 1)
            end
        end

        local inside = ((((below == 1) or (below == 2)) and 1) or 0)

        total[p.kind], total.all = ((total[p.kind] or 0) + 1), (total.all + 1)
        middle[p.kind], middle.all = ((middle[p.kind] or 0) + inside), (middle.all + inside)
    end)

    -- Chance is half. With one mistake always on one side, an even draw over the places left makes it two thirds, and a
    -- draw that ignores the answer makes it nine in ten.
    for kind, count in pairs(total) do
        local share = (middle[kind] / count)

        if share > (((kind == "all") and 0.7) or 0.78) then
            over[#over + 1] = ("%s %.2f"):format(kind, share)
        end
    end

    table.sort(over)
    eq(table.concat(over, ", "), "", "no kind's answer is a middle value much more often than two times in three")
end)

test("hints fit the riddle they're on", function()
    local _, _, ns = Kit.LoadKid()

    Sample(ns.Puzzles, 30, function(p, options)
        local where, hint, n = Where(p, options), p.hint:lower(), ((p.expression and Numbers(p.expression)) or {})

        if p.kind == "math.percent" then
            local percent = n[#n - 1]

            if percent == 50 then
                truthy(hint:find("half") and not hint:find("tenth"), "half for 50% at " .. where)
            elseif (percent == 25) or (percent == 75) then
                truthy(hint:find("quarter") and not hint:find("tenth"), "a quarter at " .. where)
            else
                truthy(hint:find("tenth"), "a tenth at " .. where)
            end

            falsy(p.title:find("Sale") or p.title:find("Bargain"), "no sale title at " .. where)
        elseif p.kind == "math.order" then
            eq(hint:find("parentheses") ~= nil, p.expression:find("(", 1, true) ~= nil, "parentheses only when there are some at " .. where)
        elseif (p.kind == "math.multiply") and (options.grade >= 4) then
            eq(hint:find("carr") ~= nil, (((n[1] % 10) * n[2]) >= 10), "the carry only when there is one at " .. where)
        elseif ((p.kind == "math.add") or (p.kind == "math.coins")) and (options.grade >= 2) and p.expression:find("+", 1, true) then
            eq(hint:find("carry") ~= nil, (((n[1] % 10) + (n[2] % 10)) >= 10), "the carry only when there is one at " .. where)
        elseif p.kind == "math.ratio" then
            falsy(hint:find("groups of 1 "), "no groups of 1 at " .. where)
        end
    end)
end)

test("a missing-number riddle offers the sum only as a near miss, and a remainder's numbers don't repeat among the choices", function()
    local _, _, ns = Kit.LoadKid()

    Sample(ns.Puzzles, 60, function(p, options)
        if p.kind == "math.missing" then
            local c = Numbers(p.expression)[1]

            for _, choice in ipairs(p.choices) do
                falsy((Value(p, choice) == c) and ((c - p.value) > 2), "the sum is only ever a near miss at " .. Where(p, options))
            end
        elseif p.kind == "math.remainder" then
            local quotients, remainders = 0, 0

            for _, choice in ipairs(p.choices) do
                local value = Value(p, choice)

                quotients = (quotients + (((value[1] == p.value) and 1) or 0))
                remainders = (remainders + (((value[2] == p.remainder) and 1) or 0))
            end

            truthy((quotients == 1) and (remainders == 1), "the answer isn't the most common value at " .. Where(p, options))
        elseif (p.kind == "math.decimal") and (options.level == 1) then
            for _, choice in ipairs(p.choices) do
                falsy(Same(Value(p, choice), p.value + 1), "no whole one more at " .. Where(p, options))
            end
        end
    end)
end)

test("small sums are spread evenly, and the first times tables include 0, 1 and 10", function()
    local _, _, ns = Kit.LoadKid()
    local sums, facts, factors, distinct = {}, {}, {}, 0

    for seed = 1, 360 do
        math.randomseed(seed)
        local p = ns.Puzzles.Generate({ grade = 0, kind = "math.add", level = 3, random = Roll, subject = "math" })

        sums[p.value] = ((sums[p.value] or 0) + 1)
        math.randomseed(seed)
        local fact = ns.Puzzles.Generate({ grade = 3, kind = "math.multiply", level = 1, random = Roll, subject = "math" })

        if not facts[fact.expression] then
            facts[fact.expression], distinct = true, (distinct + 1)
        end

        for _, factor in ipairs(Numbers(fact.expression)) do
            factors[factor] = true
        end
    end

    for sum = 2, 10 do
        truthy((sums[sum] or 0) <= 80, ("the sum %d comes up %d times in 360, no more than twice its share"):format(sum, sums[sum] or 0))
    end

    truthy(factors[0] and factors[1] and factors[10], "times 0, 1 and 10 are asked")
    truthy(distinct > 30, distinct .. " different facts")
end)

test("the player's levels to a milestone are an occasional subtraction riddle", function()
    local _, _, ns = Kit.LoadKid()
    local levels = 0

    for seed = 1, 300 do
        math.randomseed(seed)
        local p = ns.Puzzles.Generate({ context = Context, grade = 1, kind = "math.subtract", level = 2, random = Roll, subject = "math" })

        levels = (levels + ((p.prompt:find("You are level") and 1) or 0))
    end

    truthy((levels > 0) and (levels < 75), levels .. " of 300 subtraction riddles count levels")
end)
