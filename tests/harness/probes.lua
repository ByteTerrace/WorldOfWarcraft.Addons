-- Calibration probes in the fake client (see wow.lua for the rest). ByteTerrace_DevTools' probe
-- files (Probes.lua and the files its header names) define each probe once; the real client runs
-- it through /btdev probe and the harness runs it here, so the two answers can be compared.
--
-- Harness.OBSERVED_PROBES is what the real client answered (tools/api/probes.json, passed by
-- tools/lib/harness.mjs as a Lua table constructor, every record with its build filled in):
-- { build, probes = { [name] = { build, context, result } } }.
--
-- Harness.RunProbe(name) runs one probe in a fresh harness the way /btdev probe runs it: the
-- probe's needs are recreated by their harness setups, the same need checks must then pass, and
-- the probe records its context and result. A probe whose needs don't say whether you're in combat
-- (neither "idle" nor "combat") runs in the combat state the client recorded it in, so typing it
-- mid-fight isn't a mismatch. It returns { probe, Probes, h, gap, problem, record,
-- observed, differences }: gap is why the harness can't run the probe (a need it can't recreate);
-- problem is why the run failed (a setup that doesn't meet its need, an error, an unsaveable
-- result, errors reported to the client); differences (Probes.Diff of the observed and the
-- harness's { context, result }) is set when the client's record exists.

Harness.OBSERVED_PROBES = type(__probes) == "string" and assert(loadstring("return " .. __probes))()
    or { build = "", probes = {} }

function Harness.RunProbe(name)
    local h = Harness.New()
    local Probes = h:LoadFiles("ByteTerrace_DevTools").Probes
    local probe = assert(Probes.ByName[name], "no probe named " .. tostring(name))
    local run = { probe = probe, Probes = Probes, h = h, observed = Harness.OBSERVED_PROBES.probes[name] }
    run.gap = Probes.HarnessGap(probe)
    if run.gap then
        return run
    end
    Probes.Setup(probe, h)
    local pinned = false
    for _, need in ipairs(probe.needs) do
        pinned = pinned or need == "idle" or need == "combat" or need == "meterInCombat"
    end
    if not pinned and run.observed and run.observed.context.combat and not h.inCombat then
        h:EnterCombat()
    end
    local met, unmet = Probes.Check(probe)
    if not met then
        run.problem = "the harness setup doesn't meet the need: " .. tostring(unmet)
        return run
    end
    local record, problem = Probes.Record(probe)
    if not record then
        run.problem = "the probe failed in the harness: " .. problem
        return run
    end
    run.problem = h:UnexpectedErrors()
    run.record = record
    if run.observed then
        run.differences = Probes.Diff({ context = run.observed.context, result = run.observed.result },
            { context = record.context, result = record.result })
    end
    return run
end
