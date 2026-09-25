-- State: declared, typed rows with one admission path, change versions, and one publication
-- pass per batch.
--
--   Declare(name, spec)  before compile. spec: kind ("boolean" | "number" | "string"), default,
--                        values (string enum), min / max (number), persist (default true),
--                        label / description (shown in settings), valueLabels (enum display).
--   Compile(saved)       sorts names to dense ids, validates every declaration (all problems
--                        reported at once), and loads persisted values: rows no longer declared
--                        and values that no longer validate are dropped.
--   Get / Set / Toggle   by id (hot paths) or name (boundaries). Every write is validated; a
--                        secret value is refused, since rules compute over rows.
--   Watch / Rule         run after a publish in which one of their rows changed.
--
-- A row changes only if its value at publish differs from its value when the batch first touched
-- it; writing a value and writing it back notifies no one. Watchers run in registration order,
-- once per publish however many of their rows changed. Writes they make publish in a further
-- round; a batch that hasn't settled after MAX_PUBLISH_ROUNDS is reported, never looped forever.
-- Persisted rows store only values that differ from the default, so a changed default applies.

local ByteTerrace = ByteTerrace
local Report, Refuse, SortedKeys = ByteTerrace.Report, ByteTerrace.Refuse, ByteTerrace.SortedKeys
local issecretvalue = issecretvalue
local ipairs, pairs, pcall, tostring, type = ipairs, pairs, pcall, tostring, type
local concat, sort = table.concat, table.sort

local MAX_PUBLISH_ROUNDS = 8
local KINDS = { boolean = true, number = true, string = true }

local State = {}
State.__index = State
ByteTerrace.State = State

function ByteTerrace.NewState(addon)
    return setmetatable({
        addon = addon,
        declared = {},
        order = {},          -- names in declaration order (settings layout)
        compiled = false,
        batchDepth = 0,
        touchedList = {},    -- ids first touched this round, in order
        spareList = {},      -- the other half of the double buffer
        isTouched = {},      -- [id] = true while in touchedList
        original = {},       -- [id] = value when first touched
        watchersByRow = {},  -- [id] = array of watchers
        pending = {},        -- reusable array of watchers to run
        watcherCount = 0,
        stamp = 0,
    }, State)
end

function State:Declare(name, spec)
    if self.compiled then
        error(self.addon.name .. ": state row " .. name .. " declared after compile", 2)
    end
    if self.declared[name] then
        error(self.addon.name .. ": duplicate state row " .. name, 2)
    end
    self.declared[name] = spec
    self.order[#self.order + 1] = name
end

local function Admits(spec, value)
    if type(value) ~= spec.kind then
        return false, "expects " .. spec.kind .. ", got " .. type(value)
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
    return true
end
State.Admits = Admits

function State:Compile(saved)
    local problems = {}
    local names = SortedKeys(self.declared)
    local ids, specs, values, versions = {}, {}, {}, {}
    for id, name in ipairs(names) do
        local spec = self.declared[name]
        ids[name], specs[id], versions[id] = id, spec, 0
        if not KINDS[spec.kind] then
            problems[#problems + 1] = name .. ": unknown kind " .. tostring(spec.kind)
        else
            if spec.values then
                spec.valueSet = {}
                for _, value in ipairs(spec.values) do
                    spec.valueSet[value] = true
                end
            end
            if spec.persist == nil then
                spec.persist = true
            end
            local ok, why = Admits(spec, spec.default)
            if not ok then
                problems[#problems + 1] = name .. ": default " .. why
            end
        end
    end
    Refuse(self.addon.name .. " state", problems)

    local dropped = {}
    for key, value in pairs(saved) do
        local id = ids[key]
        if not id or not specs[id].persist or not Admits(specs[id], value) then
            saved[key] = nil
            dropped[#dropped + 1] = tostring(key)
        end
    end
    sort(dropped)
    for id, name in ipairs(names) do
        local value = saved[name]
        if value == nil then
            value = specs[id].default
        end
        values[id] = value
    end

    self.ids, self.names, self.specs, self.values, self.versions, self.saved = ids, names, specs, values, versions, saved
    self.declared = nil
    self.compiled = true
    return dropped
end

function State:Id(name)
    local id = self.ids[name]
    if not id then
        error(self.addon.name .. ": unknown state row " .. tostring(name), 3)
    end
    return id
end

function State:Get(ref)
    if type(ref) == "number" then
        return self.values[ref]
    end
    return self.values[self:Id(ref)]
end

function State:Version(ref)
    return self.versions[type(ref) == "number" and ref or self:Id(ref)]
end

function State:Set(ref, value)
    local id = type(ref) == "number" and ref or self:Id(ref)
    local spec = self.specs[id]
    if issecretvalue(value) then
        error(self.addon.name .. ": state row " .. self.names[id] .. " cannot hold a secret value", 2)
    end
    local ok, why = Admits(spec, value)
    if not ok then
        error(self.addon.name .. ": state row " .. self.names[id] .. " " .. why, 2)
    end
    local current = self.values[id]
    if current == value then
        return
    end
    if not self.isTouched[id] then
        self.isTouched[id] = true
        self.original[id] = current
        self.touchedList[#self.touchedList + 1] = id
    end
    self.values[id] = value
    if spec.persist then
        if value == spec.default then
            self.saved[self.names[id]] = nil
        else
            self.saved[self.names[id]] = value
        end
    end
    if self.batchDepth == 0 then
        self:Publish()
    end
end

function State:Toggle(ref)
    local id = type(ref) == "number" and ref or self:Id(ref)
    self:Set(id, not self.values[id])
end

function State:BeginBatch()
    self.batchDepth = self.batchDepth + 1
end

function State:EndBatch()
    self.batchDepth = self.batchDepth - 1
    if self.batchDepth == 0 and #self.touchedList > 0 then
        self:Publish()
    end
end

local function ByRegistration(a, b)
    return a.index < b.index
end

function State:Publish()
    self.batchDepth = self.batchDepth + 1
    local values, original, isTouched, versions = self.values, self.original, self.isTouched, self.versions
    local pending = self.pending
    for _ = 1, MAX_PUBLISH_ROUNDS do
        local list = self.touchedList
        if #list == 0 then
            break
        end
        self.touchedList, self.spareList = self.spareList, list

        self.stamp = self.stamp + 1
        local stamp, count = self.stamp, 0
        for i = 1, #list do
            local id = list[i]
            list[i] = nil
            isTouched[id] = nil
            if values[id] ~= original[id] then
                versions[id] = versions[id] + 1
                local watchers = self.watchersByRow[id]
                if watchers then
                    for j = 1, #watchers do
                        local watcher = watchers[j]
                        if watcher.stamp ~= stamp then
                            watcher.stamp = stamp
                            count = count + 1
                            pending[count] = watcher
                        end
                    end
                end
            end
            original[id] = nil
        end

        if count > 1 then
            sort(pending, ByRegistration)
        end
        for i = 1, count do
            local watcher = pending[i]
            pending[i] = nil
            if watcher.active then
                local ok, err = pcall(watcher.fn, self)
                if not ok then
                    Report(err)
                end
            end
        end
    end

    local unsettled = self.touchedList
    if #unsettled > 0 then
        local names = {}
        for i = 1, #unsettled do
            local id = unsettled[i]
            names[i] = self.names[id]
            isTouched[id], original[id], unsettled[i] = nil, nil, nil
        end
        Report(self.addon.name .. ": state did not settle after " .. MAX_PUBLISH_ROUNDS
            .. " publish rounds; still changing: " .. concat(names, ", "))
    end
    self.batchDepth = self.batchDepth - 1
end

-- Calls fn(state) now (unless skipInitial) and after every publish in which one of the rows
-- changed. Returns a watcher to pass to Unwatch.
function State:Watch(rows, fn, skipInitial)
    local ids = {}
    for i, row in ipairs(rows) do
        ids[i] = type(row) == "number" and row or self:Id(row)
    end
    self.watcherCount = self.watcherCount + 1
    local watcher = { ids = ids, fn = fn, active = true, index = self.watcherCount, stamp = 0 }
    for _, id in ipairs(ids) do
        local watchers = self.watchersByRow[id]
        if not watchers then
            watchers = {}
            self.watchersByRow[id] = watchers
        end
        watchers[#watchers + 1] = watcher
    end
    if not skipInitial then
        local ok, err = pcall(fn, self)
        if not ok then
            Report(err)
        end
    end
    return watcher
end

function State:Unwatch(watcher)
    watcher.active = false
    for _, id in ipairs(watcher.ids) do
        local watchers = self.watchersByRow[id]
        for i = #watchers, 1, -1 do
            if watchers[i] == watcher then
                table.remove(watchers, i)
            end
        end
    end
end

-- A verdict over rows. spec: reads, when(state) -> boolean, changed(active, state).
-- changed runs whenever the verdict flips; with spec.initial it also runs once at registration.
function State:Rule(spec)
    local verdict
    local when, changed, initial = spec.when, spec.changed, spec.initial
    return self:Watch(spec.reads, function(state)
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
end
