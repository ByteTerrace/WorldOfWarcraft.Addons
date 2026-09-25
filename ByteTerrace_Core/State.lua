-- State: declared, typed rows with one admission path, change versions, and one publication
-- pass per batch.
--
--   Declare(name, spec)  before compile. spec: kind ("boolean" | "number" | "string"), default,
--                        values (string enum), valueLabels (enum display), min / max / step
--                        (number), persist (default true), scope ("account" default, or
--                        "character"), label / description / section (settings panel), lockedBy
--                        (a boolean row's name: while that row is true, writes to this row are
--                        refused, e.g. settings a parent locked). The spec is copied; the
--                        caller's table is never changed.
--   Compile(stores)      sorts names to dense ids and validates every declaration, reporting all
--                        problems at once. stores = { account = table, character = table? }: the
--                        SavedVariables tables persisted rows load from and write to, by scope.
--                        A value that no longer validates is dropped, and so is a key under a
--                        declared module that no row declares (a renamed row). Keys under modules
--                        this load didn't declare are kept: a module whose file failed to load
--                        must not lose its settings.
--                        A records row (declared by Records.lua with records = true) is a
--                        collection's version; its store key holds the collection and is kept.
--   Get / Set / Toggle   by id (hot paths) or name (boundaries). Every write is validated: kind,
--                        enum, bounds, step, finiteness, and never a secret value, since rules
--                        compute over rows.
--   Watch / Rule         run after a publish in which one of their rows changed.
--   BeginBatch/EndBatch  bracket a batch; the outermost EndBatch publishes.
--
-- After compile, hot paths read state.Values[id] directly; Ids, Specs and Order (names in
-- declaration order, the settings layout) are public too. Nothing outside this file writes them.
--
-- A row changes only if its value at publish differs from its baseline: its value when the batch
-- first touched it, or, for a watcher registered later in the same batch, its value when that
-- watcher registered. So writing a value and writing it back notifies no one, and a watcher never
-- reacts to a write made before it existed. A rule registered inside a batch takes its first
-- verdict when that batch publishes, so what modules do while starting can't depend on the order
-- they were declared in. Watchers run in registration order, once per publish however many of
-- their rows changed. Their writes publish in a further round; a batch still scheduling watchers
-- after MaxPublishRounds is reported, never looped forever. Persisted rows store only values
-- that differ from the default, so a changed default applies.

local MaxPublishRounds = 8
local Kinds = { boolean = true, number = true, string = true }

local ByteTerrace = ByteTerrace
local Report, Refuse = ByteTerrace.Report, ByteTerrace.Refuse
local SafeCall, SortedKeys = ByteTerrace.SafeCall, ByteTerrace.SortedKeys
local issecretvalue = issecretvalue
local ipairs, pairs, tostring, type = ipairs, pairs, tostring, type
local concat, remove, sort = table.concat, table.remove, table.sort
local floor, huge = math.floor, math.huge

local State = {}
State.__index = State
ByteTerrace.State = State

local function IsWhole(x)
    return x - floor(x + 0.5) < 1e-9 and floor(x + 0.5) - x < 1e-9
end

local function Admits(spec, value)
    if type(value) ~= spec.kind then
        return false, "expects " .. spec.kind .. ", got " .. type(value)
    end
    if spec.kind == "number" and (value ~= value or value == huge or value == -huge) then
        return false, "expects a finite number, got " .. tostring(value)
    end
    if spec.valueSet and not spec.valueSet[value] then
        return false, "expects one of " .. concat(spec.values, ", ") .. ", got " .. tostring(value)
    end
    if spec.min and value < spec.min then
        return false, "expects at least " .. spec.min .. ", got " .. value
    end
    if spec.max and value > spec.max then
        return false, "expects at most " .. spec.max .. ", got " .. value
    end
    if spec.step and not IsWhole((value - (spec.min or 0)) / spec.step) then
        return false, "expects a multiple of " .. spec.step .. ", got " .. value
    end
    return true
end

-- Appends every problem with one declaration to problems, and fills in the spec's derived keys
-- (valueSet, persist, scope).
local function Validate(name, spec, problems)
    local function AddProblem(message)
        problems[#problems + 1] = name .. ": " .. message
    end
    if not Kinds[spec.kind] then
        AddProblem("unknown kind " .. tostring(spec.kind))
        return
    end
    if spec.values and spec.kind ~= "string" then
        AddProblem("values only apply to string rows")
    end
    if (spec.min or spec.max or spec.step) and spec.kind ~= "number" then
        AddProblem("min / max / step only apply to number rows")
    end
    if spec.values then
        spec.valueSet = {}
        for _, value in ipairs(spec.values) do
            spec.valueSet[value] = true
        end
    end
    if spec.persist == nil then
        spec.persist = true
    end
    spec.scope = spec.scope or "account"
    if spec.scope ~= "account" and spec.scope ~= "character" then
        AddProblem("unknown scope " .. tostring(spec.scope))
    end
    local ok, why = Admits(spec, spec.default)
    if not ok then
        AddProblem("default " .. why)
    end
    if spec.lockedBy ~= nil and type(spec.lockedBy) ~= "string" then
        AddProblem("lockedBy must be a row name")
    end
    if spec.section ~= nil and type(spec.section) ~= "string" then
        AddProblem("section must be a string")
    end
    if spec.label and spec.persist then
        local control = spec.kind == "boolean" or (spec.kind == "string" and spec.values)
            or (spec.kind == "number" and spec.min and spec.max)
        if not control then
            local needs = spec.kind == "string" and "values" or "min and max"
            AddProblem(("a labeled %s row needs %s for its settings control"):format(spec.kind, needs))
        end
    end
end

-- "Module.row" -> "Module".
local function ModuleOf(name)
    return type(name) == "string" and name:match("^([^.]+)%.") or nil
end

-- A watcher is due for row id if the row's value differs from that watcher's baseline.
local function Due(watcher, id, value)
    local baseline = watcher.baseline
    if baseline then
        local base = baseline[id]
        if base ~= nil then
            return base ~= value
        end
    end
    return true
end

-- One round's bookkeeping: bumps versions of rows that really changed and schedules their due
-- watchers (each once). Returns how many it scheduled.
local function Settle(self, list, stamp)
    local values, original, isTouched = self.Values, self.m_original, self.m_isTouched
    local versions, watchersByRow = self.m_versions, self.m_watchersByRow
    local scheduled, count = self.m_scheduled, 0
    for i = 1, #list do
        local id = list[i]
        list[i] = nil
        isTouched[id] = nil
        local value = values[id]
        if value ~= original[id] then
            versions[id] = versions[id] + 1
            local watchers = watchersByRow[id]
            if watchers then
                for j = 1, #watchers do
                    local watcher = watchers[j]
                    if watcher.stamp ~= stamp and Due(watcher, id, value) then
                        watcher.stamp = stamp
                        count = count + 1
                        scheduled[count] = watcher
                    end
                end
            end
        end
        original[id] = nil
    end
    return count
end

-- Insertion sort by registration sequence: the scheduled list is short.
local function SortScheduled(scheduled, count)
    for i = 2, count do
        local watcher, j = scheduled[i], i - 1
        while j >= 1 and scheduled[j].seq > watcher.seq do
            scheduled[j + 1] = scheduled[j]
            j = j - 1
        end
        scheduled[j + 1] = watcher
    end
end

local function Publish(self)
    self.m_batchDepth = self.m_batchDepth + 1

    local scheduled, deferred = self.m_scheduled, self.m_deferred
    for _ = 1, MaxPublishRounds do
        -- Rules registered during the batch (or by a watcher last round) take their first verdict
        -- from the state as it stands, before this round's changes are delivered.
        for i = 1, #deferred do
            local watcher = deferred[i]
            deferred[i] = nil
            if watcher.active then
                SafeCall(watcher.fn, self)
            end
        end
        local list = self.m_touchedList
        if #list == 0 then
            break
        end
        self.m_touchedList, self.m_spareList = self.m_spareList, list
        self.m_stamp = self.m_stamp + 1
        local count = Settle(self, list, self.m_stamp)
        SortScheduled(scheduled, count)
        for i = 1, count do
            local watcher = scheduled[i]
            scheduled[i] = nil
            if watcher.active then
                SafeCall(watcher.fn, self)
            end
        end
    end

    local unsettled = self.m_touchedList
    if #unsettled > 0 then
        -- Out of rounds. The leftover writes still count (versions move); only a batch that would
        -- run watchers yet again is a real loop, and it is reported rather than run.
        local names = {}
        for i = 1, #unsettled do
            names[i] = self.m_names[unsettled[i]]
        end
        self.m_stamp = self.m_stamp + 1
        local count = Settle(self, unsettled, self.m_stamp)
        for i = 1, count do
            scheduled[i] = nil
        end
        if count > 0 then
            Report(("%s: state did not settle after %d publish rounds; still changing: %s"):format(
                self.m_addon.Name, MaxPublishRounds, concat(names, ", ")))
        end
    end

    local baselined = self.m_baselined
    for i = 1, #baselined do
        baselined[i].baseline = nil
        baselined[i] = nil
    end
    self.m_batchDepth = self.m_batchDepth - 1
end

-- Registers a watcher. Inside a batch, rows the batch already touched get this watcher's own
-- baseline (their current value), so it never reacts to writes made before it registered.
local function Register(self, ids, fn)
    self.m_seq = self.m_seq + 1
    local watcher = { ids = ids, fn = fn, active = true, stamp = 0, seq = self.m_seq }
    for _, id in ipairs(ids) do
        local watchers = self.m_watchersByRow[id]
        if not watchers then
            watchers = {}
            self.m_watchersByRow[id] = watchers
        end
        watchers[#watchers + 1] = watcher
        if self.m_batchDepth > 0 and self.m_isTouched[id] then
            if not watcher.baseline then
                watcher.baseline = {}
                self.m_baselined[#self.m_baselined + 1] = watcher
            end
            watcher.baseline[id] = self.Values[id]
        end
    end
    return watcher
end

local function ResolveIds(self, rows)
    local ids = {}
    for i, row in ipairs(rows) do
        ids[i] = type(row) == "number" and row or self:Id(row)
    end
    return ids
end

local function RemoveFrom(list, item)
    for i = #list, 1, -1 do
        if list[i] == item then
            remove(list, i)
            return
        end
    end
end

--- Whether value passes spec's admission check (kind, finiteness, enum, bounds, step). Doesn't
--- check secrecy; callers refuse secrets first.
---@param spec table a validated row or field spec
---@return boolean ok
---@return string? why the reason when refused
State.Admits = Admits

--- Validates a row or field spec in place, appending each problem to problems. Records.lua uses
--- it for fields.
---@param name string the full name, for messages
---@param spec table
---@param problems string[]
State.Prepare = Validate

--- Creates an addon's state, empty and uncompiled.
---@param addon table the owning AddOn, for its name in messages
function ByteTerrace.NewState(addon)
    return setmetatable({
        Order = {},
        m_addon = addon,
        m_declared = {},
        m_compiled = false,
        m_batchDepth = 0,
        m_touchedList = {},    -- ids first touched this round, in order
        m_spareList = {},      -- the other half of the double buffer
        m_isTouched = {},      -- [id] = true while in m_touchedList
        m_original = {},       -- [id] = value when first touched
        m_watchersByRow = {},  -- [id] = array of watchers reading that row
        m_scheduled = {},      -- reused: watchers to run this round
        m_baselined = {},      -- watchers holding per-row baselines until the batch publishes
        m_deferred = {},       -- rules waiting for their batch's publish to take a first verdict
        m_seq = 0,
        m_stamp = 0,
    }, State)
end

--- Declares a row before compile. The spec is copied.
---@param name string "<Module>.<row>"
---@param spec table see the file header
function State:Declare(name, spec)
    if self.m_compiled then
        error(self.m_addon.Name .. ": state row " .. name .. " declared after compile", 2)
    end
    if self.m_declared[name] then
        error(self.m_addon.Name .. ": duplicate state row " .. name, 2)
    end
    local own = {}
    for key, value in pairs(spec) do
        own[key] = value
    end
    self.m_declared[name] = own
    self.Order[#self.Order + 1] = name
end

--- Assigns ids, validates every declaration (raising all problems at once) and loads persisted
--- values from stores.
---@param stores table { account = table, character = table? }
---@return string[] dropped saved keys reset because they no longer validate
---@return string[] unclaimed saved keys kept because no loaded module declares them
function State:Compile(stores)
    local problems = {}
    local names = SortedKeys(self.m_declared)
    local ids, specs, values, versions, modules = {}, {}, {}, {}, {}
    for id, name in ipairs(names) do
        local spec = self.m_declared[name]
        ids[name], specs[id], versions[id] = id, spec, 0
        modules[ModuleOf(name) or name] = true
        Validate(name, spec, problems)
        if spec.persist and not stores[spec.scope] then
            local variable = spec.scope == "character" and "savedVariablePerCharacter" or "savedVariable"
            problems[#problems + 1] = ("%s: scope %s needs the addon's %s"):format(name, spec.scope, variable)
        end
    end
    for id, name in ipairs(names) do
        local lockedBy = specs[id].lockedBy
        if lockedBy then
            local lockId = ids[lockedBy]
            if not lockId or specs[lockId].kind ~= "boolean" then
                problems[#problems + 1] = name .. ": lockedBy " .. tostring(lockedBy) .. " must name a boolean row"
            end
            specs[id].lockId = lockId
        end
    end
    Refuse(self.m_addon.Name .. " state", problems)

    local dropped, unclaimed = {}, {}
    for scope, store in pairs(stores) do
        for key, value in pairs(store) do
            local id = ids[key]
            if not id and not modules[ModuleOf(key) or ""] then
                unclaimed[#unclaimed + 1] = tostring(key)
            elseif id and specs[id].records then
                if specs[id].scope ~= scope or type(value) ~= "table" then
                    store[key] = nil
                    dropped[#dropped + 1] = tostring(key)
                end
            elseif not id or not specs[id].persist or specs[id].scope ~= scope or not Admits(specs[id], value) then
                store[key] = nil
                dropped[#dropped + 1] = tostring(key)
            end
        end
    end
    sort(dropped)
    sort(unclaimed)
    for id, name in ipairs(names) do
        local spec = specs[id]
        spec.store = spec.persist and stores[spec.scope] or nil
        local value = spec.store and spec.store[name]
        if value == nil then
            value = spec.default
        end
        values[id] = value
    end

    self.Ids, self.Specs, self.Values = ids, specs, values
    self.m_names, self.m_versions = names, versions
    self.m_declared = nil
    self.m_compiled = true
    return dropped, unclaimed
end

--- A row's id. An unknown name is an error.
---@param name string
---@return integer
function State:Id(name)
    local id = self.Ids[name]
    if not id then
        error(self.m_addon.Name .. ": unknown state row " .. tostring(name), 3)
    end
    return id
end

--- A row's value, by id or name.
---@param ref integer|string
function State:Get(ref)
    if type(ref) == "number" then
        return self.Values[ref]
    end
    return self.Values[self:Id(ref)]
end

--- Whether a row is locked (its lockedBy row is true).
---@param ref integer|string
---@return boolean
function State:IsLocked(ref)
    local spec = self.Specs[type(ref) == "number" and ref or self:Id(ref)]
    return spec.lockId ~= nil and self.Values[spec.lockId] == true
end

--- How many published changes a row has had since load.
---@param ref integer|string
---@return integer
function State:Version(ref)
    return self.m_versions[type(ref) == "number" and ref or self:Id(ref)]
end

--- Writes a row, validating the value first; outside a batch it publishes at once. Writing the
--- value a row already holds returns before any validation.
---@param ref integer|string
---@param level integer? the error level for a caller that wraps Set (Module:Set passes 2)
function State:Set(ref, value, level)
    local id = type(ref) == "number" and ref or self:Id(ref)
    local current = self.Values[id]
    -- Already validated, and never secret, since a secret can't equal a stored value.
    if current == value and current ~= nil then
        return
    end
    level = (level or 1) + 1
    local spec = self.Specs[id]
    if not spec then
        error(self.m_addon.Name .. ": unknown state row id " .. tostring(id), level)
    end
    if spec.lockId and self.Values[spec.lockId] then
        error(self.m_addon.Name .. ": state row " .. self.m_names[id] .. " is locked", level)
    end
    if issecretvalue(value) then
        error(self.m_addon.Name .. ": state row " .. self.m_names[id] .. " cannot hold a secret value", level)
    end
    local ok, why = Admits(spec, value)
    if not ok then
        error(self.m_addon.Name .. ": state row " .. self.m_names[id] .. " " .. why, level)
    end
    if not self.m_isTouched[id] then
        self.m_isTouched[id] = true
        self.m_original[id] = current
        self.m_touchedList[#self.m_touchedList + 1] = id
    end
    self.Values[id] = value
    local store = spec.store
    if store then
        if value == spec.default then
            store[self.m_names[id]] = nil
        else
            store[self.m_names[id]] = value
        end
    end
    if self.m_batchDepth == 0 then
        Publish(self)
    end
end

--- Flips a boolean row.
---@param ref integer|string
---@param level integer? as for Set
function State:Toggle(ref, level)
    local id = type(ref) == "number" and ref or self:Id(ref)
    if self.Specs[id].kind ~= "boolean" then
        error(self.m_addon.Name .. ": state row " .. self.m_names[id] .. " is not boolean", (level or 1) + 1)
    end
    self:Set(id, not self.Values[id], (level or 1) + 1)
end

--- Opens a batch; batches nest, and the outermost EndBatch publishes.
function State:BeginBatch()
    self.m_batchDepth = self.m_batchDepth + 1
end

--- Closes a batch. An EndBatch without a BeginBatch is an error.
function State:EndBatch()
    if self.m_batchDepth <= 0 then
        error(self.m_addon.Name .. ": EndBatch without BeginBatch", 2)
    end
    self.m_batchDepth = self.m_batchDepth - 1
    if self.m_batchDepth == 0 and (#self.m_touchedList > 0 or #self.m_deferred > 0) then
        Publish(self)
    end
end

--- Calls fn(state) now (unless skipInitial) and after every publish in which one of the rows
--- changed.
---@param rows (integer|string)[]
---@param fn fun(state: table)
---@param skipInitial boolean?
---@return table watcher for Unwatch
function State:Watch(rows, fn, skipInitial)
    local watcher = Register(self, ResolveIds(self, rows), fn)
    if not skipInitial then
        SafeCall(fn, self)
    end
    return watcher
end

--- Stops a watcher or rule; it doesn't run again, even later in a publish in progress.
---@param watcher table from Watch or Rule
function State:Unwatch(watcher)
    if not watcher.active then
        return
    end
    watcher.active = false
    for _, id in ipairs(watcher.ids) do
        RemoveFrom(self.m_watchersByRow[id], watcher)
    end
end

--- A verdict over rows. changed runs whenever the verdict flips; with spec.initial it also runs
--- once with the first verdict. Registered inside a batch, the first verdict is taken when the
--- batch publishes.
---@param spec table { reads, when(state) -> boolean, changed(active, state), initial? }
---@return table watcher for Unwatch
function State:Rule(spec)
    local verdict
    local when, changed, initial = spec.when, spec.changed, spec.initial
    local watcher = Register(self, ResolveIds(self, spec.reads), function(state)
        local now = when(state) and true or false
        if verdict == nil then
            verdict = now
            if initial then
                changed(now, state)
            end
        elseif now ~= verdict then
            verdict = now
            changed(now, state)
        end
    end)
    if self.m_batchDepth > 0 then
        self.m_deferred[#self.m_deferred + 1] = watcher
    else
        SafeCall(watcher.fn, self)
    end
    return watcher
end
