local addonName, ns = ...

-- WarbandBadges: a raid-target icon above the nameplate of anyone with a standing in the Krew (skull: marked for death,
-- cross: grudge, square: guild at war, star: champion). The ledger is shared, so every Krew member sees the same
-- badges. Addons can't set real raid icons in this client; a badge is our own texture on the plate, visible only to
-- you.
--
-- One badge frame per nameplate frame, parented to it, so it hides and recycles with the plate; its texture is
-- badge.Icon. Badges refresh when a plate appears and when the ledger or the wars change; nothing polls. A plate that
-- appears is read once, by Warband.lua, which hands the info to Warband.OnPlate while this module runs; a ledger or war
-- change repaints from those readings. A plate without a readable player (a creature) wears no badge and costs nothing.

local BadgeSize = 24
-- Nameplate unit tokens run from nameplate1 to nameplate40.
local MaxNameplates = 40

local C_NamePlate = C_NamePlate
local CreateFrame = CreateFrame
local UnitExists = UnitExists

local Addon = ns.Addon
local Warband = ns.Warband

-- Maps each nameplate frame to its badge frame.
local Badges = {}
-- Maps each unit token to the plate it showed on, for player plates on screen.
local Shown = {}
-- Maps each unit token to that plate's info, as Warband read it when the plate appeared.
local Who = {}

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

local function HideAll()
    for _, badge in pairs(Badges) do
        badge:Hide()
    end

    wipe(Shown)
    wipe(Who)
end

-- Shows or hides a plate's badge for the standing of the player info names.
local function Paint(plate, info)
    local status = Warband.Status(info.key, info.guild)

    if status then
        local badge = BadgeFor(plate)

        badge.Icon:SetTexture(Warband.Icons[status])
        badge:Show()
    elseif Badges[plate] then
        Badges[plate]:Hide()
    end
end

local function RefreshAll()
    for unit, plate in pairs(Shown) do
        Paint(plate, Who[unit])
    end
end

-- A nameplate appeared; info is what Warband.Identify read from it (nil for no readable player).
local function Show(unit, info)
    if not info then
        return
    end

    local plate = C_NamePlate.GetNamePlateForUnit(unit)

    if not plate then
        -- Addons get no plate frame for some units (friendly plates in instances).
        return
    end

    Shown[unit], Who[unit] = plate, info
    Paint(plate, info)
end

Addon:Module("Badges", {
    active = { reads = { "Warband.enabled" }, when = function(state) return state:Get("Warband.enabled") end },
    description = "A skull, cross, square or star above the nameplates of marked, grudge, guild-at-war and champion players. Needs enemy nameplates on.",
    label = "Nameplate badges",
    OnDisable = function()
        Warband.OnPlate = nil
        HideAll()
    end,
    OnEnable = function(module)
        Warband.OnPlate = Show

        -- The plate the unit showed on, kept since: nameplate addons find GetNamePlateForUnit can already answer nil
        -- while the removal dispatches. Only those plates can wear a badge.
        module:On("NAME_PLATE_UNIT_REMOVED", function(unit)
            local plate = Shown[unit]

            Shown[unit], Who[unit] = nil, nil

            if plate and Badges[plate] then
                Badges[plate]:Hide()
            end
        end)

        module:Watch({ "Warband.ledger", "Warband.wars" }, RefreshAll, true)

        -- Badge the plates already on screen, after a /reload or when switched back on.
        for i = 1, MaxNameplates do
            local unit = ("nameplate" .. i)

            if UnitExists(unit) then
                Show(unit, Warband.Identify(unit))
            end
        end
    end,
    page = "Warband",
})
