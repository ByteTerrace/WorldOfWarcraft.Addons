-- Calibration of the fake client against the real one. Every probe in
-- ByteTerrace_DevTools' probe files run here the way `/btdev probe` runs it in game
-- (Harness.RunProbe, tests/harness/probes.lua), once per context the real client recorded, and in
-- each its context and result must match what the client recorded (tools/api/probes.json, from
-- `node tools/tlk.mjs probes --import`). A
-- mismatch means the harness models the client wrongly: fix the harness (marking the behavior
-- [E]), never the observation.
--
-- A probe without an observed result, or one whose needs the harness can't recreate, is pending.
-- It still runs where the harness can, so a probe that errors or returns something unsaveable
-- fails before anyone records it in game.

local Observed = Harness.OBSERVED_PROBES.probes

-- The probe list, from a harness of its own (each test runs its probe in a fresh one).
local Definitions = Harness.New():LoadFiles("ByteTerrace_DevTools").Probes

for _, definition in ipairs(Definitions.List) do
    local name = definition.name
    test("probe " .. name, function()
        local run = Harness.RunProbe(name)
        local Probes = run.Probes
        if run.gap then
            pending(("the harness can't run it (%s)%s"):format(run.gap, run.observed and "; the client's record is unchecked" or ""))
        end
        if run.problem then
            error(run.problem, 0)
        end
        if not run.observed then
            local needs = #run.probe.needs > 0 and (" with " .. Probes.NeedsText(run.probe)) or ""
            pending("no observed result (in game: /btdev probe" .. needs .. ")")
        end
        if #run.differences > 0 then
            local lines = { ("the harness answers differently than client %s did:"):format(run.observed.build) }
            for _, difference in ipairs(run.differences) do
                lines[#lines + 1] = ("  in %s, %s: client %s, harness %s"):format(difference.context, difference.path,
                    Probes.Show(difference.a), Probes.Show(difference.b))
            end
            error(table.concat(lines, "\n"), 0)
        end
    end)
end

test("the harness replays a probe in every context the client confirmed its result in", function()
    local result = Harness.RunProbe("chatTypeInfo.raidWarning", false).runs[1].record.result
    local run = Harness.RunProbe("chatTypeInfo.raidWarning",
        { build = Harness.BUILD, contexts = { ["idle/none"] = true, ["combat/Combat"] = true }, result = result })
    eq(#run.runs, 2, "one run per context")
    eq(run.runs[1].context, "combat/Combat", "contexts run sorted")
    eq(run.runs[1].h.inCombat, true, "an anywhere probe enters combat for a combat context")
    eq(run.runs[2].context, "idle/none")
    eq(run.runs[2].h.inCombat, false)
    eq(#run.differences, 0)
end)

test("a context the harness answers differently in is a difference, named by its context", function()
    local result = Harness.RunProbe("chat.lockdownIdle", false).runs[1].record.result
    local run = Harness.RunProbe("chat.lockdownIdle",
        { build = Harness.BUILD, contexts = { ["idle/none"] = true, ["combat/Combat"] = true }, result = result })
    eq(#run.differences, 1, "the idle context matches; the combat one can't, since the probe needs idle")
    eq(run.differences[1].context, "combat/Combat")
    eq(run.differences[1].path, "context")
    eq(run.differences[1].b, "idle/none")
end)

test("every observed result belongs to the current version of a probe", function()
    local orphans = {}
    for name, record in pairs(Observed) do
        local probe = Definitions.ByName[name]
        if not probe or not Definitions.IsCurrent(probe, record) then
            orphans[#orphans + 1] = name
        end
    end
    table.sort(orphans)
    eq(table.concat(orphans, ", "), "", "observations for probes ByteTerrace_DevTools no longer defines, or made by "
        .. "another version of their probe (re-run tlk probes --import)")
end)
