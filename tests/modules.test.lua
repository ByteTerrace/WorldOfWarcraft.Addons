-- ByteTerrace framework: module declarations and activation, per-character scope, row locks and records.

local Kit = use("framework")

local NewAddOn = Kit.NewAddOn
local Start = Kit.Start
local StartRefused = Kit.StartRefused

test("a module with an active rule runs only while the rule holds", function()
    local h, addon = NewAddOn()
    local fired = 0

    addon:Module("Master", { label = "Master" })

    local dependent = addon:Module("Dependent", { active = { reads = { "Master.enabled" }, when = function(s) return s:Get("Master.enabled") end },
        OnEnable = function(m) m:On("PLAYER_TARGET_CHANGED", function() fired = (fired + 1) end) end, toggle = false })

    Start(h)
    truthy(dependent.Enabled)
    addon.State:Set("Master.enabled", false)
    falsy(dependent.Enabled)
    falsy(addon.Events.Frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(fired, 0)
end)

test("character-scoped rows persist to the per-character table", function()
    local h, addon = NewAddOn({ harness = { saved = { TestCharDB = { ["M.count"] = 4 } } },
        savedVariablePerCharacter = "TestCharDB" })

    h.declared.TestCharDB = true
    rawset(h.env, "TestCharDB", h.saved.TestCharDB)

    local m = addon:Module("M", { state = {
            { default = 0, kind = "number", name = "count", scope = "character" },
            { default = 0, kind = "number", name = "shared" },
        },
        toggle = false })

    Start(h)
    eq(m:Get("count"), 4)
    m:Set("count", 5)
    m:Set("shared", 1)
    eq(h.env.TestCharDB["M.count"], 5)
    eq(h.env.TestDB["M.shared"], 1)
    eq(h.env.TestDB["M.count"], nil)
end)

test("character scope needs a per-character SavedVariable", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", name = "count", scope = "character" } }, toggle = false })
    truthy(StartRefused(h, addon):find("savedVariablePerCharacter", 1, true))
end)

test("a row locked by another row refuses writes from code, slash and the window", function()
    local h, addon = NewAddOn()

    local m = addon:Module("M", { state = {
            { default = false, kind = "boolean", name = "locked", persist = false },
            { default = "a", kind = "string", label = "Mode", lockedBy = "M.locked", name = "mode", values = { "a", "b" } },
        },
        toggle = false })

    Start(h)
    m:Set("locked", true)
    throws(function() m:Set("mode", "b") end, "is locked")
    h:Slash("/test set M.mode b")
    truthy(h.printed[#h.printed]:find("is locked", 1, true))
    addon.SettingsWindow:Show()
    local button = addon.SettingsWindow.Controls[addon.State:Id("M.mode")]

    button:Click()
    truthy(h.printed[#h.printed]:find("Mode is locked", 1, true))
    eq(m:Get("mode"), "a")
    eq(button.Label:GetText(), "a")
    m:Set("locked", false)
    m:Set("mode", "b")
    eq(m:Get("mode"), "b")
    eq(button.Label:GetText(), "b")
end)

test("lockedBy must name a boolean row", function()
    local h, addon = NewAddOn()

    addon:Module("M", { state = { { default = 0, kind = "number", lockedBy = "M.nope", name = "x" } }, toggle = false })
    truthy(StartRefused(h, addon):find("must name a boolean row", 1, true))
end)

test("a character-scoped module's switch is saved per character", function()
    local h, addon = NewAddOn({ savedVariablePerCharacter = "TestCharDB" })

    h.declared.TestCharDB = true
    addon:Module("Kid", { default = false, label = "Kid", scope = "character" })
    Start(h)
    addon.State:Set("Kid.enabled", true)
    eq(h.env.TestCharDB["Kid.enabled"], true)
    eq(h.env.TestDB["Kid.enabled"], nil)
end)

local People = {
    evict = "seen",
    fields = {
        { default = "grudge", kind = "string", name = "kind", values = { "grudge", "glory" } },
        { default = 0, kind = "number", min = 0, name = "deaths", step = 1 },
        { default = 0, kind = "number", name = "seen" },
        { default = "", kind = "string", name = "note" },
    },
    limit = 3, name = "people",
}

local function NewLedger(saved)
    local h, addon = NewAddOn({ harness = { saved = { TestDB = saved } } })

    rawset(h.env, "TestDB", h.saved.TestDB)
    local m = addon:Module("Ledger", { records = { People }, toggle = false })

    Start(h)

    return h, addon, m.Records.people
end

test("records validate every write and store only non-default fields", function()
    local h, _, people = NewLedger()

    people:Set("Bob-Realm", { deaths = 2, seen = 10 })
    eq(people:Field("Bob-Realm", "deaths"), 2)
    eq(people:Field("Bob-Realm", "kind"), "grudge", "defaults fill in")
    eq(people:Field("Nobody", "deaths"), 0, "an absent record reads as defaults")
    throws(function() people:Field("Bob-Realm", "bogus") end, "has no field bogus")
    eq(people:Get("Bob-Realm").seen, 10)
    eq(people:Get("Nobody"), nil, "there's no copy of an absent record")
    eq(h.env.TestDB["Ledger.people"]["Bob-Realm"].kind, nil, "defaults aren't stored")
    throws(function() people:Set("Bob-Realm", { kind = "friend" }) end, "expects one of grudge, glory")
    throws(function() people:Set("Bob-Realm", { deaths = 1.5 }) end, "multiple of 1")
    throws(function() people:Set("Bob-Realm", { bogus = 1, deaths = 3 }) end, "has no field bogus")
    eq(people:Field("Bob-Realm", "deaths"), 2, "a refused write changes nothing")
    throws(function() people:Set("", { deaths = 1 }) end, "key must be")
    throws(function() people:Set(("x"):rep(65), { deaths = 1 }) end, "key must be")
    throws(function() people:Set("Bob-Realm", { note = Secret("x") }) end, "secret")
end)

test("a change moves the collection's version row, once per batch", function()
    local _, addon, people = NewLedger()
    local runs = 0

    addon.State:Watch({ "Ledger.people" }, function() runs = (runs + 1) end, true)

    addon:Batch(function()
        people:Set("A", { seen = 1 })
        people:Set("B", { seen = 2 })
    end)

    eq(runs, 1)
    people:Set("A", { seen = 1 })
    eq(runs, 1, "an unchanged write isn't a change")
    people:Remove("A")
    eq(runs, 2)
    falsy(people:Remove("A"), "removing a missing key is a no-op")
    eq(runs, 2)
end)

test("at the limit a new key evicts the least recently seen", function()
    local _, _, people = NewLedger()

    people:Set("A", { seen = 5 })
    people:Set("B", { seen = 1 })
    people:Set("C", { seen = 9 })
    people:Set("D", { seen = 7 })
    eq(people:Count(), 3)
    falsy(people:Has("B"))
    eq(table.concat(people:Keys(), ","), "A,C,D")
    people:Set("F", { deaths = 1 })
    eq(table.concat(people:Keys(), ","), "C,D,F")
    people:Set("G", { seen = 8 })
    eq(table.concat(people:Keys(), ","), "C,D,G", "a record that never set seen reads as its default, the lowest")
end)

test("loading keeps valid records, resets bad fields and drops bad records", function()
    local h, _, people = NewLedger({ ["Ledger.people"] = {
        ["Bob-Realm"] = { deaths = 3, kind = "enemy", renamed = true, seen = 0 },
        [""] = { deaths = 1 },
        ["Cara-Realm"] = "not a record",
    } })

    eq(people:Count(), 1)
    eq(people:Field("Bob-Realm", "deaths"), 3)
    eq(people:Field("Bob-Realm", "kind"), "grudge", "an invalid field resets")
    eq(h.env.TestDB["Ledger.people"]["Bob-Realm"].renamed, nil)
    eq(h.env.TestDB["Ledger.people"]["Bob-Realm"].seen, nil, "a saved default isn't kept, so a changed default applies")
    eq(people:Field("Bob-Realm", "seen"), 0)
end)

test("a collection saved in the other scope, or as something other than a table, is reset", function()
    local h, addon = NewAddOn({ harness = { saved = { TestDB = {
            ["addon.debug"] = true, ["Kid.people"] = { Bob = { seen = 1 } }, ["Ledger.people"] = "junk",
        } } },
        savedVariablePerCharacter = "TestCharDB" })

    h.declared.TestCharDB = true
    rawset(h.env, "TestCharDB", h.saved.TestCharDB)

    local kid = addon:Module("Kid", { records = { {
        fields = People.fields, limit = 3, name = "people", scope = "character",
    } },
        toggle = false })

    local ledger = addon:Module("Ledger", { records = { People }, toggle = false })

    Start(h)
    eq(h.env.TestDB["Kid.people"], nil, "a per-character collection doesn't keep account data")
    eq(kid.Records.people:Count(), 0)
    eq(type(h.env.TestDB["Ledger.people"]), "table")
    eq(ledger.Records.people:Count(), 0)
    local said = table.concat(h.printed, "\n")

    truthy(said:find("Reset saved settings that are no longer valid: Kid.people, Ledger.people", 1, true), said)
end)

test("a collection is usable only once its addon has loaded", function()
    local h, addon = NewAddOn()
    local m = addon:Module("Ledger", { records = { People }, toggle = false })

    throws(function() m.Records.people:Count() end, "records Ledger.people used before the addon loaded")
    Start(h)
    eq(m.Records.people:Count(), 0)
end)

test("kept keys are never evicted; a collection of only kept keys refuses new ones", function()
    local h, addon = NewAddOn()
    local kept = { A = true }

    local m = addon:Module("Ledger", { records = { {
        evict = "seen", fields = { { default = 0, kind = "number", name = "seen" } },
        keep = function(key) return kept[key] end, limit = 2, name = "people",
    } },
        toggle = false })

    Start(h)
    local people = m.Records.people

    people:Set("A", { seen = 1 })
    people:Set("B", { seen = 5 })
    people:Set("C", { seen = 9 })
    truthy(people:Has("A"), "kept despite the lowest seen")
    falsy(people:Has("B"))
    kept.C = true
    throws(function() people:Set("D", { seen = 10 }) end, "is full")
end)

test("record specs are validated at declaration", function()
    local _, addon = NewAddOn()

    local ok, err = pcall(addon.Module, addon, "Bad", { records = {
            { evict = "nope", fields = { { default = {}, kind = "table", name = "a" } }, limit = 0, name = "x" } },
        toggle = false })

    falsy(ok)
    err = tostring(err)
    truthy(err:find("Bad.x.a: unknown kind table", 1, true), err)
    truthy(err:find("Bad.x: limit must be a positive whole number", 1, true), err)
    truthy(err:find("Bad.x: evict must name a number field", 1, true), err)

    ok, err = pcall(addon.Module, addon, "Worse", { records = { { fields = { { default = 0, kind = "number", name = "a" }, { default = 0, kind = "number", name = "a" },
            { default = 0, kind = "number", name = "two words" } },
        keep = true, limit = 1, name = "y" } },
        toggle = false })

    falsy(ok)
    err = tostring(err)
    truthy(err:find("Worse.y: duplicate field a", 1, true), err)
    truthy(err:find("Worse.y: field name 'two words' must be an identifier", 1, true), err)
    truthy(err:find("Worse.y: keep must be a function(key)", 1, true), err)

    throws(function() addon:Module("Empty", { records = { { limit = 1, name = "z" } }, toggle = false }) end,
        "Empty.z: a collection needs fields")
end)

test("declaring after a refused start is refused too", function()
    local h, addon = NewAddOn()

    addon:Module("M", { toggle = false, uses = { "Missing" } })
    StartRefused(h, addon)
    throws(function() addon:Module("Late", { toggle = false }) end, "after start")
    eq(addon.Modules.Late, nil)
end)

test("a module spec that can't be declared is refused, naming what's wrong", function()
    local h, addon = NewAddOn()
    local ByteTerrace = h.env.ByteTerrace

    throws(function() ByteTerrace.NewAddOn({ name = "Other" }) end, "needs a name and a savedVariable")

    throws(function() ByteTerrace.NewAddOn({ facts = { "weather" }, name = "Other", savedVariable = "OtherDB" }) end,
        "unknown fact weather")

    addon:Module("M", { toggle = false })
    throws(function() addon:Module("M", { toggle = false }) end, "duplicate module M")
    throws(function() addon:Module("A", { active = { reads = { "M.x" } } }) end, "active must be")
    throws(function() addon:Module("U", { uses = "target" }) end, "uses must be a list")

    throws(function() addon:Module("R", { label = "R", state = { { default = true, kind = "boolean", name = "enabled" } } }) end,
        "duplicate state row R.enabled")

    throws(function() addon:Module("C", { records = { { limit = 1, name = "a.b" } } }) end,
        "records name 'a.b' in module C must be an identifier")

    throws(function() addon:Module("N", { commands = { { label = "Go", name = "go now", run = function() end } } }) end,
        "command name in module N must be an identifier")

    throws(function() addon:Module("D", { commands = {
        { label = "Go", name = "go", run = function() end }, { label = "Again", name = "go", run = function() end },
    } }) end, "duplicate command D.go")

    Start(h)
    truthy(addon.Started, "the refused declarations left nothing behind")
end)
