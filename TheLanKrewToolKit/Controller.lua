local addonName, ns = ...

-- Controller light bar and rumble, as two modules on the Controller settings page:
--
--   LightBar     colors the light bar by combat.active and afk.active: red, yellow, else green.
--                Cleared when the module stops and at logout.
--   Rumble       vibrates strongly when combat starts and lightly when it ends.
--   QuestFlash   turns the light bar gold for FlashSeconds when a quest is ready to turn in
--                (QuestProgress.lua), while LightBar.questReady is on. Combat's red wins over it.
--   QuestRumble  rumbles lightly when a quest is ready, while Rumble.questReady is on.
--
-- Blizzard's controller UI uses neither, so nothing conflicts. Both are harmless with no controller connected.

local C_GamePad = C_GamePad
local CreateColor = CreateColor

local AFKColor = CreateColor(1, 1, 0)
local CombatColor = CreateColor(1, 0, 0)
-- How long, in seconds, the light bar stays gold for a quest that's ready.
local FlashSeconds = 3
local NeutralColor = CreateColor(0, 1, 0)
local QuestColor = CreateColor(1, 0.82, 0)

ns.Addon:Module("LightBar", {
    description = "Color your controller's light bar by state: red in combat, yellow when AFK, green otherwise.",
    label = "Controller light bar",
    OnDisable = function()
        C_GamePad.ClearLedColor()
    end,
    OnEnable = function(module)
        local state = module.Addon.State
        local combat = module:Id("combat.active")
        local afk = module:Id("afk.active")
        local quest = module:Id("QuestFlash.on")

        local function Apply()
            if state.Values[combat] then
                C_GamePad.SetLedColor(CombatColor)
            elseif state.Values[quest] then
                C_GamePad.SetLedColor(QuestColor)
            elseif state.Values[afk] then
                C_GamePad.SetLedColor(AFKColor)
            else
                C_GamePad.SetLedColor(NeutralColor)
            end
        end

        module:Watch({ combat, afk, quest }, Apply)
        module:On("GAME_PAD_CONNECTED", Apply)
        module:On("PLAYER_LOGOUT", C_GamePad.ClearLedColor)
    end,
    page = "Controller",
    state = {
        { default = true, description = "Turn the light bar gold for a moment when one of your quests is ready to turn in.",
            kind = "boolean", label = "Flash gold when a quest is ready", name = "questReady" },
    },
})

ns.Addon:Module("Rumble", {
    description = "Rumble your controller strongly when combat starts and lightly when it ends.",
    label = "Controller rumble",
    OnDisable = function()
        C_GamePad.StopVibration()
    end,
    OnEnable = function(module)
        module:On("PLAYER_LOGOUT", C_GamePad.StopVibration)
        local combat = module:Id("combat.active")

        module:Rule({
            changed = function(active)
                if active then
                    C_GamePad.SetVibration("High", 1.0)
                else
                    C_GamePad.SetVibration("Low", 0.5)
                end
            end,
            reads = { combat }, when = function(state) return state.Values[combat] end,
        })
    end,
    page = "Controller",
    state = {
        { default = true, description = "Rumble lightly when one of your quests is ready to turn in.", kind = "boolean",
            label = "Rumble when a quest is ready", name = "questReady" },
    },
})

ns.Addon:Module("QuestFlash", {
    active = {
        reads = { "LightBar.enabled", "LightBar.questReady" },
        when = function(state) return (state:Get("LightBar.enabled") and state:Get("LightBar.questReady")) end,
    },
    OnEnable = function(module)
        local timer = nil

        module:OnIncrease("QuestProgress.ready", function()
            if timer then
                module:Cancel(timer)
            end

            module:Set("on", true)

            timer = module:After(FlashSeconds, function()
                timer = nil
                module:Set("on", false)
            end)
        end)
    end,
    state = { { default = false, kind = "boolean", name = "on", persist = false } },
    toggle = false,
    uses = { "QuestProgress" },
})

ns.Addon:Module("QuestRumble", {
    active = {
        reads = { "Rumble.enabled", "Rumble.questReady" },
        when = function(state) return (state:Get("Rumble.enabled") and state:Get("Rumble.questReady")) end,
    },
    OnEnable = function(module)
        module:OnIncrease("QuestProgress.ready", function() C_GamePad.SetVibration("Low", 0.5) end)
    end,
    toggle = false,
    uses = { "QuestProgress" },
})
