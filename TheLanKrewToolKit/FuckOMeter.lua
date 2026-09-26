local addonName, ns = ...

-- FuckOMeter: a comically oversized energy bar across the middle of the screen, shown while the
-- player's power type is energy. /tlk fom turns the module off and on again.
--
-- Energy is a secret value in combat, so it never enters state: UnitPower/UnitPowerMax results
-- go straight to the bar and text (both accept secrets) and are never compared or computed with.
-- Power events are registered only while the meter is visible.
--
-- The meter frame is the global TheLanKrewToolKitFuckOMeter; its Bar and Value regions hold the
-- energy.

local Energy = Enum.PowerType.Energy
local Height = 64
local SideInset = 24

local CreateFrame, UnitPower, UnitPowerMax, UnitPowerType = CreateFrame, UnitPower, UnitPowerMax, UnitPowerType

local Meter

local function CreateMeter()
    local frame = CreateFrame("Frame", addonName .. "FuckOMeter", UIParent, "BackdropTemplate")
    frame:SetPoint("LEFT", UIParent, "LEFT", SideInset, 0)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -SideInset, 0)
    frame:SetHeight(Height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:Hide()

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", 5, -5)
    bar:SetPoint("BOTTOMRIGHT", -5, 5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local color = PowerBarColor and PowerBarColor.ENERGY or { r = 1, g = 1, b = 0 }
    bar:SetStatusBarColor(color.r, color.g, color.b)
    frame.Bar = bar

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    label:SetPoint("LEFT", 16, 0)
    label:SetText("FUCK-O-METER")
    label:SetTextColor(1, 1, 1)

    local value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    value:SetPoint("RIGHT", -16, 0)
    value:SetTextColor(1, 1, 1)
    frame.Value = value

    return frame
end

-- Power events carry the power token; other resources (a druid's mana) are ignored.
local function UpdateRange(_, powerToken)
    if powerToken == nil or powerToken == "ENERGY" then
        Meter.Bar:SetMinMaxValues(0, UnitPowerMax("player", Energy)) -- secret: widget sink
    end
end

local function UpdateValue(_, powerToken)
    if powerToken == nil or powerToken == "ENERGY" then
        local current = UnitPower("player", Energy) -- secret: widget sink
        Meter.Bar:SetValue(current)
        Meter.Value:SetText(current)
    end
end

ns.Addon:Module("FuckOMeter", {
    label = "Fuck-o-meter",
    description = "Show an obnoxiously wide energy bar across the middle of the screen.",
    commands = {
        {
            name = "toggle", slash = "fom", label = "Toggle the fuck-o-meter", always = true,
            run = function() ns.Addon.State:Toggle("FuckOMeter.enabled") end,
        },
    },
    OnEnable = function(module)
        Meter = Meter or CreateMeter()
        local powerHandles

        local function UpdateVisibility()
            local visible = UnitPowerType("player") == Energy
            if visible and not powerHandles then
                powerHandles = {
                    module:On("UNIT_MAXPOWER", UpdateRange, "player"),
                    module:On("UNIT_POWER_FREQUENT", UpdateValue, "player"),
                }
                UpdateRange()
                UpdateValue()
                Meter:Show()
            elseif not visible and powerHandles then
                module:Off(powerHandles[1])
                module:Off(powerHandles[2])
                powerHandles = nil
                Meter:Hide()
            end
        end

        -- After a loading screen, a visible meter re-reads range and value too.
        module:On("PLAYER_ENTERING_WORLD", function()
            UpdateVisibility()
            if powerHandles then
                UpdateRange()
                UpdateValue()
            end
        end)
        module:On("UNIT_DISPLAYPOWER", UpdateVisibility, "player")
        UpdateVisibility()
    end,
    OnDisable = function()
        Meter:Hide()
    end,
})
