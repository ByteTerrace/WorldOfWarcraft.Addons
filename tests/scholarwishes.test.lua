-- Wishes (ScholarWishes.lua): stars a child earns buy wishes from a grown-up. A grown-up adds wishes with a price, and
-- a child can wish for something too, for a grown-up to price. With enough stars, the Owl offers to ask. Asking holds
-- the stars, so they can't be spent twice, and the wish waits for a grown-up's answer: on the same account at their
-- next login, or as a card right away when they're grouped and the child named them. Granted spends the stars, and Not
-- now gives them back. Ranks count every star ever earned, so spending never lowers one. With a PIN set, only a
-- grown-up who knows it can price, grant, or give bonus stars.

local Kit = use("scholar")
local Krew = use("toolkit")
local LoadKid = Kit.LoadKid
local Solve = Kit.Solve
local Watch = Kit.Watch

-- A child's character, with the grown-up's PIN set (1234) when locked, and the challenge on.
local function Child(locked, settings)
    local saved = { ["Scholar.quests"] = false }

    for key, value in pairs(settings or {}) do saved[key] = value end

    local h, addon, ns = LoadKid(saved)

    if locked then
        h:Slash("/tlk lock 1234")
    end

    return h, addon, ns
end

local function Printed(h, from)
    local lines = {}

    for i = (from or 0) + 1, #h.printed do
        lines[#lines + 1] = h.printed[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end

    return table.concat(lines, "\n")
end

-- What /tlk wishes prints.
local function Wishes(h)
    local from = #h.printed

    h:Slash("/tlk wishes")

    return Printed(h, from)
end

test("a grown-up adds a wish with a price, and the child sees how close their stars are", function()
    local h, addon = Child()

    h:Slash("/tlk wish 15 Ride the gryphon together")
    truthy(Printed(h):find("Wish added: Ride the gryphon together, for 15 stars.", 1, true), Printed(h))
    truthy(Wishes(h):find("1. Ride the gryphon together: 0 of 15 stars.", 1, true), Wishes(h))
    addon.State:Set("Scholar.stars", 12)
    truthy(Wishes(h):find("1. Ride the gryphon together: 12 of 15 stars.", 1, true), Wishes(h))
end)

test("a child can wish for something too, and a grown-up gives it its price", function()
    local h = Child(true)

    h:Slash("/tlk wish Get a turtle pet")
    truthy(Wishes(h):find("1. Get a turtle pet: waiting for a grown-up to set its price.", 1, true), Wishes(h))
    h:Slash("/tlk price 1 10")
    truthy(Printed(h):find("That's for a grown-up", 1, true), "a locked child can't price it")
    h:Slash("/tlk unlock 1234")
    h:Slash("/tlk price 1 10")
    truthy(Wishes(h):find("1. Get a turtle pet: 0 of 10 stars.", 1, true), Wishes(h))
end)

test("with enough stars the Owl offers to ask, and asking holds the stars so they can't be spent twice", function()
    local h, addon, ns = Child(false, { ["Scholar.missPause"] = "off" })
    local shown = Watch(ns)

    h:Slash("/tlk wish 2 A new pet")
    h:Slash("/tlk wish 2 Pick our next zone")
    Solve(h, shown)
    eq(Krew.Card(h), nil, "one star isn't enough for either")
    Solve(h, shown)
    h:Advance(2)
    local text, card = Krew.Card(h)

    truthy(text and text:find("A new pet", 1, true), tostring(text))
    h:Click(card)
    truthy(Wishes(h):find("1. A new pet: asked! Waiting for a grown-up's answer.", 1, true), Wishes(h))
    local stars = addon.State:Get("Scholar.stars")
    local left = (stars - 2)

    truthy(Wishes(h):find(("Stars to spend: %d."):format(left), 1, true), "the wish's two stars are held: " .. Wishes(h))
    h:Slash("/tlk ask 2")

    truthy(Printed(h):find(("Pick our next zone needs 2 stars, and you have %d to spend. %d to go!"):format(left, 2 - left),
        1, true), Printed(h))

    eq(addon.State:Get("Scholar.stars"), stars, "holding stars doesn't take them away")
end)

test("a grown-up on the same account grants the wish at their next login, and the child's stars are spent at theirs", function()
    local h, addon = Child()

    h:Slash("/tlk wish 5 Ride the gryphon together")
    addon.State:Set("Scholar.stars", 7)
    h:Slash("/tlk ask 1")
    h:SwitchCharacter("Mom")
    local text, card = Krew.Card(h)

    truthy(text and text:find("Tester Doe wishes for Ride the gryphon together (5 stars).", 1, true), tostring(text))
    h:Click(card)
    truthy(Wishes(h):find("No wishes are waiting for an answer.", 1, true), Wishes(h))
    h:SwitchCharacter("Tester")
    text = Krew.Card(h)
    truthy(text and text:find("Ride the gryphon together", 1, true) and text:find("granted", 1, true), tostring(text))
    truthy(Wishes(h):find("Stars to spend: 2.", 1, true), Wishes(h))
    truthy(not Wishes(h):find("Ride the gryphon", 1, true), "a granted wish leaves the list")
end)

test("Not now gives the child's stars back, and the wish stays on the list", function()
    local h, addon = Child()

    h:Slash("/tlk wish 5 Ride the gryphon together")
    addon.State:Set("Scholar.stars", 5)
    h:Slash("/tlk ask 1")
    h:SwitchCharacter("Mom")
    h:Slash("/tlk deny 1")
    h:SwitchCharacter("Tester")
    truthy(Wishes(h):find("1. Ride the gryphon together: 5 of 5 stars.", 1, true), Wishes(h))
    truthy(Wishes(h):find("Stars to spend: 5.", 1, true), Wishes(h))
end)

test("ranks count every star earned, so a granted wish never lowers one", function()
    local h, addon = Child()

    addon.State:Set("Scholar.stars", 12)
    h:Slash("/tlk wish 10 A new mount")
    h:Slash("/tlk ask 1")
    h:SwitchCharacter("Mom")
    h:Slash("/tlk grant 1")
    h:SwitchCharacter("Tester")
    local from = #h.printed

    h:Slash("/tlk scholar")
    truthy(Printed(h, from):find("Stars: 12 (Journeyman). 2 to spend.", 1, true), Printed(h, from))
end)

test("with a PIN set, only a grown-up who knows it can grant, and three wrong PINs make it wait", function()
    local h, addon = Child(true)

    h:Slash("/tlk unlock 1234")
    h:Slash("/tlk wish 3 A new pet")
    addon.State:Set("Scholar.stars", 3)
    h:Slash("/tlk ask 1")
    h:SwitchCharacter("Mom")
    local _, card = Krew.Card(h)

    h:Click(card)
    truthy(Printed(h):find("/tlk grant 1 <your PIN>", 1, true), "a card can't take a PIN, so it says how")
    h:Slash("/tlk grant 1 9999")
    h:Slash("/tlk grant 1 9998")
    h:Slash("/tlk grant 1 9997")
    h:Slash("/tlk grant 1 1234")
    truthy(Printed(h):find("Too many wrong PINs.", 1, true), Printed(h))
    h:Advance(61)
    h:Slash("/tlk grant 1 1234")
    truthy(Wishes(h):find("No wishes are waiting for an answer.", 1, true), Wishes(h))
end)

test("a grown-up gives bonus stars for a clever trick, and the report says so", function()
    local h, addon = Child()

    h:Slash("/tlk star 2 Nice trick with the reload!")
    truthy(Wishes(h):find("Stars to spend: 2.", 1, true), "bonus stars are stars to spend")
    eq(addon.State:Get("Scholar.stars"), 0, "but not riddles solved, so no rank or Krew card claims they were")
    local text = Krew.Card(h)

    truthy(text and text:find("Nice trick with the reload!", 1, true), tostring(text))
    local from = #h.printed

    h:Slash("/tlk report")

    truthy(Printed(h, from):find("2 bonus stars from a grown-up, the last for: Nice trick with the reload!", 1, true),
        Printed(h, from))
end)

test("grouped with a grown-up the child named, a wish arrives as a card, and their answer comes straight back", function()
    local h, addon = Child()

    h:Slash("/tlk parent Mom Doe")
    h:Slash("/tlk wish 3 A dungeon run together")
    addon.State:Set("Scholar.stars", 3)
    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)
    h:Slash("/tlk ask 1")
    eq(table.concat(Krew.Sent(h, "WISH"), " | "), "WISH:Mom Doe\t1\t3\tA dungeon run together", "the wish names Mom")
    Krew.Receive(h, "Pal", "WISHED", "Tester Doe", "1", "1")
    truthy(Wishes(h):find("asked!", 1, true), "an answer from anyone else is ignored")
    Krew.Receive(h, "Mom", "WISHED", "Tester Doe", "1", "1")
    truthy(Wishes(h):find("Stars to spend: 0.", 1, true), Wishes(h))
    truthy(not Wishes(h):find("A dungeon run", 1, true), "Mom granted it")
end)

test("a grown-up grouped with a child sees the wish meant for them as a card, and answers it back", function()
    local h = Krew.Grouped()

    Krew.Receive(h, "Mom", "WISH", "Someone Else", "1", "3", "Not for you")
    eq(Krew.Card(h), nil, "a wish meant for someone else doesn't show")
    Krew.Receive(h, "Mom", "WISH", "Tester Doe", "4", "3", "A dungeon run together")
    local text, card = Krew.Card(h)

    truthy(text and text:find("Mom Doe wishes for A dungeon run together (3 stars).", 1, true), tostring(text))
    h:Click(card)
    eq(table.concat(Krew.Sent(h, "WISHED"), " | "), "WISHED:Mom Doe\t4\t1", "the answer goes back to Mom")
end)

test("the wishlist says what's wrong with a command it can't do", function()
    local h, addon = Child()
    local said = {}

    local function Try(slash, expected)
        local from = #h.printed

        h:Slash(slash)
        said[#said + 1] = slash
        truthy(Printed(h, from):find(expected, 1, true), slash .. ": " .. Printed(h, from))
    end

    Try("/tlk wish", "Usage: /tlk wish <what you'd like>")
    Try("/tlk wish " .. string.rep("a", 61), "Keep a wish under 60 letters.")
    Try("/tlk ask 9", "There's no wish with that number.")
    Try("/tlk grant 9", "There's no wish waiting with that number.")
    Try("/tlk star", "Usage: /tlk star <1 to 10> <why>.")
    Try("/tlk parent", "Usage: /tlk parent <First Last>.")
    h:Slash("/tlk lock 1234")
    Try("/tlk wish A surprise", "A grown-up will set its price.")
    Try("/tlk ask 1", "A surprise needs a grown-up to set its price first.")
    h:Slash("/tlk unlock 1234")
    h:Slash("/tlk price 1 1")
    addon.State:Set("Scholar.stars", 1)
    h:Slash("/tlk ask 1")
    Try("/tlk ask 1", "You already asked for A surprise.")

    for i = 2, 12 do h:Slash("/tlk wish 1 Wish " .. i) end

    Try("/tlk wish 1 One too many", "The wishlist is full.")
    Try("/tlk unwish 12", "Removed: Wish 12.")
end)

test("a grown-up sees every waiting wish in order, and the report counts the ones granted", function()
    local h, addon = Child()

    h:Slash("/tlk wish 1 A new pet")
    h:Slash("/tlk wish 1 Pick our next zone")
    addon.State:Set("Scholar.stars", 2)
    h:Slash("/tlk ask 1")
    h:Advance(5)
    h:Slash("/tlk ask 2")
    h:SwitchCharacter("Mom")
    local list = Wishes(h)

    truthy(list:find("Waiting for your answer:\n", 1, true) and list:find("1. Tester Doe wishes for A new pet", 1, true)
        and list:find("2. Tester Doe wishes for Pick our next zone", 1, true), list)

    h:Slash("/tlk grant 1")
    h:Slash("/tlk grant 1")
    h:SwitchCharacter("Tester")
    local from = #h.printed

    h:Slash("/tlk report")
    truthy(Printed(h, from):find("Wishes granted: 2, the last: ", 1, true), Printed(h, from))
end)

test("an answer for a wish that's gone changes nothing", function()
    local h, addon = Child()

    h:Slash("/tlk parent Mom Doe")
    h:Slash("/tlk wish 1 A new pet")
    addon.State:Set("Scholar.stars", 1)
    h:Slash("/tlk ask 1")
    h:Slash("/tlk unwish 1")
    h:JoinGroup("party", { "Mom" })
    h:Advance(2)
    Krew.Receive(h, "Mom", "WISHED", "Tester Doe", "1", "1")
    eq(addon.Modules.Wishes:Get("spent"), 0, "nothing is spent on a wish that's gone")
end)
