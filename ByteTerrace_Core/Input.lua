-- Input: a positional controller vocabulary, per-family labels, and binding maps that route controller buttons to
-- commands.
--
-- Sources are named by position ("gamepad.south"), never by printed letter, because the letter depends on the
-- controller family. Input.Label(source) gives the printed name for the connected controller: A on Xbox, Cross on
-- PlayStation, B on Switch. Input.IsControllerUI() says whether the controller interface style is on, when an addon
-- must add nothing to Blizzard's menus. Input.Glyph(source, size) gives the button's own art, as the controller UI
-- draws it, inline in text, and Input.Prompt(source, size) gives the glyph, or the name when the client has no art for
-- the button.
--
--   Bind(map, source, command)  before compile. A map binds one module's commands (or the
--                               addon's own). Compile refuses one that mixes modules.
--   SetActiveMaps(maps)         activates exactly these maps. Later ones win a source two of them
--                               bind. While any is active, the capture frame takes every controller
--                               button: bound ones run their commands, the rest do nothing. The
--                               client ignores a controller button script's return value, so capture can't
--                               pass a button on (seen in game: the d-pad never reached the game
--                               under Scholar's riddle). Any active map is modal for the controller.
--   ActiveMaps()                the active maps' names, in order (a copy).
--   Release(module)             deactivates the maps and ends the summons of a stopping module.
--                               Module.lua calls it, so a stopped feature never keeps the
--                               controller, even when its own OnDisable fails.
--   Summon(module, source, command)  binds one button to a command without capture, so every other
--                               button stays the player's: a non-priority override binding
--                               (SetOverrideBindingClick) to the addon's summon button, which
--                               Blizzard's own priority bindings (an open panel's buttons) still
--                               win over. Only for a running module, and only out of combat
--                               lockdown: it returns false otherwise. Combat starting ends every
--                               summon, during PLAYER_REGEN_DISABLED, before lockdown (probe
--                               combat.edges). Returns whether it took. Summons of one button
--                               stack: the latest wins, and the same module and command summoned
--                               again moves back to the top. A summon runs its command on the
--                               press only: whether the client clicks on a release is unknown.
--   Dismiss(module, source, command)  ends that summon. The button goes to the summon below it,
--                               or back to the game.
--
-- A release always goes to the command its press went to, even if the maps changed in between. A held command whose map
-- is deactivated while its button is down receives "cancel". When its own press is what changed the maps, the cancel
-- comes after that press's "down" returns. Captured input is insecure: bind commands, never protected actions.

-- Each entry is { source, WoW key, label key }.
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
local DirectionalPadLabels = { dpadDown = "D-pad Down", dpadLeft = "D-pad Left", dpadRight = "D-pad Right", dpadUp = "D-pad Up" }

-- Keyed by C_GamePad's labelStyle for the active device.
local Labels = {
    Generic = { back = "Back", east = "East", leftShoulder = "Left Shoulder", leftStick = "Left Stick",
        leftTrigger = "Left Trigger", north = "North", rightShoulder = "Right Shoulder", rightStick = "Right Stick",
        rightTrigger = "Right Trigger", south = "South", start = "Start", west = "West" },
    Letters = { back = "View", east = "B", leftShoulder = "LB", leftStick = "LS", leftTrigger = "LT", north = "Y",
        rightShoulder = "RB", rightStick = "RS", rightTrigger = "RT", south = "A", start = "Menu", west = "X" },
    Reverse = { back = "-", east = "A", leftShoulder = "L", leftStick = "LS", leftTrigger = "ZL", north = "X",
        rightShoulder = "R", rightStick = "RS", rightTrigger = "ZR", south = "B", start = "+", west = "Y" },
    Shapes = { back = "Create", east = "Circle", leftShoulder = "L1", leftStick = "L3", leftTrigger = "L2",
        north = "Triangle", rightShoulder = "R1", rightStick = "R3", rightTrigger = "R2", south = "Cross",
        start = "Options", west = "Square" },
}

-- [source] = WoW key and [source] = label key, from Sources.
local KeyOf = {}
local LabelKeyOf = {}

for _, entry in ipairs(Sources) do
    KeyOf[entry[1]], LabelKeyOf[entry[1]] = entry[2], entry[3]
end

local ByteTerrace = ByteTerrace
local C_GamePad = C_GamePad
local ClearOverrideBindings = ClearOverrideBindings
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local next = next
local pairs = pairs
local pcall = pcall
local Refuse = ByteTerrace.Refuse
local SetOverrideBindingClick = SetOverrideBindingClick
local tostring = tostring
local type = type
local UnitAffectingCombat = UnitAffectingCombat
local wipe = wipe

local ApplySummons
local Input = {}

ByteTerrace.Input = Input
Input.__index = Input

-- A button press: a bound button runs its command, and any other does nothing. A cancel its own command caused by
-- changing the maps is delivered once its "down" has returned.
local function Down(self, key)
    local id = self.m_active[key]

    if not id then
        return
    end

    local commands = self.m_addon.Commands

    self.m_latched[key] = id
    self.m_pressing = key
    commands:Run(id, nil, "down", "gamepad")
    self.m_pressing = nil
    local canceled = self.m_pendingCancel

    if canceled then
        self.m_pendingCancel = nil
        commands:Run(canceled, nil, "cancel", "gamepad")
    end
end

-- The button a summon's binding clicks, created on first use and named so a binding can name it. A binding passes its
-- key as the mouse button, so one button serves every summon. It's shown but sizeless and takes no mouse, so nothing
-- but a binding reaches it. While a summon holds, it hears combat start and ends them all.
local function SummonButton(self)
    if self.m_summonButton then
        return self.m_summonButton
    end

    local button = CreateFrame("Button", self.m_addon.Name .. "Summon")

    button:EnableMouse(false)

    button:SetScript("OnClick", function(_, key)
        local stack = self.m_summons[key]
        local summon = (stack and stack[#stack])

        if summon then
            self.m_addon.Commands:Run(summon.id, nil, "down", "gamepad")
        end
    end)

    button:SetScript("OnEvent", function()
        wipe(self.m_summons)
        ApplySummons(self)
    end)

    self.m_summonButton = button

    return button
end

-- Takes the summons drop matches out of key's stack, returning whether any went.
local function Unstack(self, key, drop)
    local stack = self.m_summons[key]
    local kept = {}

    for _, summon in ipairs(stack) do
        if not drop(summon) then
            kept[#kept + 1] = summon
        end
    end

    self.m_summons[key] = (((#kept > 0) and kept) or nil)

    return (#kept < #stack)
end

-- A button release: it goes to the command its press went to.
local function Up(self, key)
    local id = self.m_latched[key]

    if not id then
        return
    end

    self.m_latched[key] = nil
    self.m_addon.Commands:Run(id, nil, "up", "gamepad")
end

-- The capture frame, created on first use. It's parentless: hiding UIParent (Alt+Z, cinematics) must not hide capture.
local function CaptureFrame(self)
    if self.m_frame then
        return self.m_frame
    end

    local frame = CreateFrame("Frame")

    frame:SetScript("OnGamePadButtonDown", function(_, key)
        Down(self, key)
    end)

    frame:SetScript("OnGamePadButtonUp", function(_, key)
        Up(self, key)
    end)

    self.m_frame = frame

    return frame
end

-- Turns capture on while any binding is active, touching the frame only when that changes. EnableGamePadButton is
-- flagged protected, but, like Show and Hide, that restricts only protected (Secure) frames. The capture frame is a
-- plain frame, so this works in combat too.
local function ApplyCapture(self)
    local wanted = (next(self.m_active) ~= nil)

    if wanted ~= self.m_capturing then
        self.m_capturing = wanted
        CaptureFrame(self):EnableGamePadButton(wanted)
    end
end

-- Sets the override bindings to the summons. Combat lockdown would block it, but by then combat's start has ended them.
function ApplySummons(self)
    if InCombatLockdown() then
        return
    end

    local button = SummonButton(self)

    ClearOverrideBindings(button)

    for key in pairs(self.m_summons) do
        SetOverrideBindingClick(button, false, key, self.m_addon.Name .. "Summon", key)
    end

    if next(self.m_summons) then
        button:RegisterEvent("PLAYER_REGEN_DISABLED")
    else
        button:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
end

--- Creates an addon's input router, with no bindings and no capture frame yet.
---@param addon table the owning AddOn, whose commands bindings run
function ByteTerrace.NewInput(addon)
    return setmetatable({
        -- Maps each key to its command id in the active maps.
        m_active = {},
        -- The active maps' names, in order.
        m_activeMaps = {},
        m_addon = addon,
        -- Whether the capture frame takes controller buttons (ApplyCapture).
        m_capturing = false,
        -- Each entry is { map, source, command }, kept until compile.
        m_declared = {},
        -- Maps each held key to the command id its press went to.
        m_latched = {},
        -- Maps each map to its { [key] = command id } table.
        m_maps = {},
        -- Maps each map to the module whose commands it binds, or false for the addon's.
        m_owners = {},
        -- The command a press's own map change canceled, to cancel once that press returns.
        m_pendingCancel = nil,
        -- The key whose press is running its command.
        m_pressing = nil,
        -- Maps each summoned key to its stack of { id, module }, the latest last.
        m_summons = {},
    }, Input)
end

--- Returns a source's button art for the connected controller's family, as the controller UI draws it, as inline text
--- markup, or nil for an unknown source or a button the client has no art for. It only reads the controller UI's icon
--- tables (Blizzard_SharedXML InputIcons), so it taints nothing.
---@param source string e.g. "gamepad.south"
---@param size number? the glyph's width and height (20 unless given)
---@return string?
function Input.Glyph(source, size)
    local key = KeyOf[source]
    -- The guarded lookup: GetNormalActiveInputIconButtonTexture errors on a button with no art.
    local textures = (key and InputIconTextureSetUtility.GetActiveInputIconButtonTextures(key))
    local atlas = (textures and textures[1])

    return ((atlas and CreateAtlasMarkup(atlas, (size or 20), (size or 20))) or nil)
end

--- Returns whether the controller interface style is on. Then Blizzard's controller UI wraps every menu and panel it
--- shows in its own binding groups, and an addon's entry in a menu (Menu.ModifyMenu, or a menu addon code opens) makes
--- that run tainted: the binding group's protected calls are blocked, and the half-built set stays in its binding
--- stack, blocking SetPreferredGamepadInteractTarget on every target change until the game freezes (taint.log, client
--- 1.60.1).
---@return boolean
function Input.IsControllerUI()
    return (C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad)
end

--- Returns a source's printed name for a label style (default: the connected controller's).
---@param source string e.g. "gamepad.south"
---@param style string? a label style; an unknown one reads as Generic
---@return string? label nil for an unknown source
function Input.Label(source, style)
    local key = LabelKeyOf[source]

    if not key then
        return nil
    end

    return (DirectionalPadLabels[key] or (Labels[style or Input.LabelStyle()] or Labels.Generic)[key])
end

--- Returns the connected controller's label style (a key of Labels: "Letters", "Shapes", or "Reverse"), or "Generic"
--- when none is connected.
---@return string
function Input.LabelStyle()
    local ok, mapped = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID())
    local style = (ok and mapped and mapped.labelStyle)

    return ((Labels[style] and style) or "Generic")
end

--- Returns how to show a source's button: its glyph, or its printed name when there's no art.
---@param source string e.g. "gamepad.south"
---@param size number? the glyph's width and height
---@return string?
function Input.Prompt(source, size)
    return (Input.Glyph(source, size) or Input.Label(source))
end

--- Returns the active maps' names, in order, as a new table, so a feature can add or remove its own map and keep the
--- rest.
---@return string[]
function Input:ActiveMaps()
    local names = {}

    for i, name in ipairs(self.m_activeMaps) do
        names[i] = name
    end

    return names
end

--- Binds a source to a command in a map, before compile. AddOn:Module checks each binding with CheckDeclaration first.
---@param map string
---@param source string
---@param command string
function Input:Bind(map, source, command)
    self.m_declared[#self.m_declared + 1] = { command = command, map = map, source = source }
end

--- Validates a binding declaration without registering it, so modules can commit atomically.
---@param map string
---@param source string e.g. "gamepad.south"
---@param command string the command's full name, e.g. "Meter.toggle"
function Input:CheckDeclaration(map, source, command)
    if (type(map) ~= "string") or (map == "") or (type(source) ~= "string") or (type(command) ~= "string") then
        error(self.m_addon.Name .. ": a binding needs a map, source and command name", 2)
    end
end

--- Resolves every binding, raising all problems at once. Runs after the commands compile.
function Input:Compile()
    local problems = {}
    local commands = self.m_addon.Commands

    for _, binding in ipairs(self.m_declared) do
        local key = KeyOf[binding.source]
        local id = commands.Ids[binding.command]

        if not key then
            problems[#problems + 1] = ("%s: unknown source %s"):format(binding.map, tostring(binding.source))
        end

        if not id then
            problems[#problems + 1] = ("%s: unknown command %s"):format(binding.map, tostring(binding.command))
        end

        if key and id then
            local map = (self.m_maps[binding.map] or {})

            self.m_maps[binding.map] = map

            if map[key] then
                problems[#problems + 1] = ("%s: %s is bound twice"):format(binding.map, binding.source)
            end

            map[key] = id
            local owner = (commands:ModuleOf(id) or false)
            local known = self.m_owners[binding.map]

            if known == nil then
                self.m_owners[binding.map] = owner
            elseif known ~= owner then
                problems[#problems + 1] = (binding.map .. ": binds commands of more than one module")
            end
        end
    end

    Refuse(self.m_addon.Name .. " input", problems)
    self.m_declared = nil
end

--- Ends a module's summon of a source to a command, if it has one. The button goes to the summon below it, or back to
--- the game.
---@param module table the module that summoned it
---@param source string e.g. "gamepad.back"
---@param command string the command's full name
function Input:Dismiss(module, source, command)
    local key = KeyOf[source]
    local id = self.m_addon.Commands.Ids[command]

    if key and self.m_summons[key]
        and Unstack(self, key, function(summon) return ((summon.module == module) and (summon.id == id)) end) then
        ApplySummons(self)
    end
end

--- Deactivates the active maps that bind a stopping module's commands, keeping the rest active.
---@param module table
function Input:Release(module)
    local kept = {}
    local dropped = false
    local dismissed = false

    if next(self.m_summons) then
        for _, key in ipairs(ByteTerrace.SortedKeys(self.m_summons)) do
            if Unstack(self, key, function(summon) return (summon.module == module) end) then
                dismissed = true
            end
        end
    end

    if dismissed then
        ApplySummons(self)
    end

    for _, name in ipairs(self.m_activeMaps) do
        if self.m_owners[name] == module then
            dropped = true
        else
            kept[#kept + 1] = name
        end
    end

    if dropped then
        self:SetActiveMaps(kept)
    end
end

--- Activates exactly these maps. Later maps win a source two of them bind. A held command whose button stops routing to
--- it gets "cancel", after the new maps are in place, so a cancel handler that switches maps again wins. An unknown map
--- is an error.
---@param maps string[]
function Input:SetActiveMaps(maps)
    local active = {}
    local names = {}

    for i, name in ipairs(maps) do
        local map = self.m_maps[name]

        if not map then
            error(self.m_addon.Name .. ": unknown input map " .. tostring(name), 2)
        end

        for key, id in pairs(map) do
            active[key] = id
        end

        names[i] = name
    end

    self.m_active, self.m_activeMaps = active, names
    local canceled

    for key, id in pairs(self.m_latched) do
        if active[key] ~= id then
            self.m_latched[key] = nil

            if key == self.m_pressing then
                self.m_pendingCancel = id
            else
                canceled = (canceled or {})
                canceled[#canceled + 1] = id
            end
        end
    end

    ApplyCapture(self)

    if canceled then
        for _, id in ipairs(canceled) do
            self.m_addon.Commands:Run(id, nil, "cancel", "gamepad")
        end
    end
end

--- Binds one controller button to a command without capturing the rest (see the header). The command is the module's
--- own and not held (a summon only presses): anything else is an error, as an unknown source or command is.
---@param module table the running module the summon belongs to
---@param source string e.g. "gamepad.back"
---@param command string the command's full name
---@return boolean took false in combat (from its first event, before lockdown) or for a module that isn't running
function Input:Summon(module, source, command)
    local commands = self.m_addon.Commands
    local key = KeyOf[source]
    local id = commands.Ids[command]

    if not key then
        error(self.m_addon.Name .. ": unknown source " .. tostring(source), 2)
    end

    if not id then
        error(self.m_addon.Name .. ": unknown command " .. tostring(command), 2)
    end

    if commands:IsHeld(id) then
        error(self.m_addon.Name .. ": a summon can't be held: " .. command, 2)
    end

    if commands:ModuleOf(id) ~= module then
        error(self.m_addon.Name .. ": " .. module.Name .. " can't summon " .. command, 2)
    end

    -- Combat ends every summon as it starts (PLAYER_REGEN_DISABLED, before lockdown), so one asked for then wouldn't
    -- last: UnitAffectingCombat is already true there.
    if InCombatLockdown() or UnitAffectingCombat("player") or not module:IsRunning() then
        return false
    end

    if self.m_summons[key] then
        Unstack(self, key, function(summon) return ((summon.module == module) and (summon.id == id)) end)
    end

    local stack = (self.m_summons[key] or {})

    stack[#stack + 1] = { id = id, module = module }
    self.m_summons[key] = stack
    ApplySummons(self)

    return true
end
