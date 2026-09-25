-- AddOn and Module: how an addon assembles the framework.
--
--   local addon = ByteTerrace.NewAddOn({ name = addonName, savedVariable = "MyAddonDB",
--                                        savedVariablePerCharacter = "MyAddonCharDB", -- optional
--                                        slash = { "/my" }, facts = { "combat" } })
--   addon:Module("Meter", {
--       label = "Meter", description = "...",   -- the module's enabled checkbox
--       page = "Display",                       -- optional: a settings subcategory for its settings
--       section = "Energy meter",               -- optional: its header on the page (default: label)
--       state = { { name = "size", kind = "string", default = "wide", values = { "wide", "wider" }, label = "Size",
--                   section = "Look" } },        -- a row's section starts a new header before it
--       commands = { { name = "toggle", slash = "meter", label = "Toggle the meter", run = function() ... end } },
--       bindings = { { map = "menu", source = "gamepad.south", command = "Meter.toggle" } },
--       records = { { name = "people", fields = { ... }, limit = 200, evict = "seen" } }, -- Records.lua
--       active = { reads = { "Other.enabled" }, when = function(state) ... end }, -- optional dependency
--       scope = "character", lockedBy = "Other.locked",   -- optional, for the enabled row
--       OnEnable = function(module) module:On("UNIT_POWER_FREQUENT", fn, "player") end,
--       OnDisable = function(module) ... end,
--   })
--
-- Everything declares at file load; the addon compiles once on ADDON_LOADED. A module's rows and
-- commands are named "<Module>.<name>". A module with a label gets an "<Module>.enabled" row
-- (default spec.default ~= false); toggle = false removes it. A module runs while its enabled row
-- is true and its active rule holds. Handlers, watchers and rules a module creates through
-- module:On / :Watch / :Rule belong to it and are removed when it stops, so a stopped module
-- registers no events and runs no code. Rows with scope = "character" persist per character.
-- A module's collections are module.Records.<name>, usable once the addon has loaded.
--
-- Settings pages (Settings.lua): modules without a page share the main page, in declaration
-- order, and addon.debug closes it under an "Advanced" header.
--
-- Built-in commands: bare slash (settings), help, version, debug, set <row> <value>, toggle <row>.
--
-- Public members. AddOn: Name, Title, Version, Slash, State, Events, Commands, Input, Modules
-- ([name] = Module) and Started. Module: Addon, Spec (the declaration, never changed), Enabled
-- and Records.

-- Module and row names are identifiers: "." separates a module from its row, so it can't appear in either.
local NamePattern = "^%a[%w_]*$"

local ByteTerrace = ByteTerrace
local Report, SafeCall = ByteTerrace.Report, ByteTerrace.SafeCall
local InCombatLockdown = InCombatLockdown
local ipairs, pairs, print, tonumber, tostring, type = ipairs, pairs, print, tonumber, tostring, type

local AddOn = {}
AddOn.__index = AddOn
ByteTerrace.AddOn = AddOn

local Module = {}
Module.__index = Module
ByteTerrace.Module = Module

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

--- Resolves "row" to "<Module>.row"; a name containing "." ("combat.active") is already absolute.
---@param row string
---@return string
function Module:RowName(row)
    return row:find(".", 1, true) and row or (self.m_name .. "." .. row)
end

--- A row's id, from its name (resolved once and cached) or an id passed straight through. An
--- unknown row is an error.
---@param row integer|string
---@return integer
function Module:Id(row)
    if type(row) == "number" then
        return row
    end
    local id = self.m_ids[row]
    if not id then
        id = self.Addon.State.Ids[self:RowName(row)]
        if not id then
            error(self.Addon.Name .. ": unknown state row " .. self:RowName(row), 2)
        end
        self.m_ids[row] = id
    end
    return id
end

--- A row's value.
---@param row integer|string relative to the module unless it contains "."
function Module:Get(row)
    return self.Addon.State.Values[self:Id(row)]
end

--- Writes a row through State:Set; errors point at the caller.
---@param row integer|string
function Module:Set(row, value)
    self.Addon.State:Set(self:Id(row), value, 2)
end

--- Flips a boolean row.
---@param row integer|string
function Module:Toggle(row)
    self.Addon.State:Toggle(self:Id(row), 2)
end

--- Adds an event handler that the module owns: it's removed when the module stops.
---@param event string
---@param fn function
---@param unit string?
---@return table handle for Off
function Module:On(event, fn, unit)
    local handle = self.Addon.Events:On(event, fn, unit)
    self.m_handles[#self.m_handles + 1] = handle
    return handle
end

--- Removes a handler early; the module's teardown skips handles that are already removed.
---@param handle table from On
function Module:Off(handle)
    self.Addon.Events:Off(handle)
end

--- Resolves a list of rows to ids.
---@param rows (integer|string)[]
---@return integer[]
function Module:ResolveRows(rows)
    local ids = {}
    for i, row in ipairs(rows) do
        ids[i] = self:Id(row)
    end
    return ids
end

--- State:Watch, owned by the module.
---@param rows (integer|string)[]
---@param fn fun(state: table)
---@param skipInitial boolean?
---@return table watcher
function Module:Watch(rows, fn, skipInitial)
    local watcher = self.Addon.State:Watch(self:ResolveRows(rows), fn, skipInitial)
    self.m_watchers[#self.m_watchers + 1] = watcher
    return watcher
end

--- State:Rule, owned by the module; reads may be relative row names.
---@param spec table { reads, when, changed, initial? }
---@return table watcher
function Module:Rule(spec)
    local watcher = self.Addon.State:Rule({
        reads = self:ResolveRows(spec.reads), when = spec.when, changed = spec.changed, initial = spec.initial,
    })
    self.m_watchers[#self.m_watchers + 1] = watcher
    return watcher
end

--- Starts or stops the module now. Stopping removes everything it owns in one pass (every
--- handler goes dead at once, even mid-dispatch, and each affected event re-registers once),
--- runs OnDisable, then returns its runtime rows to their defaults so no reader sees stale facts.
---@param enabled boolean
function Module:SetEnabled(enabled)
    if enabled == self.Enabled then
        return
    end
    local addon, spec = self.Addon, self.Spec
    if enabled then
        self.Enabled = true
        if spec.OnEnable then
            SafeCall(spec.OnEnable, self)
        end
        return
    end
    local handles, watchers = self.m_handles, self.m_watchers
    self.m_handles, self.m_watchers = {}, {}
    for i = 1, #watchers do
        addon.State:Unwatch(watchers[i])
    end
    addon.Events:OffAll(handles)
    if spec.OnDisable then
        SafeCall(spec.OnDisable, self)
    end
    local state = addon.State
    state:BeginBatch()
    for _, id in ipairs(self.m_runtime) do
        state:Set(id, state.Specs[id].default)
    end
    state:EndBatch()
    self.Enabled = false
end

--- Connects the module to its enabled row and active rule. A module runs while its enabled row
--- (if it has one) is true and its spec.active rule (if any) holds; that's how a module depends
--- on other rows, so a switched-off feature registers nothing.
function Module:Start()
    local spec, state = self.Spec, self.Addon.State
    self.m_runtime = {}
    for _, row in ipairs(spec.state or {}) do
        if row.persist == false then
            self.m_runtime[#self.m_runtime + 1] = self:Id(row.name)
        end
    end
    local enabledId = spec.toggle ~= false and self:Id("enabled") or nil
    local active = spec.active
    if not enabledId and not active then
        self:SetEnabled(true)
        return
    end
    local reads = active and self:ResolveRows(active.reads) or {}
    if enabledId then
        reads[#reads + 1] = enabledId
    end
    local when = active and active.when
    state:Watch(reads, function(current)
        self:SetEnabled((not enabledId or current.Values[enabledId]) and (not when or when(current)) and true or false)
    end)
end

--- Creates an addon. It declares its facts and built-in commands now and starts itself on its
--- ADDON_LOADED.
---@param options table { name, savedVariable, savedVariablePerCharacter?, title?, version?, slash?, facts? }
---@return table addon
function ByteTerrace.NewAddOn(options)
    if type(options.name) ~= "string" or type(options.savedVariable) ~= "string" then
        error("NewAddOn needs a name and a savedVariable (the TOC's ## SavedVariables)", 2)
    end
    local addon = setmetatable({
        Name = options.name,
        Title = options.title or C_AddOns.GetAddOnMetadata(options.name, "Title") or options.name,
        Version = options.version or C_AddOns.GetAddOnMetadata(options.name, "Version"),
        Slash = options.slash,
        Modules = {},
        Started = false,
        m_savedVariable = options.savedVariable,
        m_savedVariablePerCharacter = options.savedVariablePerCharacter,
        m_moduleOrder = {},
        m_collections = {},
    }, AddOn)
    addon.m_prefix = "|cff33ccff" .. addon.Title .. "|r:"
    addon.State = ByteTerrace.NewState(addon)
    addon.Events = ByteTerrace.NewEvents(addon)
    addon.Commands = ByteTerrace.NewCommands(addon)
    addon.Input = ByteTerrace.NewInput(addon)

    for _, fact in ipairs(options.facts or {}) do
        local spec = ByteTerrace.Facts[fact]
        if not spec then
            error(addon.Name .. ": unknown fact " .. tostring(fact), 2)
        end
        addon:Module(fact, spec)
    end
    addon:DefineBuiltinCommands()

    local loaded
    loaded = addon.Events:On("ADDON_LOADED", function(name)
        if name == addon.Name then
            addon.Events:Off(loaded)
            addon:Start()
        end
    end)
    return addon
end

--- Declares a module before the addon starts. See the file header for the spec.
---@param name string an identifier, unique in the addon
---@param spec table
---@return table module
function AddOn:Module(name, spec)
    if self.Started then
        error(self.Name .. ": module " .. name .. " declared after start", 2)
    end
    if self.Modules[name] then
        error(self.Name .. ": duplicate module " .. name, 2)
    end
    if not name:find(NamePattern) then
        error(self.Name .. ": module name '" .. name .. "' must be an identifier", 2)
    end
    if name == "addon" or (ByteTerrace.Facts[name] and ByteTerrace.Facts[name] ~= spec) then
        error(self.Name .. ": module name '" .. name .. "' is reserved", 2)
    end
    local active = spec.active
    if active ~= nil and (type(active) ~= "table" or type(active.reads) ~= "table" or type(active.when) ~= "function") then
        error(self.Name .. ": module " .. name .. ": active must be { reads = { rows... }, when = function(state) }", 2)
    end
    for _, key in ipairs({ "page", "section" }) do
        if spec[key] ~= nil and type(spec[key]) ~= "string" then
            error(self.Name .. ": module " .. name .. ": " .. key .. " must be a string", 2)
        end
    end
    local module = setmetatable({
        Addon = self, Spec = spec, Enabled = false, Records = {},
        m_name = name, m_handles = {}, m_watchers = {}, m_ids = {}, m_runtime = {},
    }, Module)
    if spec.toggle ~= false then
        self.State:Declare(name .. ".enabled", {
            kind = "boolean", default = spec.default ~= false, label = spec.label, description = spec.description,
            scope = spec.scope, lockedBy = spec.lockedBy,
        })
    end
    for _, row in ipairs(spec.state or {}) do
        if not tostring(row.name):find(NamePattern) then
            error(self.Name .. ": row name '" .. tostring(row.name) .. "' in module " .. name .. " must be an identifier", 2)
        end
        self.State:Declare(name .. "." .. row.name, row)
    end
    for _, collection in ipairs(spec.records or {}) do
        if not tostring(collection.name):find(NamePattern) then
            local message = "%s: records name '%s' in module %s must be an identifier"
            error(message:format(self.Name, tostring(collection.name), name), 2)
        end
        local records = ByteTerrace.NewRecords(self, name .. "." .. collection.name, collection)
        module.Records[collection.name] = records
        self.m_collections[#self.m_collections + 1] = records
    end
    for _, command in ipairs(spec.commands or {}) do
        -- A copy: a spec shared by several addons (like ByteTerrace.Facts) must stay unprefixed.
        -- A module's command runs only while the module runs, unless it's marked `always` (a
        -- command that turns its own module on, or works without it).
        local run = command.run
        if not command.always then
            run = function(...)
                if module.Enabled then
                    return command.run(...)
                end
                local slash = self.Slash and self.Slash[1] or ""
                self:Print(("%s is turned off. Turn it on in settings (%s)."):format(spec.label or name, slash))
            end
        end
        self.Commands:Define({
            name = name .. "." .. command.name, label = command.label, run = run,
            slash = command.slash, held = command.held,
        })
    end
    for _, binding in ipairs(spec.bindings or {}) do
        self.Input:Bind(binding.map, binding.source, binding.command)
    end
    self.Modules[name] = module
    self.m_moduleOrder[#self.m_moduleOrder + 1] = module
    return module
end

--- Compiles every declaration, loads SavedVariables, builds settings and slash commands, then
--- starts the modules in one batch. ADDON_LOADED calls it; a refused declaration raises before
--- anything starts.
function AddOn:Start()
    self.State:Declare("addon.debug", {
        kind = "boolean", default = false, label = "Debug output", description = "Print diagnostic messages to chat.",
        section = "Advanced",
    })
    local stores = {}
    for scope, variable in pairs({ account = self.m_savedVariable, character = self.m_savedVariablePerCharacter }) do
        local store = _G[variable] -- global: the TOC's SavedVariables, restored before ADDON_LOADED
        if type(store) ~= "table" then
            store = {}
            _G[variable] = store -- global: declared in the TOC
        end
        stores[scope] = store
    end
    local dropped, unclaimed = self.State:Compile(stores)
    for _, records in ipairs(self.m_collections) do
        local droppedRecords, resetFields = records:Load(stores)
        if droppedRecords + resetFields > 0 then
            dropped[#dropped + 1] = ("%s (%d records, %d fields)"):format(records.Name, droppedRecords, resetFields)
        end
    end
    self.m_debugId = self.State:Id("addon.debug")
    self.Commands:Compile()
    self.Input:Compile()
    self.m_settingsCategoryID = ByteTerrace.BuildSettings(self)
    self:RegisterSlash()
    self.Started = true
    self.State:BeginBatch()
    for _, module in ipairs(self.m_moduleOrder) do
        SafeCall(module.Start, module) -- one broken module can't stop the rest, or the batch
    end
    self.State:EndBatch()
    if #dropped > 0 then
        self:Debug("Reset saved settings that are no longer valid:", table.concat(dropped, ", "))
    end
    if #unclaimed > 0 then
        self:Debug("Kept saved settings no module declares:", table.concat(unclaimed, ", "))
    end
end

--- Registers the slash aliases with the client. An alias another addon already registered is
--- reported and skipped.
function AddOn:RegisterSlash()
    if not self.Slash then
        return
    end
    local key = self.Name:upper():gsub("[^%w]", "")
    if SlashCmdList[key] then
        Report(self.Name .. ": slash command key " .. key .. " is already registered; slash commands are off")
        return
    end
    local taken = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and name:sub(1, 6) == "SLASH_" and type(value) == "string" then
            taken[value:lower()] = name
        end
    end
    local index = 0
    for _, alias in ipairs(self.Slash) do
        if taken[alias:lower()] then
            Report(self.Name .. ": " .. alias .. " is already taken by " .. taken[alias:lower()] .. "; skipping it")
        else
            index = index + 1
            _G["SLASH_" .. key .. index] = alias -- global: WoW's slash command registration
        end
    end
    if index > 0 then
        SlashCmdList[key] = function(input)
            self.Commands:Slash(input)
        end
    end
end

--- Runs fn(...) as one state batch: its writes publish once, when it returns. Timer callbacks and
--- widget scripts aren't batches on their own, unlike event handlers and commands.
---@param fn function
---@return boolean ok false when fn errored (the error reaches the error handler)
function AddOn:Batch(fn, ...)
    local state = self.State
    state:BeginBatch()
    local ok = SafeCall(fn, ...)
    state:EndBatch()
    return ok
end

--- Prints to chat behind the addon's colored title.
function AddOn:Print(...)
    print(self.m_prefix, ...)
end

--- Prints to chat only while addon.debug is on.
function AddOn:Debug(...)
    if self.m_debugId and self.State.Values[self.m_debugId] then
        print(self.m_prefix, "|cff999999[debug]|r", ...)
    end
end

--- Opens the addon's settings. The panel can't open during combat lockdown; it opens as soon as
--- combat ends instead.
function AddOn:OpenSettings()
    if InCombatLockdown() then
        if not self.m_pendingSettings then
            self:Print("Settings will open when combat ends.")
            self.m_pendingSettings = self.Events:On("PLAYER_REGEN_ENABLED", function()
                self.Events:Off(self.m_pendingSettings)
                self.m_pendingSettings = nil
                self:OpenSettings()
            end)
        end
        return
    end
    Settings.OpenToCategory(self.m_settingsCategoryID) -- protected: guarded by InCombatLockdown above
end

--- The `set <setting> <value>` command: only settings (labeled, persisted rows) are reachable.
---@param arg string?
function AddOn:SetFromText(arg)
    local name, text = (arg or ""):match("^(%S+)%s+(.+)$")
    local state = self.State
    local id = name and state.Ids[name]
    if not id or not state.Specs[id].persist or not state.Specs[id].label then
        self:Print("Usage: " .. self.Slash[1] .. " set <setting> <value>. Settings: " .. self:SettingNames())
        return
    end
    if state:IsLocked(id) then
        self:Print(name .. " is locked.")
        return
    end
    local value = ParseValue(state.Specs[id].kind, text)
    local ok = value ~= nil and ByteTerrace.State.Admits(state.Specs[id], value)
    if not ok then
        self:Print(("%s can't be set to '%s'."):format(name, text))
        return
    end
    state:Set(id, value)
    self:Print(name, "=", tostring(value))
end

--- The `toggle <setting>` command, for boolean settings.
---@param arg string?
function AddOn:ToggleFromText(arg)
    local state = self.State
    local id = arg and state.Ids[arg]
    if not id or state.Specs[id].kind ~= "boolean" or not state.Specs[id].persist or not state.Specs[id].label then
        self:Print("Usage: " .. self.Slash[1] .. " toggle <setting>. Settings: " .. self:SettingNames("boolean"))
        return
    end
    if state:IsLocked(id) then
        self:Print(arg .. " is locked.")
        return
    end
    state:Toggle(id)
    self:Print(arg, "=", tostring(state.Values[id]))
end

--- The settings' names in declaration order, comma separated.
---@param kind string? only rows of this kind
---@return string
function AddOn:SettingNames(kind)
    local names, state = {}, self.State
    for _, name in ipairs(state.Order) do
        local spec = state.Specs[state.Ids[name]]
        if spec.persist and spec.label and (not kind or spec.kind == kind) then
            names[#names + 1] = name
        end
    end
    return table.concat(names, ", ")
end

--- Declares the built-in commands: bare slash, help, version, debug, set and toggle.
function AddOn:DefineBuiltinCommands()
    local commands = self.Commands
    commands:Define({
        name = "addon.settings", slash = "", label = "Open settings",
        run = function() self:OpenSettings() end,
    })
    commands:Define({
        name = "addon.help", slash = "help", label = "List commands",
        run = function() commands:PrintHelp() end,
    })
    commands:Define({
        name = "addon.version", slash = "version", label = "Show version",
        run = function() self:Print("Version", self.Version) end,
    })
    commands:Define({
        name = "addon.debug", slash = "debug", label = "Toggle debug output",
        run = function()
            self.State:Toggle(self.m_debugId)
            self:Print("Debug output", self.State.Values[self.m_debugId] and "enabled." or "disabled.")
        end,
    })
    commands:Define({
        name = "addon.set", slash = "set", label = "Set a setting: set <setting> <value>",
        run = function(arg) self:SetFromText(arg) end,
    })
    commands:Define({
        name = "addon.toggle", slash = "toggle", label = "Toggle a setting: toggle <setting>",
        run = function(arg) self:ToggleFromText(arg) end,
    })
end
