local addonName, ns = ...

-- ScholarAdvice: the Owl's take on an item a young player might buy, in a child's words. It only decides, from plain
-- facts the shopping helper (ScholarShop.lua) reads, so it holds no state and calls no API.
--
--   ns.ScholarAdvice.Verdict(item, player) -> lines   most important first, or none for a plain, cheap item
--     item: { name, quality, itemLevel, minLevel, equipLoc ("" for none), price (copper), usable (false when the
--     vendor says the player's class can't use it), equippedLevel (the item level in its slot, false for an empty
--     slot, nil when it isn't gear) }; player: { level, money (copper) }
--   ns.ScholarAdvice.Stars(price, worth) -> stars   a wish's price: the gold price at a star's worth, rounded up, at
--     least one

-- How many levels below the player's an item's level requirement can be before they'll soon outgrow it.
local OutgrowLevels = 5

local ceil = math.ceil
local max = math.max

-- Whether an equipLoc names gear worn in a slot.
local function IsGear(item)
    return ((item.equipLoc ~= nil) and (item.equipLoc ~= "") and (item.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE")
        and (item.equippedLevel ~= nil))
end

local function Stars(price, worth)
    return max(1, ceil((price or 0) / worth))
end

local function Verdict(item, player)
    local lines = {}
    local usable = true

    if (item.minLevel or 0) > player.level then
        lines[#lines + 1] = ("You can use this at level %d."):format(item.minLevel)
        usable = false
    end

    if item.usable == false then
        lines[#lines + 1] = "Your class can't use this."
        usable = false
    end

    if usable and IsGear(item) then
        if item.equippedLevel == false then
            lines[#lines + 1] = "Nothing in that slot yet: a good pick!"
        elseif item.itemLevel > item.equippedLevel then
            lines[#lines + 1] = ("An upgrade: +%d item level!"):format(item.itemLevel - item.equippedLevel)
        else
            lines[#lines + 1] = "Not better than what you're wearing."
        end

        if (player.level - (item.minLevel or 0)) >= OutgrowLevels then
            lines[#lines + 1] = "You'll outgrow this soon. Quests give gear like this."
        end
    end

    if (item.price or 0) > player.money then
        lines[#lines + 1] = "You don't have enough gold. Wish for it instead!"
    elseif ((item.price or 0) * 2) > player.money then
        lines[#lines + 1] = "That's most of your gold! Maybe wish for it instead."
    end

    return lines
end

ns.ScholarAdvice = { Stars = Stars, Verdict = Verdict }
