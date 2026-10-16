-- Question cards with a controller (Cards.lua): while a question card shows, out of combat, Select focuses it, then A
-- answers yes and B no. Every other button stays the player's until Select is pressed, and the card's buttons are the
-- controller's only while it's focused.

local Kit = use("toolkit")
local Card = Kit.Card

-- Shows a question card whose yes counts in answers.yes.
local function Ask(ns, answers)
    ns.Cards.Show({ body = "Bob Doe killed you.", onClick = function() answers.yes = (answers.yes + 1) end,
        title = "Hold the grudge?" })
end

-- A harness with The Lan Krew ToolKit loaded and an Xbox controller connected, and its namespace.
local function LoadWithController()
    local h = Harness.New()

    h.labelStyle = "Letters"
    local ns = h:LoadAddon("TheLanKrewToolKit")

    return h, ns
end

local function Prompt(h)
    local card = rawget(h.env, "TheLanKrewToolKitCard")

    return Reveal(Harness.State(card.Prompt).text), card.Prompt:IsShown()
end

test("Select focuses a question card, then A answers yes, and the controller is the player's again", function()
    local h, ns = LoadWithController()
    local answers = { yes = 0 }

    Ask(ns, answers)
    eq(Prompt(h), "View: answer", "the card says how")
    h:Gamepad("PAD3", true)
    eq(h.propagated[#h.propagated], "PAD3", "before Select, every other button is the player's")
    h:Gamepad("PADBACK", true)
    h:Gamepad("PADBACK", false)
    eq(Prompt(h), "A: yes    B: no")
    local propagated = #h.propagated

    h:Gamepad("PAD3", true)
    eq(#h.propagated, propagated, "focused, the card has the controller")
    h:Gamepad("PAD1", true)
    h:Gamepad("PAD1", false)
    eq(answers.yes, 1, "A said yes")
    eq(Card(h), nil, "and the card went")
    eq(next(h.overrideBindings), nil, "Select is the game's again")
    h:Gamepad("PAD3", true)
    eq(h.propagated[#h.propagated], "PAD3", "and so is every other button")
end)

test("B says no: the card goes, and nothing happens", function()
    local h, ns = LoadWithController()
    local answers = { yes = 0 }

    Ask(ns, answers)
    h:Gamepad("PADBACK", true)
    h:Gamepad("PAD2", true)
    eq(answers.yes, 0)
    eq(Card(h), nil)
end)

test("Select again lets go of the card without answering, and a focused card waits", function()
    local h, ns = LoadWithController()
    local answers = { yes = 0 }

    Ask(ns, answers)
    h:Gamepad("PADBACK", true)
    h:Advance(30)
    truthy(Card(h), "a focused card doesn't time out")
    h:Gamepad("PADBACK", true)
    eq(Prompt(h), "View: answer", "back to the question")
    h:Gamepad("PAD3", true)
    eq(h.propagated[#h.propagated], "PAD3", "and the controller is the player's")
    h:Advance(13)
    eq(Card(h), nil, "unfocused, it times out again")
    eq(next(h.overrideBindings), nil, "and its summon goes with it")
end)

test("a card that isn't a question takes no button, and says nothing about the controller", function()
    local h, ns = LoadWithController()

    ns.Cards.Show({ body = "Level 12!", title = "Ding" })
    truthy(Card(h))
    eq(next(h.overrideBindings), nil)
    local _, shown = Prompt(h)

    falsy(shown)
end)

test("a fight takes the question card and its summon away before lockdown, and they come back after", function()
    local h, ns = LoadWithController()
    local answers = { yes = 0 }

    Ask(ns, answers)
    h:Gamepad("PADBACK", true)
    h:EnterCombat()
    eq(Card(h), nil, "cards never interrupt a fight")
    eq(next(h.overrideBindings), nil, "Select is the game's in the fight")
    eq(#h.blocked, 0, "nothing was blocked")
    h:Gamepad("PAD3", true)
    eq(h.propagated[#h.propagated], "PAD3", "nor is the controller held")
    h:LeaveCombat()
    truthy(Card(h), "the card is back")
    eq(Prompt(h), "View: answer", "unfocused")
    h:Gamepad("PADBACK", true)
    h:Gamepad("PAD1", true)
    eq(answers.yes, 1)
end)

test("without a controller a question card says nothing about one, and the mouse still answers", function()
    local h = Harness.New()
    local ns = h:LoadAddon("TheLanKrewToolKit")
    local answers = { yes = 0 }

    Ask(ns, answers)
    local _, shown = Prompt(h)

    falsy(shown, "no controller, no prompt")
    h:Click(rawget(h.env, "TheLanKrewToolKitCard"))
    eq(answers.yes, 1)
end)

test("a focused card holds after the mouse leaves it", function()
    local h, ns = LoadWithController()

    Ask(ns, { yes = 0 })
    h:Gamepad("PADBACK", true)
    local card = rawget(h.env, "TheLanKrewToolKitCard")

    truthy(h:Hover(card, true))
    truthy(h:Hover(card, false))
    h:Advance(13)
    truthy(Card(h), "a focused card doesn't time out when the mouse leaves it")
end)

test("focusing a card keeps a riddle's controller map, and letting go of the card leaves it", function()
    local h, ns = LoadWithController()
    local addon = ns.Addon
    local answers = { yes = 0 }

    Ask(ns, answers)
    h:Gamepad("PADBACK", true)
    eq(table.concat(addon.Input:ActiveMaps(), ","), "card")
    addon.Input:SetActiveMaps({ "scholar", "card" })
    h:Gamepad("PAD2", true)
    eq(table.concat(addon.Input:ActiveMaps(), ","), "scholar", "only the card's map goes")
end)
