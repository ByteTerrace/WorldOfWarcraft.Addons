-- Input: a positional controller vocabulary, per-family labels, and binding maps that route
-- controller buttons to commands.
--
-- Sources are named by position ("gamepad.south"), never by printed letter, because the letter
-- depends on the controller family. Input.Label(source) gives the printed name for the connected
-- controller: A on Xbox, Cross on PlayStation, B on Switch.
--
--   Bind(map, source, command)  before compile.
--   SetActiveMaps(maps)         activates a set of maps (several = overlay, one = modal). While any
--                               bound button is active, the capture frame takes every controller
--                               button: bound ones run their commands, the rest do nothing. The
--                               client ignores a gamepad script's return value, so capture can't
--                               pass a button on (seen in game: the d-pad never reached the game
--                               under Scholar's riddle). An active map is modal for the controller.
--
-- A release always goes to the command its press went to, even if the maps changed in between.
-- A held command whose map is deactivated while its button is down receives "cancel".
-- Captured input is insecure: bind commands, never protected actions.

-- { source, WoW key, label key }
local Sources = {
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

-- The same on every family.
local DirectionalPadLabels = { dpadUp = "D-pad Up", dpadDown = "D-pad Down", dpadLeft = "D-pad Left", dpadRight = "D-pad Right" }

-- Keyed by C_GamePad's labelStyle for the active device.
local Labels = {
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

-- [source] = WoW key and [source] = label key, from Sources.
local KeyOf, LabelKeyOf = {}, {}
for _, entry in ipairs(Sources) do
    KeyOf[entry[1]], LabelKeyOf[entry[1]] = entry[2], entry[3]
end

local ByteTerrace = ByteTerrace
local Refuse = ByteTerrace.Refuse
local C_GamePad, CreateFrame, pcall = C_GamePad, CreateFrame, pcall
local ipairs, next, pairs, tostring, type = ipairs, next, pairs, tostring, type

local Input = {}
Input.__index = Input
ByteTerrace.Input = Input

--- The connected controller's label style (a key of Labels: "Letters", "Shapes", "Reverse"), or
--- "Generic" when none is connected.
---@return string
function Input.LabelStyle()
    local ok, mapped = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID())
    local style = ok and mapped and mapped.labelStyle
    return Labels[style] and style or "Generic"
end

--- A source's printed name for a label style (default: the connected controller's).
---@param source string e.g. "gamepad.south"
---@param style string?
---@return string? label nil for an unknown source
function Input.Label(source, style)
    local key = LabelKeyOf[source]
    if not key then
        return nil
    end
    return DirectionalPadLabels[key] or Labels[style or Input.LabelStyle()][key]
end

--- Creates an addon's input router, with no bindings and no capture frame yet.
---@param addon table the owning AddOn, whose commands bindings run
function ByteTerrace.NewInput(addon)
    return setmetatable({
        m_addon = addon,
        m_declared = {},     -- { map, source, command } until compile
        m_compiled = false,
        m_maps = {},         -- [map] = { [key] = command id }
        m_active = {},       -- [key] = command id, for the active maps
        m_latched = {},      -- [key] = command id its press went to
    }, Input)
end

--- Validates a binding declaration without registering it, so modules can commit atomically.
---@param map string
---@param source string e.g. "gamepad.south"
---@param command string the command's full name, e.g. "Meter.toggle"
function Input:CheckDeclaration(map, source, command)
    if self.m_compiled then
        error(self.m_addon.Name .. ": binding for " .. tostring(source) .. " declared after compile", 2)
    end
    if type(map) ~= "string" or map == "" or type(source) ~= "string" or type(command) ~= "string" then
        error(self.m_addon.Name .. ": a binding needs a map, source and command name", 2)
    end
end

--- Binds a source to a command in a map, before compile.
---@param map string
---@param source string
---@param command string
function Input:Bind(map, source, command)
    self:CheckDeclaration(map, source, command)
    self.m_declared[#self.m_declared + 1] = { map = map, source = source, command = command }
end

--- Resolves every binding, raising all problems at once. Runs after the commands compile.
function Input:Compile()
    local problems, commands = {}, self.m_addon.Commands
    for _, binding in ipairs(self.m_declared) do
        local key, id = KeyOf[binding.source], commands.Ids[binding.command]
        if not key then
            problems[#problems + 1] = ("%s: unknown source %s"):format(binding.map, tostring(binding.source))
        end
        if not id then
            problems[#problems + 1] = ("%s: unknown command %s"):format(binding.map, tostring(binding.command))
        end
        if key and id then
            local map = self.m_maps[binding.map] or {}
            self.m_maps[binding.map] = map
            if map[key] then
                problems[#problems + 1] = ("%s: %s is bound twice"):format(binding.map, binding.source)
            end
            map[key] = id
        end
    end
    Refuse(self.m_addon.Name .. " input", problems)
    self.m_declared = nil
    self.m_compiled = true
end

--- The capture frame, created on first use. It's parentless: hiding UIParent (Alt+Z,
--- cinematics) must not hide capture.
function Input:EnsureFrame()
    if self.m_frame then
        return self.m_frame
    end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnGamePadButtonDown", function(_, key)
        self:Down(key)
    end)
    frame:SetScript("OnGamePadButtonUp", function(_, key)
        self:Up(key)
    end)
    self.m_frame = frame
    return frame
end

--- Handles a button press: a bound button runs its command; any other does nothing.
---@param key string the WoW key, e.g. "PAD1"
function Input:Down(key)
    local id = self.m_active[key]
    if not id then
        return
    end
    self.m_latched[key] = id
    self.m_addon.Commands:Run(id, nil, "down", "gamepad")
end

--- Handles a button release; it goes to the command its press went to.
---@param key string
function Input:Up(key)
    local id = self.m_latched[key]
    if not id then
        return
    end
    self.m_latched[key] = nil
    self.m_addon.Commands:Run(id, nil, "up", "gamepad")
end

--- Turns capture on while any binding is active. EnableGamePadButton is flagged protected, but
--- like Show and Hide that only restricts protected (Secure) frames; the capture frame is a
--- plain frame, so this works in combat too.
function Input:ApplyCapture()
    local wanted = next(self.m_active) ~= nil
    if wanted or self.m_frame then
        self:EnsureFrame():EnableGamePadButton(wanted)
    end
end

--- Activates exactly these maps; later maps win a source two of them bind. A held command
--- whose button stops routing to it gets "cancel", after the new maps are in place, so a cancel
--- handler that switches maps again wins. An unknown map is an error.
---@param maps string[]
function Input:SetActiveMaps(maps)
    local active = {}
    for _, name in ipairs(maps) do
        local map = self.m_maps[name]
        if not map then
            error(self.m_addon.Name .. ": unknown input map " .. tostring(name), 2)
        end
        for key, id in pairs(map) do
            active[key] = id
        end
    end
    self.m_active = active
    local canceled
    for key, id in pairs(self.m_latched) do
        if active[key] ~= id then
            canceled = canceled or {}
            canceled[#canceled + 1] = id
            self.m_latched[key] = nil
        end
    end
    self:ApplyCapture()
    if canceled then
        for _, id in ipairs(canceled) do
            self.m_addon.Commands:Run(id, nil, "cancel", "gamepad")
        end
    end
end
