local addonName, ns = ...

-- Calibration probes about controllers: the connected device, which vibration types the client takes, what each
-- controller reports about itself, and which input events fire. Blizzard's Forever UI never calls
-- C_GamePad.SetVibration, and GamePadDocumentation gives its vibrationType only as a cstring, so the types are asked of
-- the client (Candidates).
--
--   Probes.Rumble(kind, intensity, seconds?) -> ok, error   one vibration; with seconds, stopped
--                                                           that long after (without, it plays
--                                                           until it stops by itself or StopRumble)
--   Probes.StopRumble()                                     stops any vibration
--   Probes.RumbleCandidates(say)                            plays each of Candidates for
--                                                           CandidateSeconds, CandidateGap apart,
--                                                           saying each one's name as it plays, for
--                                                           gamePad.vibration
--   Probes.NoteInputEvent(event, ...)                       DevTools.lua's listener, from load, for
--                                                           input.events
--   Probes.NoteWorldEntered()                               the first PLAYER_ENTERING_WORLD, so
--                                                           input.events can say what fired before
--
-- What a controller does when it vibrates can't be probed: /btdev rumble says what it played, and the player says what
-- they felt.

local CandidateGap = 1.5
local Candidates = { "High", "Low", "LTrigger", "RTrigger" }
local CandidateSeconds = 0.5

local InputEvents = {
    "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONFIGS_CHANGED", "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED",
    "GAME_PAD_POWER_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION",
}

-- The label styles ByteTerrace_Core/Input.lua has labels for (its Labels table).
local KnownLabelStyles = { Generic = true, Letters = true, Reverse = true, Shapes = true }

local C_GamePad = C_GamePad
local C_InputInterfaceStyle = C_InputInterfaceStyle
local C_Timer = C_Timer
local IsUsingGamepad = IsUsingGamepad
local pcall = pcall
local tostring = tostring

local Probes = ns.Probes
local EnumName = Probes.EnumName
local Fields = Probes.Fields
local Joined = Probes.Joined
local Shape = Probes.Shape

-- [event] = { payloads = { [shape] = true }, beforeWorld = whether it fired before the first PLAYER_ENTERING_WORLD }.
local Heard = {}
-- Bumped by every Rumble, so a stop scheduled for an earlier one doesn't cut a later one short.
local RumbleSerial = 0
-- The candidates' answers: [kind] = true for each SetVibration took, and what each refused said.
local Vibration = { accepted = {}, refused = {}, tried = false }
local WorldEntered = false

-- Returns the active controller's label style as a value when it's one Blizzard's UI knows, or "other" otherwise.
local function LabelStyle(state)
    local style = (((type(state) == "table") and state.labelStyle) or nil)

    if not issecretvalue(style) and (type(style) == "string") and (KnownLabelStyles[style] == true) then
        return style
    end

    return "other"
end

local function NoteWorldEntered()
    WorldEntered = true
end

-- Returns a payload value as a shape: enum values by name (interface type, power level).
local function PayloadShape(event, value)
    if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        return (EnumName(Enum.InputDeviceInterfaceType, value) or Shape(value))
    elseif event == "GAME_PAD_POWER_CHANGED" then
        return (EnumName(Enum.GamePadPowerLevel, value) or Shape(value))
    end

    return Shape(value)
end

local function NoteInputEvent(event, ...)
    local entry = Heard[event]

    if not entry then
        entry = { beforeWorld = false, payloads = {} }
        Heard[event] = entry
    end

    if not WorldEntered then
        entry.beforeWorld = true
    end

    local count = select("#", ...)

    if count == 0 then
        entry.payloads.none = true
    end

    for i = 1, count do
        entry.payloads[PayloadShape(event, (select(i, ...)))] = true
    end
end

local function StopRumble()
    RumbleSerial = (RumbleSerial + 1)
    C_GamePad.StopVibration()
end

local function Rumble(kind, intensity, seconds)
    RumbleSerial = (RumbleSerial + 1)
    local serial = RumbleSerial
    local ok, problem = pcall(C_GamePad.SetVibration, kind, intensity)

    if ok and seconds then
        C_Timer.After(seconds, function()
            if serial == RumbleSerial then
                StopRumble()
            end
        end)
    end

    return ok, problem
end

local function RumbleCandidates(say)
    local function Play(i)
        local kind = Candidates[i]
        local ok, problem = Rumble(kind, 1, CandidateSeconds)

        if ok then
            Vibration.accepted[kind] = true
            say(("%d/%d: %s"):format(i, #Candidates, kind))
        else
            Vibration.refused[kind] = true
            say(("%d/%d: %s refused: %s"):format(i, #Candidates, kind, tostring(problem)))
        end

        if i == #Candidates then
            Vibration.tried = true
        end
    end

    Play(1)

    for i = 2, #Candidates do
        C_Timer.After(((i - 1) * CandidateGap), function() Play(i) end)
    end
end

Probes.InputEvents = InputEvents
Probes.NoteInputEvent, Probes.NoteWorldEntered = NoteInputEvent, NoteWorldEntered
Probes.Rumble, Probes.RumbleCandidates, Probes.StopRumble = Rumble, RumbleCandidates, StopRumble

Probes.AddNeeds({
    rumbleTried = {
        check = function() return Vibration.tried end,
        label = "rumble tried",
        setup = function(h)
            h.labelStyle = "Letters"
            h:Slash("/btdev rumble")
            h:Advance(#Candidates * CandidateGap)
        end,
        step = 1,
        text = "/btdev rumble played its four vibrations since you logged in (a controller connected)",
    },
})

Probes.Define({
    {
        -- The connected controller's shapes: its ID, its mapped state's fields and label style, the interface style,
        -- and its power level (GetPowerLevel, Enum.GamePadPowerLevel).
        name = "gamePad.device",
        needs = { "controller" },
        run = function()
            local deviceID = C_GamePad.GetActiveDeviceID()
            local state = C_GamePad.GetDeviceMappedState(deviceID)
            local style = LabelStyle(state)

            return {
                deviceID = Shape(deviceID), fields = Fields(state), interfaceStyle = Shape(C_InputInterfaceStyle.GetCurrentStyle()),
                isKnownLabelStyle = (style ~= "other"), powerLevel = Shape(C_GamePad.GetPowerLevel(deviceID)),
                state = Shape(state), usingGamepad = Shape(IsUsingGamepad()),
            }
        end,
        version = 2,
    },
    {
        harness = "the harness doesn't fake IsGamePadFreelookEnabled or C_GamePad.IsEnabled",
        name = "gamePad.settings",
        needs = { "controller" },
        run = function()
            return { enabled = Shape(C_GamePad.IsEnabled()), freelook = Shape(IsGamePadFreelookEnabled()) }
        end,
    },
    {
        accumulates = true,
        -- What each controller probed with says about itself, merged across controllers: label styles, power levels,
        -- and the interface style each was used in, by name.
        harness = "these are your controllers' own answers: they become the input fact's cases",
        name = "gamePad.controllers",
        needs = { "controller" },
        run = function()
            local deviceID = C_GamePad.GetActiveDeviceID()

            return {
                interfaceStyles = (EnumName(Enum.InputDeviceInterfaceType, C_InputInterfaceStyle.GetCurrentStyle()) or "other"),
                labelStyles = LabelStyle(C_GamePad.GetDeviceMappedState(deviceID)),
                powerLevels = (EnumName(Enum.GamePadPowerLevel, C_GamePad.GetPowerLevel(deviceID)) or "other"),
            }
        end,
    },
    {
        -- Which of Candidates C_GamePad.SetVibration took (accepted) and which raised an error (refused), from /btdev
        -- rumble's run.
        name = "gamePad.vibration",
        needs = { "rumbleTried" },
        run = function()
            return {
                accepted = ((next(Vibration.accepted) and Joined(Vibration.accepted)) or "none"),
                refused = ((next(Vibration.refused) and Joined(Vibration.refused)) or "none"),
            }
        end,
    },
    {
        accumulates = true,
        -- The controller and interface events heard since load (DevTools.lua listens), each with its payloads' shapes
        -- (enum values by name) and whether it fired before the first PLAYER_ENTERING_WORLD: which ones the input fact
        -- can rely on at login.
        harness = "which events fire depends on what you did with your controllers",
        name = "input.events",
        needs = { "controller" },
        run = function()
            local result = { heard = "none" }
            local names = {}

            for event, entry in pairs(Heard) do
                names[event] = true
                result[event] = { beforeWorld = entry.beforeWorld, payloads = Joined(entry.payloads) }
            end

            if next(names) then
                result.heard = Joined(names)
            end

            return result
        end,
    },
})
