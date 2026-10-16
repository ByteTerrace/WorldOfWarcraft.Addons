local addonName, ns = ...

-- ScholarLater: putting a riddle off, so a fight, a chat, or a friend never has to wait for one. Later (L, the Later
-- tab, or D-pad left) sets the Scholar module's collapsed row, and Scholar.lua's rules put the riddle away while it's
-- set and keep it from showing. While it waits, a pill at the top of the screen says so: clicking it, D-pad left (a
-- summon, out of combat, so every other button stays the player's), or /tlk puzzle opens it again. In "Solve to keep
-- playing" a riddle put off comes back by itself after ReturnSeconds, once no fight is on. In Gentle mode it waits to
-- be opened. It's the same riddle either way, still due, and each one put off counts in laterCount for the parent's
-- report. The rows are the Scholar module's (ScholarSettings.lua).
--
-- Start opens the controller UI's radial menu, and the riddle steps aside then too, as it does for Esc. It hears
-- EventRegistry's Gamepad.ShowMainMenu, which the radial fires last as it shows, behind securecallfunction, so the
-- callback can't taint the radial (Blizzard_SharedXMLBase CallbackRegistry.lua). It only sets rows: it never touches
-- the radial itself.
--
--   ns.ScholarLater.Commands       later and reopen, for the Scholar module's spec
--   ns.ScholarLater.Start(module)  its watchers, from the Scholar module's OnEnable
--   ns.ScholarLater.Stop()         hides the pill, from the Scholar module's OnDisable

-- The controller button that opens a riddle put off: the one Later uses on the riddle screen.
local ReopenSource = "gamepad.dpadLeft"
-- How long a riddle put off waits in "Solve to keep playing" before it comes back by itself.
local ReturnSeconds = 60
-- The controller button that opens the wishes window while a riddle waits, as it does on the riddle screen.
local WishesSource = "gamepad.dpadRight"

local CreateFrame = CreateFrame
local UIParent = UIParent

local Addon = ns.Addon
-- The pill saying a riddle waits, made the first time one is put off.
local Pill = nil
-- What the radial menu's callback is registered under.
local RadialOwner = {}

-- The pill, made once, at the top of the screen.
local function PillFrame()
    if not Pill then
        Pill = CreateFrame("Button", addonName .. "ScholarPill", UIParent, "BackdropTemplate")

        -- Never focused by the controller UI's SmartNavigation (it covers every child): focus on an addon's control
        -- carries its taint into what the controller UI remembers, which blocks SetPreferredGamepadInteractTarget and
        -- can freeze the game (docs/ControllerSupport.md). Its controller input is summons (Input:Summon) instead.
        Pill.smartNavigationIgnored = true
        Pill:SetSize(300, 34)
        Pill:SetPoint("TOP", 0, -110)
        ns.ScholarStyle.Backdrop(Pill, 12)
        ns.ScholarStyle.BackdropColors(Pill, ns.ScholarStyle.Palette.panel, ns.ScholarStyle.Palette.gold)
        Pill.Icon = Pill:CreateTexture(nil, "ARTWORK")
        Pill.Icon:SetSize(24, 24)
        Pill.Icon:SetPoint("LEFT", 6, 0)
        Pill.Icon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Owl")
        Pill.Label = Pill:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Pill.Label:SetPoint("LEFT", Pill.Icon, "RIGHT", 8, 0)
        Pill:Hide()
    end

    return Pill
end

-- What the pill says: with a controller connected, the glyph of the button that opens the riddle, as the controller UI
-- draws it.
local function PillText()
    if ByteTerrace.Input.LabelStyle() ~= "Generic" then
        return (ByteTerrace.Input.Prompt(ReopenSource, 26) .. "  The Owl's riddle is waiting!    "
            .. ByteTerrace.Input.Prompt(WishesSource, 26) .. "  Wishes")
    end

    return "The Owl's riddle is waiting. Click to answer!"
end

-- The Scholar module, which Scholar.lua declares after this file loads.
local function Scholar()
    return Addon.Modules.Scholar
end

-- Puts the riddle on screen off, unless it's celebrating a right answer.
local function Later()
    local scholar = Scholar()

    if ns.ScholarView.IsShown() and not scholar:Get("solved") and not scholar:Get("collapsed") then
        scholar:Set("laterCount", scholar:Get("laterCount") + 1)
        scholar:Set("collapsed", true)
    end
end

-- Opens the riddle put off again (when no fight is on: Scholar.lua's rules wait for that).
local function Reopen()
    Scholar():Set("collapsed", false)
end

local function Start(module)
    local combat = module:Id("combat.active")
    local collapsed = module:Id("collapsed")
    local back = nil

    PillFrame():SetScript("OnClick", module:Callback(Reopen))
    EventRegistry:RegisterCallback("Gamepad.ShowMainMenu", function() Later() end, RadialOwner)

    -- The pill shows while a riddle waits, and in "Solve to keep playing" a timer brings it back.
    module:Watch({ collapsed }, function(state)
        module:Cancel(back)
        back = nil
        PillFrame().Label:SetText(PillText())
        -- The icon, its gaps, and the label: the pill fits what it says.
        -- secret: the label is built from fixed words and controller glyphs, so it holds no secret aspect
        Pill:SetWidth(Pill.Label:GetStringWidth() + 46)
        Pill:SetShown(state.Values[collapsed])

        if state.Values[collapsed] and (module:Get("style") == "gate") then
            back = module:After(ReturnSeconds, Reopen)
        end
    end, true)

    -- D-pad left opens it while it waits and no fight is on. A fight ends the summon, and this takes it up again after.
    module:Watch({ collapsed, combat }, function(state)
        if state.Values[collapsed] and not state.Values[combat] then
            Addon.Input:Summon(module, ReopenSource, "Scholar.reopen")
            Addon.Input:Summon(module, WishesSource, "Scholar.pillWishes")
        else
            Addon.Input:Dismiss(module, ReopenSource, "Scholar.reopen")
            Addon.Input:Dismiss(module, WishesSource, "Scholar.pillWishes")
        end
    end, true)
end

local function Stop()
    EventRegistry:UnregisterCallback("Gamepad.ShowMainMenu", RadialOwner)

    if Pill then
        Pill:Hide()
    end
end

ns.ScholarLater = {
    Commands = {
        { label = "Put the riddle off for later", name = "later", run = Later },
        { label = "Open the riddle put off for later", name = "reopen", run = Reopen },
        -- Its own command, so the riddle closing never dismisses the pill's D-pad right (Input:Dismiss ends one
        -- summon).
        { label = "Open the wishes window while a riddle waits", name = "pillWishes", run = function() ns.ScholarWishes.Open() end },
    },
    Start = Start,
    Stop = Stop,
}
