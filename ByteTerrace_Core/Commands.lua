-- Commands: named intents. A command is declared once and every driver runs the same
-- definition: slash text, key bindings, controller buttons (Input.lua) and UI controls.
--
--   Define(spec)  before compile. spec: name (unique), label, run(arg, phase, source),
--                 slash (the word after the slash command; "" for a bare slash command),
--                 held (true to also receive "up" and "cancel" phases).
--   Run(ref, arg, phase, source)
--                 ref is an id (hot path) or a name. phase defaults to "down"; commands that
--                 aren't held only run on "down". Returns false for an unknown command. A command
--                 that errors is reported and returns false; the caller keeps going.
--
-- Commands are insecure: they can drive the addon's own UI and state, never protected actions
-- (casting, targeting), which WoW only allows from secure templates and bindings.

local ByteTerrace = ByteTerrace
local Report, Refuse, SortedKeys = ByteTerrace.Report, ByteTerrace.Refuse, ByteTerrace.SortedKeys
local ipairs, pcall, print, strtrim, type = ipairs, pcall, print, strtrim, type

local Commands = {}
Commands.__index = Commands
ByteTerrace.Commands = Commands

function ByteTerrace.NewCommands(addon)
    return setmetatable({ addon = addon, declared = {}, compiled = false }, Commands)
end

function Commands:Define(spec)
    if self.compiled then
        error(self.addon.name .. ": command " .. tostring(spec.name) .. " defined after compile", 2)
    end
    if self.declared[spec.name] then
        error(self.addon.name .. ": duplicate command " .. tostring(spec.name), 2)
    end
    self.declared[spec.name] = spec
end

function Commands:Compile()
    local problems = {}
    local names = SortedKeys(self.declared)
    local ids, specs, bySlash = {}, {}, {}
    for id, name in ipairs(names) do
        local spec = self.declared[name]
        ids[name], specs[id] = id, spec
        if type(spec.run) ~= "function" then
            problems[#problems + 1] = name .. ": run must be a function"
        end
        if not spec.label then
            problems[#problems + 1] = name .. ": needs a label"
        end
        if spec.slash then
            if bySlash[spec.slash] then
                problems[#problems + 1] = name .. ": slash word '" .. spec.slash .. "' is taken by " .. names[bySlash[spec.slash]]
            end
            bySlash[spec.slash] = id
        end
    end
    Refuse(self.addon.name .. " commands", problems)
    self.ids, self.names, self.specs, self.bySlash = ids, names, specs, bySlash
    self.declared = nil
    self.compiled = true
end

function Commands:Id(name)
    return self.ids[name]
end

function Commands:Run(ref, arg, phase, source)
    local id = type(ref) == "number" and ref or self.ids[ref]
    local spec = id and self.specs[id]
    if not spec then
        return false
    end
    phase = phase or "down"
    if phase ~= "down" and not spec.held then
        return true
    end
    local ok, err = pcall(spec.run, arg, phase, source)
    if not ok then
        Report(err)
    end
    return ok
end

-- The slash driver: "<word> <rest>" runs the command whose slash word matches, with rest as arg.
function Commands:Slash(input)
    local text = strtrim(input or "")
    local word, rest = text:match("^(%S*)%s*(.-)$")
    word = word:lower()
    local id = self.bySlash[word]
    if not id then
        self.addon:Print("Unknown command '" .. word .. "'. Type " .. self.addon.slash[1] .. " help.")
        return false
    end
    return self:Run(id, rest ~= "" and rest or nil, "down", "slash")
end

function Commands:PrintHelp()
    local addon = self.addon
    addon:Print("Commands:")
    local words = SortedKeys(self.bySlash)
    for _, word in ipairs(words) do
        local spec = self.specs[self.bySlash[word]]
        print(("  %s%s - %s"):format(addon.slash[1], word ~= "" and (" " .. word) or "", spec.label))
    end
end
