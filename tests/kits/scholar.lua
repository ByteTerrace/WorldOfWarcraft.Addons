-- Helpers for Scholar's end-to-end tests (scholarui, scholarquests, scholarscreen): a child's character with the
-- challenge on, the riddles the screen shows, and answering them. Every load seeds the random source with 7, so the
-- riddles asked are the same on every run. A test file gets the table with use("scholar").

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

--- An answer other than the right one and except.
local function WrongAnswer(puzzle, except)
    for i = 1, 4 do
        if (i ~= puzzle.answer) and (i ~= except) then
            return i
        end
    end
end

return {
    Accept = Accept, Banner = Banner, Load = Load, LoadKid = LoadKid, Numbers = Numbers, Showing = Showing, Solve = Solve,
    Watch = Watch, WrongAnswer = WrongAnswer,
}
