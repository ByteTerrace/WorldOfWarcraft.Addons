local addonName, ns = ...

-- WarbandBadges: a raid-target icon above the nameplate of anyone with a standing in the Krew
-- (skull: marked for death, cross: grudge, square: guild at war, star: champion). The ledger is
-- shared, so every Krew member sees the same badges. Addons can't set real raid icons in this
-- client; a badge is our own texture on the plate, visible only to you.
--
-- One badge frame per nameplate frame, parented to it, so it hides and recycles with the plate;
-- its texture is badge.Icon. Badges refresh when a plate appears and when the ledger or the wars
-- change; nothing polls. A plate that appears is read once, by Warband.lua, which hands the info
-- to Warband.OnPlate while this module runs.

local BadgeSize = 24
local MaxNameplates = 40 -- nameplate1 to nameplate40

local C_NamePlate, CreateFrame, UnitExists = C_NamePlate, CreateFrame, UnitExists

local Addon = ns.Addon
local Warband = ns.Warband

local Badges = {} -- [nameplate frame] = badge frame
local Shown = {}  -- [unit token] = the plate it showed on, for plates on screen

local function BadgeFor(plate)
    local badge = Badges[plate]
    if not badge then
        badge = CreateFrame("Frame", nil, plate)
        badge:SetSize(BadgeSize, BadgeSize)
        badge:SetPoint("BOTTOM", plate, "TOP", 0, 2)
        badge.Icon = badge:CreateTexture(nil, "OVERLAY")
        badge.Icon:SetAllPoints(badge)
        Badges[plate] = badge
    end
    return badge
end

-- Shows or hides the badge for one nameplate unit; info is what Warband.Identify read from it.
local function Show(unit, info)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then
        return -- a plate addons can't touch (friendly plates in instances)
    end
    Shown[unit] = plate
    local status = info and Warband.Status(info.key, info.guild)
    if status then
        local badge = BadgeFor(plate)
        badge.Icon:SetTexture(Warband.Icons[status])
        badge:Show()
    elseif Badges[plate] then
        Badges[plate]:Hide()
    end
end

local function Refresh(unit)
    Show(unit, Warband.Identify(unit))
end

local function RefreshAll()
    for unit in pairs(Shown) do
        Refresh(unit)
    end
end

local function HideAll()
    for _, badge in pairs(Badges) do
        badge:Hide()
    end
    wipe(Shown)
end

Addon:Module("Badges", {
    label = "Nameplate badges",
    page = "Warband",
    description = "A skull, cross, square or star above the nameplates of marked, grudge, guild-at-war and champion players. Needs enemy nameplates on.",
    active = { reads = { "Warband.enabled" }, when = function(state) return state:Get("Warband.enabled") end },
    OnEnable = function(module)
        Warband.OnPlate = Show
        -- The plate the unit showed on: nameplate addons find GetNamePlateForUnit can already
        -- answer nil while the removal dispatches.
        module:On("NAME_PLATE_UNIT_REMOVED", function(unit)
            local plate = Shown[unit] or C_NamePlate.GetNamePlateForUnit(unit)
            Shown[unit] = nil
            if plate and Badges[plate] then
                Badges[plate]:Hide()
            end
        end)
        module:Watch({ "Warband.ledger", "Warband.wars" }, RefreshAll, true)
        for i = 1, MaxNameplates do -- plates already on screen (a /reload, or switched back on)
            local unit = "nameplate" .. i
            if UnitExists(unit) then
                Refresh(unit)
            end
        end
    end,
    OnDisable = function()
        Warband.OnPlate = nil
        HideAll()
    end,
})
