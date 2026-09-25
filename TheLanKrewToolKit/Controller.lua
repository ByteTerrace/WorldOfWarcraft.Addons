local addonName, ns = ...

-- Controller light bar and rumble, ported from ByteTerrace GamePadActionBars. Blizzard's gamepad
-- UI uses neither, so nothing conflicts. Both are harmless with no controller connected.

local C_GamePad, CreateColor = C_GamePad, CreateColor

local COMBAT = CreateColor(1, 0, 0)
local AFK = CreateColor(1, 1, 0)
local NEUTRAL = CreateColor(0, 1, 0)

ns.addon:Module("LightBar", {
    label = "Controller light bar",
    description = "Color your controller's light bar by state: red in combat, yellow when AFK, green otherwise.",
    OnEnable = function(module)
        local state = module.addon.state
        local combat, afk = module:Id("combat.active"), module:Id("afk.active")
        local function Apply()
            if state.values[combat] then
                C_GamePad.SetLedColor(COMBAT)
            elseif state.values[afk] then
                C_GamePad.SetLedColor(AFK)
            else
                C_GamePad.SetLedColor(NEUTRAL)
            end
        end
        module:Watch({ combat, afk }, Apply)
        module:On("GAME_PAD_CONNECTED", Apply)
        module:On("PLAYER_LOGOUT", C_GamePad.ClearLedColor)
    end,
    OnDisable = function()
        C_GamePad.ClearLedColor()
    end,
})

ns.addon:Module("Rumble", {
    label = "Controller rumble",
    description = "Rumble your controller strongly when combat starts and lightly when it ends.",
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        module:Rule({
            reads = { combat }, when = function(s) return s.values[combat] end,
            changed = function(active)
                if active then
                    C_GamePad.SetVibration("High", 1.0)
                else
                    C_GamePad.SetVibration("Low", 0.5)
                end
            end,
        })
    end,
})
