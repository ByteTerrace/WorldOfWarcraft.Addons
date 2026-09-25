-- AddOn and Module: how an addon assembles the framework.
--
--   local addon = ByteTerrace.NewAddOn({ name = addonName, savedVariable = "MyAddonDB",
--                                    slash = { "/my" }, facts = { "combat" } })
--   addon:Module("Meter", {
--       label = "Meter", description = "...",   -- the module's enabled checkbox
--       state = { { name = "size", kind = "string", default = "wide", values = { "wide", "wider" }, label = "Size" } },
--       commands = { { name = "toggle", slash = "meter", label = "Toggle the meter", run = function() ... end } },
--       bindings = { { map = "menu", source = "gamepad.south", command = "Meter.toggle" } },
--       OnEnable = function(module) module:On("UNIT_POWER_FREQUENT", fn, "player") end,
--       OnDisable = function(module) ... end,
--   })
--
-- Everything declares at file load; the addon compiles once on ADDON_LOADED. A module's rows and
-- commands are named "<Module>.<name>". A module with a label gets an "<Module>.enabled" row
-- (default spec.default ~= false); toggle = false makes it always on. Handlers, watchers and
-- rules a module creates through module:On / :Watch / :Rule belong to it and are removed when it
-- is disabled, so a disabled module registers no events and runs no code.
--
-- Built-in commands: bare slash (settings), help, version, debug, set <row> <value>, toggle <row>.

local ByteTerrace = ByteTerrace
local Report = ByteTerrace.Report
local ipairs, pcall, print, tonumber, tostring, type = ipairs, pcall, print, tonumber, tostring, type

local AddOn = {}
AddOn.__index = AddOn
ByteTerrace.AddOn = AddOn

local Module = {}
Module.__index = Module
ByteTerrace.Module = Module

-- Module -------------------------------------------------------------------

-- Resolves "row" to "<Module>.row"; a name containing "." is already absolute.
function Module:RowName(row)
    return row:find(".", 1, true) and row or (self.name .. "." .. row)
end

function Module:Id(row)
    local id = self.ids[row]
    if not id then
        id = self.addon.state:Id(self:RowName(row))
        self.ids[row] = id
    end
    return id
end

function Module:Get(row)
    return self.addon.state.values[self:Id(row)]
end

function Module:Set(row, value)
    self.addon.state:Set(self:Id(row), value)
end

function Module:On(event, fn, unit)
    local handle = self.addon.events:On(event, fn, unit)
    self.owned[#self.owned + 1] = handle
    return handle
end

function Module:Off(handle)
    self.addon.events:Off(handle)
    for i = #self.owned, 1, -1 do
        if self.owned[i] == handle then
            table.remove(self.owned, i)
        end
    end
end

function Module:ResolveRows(rows)
    local ids = {}
    for i, row in ipairs(rows) do
        ids[i] = type(row) == "number" and row or self:Id(row)
    end
    return ids
end

function Module:Watch(rows, fn, skipInitial)
    local watcher = self.addon.state:Watch(self:ResolveRows(rows), fn, skipInitial)
    self.owned[#self.owned + 1] = watcher
    return watcher
end

function Module:Rule(spec)
    local watcher = self.addon.state:Rule({
        reads = self:ResolveRows(spec.reads), when = spec.when, changed = spec.changed, initial = spec.initial,
    })
    self.owned[#self.owned + 1] = watcher
    return watcher
end

function Module:SetEnabled(enabled)
    if enabled == self.enabled then
        return
    end
    local addon, spec = self.addon, self.spec
    if enabled then
        self.enabled = true
        if spec.OnEnable then
            local ok, err = pcall(spec.OnEnable, self)
            if not ok then
                Report(err)
            end
        end
    else
        for i = #self.owned, 1, -1 do
            local owned = self.owned[i]
            if owned.event then
                addon.events:Off(owned)
            else
                addon.state:Unwatch(owned)
            end
            self.owned[i] = nil
        end
        if spec.OnDisable then
            local ok, err = pcall(spec.OnDisable, self)
            if not ok then
                Report(err)
            end
        end
        self.enabled = false
    end
end

function Module:Start()
    if self.spec.toggle == false then
        self:SetEnabled(true)
    else
        local id = self:Id("enabled")
        self.addon.state:Watch({ id }, function(state)
            self:SetEnabled(state.values[id])
        end)
    end
end

-- AddOn ----------------------------------------------------------------------

function ByteTerrace.NewAddOn(options)
    local addon = setmetatable({
        name = options.name,
        title = options.title or C_AddOns.GetAddOnMetadata(options.name, "Title") or options.name,
        version = options.version or C_AddOns.GetAddOnMetadata(options.name, "Version"),
        savedVariable = options.savedVariable,
        slash = options.slash,
        modules = {},
        moduleOrder = {},
        started = false,
    }, AddOn)
    addon.prefix = "|cff33ccff" .. addon.title .. "|r:"
    addon.state = ByteTerrace.NewState(addon)
    addon.events = ByteTerrace.NewEvents(addon)
    addon.commands = ByteTerrace.NewCommands(addon)
    addon.input = ByteTerrace.NewInput(addon)

    for _, fact in ipairs(options.facts or {}) do
        local spec = ByteTerrace.Facts[fact]
        if not spec then
            error(addon.name .. ": unknown fact " .. tostring(fact), 2)
        end
        addon:Module(fact, spec)
    end
    addon:DefineBuiltinCommands()

    local loaded
    loaded = addon.events:On("ADDON_LOADED", function(name)
        if name == addon.name then
            addon.events:Off(loaded)
            addon:Start()
        end
    end)
    return addon
end

function AddOn:Module(name, spec)
    if self.started then
        error(self.name .. ": module " .. name .. " declared after start", 2)
    end
    if self.modules[name] then
        error(self.name .. ": duplicate module " .. name, 2)
    end
    local module = setmetatable({ addon = self, name = name, spec = spec, enabled = false, owned = {}, ids = {} }, Module)
    if spec.toggle ~= false then
        self.state:Declare(name .. ".enabled", {
            kind = "boolean", default = spec.default ~= false, label = spec.label, description = spec.description,
        })
    end
    for _, row in ipairs(spec.state or {}) do
        self.state:Declare(name .. "." .. row.name, row)
    end
    for _, command in ipairs(spec.commands or {}) do
        command.name = name .. "." .. command.name
        self.commands:Define(command)
    end
    for _, binding in ipairs(spec.bindings or {}) do
        self.input:Bind(binding.map, binding.source, binding.command)
    end
    self.modules[name] = module
    self.moduleOrder[#self.moduleOrder + 1] = module
    return module
end

function AddOn:Start()
    self.state:Declare("addon.debug", {
        kind = "boolean", default = false, label = "Debug output", description = "Print diagnostic messages to chat.",
    })
    local saved = _G[self.savedVariable]
    if type(saved) ~= "table" then
        saved = {}
        _G[self.savedVariable] = saved
    end
    local dropped = self.state:Compile(saved)
    self.debugId = self.state:Id("addon.debug")
    self.commands:Compile()
    self.input:Compile()
    self.settingsCategoryID = ByteTerrace.BuildSettings(self)
    self:RegisterSlash()
    self.started = true
    self.state:BeginBatch()
    for _, module in ipairs(self.moduleOrder) do
        module:Start()
    end
    self.state:EndBatch()
    if #dropped > 0 then
        self:Debug("Dropped saved settings that are no longer declared or valid:", table.concat(dropped, ", "))
    end
end

function AddOn:RegisterSlash()
    if not self.slash then
        return
    end
    local key = self.name:upper():gsub("[^%w]", "")
    for i, alias in ipairs(self.slash) do
        _G["SLASH_" .. key .. i] = alias
    end
    SlashCmdList[key] = function(input)
        self.commands:Slash(input)
    end
end

function AddOn:Print(...)
    print(self.prefix, ...)
end

function AddOn:Debug(...)
    if self.debugId and self.state.values[self.debugId] then
        print(self.prefix, "|cff999999[debug]|r", ...)
    end
end

function AddOn:OpenSettings()
    Settings.OpenToCategory(self.settingsCategoryID)
end

-- Parses slash text into a row's kind: on/off/true/false for booleans, numbers for numbers.
local function ParseValue(kind, text)
    if kind == "boolean" then
        local lower = text:lower()
        if lower == "on" or lower == "true" or lower == "1" then
            return true
        elseif lower == "off" or lower == "false" or lower == "0" then
            return false
        end
        return nil
    elseif kind == "number" then
        return tonumber(text)
    end
    return text
end

function AddOn:SetFromText(arg)
    local name, text = (arg or ""):match("^(%S+)%s+(.+)$")
    local state = self.state
    local id = name and state.ids[name]
    if not id or not state.specs[id].persist then
        self:Print("Usage: " .. self.slash[1] .. " set <setting> <value>. Settings: " .. self:SettingNames())
        return
    end
    local value = ParseValue(state.specs[id].kind, text)
    local ok = value ~= nil and ByteTerrace.State.Admits(state.specs[id], value)
    if not ok then
        self:Print(("%s can't be set to '%s'."):format(name, text))
        return
    end
    state:Set(id, value)
    self:Print(name, "=", tostring(value))
end

function AddOn:ToggleFromText(arg)
    local state = self.state
    local id = arg and state.ids[arg]
    if not id or state.specs[id].kind ~= "boolean" or not state.specs[id].persist then
        self:Print("Usage: " .. self.slash[1] .. " toggle <setting>. Settings: " .. self:SettingNames("boolean"))
        return
    end
    state:Toggle(id)
    self:Print(arg, "=", tostring(state.values[id]))
end

function AddOn:SettingNames(kind)
    local names, state = {}, self.state
    for _, name in ipairs(state.order) do
        local spec = state.specs[state.ids[name]]
        if spec.persist and (not kind or spec.kind == kind) then
            names[#names + 1] = name
        end
    end
    return table.concat(names, ", ")
end

function AddOn:DefineBuiltinCommands()
    local commands = self.commands
    commands:Define({ name = "addon.settings", slash = "", label = "Open settings", run = function() self:OpenSettings() end })
    commands:Define({ name = "addon.help", slash = "help", label = "List commands", run = function() commands:PrintHelp() end })
    commands:Define({ name = "addon.version", slash = "version", label = "Show version", run = function() self:Print("Version", self.version) end })
    commands:Define({
        name = "addon.debug", slash = "debug", label = "Toggle debug output",
        run = function()
            self.state:Toggle(self.debugId)
            self:Print("Debug output", self.state.values[self.debugId] and "enabled." or "disabled.")
        end,
    })
    commands:Define({ name = "addon.set", slash = "set", label = "Set a setting: set <setting> <value>", run = function(arg) self:SetFromText(arg) end })
    commands:Define({ name = "addon.toggle", slash = "toggle", label = "Toggle a setting: toggle <setting>", run = function(arg) self:ToggleFromText(arg) end })
end
