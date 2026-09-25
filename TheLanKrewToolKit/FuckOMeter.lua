local addonName, ns = ...

-- A comically oversized energy bar across the middle of the screen.
--
-- Energy is a secret value in combat, so it never enters state: UnitPower/UnitPowerMax results
-- go straight to the bar and text (both accept secrets) and are never compared or computed with.
-- Power events are registered only while the meter is visible.

local ENERGY = Enum.PowerType.Energy
local HEIGHT = 64
local SIDE_INSET = 24
local CreateFrame, UnitPower, UnitPowerMax, UnitPowerType = CreateFrame, UnitPower, UnitPowerMax, UnitPowerType

local meter

local function CreateMeter()
    local frame = CreateFrame("Frame", addonName .. "FuckOMeter", UIParent, "BackdropTemplate")
    frame:SetPoint("LEFT", UIParent, "LEFT", SIDE_INSET, 0)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -SIDE_INSET, 0)
    frame:SetHeight(HEIGHT)
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
    frame.bar = bar

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    label:SetPoint("LEFT", 16, 0)
    label:SetText("FUCK-O-METER")
    label:SetTextColor(1, 1, 1)

    local value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    value:SetPoint("RIGHT", -16, 0)
    value:SetTextColor(1, 1, 1)
    frame.value = value

    return frame
end

local function UpdateRange()
    meter.bar:SetMinMaxValues(0, UnitPowerMax("player", ENERGY)) -- secret: widget sink
end

local function UpdateValue(_, powerToken)
    if powerToken == nil or powerToken == "ENERGY" then
        local current = UnitPower("player", ENERGY) -- secret: widget sink
        meter.bar:SetValue(current)
        meter.value:SetText(current)
    end
end

ns.addon:Module("FuckOMeter", {
    label = "Fuck-o-meter",
    description = "Show an obnoxiously wide energy bar across the middle of the screen.",
    commands = {
        {
            name = "toggle", slash = "fom", label = "Toggle the fuck-o-meter",
            run = function() ns.addon.state:Toggle("FuckOMeter.enabled") end,
        },
    },
    OnEnable = function(module)
        meter = meter or CreateMeter()
        local powerHandles

        local function UpdateVisibility()
            local visible = UnitPowerType("player") == ENERGY
            if visible and not powerHandles then
                powerHandles = {
                    module:On("UNIT_MAXPOWER", UpdateRange, "player"),
                    module:On("UNIT_POWER_FREQUENT", UpdateValue, "player"),
                }
                UpdateRange()
                UpdateValue()
                meter:Show()
            elseif not visible and powerHandles then
                module:Off(powerHandles[1])
                module:Off(powerHandles[2])
                powerHandles = nil
                meter:Hide()
            end
        end

        module:On("PLAYER_ENTERING_WORLD", UpdateVisibility)
        module:On("UNIT_DISPLAYPOWER", UpdateVisibility, "player")
        UpdateVisibility()
    end,
    OnDisable = function()
        meter:Hide()
    end,
})
