local addonName, ns = ...

-- Controller light bar and rumble, as two modules on the Controller settings page:
--
--   LightBar   colors the light bar by combat.active and afk.active: red, yellow, else green.
--              Cleared when the module stops and at logout.
--   Rumble     vibrates strongly when combat starts and lightly when it ends.
--
-- Blizzard's gamepad UI uses neither, so nothing conflicts. Both are harmless with no controller
-- connected.

local C_GamePad, CreateColor = C_GamePad, CreateColor

local CombatColor = CreateColor(1, 0, 0)
local AFKColor = CreateColor(1, 1, 0)
local NeutralColor = CreateColor(0, 1, 0)

ns.Addon:Module("LightBar", {
    label = "Controller light bar",
    page = "Controller",
    description = "Color your controller's light bar by state: red in combat, yellow when AFK, green otherwise.",
    OnEnable = function(module)
        local state = module.Addon.State
        local combat, afk = module:Id("combat.active"), module:Id("afk.active")
        local function Apply()
            if state.Values[combat] then
                C_GamePad.SetLedColor(CombatColor)
            elseif state.Values[afk] then
                C_GamePad.SetLedColor(AFKColor)
            else
                C_GamePad.SetLedColor(NeutralColor)
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

ns.Addon:Module("Rumble", {
    label = "Controller rumble",
    page = "Controller",
    description = "Rumble your controller strongly when combat starts and lightly when it ends.",
    OnEnable = function(module)
        module:On("PLAYER_LOGOUT", C_GamePad.StopVibration)
        local combat = module:Id("combat.active")
        module:Rule({
            reads = { combat }, when = function(state) return state.Values[combat] end,
            changed = function(active)
                if active then
                    C_GamePad.SetVibration("High", 1.0)
                else
                    C_GamePad.SetVibration("Low", 0.5)
                end
            end,
        })
    end,
    OnDisable = function()
        C_GamePad.StopVibration()
    end,
})
