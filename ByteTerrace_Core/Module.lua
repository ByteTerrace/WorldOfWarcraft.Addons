-- Module: one feature of an addon, declared with addon:Module (AddOn.lua), which validates the
-- spec and declares its rows, records, messages and commands.
--
-- A module owns what it creates through its methods: handlers (On), watchers (Watch, OnIncrease),
-- rules (Rule), message listeners (Listen) and timers (After, Every). Callback binds deferred UI
-- actions to one activation. Stopping removes subscriptions, expires actions, runs OnDisable,
-- and returns its runtime rows to their defaults, so a stopped module registers no events, runs
-- no code and leaves no stale facts.
--
-- Timers run their callback as one state batch, isolated like an event handler, and never after
-- the module stops: a retry scheduled by a feature the player just switched off doesn't fire.
--
-- Dependencies: a module with demand = true runs only while a running module names it in its
-- uses list. A user's dependencies start before its OnEnable, so their rows hold real values
-- when its rules take their first reading and their handlers for an event run before its own.
-- They stop after the last user stops. A failed start tears down its resources and releases the
-- dependencies it acquired; a failed dependency prevents its user from starting.
--
-- Public members: Name, Addon, Spec (the declaration, never changed), Enabled, Records ([name] =
-- collection), Comms (its messages, when spec.comms declares them) and Users (how many running
-- modules use a demand module).

local ByteTerrace = ByteTerrace
local SafeCall = ByteTerrace.SafeCall
local C_Timer = C_Timer
local ipairs, pairs, select, type, unpack = ipairs, pairs, select, type, unpack
local remove = table.remove

local Module = {}
Module.__index = Module
ByteTerrace.Module = Module

local function Enable(module)
    for _, dependency in ipairs(module.m_uses) do
        module.m_acquired = module.m_acquired + 1
        if not dependency:Acquire() then
            return false
        end
    end
    if module.Comms then
        module.Comms:Open()
    end
    if module.Spec.OnEnable then
        module.Spec.OnEnable(module)
    end
    return module.Enabled
end

--- Creates a module object; AddOn:Module declares everything else.
---@param addon table the owning AddOn
---@param name string
---@param spec table
---@return table module
function ByteTerrace.NewModule(addon, name, spec)
    return setmetatable({
        Addon = addon, Spec = spec, Enabled = false, Records = {}, Users = 0,
        Name = name, m_handles = {}, m_watchers = {}, m_timers = {}, m_ids = {}, m_runtime = {}, m_uses = {},
        m_listeners = {}, m_acquired = 0, m_generation = 0,
        m_stopping = false,
    }, Module)
end

--- Resolves "row" to "<Module>.row"; a name containing "." ("combat.active") is already absolute.
---@param row string
---@return string
function Module:RowName(row)
    return row:find(".", 1, true) and row or (self.Name .. "." .. row)
end

--- A row's id, from its name (resolved once and cached) or an id passed straight through. An
--- unknown row is an error.
---@param row integer|string
---@param level integer? the error level for a caller that wraps Id (1, the default, is Id's caller)
---@return integer
function Module:Id(row, level)
    if type(row) == "number" then
        return row
    end
    local id = self.m_ids[row]
    if not id then
        id = self.Addon.State.Ids[self:RowName(row)]
        if not id then
            error(self.Addon.Name .. ": unknown state row " .. self:RowName(row), (level or 1) + 1)
        end
        self.m_ids[row] = id
    end
    return id
end

--- A row's value.
---@param row integer|string relative to the module unless it contains "."
function Module:Get(row)
    return self.Addon.State.Values[self:Id(row, 2)]
end

--- Writes a row through State:Set; errors point at the caller.
---@param row integer|string
function Module:Set(row, value)
    self.Addon.State:Set(self:Id(row, 2), value, 2)
end

--- Whether the module can accept work; OnDisable and dependency teardown are already stopped.
---@return boolean
function Module:IsRunning()
    return self.Enabled and not self.m_stopping
end

--- Raises when the module is stopped or stopping (in OnDisable): what it would create then would
--- outlive it.
function Module:CheckRunning()
    if not self:IsRunning() then
        error(self.Addon.Name .. ": module " .. self.Name .. " is stopped", 3)
    end
end

--- Adds an event handler that the module owns: it's removed when the module stops.
---@param event string
---@param fn function
---@param unit string?
---@return table handle for Off
function Module:On(event, fn, unit)
    self:CheckRunning()
    local handle = self.Addon.Events:On(event, fn, unit)
    self.m_handles[#self.m_handles + 1] = handle
    return handle
end

--- Removes a handler early and releases its ownership entry, so repeated subscriptions don't
--- grow the module's teardown work or retain dead callbacks.
---@param handle table from On
function Module:Off(handle)
    self.Addon.Events:Off(handle)
    for i = #self.m_handles, 1, -1 do
        if self.m_handles[i] == handle then
            remove(self.m_handles, i)
            break
        end
    end
end

--- Resolves a list of rows to ids.
---@param rows (integer|string)[]
---@param level integer? as for Id
---@return integer[]
function Module:ResolveRows(rows, level)
    local ids = {}
    for i, row in ipairs(rows) do
        ids[i] = self:Id(row, (level or 1) + 1)
    end
    return ids
end

--- State:Watch, owned by the module.
---@param rows (integer|string)[]
---@param fn fun(state: table)
---@param skipInitial boolean?
---@return table watcher
function Module:Watch(rows, fn, skipInitial)
    self:CheckRunning()
    local state = self.Addon.State
    local watcher = state:Watch(self:ResolveRows(rows, 2), fn, true)
    self.m_watchers[#self.m_watchers + 1] = watcher
    if not skipInitial then
        SafeCall(fn, state) -- ownership precedes a callback that may stop this module
    end
    return watcher
end

--- Calls fn(state, count, previous) after each publish in which a count row went up: how a
--- feature reacts to something that happened (a kill, a death, a star) rather than to a value.
--- A count that goes down (a stopped module resetting its rows) is only remembered.
---@param row integer|string a number row
---@param fn fun(state: table, count: number, previous: number)
---@return table watcher
function Module:OnIncrease(row, fn)
    local id = self:Id(row, 2)
    local last = self.Addon.State.Values[id]
    return self:Watch({ id }, function(state)
        local count, previous = state.Values[id], last
        last = count
        if count > previous then
            fn(state, count, previous)
        end
    end, true)
end

--- State:Rule, owned by the module; reads may be relative row names.
---@param spec table { reads, when, changed, initial? }
---@return table watcher
function Module:Rule(spec)
    self:CheckRunning()
    local state, reads = self.Addon.State, self:ResolveRows(spec.reads, 2)
    state:BeginBatch()
    local watcher = state:Rule({
        reads = reads, when = spec.when, changed = spec.changed, initial = spec.initial,
    })
    self.m_watchers[#self.m_watchers + 1] = watcher
    state:EndBatch()
    return watcher
end

--- Listens to a shared transport while this module runs. Stopping removes the listener, even
--- during a delivery; enabling again registers a fresh listener from OnEnable.
---@param comms table a module's Comms
---@param kind string uppercase message kind
---@param fn fun(sender: string, fields: string[])
function Module:Listen(comms, kind, fn)
    self:CheckRunning()
    local handle = comms:Listen(kind, fn)
    self.m_listeners[#self.m_listeners + 1] = { comms = comms, handle = handle }
    return handle
end

--- Binds an action and its arguments to this activation of the module. The returned callback
--- runs in one state batch and ignores invocation arguments (such as a menu's context). After
--- the module stops it does nothing, even if the module starts again: old UI stays inert.
--- Returns no value: Blizzard_Menu's Pick treats a truthy return as a response override.
---@param fn function
---@return function
function Module:Callback(fn, ...)
    self:CheckRunning()
    if type(fn) ~= "function" then
        error("Callback needs a function", 2)
    end
    local generation, args, count = self.m_generation, { ... }, select("#", ...)
    return function()
        if not self:IsRunning() or self.m_generation ~= generation then
            return
        end
        self.Addon:Batch(fn, unpack(args, 1, count))
    end
end

--- Calls fn() once after seconds, as one state batch, unless the module stops (or Cancel) first.
--- Scheduling on a stopped or stopping module (from OnDisable) is an error, as for On, Watch and
--- Rule.
---@param seconds number
---@param fn function
---@return table timer for Cancel
function Module:After(seconds, fn)
    self:CheckRunning()
    local timers, addon = self.m_timers, self.Addon
    local timer
    timer = C_Timer.NewTimer(seconds, function()
        timers[timer] = nil
        addon:Batch(fn)
    end)
    timers[timer] = true
    return timer
end

--- Calls fn() every seconds, each call one state batch, until Cancel or the module stops.
---@param seconds number
---@param fn function
---@return table timer for Cancel
function Module:Every(seconds, fn)
    self:CheckRunning()
    local addon = self.Addon
    local timer = C_Timer.NewTicker(seconds, function()
        addon:Batch(fn)
    end)
    self.m_timers[timer] = true
    return timer
end

--- Cancels a timer from After or Every; nil, or a timer that already ran, is ignored.
---@param timer table?
function Module:Cancel(timer)
    if timer and self.m_timers[timer] then
        self.m_timers[timer] = nil
        timer:Cancel()
    end
end

--- How many of the module's timers are pending.
---@return integer
function Module:PendingTimers()
    local count = 0
    for _ in pairs(self.m_timers) do
        count = count + 1
    end
    return count
end

-- Returns the module's runtime rows to their defaults.
local function ResetRuntime(module)
    local state = module.Addon.State
    for _, id in ipairs(module.m_runtime) do
        state:Set(id, state.Specs[id].default)
    end
end

--- Starts a demand module for one more user. Answers whether it runs: not while it's stopping,
--- so a user started from its OnDisable doesn't run on it.
---@return boolean
function Module:Acquire()
    self.Users = self.Users + 1
    if self.Users == 1 then
        self:SetEnabled(true)
    end
    return self:IsRunning()
end

--- Releases one user of a demand module; the last one stops it. Only a stopping user calls it,
--- once for each Acquire it made.
function Module:Release()
    self.Users = self.Users - 1
    if self.Users == 0 then
        self:SetEnabled(false)
    end
end

--- Starts or stops the module as one state batch. A failed start tears down its resources and
--- releases the dependencies it acquired. Stopping removes subscriptions, runs OnDisable,
--- cancels timers, resets runtime rows, and releases dependencies.
---@param enabled boolean
function Module:SetEnabled(enabled)
    if enabled == self.Enabled or self.m_stopping then
        return -- a stop in progress finishes first; a nested start or stop is ignored
    end
    local addon, spec = self.Addon, self.Spec
    addon.State:BeginBatch()
    if enabled then
        self.Enabled = true
        self.m_generation = self.m_generation + 1
        local ok, started = SafeCall(Enable, self)
        if not ok or not started then
            self:SetEnabled(false)
        end
        addon.State:EndBatch()
        return
    end
    self.m_stopping = true
    local handles, watchers = self.m_handles, self.m_watchers
    self.m_handles, self.m_watchers = {}, {}
    for i = 1, #watchers do
        addon.State:Unwatch(watchers[i])
    end
    addon.Events:OffAll(handles)
    for _, listener in ipairs(self.m_listeners) do
        listener.comms:Unlisten(listener.handle)
    end
    self.m_listeners = {}
    if self.Comms then
        self.Comms:Close()
    end
    if spec.OnDisable then
        SafeCall(spec.OnDisable, self)
    end
    addon.Input:Release(self) -- its maps, even when OnDisable failed to give the controller back
    for timer in pairs(self.m_timers) do
        self.m_timers[timer] = nil
        timer:Cancel()
    end
    addon:Batch(ResetRuntime, self)
    self.Enabled = false
    for i = self.m_acquired, 1, -1 do
        self.m_uses[i]:Release()
    end
    self.m_acquired = 0
    self.m_stopping = false
    addon.State:EndBatch()
end

--- Resolves what the module needs to start and stop: its dependencies and its runtime rows.
--- AddOn:Start prepares every module before starting any, since a user may start a dependency
--- declared after it.
---@param uses table[] the modules its spec.uses names, resolved by AddOn:ResolveUses
function Module:Prepare(uses)
    self.m_uses = uses
    self.m_runtime = {}
    for _, row in ipairs(self.Spec.state or {}) do
        if row.persist == false then
            self.m_runtime[#self.m_runtime + 1] = self:Id(row.name)
        end
    end
end

--- Connects the module to its enabled row and active rule. A module runs while its enabled row
--- (if it has one) is true and its spec.active rule (if any) holds; that's how a module depends
--- on other rows, so a switched-off feature registers nothing. A demand module waits for users.
function Module:Start()
    local spec, state = self.Spec, self.Addon.State
    if spec.demand then
        return
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
