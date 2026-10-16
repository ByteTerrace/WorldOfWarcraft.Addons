-- Scholar's place-value, clock, and number-line riddles (ScholarNumbers.lua and ScholarNumberWords.lua): every answer
-- is what the prompt alone works out to, by an independent reading of the prompt. Each kind offers the mistakes it
-- exists to catch, with a why, and a number line's star riddle is drawn as a line. scholar.test.lua's sweeps check
-- their shape, and scholarmath.test.lua their steps, praise, and working.

local Kit = use("scholar")
local Numbers = Kit.Numbers

-- How far along a line each fraction of the way goes.
local Fractions = {
    ["a fifth"] = (1 / 5), ["a quarter"] = (1 / 4), ["a tenth"] = (1 / 10), half = (1 / 2), ["three quarters"] = (3 / 4),
    ["three tenths"] = (3 / 10), ["two fifths"] = (2 / 5),
}

local Kinds = { "math.placeValue", "math.time", "math.numberLine" }
local Places = { hundred = 100, hundreds = 100, one = 1, ones = 1, ten = 10, tens = 10 }

-- A clock time's text: 165 minutes is "2:45".
local function Clock(minutes)
    return ("%d:%02d"):format(math.floor(minutes / 60), minutes % 60)
end

-- The hour before hour on a clock face.
local function HourBefore(hour)
    return (((hour + 10) % 12) + 1)
end

local Minutes = Kit.ClockMinutes

-- The answer a number-line prompt works out to, or nil for a closest riddle (its answer depends on its choices).
local function NumberLine(prompt)
    local lo, hi = prompt:match("between (%d+) and (%d+)")

    if not lo then
        lo, hi = prompt:match("from mile (%d+) to mile (%d+)")
    end

    if not lo then
        lo, hi = prompt:match("stretches from (%d+) to (%d+)")
    end

    if lo then
        return ((tonumber(lo) + tonumber(hi)) / 2)
    end

    local row = prompt:match("\n(0 [%+%*%-]+ %d+)\n")

    if row then
        local ticks = (row:match("^0 ([%+%*%-]+) "):gsub("%-", ""))
        local e = tonumber(row:match("(%d+)$"))
        local star = ticks:find("*", 1, true)

        return ((e / (#ticks - 1)) * (star - 1))
    end

    local frac, e = prompt:match("sits (.-) of the way from 0 to (%d+)")

    if not frac then
        frac, e = prompt:match("rides (.-) of the way along a road of (%d+) miles")
    end

    if frac then
        return (tonumber(e) * Fractions[frac])
    end

    return nil
end

-- The answer a place-value prompt works out to.
local function PlaceValue(prompt)
    local d, n = prompt:match("the (%d) worth in (%d+)")

    if not d then
        n, d = prompt:match("reads (%d+)%. What is the (%d) in it worth")
    end

    if not d then
        n, d = prompt:match("In the number (%d+), what is the (%d) worth")
    end

    if d then
        local text = tostring(n)

        return (tonumber(d) * (10 ^ (#text - text:find(d, 1, true))))
    end

    local whole = (prompt:match("How many tens are in (%d+)") or prompt:match("bundles (%d+) ") or prompt:match("stacks (%d+) copper"))

    if whole then
        return math.floor(tonumber(whole) / 10)
    end

    local s, from = prompt:match("(%d+) more than (%d+)")

    if s then
        return (tonumber(from) + tonumber(s))
    end

    s, from = prompt:match("(%d+) less than (%d+)")

    if s then
        return (tonumber(from) - tonumber(s))
    end

    from, s = prompt:match("has (%d+) [%a ]-and finds (%d+) more")

    if from then
        return (tonumber(from) + tonumber(s))
    end

    from, s = prompt:match("has (%d+) [%a ]-and gives (%d+) of them")

    if from then
        return (tonumber(from) - tonumber(s))
    end

    local v = 0

    for digit, place in prompt:gmatch("(%d+) (%a+)") do
        v = (v + (tonumber(digit) * (Places[place] or 0)))
    end

    return v
end

local Roll = Kit.Roll

-- Calls fn(puzzle, options) for seeds riddles of kind at every grade that asks it and every level.
local function Sample(puzzles, kind, seeds, fn)
    for grade = 0, 6 do
        local listed = false

        for _, each in ipairs(puzzles.Kinds("math", grade)) do
            listed = (listed or (each == kind))
        end

        for level = 1, (((listed and 3) or 0)) do
            for seed = 1, seeds do
                math.randomseed(((grade * 1000) + (level * 100)) + seed)
                local options = { grade = grade, kind = kind, level = level, random = Roll, subject = "math" }

                fn(puzzles.Generate(options), options)
            end
        end
    end
end

-- The answer a clock prompt works out to, as its choice reads.
local function Time(prompt)
    local hour = tonumber(prompt:match("half past (%d+)") or "")

    if hour then
        return Clock((hour * 60) + 30)
    end

    hour = tonumber(prompt:match("quarter past (%d+)") or "")

    if hour then
        return Clock((hour * 60) + 15)
    end

    hour = tonumber(prompt:match("quarter to (%d+)") or "")

    if hour then
        return Clock((HourBefore(hour) * 60) + 45)
    end

    local m, past = prompt:match("(%d+) minutes past (%d+)")

    if m then
        return Clock((tonumber(past) * 60) + tonumber(m))
    end

    local k, to = prompt:match("(%d+) minutes to (%d+)")

    if k then
        return Clock((HourBefore(tonumber(to)) * 60) + (60 - tonumber(k)))
    end

    if prompt:find("short hand") then
        local short = tonumber(prompt:match("short hand [%a ]-the (%d+)"))
        local long = tonumber(prompt:match("long hand [%a ]-the (%d+)"))

        return Clock((short * 60) + ((long % 12) * 5))
    end

    local times = {}

    for clock in prompt:gmatch("%d+:%d%d") do
        times[#times + 1] = Minutes(clock)
    end

    if #times == 2 then
        return ((times[2] - times[1]) .. " minutes")
    end

    return Clock(times[1] + tonumber(prompt:match("(%d+) minutes")))
end

local function Where(p, options)
    return ("%s grade %d level %d: %q (choices %s)"):format(p.kind, options.grade, options.level, p.prompt, table.concat(p.choices, " | "))
end

test("every place-value, clock and number-line answer is what its prompt works out to", function()
    local _, _, ns = Kit.LoadKid()

    for _, kind in ipairs(Kinds) do
        Sample(ns.Puzzles, kind, 40, function(p, options)
            local correct = p.choices[p.answer]
            local where = Where(p, options)

            if kind == "math.placeValue" then
                eq(tonumber(correct), PlaceValue(p.prompt), where)
            elseif kind == "math.time" then
                eq(correct, Time(p.prompt), where)

                for _, choice in ipairs(p.choices) do
                    local minutes = Minutes(choice)

                    if minutes then
                        truthy((minutes >= 60) and (minutes < 780), "a real clock time " .. choice .. " at " .. where)
                    else
                        truthy(choice:match("^%d+ minutes$"), "a length of time " .. choice .. " at " .. where)
                    end
                end
            elseif NumberLine(p.prompt) then
                eq(tonumber(correct), NumberLine(p.prompt), where)
            else
                local t = Numbers(p.prompt)[1]

                for i, choice in ipairs(p.choices) do
                    truthy((i == p.answer) or (math.abs(tonumber(choice) - t) > math.abs(tonumber(correct) - t)),
                        "the answer is the one closest at " .. where)
                end
            end
        end)
    end
end)

-- Whether the riddle offers choice, with a why.
local function Offers(p, choice)
    for i, offered in ipairs(p.choices) do
        if (i ~= p.answer) and (offered == choice) then
            return (p.whys[i] ~= nil)
        end
    end

    return false
end

test("each kind offers the mistakes it exists to catch, with a why", function()
    local _, _, ns = Kit.LoadKid()
    local seen = {}

    local function Saw(label, yes)
        seen[label] = ((seen[label] or 0) + ((yes and 1) or 0))
    end

    Sample(ns.Puzzles, "math.time", 60, function(p, options)
        local where = Where(p, options)
        local hour = tonumber(p.prompt:match("half past (%d+)") or "")

        if hour then
            truthy(Offers(p, Clock((hour * 60) + 50)), "half past read as :50 at " .. where)
            Saw("half", true)
        end

        hour = tonumber(p.prompt:match("quarter to (%d+)") or "")

        if hour then
            truthy(Offers(p, Clock((hour * 60) + 15)), "quarter to read as quarter past at " .. where)
            Saw("quarter to", true)
        end

        local short = p.prompt:match("short hand [%a ]-the (%d+)")
        local long = p.prompt:match("long hand [%a ]-the (%d+)")

        if short and (short ~= long) then
            Saw("hands swapped", Offers(p, Clock((tonumber(long) * 60) + ((tonumber(short) % 12) * 5))))
        end

        local start, stop = p.prompt:match("at (%d+:%d%d) and [%a ]-at (%d+:%d%d)")

        if start and (math.floor(Minutes(stop) / 60) > math.floor(Minutes(start) / 60)) then
            local hundred = ((tonumber((stop:gsub(":", ""))) - tonumber((start:gsub(":", "")))) .. " minutes")

            truthy(Offers(p, hundred), "an hour taken as 100 minutes at " .. where)
            Saw("hundred", true)
        end
    end)

    Sample(ns.Puzzles, "math.placeValue", 60, function(p, options)
        local where = Where(p, options)
        local d = (p.prompt:match("the (%d) worth") or p.prompt:match("the (%d) in it worth"))

        if d then
            truthy(Offers(p, d), "the digit itself at " .. where)
            Saw("wrong place", Offers(p, tostring(PlaceValue(p.prompt) * 10)))
        end

        local tens, ones = p.prompt:match("is (%d+) tens? and (%d+) ones?%?")

        if tens and (tens ~= ones) then
            truthy(Offers(p, ones .. tens), "swapped digits at " .. where)
            Saw("swapped", true)
        end
    end)

    Sample(ns.Puzzles, "math.numberLine", 60, function(p, options)
        local where = Where(p, options)

        if p.prompt:find("closest") then
            local t = Numbers(p.prompt)[1]
            local found = false

            for i, choice in ipairs(p.choices) do
                found = (found or ((i ~= p.answer) and (choice:sub(1, 1) == tostring(t):sub(1, 1)) and Offers(p, choice)))
            end

            truthy(found, "a number with the same first digit, farther off, at " .. where)
            Saw("digits", true)
        end

        local row = p.prompt:match("\n(0 [%+%*%-]+ %d+)\n")

        if row then
            local ticks = row:match("^0 ([%+%*%-]+) "):gsub("%-", "")

            truthy(Offers(p, tostring(ticks:find("*", 1, true) - 1)), "the jumps counted, not their worth, at " .. where)
            Saw("ticks", true)
        end
    end)

    for _, label in ipairs({ "half", "quarter to", "hands swapped", "hundred", "wrong place", "swapped", "digits", "ticks" }) do
        truthy((seen[label] or 0) > 0, label .. " turns up")
    end
end)

test("a number line's star riddle is drawn as a line with its ends labeled, in place of its text", function()
    local _, _, ns = Kit.LoadKid()
    local puzzle

    for seed = 1, 200 do
        math.randomseed(seed)
        local p = ns.Puzzles.Generate({ grade = 2, kind = "math.numberLine", level = 2, random = Roll, subject = "math" })

        if p.picture then
            puzzle = p

            break
        end
    end

    truthy(puzzle, "some grade 2 number-line riddle has a picture")
    eq(puzzle.picture.kind, "line")
    ns.ScholarView.Show(puzzle, { keys = { "1", "2", "3", "4" }, rank = "Apprentice", stars = 3 })
    local frame = ns.ScholarView.Frame()
    local pictures = frame.Pictures
    local ticks = 0

    for _, tick in ipairs(pictures.Ticks) do
        if tick:IsShown() then ticks = (ticks + 1) end
    end

    eq(ticks, puzzle.picture.jumps + 1, "a tick at 0 and after every jump")
    truthy(pictures:IsShown() and pictures.Bar:IsShown() and pictures.Star:IsShown(), "the line and its star")
    eq(Reveal(Harness.State(pictures.From).text), "0")
    eq(Reveal(Harness.State(pictures.To).text), tostring(puzzle.picture.to))
    local text = (Reveal(Harness.State(frame.Story).text or "") .. Reveal(Harness.State(frame.Question).text or ""))

    falsy(text:find(puzzle.picture.row, 1, true), "the line's text gives way to the drawing: " .. text)

    ns.ScholarView.Show({ answer = 1, choices = { "4", "5", "3", "6" }, explanation = "", hint = "", kind = "math.add",
        prompt = "What is 2 + 2?", subject = "math", title = "Add" }, { keys = { "1", "2", "3", "4" }, rank = "Apprentice", stars = 3 })

    falsy(pictures.Bar:IsShown() or pictures.Star:IsShown() or pictures.From:IsShown(), "the next riddle's picture area forgets the line")
end)
