-- The Owl's shopping help (ScholarShop.lua): at a vendor or the auction house, the item a young player points at (with
-- the mouse, or the controller's focus) gets the Owl's take in its tooltip and in a helper panel beside the window:
-- whether they can use it, whether it's better, whether they'll outgrow it soon, and whether it costs too much of their
-- gold. Wish for it (L3, or a click) adds it to their wishes, priced in stars at the worth a grown-up set, with no
-- grown-up step before they can ask.

local Kit = use("scholar")
local LoadKid = Kit.LoadKid

local Helm = 1002
local Robe = 1003
local Vest = 1001
local Worn = 1004

local function Panel(h)
    return rawget(h.env, "TheLanKrewToolKitShop")
end

-- A level 10 young player with 2 gold, a worn chest of item level 8, and a vendor's items.
local function Shopper(settings)
    local saved = { ["Scholar.quests"] = false }

    for key, value in pairs(settings or {}) do saved[key] = value end

    local h, addon, ns = LoadKid(saved)

    h.player.level, h.player.money = 10, 20000
    h:AddItem(Vest, "Linen Vest", 1, 135009, nil, { equipLoc = "INVTYPE_CHEST", level = 12, minLevel = 8 })
    h:AddItem(Helm, "Iron Helm", 2, 133070, nil, { equipLoc = "INVTYPE_HEAD", level = 20, minLevel = 14 })
    h:AddItem(Robe, "Silk Robe", 3, 132665, nil, { equipLoc = "INVTYPE_ROBE", level = 15, minLevel = 9 })
    h:AddItem(Worn, "Recruit's Shirt", 1, 135011, nil, { equipLoc = "INVTYPE_CHEST", level = 8, minLevel = 1 })
    h.equipped = { [5] = Worn }
    h.merchantItems = { { id = Vest, price = 800 }, { id = Helm, price = 1200 }, { id = Robe, price = 30000, usable = false } }

    return h, addon, ns
end

local function Text(fontString)
    return (fontString:GetText() or "")
end

local function TooltipLines(h)
    return table.concat(Harness.State(h.env.GameTooltip).lines, "\n")
end

local function Wishes(h)
    local from = #h.printed

    h:Slash("/tlk wishes")
    h:Key("ESCAPE", true)

    return table.concat(h.printed, "\n", from + 1)
end

test("at a vendor, the Owl's take on the item pointed at joins its tooltip", function()
    local h = Shopper()

    h:OpenInteraction("Merchant")
    h:ShowItemTooltip(Vest)
    truthy(TooltipLines(h):find("The Owl: An upgrade: +4 item level!", 1, true), TooltipLines(h))
    h:ShowItemTooltip(Helm)
    truthy(TooltipLines(h):find("The Owl: You can use this at level 14.", 1, true), TooltipLines(h))
    h:ShowItemTooltip(Robe)
    truthy(TooltipLines(h):find("The Owl: Your class can't use this.", 1, true), TooltipLines(h))
end)

test("the helper panel beside the vendor shows the item pointed at, the Owl's take, and its price in stars", function()
    local h = Shopper()

    h:OpenInteraction("Merchant")
    local panel = Panel(h)

    truthy(panel:IsShown(), "it opens with the vendor")
    truthy(Text(panel.Lines):find("Point at something", 1, true), "and says what to do")
    h:ShowItemTooltip(Vest)
    eq(Text(panel.Name), "Linen Vest")
    truthy(Text(panel.Lines):find("An upgrade: +4 item level!", 1, true), Text(panel.Lines))
    eq(Text(panel.Price), "Wish for it: 1 star")
    eq(panel.Icon:GetTexture(), 135009)
end)

test("Wish for it, with L3 or a click, adds the item to the wishes at its price, ready to ask for", function()
    local h, addon = Shopper({ ["Scholar.stars"] = 3 })

    h:OpenInteraction("Merchant")
    h:ShowItemTooltip(Vest)
    h:Gamepad("PADLSTICK", true)
    local listed = Wishes(h)

    truthy(listed:find("1. |cffffffff|Hitem:1001::::::::|h[Linen Vest]|h|r: 3 of 1 star.", 1, true), "priced with no grown-up step: " .. listed)
    h:ShowItemTooltip(Helm)
    h:Click(Panel(h).Wish)
    truthy(Wishes(h):find("[Iron Helm]|h|r: 3 of 2 stars.", 1, true), "a click does the same")
    h:Slash("/tlk ask 1")
    truthy(addon.Modules.Wishes.Records.wishes:Get("1").asked, "and the child can ask for it at once")
end)

test("a grown-up sets what a star is worth, and item wishes are priced by it", function()
    local h, addon = Shopper()

    addon.State:Set("Wishes.starWorth", "1s")
    h:OpenInteraction("Merchant")
    h:ShowItemTooltip(Vest)
    eq(Text(Panel(h).Price), "Wish for it: 8 stars")
end)

test("in the auction house, an item's price is its lowest buyout", function()
    local h = Shopper()

    h.auctionResults = { { id = Vest, minPrice = 5000 } }
    h:OpenInteraction("Auctioneer")
    h:ShowItemTooltip(Vest)
    eq(Text(Panel(h).Price), "Wish for it: 5 stars")
end)

test("an item dearer than the most stars a wish can cost waits for a grown-up's price instead of failing", function()
    local h, addon = Shopper()

    -- 5000 gold at 10 silver a star is 50,000 stars; a wish costs at most 999.
    h.auctionResults = { { id = Vest, minPrice = 50000000 } }
    h:OpenInteraction("Auctioneer")
    h:ShowItemTooltip(Vest)
    eq(Text(Panel(h).Price), "Wish for it: a grown-up will set its price")
    h:Gamepad("PADLSTICK", true)
    eq(#h.errors, 0, table.concat(h.errors, "\n"))
    truthy(table.concat(h.printed, "\n"):find("Added to your wishes: Linen Vest. A grown-up will set its price.", 1, true))
    eq(addon.Modules.Wishes.Records.wishes:Get("1").price, 0, "unpriced")
end)

test("away from a vendor nothing changes, and closing the vendor hides the panel and gives L3 back", function()
    local h = Shopper()

    h:ShowItemTooltip(Vest)
    falsy(TooltipLines(h):find("The Owl:", 1, true), "no take away from a vendor")
    h:OpenInteraction("Merchant")
    h:CloseInteraction("Merchant")
    falsy(Panel(h):IsShown())
    local before = #h.propagated

    h:Gamepad("PADLSTICK", true)
    eq(h.propagated[before + 1], "PADLSTICK", "L3 is the game's again")
end)

test("the help follows its own switch and the challenge's", function()
    for _, row in ipairs({ "Shopping.enabled", "Scholar.enabled" }) do
        local h, addon = Shopper()

        addon.State:Set(row, false)
        h:OpenInteraction("Merchant")
        h:ShowItemTooltip(Vest)
        falsy(TooltipLines(h):find("The Owl:", 1, true), row)
        falsy(Panel(h) and Panel(h):IsShown(), row)
    end
end)

test("with a controller, Wish for it shows L3's glyph", function()
    local h = Shopper()

    h.labelStyle = "Letters"
    h:OpenInteraction("Merchant")
    truthy(Text(Panel(h).Wish.Label):find("|A:gamepad-xbox1-padlstick-normal", 1, true), Text(Panel(h).Wish.Label))
end)

test("an item the shop doesn't sell waits for a grown-up's price, one not cached yet gets no take, and a full list says so", function()
    local h = Shopper()

    h:AddItem(2001, "Mystery Box", 1, 134400, true)
    h:OpenInteraction("Merchant")
    h:ShowItemTooltip(2001)
    falsy(TooltipLines(h):find("The Owl:", 1, true), "nothing to say about an item not cached yet")
    h:AddItem(2002, "Bag of Marbles", 1, 134400)
    h:ShowItemTooltip(2002)
    eq(Text(Panel(h).Price), "", "no price where it isn't sold")
    h:Gamepad("PADLSTICK", true)
    truthy(table.concat(h.printed, "\n"):find("Added to your wishes: Bag of Marbles. A grown-up will set its price.", 1, true))

    for _ = 2, 12 do h:Gamepad("PADLSTICK", true) end

    h:Gamepad("PADLSTICK", true)
    truthy(h.printed[#h.printed]:find("The wishlist is full.", 1, true), h.printed[#h.printed])
end)
