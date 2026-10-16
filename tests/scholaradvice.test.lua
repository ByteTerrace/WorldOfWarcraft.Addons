-- The Owl's take on an item (ScholarAdvice.lua): whether a young player can use it, whether it's better than what they
-- wear, whether they'll outgrow it soon, and whether it costs too much of their gold, in a child's words, most
-- important first, with its price in stars for a wish.

local Kit = use("scholar")

local function Advice()
    local _, _, ns = Kit.LoadKid()

    return ns.ScholarAdvice
end

-- A level 10 player with 2 gold.
local Player = { level = 10, money = 20000 }

local function Item(fields)
    local item = { equipLoc = "INVTYPE_CHEST", itemLevel = 12, minLevel = 8, name = "Linen Vest", price = 800, quality = 1 }

    for key, value in pairs(fields or {}) do item[key] = value end

    return item
end

test("an item a player can't use yet says when they can, first", function()
    local lines = Advice().Verdict(Item({ minLevel = 14 }), Player)

    eq(lines[1], "You can use this at level 14.")
end)

test("an item their class can't use says so", function()
    local lines = Advice().Verdict(Item({ usable = false }), Player)

    eq(lines[1], "Your class can't use this.")
end)

test("gear says whether it's better than what's in its slot", function()
    local advice = Advice()

    eq(advice.Verdict(Item({ equippedLevel = 8 }), Player)[1], "An upgrade: +4 item level!")
    eq(advice.Verdict(Item({ equippedLevel = 12 }), Player)[1], "Not better than what you're wearing.")
    eq(advice.Verdict(Item({ equippedLevel = false }), Player)[1], "Nothing in that slot yet: a good pick!")
end)

test("cheap gear far below their level says they'll outgrow it soon", function()
    local lines = Advice().Verdict(Item({ equippedLevel = 3, minLevel = 3 }), Player)

    eq(lines[2], "You'll outgrow this soon. Quests give gear like this.")
end)

test("an item over half their gold says to think twice, and one they can't afford says to wish for it", function()
    local advice = Advice()

    eq(advice.Verdict(Item({ equipLoc = "", price = 15000 }), Player)[1], "That's most of your gold! Maybe wish for it instead.")
    eq(advice.Verdict(Item({ equipLoc = "", price = 30000 }), Player)[1], "You don't have enough gold. Wish for it instead!")
    eq(#advice.Verdict(Item({ equipLoc = "", price = 500 }), Player), 0, "a cheap, plain item gets no warning")
end)

test("a wish's price in stars is its gold price at a star's worth, rounded up, at least one", function()
    local advice = Advice()

    eq(advice.Stars(800, 1000), 1)
    eq(advice.Stars(2500, 1000), 3)
    eq(advice.Stars(0, 1000), 1)
end)
