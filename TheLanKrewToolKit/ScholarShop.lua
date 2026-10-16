local addonName, ns = ...

-- Shopping: the Owl's shopping help for a young player. While a vendor or the auction house is open, the item they
-- point at (with the mouse, or the controller's focus, which shows its tooltip the same way) gets the Owl's take
-- (ScholarAdvice.lua): in its tooltip, as one line, and in a helper panel beside the window, with its price in stars.
-- Wish for it (L3, or the panel's button) adds the item to their wishes, priced at the worth a grown-up set
-- (ns.ScholarWishes.WishFor), so they can ask for it at once instead of spending their gold on something they'll
-- outgrow.
--
-- It only reads: the vendor's items (GetMerchantItemID, C_MerchantFrame.GetItemInfo), the auction house's browse
-- results (C_AuctionHouse.GetBrowseResults, never a query), the item (C_Item.GetItemInfo), what's worn
-- (GetInventoryItemLink), and the player's level and gold. It hears the item through
-- TooltipDataProcessor.AddTooltipPostCall, which calls it behind securecallfunction, registered once as the file loads
-- (there's no way to take a post call back), so the call checks that the help runs. L3 is the one controller button
-- Blizzard's priority bindings leave free while a vendor has focus, and it's a summon (Input:Summon) only while a shop
-- is open. It follows its own switch, under Wishes on the Scholar's challenge page, and runs only while the challenge
-- does.

local OwlIcon = "Interface\\Icons\\Ability_Hunter_Pet_Owl"

-- The inventory slot each equipLoc is worn in, to compare with what's there.
local Slots = {
    INVTYPE_2HWEAPON = 16, INVTYPE_BODY = 4, INVTYPE_CHEST = 5, INVTYPE_CLOAK = 15, INVTYPE_FEET = 8, INVTYPE_FINGER = 11,
    INVTYPE_HAND = 10, INVTYPE_HEAD = 1, INVTYPE_HOLDABLE = 17, INVTYPE_LEGS = 7, INVTYPE_NECK = 2, INVTYPE_RANGED = 18,
    INVTYPE_RANGEDRIGHT = 18, INVTYPE_ROBE = 5, INVTYPE_SHIELD = 17, INVTYPE_SHOULDER = 3, INVTYPE_TRINKET = 13,
    INVTYPE_WAIST = 6, INVTYPE_WEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17, INVTYPE_WRIST = 9,
}

-- The controller button that wishes for the item pointed at.
local WishSource = "gamepad.leftStick"

local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local C_MerchantFrame = C_MerchantFrame
local CreateFrame = CreateFrame
local GetInventoryItemLink = GetInventoryItemLink
local GetMerchantItemID = GetMerchantItemID
local GetMerchantNumItems = GetMerchantNumItems
local GetMoney = GetMoney
local UIParent = UIParent
local UnitLevel = UnitLevel

local Addon = ns.Addon
local Advice = ns.ScholarAdvice
-- The item the Owl last looked at in the open shop, as ScholarAdvice's facts, or nil.
local Current = nil
local Interaction = Enum.PlayerInteractionType
-- The open shop: Interaction.Merchant or Interaction.Auctioneer, or nil.
local Open = nil
local Panel = nil
-- The module, assigned at the end of the file.
local Shopping

local function Close()
    Open, Current = nil, nil

    if Panel then
        Panel:Hide()
    end

    Addon.Input:Dismiss(Shopping, WishSource, "Shopping.wish")
end

local function PanelFrame()
    if Panel then
        return Panel
    end

    local style = ns.ScholarStyle

    Panel = CreateFrame("Frame", addonName .. "Shop", UIParent, "BackdropTemplate")

    -- Never focused by the controller UI's SmartNavigation (it covers every child): focus on an addon's control carries
    -- its taint into what the controller UI remembers, which blocks SetPreferredGamepadInteractTarget and can freeze
    -- the game (docs/ControllerSupport.md). Its controller input is summons (Input:Summon) instead.
    Panel.smartNavigationIgnored = true
    Panel:SetFrameStrata("HIGH")
    Panel:SetSize(300, 200)
    Panel:SetPoint("RIGHT", -60, 60)
    Panel:EnableMouse(true)
    style.Backdrop(Panel, 14)
    style.BackdropColors(Panel, style.Palette.panel, style.Palette.gold)
    Panel.Icon = Panel:CreateTexture(nil, "ARTWORK")
    Panel.Icon:SetSize(36, 36)
    Panel.Icon:SetPoint("TOPLEFT", 16, -16)
    Panel.Name = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Panel.Name:SetPoint("LEFT", Panel.Icon, "RIGHT", 10, 0)
    Panel.Name:SetPoint("RIGHT", -16, 0)
    Panel.Name:SetJustifyH("LEFT")
    Panel.Lines = Panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Panel.Lines:SetPoint("TOPLEFT", Panel.Icon, "BOTTOMLEFT", 0, -12)
    Panel.Lines:SetPoint("RIGHT", -16, 0)
    Panel.Lines:SetJustifyH("LEFT")
    Panel.Lines:SetSpacing(4)
    Panel.Price = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Panel.Price:SetPoint("BOTTOMLEFT", 16, 54)
    Panel.Wish = CreateFrame("Button", nil, Panel, "BackdropTemplate")
    Panel.Wish:SetSize(268, 30)
    Panel.Wish:SetPoint("BOTTOM", 0, 16)
    style.Backdrop(Panel.Wish, 10)
    style.BackdropColors(Panel.Wish, style.Palette.pill, style.Palette.edge)
    Panel.Wish.Label = Panel.Wish:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Panel.Wish.Label:SetPoint("CENTER")
    Panel:Hide()

    return Panel
end

local function Player()
    return { level = UnitLevel("player"), money = GetMoney() }
end

-- The item's price where it's sold, and whether the vendor says the player can use it.
local function PriceOf(itemID)
    if Open == Interaction.Merchant then
        for i = 1, GetMerchantNumItems() do
            if GetMerchantItemID(i) == itemID then
                local info = C_MerchantFrame.GetItemInfo(i)

                return (info and info.price), (info and info.isUsable)
            end
        end
    else
        for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
            if result.itemKey.itemID == itemID then
                return result.minPrice, nil
            end
        end
    end
end

-- ScholarAdvice's facts about an item, or nil while the client hasn't cached it.
local function Facts(itemID)
    local name, _, quality, itemLevel, minLevel, _, _, _, equipLoc, icon = C_Item.GetItemInfo(itemID)

    if not name then
        return nil
    end

    local price, usable = PriceOf(itemID)
    local slot = Slots[equipLoc]
    local equippedLevel = nil

    if slot then
        local link = GetInventoryItemLink("player", slot)

        equippedLevel = ((link and select(4, C_Item.GetItemInfo(link))) or false)
    end

    return {
        equipLoc = equipLoc, equippedLevel = equippedLevel, icon = icon, id = itemID, itemLevel = itemLevel,
        minLevel = minLevel, name = name, price = price, quality = quality, usable = usable,
    }
end

-- Wishes for the item looked at.
local function Wish()
    if Current then
        ns.ScholarWishes.WishFor(Current.id, Current.name, Current.price)
    end
end

-- The wish button's label: L3's glyph with a controller connected.
local function WishLabel()
    local prompt = ((ByteTerrace.Input.LabelStyle() ~= "Generic") and ByteTerrace.Input.Prompt(WishSource, 20))

    return (((prompt and (prompt .. "  ")) or "") .. "Wish for it")
end

-- Draws the panel for the item looked at, or says what to do before there's one.
local function Draw()
    local panel = PanelFrame()
    local item = Current

    panel.Wish.Label:SetText(WishLabel())
    panel.Icon:SetTexture((item and item.icon) or OwlIcon)
    panel.Name:SetText((item and item.name) or "The Owl's shopping help")

    if not item then
        panel.Lines:SetText("Point at something to hear what the Owl thinks of it.")
        panel.Price:SetText("")
        panel.Wish:Disable()

        return
    end

    local lines = Advice.Verdict(item, Player())

    panel.Lines:SetText(((#lines > 0) and table.concat(lines, "\n")) or "Looks fine to the Owl.")

    panel.Price:SetText((item.price and ("Wish for it: %s"):format(((Advice.Stars(item.price, ns.ScholarWishes.Worth()) == 1)
        and "1 star") or (Advice.Stars(item.price, ns.ScholarWishes.Worth()) .. " stars"))) or "")

    panel.Wish:Enable()
end

-- An item's tooltip showed: in an open shop, the Owl looks at it.
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not (Shopping and Shopping:IsRunning() and Open and data and data.id) then
        return
    end

    Current = Facts(data.id)

    if Current then
        local lines = Advice.Verdict(Current, Player())

        if lines[1] then
            tooltip:AddLine("The Owl: " .. lines[1], 1, 0.82, 0, true)
        end

        Draw()
    end
end)

Shopping = Addon:Module("Shopping", {
    active = { reads = { "Scholar.enabled" }, when = function(state) return state:Get("Scholar.enabled") end },
    commands = { { label = "Wish for the item you're looking at in a shop", name = "wish", run = Wish } },
    description = ("At a vendor or the auction house, the Owl says whether an item is worth your child's gold: whether "
        .. "they can use it, whether it's better than what they wear, whether they'll outgrow it soon, and whether it "
        .. "costs most of their gold. Wish for it adds it to their wishes instead."),
    label = "The Owl's shopping help",
    lockedBy = "Scholar.locked",
    OnDisable = Close,
    OnEnable = function(module)
        PanelFrame().Wish:SetScript("OnClick", module:Callback(Wish))

        module:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(interaction)
            if (interaction == Interaction.Merchant) or (interaction == Interaction.Auctioneer) then
                Open, Current = interaction, nil
                Draw()
                Panel:Show()
                Addon.Input:Summon(module, WishSource, "Shopping.wish")
            end
        end)

        module:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(interaction)
            if interaction == Open then
                Close()
            end
        end)
    end,
    page = "Scholar's challenge",
    scope = "character",
    section = "Wishes",
})
