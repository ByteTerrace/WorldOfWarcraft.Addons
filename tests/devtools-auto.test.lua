-- ByteTerrace_DevTools' probes as you play (/btdev probe auto): the sweeps that record each probe once its needs are
-- met, and what DevTools says is stale on entering the world.

-- Counts the runs of one probe.
local function CountRuns(h, name)
    local probe = h.ns.Probes.ByName[name]
    local counter = { runs = 0 }
    local run = probe.run

    probe.run = function()
        counter.runs = (counter.runs + 1)

        return run()
    end

    return counter
end

local function Load(saved)
    local h = Harness.New({ saved = saved })

    h:LoadAddon("ByteTerrace_DevTools")

    return h
end

local function Printed(h, from)
    return table.concat(h.printed, "\n", from or 1)
end

local function Records(h)
    return (h.env.ByteTerraceDevToolsDB.probes or {})
end

test("probes record themselves as you play, each once per build and context, and the sweep names them", function()
    local h = Load()
    local raidWarning = CountRuns(h, "chatTypeInfo.raidWarning")

    eq(Records(h)["chatTypeInfo.raidWarning"], nil, "nothing before the first sweep")
    h:Advance(5)
    truthy(Records(h)["chatTypeInfo.raidWarning"], "a probe that needs nothing is recorded")
    truthy(Printed(h):find("recorded [^\n]*chatTypeInfo%.raidWarning[^\n]* as you played%. /reload to write them%."), Printed(h))
    local from = (#h.printed + 1)

    h:Advance(15)
    eq(raidWarning.runs, 1, "a probe recorded in this context isn't run again")
    eq(Printed(h, from), "", "and the sweeps that find nothing new say nothing")
    h:SetTarget({ classFile = "WARRIOR", name = "Kobold Vermin" })
    h:Advance(5)
    local text = Printed(h, from)

    truthy(text:find("unitIdentity.npcTarget", 1, true), "a target's probes record once there's a target: " .. text)
    falsy(text:find("chatTypeInfo.raidWarning", 1, true), "only what's new is named: " .. text)
    h:EnterCombat()
    h:Advance(5)
    eq(Records(h)["unitHealth.npcTargetInCombat"].result.health.secret, true, "in combat, the combat probes record")
    eq(raidWarning.runs, 2, "and a probe recorded idle runs once more, in the new context")
    truthy(Records(h)["chatTypeInfo.raidWarning"].contexts["combat/Combat"], "which the record adds")
end)

test("a probe that fails in a sweep is printed once and not retried until a reload", function()
    local h = Load()

    h:Advance(20)
    local _, failures = Printed(h):gsub("probe fonts%.scholar failed:", "")

    eq(failures, 1, Printed(h))
    eq(Records(h)["fonts.scholar"], nil)
end)

test("/btdev probe auto off stops the sweeps, the setting survives a reload, and on starts them again", function()
    local h = Load()

    h:Slash("/btdev probe auto off")
    truthy(Printed(h):find("probes don't record themselves as you play.", 1, true), Printed(h))
    h:Advance(10)
    eq(next(Records(h)), nil, "no sweep records anything")
    h:Reload()
    h:Advance(10)
    eq(next(Records(h)), nil, "still off after a reload")
    h:Slash("/btdev probe auto")
    truthy(Printed(h):find("probes don't record themselves as you play.", 1, true), "auto alone says the setting")
    h:Slash("/btdev probe auto on")
    h:Advance(5)
    truthy(Records(h)["chatTypeInfo.raidWarning"], "on again")
    h:Slash("/btdev probe auto sometimes")
    truthy(Printed(h):find("usage: /btdev probe auto [on|off]", 1, true), Printed(h))
end)

test("on entering the world, DevTools says when the dump is from another build and how many probes are still to do", function()
    local h = Load({ ByteTerraceDevToolsDB = { build = { build = "70009", version = "1.60.1" }, globals = {} } })
    local text = Printed(h)

    truthy(text:find("the globals dump is from 1.60.1 (70009), the client is " .. Harness.BUILD, 1, true), text)

    truthy(text:find(("%d of %d probes have no result for %s yet. They record themselves as you play"):format(
        #h.ns.Probes.List, #h.ns.Probes.List, Harness.BUILD), 1, true), text)

    local _, number = h.env.GetBuildInfo()
    local current = Load({ ByteTerraceDevToolsDB = { autoProbe = false, build = { build = number, version = "1.60.1" } } })

    falsy(Printed(current):find("globals dump is from", 1, true), "a dump from this build isn't stale")
    truthy(Printed(current):find("Type /btdev probe in each situation", 1, true), Printed(current))
end)
