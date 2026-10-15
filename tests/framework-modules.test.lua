-- ByteTerrace framework: what a module owns beyond handlers and watchers (timers, rising counts,
-- demand dependencies, group messages, sounds), names, slash registration and the debug command.

-- A harness with the framework loaded and a bare addon, not yet started.
local function NewAddOn(options)
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local spec = { name = "TestApp", title = "Test AddOn", version = "1.0", savedVariable = "TestDB", slash = { "/test" } }
    for key, value in pairs(options or {}) do
        spec[key] = value
    end
    return h, h.env.ByteTerrace.NewAddOn(spec)
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp", false)
end

local function Printed(h)
    return table.concat(h.printed, "\n")
end


test("a module's timer runs its callback as one state batch", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", state = {
        { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    addon.State:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    module:After(2, function()
        module:Set("a", 1)
        module:Set("b", 1)
    end)
    h:Advance(1)
    eq(runs, 0, "not due yet")
    h:Advance(1)
    eq(runs, 1, "both writes publish once")
    eq(module:PendingTimers(), 0)
end)

test("a stopped module's timers never fire, one-shot or repeating", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M" })
    Start(h)
    local once, ticks = 0, 0
    module:After(5, function() once = once + 1 end)
    module:Every(1, function() ticks = ticks + 1 end)
    h:Advance(2)
    eq(ticks, 2)
    addon.State:Set("M.enabled", false)
    h:Advance(10)
    eq(once, 0, "a retry scheduled before the stop doesn't fire")
    eq(ticks, 2, "the ticker stopped with the module")
    eq(module:PendingTimers(), 0)
end)

test("a canceled timer doesn't fire; scheduling on a stopped module is an error", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M" })
    Start(h)
    local fired = false
    local timer = module:After(1, function() fired = true end)
    module:Cancel(timer)
    module:Cancel(nil)
    h:Advance(2)
    falsy(fired)
    addon.State:Set("M.enabled", false)
    local ok, err = pcall(module.After, module, 1, function() end)
    falsy(ok)
    truthy(tostring(err):find("module M is stopped", 1, true), tostring(err))
end)

test("scheduling a timer from OnDisable is an error, not a timer that silently never fires", function()
    local h, addon = NewAddOn()
    local scheduled
    addon:Module("M", { label = "M", OnDisable = function(module)
        scheduled = pcall(module.After, module, 1, function() end)
    end })
    Start(h)
    addon.State:Set("M.enabled", false)
    eq(scheduled, false)
end)

test("a timer callback that errors is reported and the others still run", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M" })
    Start(h)
    local ran = false
    module:After(1, function() error("boom") end)
    module:After(1, function() ran = true end)
    h:ExpectErrors(1)
    h:Advance(1)
    truthy(ran)
end)


test("OnIncrease runs when a count rises, not when it falls or holds", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", state = { { name = "count", kind = "number", default = 0, persist = false } } })
    local seen = {}
    addon:Module("Reader", { label = "Reader", OnEnable = function(reader)
        reader:OnIncrease("M.count", function(_, count, previous) seen[#seen + 1] = previous .. ">" .. count end)
    end })
    Start(h)
    module:Set("count", 1)
    module:Set("count", 3)
    module:Set("count", 0)
    module:Set("count", 1)
    eq(table.concat(seen, " "), "0>1 1>3 0>1")
end)


test("a demand module runs only while a module that uses it runs", function()
    local h, addon = NewAddOn()
    local order = {}
    local fact = addon:Module("Fact", { toggle = false, demand = true,
        state = { { name = "value", kind = "number", default = 0, persist = false } },
        OnEnable = function(module)
            order[#order + 1] = "fact"
            module:On("PLAYER_TARGET_CHANGED", function() order[#order + 1] = "fact handler" end)
            module:Set("value", 7)
        end })
    local firstReading
    addon:Module("A", { label = "A", uses = { "Fact" }, OnEnable = function(module)
        order[#order + 1] = "A"
        firstReading = module:Get("Fact.value")
        module:On("PLAYER_TARGET_CHANGED", function() order[#order + 1] = "A handler" end)
    end })
    addon:Module("B", { label = "B", default = false, uses = { "Fact" } })
    Start(h)
    truthy(fact.Enabled)
    eq(fact.Users, 1)
    eq(firstReading, 7, "a user's first reading sees the dependency's real value")
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(table.concat(order, ", "), "fact, A, fact handler, A handler", "dependencies start and dispatch first")

    addon.State:Set("B.enabled", true)
    eq(fact.Users, 2)
    addon.State:Set("A.enabled", false)
    truthy(fact.Enabled, "one user is left")
    addon.State:Set("B.enabled", false)
    falsy(fact.Enabled, "the last user stopped it")
    falsy(addon.Events.Frame:IsEventRegistered("PLAYER_TARGET_CHANGED"), "a fact no one uses registers nothing")
    eq(addon.State:Get("Fact.value"), 0, "its runtime rows reset")
end)

test("a user declared before its dependency starts it fully, and stopping resets it", function()
    local h, addon = NewAddOn()
    addon:Module("User", { label = "User", uses = { "Late" } })
    local late = addon:Module("Late", { toggle = false, demand = true, uses = { "Base" },
        state = { { name = "value", kind = "number", default = 0, persist = false } },
        OnEnable = function(module) module:Set("value", 5) end })
    local base = addon:Module("Base", { toggle = false, demand = true })
    Start(h)
    truthy(late.Enabled)
    truthy(base.Enabled, "the dependency's own dependency started too")
    addon.State:Set("User.enabled", false)
    falsy(late.Enabled)
    falsy(base.Enabled)
    eq(base.Users, 0)
    eq(addon.State:Get("Late.value"), 0, "its runtime rows reset")
end)

test("uses must name demand modules, without cycles", function()
    local h, addon = NewAddOn()
    addon:Module("Plain", { toggle = false })
    addon:Module("X", { toggle = false, demand = true, uses = { "Y" } })
    addon:Module("Y", { toggle = false, demand = true, uses = { "X" } })
    addon:Module("User", { toggle = false, uses = { "Plain", "Missing" } })
    h:ExpectErrors(1)
    Start(h)
    falsy(addon.Started)
    local message = h.errors[1] or ""
    truthy(message:find("User uses Plain, which isn't a demand module", 1, true), message)
    truthy(message:find("User uses unknown module Missing", 1, true), message)
    truthy(message:find("uses cycle", 1, true), message)
end)

test("a demand module can't have a switch or an active rule", function()
    local _, addon = NewAddOn()
    local ok, err = pcall(addon.Module, addon, "D", { label = "D", demand = true })
    falsy(ok)
    truthy(tostring(err):find("a demand module has toggle = false and no active rule", 1, true))
end)


test("group messages: sent to the group, received from it, never your own", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    local got = {}
    module.Comms:Listen("PING", function(sender, fields) got[#got + 1] = sender .. ":" .. table.concat(fields, ",") end)
    Start(h)
    h:JoinGroup("party", { "Bob" })
    truthy(module.Comms:Ready())
    module.Comms:Send("PING", { "a", "b" })
    eq(h.addonMessages[1].message, "PING:a\tb")
    eq(h.addonMessages[1].chatType, "PARTY")
    h:Advance(1)
    eq(#got, 0, "the client's echo of your own message is ignored")
    h:ReceiveAddonMessage("TestApp1", "PING:x", "PARTY", "Bob")
    h:ReceiveAddonMessage("TestApp1", "PING:x", "WHISPER", "Bob")
    h:ReceiveAddonMessage("TestApp1", "ping", "PARTY", "Bob")
    eq(table.concat(got, " "), "Bob Doe:x", "only well-formed group messages arrive, from the sender's full name")
    h:LeaveGroup()
    h:JoinGroup("instance", { "Ann" })
    module.Comms:Send("PING")
    eq(h.addonMessages[#h.addonMessages].chatType, "INSTANCE_CHAT", "an instance group talks on instance chat")
    eq(h.addonMessages[#h.addonMessages].result, h.env.Enum.SendAddonMessageResult.Success)
end)

test("group messages keep one per interval from a bounded queue, and nothing while stopped", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1", interval = 2, queue = 3 } })
    local got = 0
    module.Comms:Listen("PING", function() got = got + 1 end)
    Start(h)
    h:JoinGroup("party", { "Bob" })
    for i = 1, 5 do
        module.Comms:Send("PING", i)
    end
    eq(#h.addonMessages, 1, "the first goes at once")
    eq(module.Comms:Queued(), 3, "3 wait their turn; the fifth was dropped")
    h:Advance(2)
    eq(#h.addonMessages, 2)
    eq(module.Comms:Queued(), 2)
    addon.State:Set("Chat.enabled", false)
    eq(module.Comms:Queued(), 0, "stopping drops the queue")
    h:Advance(10)
    eq(#h.addonMessages, 2, "and its pending send")
    module.Comms:Send("PING")
    eq(#h.addonMessages, 2, "a stopped module sends nothing")
    falsy(module.Comms:Ready())
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
    eq(got, 0, "nor hears anything")
end)

local function Messages(h, from)
    local texts = {}
    for i = from or 1, #h.addonMessages do
        texts[#texts + 1] = h.addonMessages[i].message
    end
    return table.concat(texts, " ")
end

test("an urgent message takes the newest ordinary message's place in a full queue", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1", queue = 3 } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:Slash("/test debug")
    for i = 1, 4 do
        module.Comms:Send("PING", i)
    end
    eq(module.Comms:Queued(), 3, "full")
    module.Comms:Send("RALLY", "now", true)
    eq(module.Comms:Queued(), 3)
    truthy(Printed(h):find("TestApp1 message PING dropped: an urgent message took its place", 1, true), Printed(h))
    module.Comms:Send("HELP", "me", true)
    h:Advance(10)
    eq(Messages(h), "PING:1 HELP:me RALLY:now PING:2", "urgent first; PING:4, then PING:3, made room")
    for i = 1, 5 do
        module.Comms:Send("SOS", i, true)
    end
    truthy(Printed(h):find("TestApp1 message SOS dropped: the queue is full", 1, true),
        "with every queued message urgent, the newcomer is dropped")
    h:Advance(10)
    eq(Messages(h, 5), "SOS:1 SOS:4 SOS:3 SOS:2", "the first went at once; the fifth found no room")
end)

test("the client's answer decides a message's fate: lockdown drops the queue, a general error retries a few times", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    local results = h.env.Enum.SendAddonMessageResult
    module.Comms:Send("PING", "a")
    module.Comms:Send("PING", "b")
    module.Comms:Send("PING", "c")
    h:AnswerAddonMessages("AddOnMessageLockdown")
    h:Advance(1)
    eq(h.addonMessages[2].result, results.AddOnMessageLockdown)
    eq(module.Comms:Queued(), 0, "lockdown drops the queue")
    eq(module:PendingTimers(), 0, "and its pending send")
    h:Advance(5)
    eq(Messages(h), "PING:a PING:b", "nothing is retried")

    h:AnswerAddonMessages("GeneralError", 5)
    module.Comms:Send("PING", "d")
    module.Comms:Send("PING", "e")
    h:Advance(10)
    eq(Messages(h, 3), "PING:d PING:d PING:d PING:e PING:e PING:e", "three tries each")
    eq(h.addonMessages[#h.addonMessages].result, results.Success, "e's third try went out")
    eq(module.Comms:Queued(), 0)
end)

test("a send that raises is reported and leaves the queue, which keeps going", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:ExpectErrors("the client raised")
    h:AnswerAddonMessages("raise")
    module.Comms:Send("PING", "a")
    module.Comms:Send("PING", "b")
    eq(module.Comms:Queued(), 1, "a left the queue")
    h:Advance(2)
    eq(Messages(h), "PING:b")
    eq(module.Comms:Queued(), 0)
end)

test("a comms prefix longer than the client allows is refused", function()
    local _, addon = NewAddOn()
    local ok, err = pcall(addon.Module, addon, "Chat", { label = "Chat", comms = { prefix = "AVeryLongPrefixIndeed" } })
    falsy(ok)
    truthy(tostring(err):find("prefix must be a string of 1 to 16 bytes", 1, true))
end)


test("an alias the chat frame already imported is taken too", function()
    local h, addon = NewAddOn()
    h.env.hash_SlashCmdList["/TEST"] = function() end -- the chat frame empties SlashCmdList into it on first use
    h:ExpectErrors("already taken")
    Start(h)
    truthy(addon.Started)
end)

test("finding taken aliases never walks every global", function()
    local h = Harness.New()
    local walks, pairs = 0, h.env.pairs
    rawset(h.env, "pairs", function(t)
        if t == h.env then
            walks = walks + 1
        end
        return pairs(t)
    end)
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" } })
    Start(h)
    eq(walks, 0)
end)

test("debug status names running, stopped and demand modules, their records and queued messages", function()
    local h, addon = NewAddOn()
    addon:Module("Fact", { toggle = false, demand = true })
    addon:Module("On", { label = "On", uses = { "Fact" } })
    addon:Module("Off", { label = "Off", default = false })
    local ledger = addon:Module("Ledger", { toggle = false, records = { {
        name = "people", limit = 5, fields = { { name = "seen", kind = "number", default = 0 } },
    } } })
    addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    Start(h)
    ledger.Records.people:Set("Bob", { seen = 1 })
    h:Slash("/test debug status")
    local text = Printed(h)
    truthy(text:find("Running (demand modules with their users): Chat, Fact (1), Ledger, On", 1, true), text)
    truthy(text:find("Stopped: Off", 1, true), text)
    truthy(text:find("4 events registered", 1, true), "the transport follows the group and restrictions: " .. text)
    truthy(text:find("0 errors caught", 1, true), text)
    truthy(text:find("Records: Ledger.people 1/5", 1, true), text)
    truthy(text:find("Messages queued: Chat 0", 1, true), text)
end)

test("debug toggles debug output, explains itself, and lists at most a screenful", function()
    local h, addon = NewAddOn()
    local rows, events = {}, {}
    for i = 1, 41 do
        rows[i] = { name = "row" .. i, kind = "number", default = 0, persist = false }
    end
    for name, entry in pairs(__snapshot.events) do
        if not entry.HasRestrictions then
            events[#events + 1] = name
        end
    end
    table.sort(events)
    addon:Module("Big", { toggle = false, state = rows, OnEnable = function(module)
        for i = 1, 41 do
            module:On(events[i], function() end)
        end
    end })
    Start(h)
    h:Slash("/test debug")
    eq(addon.State:Get("addon.debug"), true)
    truthy(Printed(h):find("Debug output enabled.", 1, true), Printed(h))
    h:Slash("/test debug")
    eq(addon.State:Get("addon.debug"), false)
    h.printed = {}
    h:Slash("/test debug rows big.row")
    truthy(Printed(h):find("41 rows matching 'big.row':", 1, true), Printed(h))
    truthy(Printed(h):find("... and 1 more; narrow the text", 1, true), Printed(h))
    h.printed = {}
    h:Slash("/test debug events")
    truthy(Printed(h):find("41 events registered", 1, true), Printed(h))
    truthy(Printed(h):find("... and 1 more", 1, true), Printed(h))
    h.printed = {}
    h:Slash("/test debug trace nothing")
    truthy(Printed(h):find("No row matches 'nothing'.", 1, true), Printed(h))
    h:Slash("/test debug bogus")
    truthy(Printed(h):find("Usage: /test debug [status | events | work | rows <text> | trace <text> | trace off | cpu | profile | reset]", 1, true),
        Printed(h))
end)

test("a sound bank plays only what's switched on, and defines each sound and test word once", function()
    local h, addon = NewAddOn()
    local ByteTerrace = h.env.ByteTerrace
    throws(function() ByteTerrace.NewSoundBank(addon, { master = "Sounds.enabled" }) end,
        "needs the master and channel row names")
    local sounds = ByteTerrace.NewSoundBank(addon, { master = "Sounds.enabled", channel = "Sounds.channel" })
    sounds:Define("cheer", { file = "Cheer", word = "cheer", label = "Cheer", row = "Sounds.cheer" })
    sounds:Define("boo", { file = "Boo", word = "boo", label = "Boo", row = "Sounds.boo" })
    throws(function() sounds:Define("cheer", { file = "Yay", word = "yay", label = "Yay", row = "Sounds.cheer" }) end,
        "sound cheer %(yay%) is already defined")
    throws(function() sounds:Define("hiss", { file = "Hiss", word = "boo", label = "Hiss", row = "Sounds.boo" }) end,
        "sound hiss %(boo%) is already defined")
    addon:Module("Sounds", { label = "Sounds", state = {
        { name = "channel", kind = "string", default = "SFX", values = { "Master", "SFX" }, label = "Channel" },
        sounds:Row("cheer", "Cheer", "When you win.", { "cheer" }),
        sounds:Row("boo", "Boo", "When you lose.", { "boo" }),
    } })
    h.files["Interface\\AddOns\\TestApp\\Media\\Cheer.ogg"] = true
    h.files["Interface\\AddOns\\TestApp\\Media\\Boo.ogg"] = true
    Start(h)
    addon.State:Set("Sounds.boo", false)
    eq(sounds:Play("boo"), nil, "a sound switched off plays nothing")
    eq(#h.sounds, 0)
    truthy(sounds:Play("cheer"))
    eq(h.sounds[1].path, "Interface\\AddOns\\TestApp\\Media\\Cheer.ogg")
    eq(h.sounds[1].channel, "SFX")
end)

test("debug events counts dispatches per registered event; reset zeroes them", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M", OnEnable = function(module)
        module:On("PLAYER_TARGET_CHANGED", function() end)
        module:On("UNIT_HEALTH", function() end, "player")
        module:On("UNIT_POWER_FREQUENT", function() end, "player")
        module:On("UNIT_POWER_FREQUENT", function() end, "target")
    end })
    Start(h)
    for _ = 1, 3 do
        h:Fire("PLAYER_TARGET_CHANGED")
    end
    h:Slash("/test debug events")
    local text = Printed(h)
    truthy(text:find("PLAYER_TARGET_CHANGED: 3, 1 handler", 1, true), text)
    truthy(text:find("UNIT_HEALTH [player]: 0, 1 handler", 1, true), text)
    truthy(text:find("UNIT_POWER_FREQUENT [player, target]: 0, 2 handlers", 1, true), "no raw | for chat to read as an escape: " .. text)
    h:Slash("/test debug reset")
    eq(addon.Events.Counts.PLAYER_TARGET_CHANGED, nil)
    eq(addon.State.Counts.publishes, 0)
end)

test("debug rows shows values; debug trace prints changes until turned off", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", state = {
        { name = "count", kind = "number", default = 0, persist = false },
        { name = "other", kind = "number", default = 0, persist = false } } })
    Start(h)
    module:Set("count", 2)
    h:Slash("/test debug rows m.count")
    truthy(Printed(h):find("M.count = 2 (runtime, version 1)", 1, true), Printed(h))
    h:Slash("/test debug trace count")
    module:Set("count", 3)
    module:Set("other", 1)
    truthy(Printed(h):find("M.count: 2 -> 3", 1, true), Printed(h))
    falsy(Printed(h):find("M.other:", 1, true), "untraced rows print nothing")
    h:Slash("/test debug trace off")
    h.printed = {}
    module:Set("count", 4)
    falsy(Printed(h):find("M.count", 1, true))
end)

test("debug cpu reads the client's addon profiler and memory", function()
    local h = NewAddOn()
    Start(h)
    h:Slash("/test debug cpu")
    truthy(Printed(h):find("addon profiler is off", 1, true))
    local metric = h.env.Enum.AddOnProfilerMetric
    h.profiler.enabled = true
    h.profiler.addons.TestApp = { [metric.RecentAverageTime] = 0.5, [metric.CountTimeOver5Ms] = 2 }
    h.profiler.application[metric.RecentAverageTime] = 10
    h.profiler.overall[metric.RecentAverageTime] = 1
    h.profiler.memory.TestApp = 321
    h.profiler.addons.ByteTerrace_Core = { [metric.RecentAverageTime] = 0.25 }
    h.profiler.memory.ByteTerrace_Core = 64
    h.printed = {}
    h:Slash("/test debug cpu")
    local text = Printed(h)
    -- Blizzard's AddOn list share: 0.5 / (10 - 1 + 0.5).
    truthy(text:find("recent 0.500 ms (5.26%)", 1, true), text)
    truthy(text:find("5 ms: 2", 1, true), text)
    truthy(text:find("Memory: 321 KB", 1, true), text)
    truthy(text:find("ByteTerrace_Core, shared by every ByteTerrace addon: recent 0.250 ms", 1, true), text)
    truthy(text:find("64 KB", 1, true), text)
    eq(h.memoryUpdates, 2)
end)

test("the counts cost no registrations: a quiet addon registers only what it handles", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M" })
    Start(h)
    local registered = {}
    for event in pairs(Harness.State(addon.Events.Frame).events) do
        registered[#registered + 1] = event
    end
    table.sort(registered)
    eq(table.concat(registered, ","), "", "the client frame has no event registered")
end)

test("an addon whose slash key another addon took reports it and registers no aliases", function()
    local h, addon = NewAddOn()
    local function Theirs() end
    h.env.SlashCmdList.TESTAPP = Theirs
    h:ExpectErrors("slash command key TESTAPP is already registered; slash commands are off")
    Start(h)
    truthy(addon.Started)
    eq(h.env.SlashCmdList.TESTAPP, Theirs, "the other addon keeps its command")
    eq(rawget(h.env, "SLASH_TESTAPP1"), nil)
end)

test("a unit's full name joins its surname; a name without one stands alone", function()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    local Names = h.env.ByteTerrace.Names
    eq(Names.Mine(), h.player.name .. " " .. h.player.surname)
    h:SetTarget({ name = "Hogger", canAttack = true })
    eq(Names.OfUnit("target"), "Hogger", "an NPC has no surname")
    eq(Names.Full("Bob", ""), "Bob")
    eq(Names.OfUnit("focus"), nil, "no unit")
end)
