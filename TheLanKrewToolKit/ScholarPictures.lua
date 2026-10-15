local addonName, ns = ...

-- Scholar's pictures: riddles drawn so young players can count. ScholarView owns the frame's place
-- on the screen; this file fills it.
--
--   ns.ScholarPictures.Create(parent) -> frame   an empty picture area
--   ns.ScholarPictures.Draw(frame, picture, tiles) -> height
--     picture (from the puzzle) is { kind = "groups", groups, each } (bags of items), "join"
--     { a, b } (two piles), "take" { a, b } (a pile with b crossed out) or "count" { n }, each with
--     the item it counts ("apple"), drawn with that item's icon (a star when none is known); tiles
--     are an unscramble's letters, drawn as letter tiles instead. Returns 0 when there's nothing
--     to draw, and the frame is then hidden.
--
-- It also defines ns.ScholarStyle, the look the whole Scholar screen shares: { Palette, Solid,
-- Border, StarIcon, WrongIcon, Backdrop(frame, edgeSize), TextColor(fontString, color) }. This file
-- loads before ScholarView.lua, which reads it.

local IconSize = 20
local IconGap = 3
local TileSize = 40
local TileGap = 8
local StarIcon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local WrongIcon = "Interface\\RAIDFRAME\\ReadyCheck-NotReady"
local Solid = "Interface\\Buttons\\WHITE8X8"
local Border = "Interface\\Tooltips\\UI-Tooltip-Border"
local Palette = {
    panel = { 0.08, 0.06, 0.04 },
    band = { 0.2, 0.15, 0.09 },
    button = { 0.2, 0.15, 0.09 },
    edge = { 0.45, 0.36, 0.17 },
    keycap = { 0.34, 0.27, 0.15 },
    keycapDim = { 0.19, 0.15, 0.09 },
    gold = { 1, 0.82, 0 },
    story = { 0.88, 0.85, 0.79 },
    question = { 1, 1, 1 },
    muted = { 0.62, 0.59, 0.54 },
    streak = { 1, 0.7, 0.28 },
    math = { 0.42, 0.77, 1 },
    reading = { 0.5, 0.88, 0.48 },
    quest = { 1, 0.76, 0.3 },
    good = { 0.35, 0.95, 0.45 },
    bad = { 1, 0.4, 0.35 },
    tile = { 0.93, 0.86, 0.68 },
    ink = { 0.16, 0.11, 0.05 },
}
-- Icons for the items riddles count, by the item's name (ScholarWords.lua's items). An item not
-- listed is drawn as a star.
local ItemIcons = {
    apple = "Interface\\Icons\\INV_Misc_Food_19",
    fish = "Interface\\Icons\\INV_Misc_Fish_02",
    gem = "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
    potion = "Interface\\Icons\\INV_Potion_51",
    arrow = "Interface\\Icons\\INV_Ammo_Arrow_02",
    scroll = "Interface\\Icons\\INV_Scroll_03",
    mushroom = "Interface\\Icons\\INV_Mushroom_11",
    gear = "Interface\\Icons\\INV_Misc_Gear_01",
}

local CreateFrame = CreateFrame
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min

local ScholarPictures = {}
ns.ScholarPictures = ScholarPictures

--- Gives frame (a BackdropTemplate frame) the screen's solid backdrop with a tooltip border.
---@param frame table
---@param edgeSize number
local function Backdrop(frame, edgeSize)
    frame:SetBackdrop({ bgFile = Solid, edgeFile = Border, edgeSize = edgeSize,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
end

--- Colors fontString with a palette color, { r, g, b }.
---@param fontString table
---@param color table
local function TextColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3])
end

local function PictureIcon(pictures, index)
    local icon = pictures.Icons[index]
    if not icon then
        icon = pictures:CreateTexture(nil, "ARTWORK")
        icon:SetSize(IconSize, IconSize)
        icon.Cross = pictures:CreateTexture(nil, "OVERLAY")
        icon.Cross:SetSize(12, 12)
        icon.Cross:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
        icon.Cross:SetTexture(WrongIcon)
        pictures.Icons[index] = icon
    end
    return icon
end

local function PictureCard(pictures, index)
    local card = pictures.Cards[index]
    if not card then
        card = CreateFrame("Frame", nil, pictures, "BackdropTemplate")
        Backdrop(card, 10)
        card:SetBackdropColor(0.16, 0.12, 0.06, 1)
        card:SetBackdropBorderColor(Palette.edge[1], Palette.edge[2], Palette.edge[3])
        pictures.Cards[index] = card
    end
    return card
end

-- Places count icons in a grid of columns starting at (x, y); returns the grid's width and height.
local function Grid(pictures, first, count, columns, x, y, texture, crossedFrom)
    for n = 1, count do
        local icon = PictureIcon(pictures, first + n - 1)
        local column, row = (n - 1) % columns, floor((n - 1) / columns)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", x + column * (IconSize + IconGap), -(y + row * (IconSize + IconGap)))
        icon:SetTexture(texture)
        local crossed = crossedFrom and n >= crossedFrom
        icon:SetDesaturated(crossed and true or false)
        icon:SetAlpha(crossed and 0.4 or 1)
        icon.Cross:SetShown(crossed and true or false)
        icon:Show()
    end
    local columnsUsed, rows = min(count, columns), ceil(count / columns)
    return columnsUsed * (IconSize + IconGap) - IconGap, rows * (IconSize + IconGap) - IconGap
end

-- Lays out an unscramble's letters as tiles; returns their width and height.
local function DrawTiles(pictures, tiles)
    local x = 0
    for i, letter in ipairs(tiles) do
        local tile = pictures.Tiles[i]
        if not tile then
            tile = CreateFrame("Frame", nil, pictures, "BackdropTemplate")
            tile:SetSize(TileSize, TileSize + 4)
            Backdrop(tile, 10)
            tile:SetBackdropColor(Palette.tile[1], Palette.tile[2], Palette.tile[3], 1)
            tile:SetBackdropBorderColor(Palette.edge[1], Palette.edge[2], Palette.edge[3])
            tile.Letter = tile:CreateFontString(nil, "OVERLAY", "Game24Font")
            tile.Letter:SetPoint("CENTER", 0, 1)
            TextColor(tile.Letter, Palette.ink)
            pictures.Tiles[i] = tile
        end
        tile.Letter:SetText(letter)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", x, 0)
        tile:Show()
        x = x + TileSize + TileGap
    end
    return x - TileGap, TileSize + 4
end

--- Draws a puzzle's picture (see the header) or its tiles, and returns the height, or 0 when
--- there's nothing to draw.
---@param pictures table the frame from Create
---@param picture table?
---@param tiles table?
---@return number height
local function Draw(pictures, picture, tiles)
    for _, icon in ipairs(pictures.Icons) do
        icon:Hide()
        icon.Cross:Hide()
    end
    for _, card in ipairs(pictures.Cards) do
        card:Hide()
    end
    for _, tile in ipairs(pictures.Tiles) do
        tile:Hide()
    end
    pictures.Plus:Hide()
    if tiles then
        local width, height = DrawTiles(pictures, tiles)
        pictures:SetSize(width, height)
        pictures:Show()
        return height
    end
    if not picture then
        pictures:Hide()
        return 0
    end
    local texture, width, height = ItemIcons[picture.item] or StarIcon, 0, 0
    if picture.kind == "groups" then
        local columns = picture.each <= 6 and 3 or 5
        local gridWidth = min(picture.each, columns) * (IconSize + IconGap) - IconGap
        local cardWidth, x = gridWidth + 16, 0
        for group = 1, picture.groups do
            local card = PictureCard(pictures, group)
            local w, h = Grid(pictures, (group - 1) * picture.each + 1, picture.each, columns, x + 8, 8, texture)
            card:SetSize(w + 16, h + 16)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", x, 0)
            card:Show()
            x = x + cardWidth + 10
            height = max(height, h + 16)
        end
        width = x - 10
    elseif picture.kind == "join" then
        local w1, h1 = Grid(pictures, 1, picture.a, 5, 0, 0, texture)
        pictures.Plus:ClearAllPoints()
        pictures.Plus:SetPoint("TOPLEFT", w1 + 10, -(h1 / 2 - 12))
        pictures.Plus:Show()
        local w2, h2 = Grid(pictures, picture.a + 1, picture.b, 5, w1 + 36, 0, texture)
        width, height = w1 + 36 + w2, max(h1, h2)
    elseif picture.kind == "take" then
        width, height = Grid(pictures, 1, picture.a, 10, 0, 0, texture, picture.a - picture.b + 1)
    elseif picture.kind == "count" then
        width, height = Grid(pictures, 1, picture.n, 5, 0, 0, texture)
    end
    pictures:SetSize(max(width, 1), height)
    pictures:Show()
    return height
end

--- An empty picture area on parent.
---@param parent table
---@return table frame
function ScholarPictures.Create(parent)
    local pictures = CreateFrame("Frame", nil, parent)
    pictures.Icons, pictures.Cards, pictures.Tiles = {}, {}, {}
    pictures.Plus = pictures:CreateFontString(nil, "OVERLAY", "Game24Font")
    pictures.Plus:SetText("+")
    TextColor(pictures.Plus, Palette.gold)
    return pictures
end

ScholarPictures.Draw = Draw

ns.ScholarStyle = {
    Palette = Palette, Solid = Solid, Border = Border, StarIcon = StarIcon, WrongIcon = WrongIcon,
    Backdrop = Backdrop, TextColor = TextColor,
}
