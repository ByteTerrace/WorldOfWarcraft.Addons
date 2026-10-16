-- Commands: named intents. A command is declared once and every driver runs the same definition: slash text, key
-- bindings, controller buttons (Input.lua), and UI controls.
--
--   Define(spec)  before compile. spec: name (unique), label, run(arg, phase, source),
--                 slash (the lowercase word after the slash command; "" for a bare slash command),
--                 held (true to also receive "up" and "cancel" phases).
--   Run(ref, arg, phase, source)
--                 ref is an id (hot path) or a name. phase defaults to "down". A command that
--                 isn't held ignores other phases. Each run is one state batch, so a command that
--                 writes several rows publishes once, and counts in its module's work record
--                 (the addon's own for built-in commands). Returns false for an unknown command,
--                 a stopped module, or a run that errored (the error reaches the error handler).
--
-- After compile, Ids maps each name to its id (Input.lua resolves bindings through it).
--
-- Commands are insecure: they can drive the addon's own UI and state, never protected actions (casting, targeting),
-- which WoW only allows from secure templates and bindings.

local ByteTerrace = ByteTerrace
local ipairs = ipairs
local pairs = pairs
local print = print
local Refuse = ByteTerrace.Refuse
local SortedKeys = ByteTerrace.SortedKeys
local strtrim = strtrim
local tostring = tostring
local type = type

local Commands = {}

ByteTerrace.Commands = Commands
Commands.__index = Commands

--- Creates an addon's command table, empty and uncompiled.
---@param addon table the owning AddOn
function ByteTerrace.NewCommands(addon)
    return setmetatable({ m_addon = addon, m_declared = {} }, Commands)
end

--- Assigns ids and validates every command, raising all problems at once.
function Commands:Compile()
    local problems = {}
    local names = SortedKeys(self.m_declared)
    local ids = {}
    local specs = {}
    local bySlash = {}

    for id, name in ipairs(names) do
        local spec = self.m_declared[name]

        ids[name], specs[id] = id, spec

        if type(spec.run) ~= "function" then
            problems[#problems + 1] = (name .. ": run must be a function")
        end

        if (type(spec.label) ~= "string") or (spec.label == "") then
            problems[#problems + 1] = (name .. ": needs a label")
        end

        local word = spec.slash

        if (word ~= nil) and spec.held then
            -- Slash text only ever presses: a held command would never hear up or cancel.
            problems[#problems + 1] = (name .. ": a held command can't have a slash word")
        elseif word ~= nil then
            if (type(word) ~= "string") or (word ~= word:lower()) or word:find("%s") then
                problems[#problems + 1] = (name .. ": slash word '" .. tostring(word) .. "' must be lowercase with no spaces")
            elseif bySlash[word] then
                problems[#problems + 1] = (name .. ": slash word '" .. word .. "' is taken by " .. names[bySlash[word]])
            else
                bySlash[word] = id
            end
        end
    end

    Refuse(self.m_addon.Name .. " commands", problems)
    self.Ids, self.m_specs, self.m_bySlash = ids, specs, bySlash
    self.m_declared = nil
end

--- Declares a command before compile. The spec is copied. AddOn.lua checks names before defining: each is
--- "<Module>.<command>" (the addon's own are "addon.<command>"), unique, and defined before compile.
---@param spec table see the file header
function Commands:Define(spec)
    local own = {}

    for key, value in pairs(spec) do
        own[key] = value
    end

    own.work = ((spec.module and spec.module.Work) or self.m_addon.Work)
    self.m_declared[spec.name] = own
end

--- Returns whether a command is held: it gets "up" and "cancel" as well as "down".
---@param id integer
---@return boolean
function Commands:IsHeld(id)
    local spec = self.m_specs[id]

    return ((spec ~= nil) and (spec.held == true))
end

--- Returns the module a command belongs to, or nil for the addon's own (help, settings, debug, and so on).
---@param id integer
---@return table? module
function Commands:ModuleOf(id)
    local spec = self.m_specs[id]

    return (spec and spec.module)
end

--- Prints every slash command with its label, sorted by word.
function Commands:PrintHelp()
    local addon = self.m_addon

    addon:Print("Commands:")

    for _, word in ipairs(SortedKeys(self.m_bySlash)) do
        local spec = self.m_specs[self.m_bySlash[word]]

        print(("  %s%s - %s"):format(addon.Slash[1], ((word ~= "") and (" " .. word)) or "", spec.label))
    end
end

--- Runs a command as one state batch.
---@param ref integer|string
---@param arg string? the slash text after the command's word
---@param phase string? "down" (default), "up" or "cancel"; only held commands get the last two
---@param source string? what ran it, e.g. "slash" or "gamepad"
---@return boolean ok false for an unknown command, stopped module or a run that errored
function Commands:Run(ref, arg, phase, source)
    local id = (((type(ref) == "number") and ref) or self.Ids[ref])
    local spec = (id and self.m_specs[id])

    if not spec then
        return false
    end

    phase = (phase or "down")

    if (phase ~= "down") and not spec.held then
        return true
    end

    local addon = self.m_addon
    local module = spec.module

    if module and not spec.always and not module:IsRunning() then
        if phase == "down" then
            local slash = ((addon.Slash and addon.Slash[1]) or "")

            addon:Print(("%s is turned off. Turn it on in settings (%s)."):format(module.Spec.label or module.Name, slash))
        end

        return false
    end

    local work = spec.work

    work.commands = (work.commands + 1)

    return addon:Run(work, spec.run, arg, phase, source)
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

    return self:Run(id, ((rest ~= "") and rest) or nil, "down", "slash")
end
