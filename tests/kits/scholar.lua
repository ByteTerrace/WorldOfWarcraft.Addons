-- Helpers for Scholar's tests: a child's character with the challenge on, a riddle on screen (Riddle), the riddles the
-- screen shows, and answering them; and for the generator tests, Roll (Generate's random), ClockMinutes, and Sorted.
-- Every load seeds the random source with 7, so the riddles asked are the same on every run. A test file gets the table
-- with use("scholar").

--- Offers the quest spec (from giver, Eagan Peltskinner by default) and accepts it.
local function Accept(h, spec, giver)
    h:OfferQuest(spec, giver or "Eagan Peltskinner")
    h:AcceptQuest()
end

--- The riddle screen's feedback banner text, without its colors.
local function Banner(h)
    local text = Harness.State(rawget(h.env, "TheLanKrewToolKitScholar").Feedback.Text).text

    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--- A clock time's minutes, its hour times 60 plus its minutes, or nil for text that isn't one.
local function ClockMinutes(text)
    local hour, minutes = text:match("^(%d+):(%d%d)$")

    return ((hour and ((tonumber(hour) * 60) + tonumber(minutes))) or nil)
end

--- A harness with The Lan Krew ToolKit loaded from saved (SavedVariables by name).
---@return table h, table addon, table ns
local function Load(saved)
    local h = Harness.New({ saved = (saved or {}) })

    h:SeedRandom(7)
    local ns = h:LoadAddon("TheLanKrewToolKit")

    return h, ns.Addon, ns
end

--- A child's character with the challenge on, and extra's character settings on top.
---@return table h, table addon, table ns
local function LoadKid(extra)
    -- The pause after a miss is off: tests that answer right after a miss don't wait (scholarpace.test.lua tests it).
    local char = { ["Scholar.enabled"] = true, ["Scholar.missPause"] = "off" }

    for key, value in pairs(extra or {}) do char[key] = value end

    return Load({ TheLanKrewToolKitCharDB = char })
end

--- Every number in text, in order.
local function Numbers(text)
    local out = {}

    for number in text:gmatch("%d+%.?%d*") do
        out[#out + 1] = tonumber(number)
    end

    return out
end

--- options.random for Generate: the test Lua's own generator, refusing ranges the client's random would.
local function Roll(m, n)
    assert((m == math.floor(m)) and (n == math.floor(n)) and (m <= n), ("random(%s, %s) is not a valid range"):format(tostring(m), tostring(n)))

    return math.random(m, n)
end

--- Whether the riddle screen is up.
local function Showing(h)
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")

    return ((overlay ~= nil) and overlay:IsShown())
end

--- Asks a riddle now and answers it right; shown is Watch's list. Returns the riddle.
local function Solve(h, shown)
    h:Slash("/tlk puzzle")
    h:Key(tostring(shown[#shown].answer), true)
    h:Advance(2)

    return shown[#shown]
end

--- A word's letters, sorted (spaces and other marks left out).
local function Sorted(word)
    local letters = {}

    for letter in word:gmatch("%a") do
        letters[#letters + 1] = letter
    end

    table.sort(letters)

    return table.concat(letters)
end

--- Every puzzle the screen shows from now on, in order.
local function Watch(ns)
    local shown = {}
    local view = ns.ScholarView
    local show = view.Show

    view.Show = function(puzzle, info)
        shown[#shown + 1] = puzzle

        return show(puzzle, info)
    end

    return shown
end

--- The riddle on screen after a /reload or a relog, seen through Watch: a fight sends it away and brings it back, so
--- Watch sees the riddle the new UI asked.
local function Returned(h)
    local shown = Watch(h.ns)

    h:EnterCombat()
    h:LeaveCombat()

    return shown[#shown], rawget(h.env, "TheLanKrewToolKitScholar")
end

--- A child's riddle on screen, with the short pause and no quest riddles, and the riddle.
local function Riddle(settings)
    local saved = { ["Scholar.missPause"] = "short", ["Scholar.quests"] = false }

    for key, value in pairs(settings or {}) do saved[key] = value end

    local h, addon, ns = LoadKid(saved)
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")

    return h, addon, shown[#shown], rawget(h.env, "TheLanKrewToolKitScholar")
end

--- An answer other than the right one and except.
local function WrongAnswer(puzzle, except)
    for i = 1, 4 do
        if (i ~= puzzle.answer) and (i ~= except) then
            return i
        end
    end
end

return {
    Accept = Accept, Banner = Banner, ClockMinutes = ClockMinutes, Load = Load, LoadKid = LoadKid, Numbers = Numbers,
    Returned = Returned, Riddle = Riddle, Roll = Roll, Showing = Showing, Solve = Solve, Sorted = Sorted, Watch = Watch,
    WrongAnswer = WrongAnswer,
}
