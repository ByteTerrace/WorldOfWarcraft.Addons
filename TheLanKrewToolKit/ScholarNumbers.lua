local addonName, ns = ...

-- More math generators, registered in Kit.Generators like ScholarMath.lua's, whose builders (Kit.Numeric, Text, Why,
-- and With) they share: place value, telling time, the number line, the order of operations, and math from the player's
-- own quests. Like ScholarPuzzles.lua, they're pure. Their text and banks are ns.ScholarNumberWords
-- (ScholarNumberWords.lua). The order of operations reads ScholarMathWords' order text.
--
-- Every puzzle here is numeric, like ScholarMath.lua's: value is the answer as a number and expression its calculation.
-- A time of day is minutes, its hour (1 to 12) times 60 plus its minutes, so 2:45 is 165. Its choices read as a clock
-- does ("2:45"), and a length of time's as minutes ("35 minutes"). A number line's star riddle carries picture = { kind
-- = "line", to, jumps, mark, row }: a line from 0 to `to` in `jumps` equal jumps, with a star on the tick `mark` jumps
-- from 0. ScholarPictures draws it in place of `row`, the line as text in the prompt, through grade 3.
--
-- math.quest counts with state.known (every QuestBook record): an objective's count and name with its quest's giver or
-- title, two objectives' total, a vendor's copper for a quest's items (with the player's own copper when it's small),
-- and the quests the book holds and has turned in. ScholarWords.fromQuests lists it, so Scholar asks it only while the
-- quest book holds a quest. When no record fits, it tells the same riddles about a stock hero, giver, and item from
-- ScholarWords' quest banks.

-- The longest giver, objective, and title, in bytes, a quest riddle names.
local MaxGiver = 24
local MaxObjective = 28
local MaxTitle = 36
-- A quest objective's kind by its log type: an item to bring or a foe to defeat. Other objectives aren't counted.
local ObjectiveKinds = { item = "item", monster = "foe" }
-- The largest number a quest riddle's count or answer reaches, per grade (copper for a vendor's riddle).
local QuestCaps = { [0] = 10, 20, 100, 100, 9999, 1000, 1000 }

-- A fraction of the way along a line, per tier: { words, parts, parts taken, the lines' ends }. No end makes the answer
-- the number of parts, which a hint names.
local Fractions = {
    { { "half", 2, 1, { 10, 20 } }, { "a quarter", 4, 1, { 20, 40 } } },
    { { "half", 2, 1, { 50, 100 } }, { "a quarter", 4, 1, { 100 } }, { "three quarters", 4, 3, { 40, 100 } }, { "a fifth", 5, 1, { 50 } } },
    {
        { "a tenth", 10, 1, { 200, 1000 } }, { "three tenths", 10, 3, { 100, 1000 } }, { "three quarters", 4, 3, { 200, 1000 } },
        { "two fifths", 5, 2, { 100, 1000 } },
    },
}

-- The star riddle's lines per tier, as { end, jumps }: never one whose star could sit on the number of jumps.
local Lines = { { { 10, 5 }, { 20, 4 }, { 20, 5 } }, { { 100, 10 }, { 100, 5 }, { 50, 5 }, { 100, 4 } },
    { { 1000, 10 }, { 1000, 4 }, { 500, 5 }, { 200, 8 }, { 1000, 5 } } }

-- The halfway riddle's step size, per grade.
local HalfwayUnits = { [0] = 1, 5, 10, 10, 100 }

-- How many digits a place-value riddle's number has, per grade and level.
local PlaceDigits = { [0] = { 2, 2, 2 }, { 2, 2, 3 }, { 2, 3, 3 }, { 3, 3, 4 }, { 3, 4, 4 } }

-- Each place, ones first, as Count names it, and how the step walks to it from the right.
local Places = { { "one", "ones" }, { "ten", "tens" }, { "hundred", "hundreds" }, { "thousand", "thousands" } }
local Units = { 1, 10, 100, 1000 }
local Walks = { "ones", "ones, then tens", "ones, tens, then hundreds", "ones, tens, hundreds, then thousands" }

local abs = math.abs
local concat = table.concat
local find = string.find
local floor = math.floor
local insert = table.insert
local ipairs = ipairs
local max = math.max
local min = math.min
local sort = table.sort
local tostring = tostring
local type = type
local unpack = unpack

local Kit = ns.Puzzles.Kit
local Chance = Kit.Chance
local Count = Kit.Count
local Fill = Kit.Fill
local Finish = Kit.Finish
local Fits = Kit.Fits
local Generators = Kit.Generators
local NumberWords = ns.ScholarNumberWords
local Numeric = Kit.Numeric
local Pick = Kit.Pick
local Shuffle = Kit.Shuffle
local Text = Kit.Text
local Vars = Kit.Vars
local Why = Kit.Why
local With = Kit.With

-- A time of day as a clock shows it: 165 minutes is "2:45".
local function Clock(minutes)
    local m = (minutes % 60)

    return (floor(minutes / 60) .. ":" .. (((m < 10) and "0") or "") .. m)
end

-- The hour before hour on a clock face.
local function LastHour(hour)
    return (((hour + 10) % 12) + 1)
end

-- A length of time as its choice reads: "35 minutes".
local function Minutes(n)
    return (n .. " minutes")
end

-- The hour after hour on a clock face.
local function NextHour(hour)
    return ((hour % 12) + 1)
end

-- One step of a calculation, as the working shows it: "4 x 3 = 12".
local function Op(x, op, y, z)
    return (x .. " " .. op .. " " .. y .. " = " .. z)
end

-- A record's text as a riddle may name it: a plain string of at most most bytes, else nil.
local function Plain(text, most)
    return ((((type(text) == "string") and (text ~= "") and (#text <= most) and not find(text, "[%c|{}\\]")) and text) or nil)
end

-- The tier of a riddle's numbers, 1 to 3, by grade and level together.
local function Tier(state)
    return min(3, floor(((state.grade + state.level) + 1) / 2))
end

-- Order of operations, per level: forms returning the text, its value, the working step by step, the first operation,
-- whether it has parentheses, and the slips it invites ({ value, why }: working left to right, or skipping the
-- parentheses). Every form and slip stays positive.
local OrderForms = {
    {
        function(a, b, c)
            local first = (a + 4)

            return {
                first = (b .. " x " .. c), parens = false, slips = { { ((first + b) * c), "leftToRight" } },
                text = (first .. " + " .. b .. " x " .. c), v = (first + (b * c)),
                work = { Op(b, "x", c, b * c), Op(first, "+", b * c, first + (b * c)) },
            }
        end,
        function(a, b, c)
            local first = ((b * c) + a)

            return {
                first = (b .. " x " .. c), parens = false, slips = { { ((first - b) * c), "leftToRight" } },
                text = (first .. " - " .. b .. " x " .. c), v = a, work = { Op(b, "x", c, b * c), Op(first, "-", b * c, a) },
            }
        end,
    },
    {
        function(a, b, c)
            return {
                first = (a .. " + " .. b), parens = true, slips = { { (a + (b * c)), "parens" } },
                text = ("(" .. a .. " + " .. b .. ") x " .. c), v = ((a + b) * c),
                work = { Op(a, "+", b, a + b), Op(a + b, "x", c, (a + b) * c) },
            }
        end,
        function(a, b, c, d)
            local first = (a + 5)
            local sum = (first + (b * c))

            return {
                first = (b .. " x " .. c), parens = false, slips = { { (((first + b) * c) - d), "leftToRight" } },
                text = (first .. " + " .. b .. " x " .. c .. " - " .. d), v = (sum - d),
                work = { Op(b, "x", c, b * c), Op(first, "+", b * c, sum), Op(sum, "-", d, sum - d) },
            }
        end,
        function(a, b, _, d)
            return {
                first = ((b + d) .. " - " .. d), parens = true, slips = { { ((a * (b + d)) - d), "parens" } },
                text = (a .. " x (" .. (b + d) .. " - " .. d .. ")"), v = (a * b), work = { Op(b + d, "-", d, b), Op(a, "x", b, a * b) },
            }
        end,
    },
    {
        function(a, b, c, d)
            return {
                first = ((c + d) .. " - " .. d), parens = true,
                slips = { { ((a + b) * c), "leftToRight" }, { ((a + (b * (c + d))) - d), "parens" } },
                text = (a .. " + " .. b .. " x (" .. (c + d) .. " - " .. d .. ")"), v = (a + (b * c)),
                work = { Op(c + d, "-", d, c), Op(b, "x", c, b * c), Op(a, "+", b * c, a + (b * c)) },
            }
        end,
        function(a, b, c, d)
            return {
                first = (a .. " + " .. b), parens = true,
                slips = { { ((a + (b * (c + d))) - c), "parens" }, { (((a + b) * (c + d)) - c), "parens" } },
                text = ("(" .. a .. " + " .. b .. ") x (" .. (c + d) .. " - " .. c .. ")"), v = ((a + b) * d),
                work = { Op(a, "+", b, a + b), Op(c + d, "-", c, d), Op(a + b, "x", d, (a + b) * d) },
            }
        end,
        function(_, b, c, d)
            local left = ((c + d) * (b + 1))
            local right = (c * b)

            return {
                first = ((c + d) .. " x " .. (b + 1)), parens = false, slips = { { ((left - c) * b), "leftToRight" } },
                text = ((c + d) .. " x " .. (b + 1) .. " - " .. c .. " x " .. b), v = (left - right),
                work = { Op(c + d, "x", b + 1, left), Op(c, "x", b, right), Op(left, "-", right, left - right) },
            }
        end,
    },
}

-- The number closest to t: one sits gap away, and every other farther. The trap shares t's leading digit but sits
-- farther off. The rest fall below or above t, so the answer's rank among the four gives nothing away.
local function Closest(state)
    local scale = (((state.grade >= 3) and 10) or 1)
    local t = ((10 * scale) * state.roll(2, 8))
    local gap = (scale * state.roll(1, 4))
    local sign = ((Chance(state, 2) and "+") or "-")
    local v = (((sign == "+") and (t + gap)) or (t - gap))
    local trap = (t + (scale * state.roll((gap / scale) + 1, 9)))
    local chosen = { trap }
    local used = { [trap] = true, [v] = true }
    local below = state.roll(0, 2)

    for i = 1, 2 do
        local side = (((i <= below) and -1) or 1)

        for _ = 1, 30 do
            local x = (t + (side * (gap + (scale * state.roll(1, 15)))))

            if not used[x] then
                used[x], chosen[#chosen + 1] = true, x

                break
            end
        end
    end

    local all = { v, unpack(chosen) }

    sort(all)
    local listed = {}

    for i, n in ipairs(all) do
        listed[i] = (n .. " is " .. abs(n - t) .. " away")
    end

    local text = Text(NumberWords.closest)

    local vars = Vars(state, {
        dx = abs(trap - t), gap = gap, listed = (concat(listed, ", ", 1, 3) .. " and " .. listed[4]), sign = sign, t = t, v = v,
        x = trap,
    })

    local wrongs = {}

    for i, n in ipairs(chosen) do
        local why = (((i == 1) and text.whys.digits) or text.whys.far)

        wrongs[i] = { tostring(n), why = Why(why, vars, { choice = tostring(n), dist = abs(n - t) }) }
    end

    return Finish(state, "math.numberLine", text, vars, tostring(v), wrongs)
end

-- A place-value number of count distinct digits, none of them 0: its digits, ones first, and its value.
local function DistinctNumber(state, count)
    local pool = Shuffle(state, { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
    local digits = {}
    local n = 0

    for i = 1, count do
        digits[i] = pool[i]
        n = (n + (pool[i] * Units[i]))
    end

    return digits, n
end

-- What a number of digits, ones first, adds up to: "347 = 300 + 40 + 7".
local function Expanded(digits, n)
    local parts = {}

    for i = #digits, 1, -1 do
        if digits[i] > 0 then
            parts[#parts + 1] = (digits[i] * Units[i])
        end
    end

    return (n .. " = " .. concat(parts, " + "))
end

-- A spot a fraction of the way from 0 to a line's end.
local function FractionOfLine(state)
    local way = Pick(state, Fractions[Tier(state)])
    local e = Pick(state, way[4])
    local j = way[2]
    local k = way[3]
    local s = (e / j)
    local v = (k * s)
    local vars = { e = e, frac = way[1], j = j, k = k, s = s, v = v }
    local named = { { j, why = "parts" }, { (e - v), why = "otherEnd" } }

    if k > 1 then
        With(named, { k, why = "top" }, { s, why = "onePart" })
    end

    return Numeric(state, "math.numberLine", NumberWords.fraction, vars, With(named, (v + s), (v - s), (v + (2 * s))),
        { cases = (((k == 1) and { "unit" }) or nil) })
end

-- The middle of two numbers: never one whose gap is the answer, which the step names.
local function Halfway(state)
    local unit = HalfwayUnits[min(state.grade, 4)]
    local lo = (unit * state.roll(1, 6))
    local half = (unit * state.roll(1, 5))

    if half == lo then
        half = (half + unit)
    end

    local hi = (lo + (2 * half))
    local v = (lo + half)
    local vars = { gap = (2 * half), half = half, hi = hi, lo = lo, v = v }
    local named = { { half, why = "half" }, { (2 * half), why = "gap" }, { (lo + hi), why = "sum" } }

    return Numeric(state, "math.numberLine", NumberWords.halfway, vars, With(named, (v + unit), (v - unit), (v + (2 * unit)), (v - (2 * unit))),
        {})
end

-- A star on a line of equal jumps, its prompt holding the line as text. It's drawn as a picture in the early grades,
-- like the other pictures (ScholarPuzzles.lua).
local function Mark(state)
    local line = Pick(state, Lines[Tier(state)])
    local e = line[1]
    local j = line[2]
    local s = (e / j)
    local k = state.roll(2, j - 1)

    if (k * s) == j then
        k = (((k < (j - 1)) and (k + 1)) or (k - 1))
    end

    local v = (k * s)
    local ticks = {}

    for i = 0, j do
        ticks[i + 1] = (((i == k) and "*") or "+")
    end

    local row = ("0 " .. concat(ticks, "--") .. " " .. e)
    local named = { { k, why = "ticks" }, { ((k + 1) * s), why = "zeroTick" }, { (e - v), why = "otherEnd" } }

    if s ~= 10 then
        named[#named + 1] = { (k * 10), why = "tens" }
    end

    local puzzle = Numeric(state, "math.numberLine", NumberWords.mark, { e = e, j = j, k = k, row = row, s = s, v = v },
        With(named, (v + s), (v - s)), {})

    if state.grade <= 3 then
        puzzle.picture = { jumps = j, kind = "line", mark = k, row = row, to = e }
    end

    return puzzle
end

-- Every objective of the player's quests a count riddle can name: { name, kind, required, giver, title } with a count
-- from 2 to most and a giver or title to say whose it is.
local function Objectives(state, most)
    local out = {}

    for _, record in ipairs(((type(state.known) == "table") and state.known) or {}) do
        local giver = ((type(record) == "table") and Plain(record.giver, MaxGiver))
        local title = ((type(record) == "table") and Plain(record.title, MaxTitle))

        for i = 1, (((giver or title) and 3) or 0) do
            local name = Plain(record["objective" .. i], MaxObjective)
            local required = record["required" .. i]
            local kind = ObjectiveKinds[record["type" .. i]]

            if name and kind and (type(required) == "number") and (required == floor(required)) and (required >= 2) and (required <= most) then
                out[#out + 1] = { giver = giver, kind = kind, name = name, required = required, title = title }
            end
        end
    end

    return out
end

-- Two objectives of the same kind with different names, from objectives, or nil.
local function Pair(state, objectives)
    for _, first in ipairs(Shuffle(state, objectives)) do
        for _, second in ipairs(objectives) do
            if (second.kind == first.kind) and (second.name:lower() ~= first.name:lower()) then
                return first, second
            end
        end
    end
end

-- The faction's quest bank (ScholarWords.questBanks), for the stock riddles.
local function QuestBank(state)
    return (Kit.Words.questBanks[state.context.faction] or Kit.Words.questBanks.Alliance)
end

-- How many quests the player's book holds and how many of them are turned in.
local function QuestCounts(state)
    local held = 0
    local turned = 0

    for _, record in ipairs(((type(state.known) == "table") and state.known) or {}) do
        if type(record) == "table" then
            held = (held + 1)
            turned = (turned + (((record.turnedIn == true) and 1) or 0))
        end
    end

    return held, turned
end

-- How many more an objective needs. The amount done is never the answer or one short of it, which the hint and step
-- name. A stock riddle tells it about a stock hero.
local function QuestMore(state, objectives, cap)
    local stock = (#objectives == 0)
    local objective = (((not stock) and Pick(state, objectives)) or nil)

    if stock then
        local bank = QuestBank(state)

        objective = { giver = Pick(state, bank.names), kind = "item", name = Pick(state, bank.items), required = state.roll(4, min(12, cap)) }
    end

    local r = objective.required
    local done = {}

    for h = 1, r - 1 do
        if (h ~= (r - h)) and ((h + 1) ~= (r - h)) then
            done[#done + 1] = h
        end
    end

    if #done == 0 then
        return nil
    end

    local h = Pick(state, done)
    local asks = NumberWords.questAsks[objective.kind]
    local who = { giver = objective.giver, objective = objective.name, r = r, title = objective.title }
    local ask = Fill((objective.giver and asks.giver) or asks.title, who)
    local so = ((((objective.kind == "foe") and "Say you've defeated ") or "Say you have ") .. h .. " so far")
    local vars = { ask = ask, giver = objective.giver, h = h, h1 = (h + 1), objective = objective.name, r = r, so = so, v = (r - h) }

    return Numeric(state, "math.quest", NumberWords.questMore, vars,
        { { (r + h), why = "added" }, { r, why = "goal" }, { h, why = "have" }, ((r - h) + 1), ((r - h) - 1), ((r - h) + 2) },
        { cases = ((stock and { "stock" }) or nil) })
end

-- A vendor's copper for an objective's items, sometimes added to the player's own copper when the sum stays in reach.
local function QuestSell(state, objectives, cap)
    local items = {}
    local stock = (#objectives == 0)

    for _, objective in ipairs(objectives) do
        if (objective.kind == "item") and (objective.required >= 3) then
            items[#items + 1] = objective
        end
    end

    local objective = (((#items > 0) and Pick(state, items)) or nil)

    if stock then
        local bank = QuestBank(state)

        objective = { giver = Pick(state, bank.names), name = Pick(state, bank.items), required = state.roll(3, 10) }
    end

    if not objective or ((2 * objective.required) > cap) then
        return nil
    end

    local r = objective.required
    local p = state.roll(2, max(2, min(25, floor(cap / r))))
    local mine = state.context.copper
    local purse = (not stock and mine and (mine >= 1) and ((mine + (r * p)) <= cap) and Chance(state, 2))
    local v = (((purse and mine) or 0) + (r * p))
    local vars = { giver = objective.giver, mine = mine, np = (r * p), objective = objective.name, p = p, p2 = (2 * p), r = r, v = v }
    local named

    if purse then
        named = { { (r * p), why = "sales" }, { ((mine + r) + p), why = "allAdded" }, (v + p), (v - p) }
    else
        named = { { (r + p), why = "added" }, { ((r - 1) * p), why = "fewer" }, { ((r + 1) * p), why = "more" }, (v + 10), (v - 10) }
    end

    return Numeric(state, "math.quest", NumberWords.questSell, vars, named, {
        cases = (((purse and { "purse" }) or (stock and { "stock" })) or nil), format = function(n) return (n .. " copper") end, lo = 1,
    })
end

-- The quests still to turn in, from the quest book's own counts.
local function QuestsLeft(state, _, cap)
    local held, turned = QuestCounts(state)

    if (turned < 1) or (turned >= held) or (held > cap) then
        return nil
    end

    local v = (held - turned)

    return Numeric(state, "math.quest", NumberWords.questBook, { n = held, t = turned, v = v },
        { { (held + turned), why = "added" }, { held, why = "all" }, { turned, why = "turned" }, (v + 1), (v - 1), (v + 2) }, {})
end

-- Two objectives' total, from the quest book or the bank.
local function QuestTotal(state, objectives, cap)
    local first, second = Pair(state, objectives)
    local stock = (#objectives == 0)

    if stock then
        local bank = QuestBank(state)
        local items = Shuffle(state, bank.items)
        local names = Shuffle(state, bank.names)

        first = { giver = names[1], kind = "item", name = items[1], required = state.roll(2, min(12, cap - 2)) }
        second = { giver = names[2], kind = "item", name = items[2], required = state.roll(2, min(12, cap - first.required)) }
    end

    if not first or ((first.required + second.required) > cap) then
        return nil
    end

    local r1 = first.required
    local r2 = second.required
    local v = (r1 + r2)
    local big = max(r1, r2)
    local small = min(r1, r2)
    local oa = (r1 % 10)
    local ob = (r2 % 10)

    local vars = {
        big = big, big1 = (big + 1), g1 = first.giver, g2 = second.giver,
        list = Fill(NumberWords.questLists[first.kind], { obj1 = first.name, obj2 = second.name, r1 = r1, r2 = r2 }),
        noun = (((first.kind == "foe") and "enemies") or "things"), oa = oa, ob = ob, obj1 = first.name, obj2 = second.name,
        od = ((oa + ob) % 10), ones = (oa + ob), r1 = r1, r2 = r2, small = small, v = v,
    }

    local named = { { big, why = "one" }, { (big - small), why = "takeAway" } }
    local cases = {}

    if big < 10 then
        cases[1] = "small"
    elseif (oa + ob) >= 10 then
        cases[1] = "carry"
        insert(named, 1, { (v - 10), why = "carry" })
    end

    if stock then
        cases[#cases + 1] = "stock"
    end

    return Numeric(state, "math.quest", NumberWords.questTotal, vars, With(named, (v + 1), (v - 1), (v + 2), (v + 10)), { cases = cases })
end

-- A number of hundreds, tens, or ones as the place-value texts say it: "3 hundreds", "1 ten".
local function Said(n, at)
    return Count(n, Places[at])
end

-- A number built from its hundreds, tens, and ones, said in a shuffled order or in place order: "7 ones and 4 tens". A
-- zero tens place is left out of what's said: the classic trap.
local function Build(state)
    local count = min(PlaceDigits[min(state.grade, 4)][state.level], 3)
    local digits = DistinctNumber(state, count)
    local zero = ((count == 3) and (state.level == 3) and Chance(state, 3))

    if zero then
        digits[2] = 0
    end

    local parts = {}

    for i = count, 1, -1 do
        if digits[i] > 0 then
            parts[#parts + 1] = { digits[i], i }
        end
    end

    local inOrder = Chance(state, 2)

    if not inOrder then
        parts = Shuffle(state, parts)
        inOrder = true

        for i, part in ipairs(parts) do
            inOrder = (inOrder and (part[2] == ((count + 1) - i)))
        end
    end

    local words = {}
    local saidDigits = 0
    local reversed = 0

    for i, part in ipairs(parts) do
        words[i] = Said(part[1], part[2])
        saidDigits = ((saidDigits * 10) + part[1])
    end

    for i = 1, count do
        reversed = ((reversed * 10) + digits[i])
    end

    local said = (((#words == 3) and (words[1] .. ", " .. words[2] .. " and " .. words[3])) or (words[1] .. " and " .. words[2]))
    local o = digits[1]
    local td = digits[2]
    local hd = (digits[3] or 0)
    local v = (((100 * hd) + (10 * td)) + o)

    local vars = {
        hd = hd, hundredsWord = Said(hd, 3), hv = (100 * hd), o = o, onesWord = Said(o, 1), said = said, td = td,
        tensWord = Said(td, 2), tv = (10 * td), v = v,
    }

    local named = { { (((hd + td) + o)), why = "added" } }

    if zero then
        insert(named, 1, { ((10 * hd) + o), why = "zero" })
    elseif inOrder then
        insert(named, 1, { reversed, why = "swapped" })
    else
        insert(named, 1, { saidDigits, why = "said" })
    end

    if count == 2 then
        named[#named + 1] = { ((100 * td) + o), why = "written" }
    end

    local cases = (((count == 3) and { "hundreds" }) or nil)

    if zero then
        cases[2] = "zero"
    end

    return Numeric(state, "math.placeValue", NumberWords.build, vars, With(named, (v + 10), (v - 10), (v + 1), (v - 1)), { cases = cases })
end

-- What a digit is worth where it sits. It's never the ones place, where the digit is its own worth.
local function DigitWorth(state)
    local count = PlaceDigits[min(state.grade, 4)][state.level]
    local digits, n = DistinctNumber(state, count)
    local at = state.roll(2, count)
    local d = digits[at]
    local unit = Units[at]
    local otherAt = Pick(state, { (((at > 1) and (at - 1)) or (at + 1)), (((at < count) and (at + 1)) or (at - 1)) })
    local v = (d * unit)

    local vars = {
        d = d, expanded = Expanded(digits, n), n = n, other = digits[otherAt], placeName = Places[at][2], unit = unit, v = v,
        walk = Walks[at], worth = Said(d, at),
    }

    local named = {
        { d, why = "face" }, { ((d * unit) * 10), why = "place" }, { (d * (unit / 10)), why = "place" },
        { (digits[otherAt] * Units[otherAt]), why = "other" },
    }

    return Numeric(state, "math.placeValue", NumberWords.digitWorth, vars, With(named, (v + unit), (v - unit), ((d + 1) * unit)), {})
end

-- Ten (or a hundred) more or less: only one digit changes, unless it carries or trades into the next place.
local function TenMore(state)
    local count = PlaceDigits[min(state.grade, 4)][state.level]
    local s = ((((count >= 3) and (state.level >= 2) and Chance(state, 2)) and 100) or 10)
    local less = Chance(state, 2)
    local cross = ((state.level == 3) and Chance(state, 3))

    -- Ten less with no tens to take trades from the next place, so the number needs one.
    cross = (cross and (not less or (Units[count] >= (10 * s))))
    local lo = Units[count]
    local hi = ((Units[count] * 10) - 1)
    local n
    local pd

    for _ = 1, 40 do
        n = state.roll(lo, hi)
        pd = (floor(n / s) % 10)

        local fits = ((less and cross and (pd == 0) and (n >= (10 * s))) or (less and not cross and (pd >= 1) and ((n - s) >= 10))
            or (not less and cross and (pd == 9)) or (not less and not cross and (pd <= 8)))

        if fits then
            break
        end

        n = nil
    end

    if not n then
        cross, n = false, ((lo + (2 * s)) + 1)
        pd = (floor(n / s) % 10)
    end

    local sign = ((less and -1) or 1)
    local v = (n + (sign * s))

    local vars = {
        big = (10 * s), bigWord = (((s == 10) and "hundreds") or "thousands"), n = n, nextWord = (((s == 10) and "hundreds") or "thousands"),
        pd = pd, placeWord = (((s == 10) and "tens") or "hundreds"), s = s, v = v,
    }

    local named = { { (n + sign), why = "one" }, { (n - (sign * s)), why = "opposite" }, { (n + ((sign * 10) * s)), why = "big" } }
    local cases = {}

    if less then
        cases[1] = "less"
    end

    if cross then
        cases[#cases + 1] = ((less and "lessCross") or "moreCross")
    end

    return Numeric(state, "math.placeValue", NumberWords.tenMore, vars, With(named, (v + 1), (v - 1), (v + 2), (v - 2)), { cases = cases })
end

-- How many tens in all: a two-digit number's tens digit (a teen's at kindergarten's first levels), or a three-digit
-- number's hundreds as tens too.
local function TensIn(state)
    local count = min(PlaceDigits[min(state.grade, 4)][state.level], 3)
    local n
    local o
    local td
    local hd

    if (state.grade == 0) and (state.level < 3) then
        hd, td, o = 0, 1, state.roll(2, 9)
    else
        local digits = DistinctNumber(state, count)

        o, td, hd = digits[1], digits[2], (digits[3] or 0)
    end

    n = (((100 * hd) + (10 * td)) + o)
    local v = ((10 * hd) + td)

    local vars = {
        ht = (10 * hd), hundredsWord = Said(hd, 3), n = n, o = o, onesWord = Said(o, 1), td = td, tensWord = Said(v, 2),
        tv = (n - o), v = v,
    }

    local named = { { o, why = "ones" }, { (n - o), why = "value" }, { n, why = "whole" } }

    if hd > 0 then
        insert(named, 1, { td, why = "digit" })
    end

    return Numeric(state, "math.placeValue", NumberWords.tensIn, vars, With(named, (v + 1), (v - 1), (v + 2), (v + 10)),
        { cases = (((hd > 0) and { "hundreds" }) or nil) })
end

-- When a trip ends, from its start and how long it lasts. At the last tier, it can cross into the next hour, but never
-- ends right on it.
local function TimeElapsed(state)
    local tier = Tier(state)
    local h = state.roll(1, 10)
    local dur = (5 * state.roll(2, ((tier <= 2) and 6) or 11))
    local m1 = (5 * state.roll(0, ((tier <= 2) and ((55 - dur) / 5)) or 11))

    -- A trip ending right on the hour would end where the step's count up stops.
    if (m1 + dur) == 60 then
        dur = (dur - 5)
    end

    local start = ((h * 60) + m1)
    local v = (((h * 60) + m1) + dur)
    local cross = ((m1 + dur) >= 60)

    local vars = {
        clock = Clock(v), dungeon = Pick(state, NumberWords.dungeons), dur = dur, h = h, m1 = m1, m2 = (m1 + dur), rest = ((m1 + dur) - 60),
        ride = Pick(state, NumberWords.rides), start = Clock(start), top = Clock((h + 1) * 60), up = (60 - m1), v = v,
    }

    local named = { { (start - dur), why = "back" }, { (v + 60), why = "extraHour" } }

    if cross then
        insert(named, 1, { (v - 60), why = "hour" })
    end

    return Numeric(state, "math.time", NumberWords.timeElapsed, vars, With(named, (v + 5), (v - 5), (v + 10), (v - 10), (v + 15)),
        { cases = ((cross and { "cross" }) or nil), format = Clock, hi = 779, lo = 60 })
end

-- A time read from the clock's hands. The long hand's number is minutes by fives. The short hand sits between its hour
-- and the next, except at o'clock.
local function TimeHands(state)
    local tier = Tier(state)
    local n = Pick(state, ((tier == 1) and { 12, 6 }) or ((tier == 2) and { 12, 3, 6, 9 }) or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 })
    local h = state.roll(1, 12)
    local mm = ((n % 12) * 5)
    local v = ((h * 60) + mm)
    local named = { { ((h * 60) + n), why = "face" }, { ((n * 60) + ((h % 12) * 5)), why = "swapped" } }

    if n ~= 12 then
        named[#named + 1] = { ((NextHour(h) * 60) + mm), why = "nextHour" }
    end

    local vars = { clock = Clock(v), h = h, h1 = NextHour(h), mm = mm, n = n, ride = Pick(state, NumberWords.rides), v = v }

    return Numeric(state, "math.time", NumberWords.timeHands, vars, With(named, (v + 5), (v - 5), (v + 30), (v - 30), (v + 60)),
        { cases = (((n == 12) and { "oclock" }) or nil), format = Clock, hi = 779, lo = 60 })
end

-- How long a trip lasts, from its start and end, never right on the hour. Across an hour, the classic slip takes the
-- times away as if an hour had 100 minutes.
local function TimeHowLong(state)
    local h = state.roll(1, 10)
    local m1 = (5 * state.roll(1, 11))
    local dur = (5 * state.roll(2, 11))

    if (m1 + dur) == 60 then
        dur = (dur - 5)
    end

    local stop = (((h * 60) + m1) + dur)
    local h2 = floor(stop / 60)
    local m2 = (stop % 60)
    local cross = (h2 > h)

    local vars = {
        dungeon = Pick(state, NumberWords.dungeons), h = h, h2 = h2, m1 = m1, m2 = m2, rest = m2, ride = Pick(state, NumberWords.rides),
        start = Clock((h * 60) + m1), stop = Clock(stop), top = Clock(h2 * 60), up = (60 - m1), v = dur,
    }

    local named

    if cross then
        named = { { (((h2 * 100) + m2) - ((h * 100) + m1)), why = "hundred" }, { abs(m2 - m1), why = "minutesOnly" } }
    else
        named = { { (m1 + m2), why = "added" }, { m2, why = "stopOnly" } }
    end

    return Numeric(state, "math.time", NumberWords.timeHowLong, vars, With(named, (dur + 5), (dur - 5), (dur + 10), (dur - 10)),
        { cases = ((cross and { "cross" }) or nil), format = Minutes, lo = 5 })
end

-- A time said in words: half past at first, then quarters, then any five minutes past or to the hour.
local function TimeWords(state)
    local tier = Tier(state)

    local form = Pick(state, ((tier == 1) and { "half" }) or ((tier == 2) and { "half", "quarterPast", "quarterTo" })
        or { "half", "quarterPast", "quarterTo", "past", "to" })

    local h = state.roll(1, 12)
    local h0 = LastHour(h)
    local h1 = NextHour(h)
    local m = (({ half = 30, quarterPast = 15, quarterTo = 45 })[form] or (5 * Pick(state, { 1, 2, 4, 5 })))

    if form == "to" then
        m = (60 - m)
    end

    local v = ((h * 60) + m)
    local k = (60 - m)
    local named

    if form == "half" then
        named = { { ((h * 60) + 50), why = "decimal" }, { ((h1 * 60) + 30), why = "nextHour" }, { ((h0 * 60) + 30), why = "prevHour" } }
    elseif form == "quarterPast" then
        named = { { ((h * 60) + 25), why = "decimal" }, { ((h0 * 60) + 45), why = "toNotPast" }, { ((h * 60) + 45), why = "threeQuarters" } }
    elseif form == "quarterTo" then
        named = { { ((h1 * 60) + 15), why = "pastNotTo" }, { ((h1 * 60) + 45), why = "keptHour" }, ((h * 60) + 15) }
    elseif form == "past" then
        named = { { ((h0 * 60) + (60 - m)), why = "toNotPast" }, ((h * 60) + (60 - m)) }
    else
        named = { { ((h1 * 60) + k), why = "pastNotTo" }, { ((h1 * 60) + m), why = "keptHour" }, { ((h * 60) + k), why = "saidMinutes" } }
    end

    local said = (({ half = ("half past " .. h), past = (m .. " minutes past " .. h), quarterPast = ("quarter past " .. h),
        quarterTo = ("quarter to " .. h1), to = (k .. " minutes to " .. h1) })[form])

    local vars = {
        clock = Clock(v), dungeon = Pick(state, NumberWords.dungeons), h = h, h0 = h0, h1 = h1, k = k, m = m,
        ride = Pick(state, NumberWords.rides), said = said, v = v,
    }

    return Numeric(state, "math.time", NumberWords.timeWords, vars, With(named, (v + 5), (v - 5), (v + 10), (v - 10), (v + 60), (v - 60)),
        { cases = { form }, format = Clock, hi = 779, lo = 60 })
end

Generators["math.numberLine"] = function(state)
    return Pick(state, { Closest, FractionOfLine, Halfway, Mark })(state)
end

Generators["math.order"] = function(state)
    local form = Pick(state, OrderForms[state.level])
    local a = state.roll(2, 6)
    local b = state.roll(2, 6)
    local c = state.roll(2, 6)
    local d = state.roll(2, 6)
    local riddle = form(a, b, c, d)
    local v = riddle.v
    local named = {}

    for i, slip in ipairs(riddle.slips) do
        named[i] = { slip[1], why = slip[2] }
    end

    return Numeric(state, "math.order", "order", { first = riddle.first, text = riddle.text, v = v, work = concat(riddle.work, ", then ") },
        With(named, (v + 3), (v + 1), (v - 1), (v + 2)), { cases = ((riddle.parens and { "parens" }) or nil), lo = 1 })
end

Generators["math.placeValue"] = function(state)
    return Pick(state, { Build, DigitWorth, TenMore, TensIn })(state)
end

-- A riddle from the quest book when one fits (each kind of riddle in a shuffled order), else a stock one.
Generators["math.quest"] = function(state)
    local cap = QuestCaps[state.grade]
    local objectives = Objectives(state, cap)
    local makers = { QuestMore, QuestTotal, QuestsLeft }

    if state.grade >= 3 then
        makers[#makers + 1] = QuestSell
    end

    for _, make in ipairs(Shuffle(state, makers)) do
        local puzzle = make(state, objectives, cap)

        if puzzle and Fits(puzzle) then
            return puzzle
        end
    end

    return QuestMore(state, {}, cap)
end

Generators["math.time"] = function(state)
    local tier = Tier(state)
    local makers = { TimeWords, TimeHands }

    if tier >= 2 then
        makers[3] = TimeElapsed
    end

    if tier >= 3 then
        makers[4] = TimeHowLong
    end

    return Pick(state, makers)(state)
end
