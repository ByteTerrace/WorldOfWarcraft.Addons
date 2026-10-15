local addonName, ns = ...

-- FuckOMeter: a comically oversized energy bar across the middle of the screen, shown while the
-- player's power type is energy. /tlk fom turns the module off and on again.
--
-- The player's primary power is secret in combat and out (probed: power.player), so energy never
-- enters state: UnitPower/UnitPowerMax results go straight to the bar and text (both accept
-- secrets) and are never compared or computed with.
-- Power events are registered only while the meter is visible. The bar eases toward each new value
-- (Enum.StatusBarInterpolation.ExponentialEaseOut) in the same SetValue call: no extra work per tick.
--
-- The meter frame is the global TheLanKrewToolKitFuckOMeter: its name (Label) centered on the
-- bar, and the energy in Bar and in Value at the bar's right end.

local Ease = Enum.StatusBarInterpolation.ExponentialEaseOut
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
        insets = { bottom = 4, left = 4, right = 4, top = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:Hide()

    local bar = CreateFrame("StatusBar", nil, frame)

    bar:SetPoint("TOPLEFT", 5, -5)
    bar:SetPoint("BOTTOMRIGHT", -5, 5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local color = ((PowerBarColor and PowerBarColor.ENERGY) or { b = 0, g = 1, r = 1 })

    bar:SetStatusBarColor(color.r, color.g, color.b)
    frame.Bar = bar

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")

    label:SetPoint("CENTER")
    label:SetText("FUCK-O-METER")
    label:SetTextColor(1, 1, 1)
    frame.Label = label

    local value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")

    value:SetPoint("RIGHT", -16, 0)
    value:SetTextColor(1, 1, 1)
    frame.Value = value

    return frame
end

-- Power events carry the power token; other resources (a druid's mana) are ignored.
local function UpdateRange(_, powerToken)
    if (powerToken == nil) or (powerToken == "ENERGY") then
        Meter.Bar:SetMinMaxValues(0, UnitPowerMax("player", Energy)) -- secret: widget sink
    end
end

local function UpdateValue(_, powerToken)
    if (powerToken == nil) or (powerToken == "ENERGY") then
        local current = UnitPower("player", Energy) -- secret: widget sink

        Meter.Bar:SetValue(current, Ease)
        Meter.Value:SetText(current)
    end
end

ns.Addon:Module("FuckOMeter", {
    commands = {
        {
            always = true, label = "Toggle the fuck-o-meter", name = "toggle",
            run = function() ns.Addon.State:Toggle("FuckOMeter.enabled") end, slash = "fom",
        },
    },
    description = "Show an obnoxiously wide energy bar across the middle of the screen.",
    label = "Fuck-o-meter",
    OnDisable = function()
        Meter:Hide()
    end,
    OnEnable = function(module)
        Meter = (Meter or CreateMeter())
        local powerHandles

        local function UpdateVisibility()
            local visible = (UnitPowerType("player") == Energy)

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
})
