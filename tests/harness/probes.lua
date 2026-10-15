-- Calibration probes in the fake client (see wow.lua for the rest). ByteTerrace_DevTools' probe
-- files (Probes.lua and the files its header names) define each probe once; the real client runs
-- it through /btdev probe and the harness runs it here, so the two answers can be compared.
--
-- Harness.OBSERVED_PROBES is what the real client answered (tools/api/probes.json, passed by
-- tools/lib/harness.mjs as a Lua table constructor, every record with its build filled in):
-- { build, probes = { [name] = { build, contexts, result, version? } } }.
--
-- Harness.RunProbe(name, observed) runs one probe the way /btdev probe runs it, once in a fresh
-- harness for each context the client's record holds (observed: the snapshot's record by default,
-- false for none), sorted: the probe's needs are recreated by their harness setups, the same need checks
-- must then pass, and the probe records its context and result. A probe whose needs don't say
-- whether you're in combat (neither "idle" nor "combat") enters combat for a "combat/..." context,
-- so typing it mid-fight isn't a mismatch. Without a record it runs once, as the setups leave it.
-- It returns { probe, Probes, gap, observed, runs, problem, differences }: gap is why the harness
-- can't run the probe (a need it can't recreate), and runs is a list of { context (the recorded
-- one, or nil), h, problem, record, differences }. A run's problem is why it failed (a setup that
-- doesn't meet its need, an error, an unsaveable result, errors reported to the client); its
-- differences (Probes.Diff of the client's { context, result } and the harness's) are set when
-- the client's record exists. The run's problem is the first run's that has one, prefixed by its
-- context, and differences every run's, each carrying its context. An accumulating probe's record
-- merges what every session showed, so one harness run can't equal it: the harness may show only
-- what the client did, so its result is compared merged into the record (Probes.Merge), and
-- anything the client never showed is a difference.

Harness.OBSERVED_PROBES = type(__probes) == "string" and assert(loadstring("return " .. __probes))()
    or { build = "", probes = {} }

-- One run of the probe in a fresh harness, in the recorded context (or none).
local function RunOnce(name, observed, context)
    local h = Harness.New()
    local Probes = h:LoadFiles("ByteTerrace_DevTools").Probes
    local probe = Probes.ByName[name]
    local run = { context = context, h = h }
    Probes.Setup(probe, h)
    local pinned = false
    for _, need in ipairs(probe.needs) do
        pinned = pinned or need == "idle" or need == "combat" or need == "meterInCombat"
    end
    if not pinned and context and context:match("^combat/") and not h.inCombat then
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
    if observed then
        local result = probe.accumulates and Probes.Merge(observed.result, record.result) or record.result
        run.differences = Probes.Diff({ context = context, result = observed.result },
            { context = next(record.contexts), result = result })
    end
    return run
end

function Harness.RunProbe(name, observed)
    local Probes = Harness.New():LoadFiles("ByteTerrace_DevTools").Probes
    local probe = assert(Probes.ByName[name], "no probe named " .. tostring(name))
    if observed == nil then
        observed = Harness.OBSERVED_PROBES.probes[name]
    end
    -- A record from another version of the probe answered another question: no observation.
    local run = { probe = probe, Probes = Probes, observed = Probes.IsCurrent(probe, observed) and observed or nil, runs = {} }
    run.gap = Probes.HarnessGap(probe)
    if run.gap then
        return run
    end
    local contexts = {}
    for context in pairs(run.observed and run.observed.contexts or {}) do
        contexts[#contexts + 1] = context
    end
    table.sort(contexts)
    for i = 1, math.max(#contexts, 1) do
        local one = RunOnce(name, run.observed, contexts[i])
        run.runs[i] = one
        if one.problem and not run.problem then
            run.problem = one.context and ("in %s: %s"):format(one.context, one.problem) or one.problem
        end
        if one.differences then
            run.differences = run.differences or {}
            for _, difference in ipairs(one.differences) do
                difference.context = one.context
                run.differences[#run.differences + 1] = difference
            end
        end
    end
    return run
end
