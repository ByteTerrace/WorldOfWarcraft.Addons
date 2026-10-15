-- Diagnostics: the built-in debug command, for finding out what an addon is doing on a player's
-- machine without a debugger.
--
--   debug               toggles debug output (AddOn:Debug lines in chat).
--   debug status        modules running and stopped (a demand module with its users), events
--                       registered, watchers, pending timers, records, queued messages, and the
--                       errors SafeCall has caught.
--   debug events        each registered event with its dispatches since load (or reset), its
--                       handlers and its unit filter, busiest first; then publishes and watcher runs.
--   debug work          each module's work since load (or reset), busiest first: its event
--                       handler calls, timer callbacks, state-change callbacks, commands, message
--                       deliveries and deferred actions; "addon" is what the framework ran for no
--                       module (built-in commands, module switching). While profiling, also the
--                       time each module's callbacks took.
--   debug rows <text>   every row whose name contains text (runtime rows too): value and version.
--   debug trace <text>  prints each published change of the rows whose names contain text, until
--                       debug trace off. Untraced rows cost nothing.
--   debug cpu           the client's addon profiler for this addon: time per frame (recent,
--                       session, peak, encounter), its share of the game's time, the frames it took
--                       over 1 to 100 ms, and its memory. Blizzard's AddOn list shows the same.
--                       The framework's own work counts under ByteTerrace_Core, shown after it.
--   debug profile       toggles profiling: from then on each dispatched callback is timed with
--                       debugprofilestop and its time added to its module's work. Times start at
--                       zero; a callback's time includes what it runs synchronously (a message
--                       listener's time is inside the transport's event handler too). Off by
--                       default, and while off nothing is timed.
--   debug reset         zeroes the event, publish, watcher and work counts.
--
-- The counts it reads are always kept: an integer increment per dispatch and per publish, and a
-- field increment on the work record the dispatched handler, watcher, timer or command holds.

local MaxLines = 40
local CoreName = "ByteTerrace_Core" -- the framework's addon: its dispatch and publishes are counted there
-- A work record's counts (Core.lua) in report order, with the word for one.
local WorkKinds = {
    { "events", "event" }, { "timers", "timer" }, { "changes", "change" }, { "commands", "command" },
    { "messages", "message" }, { "actions", "action" },
}

local ByteTerrace = ByteTerrace
local C_AddOnProfiler, Enum, GetAddOnMemoryUsage = C_AddOnProfiler, Enum, GetAddOnMemoryUsage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local ipairs, pairs, print, tostring = ipairs, pairs, print, tostring
local concat, sort = table.concat, table.sort

local AddOn = ByteTerrace.AddOn

local function Plural(count, word)
    return ("%d %s%s"):format(count, word, count == 1 and "" or "s")
end

-- Rows whose names contain text, ignoring case, in name order.
local function MatchingRows(state, text)
    local wanted, ids = text:lower(), {}
    for name, id in pairs(state.Ids) do
        if name:lower():find(wanted, 1, true) then
            ids[#ids + 1] = id
        end
    end
    sort(ids)
    return ids
end

local function Status(addon)
    local running, stopped, timers, collections, queued = {}, {}, 0, {}, {}
    for _, name in ipairs(ByteTerrace.SortedKeys(addon.Modules)) do
        local module = addon.Modules[name]
        if module.Enabled then
            running[#running + 1] = module.Spec.demand and ("%s (%d)"):format(name, module.Users) or name
        else
            stopped[#stopped + 1] = name
        end
        timers = timers + module:PendingTimers()
        for _, recordsName in ipairs(ByteTerrace.SortedKeys(module.Records)) do
            local records = module.Records[recordsName]
            collections[#collections + 1] = ("%s %d/%d"):format(records.Name, records:Count(), records.Limit)
        end
        if module.Comms then
            queued[#queued + 1] = ("%s %d"):format(name, module.Comms:Queued())
        end
    end
    local events = 0
    for _ in pairs(addon.Events:Registrations()) do
        events = events + 1
    end
    addon:Print(("%s %s: %s, %s, %s, %s; %s caught in ByteTerrace addons since load.")
        :format(addon.Title, tostring(addon.Version), Plural(#running, "module") .. " running",
            Plural(events, "event") .. " registered", Plural(addon.State:WatcherCount(), "watcher"),
            Plural(timers, "timer") .. " pending", Plural(ByteTerrace.Errors, "error")))
    print("  Running (demand modules with their users): " .. (#running > 0 and concat(running, ", ") or "none"))
    print("  Stopped: " .. (#stopped > 0 and concat(stopped, ", ") or "none"))
    if #collections > 0 then
        print("  Records: " .. concat(collections, ", "))
    end
    if #queued > 0 then
        print("  Messages queued: " .. concat(queued, ", "))
    end
end

local function EventsReport(addon)
    local events, counts = addon.Events, addon.Events.Counts
    local registrations, names = events:Registrations(), {}
    for event in pairs(registrations) do
        names[#names + 1] = event
    end
    sort(names, function(a, b)
        local countA, countB = counts[a] or 0, counts[b] or 0
        if countA ~= countB then
            return countA > countB
        end
        return a < b
    end)
    addon:Print(("%s registered; dispatches since load or reset:"):format(Plural(#names, "event")))
    for i, event in ipairs(names) do
        if i > MaxLines then
            print(("  ... and %d more"):format(#names - MaxLines))
            break
        end
        -- "player|target": a raw "|" would start one of chat's escape codes.
        local units = registrations[event] ~= "all" and (registrations[event]:gsub("|$", ""):gsub("|", ", "))
        local filter = units and (" [" .. units .. "]") or ""
        print(("  %s%s: %d, %s"):format(event, filter, counts[event] or 0, Plural(events:HandlerCount(event), "handler")))
    end
    local stateCounts = addon.State.Counts
    print(("  %d publishes, %d watcher runs."):format(stateCounts.publishes, stateCounts.watchers))
end

-- Every work record: [name] = work, "addon" for the addon's own.
local function WorkRecords(addon)
    local records = { addon = addon.Work }
    for name, module in pairs(addon.Modules) do
        records[name] = module.Work
    end
    return records
end

local function WorkTotal(work)
    local total = 0
    for _, kind in ipairs(WorkKinds) do
        total = total + work[kind[1]]
    end
    return total
end

local function WorkReport(addon)
    local records, names, totals, idle = WorkRecords(addon), {}, {}, {}
    for name, work in pairs(records) do
        totals[name] = WorkTotal(work)
        if totals[name] > 0 then
            names[#names + 1] = name
        else
            idle[#idle + 1] = name
        end
    end
    sort(names, function(a, b)
        if totals[a] ~= totals[b] then
            return totals[a] > totals[b]
        end
        return a < b
    end)
    sort(idle)
    local profiling = addon.Profiling
    addon:Print(("Work since load or reset, busiest first%s:"):format(profiling and "; time while profiling" or ""))
    for i, name in ipairs(names) do
        if i > MaxLines then
            print(("  ... and %d more"):format(#names - MaxLines))
            break
        end
        local work, parts = records[name], {}
        for _, kind in ipairs(WorkKinds) do
            if work[kind[1]] > 0 then
                parts[#parts + 1] = Plural(work[kind[1]], kind[2])
            end
        end
        local time = profiling and (", %.3f ms"):format(work.time) or ""
        print(("  %s: %d (%s)%s"):format(name, totals[name], concat(parts, ", "), time))
    end
    if #idle > 0 then
        print("  No work: " .. concat(idle, ", "))
    end
end

-- Turns profiling on (every work record's time from zero) or off.
local function Profile(addon)
    local on = not addon.Profiling
    if on then
        for _, work in pairs(WorkRecords(addon)) do
            work.time = 0
        end
    end
    addon.Profiling = on
    addon.Events:SetProfiling(on)
    if not on then
        addon:Print("Profiling off.")
        return
    end
    local slash = addon.Slash and addon.Slash[1] or ""
    addon:Print(("Profiling on: %s debug work shows each module's time. Turn it off with %s debug profile.")
        :format(slash, slash))
end

local function Rows(addon, text)
    local state = addon.State
    local ids = MatchingRows(state, text)
    addon:Print(("%s matching '%s':"):format(Plural(#ids, "row"), text))
    for i, id in ipairs(ids) do
        if i > MaxLines then
            print(("  ... and %d more; narrow the text"):format(#ids - MaxLines))
            break
        end
        local spec = state.Specs[id]
        print(("  %s = %s (%s, version %d)"):format(state:Name(id), tostring(state.Values[id]),
            spec.persist and "saved" or "runtime", state:Version(id)))
    end
end

local function Trace(addon, text)
    local state = addon.State
    if text == "off" then
        state:Trace(nil)
        addon:Print("Trace off.")
        return
    end
    local ids = MatchingRows(state, text)
    if #ids == 0 then
        addon:Print(("No row matches '%s'."):format(text))
        return
    end
    state:Trace(ids, function(name, old, new)
        print(("|cff999999[trace]|r %s: %s -> %s"):format(name, tostring(old), tostring(new)))
    end)
    addon:Print(("Tracing %s matching '%s'. Stop with %s debug trace off."):format(Plural(#ids, "row"), text,
        addon.Slash and addon.Slash[1] or ""))
end

-- An addon's time per frame for metric, and its share as Blizzard's AddOn list computes it: its
-- time against the game's time outside other addons.
local function Share(name, metric)
    local mine = C_AddOnProfiler.GetAddOnMetric(name, metric)
    local total = C_AddOnProfiler.GetApplicationMetric(metric) - C_AddOnProfiler.GetOverallMetric(metric) + mine
    return ("%.3f ms (%.2f%%)"):format(mine, total > 0 and mine / total * 100 or 0)
end

local function Cpu(addon)
    local name, profiling = addon.Name, C_AddOnProfiler.IsEnabled()
    if not profiling then
        addon:Print("The client's addon profiler is off.")
    else
        local metrics = Enum.AddOnProfilerMetric
        addon:Print("Time per frame: recent " .. Share(name, metrics.RecentAverageTime) .. ", session "
            .. Share(name, metrics.SessionAverageTime) .. ", peak " .. Share(name, metrics.PeakTime) .. ", encounters "
            .. Share(name, metrics.EncounterAverageTime) .. ".")
        local over = {}
        for _, limit in ipairs({ 1, 5, 10, 50, 100 }) do
            over[#over + 1] = ("%d ms: %d"):format(limit, C_AddOnProfiler.GetAddOnMetric(name, metrics["CountTimeOver" .. limit .. "Ms"]))
        end
        print("  Frames over " .. concat(over, ", "))
    end
    UpdateAddOnMemoryUsage()
    print(("  Memory: %.0f KB"):format(GetAddOnMemoryUsage(name)))
    -- The framework's dispatch, publishes and records run in ByteTerrace_Core, counted there.
    if name ~= CoreName then
        local time = profiling and (" recent " .. Share(CoreName, Enum.AddOnProfilerMetric.RecentAverageTime) .. ",") or ""
        print(("  %s, shared by every ByteTerrace addon:%s %.0f KB"):format(CoreName, time, GetAddOnMemoryUsage(CoreName)))
    end
end

--- The debug command: no argument toggles debug output; otherwise a report (see the file header).
---@param arg string?
function AddOn:DebugCommand(arg)
    local word, rest = (arg or ""):match("^(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "" then
        self.State:Toggle(self.m_debugId)
        self:Print("Debug output", self.State.Values[self.m_debugId] and "enabled." or "disabled.")
    elseif word == "status" then
        Status(self)
    elseif word == "events" then
        EventsReport(self)
    elseif word == "work" then
        WorkReport(self)
    elseif word == "rows" and rest ~= "" then
        Rows(self, rest)
    elseif word == "trace" and rest ~= "" then
        Trace(self, rest:lower() == "off" and "off" or rest)
    elseif word == "cpu" then
        Cpu(self)
    elseif word == "profile" then
        Profile(self)
    elseif word == "reset" then
        local counts = self.State.Counts
        counts.publishes, counts.watchers = 0, 0
        for event in pairs(self.Events.Counts) do
            self.Events.Counts[event] = nil
        end
        for _, work in pairs(WorkRecords(self)) do
            for key in pairs(work) do
                work[key] = 0
            end
        end
        self:Print("Counts reset.")
    else
        local usage = "Usage: %s debug [status | events | work | rows <text> | trace <text> | trace off | cpu | profile | reset]"
        self:Print(usage:format(self.Slash and self.Slash[1] or ""))
    end
end
