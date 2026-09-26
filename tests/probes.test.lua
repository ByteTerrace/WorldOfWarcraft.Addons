-- Calibration of the fake client against the real one. Every probe in
-- ByteTerrace_DevTools' probe files run here the way `/btdev probe` runs it in game
-- (Harness.RunProbe, tests/harness/probes.lua), and its context and result must match what the
-- real client recorded (tools/api/probes.json, from `node tools/tlk.mjs probes --import`). A
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
                lines[#lines + 1] = ("  %s: client %s, harness %s"):format(difference.path, Probes.Show(difference.a),
                    Probes.Show(difference.b))
            end
            error(table.concat(lines, "\n"), 0)
        end
    end)
end

test("every observed result belongs to a probe", function()
    local orphans = {}
    for name in pairs(Observed) do
        if not Definitions.ByName[name] then
            orphans[#orphans + 1] = name
        end
    end
    table.sort(orphans)
    eq(table.concat(orphans, ", "), "", "observations for probes ByteTerrace_DevTools no longer defines (re-run tlk probes --import)")
end)
