local addonName, ns = ...

-- Calibration probes: small, read-only questions about how the real client behaves, asked the
-- same way in game (`/btdev probe`, DevTools.lua) and in the test harness (tests/probes.test.lua),
-- so the harness's model of the client is checked against what the client answered.
--
-- This file is the probe engine: the shape helpers probes record with, running and recording a
-- probe, and comparing records. ProbeNeeds.lua defines the situations probes need
-- (Probes.AddNeeds); ProbesWorld.lua, ProbesUnits.lua and ProbesCombat.lua define the probes
-- (Probes.Define), in the order they run and print.
--
-- A probe is { name, needs = { need key, ... }, run, harness }:
--   * needs names needs: the situation the probe must run in. Each need has a short label for
--     tables ("NPC target"), the text the player reads ("target a living NPC"), the step of a
--     play session that reaches it (an index into Steps, the order `/btdev probe list` prints
--     in), a check that decides it from the live client, and a harness setup(h) that recreates it
--     in the fake client. A need without a setup carries `harness`, the reason the harness can't
--     model it; its probes run in game only.
--   * run returns the result: a table with string keys whose values are strings, booleans,
--     finite numbers or such tables. Results describe shapes (a type, an empty string, a color's
--     bytes), never data that differs between characters, targets or sessions, so any player's
--     run compares with any other's. The exceptions list what a session happened to show, which
--     is their point: unitCombat.seen's actions and flags, questLog.objectives' types.
--   * harness (optional) is the reason the harness can't run this probe at all.
--   * accumulates (optional) marks a probe whose result lists what sessions happened to show. Its
--     new result merges into the current record instead of replacing it (Probes.Merge), so each
--     session, and each /reload, adds to what earlier ones saw.
--   * version (optional, 1 when absent) goes up whenever the result's shape changes: a record
--     made by another version answered a different question, so it's no evidence for this one.
--     Probes.IsCurrent tells them apart; /btdev probe list, the import and the tests ignore it.
-- A probe only reads. It never calls a protected or restricted function, never changes game
-- state, and never compares, computes with or stores a secret: a secret becomes the marker
-- { secret = true, type = <its type> } (Value, Shape, Text), checked with issecretvalue first.
-- textures.used draws on hidden textures of a frame of its own, made the first time it runs.
--
-- UNIT_COMBAT can't be asked for after the fact, so DevTools.lua listens for it from load (for
-- the player and the target only) and passes each payload to Probes.NoteUnitCombat, which keeps
-- every payload's shape per unit and action, merged, in Probes.UnitCombat; unitCombat.seen
-- records it. The kill events (PARTY_KILL, PLAYER_TARGET_DIED, UNIT_DIED) go to Probes.NoteKill
-- the same way, for kills.seen, and chat events' senders to Probes.NoteSender, for
-- names.chatSenders; each merges what it sees into what it kept.
--
-- A record is { build = "1.60.1 (70009)", context = { combat, restrictions }, result, version? }:
-- the version of the probe that made it (absent for version 1), the build,
-- whether combat lockdown held and which addon restrictions were active ("none", or their
-- Enum.AddOnRestrictionType names sorted and joined by commas), and the result. It holds no
-- time, so running a probe twice in the same situation gives the same record.
--
-- Every probe file (all the TOC lists before DevTools.lua) defines data and functions only;
-- nothing runs at load, so `tlk probes` can read the probe names and needs in plain Lua.

-- The steps of one play session in a starting zone, in the order it reaches them; each need
-- names one.
local Steps = {
    "anywhere",
    "at a quest giver",
    "at a vendor or trainer",
    "fighting mobs",
    "after a mob kills you",
    "later, outside a starting zone",
}

local Probes = {}

-- The needs by key, and the probes in run order and by name, as the other probe files add them.
local Needs, List, ByName = {}, {}, {}

-- The UNIT_COMBAT payloads seen since load (Probes.NoteUnitCombat): units[unit][action] is the
-- last payload's shape (a secret action keys "secret"); actions and flagTexts are the plain
-- strings seen, as sets; amountInCombat is the last amount on you in combat: its type, or
-- "secret".
local UnitCombat = { units = { player = {}, target = {} }, actions = {}, flagTexts = {} }

-- The kill events seen since load (Probes.NoteKill): the last PARTY_KILL's and UNIT_DIED's
-- payload described (whose blow, what kind of unit), and whether PLAYER_TARGET_DIED fired.
local Kills = { partyKill = nil, unitDied = nil, targetDied = false }

-- The last sender's name shape per chat event since load (Probes.NoteSender).
local Senders = {}

--- The marker a secret is recorded as.
local function Marker(value)
    return { secret = true, type = type(value) }
end

--- The value itself, or the marker for a secret.
local function Value(value)
    if issecretvalue(value) then
        return Marker(value)
    end
    return value
end

--- The value's type name ("nil" for nothing), or the marker for a secret.
local function Shape(value)
    if issecretvalue(value) then
        return Marker(value)
    end
    return type(value)
end

--- A name's shape: each run of letters (accented ones too) becomes "Aa", so "Dh Taketwo-Realm"
--- is "Aa Aa-Aa"; "empty", the type name, or the marker for a secret otherwise. No name survives.
local function NameShape(value)
    if issecretvalue(value) then
        return Marker(value)
    elseif type(value) ~= "string" then
        return type(value)
    end
    return value == "" and "empty" or (value:gsub("[%a\128-\255]+", "Aa"))
end

--- "text", "empty" or the type name for a text an API returns, or the marker for a secret.
local function Text(value)
    if issecretvalue(value) then
        return Marker(value)
    elseif type(value) ~= "string" then
        return type(value)
    end
    return value == "" and "empty" or "text"
end

--- A 0-1 color channel as a byte (0-255), or the marker for a secret.
local function Byte(channel)
    if issecretvalue(channel) then
        return Marker(channel)
    elseif type(channel) ~= "number" then
        return type(channel)
    end
    return math.floor(channel * 255 + 0.5)
end

--- A table's string keys, sorted and joined by commas; the Shape of anything else.
local function Fields(tbl)
    if issecretvalue(tbl) or type(tbl) ~= "table" then
        return Shape(tbl)
    end
    local keys = {}
    for key in pairs(tbl) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

--- A table's string keys, each with its value's Shape.
local function FieldShapes(tbl)
    local shapes = {}
    for key, value in pairs(tbl) do
        if type(key) == "string" then
            shapes[key] = Shape(value)
        end
    end
    return shapes
end

--- Whether two values are equal, or "secret" when either is one (secrets are never compared).
local function Same(a, b)
    if issecretvalue(a) or issecretvalue(b) then
        return "secret"
    end
    return a == b
end

--- A list's first entry, or nil for an empty, missing or secret list.
local function First(list)
    if issecretvalue(list) or type(list) ~= "table" then
        return nil
    end
    return list[1]
end

--- A set's keys, sorted and joined by commas.
local function Joined(set)
    local keys = {}
    for key in pairs(set) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Two values of the kind a record holds, as one: tables merge key by key, two different strings
-- become the sorted union of their comma-separated items, two booleans are true if either is,
-- and otherwise b stands (a when b is nil).
local function Merge(a, b)
    if b == nil then
        return a
    elseif type(a) == "table" and type(b) == "table" then
        local merged = {}
        for key, value in pairs(a) do
            merged[key] = value
        end
        for key, value in pairs(b) do
            merged[key] = Merge(a[key], value)
        end
        return merged
    elseif type(a) == "string" and type(b) == "string" and a ~= b then
        local items = {}
        for item in (a .. "," .. b):gmatch("[^,]+") do
            items[item] = true
        end
        return Joined(items)
    elseif type(a) == "boolean" and type(b) == "boolean" then
        return a or b
    end
    return b
end

-- Why a result can't be saved and compared, or nil: only string keys, and strings, booleans,
-- finite numbers and tables of them.
local function Problem(value, path)
    local kind = type(value)
    if issecretvalue(value) then
        return path .. " is a secret"
    elseif kind == "string" or kind == "boolean" then
        return nil
    elseif kind == "number" then
        return (value ~= value or value == math.huge or value == -math.huge) and (path .. " isn't finite") or nil
    elseif kind ~= "table" then
        return ("%s is a %s"):format(path, kind)
    end
    for key, item in pairs(value) do
        if type(key) ~= "string" then
            return path .. " has a key that isn't a string"
        end
        local problem = Problem(item, path .. "." .. key)
        if problem then
            return problem
        end
    end
    return nil
end

local function SortedKeys(...)
    local seen, keys = {}, {}
    for i = 1, select("#", ...) do
        local tbl = select(i, ...)
        if type(tbl) == "table" then
            for key in pairs(tbl) do
                if not seen[key] then
                    seen[key] = true
                    keys[#keys + 1] = key
                end
            end
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function Differences(a, b, path, out)
    if type(a) == "table" and type(b) == "table" then
        for _, key in ipairs(SortedKeys(a, b)) do
            Differences(a[key], b[key], path == "" and key or (path .. "." .. key), out)
        end
    elseif a ~= b then
        out[#out + 1] = { path = path, a = a, b = b }
    end
    return out
end

--- The needs by key ({ label, text, step, check, setup | harness }), and the probes in run order
--- and by name.
Probes.Needs = Needs
Probes.List = List
Probes.ByName = ByName

--- The steps of a starting-zone play session, in order; a need's step indexes it.
Probes.Steps = Steps

--- The UNIT_COMBAT payload shapes seen since load (UnitCombat above), for unitCombat.seen.
Probes.UnitCombat = UnitCombat

--- The kill events seen since load (Kills above), for kills.seen.
Probes.Kills = Kills

--- The chat senders seen, by event (Probes.NoteSender).
Probes.Senders = Senders
Probes.NameShape = NameShape

--- The shape helpers probes record with (documented above).
Probes.Marker, Probes.Value, Probes.Shape, Probes.Text = Marker, Value, Shape, Text
Probes.Byte, Probes.Fields, Probes.FieldShapes, Probes.Same = Byte, Fields, FieldShapes, Same
Probes.First, Probes.Joined, Probes.Merge = First, Joined, Merge

--- Adds needs ({ [key] = need }); a key that's already defined is an error.
function Probes.AddNeeds(needs)
    for key, need in pairs(needs) do
        assert(not Needs[key], "duplicate need " .. key)
        Needs[key] = need
    end
end

--- Adds probes to the end of the run order; a duplicate name or an unknown need is an error.
function Probes.Define(probes)
    for _, probe in ipairs(probes) do
        assert(not ByName[probe.name], "duplicate probe " .. probe.name)
        for _, key in ipairs(probe.needs) do
            assert(Needs[key], ("probe %s: unknown need %s"):format(probe.name, key))
        end
        local version = probe.version
        assert(version == nil or (type(version) == "number" and version >= 2 and version % 1 == 0),
            ("probe %s: version must be a whole number from 2 (leave it out for 1)"):format(probe.name))
        List[#List + 1] = probe
        ByName[probe.name] = probe
    end
end

--- The active addon restrictions: "none", or their Enum.AddOnRestrictionType names, sorted and
--- joined by commas.
function Probes.Restrictions()
    local active = {}
    for name, value in pairs(Enum.AddOnRestrictionType) do
        if C_RestrictedActions.IsAddOnRestrictionActive(value) then
            active[#active + 1] = name
        end
    end
    table.sort(active)
    return #active > 0 and table.concat(active, ",") or "none"
end

--- The client build as "<version> (<build>)".
function Probes.Build()
    local version, build = GetBuildInfo()
    return ("%s (%s)"):format(version, build)
end

--- The situation a probe runs in: combat lockdown and the active restrictions.
function Probes.Context()
    return { combat = InCombatLockdown() and true or false, restrictions = Probes.Restrictions() }
end

--- Whether the probe's needs are met right now.
---@return boolean met
---@return string? unmet the first unmet need's text
function Probes.Check(probe)
    for _, key in ipairs(probe.needs) do
        local need = Needs[key]
        local ok, met = pcall(need.check)
        if not ok or not met then
            return false, need.text
        end
    end
    return true, nil
end

--- The step of the play session that meets all of the probe's needs: the latest of their steps,
--- or the first step for a probe that runs anywhere.
function Probes.Step(probe)
    local step = 1
    for _, key in ipairs(probe.needs) do
        step = math.max(step, Needs[key].step)
    end
    return step
end

--- Keeps a UNIT_COMBAT payload's shape for unitCombat.seen (DevTools.lua passes every payload for
--- the player and the target): the last one per unit and action, and the plain action and flag
--- strings seen. Payloads for other units are ignored.
function Probes.NoteUnitCombat(unit, action, flagText, amount, schoolMask)
    local byAction = not issecretvalue(unit) and UnitCombat.units[unit]
    if not byAction then
        return
    end
    local plainAction = not issecretvalue(action) and type(action) == "string" and action ~= ""
    local key = plainAction and action or (issecretvalue(action) and "secret" or Text(action))
    byAction[key] = Merge(byAction[key], {
        action = Text(action), flagText = Text(flagText), amount = Shape(amount), schoolMask = Shape(schoolMask),
    })
    if unit == "player" and InCombatLockdown() then
        UnitCombat.amountInCombat = issecretvalue(amount) and "secret" or type(amount)
    end
    if plainAction then
        UnitCombat.actions[action] = true
    end
    if not issecretvalue(flagText) and type(flagText) == "string" and flagText ~= "" then
        UnitCombat.flagTexts[flagText] = true
    end
end

-- A GUID's kind ("Player", "Creature", "Pet"...), "secret", or its shape when it isn't a string.
local function GUIDKind(guid)
    if issecretvalue(guid) then
        return "secret"
    end
    return type(guid) == "string" and guid:match("^(%a+)%-") or Shape(guid)
end

-- Whose a GUID is, as seen from you: "you", "pet", "other", or "secret".
local function Whose(guid)
    if issecretvalue(guid) then
        return "secret"
    end
    local me, pet = UnitGUID("player"), UnitGUID("pet")
    if not issecretvalue(me) and guid == me then
        return "you"
    end
    if not issecretvalue(pet) and pet ~= nil and guid == pet then
        return "pet"
    end
    return "other"
end

--- Keeps what a kill event says for kills.seen (DevTools.lua passes each one): for PARTY_KILL,
--- whose blow and the victim's kind; for UNIT_DIED, the unit's kind; for PLAYER_TARGET_DIED, that
--- it fired.
function Probes.NoteKill(event, ...)
    if event == "PARTY_KILL" then
        local attacker, target = ...
        Kills.partyKill = Merge(Kills.partyKill,
            { attacker = Whose(attacker), target = GUIDKind(target), attackerKind = GUIDKind(attacker) })
    elseif event == "UNIT_DIED" then
        Kills.unitDied = Merge(Kills.unitDied, { unit = GUIDKind((...)) })
    elseif event == "PLAYER_TARGET_DIED" then
        Kills.targetDied = true
    end
end

--- Keeps a chat event's sender shape for names.chatSenders (DevTools.lua passes each one).
---@param event string
function Probes.NoteSender(event, sender)
    Senders[event] = Merge(Senders[event], NameShape(sender))
end

--- The needs' texts joined with " + ", or "nothing" for a probe that runs anywhere.
function Probes.NeedsText(probe)
    local texts = {}
    for i, key in ipairs(probe.needs) do
        texts[i] = Needs[key].text
    end
    return #texts > 0 and table.concat(texts, " + ") or "nothing"
end

--- The needs' short labels joined with " + ", or "anywhere" for a probe that runs anywhere.
function Probes.NeedsLabel(probe)
    local labels = {}
    for i, key in ipairs(probe.needs) do
        labels[i] = Needs[key].label
    end
    return #labels > 0 and table.concat(labels, " + ") or "anywhere"
end

--- Why the harness can't run the probe, or nil when it can.
function Probes.HarnessGap(probe)
    if probe.harness then
        return probe.harness
    end
    for _, key in ipairs(probe.needs) do
        if not Needs[key].setup then
            return ("%s: %s"):format(Needs[key].text, Needs[key].harness)
        end
    end
    return nil
end

--- Recreates the probe's needs in a test harness, in the order the probe lists them.
function Probes.Setup(probe, h)
    for _, key in ipairs(probe.needs) do
        Needs[key].setup(h)
    end
end

--- The probe's version: probe.version, or 1.
function Probes.Version(probe)
    return probe.version or 1
end

--- Whether a record was made by the probe's current version, so it answers the probe's question.
---@param record table? a record, or nil
function Probes.IsCurrent(probe, record)
    return type(record) == "table" and (record.version or 1) == Probes.Version(probe)
end

--- Runs the probe and returns its record, or nil and why it failed (an error or a result that
--- can't be saved).
---@return table? record { build, context, result, version? }
---@return string? problem
function Probes.Record(probe)
    local context = Probes.Context()
    local ok, result = pcall(probe.run)
    if not ok then
        return nil, tostring(result)
    end
    local problem = Problem(result, "result")
    if problem then
        return nil, problem
    end
    local version = probe.version -- absent for version 1, like the records made before versions
    return { build = Probes.Build(), context = context, result = result, version = version }, nil
end

--- Where two records (or any values of the kind a record holds) differ: a list of
--- { path, a, b }, sorted by path; empty when they're equal.
function Probes.Diff(a, b)
    return Differences(a, b, "", {})
end

--- A value of the kind a record holds, as text.
function Probes.Show(value)
    if type(value) == "string" then
        return ("%q"):format(value)
    elseif type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for _, key in ipairs(SortedKeys(value)) do
        parts[#parts + 1] = ("%s = %s"):format(tostring(key), Probes.Show(value[key]))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

ns.Probes = Probes
