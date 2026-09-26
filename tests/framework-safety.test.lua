-- ByteTerrace framework: data safety and lifecycle edge cases, each a bug that once got through.

-- A harness with the framework loaded and a bare addon, not yet started. saved seeds TestDB.
local function NewAddOn(saved, options)
    local h = Harness.New({ saved = { TestDB = saved } })
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local spec = { name = "TestApp", title = "Test AddOn", savedVariable = "TestDB", slash = { "/test" } }
    for key, value in pairs(options or {}) do
        spec[key] = value
    end
    return h, h.env.ByteTerrace.NewAddOn(spec)
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp")
end

test("mixed unit filters check secret tokens regardless of registration order and keep publishing", function()
    for _, unfilteredFirst in ipairs({ true, false }) do
        local h, addon = NewAddOn()
        local general = addon:Module("General", { toggle = false, state = {
            { name = "count", kind = "number", default = 0, persist = false },
        } })
        local player = addon:Module("Player", { toggle = false })
        Start(h)
        local published, filtered, secretChecks = 0, 0, 0
        general:Watch({ "count" }, function() published = published + 1 end, true)
        local function General()
            secretChecks = h:CountApiCalls("issecretvalue")
            general:Set("count", general:Get("count") + 1)
        end
        local function Player()
            filtered = filtered + 1
        end
        if unfilteredFirst then
            general:On("UNIT_AURA", General)
            player:On("UNIT_AURA", Player, "player")
        else
            player:On("UNIT_AURA", Player, "player")
            general:On("UNIT_AURA", General)
        end
        h.apiCalls = {}
        h:Fire("UNIT_AURA", Secret("player"))
        eq(#h.errors, 0)
        eq(filtered, 0, "a filtered handler cannot claim a secret unit")
        eq(published, 1, "the unfiltered handler's write publishes")
        general:Set("count", 2)
        eq(published, 2, "the event batch closes, so subsequent writes still publish")
        -- Lua 5.1 cannot trap secret == string; the API count proves dispatch checks the token.
        eq(secretChecks, 1, "a later unit filter still requires a secrecy check")
        h:Fire("UNIT_AURA", "player")
        eq(filtered, 1, "a plain matching token still reaches the filtered handler")
        eq(published, 3)
    end
end)

test("a module whose declaration fails partway keeps its saved rows and records", function()
    local h, addon = NewAddOn({ ["Ledger.note"] = "kept", ["Ledger.people"] = { Bob = { deaths = 3 } } })
    local ok = pcall(addon.Module, addon, "Ledger", {
        toggle = false,
        state = { { name = "note", kind = "string", default = "" } },
        records = { { name = "people", limit = 5, fields = { { name = "deaths", kind = "number", default = "oops" } } } },
    })
    falsy(ok, "the bad field default is refused")
    Start(h)
    truthy(addon.Started)
    eq(h.env.TestDB["Ledger.note"], "kept")
    eq(h.env.TestDB["Ledger.people"].Bob.deaths, 3, "the ledger survives the typo")
end)

test("a rule registered while deferred rules take their first verdict gets its own", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = { { name = "a", kind = "boolean", default = true, persist = false } } })
    Start(h)
    local state, lateRuns = addon.State, 0
    local Always = function() return true end
    state:BeginBatch()
    state:Rule({ reads = { "M.a" }, when = Always, initial = true, changed = function()
        state:Rule({ reads = { "M.a" }, when = Always, initial = true, changed = function() lateRuns = lateRuns + 1 end })
    end })
    for _ = 1, 3 do
        state:Rule({ reads = { "M.a" }, when = Always, initial = true, changed = function() end })
    end
    state:EndBatch()
    eq(lateRuns, 1)
end)

test("stopping a module from its own OnDisable stops it once and releases each dependency once", function()
    local h, addon = NewAddOn()
    local fact = addon:Module("Fact", { toggle = false, demand = true })
    local stops = 0
    addon:Module("User", { label = "User", uses = { "Fact" }, OnDisable = function(module)
        stops = stops + 1
        module:SetEnabled(false)
    end })
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
    falsy(pcall(module.Rule, module, { reads = { "M.enabled" }, when = function() return true end, changed = function() end }))
end)

test("a locked runtime row is refused at compile: stopping couldn't reset it", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, state = {
        { name = "lock", kind = "boolean", default = false },
        { name = "fact", kind = "number", default = 0, persist = false, lockedBy = "M.lock" },
    } })
    h:ExpectErrors("lockedBy only applies to persisted rows")
    Start(h)
    falsy(addon.Started)
end)

test("a character collection without a per-character variable is refused by name", function()
    local h, addon = NewAddOn()
    addon:Module("M", { toggle = false, records = {
        { name = "people", scope = "character", limit = 5, fields = { { name = "n", kind = "number", default = 0 } } },
    } })
    h:ExpectErrors("needs the addon's savedVariablePerCharacter")
    Start(h)
    falsy(addon.Started)
end)

test("releasing a held button after its module stopped says nothing", function()
    local h, addon = NewAddOn()
    local phases = {}
    addon:Module("M", { label = "M", commands = {
        { name = "hold", label = "Hold", held = true, run = function(_, phase) phases[#phases + 1] = phase end } } })
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
    local module = addon:Module("Chat", { label = "Chat", comms = { prefix = "TestApp1" } })
    local got = {}
    module.Comms:Listen("PING", function(_, fields) got[#got + 1] = #fields end)
    Start(h)
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage("TestApp1", "PINGextra", "PARTY", "Bob")
    h:ReceiveAddonMessage("TestApp1", "PING", "PARTY", "Bob")
    h:ReceiveAddonMessage("TestApp1", "PING:a\tb", "PARTY", "Bob")
    eq(table.concat(got, ","), "0,2", "a bare kind has no fields; a kind glued to text is no kind")
    falsy(pcall(module.Comms.Send, module.Comms, "ping"))
    falsy(pcall(module.Comms.Send, module.Comms, "PING", { "a\tb" }))
end)

test("honor messages in a locale with positional arguments still parse", function()
    local h = Harness.New({ saved = { TestDB = {} } })
    rawset(h.env, "COMBATLOG_HONORGAIN", "%2$s: %1$s stirbt (Ehrenhafter Sieg). Ihr erhaltet %3$d Ehre.")
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", facts = { "kills" } })
    addon:Module("User", { toggle = false, uses = { "kills" } })
    Start(h)
    h:Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Sergeant: Bob Doe stirbt (Ehrenhafter Sieg). Ihr erhaltet 12 Ehre.")
    eq(addon.State:Get("kills.honorable"), 1)
end)

test("trimming a collection far over its limit asks keep once per key", function()
    local people = {}
    for i = 1, 40 do
        people[("P%02d"):format(i)] = { seen = i }
    end
    local h, addon = NewAddOn({ ["M.people"] = people })
    local asked = 0
    addon:Module("M", { toggle = false, records = { { name = "people", limit = 10, evict = "seen", fields = {
        { name = "seen", kind = "number", default = 0 } },
        keep = function(key)
            asked = asked + 1
            return key == "P01"
        end } } })
    Start(h)
    local records = addon.Modules.M.Records.people
    eq(records:Count(), 10)
    truthy(records:Has("P01"), "a kept key stays")
    truthy(records:Has("P40") and not records:Has("P02"), "the lowest unkept go first")
    eq(asked, 40)
end)

Harness.DefineAddOn("HalfLoaded", { savedVariables = { "HalfDB" }, dependencies = { "ByteTerrace_Core" }, sources = {
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
