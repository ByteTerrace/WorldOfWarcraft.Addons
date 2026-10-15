-- ByteTerrace framework: data safety and lifecycle edge cases, each a bug that once got through.

local Kit = use("framework")

local NewAddOn = Kit.NewAddOn
local Start = Kit.Start

test("mixed unit filters check secret tokens regardless of registration order and keep publishing", function()
    for _, unfilteredFirst in ipairs({ true, false }) do
        local h, addon = NewAddOn()

        local general = addon:Module("General", { state = {
                { default = 0, kind = "number", name = "count", persist = false },
            },
            toggle = false })

        local player = addon:Module("Player", { toggle = false })

        Start(h)
        local published, filtered, secretChecks = 0, 0, 0

        general:Watch({ "count" }, function() published = (published + 1) end, true)

        local function General()
            secretChecks = h:CountApiCalls("issecretvalue")
            general:Set("count", general:Get("count") + 1)
        end

        local function Player()
            filtered = (filtered + 1)
        end

        if unfilteredFirst then
            general:On("UNIT_AURA", General)
            player:On("UNIT_AURA", Player, "player")
        else
            player:On("UNIT_AURA", Player, "player")
            general:On("UNIT_AURA", General)
        end

        h.apiCalls = {}
        h:Fire("UNIT_AURA", Secret("player"), {})
        eq(#h.errors, 0)
        eq(filtered, 0, "a filtered handler cannot claim a secret unit")
        eq(published, 1, "the unfiltered handler's write publishes")
        general:Set("count", 2)
        eq(published, 2, "the event batch closes, so subsequent writes still publish")
        -- Lua 5.1 cannot trap secret == string; the API count proves dispatch checks the token.
        eq(secretChecks, 1, "a later unit filter still requires a secrecy check")
        h:Fire("UNIT_AURA", "player", {})
        eq(filtered, 1, "a plain matching token still reaches the filtered handler")
        eq(published, 3)
    end
end)

test("a module whose declaration fails partway keeps its saved rows and records", function()
    local h, addon = NewAddOn({ harness = { saved = { TestDB = { ["Ledger.note"] = "kept", ["Ledger.people"] = { Bob = { deaths = 3 } } } } } })

    local ok = pcall(addon.Module, addon, "Ledger", {
        records = { { fields = { { default = "oops", kind = "number", name = "deaths" } }, limit = 5, name = "people" } },
        state = { { default = "", kind = "string", name = "note" } },
        toggle = false,
    })

    falsy(ok, "the bad field default is refused")
    Start(h)
    truthy(addon.Started)
    eq(h.env.TestDB["Ledger.note"], "kept")
    eq(h.env.TestDB["Ledger.people"].Bob.deaths, 3, "the ledger survives the typo")
end)

test("a rule registered while deferred rules take their first verdict gets its own", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = true, kind = "boolean", name = "a", persist = false } }, toggle = false })
    Start(h)
    local state, lateRuns = addon.State, 0
    local Always = function() return true end

    state:BeginBatch()

    state:Rule({ changed = function()
            state:Rule({ changed = function() lateRuns = (lateRuns + 1) end, initial = true, reads = { "M.a" }, when = Always })
        end,
        initial = true, reads = { "M.a" }, when = Always })

    for _ = 1, 3 do
        state:Rule({ changed = function() end, initial = true, reads = { "M.a" }, when = Always })
    end

    state:EndBatch()
    eq(lateRuns, 1)
end)

test("a watcher registered mid-batch hears a row return to the value it registered with", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "n", persist = false } }, toggle = false })
    Start(h)
    local state = addon.State
    local moved, seen, bounced = false, {}, false

    state:Watch({ "M.n" }, function(s)
        if (s:Get("M.n") == 1) and not moved then
            moved = true
            s:Set("M.n", 2)
        end
    end, true)

    state:BeginBatch()
    state:Set("M.n", 1)
    state:Watch({ "M.n" }, function(s) seen[#seen + 1] = s:Get("M.n") end, true)

    state:Watch({ "M.n" }, function(s)
        if (s:Get("M.n") == 2) and not bounced then
            bounced = true
            s:Set("M.n", 1)
        end
    end, true)

    state:EndBatch()
    eq(state:Get("M.n"), 1)
    eq(table.concat(seen, ","), "2,1", "it hears the row move off its baseline, and back")
end)

test("stopping a module from its own OnDisable stops it once and releases each dependency once", function()
    local h, addon = NewAddOn()
    local fact = addon:Module("Fact", { demand = true, toggle = false })
    local stops = 0

    addon:Module("User", { label = "User",
        OnDisable = function(module)
            stops = (stops + 1)
            module:SetEnabled(false)
        end,
        uses = { "Fact" } })

    Start(h)
    addon.State:Set("User.enabled", false)
    eq(stops, 1)
    eq(fact.Users, 0)
    addon.State:Set("User.enabled", true)
    truthy(fact.Enabled, "the fact starts again")
end)

test("a module can't register handlers or watchers while stopping or stopped", function()
    local h, addon = NewAddOn()
    local results = {}

    local module = addon:Module("M", { label = "M", OnDisable = function(stopping)
        results.on = pcall(stopping.On, stopping, "PLAYER_TARGET_CHANGED", function() end)
        results.watch = pcall(stopping.Watch, stopping, { "M.enabled" }, function() end)
    end })

    Start(h)
    addon.State:Set("M.enabled", false)
    eq(results.on, false)
    eq(results.watch, false)
    falsy(addon.Events.Frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    falsy(pcall(module.Rule, module, { changed = function() end, reads = { "M.enabled" }, when = function() return true end }))
end)

test("a locked runtime row is refused at compile: stopping couldn't reset it", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = {
            { default = false, kind = "boolean", name = "lock" },
            { default = 0, kind = "number", lockedBy = "M.lock", name = "fact", persist = false },
        },
        toggle = false })

    h:ExpectErrors("lockedBy only applies to persisted rows")
    Start(h)
    falsy(addon.Started)
end)

test("a character collection without a per-character variable is refused by name", function()
    local h, addon = NewAddOn()

    addon:Module("M", { records = {
            { fields = { { default = 0, kind = "number", name = "n" } }, limit = 5, name = "people", scope = "character" },
        },
        toggle = false })

    h:ExpectErrors("needs the addon's savedVariablePerCharacter")
    Start(h)
    falsy(addon.Started)
end)

test("releasing a held button after its module stopped says nothing", function()
    local h, addon = NewAddOn()
    local phases = {}

    addon:Module("M", { commands = {
            { held = true, label = "Hold", name = "hold", run = function(_, phase) phases[#phases + 1] = phase end } },
        label = "M" })

    Start(h)
    addon.Commands:Run("M.hold", nil, "down", "gamepad")
    addon.State:Set("M.enabled", false)
    h.printed = {}
    addon.Commands:Run("M.hold", nil, "up", "gamepad")
    eq(#h.printed, 0, "no turned-off notice for a release")
    eq(table.concat(phases, ","), "down")
end)

test("group messages parse strictly and sends are checked", function()
    local h, addon = NewAddOn()
    local module = addon:Module("Chat", { comms = { prefix = "TestApp1" }, label = "Chat" })
    local got = {}

    module.Comms:Listen("PING", function(_, fields) got[#got + 1] = #fields end)
    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage("TestApp1", "PINGextra", "PARTY", "Bob")
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
    h:ReceiveAddonMessage("TestApp1", "PING:a\tb", "PARTY", "Bob")
    h:ReceiveAddonMessage("TestApp1", "PING:a\nb", "PARTY", "Bob")
    h.env.C_ChatInfo.RegisterAddonMessagePrefix("Other1")
    h:ReceiveAddonMessage("Other1", "PING", "PARTY", "Bob")
    eq(table.concat(got, ","), "0,2", "a bare kind has no fields; a kind glued to text, a line break or another prefix is no message")
    falsy(pcall(module.Comms.Send, module.Comms, "ping"))
    falsy(pcall(module.Comms.Send, module.Comms, "PING", { "a\tb" }))
end)

test("honor messages in a locale with positional arguments still parse", function()
    local h = Harness.New({ saved = { TestDB = {} } })

    rawset(h.env, "COMBATLOG_HONORGAIN", "%2$s: %1$s stirbt (Ehrenhafter Sieg). Ihr erhaltet %3$d Ehre.")
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local addon = h.env.ByteTerrace.NewAddOn({ facts = { "kills" }, name = "TestApp", savedVariable = "TestDB" })

    addon:Module("User", { toggle = false, uses = { "kills" } })
    Start(h)
    h:FireHonorMessage("Sergeant: Bob Doe stirbt (Ehrenhafter Sieg). Ihr erhaltet 12 Ehre.")
    eq(addon.State:Get("kills.honorable"), 1)
end)

test("trimming a collection far over its limit asks keep once per key", function()
    local people = {}

    for i = 1, 40 do
        people[("P%02d"):format(i)] = { seen = i }
    end

    local h, addon = NewAddOn({ harness = { saved = { TestDB = { ["M.people"] = people } } } })
    local asked = 0

    addon:Module("M", { records = { { evict = "seen",
        fields = {
                { default = 0, kind = "number", name = "seen" } },
        keep = function(key)
            asked = (asked + 1)

            return (key == "P01")
        end,
        limit = 10, name = "people" } },
        toggle = false })

    Start(h)
    local records = addon.Modules.M.Records.people

    eq(records:Count(), 10)
    truthy(records:Has("P01"), "a kept key stays")
    truthy(records:Has("P40") and not records:Has("P02"), "the lowest unkept go first")
    eq(asked, 40)
end)

Harness.DefineAddOn("HalfLoaded", { dependencies = { "ByteTerrace_Core" }, savedVariables = { "HalfDB" }, sources = {
    [[local addon = ByteTerrace.NewAddOn({ name = "HalfLoaded", savedVariable = "HalfDB" })
      addon:Module("Good", { toggle = false, state = { { name = "n", kind = "number", default = 0 } } })
      local addonName, ns = ...
      ns.Addon = addon]],
    [[error("a typo in the second file")]],
} })

test("a file that errors while loading costs no saved settings: the client loads the rest", function()
    local h = Harness.New({ saved = { HalfDB = { ["Good.n"] = 4, ["Broken.flag"] = true } } })

    h:ExpectErrors("a typo in the second file")
    local ns = h:LoadAddon("HalfLoaded")

    truthy(ns.Addon.Started, "ADDON_LOADED still fires")
    eq(ns.Addon.State:Get("Good.n"), 4)
    eq(h.env.HalfDB["Broken.flag"], true, "the broken file's module keeps its settings")
end)

test("a watcher registered mid-batch hears a row move back to the value the batch started from", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "n", persist = false } }, toggle = false })
    Start(h)
    local state, seen = addon.State, {}

    state:BeginBatch()
    state:Set("M.n", 1)
    state:Watch({ "M.n" }, function(s) seen[#seen + 1] = s:Get("M.n") end)
    state:Set("M.n", 0)
    state:EndBatch()
    eq(table.concat(seen, ","), "1,0", "it saw 1, so 0 is news to it")
end)

test("a count that went up, down and up again across a registration still counts as rising", function()
    local h, addon = NewAddOn()
    local m = addon:Module("M", { state = { { default = 0, kind = "number", name = "count", persist = false } }, toggle = false })

    Start(h)
    local state, rises = addon.State, 0

    state:BeginBatch()
    state:Set("M.count", 1)
    m:OnIncrease("count", function() rises = (rises + 1) end)
    state:Set("M.count", 0)
    state:EndBatch()
    state:Set("M.count", 1)
    eq(rises, 1)
end)

test("a rule registered in a batch's last publish round still takes its first verdict", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "n", persist = false } }, toggle = false })
    Start(h)
    local state, verdicts = addon.State, 0

    state:Watch({ "M.n" }, function(s)
        local n = s:Get("M.n")

        if n < 8 then
            s:Set("M.n", n + 1)
        elseif verdicts == 0 then
            s:Rule({ changed = function() verdicts = (verdicts + 1) end, initial = true, reads = { "M.n" },
                when = function() return true end })
        end
    end, true)

    state:Set("M.n", 1)
    eq(verdicts, 1, "the batch settled: nothing to report")
end)

test("an extra EndBatch in a watcher is refused and leaves publishing intact", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = {
            { default = 0, kind = "number", name = "a", persist = false },
            { default = 0, kind = "number", name = "b", persist = false },
        },
        toggle = false })

    Start(h)
    local state, heard = addon.State, 0

    state:Watch({ "M.a" }, function(s) s:EndBatch() end, true)
    state:Watch({ "M.b" }, function() heard = (heard + 1) end, true)
    h:ExpectErrors("EndBatch without BeginBatch")
    state:Set("M.a", 1)
    state:Set("M.b", 1)
    eq(heard, 1, "later writes still publish")
end)

test("a demand module stopping can't be acquired as if it were running", function()
    local h, addon = NewAddOn()
    local other
    local fact = addon:Module("Fact", { demand = true, OnDisable = function() other:SetEnabled(true) end, toggle = false })

    addon:Module("User", { label = "User", uses = { "Fact" } })
    other = addon:Module("Other", { default = false, label = "Other", uses = { "Fact" } })
    Start(h)
    addon.State:Set("User.enabled", false)
    falsy(other.Enabled and not fact:IsRunning(), "Other never runs on a stopped Fact")
    eq(fact.Users, (other.Enabled and 1) or 0, "and the count stays honest")
end)

test("a keep function that errors while a collection loads costs the addon nothing but that answer", function()
    local saved = { ["M.people"] = { a = { seen = 1 }, b = { seen = 2 }, c = { seen = 3 } } }
    local h, addon = NewAddOn({ harness = { saved = { TestDB = saved } } })

    addon:Module("M", { records = { { evict = "seen", fields = { { default = 0, kind = "number", name = "seen" } },
        keep = function() error("keep broke") end, limit = 2, name = "people" } },
        toggle = false })

    -- asked once per record
    h:ExpectErrors("keep broke", "keep broke", "keep broke")
    Start(h)
    truthy(addon.Started)
    eq(addon.Modules.M.Records.people:Count(), 2)
end)

test("enum values must be strings, and value labels must name them", function()
    for _, row in ipairs({
        { default = "a", kind = "string", name = "mode", values = { "a", true } },
        { default = "a", kind = "string", name = "mode", valueLabels = { c = "C" }, values = { "a", "b" } },
    }) do
        local h, addon = NewAddOn()

        addon:Module("M", { state = { row }, toggle = false })
        h:ExpectErrors("M.mode")
        Start(h)
        falsy(addon.Started)
    end
end)
