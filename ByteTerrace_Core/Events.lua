-- Events: one dispatcher frame per addon.
--
--   On(event, fn, unit)  fn(...) receives the event payload. With unit, only that unit's events
--                        arrive. Returns a handle for Off.
--   Off(handle)
--
-- An event is registered with the client only while a handler wants it, so a disabled module
-- costs no dispatch. Unit filters compile to RegisterUnitEvent when at most two units are wanted.
-- Handler lists are copy-on-write: registration allocates, dispatch never does. Each handler is
-- isolated (an error is reported and the rest still run), and a whole dispatch is one state
-- batch, so the rows it writes publish once.

local ByteTerrace = ByteTerrace
local Report = ByteTerrace.Report
local CreateFrame, pcall = CreateFrame, pcall

local Events = {}
Events.__index = Events
ByteTerrace.Events = Events

function ByteTerrace.NewEvents(addon)
    local self = setmetatable({ addon = addon, handlers = {} }, Events)
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        self:Dispatch(event, ...)
    end)
    self.frame = frame
    return self
end

function Events:Refresh(event)
    local frame, list = self.frame, self.handlers[event]
    if frame:IsEventRegistered(event) then
        frame:UnregisterEvent(event)
    end
    if not list then
        return
    end
    local unit1, unit2, all
    for i = 1, #list do
        local unit = list[i].unit
        if not unit then
            all = true
        elseif unit ~= unit1 and unit ~= unit2 then
            if not unit1 then
                unit1 = unit
            elseif not unit2 then
                unit2 = unit
            else
                all = true
            end
        end
    end
    if all then
        frame:RegisterEvent(event)
    else
        frame:RegisterUnitEvent(event, unit1, unit2)
    end
end

function Events:On(event, fn, unit)
    local list = self.handlers[event]
    local copy = {}
    if list then
        for i = 1, #list do
            copy[i] = list[i]
        end
    end
    local handle = { event = event, fn = fn, unit = unit }
    copy[#copy + 1] = handle
    self.handlers[event] = copy
    self:Refresh(event)
    return handle
end

function Events:Off(handle)
    local list = self.handlers[handle.event]
    if not list then
        return
    end
    local copy = {}
    for i = 1, #list do
        if list[i] ~= handle then
            copy[#copy + 1] = list[i]
        end
    end
    self.handlers[handle.event] = #copy > 0 and copy or nil
    self:Refresh(handle.event)
end

function Events:Dispatch(event, ...)
    local list = self.handlers[event]
    if not list then
        return
    end
    local state = self.addon.state
    local unit = ...
    state:BeginBatch()
    for i = 1, #list do
        local handle = list[i]
        if not handle.unit or handle.unit == unit then
            local ok, err = pcall(handle.fn, ...)
            if not ok then
                Report(err)
            end
        end
    end
    state:EndBatch()
end
