-- Framework boundaries under reentrant callbacks, failed startup and malformed messages.

local function NewAddOn()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" } })
    return h, addon
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp")
end

test("record replacement publishes only the complete collection", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Ledger", { toggle = false, records = {
        { name = "people", limit = 1, evict = "seen", fields = { { name = "seen", kind = "number", default = 0 } } },
    } })
    Start(h)
    local people, snapshots = module.Records.people, {}
    people:Set("A", { seen = 1 })
    addon.State:Watch({ "Ledger.people" }, function()
        snapshots[#snapshots + 1] = table.concat(people:Keys(), ",")
        if people:Count() == 0 then
            people:Set("Intruder", { seen = 2 })
        end
    end, true)
    people:Set("B", { seen = 3 })
    eq(table.concat(snapshots, ";"), "B")
    eq(people:Count(), 1, "a watcher cannot fill a transient eviction hole")
end)

test("an immediate watcher that stops its owner leaves no subscription", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    local runs, before = 0, addon.State:WatcherCount()
    module:Watch({ "n" }, function()
        runs = runs + 1
        module:SetEnabled(false)
    end)
    eq(addon.State:WatcherCount(), before)
    module:Set("n", 1)
    eq(runs, 1)
end)

test("an immediate rule that stops its owner leaves no subscription", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    local runs, before = 0, addon.State:WatcherCount()
    module:Rule({ reads = { "n" }, initial = true, when = function(state) return state:Get("M.n") > 0 end,
        changed = function()
            runs = runs + 1
            module:SetEnabled(false)
        end })
    eq(addon.State:WatcherCount(), before)
    module:Set("n", 1)
    eq(runs, 1)
end)

test("failed module startup releases all resources and dependencies", function()
    local h, addon = NewAddOn()
    local fact = addon:Module("Fact", { toggle = false, demand = true })
    local fired = 0
    local broken = addon:Module("Broken", { label = "Broken", uses = { "Fact" }, state = {
        { name = "value", kind = "number", default = 0, persist = false },
    }, OnEnable = function(module)
        module:On("PLAYER_TARGET_CHANGED", function() fired = fired + 1 end)
        module:Every(1, function() fired = fired + 1 end)
        module:Set("value", 1)
        error("startup failed")
    end })
    local good = addon:Module("Good", { label = "Good" })
    h:ExpectErrors("startup failed")
    Start(h)
    truthy(good.Enabled)
    falsy(broken.Enabled)
    falsy(fact.Enabled)
    eq(fact.Users, 0)
    eq(broken:Get("value"), 0)
    eq(broken:PendingTimers(), 0)
    h:Fire("PLAYER_TARGET_CHANGED")
    h:Advance(2)
    eq(fired, 0)
end)

test("scalar and array message fields obey the same encoding rules", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    for _, field in ipairs({ "a\tb", "a\nb", "a\rb", "a\000b" }) do
        throws(function() module.Comms:Send("PING", field) end, "field")
        throws(function() module.Comms:Send("PING", { field }) end, "field")
    end
    eq(#h.addonMessages, 0)
end)

for _, restriction in ipairs({ "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }) do
    test(restriction .. " activation drops queued messages before chat lockdown applies", function()
        local h, addon = NewAddOn()
        local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1", interval = 5 } })
        Start(h)
        h:JoinGroup("party", { "Bob" })
        module.Comms:Send("PING", "first")
        module.Comms:Send("PING", "stale")
        eq(module.Comms:Queued(), 1)
        eq(module:PendingTimers(), 1)
        local activating, locked, queued, timers
        module:On("ADDON_RESTRICTION_STATE_CHANGED", function(kind, state)
            if kind == h.env.Enum.AddOnRestrictionType[restriction]
                and state == h.env.Enum.AddOnRestrictionState.Activating then
                activating = true
                locked = h.env.C_ChatInfo.InChatMessagingLockdown()
                queued, timers = module.Comms:Queued(), module:PendingTimers()
            end
        end)
        h:SetRestriction(restriction, true)
        truthy(activating)
        falsy(locked, "the restriction is not yet enforced during Activating")
        eq(queued, 0, "the event payload clears the queue before lockdown applies")
        eq(timers, 0, "activation cancels the pending send")
        h:SetRestriction(restriction, false)
        h:Advance(6)
        eq(#h.addonMessages, 1, "a brief lockdown never replays stale messages")
        module.Comms:Send("PING", "fresh")
        eq(#h.addonMessages, 2, "fresh messages resume after lockdown")
        eq(h.addonMessages[2].message, "PING:fresh")
    end)
end

test("combat and inactive restriction events preserve the message queue", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1", interval = 5 } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    module.Comms:Send("PING", "first")
    module.Comms:Send("PING", "waiting")
    h:EnterCombat()
    eq(module.Comms:Queued(), 1, "combat alone allows addon messages")
    for _, restriction in ipairs({ "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }) do
        h:Fire("ADDON_RESTRICTION_STATE_CHANGED", h.env.Enum.AddOnRestrictionType[restriction],
            h.env.Enum.AddOnRestrictionState.Inactive)
        eq(module.Comms:Queued(), 1)
    end
    h:Advance(5)
    eq(#h.addonMessages, 2)
    eq(h.addonMessages[2].message, "PING:waiting")
end)

test("stopping a transport inside a listener stops the rest of that delivery", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    local runs = 0
    module.Comms:Listen("PING", function() module:SetEnabled(false) end)
    module.Comms:Listen("PING", function() runs = runs + 1 end)
    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
    eq(runs, 0)
end)

test("restarting a transport inside a listener ends the old delivery", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    local runs = 0
    module.Comms:Listen("PING", function()
        module:SetEnabled(false)
        module:SetEnabled(true)
    end)
    module.Comms:Listen("PING", function() runs = runs + 1 end)
    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
    eq(runs, 0, "the old delivery ended with the transport it began on")
    truthy(module.Comms:Ready(), "the restarted transport is open")
end)

test("a failed declaration leaves no rows, commands or records and can be retried", function()
    local h, addon = NewAddOn()
    local saved = { ["Broken.note"] = 17, ["Broken.people"] = { A = { renamed = "keep" } } }
    rawset(h.env, "TestDB", saved)
    local ran = false
    throws(function()
        addon:Module("Broken", { label = "Broken", state = {
            { name = "note", kind = "string", default = "" },
        }, records = {
            { name = "people", limit = 1, fields = { { name = "n", kind = "number", default = 0 } } },
        }, commands = {
            { name = "orphan", label = "Orphan", always = true, run = function() ran = true end },
        }, comms = { prefix = "" } })
    end, "prefix")
    Start(h)
    truthy(addon.Started)
    eq(addon.State.Ids["Broken.note"], nil)
    eq(saved["Broken.note"], 17)
    eq(saved["Broken.people"].A.renamed, "keep")
    falsy(addon.Commands:Run("Broken.orphan"))
    falsy(ran)

    local retryHarness, retryAddon = NewAddOn()
    throws(function()
        retryAddon:Module("Retry", { label = "Retry", comms = { prefix = "" } })
    end, "prefix")
    retryAddon:Module("Retry", { label = "Retry" })
    Start(retryHarness)
    truthy(retryAddon.Modules.Retry.Enabled)
end)

test("a failed dependency never starts its user and only releases acquired dependencies", function()
    local h, addon = NewAddOn()
    local broken = addon:Module("Broken", { toggle = false, demand = true,
        OnEnable = function() error("dependency failed") end })
    local untouched = addon:Module("Untouched", { toggle = false, demand = true })
    local ran = false
    local user = addon:Module("User", { label = "User", uses = { "Broken", "Untouched" },
        OnEnable = function() ran = true end })
    h:ExpectErrors("dependency failed")
    Start(h)
    falsy(ran)
    falsy(user.Enabled)
    eq(broken.Users, 0)
    eq(untouched.Users, 0)
end)

test("module message subscriptions stop immediately and do not accumulate across restarts", function()
    local h, addon = NewAddOn()
    local chat = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    local runs = 0
    local listener = addon:Module("Listener", { label = "Listener", OnEnable = function(module)
        module:Listen(chat.Comms, "PING", function() module:SetEnabled(false) end)
        module:Listen(chat.Comms, "PING", function() runs = runs + 1 end)
        module:Listen(chat.Comms, "PONG", function() runs = runs + 1 end)
    end })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    for _ = 1, 3 do
        listener:SetEnabled(true)
        h:ReceiveAddonMessage("TestApp1", "PONG", "PARTY", "Bob")
        h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
        h:ReceiveAddonMessage("TestApp1", "PONG", "PARTY", "Bob")
    end
    eq(runs, 3)
    throws(function() listener:Listen(chat.Comms, "PING", function() end) end, "stopped")
end)

test("messages reject secrets, sparse arrays, non-scalar fields, non-finite numbers and excess length before sending", function()
    local h, addon = NewAddOn()
    local chat = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    Start(h)
    h:JoinGroup("party", { "Bob" })
    for _, fields in ipairs({ Secret("hidden"), { Secret(3) }, { math.huge }, 0 / 0, { [2] = "gap" } }) do
        throws(function() chat.Comms:Send("PING", fields) end, "field")
    end
    throws(function() chat.Comms:Send("PING", { "a", nil, "c" }) end, "dense array")
    throws(function() chat.Comms:Send("PING", { {} }) end, "must be a string, number or boolean")
    throws(function() chat.Comms:Send("PING", print) end, "must be a string, number or boolean")
    throws(function() chat.Comms:Send("PING", ("x"):rep(251)) end, "message PING is longer than 255 bytes")
    throws(function() chat.Comms:Listen("ping", function() end) end, "uppercase message kind and a function")
    throws(function() chat.Comms:Listen("PING") end, "uppercase message kind and a function")
    eq(#h.addonMessages, 0, "nothing refused went out")
    chat.Comms:Send("PING", ("x"):rep(250))
    eq(#h.addonMessages[1].message, 255, "a message at the limit goes")
    h:Advance(1)
    chat.Comms:Send("PING", { true, false, 3, "" })
    eq(h.addonMessages[2].message, "PING:true\tfalse\t3\t")
    chat.Comms:Send("PING", {})
    h:Advance(1)
    eq(h.addonMessages[3].message, "PING", "empty arrays carry no fields")
end)

test("an open Warband menu cannot act after its module stops or restarts", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    h:SetTarget({ name = "Bob", isPlayer = true, playerControlled = true, isEnemy = true, canAttack = true })
    local menu = h:OpenTargetMenu()
    addon.State:Set("Warband.enabled", false)
    addon.State:Set("Warband.enabled", true)
    menu:Click("Mark for death")
    eq(addon.Modules.Warband.Records.ledger:Count(), 0)
end)

test("a grudge card cannot act after Warband stops or restarts", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    h:SetTarget({ name = "Bob", isPlayer = true, playerControlled = true, isEnemy = true, canAttack = true })
    h:EnterCombat()
    h:Die()
    h:Advance(4)
    local card = h.env.TheLanKrewToolKitCard
    truthy(card and card:IsShown(), "the unknown-killer card offers a grudge")
    addon.State:Set("Warband.enabled", false)
    addon.State:Set("Warband.enabled", true)
    card:GetScript("OnClick")(card, "LeftButton")
    eq(addon.Modules.Warband.Records.ledger:Count(), 0)
end)

test("a malformed binding cannot leave a partial module declaration", function()
    local h, addon = NewAddOn()
    throws(function()
        addon:Module("M", { label = "M", bindings = { false } })
    end, "a binding must be a table")
    throws(function()
        addon:Module("M", { label = "M", commands = { { name = "go", label = "Go", run = function() end } },
            bindings = { { source = "gamepad.south", command = "M.go" } } })
    end, "a binding needs a map, source and command name")
    local module = addon:Module("M", { label = "M" })
    Start(h)
    truthy(addon.Started, "the refused declarations left nothing that fails compile")
    truthy(module.Enabled)
    falsy(addon.Commands:Run("M.go"), "the refused declaration's command is gone")
end)

test("numeric declarations reject invalid bounds before reaching settings controls", function()
    for _, bounds in ipairs({ { min = 0 / 0, max = 10 }, { min = 0, max = math.huge },
        { min = 0, max = 10, step = -1 }, { min = 0, max = 10, step = math.huge } }) do
        local h, addon = NewAddOn()
        local row = { name = "n", kind = "number", default = 0, label = "Number" }
        for key, value in pairs(bounds) do row[key] = value end
        addon:Module("M", { label = "M", state = { row } })
        h:ExpectErrors(1)
        Start(h)
        falsy(addon.Started)
    end
end)

test("recursive deferred rules report a loop and leave no queued initial callbacks", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "n", kind = "number", default = 0 } } })
    Start(h)
    local runs = 0
    local function Register()
        runs = runs + 1
        addon.State:Rule({ reads = { "M.n" }, initial = true, when = function() return true end,
            changed = Register })
    end
    h:ExpectErrors("did not settle")
    addon:Batch(Register)
    local after = runs
    addon:Batch(function() end)
    eq(runs, after)
end)

test("early event removal keeps teardown work independent of past registrations", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M" })
    Start(h)
    for _ = 1, 100 do
        module:Off(module:On("PLAYER_TARGET_CHANGED", function() end))
    end
    module:On("PLAYER_TARGET_CHANGED", function() end)
    local frame = addon.Events.Frame
    Harness.State(frame).calls = {}
    module:SetEnabled(false)
    local calls = Harness.State(frame).calls
    eq(calls.UnregisterEvent, 1, "one unregister for the one live subscription")
    eq(calls.RegisterEvent, nil)
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
end)

test("dependency teardown cannot restart a module whose stop is still in progress", function()
    local h, addon = NewAddOn()
    local user
    local fact = addon:Module("Fact", { toggle = false, demand = true, OnDisable = function()
        user:SetEnabled(true)
    end })
    user = addon:Module("User", { label = "User", uses = { "Fact" } })
    Start(h)
    user:SetEnabled(false)
    falsy(user.Enabled)
    eq(fact.Users, 0)
end)

test("bound callbacks preserve nil arguments and publish once, then expire permanently", function()
    local h, addon = NewAddOn()
    local module = addon:Module("M", { label = "M", state = {
        { name = "a", kind = "number", default = 0 }, { name = "b", kind = "number", default = 0 },
    } })
    Start(h)
    local runs = 0
    addon.State:Watch({ "M.a", "M.b" }, function() runs = runs + 1 end, true)
    local action = module:Callback(function(...)
        eq(select("#", ...), 3)
        local first, second, third = ...
        eq(first, nil)
        eq(second, false)
        eq(third, 3)
        module:Set("a", module:Get("a") + 1)
        module:Set("b", module:Get("b") + 1)
    end, nil, false, 3)
    action("ignored menu arguments")
    eq(runs, 1)
    module:SetEnabled(false)
    action()
    module:SetEnabled(true)
    action()
    eq(runs, 1)
    throws(function() module:Callback("Mark") end, "Callback needs a function")
end)

test("a live bound menu action preserves Blizzard's default close response", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    h:SetTarget({ name = "Bob", isPlayer = true, playerControlled = true, isEnemy = true, canAttack = true })
    local menu = h:OpenTargetMenu()
    local responded, response = menu:Click("Mark for death")
    truthy(responded)
    eq(addon.Modules.Warband.Records.ledger:Count(), 1)
    eq(response, nil, "a Batch success boolean must not override the menu response")
end)

test("invalid commands refuse startup before saved values are normalized", function()
    local h, addon = NewAddOn()
    local saved = { ["M.renamed"] = "recover", ["M.n"] = 99 }
    rawset(h.env, "TestDB", saved)
    addon:Module("M", { label = "M", state = { { name = "n", kind = "number", default = 0, max = 10 } },
        commands = { { name = "broken", label = "Broken" } } })
    h:ExpectErrors("run must be a function")
    Start(h)
    falsy(addon.Started)
    eq(saved["M.n"], 99)
    eq(saved["M.renamed"], "recover")
end)

test("secret defaults cannot bypass the state and record admission boundary", function()
    local h, addon = NewAddOn()
    addon:Module("M", { label = "M", state = { { name = "text", kind = "string", default = Secret("hidden") } } })
    h:ExpectErrors("secret value")
    Start(h)
    falsy(addon.Started)

    local _, other = NewAddOn()
    throws(function()
        other:Module("M", { label = "M", records = { { name = "people", limit = 1,
            fields = { { name = "text", kind = "string", default = Secret("hidden") } } } } })
    end, "secret value")
end)
