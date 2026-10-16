-- AddOn: how an addon assembles the framework.
--
--   local addon = ByteTerrace.NewAddOn({ name = addonName, savedVariable = "MyAddonDB",
--                                        savedVariablePerCharacter = "MyAddonCharDB", -- optional
--                                        slash = { "/my" }, facts = { "combat" } })
--   addon:Module("Meter", {
--       label = "Meter", description = "...",   -- the module's enabled checkbox
--       page = "Display",                       -- optional: a subpage in the settings window
--       section = "Energy meter",               -- optional: its header on the page (default: label)
--       state = { { name = "size", kind = "string", default = "wide", values = { "wide", "wider" }, label = "Size",
--                   section = "Look" } },        -- a row's section starts a new header before it
--       commands = { { name = "toggle", slash = "meter", label = "Toggle the meter", run = function() ... end } },
--       bindings = { { map = "menu", source = "gamepad.south", command = "Meter.toggle" } },
--       records = { { name = "people", fields = { ... }, limit = 200, evict = "seen" } }, -- Records.lua
--       comms = { prefix = "MyAddon1" },        -- optional: module.Comms, messages to the group (Comms.lua)
--       active = { reads = { "Other.enabled" }, when = function(state) ... end }, -- optional dependency
--       uses = { "target" },                    -- optional: demand modules it needs running (Module.lua)
--       demand = true,                          -- runs only while a module that uses it runs (toggle = false)
--       scope = "character", lockedBy = "Other.locked",   -- optional, for the enabled row
--       OnEnable = function(module) module:On("UNIT_POWER_FREQUENT", fn, "player") end,
--       OnDisable = function(module) ... end,
--   })
--
-- Everything declares at file load, and the addon compiles once on ADDON_LOADED. A module's rows and commands are named
-- "<Module>.<name>". A module with a label gets an "<Module>.enabled" row (default spec.default ~= false). Setting
-- toggle = false removes it. A module runs while its enabled row is true and its active rule holds. What a module
-- creates through its methods (Module.lua) belongs to it and is removed when it stops, so a stopped module registers no
-- events and runs no code. Rows with scope = "character" persist per character. A module's collections are
-- module.Records.<name>, usable once the addon has loaded. A module's uses must name demand modules and can't form a
-- cycle. Start refuses anything else.
--
-- Settings pages (Settings.lua): modules without a page share the main page, in declaration order, and addon.debug
-- closes it under an "Advanced" header.
--
-- Built-in commands: bare slash (the settings window, SettingsWindow.lua), help, version, debug [status | events | work
-- | rows | trace | cpu | profile | reset] (Diagnostics.lua), set <row> <value>, and toggle <row>.
--
-- Public members: Name, Title, Version, Slash, State, Events, Commands, Input, SettingsWindow, Modules ([name] =
-- Module, Module.lua), Started, Work, and Profiling. Work is the work record (Core.lua) of what the framework runs for
-- no module: built-in commands and module switching. Profiling is whether dispatches are timed (debug profile).

-- Module and row names are identifiers: "." separates a module from its row, so it can't appear in either.
local NamePattern = "^%a[%w_]*$"

local ByteTerrace = ByteTerrace
local ipairs = ipairs
local pairs = pairs
local print = print
local Report = ByteTerrace.Report
local SafeCall = ByteTerrace.SafeCall
local TimedCall = ByteTerrace.TimedCall
local tonumber = tonumber
local tostring = tostring
local type = type

local AddOn = {}

AddOn.__index = AddOn
ByteTerrace.AddOn = AddOn

-- Parses slash text into a row's kind: on/off/true/false for booleans, numbers for numbers.
local function ParseValue(kind, text)
    if kind == "boolean" then
        local lower = text:lower()

        if (lower == "on") or (lower == "true") or (lower == "1") then
            return true
        elseif (lower == "off") or (lower == "false") or (lower == "0") then
            return false
        end

        return nil
    elseif kind == "number" then
        return tonumber(text)
    end

    return text
end

-- Returns who already registered alias ("SLASH_KEYn"), or nil. It reads registrations the way Blizzard's chat code
-- reads slash commands (ChatFrameUtil.lua's ImportListToHash): each SlashCmdList key's numbered SLASH_ globals, never a
-- walk of every global (8 milliseconds in game). The chat frame moves commands out of SlashCmdList into
-- hash_SlashCmdList (keyed by the uppercased alias) once any is typed.
local function TakenBy(alias)
    local wanted = alias:lower()

    if hash_SlashCmdList[alias:upper()] then
        return "a command already in use"
    end

    for key in pairs(SlashCmdList) do
        local i = 1
        -- global: the client's slash registration
        local registered = _G["SLASH_" .. key .. i]

        while type(registered) == "string" do
            if registered:lower() == wanted then
                return ("SLASH_" .. key .. i)
            end

            i = (i + 1)
            -- global: the client's slash registration
            registered = _G["SLASH_" .. key .. i]
        end
    end

    return nil
end

--- Runs fn(...) as one state batch: its writes publish once, when it returns. Timer callbacks and widget scripts aren't
--- batches on their own, unlike event handlers and commands.
---@param fn function
---@return boolean ok false when fn errored (the error reaches the error handler)
function AddOn:Batch(fn, ...)
    local state = self.State

    state:BeginBatch()
    local ok = SafeCall(fn, ...)

    state:EndBatch()

    return ok
end

--- Prints to chat only while addon.debug is on.
function AddOn:Debug(...)
    if self.m_debugId and self.State.Values[self.m_debugId] then
        print(self.m_prefix, "|cff999999[debug]|r", ...)
    end
end

--- Declares the built-in commands: bare slash, help, version, debug, set and toggle.
function AddOn:DefineBuiltinCommands()
    local commands = self.Commands

    commands:Define({
        label = "Show or hide settings", name = "addon.settings", run = function() self:ToggleSettings() end,
        slash = "",
    })

    commands:Define({
        label = "List commands", name = "addon.help", run = function() commands:PrintHelp() end, slash = "help",
    })

    commands:Define({
        label = "Show version", name = "addon.version", run = function() self:Print("Version", self.Version) end,
        slash = "version",
    })

    commands:Define({
        label = "Toggle debug output, or inspect: debug status | events | work | rows | trace | cpu | profile | reset",
        name = "addon.debug", run = function(arg) self:DebugCommand(arg) end, slash = "debug",
    })

    commands:Define({
        label = "Set a setting: set <setting> <value>", name = "addon.set",
        run = function(arg) self:SetFromText(arg) end, slash = "set",
    })

    commands:Define({
        label = "Toggle a setting: toggle <setting>", name = "addon.toggle",
        run = function(arg) self:ToggleFromText(arg) end, slash = "toggle",
    })
end

--- Declares a module before the addon starts. Preparations that fail register nothing and claim no saved data. See the
--- file header for the spec.
---@param name string an identifier, unique in the addon
---@param spec table
---@return table module
function AddOn:Module(name, spec)
    if self.m_sealed then
        error(self.Name .. ": module " .. name .. " declared after start", 2)
    end

    if self.Modules[name] then
        error(self.Name .. ": duplicate module " .. name, 2)
    end

    if (type(name) ~= "string") or not name:find(NamePattern) then
        error(self.Name .. ": module name '" .. tostring(name) .. "' must be an identifier", 2)
    end

    if (name == "addon") or (ByteTerrace.Facts[name] and (ByteTerrace.Facts[name] ~= spec)) then
        error(self.Name .. ": module name '" .. name .. "' is reserved", 2)
    end

    local active = spec.active

    if (active ~= nil) and ((type(active) ~= "table") or (type(active.reads) ~= "table") or (type(active.when) ~= "function")) then
        error(self.Name .. ": module " .. name .. ": active must be { reads = { rows... }, when = function(state) }", 2)
    end

    for _, key in ipairs({ "page", "section" }) do
        if (spec[key] ~= nil) and (type(spec[key]) ~= "string") then
            error(self.Name .. ": module " .. name .. ": " .. key .. " must be a string", 2)
        end
    end

    if (spec.uses ~= nil) and (type(spec.uses) ~= "table") then
        error(self.Name .. ": module " .. name .. ": uses must be a list of module names", 2)
    end

    if spec.demand and ((spec.toggle ~= false) or (active ~= nil)) then
        error(self.Name .. ": module " .. name .. ": a demand module has toggle = false and no active rule", 2)
    end

    local module = ByteTerrace.NewModule(self, name, spec)
    local rows = {}
    local commands = {}
    local collections = {}
    local rowNames = {}
    local commandNames = {}

    local function AddRow(rowName, row)
        if (type(rowName) ~= "string") or not rowName:find(NamePattern) then
            error(self.Name .. ": row name '" .. tostring(rowName) .. "' in module " .. name .. " must be an identifier", 2)
        end

        local full = (name .. "." .. rowName)

        if rowNames[full] then
            error(self.Name .. ": duplicate state row " .. full, 2)
        end

        rowNames[full] = true
        rows[#rows + 1] = { name = full, spec = row }
    end

    if spec.toggle ~= false then
        AddRow("enabled", {
            default = (spec.default ~= false), description = spec.description, kind = "boolean", label = spec.label,
            lockedBy = spec.lockedBy, scope = spec.scope,
        })
    end

    for _, row in ipairs(spec.state or {}) do
        AddRow(row.name, row)
    end

    for _, collection in ipairs(spec.records or {}) do
        if (type(collection.name) ~= "string") or not collection.name:find(NamePattern) then
            local message = "%s: records name '%s' in module %s must be an identifier"

            error(message:format(self.Name, tostring(collection.name), name), 2)
        end

        local records = ByteTerrace.NewRecords(self, name .. "." .. collection.name, collection)

        module.Records[collection.name] = records
        collections[#collections + 1] = records
        AddRow(collection.name, { default = 0, kind = "number", persist = false, records = true, scope = collection.scope })
    end

    for _, command in ipairs(spec.commands or {}) do
        -- Commands owns the activation check, so validation still sees the actual callback.
        if (type(command.name) ~= "string") or not command.name:find(NamePattern) then
            error(self.Name .. ": command name in module " .. name .. " must be an identifier", 2)
        end

        local full = (name .. "." .. command.name)

        if commandNames[full] then
            error(self.Name .. ": duplicate command " .. full, 2)
        end

        commandNames[full] = true

        commands[#commands + 1] = {
            always = command.always, held = command.held, label = command.label, module = module, name = full,
            run = command.run, slash = command.slash,
        }
    end

    if spec.comms ~= nil then
        module.Comms = ByteTerrace.NewComms(module, spec.comms)
    end

    for _, binding in ipairs(spec.bindings or {}) do
        if type(binding) ~= "table" then
            error(self.Name .. ": a binding must be a table", 2)
        end

        self.Input:CheckDeclaration(binding.map, binding.source, binding.command)
    end

    -- No registration or SavedVariables ownership escapes a failed declaration.
    for _, row in ipairs(rows) do
        self.State:Declare(row.name, row.spec)
    end

    for _, command in ipairs(commands) do
        self.Commands:Define(command)
    end

    for _, binding in ipairs(spec.bindings or {}) do
        self.Input:Bind(binding.map, binding.source, binding.command)
    end

    for _, records in ipairs(collections) do
        self.m_collections[#self.m_collections + 1] = records
    end

    self.Modules[name] = module
    self.m_moduleOrder[#self.m_moduleOrder + 1] = module

    return module
end

--- Prints to chat behind the addon's colored title.
function AddOn:Print(...)
    print(self.m_prefix, ...)
end

--- Registers the slash aliases with the client. An alias another addon already registered is reported and skipped.
function AddOn:RegisterSlash()
    if not self.Slash then
        return
    end

    local key = self.Name:upper():gsub("[^%w]", "")

    if SlashCmdList[key] then
        Report(self.Name .. ": slash command key " .. key .. " is already registered; slash commands are off")

        return
    end

    local index = 0

    for _, alias in ipairs(self.Slash) do
        local owner = TakenBy(alias)

        if owner then
            Report(self.Name .. ": " .. alias .. " is already taken by " .. owner .. "; skipping it")
        else
            index = (index + 1)
            -- global: WoW's slash command registration
            _G["SLASH_" .. key .. index] = alias
        end
    end

    if index > 0 then
        SlashCmdList[key] = function(input)
            self.Commands:Slash(input)
        end
    end
end

--- Resolves each module's uses to the demand modules it names, raising every problem at once: an unknown name, a module
--- that isn't a demand module, or a cycle.
---@return table usesOf [module] = array of its dependencies
function AddOn:ResolveUses()
    local problems = {}
    local usesOf = {}

    for _, module in ipairs(self.m_moduleOrder) do
        local list = {}

        for _, name in ipairs(module.Spec.uses or {}) do
            local dependency = self.Modules[name]

            if not dependency then
                problems[#problems + 1] = ("%s uses unknown module %s"):format(module.Name, tostring(name))
            elseif not dependency.Spec.demand then
                problems[#problems + 1] = ("%s uses %s, which isn't a demand module"):format(module.Name, name)
            else
                list[#list + 1] = dependency
            end
        end

        usesOf[module] = list
    end

    local visiting = {}
    local done = {}

    local function Visit(module)
        if done[module] then
            return
        end

        if visiting[module] then
            problems[#problems + 1] = (module.Name .. " is part of a uses cycle")

            return
        end

        visiting[module] = true

        for _, dependency in ipairs(usesOf[module]) do
            Visit(dependency)
        end

        visiting[module], done[module] = nil, true
    end

    for _, module in ipairs(self.m_moduleOrder) do
        Visit(module)
    end

    ByteTerrace.Refuse(self.Name .. " modules", problems)

    return usesOf
end

--- Runs fn as one batch for work the framework runs on a module's behalf (timers, commands, and deferred actions).
--- While profiling, fn's time, not the publish after it, adds to work.time. The caller counts the run in work's field
--- for its kind.
---@param work table a work record (Core.lua)
---@param fn function
---@return boolean ok false when fn errored (the error reaches the error handler)
function AddOn:Run(work, fn, ...)
    local state = self.State

    state:BeginBatch()
    local ok

    if self.Profiling then
        ok = TimedCall(work, fn, ...)
    else
        ok = SafeCall(fn, ...)
    end

    state:EndBatch()

    return ok
end

--- The `set <setting> <value>` command: only settings (labeled, persisted rows) are reachable.
---@param arg string?
function AddOn:SetFromText(arg)
    local name, text = (arg or ""):match("^(%S+)%s+(.+)$")
    local state = self.State
    local id = (name and state.Ids[name])

    if not id or not state.Specs[id].persist or not state.Specs[id].label then
        self:Print("Usage: " .. self.Slash[1] .. " set <setting> <value>. Settings: " .. self:SettingNames())

        return
    end

    if state:IsLocked(id) then
        self:Print(name .. " is locked.")

        return
    end

    local value = ParseValue(state.Specs[id].kind, text)
    local ok = ((value ~= nil) and ByteTerrace.State.Admits(state.Specs[id], value))

    if not ok then
        self:Print(("%s can't be set to '%s'."):format(name, text))

        return
    end

    state:Set(id, value)
    self:Print(name, "=", tostring(value))
end

--- Returns the settings' names in declaration order, comma separated.
---@param kind string? only rows of this kind
---@return string
function AddOn:SettingNames(kind)
    local names = {}
    local state = self.State

    for _, name in ipairs(state.Order) do
        local spec = state.Specs[state.Ids[name]]

        if spec.persist and spec.label and (not kind or (spec.kind == kind)) then
            names[#names + 1] = name
        end
    end

    return table.concat(names, ", ")
end

--- Compiles every declaration, loads SavedVariables, creates the settings window and slash commands, then starts the
--- modules in one batch. ADDON_LOADED calls it. A refused declaration raises before anything starts. Declarations close
--- as it begins, so none follows even a refused start.
function AddOn:Start()
    self.m_sealed = true
    local usesOf = self:ResolveUses()

    self.State:Declare("addon.debug", {
        default = false, description = "Print diagnostic messages to chat.", kind = "boolean", label = "Debug output",
        section = "Advanced",
    })

    local stores = {}

    for scope, variable in pairs({ account = self.m_savedVariable, character = self.m_savedVariablePerCharacter }) do
        -- global: the TOC's SavedVariables, restored before ADDON_LOADED
        local store = _G[variable]

        if type(store) ~= "table" then
            store = {}
            -- global: declared in the TOC
            _G[variable] = store
        end

        stores[scope] = store
    end

    local declared = { addon = true }

    for name in pairs(self.Modules) do
        declared[name] = true
    end

    -- Refuse commands and bindings before state or record loading can normalize saved data.
    self.Commands:Compile()
    self.Input:Compile()
    local dropped, unclaimed = self.State:Compile(stores, declared)

    for _, records in ipairs(self.m_collections) do
        local droppedRecords, resetFields = records:Load(stores)

        if (droppedRecords + resetFields) > 0 then
            dropped[#dropped + 1] = ("%s (%d records, %d fields)"):format(records.Name, droppedRecords, resetFields)
        end
    end

    self.m_debugId = self.State:Id("addon.debug")
    local pages = ByteTerrace.SettingsPages(self)

    self.SettingsWindow = ByteTerrace.NewSettingsWindow(self, pages)
    self.SettingsWindow:Register()
    self:RegisterSlash()
    self.Started = true
    self.State:BeginBatch()

    for _, module in ipairs(self.m_moduleOrder) do
        module:Prepare(usesOf[module])
    end

    for _, module in ipairs(self.m_moduleOrder) do
        -- SafeCall keeps one broken module from stopping the rest, or the batch.
        SafeCall(module.Start, module)
    end

    self.State:EndBatch()

    if #dropped > 0 then
        self:Debug("Reset saved settings that are no longer valid:", table.concat(dropped, ", "))
    end

    if #unclaimed > 0 then
        self:Debug("Kept saved settings no module declares:", table.concat(unclaimed, ", "))
    end
end

--- The `toggle <setting>` command, for boolean settings.
---@param arg string?
function AddOn:ToggleFromText(arg)
    local state = self.State
    local id = (arg and state.Ids[arg])

    if not id or (state.Specs[id].kind ~= "boolean") or not state.Specs[id].persist or not state.Specs[id].label then
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

--- Shows the addon's settings window, or hides it when it shows (SettingsWindow.lua). It's the addon's own frame, so it
--- opens in combat too.
function AddOn:ToggleSettings()
    self.SettingsWindow:Toggle()
end

--- Creates an addon. It declares its facts and built-in commands now and starts itself on its ADDON_LOADED.
---@param options table { name, savedVariable, savedVariablePerCharacter?, title?, version?, slash?, facts? }
---@return table addon
function ByteTerrace.NewAddOn(options)
    if (type(options.name) ~= "string") or (type(options.savedVariable) ~= "string") then
        error("NewAddOn needs a name and a savedVariable (the TOC's ## SavedVariables)", 2)
    end

    local addon = setmetatable({
        m_collections = {},
        m_moduleOrder = {},
        m_savedVariable = options.savedVariable,
        m_savedVariablePerCharacter = options.savedVariablePerCharacter,
        -- True once Start begins. Nothing declares after that.
        m_sealed = false,
        Modules = {},
        Name = options.name,
        Profiling = false,
        Slash = options.slash,
        Started = false,
        Title = (options.title or C_AddOns.GetAddOnMetadata(options.name, "Title") or options.name),
        Version = (options.version or C_AddOns.GetAddOnMetadata(options.name, "Version")),
        Work = ByteTerrace.NewWork(),
    }, AddOn)

    addon.m_prefix = ("|cff33ccff" .. addon.Title .. "|r:")
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
