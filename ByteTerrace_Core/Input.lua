-- Input: a positional controller vocabulary, per-family labels, and binding maps that route
-- controller buttons to commands.
--
-- Sources are named by position ("gamepad.south"), never by printed letter, because the letter
-- depends on the controller family. Label(source) gives the printed name for the connected
-- controller: A on Xbox, Cross on PlayStation, B on Switch.
--
--   Bind(map, source, command)  before compile.
--   SetActiveMaps(maps)         activates a set of maps (several = overlay, one = modal). While any
--                               bound button is active, the capture frame takes those buttons;
--                               every other button propagates to the game untouched.
--
-- A release always goes to the command its press went to, even if the maps changed in between.
-- A held command whose map is deactivated while its button is down receives "cancel".
-- Captured input is insecure: bind commands, never protected actions.

local ByteTerrace = ByteTerrace
local Refuse = ByteTerrace.Refuse
local C_GamePad, CreateFrame, pcall = C_GamePad, CreateFrame, pcall
local ipairs, pairs = ipairs, pairs

local Input = {}
Input.__index = Input
ByteTerrace.Input = Input

-- { source, WoW key, label key }
local SOURCES = {
    { "gamepad.south", "PAD1", "south" },
    { "gamepad.east", "PAD2", "east" },
    { "gamepad.west", "PAD3", "west" },
    { "gamepad.north", "PAD4", "north" },
    { "gamepad.dpadUp", "PADDUP", "dpadUp" },
    { "gamepad.dpadDown", "PADDDOWN", "dpadDown" },
    { "gamepad.dpadLeft", "PADDLEFT", "dpadLeft" },
    { "gamepad.dpadRight", "PADDRIGHT", "dpadRight" },
    { "gamepad.leftShoulder", "PADLSHOULDER", "leftShoulder" },
    { "gamepad.rightShoulder", "PADRSHOULDER", "rightShoulder" },
    { "gamepad.leftTrigger", "PADLTRIGGER", "leftTrigger" },
    { "gamepad.rightTrigger", "PADRTRIGGER", "rightTrigger" },
    { "gamepad.leftStick", "PADLSTICK", "leftStick" },
    { "gamepad.rightStick", "PADRSTICK", "rightStick" },
    { "gamepad.back", "PADBACK", "back" },
    { "gamepad.start", "PADFORWARD", "start" },
}

local DPAD = { dpadUp = "D-pad Up", dpadDown = "D-pad Down", dpadLeft = "D-pad Left", dpadRight = "D-pad Right" }

-- Keyed by C_GamePad's labelStyle for the active device.
local LABELS = {
    Letters = { south = "A", east = "B", west = "X", north = "Y", leftShoulder = "LB", rightShoulder = "RB",
        leftTrigger = "LT", rightTrigger = "RT", leftStick = "LS", rightStick = "RS", back = "View", start = "Menu" },
    Shapes = { south = "Cross", east = "Circle", west = "Square", north = "Triangle", leftShoulder = "L1", rightShoulder = "R1",
        leftTrigger = "L2", rightTrigger = "R2", leftStick = "L3", rightStick = "R3", back = "Create", start = "Options" },
    Reverse = { south = "B", east = "A", west = "Y", north = "X", leftShoulder = "L", rightShoulder = "R",
        leftTrigger = "ZL", rightTrigger = "ZR", leftStick = "LS", rightStick = "RS", back = "-", start = "+" },
    Generic = { south = "South", east = "East", west = "West", north = "North", leftShoulder = "Left Shoulder",
        rightShoulder = "Right Shoulder", leftTrigger = "Left Trigger", rightTrigger = "Right Trigger",
        leftStick = "Left Stick", rightStick = "Right Stick", back = "Back", start = "Start" },
}

local keyOf, labelKeyOf, sourceOf = {}, {}, {}
for _, entry in ipairs(SOURCES) do
    keyOf[entry[1]], labelKeyOf[entry[1]], sourceOf[entry[2]] = entry[2], entry[3], entry[1]
end
Input.keyOf, Input.sourceOf = keyOf, sourceOf

-- The connected controller's label style, or "Generic" when none is connected.
function Input.LabelStyle()
    local ok, mapped = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID())
    local style = ok and mapped and mapped.labelStyle
    return LABELS[style] and style or "Generic"
end

function Input.Label(source, style)
    local key = labelKeyOf[source]
    if not key then
        return nil
    end
    return DPAD[key] or LABELS[style or Input.LabelStyle()][key]
end

function ByteTerrace.NewInput(addon)
    return setmetatable({
        addon = addon,
        declared = {},     -- { map, source, command } until compile
        compiled = false,
        maps = {},         -- [map] = { [key] = command id }
        active = {},       -- [key] = command id, for the active maps
        latched = {},      -- [key] = command id its press went to
        activeMaps = {},
    }, Input)
end

function Input:Bind(map, source, command)
    if self.compiled then
        error(self.addon.name .. ": binding for " .. tostring(source) .. " declared after compile", 2)
    end
    self.declared[#self.declared + 1] = { map = map, source = source, command = command }
end

function Input:Compile()
    local problems, commands = {}, self.addon.commands
    for _, binding in ipairs(self.declared) do
        local key, id = keyOf[binding.source], commands:Id(binding.command)
        if not key then
            problems[#problems + 1] = ("%s: unknown source %s"):format(binding.map, tostring(binding.source))
        end
        if not id then
            problems[#problems + 1] = ("%s: unknown command %s"):format(binding.map, tostring(binding.command))
        end
        if key and id then
            local map = self.maps[binding.map] or {}
            self.maps[binding.map] = map
            if map[key] then
                problems[#problems + 1] = ("%s: %s is bound twice"):format(binding.map, binding.source)
            end
            map[key] = id
        end
    end
    Refuse(self.addon.name .. " input", problems)
    self.declared = nil
    self.compiled = true
end

function Input:EnsureFrame()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetScript("OnGamePadButtonDown", function(_, key)
        return self:Down(key)
    end)
    frame:SetScript("OnGamePadButtonUp", function(_, key)
        return self:Up(key)
    end)
    self.frame = frame
    return frame
end

-- Returns true to let the button propagate (Blizzard's convention for gamepad button scripts).
function Input:Down(key)
    local id = self.active[key]
    if not id then
        return true
    end
    self.latched[key] = id
    self.addon.commands:Run(id, nil, "down", "gamepad")
    return false
end

function Input:Up(key)
    local id = self.latched[key]
    if not id then
        return true
    end
    self.latched[key] = nil
    self.addon.commands:Run(id, nil, "up", "gamepad")
    return false
end

function Input:SetActiveMaps(maps)
    local active, any = {}, false
    for _, name in ipairs(maps) do
        local map = self.maps[name]
        if not map then
            error(self.addon.name .. ": unknown input map " .. tostring(name), 2)
        end
        for key, id in pairs(map) do
            active[key] = id
            any = true
        end
    end
    for key, id in pairs(self.latched) do
        if active[key] ~= id then
            self.latched[key] = nil
            self.addon.commands:Run(id, nil, "cancel", "gamepad")
        end
    end
    self.active, self.activeMaps = active, maps
    if any or self.frame then
        self:EnsureFrame():EnableGamePadButton(any)
    end
end
