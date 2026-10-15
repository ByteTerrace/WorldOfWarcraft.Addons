-- Events: one dispatcher frame per addon.
--
--   On(event, fn, unit)  fn(...) receives the event payload. With unit, only that unit's events
--                        arrive. Returns a handle for Off.
--   Off(handle)          the handle stops receiving immediately, including the rest of a dispatch
--                        already in progress.
--   OffAll(handles)      Off for many handles, rebuilding each affected event once.
--
-- An event is registered with the client only while a handler wants it, so a disabled module
-- costs no dispatch; the registration is only touched when what's wanted actually changes. Unit
-- filters compile to RegisterUnitEvent when at most two units are wanted. Handler lists are
-- copy-on-write: registration allocates, dispatch never does. Each handler is isolated (an error
-- reaches the error handler with its stack, and the rest still run), and a whole dispatch is one
-- state batch, so the rows it writes publish once.
--
-- Frame, the dispatcher frame, is public so tests can ask what's registered, and Counts ([event] =
-- dispatches since load or the last debug reset) feeds debug events. Handles are opaque.

local ByteTerrace = ByteTerrace
local SafeCall = ByteTerrace.SafeCall
local CreateFrame, issecretvalue, pairs, pcall = CreateFrame, issecretvalue, pairs, pcall

local Events = {}
Events.__index = Events
ByteTerrace.Events = Events

-- The registration an event's handlers want: "all", a "unit1|unit2" key (units in sorted order, so
-- the same set always gives the same key), or nil for none. Also whether any handler filters.
local function Wanted(list)
    if not list then
        return nil
    end
    local unit1, unit2, filtered, all
    for i = 1, #list do
        local unit = list[i].unit
        if not unit then
            all = true
        else
            filtered = true
            if unit ~= unit1 and unit ~= unit2 then
                if not unit1 then
                    unit1 = unit
                elseif not unit2 then
                    unit2 = unit
                else
                    all = true
                end
            end
        end
    end
    if all then
        return "all", nil, nil, filtered or false
    end
    if unit2 and unit2 < unit1 then
        unit1, unit2 = unit2, unit1
    end
    return unit1 .. "|" .. (unit2 or ""), unit1, unit2, filtered
end

-- Brings an event's client registration in line with what its handlers want, touching it only
-- when that changed.
local function Refresh(self, event)
    local key, unit1, unit2, filtered = Wanted(self.m_handlers[event])
    self.m_filtered[event] = filtered
    if key == self.m_registered[event] then
        return
    end
    local frame = self.Frame
    if self.m_registered[event] then
        frame:UnregisterEvent(event)
        self.m_registered[event] = nil -- stays accurate if registering below fails
    end
    if key == "all" then
        frame:RegisterEvent(event)
    elseif key then
        frame:RegisterUnitEvent(event, unit1, unit2)
    end
    self.m_registered[event] = key
end

local function Rebuild(self, event)
    local list, copy = self.m_handlers[event], {}
    if list then
        for i = 1, #list do
            if not list[i].dead then
                copy[#copy + 1] = list[i]
            end
        end
    end
    self.m_handlers[event] = #copy > 0 and copy or nil
    Refresh(self, event)
end

--- Creates an addon's dispatcher and its frame.
---@param addon table the owning AddOn, whose state batches each dispatch
function ByteTerrace.NewEvents(addon)
    local self = setmetatable({
        Counts = {}, m_addon = addon, m_handlers = {}, m_registered = {}, m_filtered = {},
    }, Events)
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        self:Dispatch(event, ...)
    end)
    self.Frame = frame
    return self
end

--- Adds a handler. An event the client refuses (an unknown name) is an error and leaves no trace.
---@param event string
---@param fn function receives the event payload
---@param unit string? only this unit's events arrive
---@return table handle for Off
function Events:On(event, fn, unit)
    local list = self.m_handlers[event]
    local copy = {}
    if list then
        for i = 1, #list do
            copy[i] = list[i]
        end
    end
    local handle = { event = event, fn = fn, unit = unit }
    copy[#copy + 1] = handle
    self.m_handlers[event] = copy
    local ok, err = pcall(Refresh, self, event)
    if not ok then
        self.m_handlers[event] = list
        pcall(Refresh, self, event)
        error(err, 0) -- the client's message already says where
    end
    return handle
end

--- Removes a handler, effective immediately; removing one twice does nothing.
---@param handle table from On
function Events:Off(handle)
    handle.dead = true
    Rebuild(self, handle.event)
end

--- Removes many handlers at once, rebuilding each affected event once.
---@param handles table[] from On
function Events:OffAll(handles)
    local events = {}
    for i = 1, #handles do
        local handle = handles[i]
        if not handle.dead then
            handle.dead = true
            events[handle.event] = true
        end
    end
    for event in pairs(events) do
        Rebuild(self, event)
    end
end

--- The client registration of every event some handler wants: [event] = "all" or "unit1|unit2".
--- A fresh table.
---@return table
function Events:Registrations()
    local registrations = {}
    for event, key in pairs(self.m_registered) do
        registrations[event] = key
    end
    return registrations
end

--- How many live handlers an event has.
---@param event string
---@return integer
function Events:HandlerCount(event)
    local list = self.m_handlers[event]
    return list and #list or 0
end

--- Runs an event's live handlers as one state batch. The frame's OnEvent calls it.
---@param event string
function Events:Dispatch(event, ...)
    local list = self.m_handlers[event]
    if not list then
        return
    end
    local counts = self.Counts
    counts[event] = (counts[event] or 0) + 1
    local state = self.m_addon.State
    local unit = ...
    -- A unit token that is itself secret can't be compared; filtered handlers can't claim it.
    local comparable = not self.m_filtered[event] or not issecretvalue(unit)
    state:BeginBatch()
    for i = 1, #list do
        local handle = list[i]
        if not handle.dead and (not handle.unit or (comparable and handle.unit == unit)) then
            SafeCall(handle.fn, ...)
        end
    end
    state:EndBatch()
end
