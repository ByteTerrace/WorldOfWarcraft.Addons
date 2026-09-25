-- Commands: named intents. A command is declared once and every driver runs the same
-- definition: slash text, key bindings, controller buttons (Input.lua) and UI controls.
--
--   Define(spec)  before compile. spec: name (unique), label, run(arg, phase, source),
--                 slash (the lowercase word after the slash command; "" for a bare slash command),
--                 held (true to also receive "up" and "cancel" phases).
--   Id(name)      the command's id; unknown names are an error.
--   Run(ref, arg, phase, source)
--                 ref is an id (hot path) or a name. phase defaults to "down"; a command that
--                 isn't held ignores other phases. Each run is one state batch, so a command that
--                 writes several rows publishes once. Returns false for an unknown command or a
--                 run that errored (the error reaches the error handler; the caller continues).
--
-- After compile, Ids maps each name to its id (Input.lua resolves bindings through it).
--
-- Commands are insecure: they can drive the addon's own UI and state, never protected actions
-- (casting, targeting), which WoW only allows from secure templates and bindings.

local ByteTerrace = ByteTerrace
local Refuse, SafeCall, SortedKeys = ByteTerrace.Refuse, ByteTerrace.SafeCall, ByteTerrace.SortedKeys
local ipairs, print, strtrim, tostring, type = ipairs, print, strtrim, tostring, type

local Commands = {}
Commands.__index = Commands
ByteTerrace.Commands = Commands

--- Creates an addon's command table, empty and uncompiled.
---@param addon table the owning AddOn
function ByteTerrace.NewCommands(addon)
    return setmetatable({ m_addon = addon, m_declared = {}, m_compiled = false }, Commands)
end

--- Declares a command before compile. The spec isn't copied; don't change it afterwards.
---@param spec table see the file header
function Commands:Define(spec)
    if self.m_compiled then
        error(self.m_addon.Name .. ": command " .. tostring(spec.name) .. " defined after compile", 2)
    end
    if self.m_declared[spec.name] then
        error(self.m_addon.Name .. ": duplicate command " .. tostring(spec.name), 2)
    end
    self.m_declared[spec.name] = spec
end

--- Assigns ids and validates every command, raising all problems at once.
function Commands:Compile()
    local problems = {}
    local names = SortedKeys(self.m_declared)
    local ids, specs, bySlash = {}, {}, {}
    for id, name in ipairs(names) do
        local spec = self.m_declared[name]
        ids[name], specs[id] = id, spec
        if type(spec.run) ~= "function" then
            problems[#problems + 1] = name .. ": run must be a function"
        end
        if not spec.label then
            problems[#problems + 1] = name .. ": needs a label"
        end
        local word = spec.slash
        if word then
            if word ~= word:lower() or word:find("%s") then
                problems[#problems + 1] = name .. ": slash word '" .. word .. "' must be lowercase with no spaces"
            elseif bySlash[word] then
                problems[#problems + 1] = name .. ": slash word '" .. word .. "' is taken by " .. names[bySlash[word]]
            end
            bySlash[word] = id
        end
    end
    Refuse(self.m_addon.Name .. " commands", problems)
    self.Ids, self.m_specs, self.m_bySlash = ids, specs, bySlash
    self.m_declared = nil
    self.m_compiled = true
end

--- A command's id. An unknown name is an error.
---@param name string
---@return integer
function Commands:Id(name)
    local id = self.Ids[name]
    if not id then
        error(self.m_addon.Name .. ": unknown command " .. tostring(name), 2)
    end
    return id
end

--- Runs a command as one state batch.
---@param ref integer|string
---@param arg string? the slash text after the command's word
---@param phase string? "down" (default), "up" or "cancel"; only held commands get the last two
---@param source string? what ran it, e.g. "slash" or "gamepad"
---@return boolean ok false for an unknown command or a run that errored
function Commands:Run(ref, arg, phase, source)
    local id = type(ref) == "number" and ref or self.Ids[ref]
    local spec = id and self.m_specs[id]
    if not spec then
        return false
    end
    phase = phase or "down"
    if phase ~= "down" and not spec.held then
        return true
    end
    local state = self.m_addon.State
    state:BeginBatch()
    local ok = SafeCall(spec.run, arg, phase, source)
    state:EndBatch()
    return ok
end

--- The slash driver: "<word> <rest>" runs the command whose slash word matches, with rest as arg.
---@param input string? the text after the slash command
---@return boolean ok
function Commands:Slash(input)
    local text = strtrim(input or "")
    local word, rest = text:match("^(%S*)%s*(.-)$")
    word = word:lower()
    local id = self.m_bySlash[word]
    if not id then
        self.m_addon:Print("Unknown command '" .. word .. "'. Type " .. self.m_addon.Slash[1] .. " help.")
        return false
    end
    return self:Run(id, rest ~= "" and rest or nil, "down", "slash")
end

--- Prints every slash command with its label, sorted by word.
function Commands:PrintHelp()
    local addon = self.m_addon
    addon:Print("Commands:")
    for _, word in ipairs(SortedKeys(self.m_bySlash)) do
        local spec = self.m_specs[self.m_bySlash[word]]
        print(("  %s%s - %s"):format(addon.Slash[1], word ~= "" and (" " .. word) or "", spec.label))
    end
end
