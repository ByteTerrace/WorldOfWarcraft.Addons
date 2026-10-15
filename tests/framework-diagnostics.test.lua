-- ByteTerrace framework: per-module work counts (debug work), their reset, profiling (debug
-- profile), and what counting costs a dispatch.

-- A harness with the framework loaded and a bare addon, not yet started.
local function NewAddOn()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local addon = h.env.ByteTerrace.NewAddOn({
        name = "TestApp", savedVariable = "TestDB", slash = { "/test" }, title = "Test AddOn", version = "1.0",
    })

    return h, addon
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp", false)
end

local function Printed(h)
    return table.concat(h.printed, "\n")
end

-- Bytes the Lua heap grows by per call of fn, with the collector stopped so nothing is freed.
local function BytesPerCall(fn, calls)
    collectgarbage("stop")
    local before = collectgarbage("count")

    for _ = 1, calls do
        fn()
    end
    local grown = (((collectgarbage("count") - before) * 1024) / calls)

    collectgarbage("restart")
    return grown
end

test("debug work counts each kind of work in the module it ran for, busiest first", function()
    local h, addon = NewAddOn()
    local chat = addon:Module("Chat", { comms = { prefix = "TestApp1" }, label = "Chat" })
    local action
    local busy = addon:Module("Busy", {
        commands = { { label = "Poke", name = "poke", run = function() end, slash = "poke" } },
        label = "Busy",
        OnEnable = function(module)
            module:On("PLAYER_TARGET_CHANGED", function() module:Set("count", module:Get("count") + 1) end)
            module:Watch({ "count" }, function() end, true)
            module:Rule({ changed = function() end, reads = { "count" },
                when = function(state) return (state:Get("Busy.count") > 1) end })
            module:Every(1, function() end)
            module:Listen(chat.Comms, "PING", function() end)
            action = module:Callback(function() end)
        end,
        state = { { default = 0, kind = "number", name = "count", persist = false } },
    })

    addon:Module("Quiet", { label = "Quiet" })
    Start(h)
    truthy(busy.Work.changes > 0, "the rule's first verdict counts as a change")
    h:Slash("/test debug reset")
    eq(busy.Work.changes, 0, "reset zeroes every work count")
    eq(addon.Work.commands, 0)

    for _ = 1, 3 do
        h:Fire("PLAYER_TARGET_CHANGED")
    end
    h:Advance(2)
    h:Slash("/test poke")
    action()
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")

    eq(busy.Work.events, 3)
    eq(busy.Work.changes, 6, "each event's write runs the watcher and the rule")
    eq(busy.Work.timers, 2)
    eq(busy.Work.commands, 1)
    eq(busy.Work.actions, 1)
    eq(busy.Work.messages, 1, "a delivery counts for the listening module")
    eq(chat.Work.events, 3, "the transport's own handlers: joined, roster, the message")
    eq(chat.Work.messages, 0)

    h.printed = {}
    h:Slash("/test debug work")
    local text = Printed(h)

    truthy(text:find("Work since load or reset, busiest first:", 1, true), text)
    local busyAt = text:find("  Busy: 14 (3 events, 2 timers, 6 changes, 1 command, 1 message, 1 action)", 1, true)
    local chatAt = text:find("  Chat: 3 (3 events)", 1, true)
    local addonAt = text:find("  addon: 1 (1 command)", 1, true)

    truthy(busyAt and chatAt and addonAt, "the framework's own work is the addon's, here the report's command: " .. text)
    truthy((busyAt < chatAt) and (chatAt < addonAt), "busiest first: " .. text)
    truthy(text:find("  No work: Quiet", 1, true), text)
    falsy(text:find(" ms", 1, true), "no time while profiling is off: " .. text)

    h:Slash("/test debug reset")
    eq(busy.Work.events, 0)
    eq(chat.Work.events, 0)
end)

test("a module's counts outlast a stop and a restart", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", OnEnable = function(module)
        module:On("PLAYER_TARGET_CHANGED", function() end)
    end })

    Start(h)
    h:Fire("PLAYER_TARGET_CHANGED")
    addon.State:Set("M.enabled", false)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(module.Work.events, 1, "a stopped module runs nothing")
    addon.State:Set("M.enabled", true)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(module.Work.events, 2)
end)

test("debug profile times each module's callbacks, only while it's on", function()
    local h, addon = NewAddOn()
    local busy = addon:Module("Busy", {
        commands = { { label = "Poke", name = "poke",
            run = function()
                h.workTime = (h.workTime + 0.5)
                addon.State:Set("Busy.count", addon.State:Get("Busy.count") + 1)
            end,
            slash = "poke" } },
        label = "Busy",
        OnEnable = function(module)
            module:On("PLAYER_TARGET_CHANGED", function() h.workTime = (h.workTime + 2.5) end)
            module:After(1, function() h.workTime = (h.workTime + 1) end)
        end,
        state = { { default = 0, kind = "number", name = "count", persist = false } },
    })
    local other = addon:Module("Other", { label = "Other", OnEnable = function(module)
        module:Watch({ "Busy.count" }, function() h.workTime = (h.workTime + 0.25) end, true)
    end })

    Start(h)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(h:CountApiCalls("debugprofilestop"), 0, "nothing reads the clock while profiling is off")
    eq(busy.Work.time, 0)

    h:Slash("/test debug profile")
    truthy(Printed(h):find("Profiling on: /test debug work shows each module's time.", 1, true), Printed(h))
    eq(addon.Profiling, true)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(h:CountApiCalls("debugprofilestop"), 2, "one clock read before the handler and one after")
    eq(busy.Work.time, 2.5)
    h:Advance(1)
    eq(busy.Work.time, 3.5, "a timer's time, not the second GetTime moved before it ran")
    h:Slash("/test poke")
    eq(busy.Work.time, 4, "a command's own time")
    eq(other.Work.time, 0.25, "the watcher its write ran is charged to the watcher's module, not the command's")

    h.printed = {}
    h:Slash("/test debug work")
    local text = Printed(h)

    truthy(text:find("busiest first; time while profiling:", 1, true), text)
    truthy(text:find("  Busy: 4 (2 events, 1 timer, 1 command), 4.000 ms", 1, true), text)
    truthy(text:find("  Other: 1 (1 change), 0.250 ms", 1, true), text)

    h:Slash("/test debug profile")
    truthy(Printed(h):find("Profiling off.", 1, true), Printed(h))
    eq(rawget(addon.Events, "Dispatch"), nil, "the dispatcher is back to the counting path")
    h.apiCalls = {}
    h:Fire("PLAYER_TARGET_CHANGED")
    h:Slash("/test poke")
    eq(h:CountApiCalls("debugprofilestop"), 0, "nothing reads the clock once profiling is off")
    eq(busy.Work.time, 4, "time stands still while off")
    eq(busy.Work.events, 3, "counting goes on")
    h.printed = {}
    h:Slash("/test debug work")
    falsy(Printed(h):find(" ms", 1, true), "no time once profiling is off: " .. Printed(h))

    h:Slash("/test debug profile")
    eq(busy.Work.time, 0, "profiling again starts every time from zero")
end)

test("counting adds no allocation to a dispatch: it costs exactly its handlers' calls", function()
    local h, addon = NewAddOn()
    local handlers = 3

    addon:Module("M", { label = "M", OnEnable = function(module)
        for _ = 1, handlers do
            module:On("PLAYER_TARGET_CHANGED", function() end)
        end
    end })
    Start(h)
    local events, SafeCall = addon.Events, h.env.ByteTerrace.SafeCall

    local function Empty() end
    events:Dispatch("PLAYER_TARGET_CHANGED") -- the event's dispatch count gets its key
    eq(rawget(events, "Dispatch"), nil, "profiling is off: the class's counting Dispatch runs")
    local dispatch = BytesPerCall(function() events:Dispatch("PLAYER_TARGET_CHANGED") end, 200)
    local call = BytesPerCall(function() SafeCall(Empty) end, 200)
    -- The harness's xpcall (WoW's, passing arguments) allocates; the dispatcher must add nothing.
    eq(dispatch, handlers * call, "bytes per dispatch")
    eq(addon.Modules.M.Work.events, 201 * handlers)
    eq(h:CountApiCalls("debugprofilestop"), 0)
end)

test("while profiling, rules, first readings, deliveries and deferred actions are timed too", function()
    local h, addon = NewAddOn()
    local chat = addon:Module("Chat", { comms = { prefix = "TestApp1" }, label = "Chat" })
    local action

    local function Spend(ms)
        return function() h.workTime = (h.workTime + ms) end
    end
    local late = addon:Module("Late", { default = false, label = "Late",
        OnEnable = function(module)
            module:Rule({ reads = { "Chat.enabled" }, when = function() return true end, changed = Spend(1), initial = true })
            module:Watch({ "Chat.enabled" }, Spend(2))
            module:Listen(chat.Comms, "PING", Spend(4))
            action = module:Callback(Spend(8))
        end })

    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:Slash("/test debug profile")
    addon.State:Set("Late.enabled", true)
    eq(late.Work.changes, 2, "the rule's first verdict and the watcher's first reading")
    eq(late.Work.time, 3)
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
    eq(late.Work.time, 7)
    eq(chat.Work.time, 4, "the delivery runs inside the transport's handler, so its time is there too")
    action()
    eq(late.Work.time, 15)
    eq(late.Work.messages + late.Work.actions, 2)
end)

test("the profiling dispatch filters units and isolates errors like the counting one", function()
    local h, addon = NewAddOn()
    local calls = {}
    local module = addon:Module("M", { label = "M", OnEnable = function(module)
        module:On("UNIT_HEALTH", function(unit) calls[#calls + 1] = ("player:" .. unit) end, "player")
        module:On("UNIT_HEALTH", function() error("boom") end)
        module:On("UNIT_HEALTH", function(unit) calls[#calls + 1] = ("any:" .. unit) end)
    end })

    Start(h)
    h:Slash("/test debug profile")
    h:ExpectErrors("boom", "boom")
    h:Fire("UNIT_HEALTH", "target")
    h:Fire("UNIT_HEALTH", "player")
    eq(table.concat(calls, " "), "any:target player:player any:player")
    eq(module.Work.events, 5, "the filtered handler ran once, the others twice")
    addon.Events:Dispatch("PLAYER_TARGET_CHANGED") -- no handler: the client's late delivery of a dropped event
    eq(addon.Events.Counts.PLAYER_TARGET_CHANGED, nil)
end)

test("debug work breaks ties by name and lists at most a screenful", function()
    local h, addon = NewAddOn()

    for i = 1, 41 do
        addon:Module(("M%02d"):format(i), { OnEnable = function(module)
                module:On("PLAYER_TARGET_CHANGED", function() end)
            end,
            toggle = false })
    end
    Start(h)
    h:Fire("PLAYER_TARGET_CHANGED")
    h.printed = {}
    h:Slash("/test debug work")
    local text = Printed(h)

    truthy(text:find(":\n  addon: 2 (1 event, 1 command)\n  M01: 1 (1 event)\n  M02: 1 (1 event)", 1, true),
        "the addon's ADDON_LOADED and report command, then ties by name: " .. text)
    truthy(text:find("  M39: 1 (1 event)\n  ... and 2 more", 1, true), text)
end)
