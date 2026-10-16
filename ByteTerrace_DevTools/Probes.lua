local addonName, ns = ...

-- Calibration probes: small, read-only questions about how the real client behaves, asked the same way in game (`/btdev
-- probe`, DevTools.lua) and in the test harness (tests/probes.test.lua), so the harness's model of the client is
-- checked against what the client answered.
--
-- This file is the probe engine: the shape helpers probes record with, running and recording a probe, and comparing
-- records. ProbeNeeds.lua defines the situations probes need (Probes.AddNeeds); ProbesWorld.lua, ProbesUnits.lua,
-- ProbesCombat.lua, ProbesNames.lua, ProbesInput.lua and ProbesOrder.lua define the probes (Probes.Define), in the
-- order they run and print.
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
--     run compares with any other's. The exceptions are the accumulating probes below, which list
--     what sessions happened to show (unitCombat.seen, kills.seen, names.chatSenders, names.chatDiscordInfo,
--     combat.edges, comms.addonMessageInLockdown, units.secretTokenInAuraEvent, questLog.objectives,
--     questLog.countForm, damageMeter.pvpSecrecy, encounterWarning.seen, input.events, death.combatState,
--     damageMeter.currentSession, namePlates.events): that's their point.
--   * harness (optional) is the reason the harness can't run this probe at all.
--   * accumulates (optional) marks a probe whose result lists what sessions happened to show. Its
--     new result merges into the current record instead of replacing it (Probes.Merge), so each
--     session, and each /reload, adds to what earlier ones saw.
--   * version (optional, 1 when absent) goes up whenever the result's shape changes: a record
--     made by another version answered a different question, so it's no evidence for this one.
--     Probes.IsCurrent tells them apart; /btdev probe list, the import and the tests ignore it.
-- A probe only reads. It never calls a protected or restricted function, never changes game state, and never compares,
-- computes with or stores a secret: a secret becomes the marker { secret = true, type = <its type> } (Value, Shape,
-- Text), checked with issecretvalue first.
-- textures.used draws on hidden textures of a frame of its own, made the first time it runs.
-- auraSound.api alone registers something, and removes it at once (ProbesUnits.lua says why).
--
-- UNIT_COMBAT can't be asked for after the fact, so DevTools.lua listens for it from load (for the player and the
-- target only) and passes each payload to Probes.NoteUnitCombat, which keeps the shapes of every payload per unit and
-- action in Probes.UnitCombat; unitCombat.seen records them. The kill events (PARTY_KILL, PLAYER_TARGET_DIED,
-- UNIT_DIED) go to Probes.NoteKill the same way, for kills.seen, chat events' senders to Probes.NoteSender, for
-- names.chatSenders, their discordInfo to Probes.NoteDiscordInfo, for names.chatDiscordInfo, addon messages' fields to
-- Probes.NoteAddonMessage, for comms.addonMessageInLockdown, the player's and the target's UNIT_AURA tokens to
-- Probes.NoteAuraToken, for units.secretTokenInAuraEvent, and your deaths and the damage meter's updates to
-- Probes.NoteDeath and NoteMeterUpdate, for damageMeter.afterDeath. Each keeps sets of the shapes it saw (a secret is
-- "secret"), joined when its probe runs, so a shape seen before costs a table lookup: these run on every chat message,
-- hit and aura change. The last three key what they hear by the restrictions in force, which Probes.NoteRestriction
-- follows from ADDON_RESTRICTION_STATE_CHANGED rather than asking the client each time. The steps into and out of
-- combat go to Probes.NoteCombatEdge, for combat.edges: the order of PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED and
-- the Combat restriction's state changes, and what InCombatLockdown, UnitAffectingCombat and IsAddOnRestrictionActive
-- said at each.
--
-- A record is { build = "1.60.1 (70009)", contexts = { ["idle/none"] = true }, result, version? }: the version of the
-- probe that made it (absent for version 1), the build, the result, and the contexts the build gave that result in. A
-- context (Probes.Context) is "idle" or "combat" for whether combat lockdown held, a slash, and the active addon
-- restrictions ("none", or their Enum.AddOnRestrictionType names sorted and joined by commas): "idle/none",
-- "combat/Combat".
-- contexts is a set, since a record holds string keys only; its keys sort when saved. A record holds no time, so
-- running a probe twice in the same situation gives the same record. Probes.Keep folds a run into the saved record
-- (tools/lib/probes.mjs's keepRecord does the same on import):
--   * the same result in a new context adds the context; in a known one, nothing changes;
--   * a different result, or a run on another build, replaces the record, contexts and all: the
--     client or the situation changed, so the earlier contexts no longer vouch for the result;
--   * an accumulating probe's result merges into the saved one, and its contexts join, while the
--     build stays the same.
--
-- Every probe file (all the TOC lists before DevTools.lua) defines data and functions only; nothing runs at load, so
-- `tlk probes` can read the probe names and needs in plain Lua.

-- The steps of one play session in a starting zone, in the order it reaches them; each need names one.
local Steps = {
    "anywhere",
    "at a quest giver",
    "at a vendor or trainer",
    "fighting mobs",
    "after a mob kills you",
    "later, outside a starting zone",
}

-- Seconds after your death in which the damage meter's updates count for damageMeter.afterDeath.
local AfterDeathSeconds = 5

local Probes = {}

-- The needs by key, and the probes in run order and by name, as the other probe files add them.
local ByName = {}
local List = {}
local Needs = {}

-- The UNIT_COMBAT payloads seen since load (Probes.NoteUnitCombat): units[unit][action] holds a set per payload field
-- (action, flagText, amount, schoolMask) of the shapes seen (a secret action keys "secret"); actions and flagTexts are
-- the plain strings seen, as sets; amountInCombat is the last amount on you in combat: its type, or "secret".
local UnitCombat = { actions = {}, flagTexts = {}, units = { player = {}, target = {} } }

-- The kill events seen since load (Probes.NoteKill): sets of whose blow and what kind of unit, for PARTY_KILL
-- (partyKill = { attacker, target, attackerKind }) and UNIT_DIED (unitDied = { unit }), each nil until its event fires;
-- and whether PLAYER_TARGET_DIED fired.
local Kills = { partyKill = nil, targetDied = false, unitDied = nil }

-- The set of sender name shapes per chat event since load (Probes.NoteSender).
local Senders = {}

-- Your last death since load (GetTime(), or nil) and the set of DamageMeterType names the meter updated in the
-- AfterDeathSeconds after each death (Probes.NoteDeath, NoteMeterUpdate).
local AfterDeath = { diedAt = nil, types = {} }

-- The addon restrictions in force as the client last said (Probes.NoteRestriction, SyncRestrictions): active is the set
-- of Enum.AddOnRestrictionType names, text the same as Probes.Restrictions writes it, and seen every name active since
-- load.
local Restricted = { active = {}, seen = {}, text = "none" }

-- The steps of your latest entering and leaving of combat (Probes.NoteCombatEdge): enter and leave are lists of step
-- strings, current the edge the last step belonged to.
local CombatEdges = { current = nil, enter = {}, leave = {} }

-- The most steps an edge keeps: entering and leaving take a few each.
local MaxEdgeSteps = 8

-- The set of UNIT_AURA unit token shapes per restriction text (Probes.NoteAuraToken).
local AuraTokens = {}

-- CHAT_MSG_ADDON's payload fields, in order, and the set of each field's shapes per restriction text
-- (Probes.NoteAddonMessage).
local AddonMessageFields = {
    "prefix", "text", "channel", "sender", "target", "zoneChannelID", "localID", "name", "instanceID",
}

local AddonMessages = {}

-- Chat events' discordInfo (Probes.NoteDiscordInfo): the set of its shapes per event, and of each field's shapes when
-- it's a table.
local DiscordInfo = { fields = {}, shapes = {} }

--- A list's first entry, or nil for an empty, missing or secret list.
local function First(list)
    if issecretvalue(list) or (type(list) ~= "table") then
        return nil
    end

    return list[1]
end

-- A value as an item of a string union: a secret's marker is "secret".
local function Item(value)
    if (type(value) == "table") and (value.secret == true) then
        return "secret"
    end

    return value
end

--- A set's keys, sorted and joined by separator (a comma unless given).
local function Joined(set, separator)
    local keys = {}

    for key in pairs(set) do
        keys[#keys + 1] = key
    end

    table.sort(keys)

    return table.concat(keys, (separator or ","))
end

--- The marker a secret is recorded as.
local function Marker(value)
    return { secret = true, type = type(value) }
end

--- A 0-1 color channel as a byte (0-255), or the marker for a secret.
local function Byte(channel)
    if issecretvalue(channel) then
        return Marker(channel)
    elseif type(channel) ~= "number" then
        return type(channel)
    end

    return math.floor((channel * 255) + 0.5)
end

-- Two values of the kind a record holds, as one: a string meets a string or a secret's marker as the sorted union of
-- their comma-separated items (the marker as "secret", so neither side is lost), tables merge key by key, two booleans
-- are true if either is, and otherwise b stands.
local function Merge(a, b)
    local itemA = Item(a)
    local itemB = Item(b)

    if ((type(a) == "string") or (type(b) == "string")) and (type(itemA) == "string") and (type(itemB) == "string") then
        if itemA == itemB then
            return itemB
        end

        local items = {}

        for item in (itemA .. "," .. itemB):gmatch("[^,]+") do
            items[item] = true
        end

        return Joined(items)
    elseif (type(a) == "table") and (type(b) == "table") then
        local merged = {}

        for key, value in pairs(a) do
            merged[key] = value
        end

        for key, value in pairs(b) do
            merged[key] = Merge(a[key], value)
        end

        return merged
    elseif (type(a) == "boolean") and (type(b) == "boolean") then
        return (a or b)
    end

    return b
end

--- A name's shape: each run of letters (accented ones too) becomes "Aa" and each run of digits "0", so "Dh Taketwo-Area
--- 52" is "Aa Aa-Aa 0"; "empty", the type name, or the marker for a secret otherwise. No name survives.
local function NameShape(value)
    if issecretvalue(value) then
        return Marker(value)
    elseif type(value) ~= "string" then
        return type(value)
    end

    return (((value == "") and "empty") or (value:gsub("[%a\128-\255]+", "Aa"):gsub("%d+", "0")))
end

-- Why a result can't be saved and compared, or nil: only string keys, and strings, booleans, finite numbers and tables
-- of them.
local function Problem(value, path)
    local kind = type(value)

    if issecretvalue(value) then
        return (path .. " is a secret")
    elseif (kind == "string") or (kind == "boolean") then
        return nil
    elseif kind == "number" then
        return ((((value ~= value) or (value == math.huge) or (value == -math.huge)) and (path .. " isn't finite")) or nil)
    elseif kind ~= "table" then
        return ("%s is a %s"):format(path, kind)
    end

    for key, item in pairs(value) do
        if type(key) ~= "string" then
            return (path .. " has a key that isn't a string")
        end

        local problem = Problem(item, path .. "." .. key)

        if problem then
            return problem
        end
    end

    return nil
end

--- Whether two values are equal, or "secret" when either is one (secrets are never compared).
local function Same(a, b)
    if issecretvalue(a) or issecretvalue(b) then
        return "secret"
    end

    return (a == b)
end

--- The value's type name ("nil" for nothing), or the marker for a secret.
local function Shape(value)
    if issecretvalue(value) then
        return Marker(value)
    end

    return type(value)
end

--- A table's string keys, sorted and joined by commas; the Shape of anything else.
local function Fields(tbl)
    if issecretvalue(tbl) or (type(tbl) ~= "table") then
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

local function SortedKeys(...)
    local seen = {}
    local keys = {}

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

    table.sort(keys, function(a, b) return (tostring(a) < tostring(b)) end)

    return keys
end

local function Differences(a, b, path, out)
    if (type(a) == "table") and (type(b) == "table") then
        for _, key in ipairs(SortedKeys(a, b)) do
            Differences(a[key], b[key], ((path == "") and key) or (path .. "." .. key), out)
        end
    elseif a ~= b then
        out[#out + 1] = { a = a, b = b, path = path }
    end

    return out
end

--- "text", "empty" or the type name for a text an API returns, or the marker for a secret.
local function Text(value)
    if issecretvalue(value) then
        return Marker(value)
    elseif type(value) ~= "string" then
        return type(value)
    end

    return (((value == "") and "empty") or "text")
end

--- The value itself, or the marker for a secret.
local function Value(value)
    if issecretvalue(value) then
        return Marker(value)
    end

    return value
end

Probes.ByName = ByName
Probes.List = List
--- The needs by key ({ label, text, step, check, setup | harness }), and the probes in run order and by name.
Probes.Needs = Needs

--- The steps of a starting-zone play session, in order; a need's step indexes it.
Probes.Steps = Steps

--- The UNIT_COMBAT payload shapes seen since load (UnitCombat above), for unitCombat.seen.
Probes.UnitCombat = UnitCombat

--- The kill events seen since load (Kills above), for kills.seen.
Probes.Kills = Kills

--- The chat senders seen, by event (Probes.NoteSender).
Probes.Senders = Senders

--- Your last death and the meter's updates after deaths (Probes.NoteDeath), and how long after a death they count.
Probes.AfterDeath, Probes.AfterDeathSeconds = AfterDeath, AfterDeathSeconds
Probes.NameShape = NameShape

--- The restrictions in force as the client last said, and every one seen since load (Restricted above); the steps of
--- your latest entering and leaving of combat, for combat.edges.
Probes.Restricted, Probes.CombatEdges = Restricted, CombatEdges

--- UNIT_AURA's token shapes, CHAT_MSG_ADDON's field shapes, and chat events' discordInfo shapes, each per restriction
--- text or event (Probes.NoteAuraToken, NoteAddonMessage, NoteDiscordInfo).
Probes.AuraTokens, Probes.AddonMessages, Probes.DiscordInfo = AuraTokens, AddonMessages, DiscordInfo

Probes.Byte, Probes.Fields, Probes.FieldShapes, Probes.Same = Byte, Fields, FieldShapes, Same
Probes.First, Probes.Joined, Probes.Merge = First, Joined, Merge
--- The shape helpers probes record with (documented above).
Probes.Marker, Probes.Shape, Probes.Text, Probes.Value = Marker, Shape, Text, Value

-- An enum's name for a value, or nil.
local function EnumName(enum, value)
    for name, known in pairs(enum) do
        if known == value then
            return name
        end
    end

    return nil
end

-- A boolean an API answered, as text: "true", "false" or "secret".
local function Flag(value)
    return ((issecretvalue(value) and "secret") or tostring(value))
end

-- A GUID's kind ("Player", "Creature", "Pet"...), "secret", or its shape when it isn't a string.
local function GUIDKind(guid)
    if issecretvalue(guid) then
        return "secret"
    end

    return (((type(guid) == "string") and guid:match("^(%a+)%-")) or Shape(guid))
end

-- Adds item to the set kept under key in sets, making the set the first time.
local function Note(sets, key, item)
    local set = sets[key]

    if not set then
        set = {}
        sets[key] = set
    end

    set[item] = true
end

local function RestrictedText()
    local names = {}

    for name in pairs(Restricted.active) do
        names[#names + 1] = name
    end

    table.sort(names)

    return (((#names > 0) and table.concat(names, ",")) or "none")
end

-- A payload field's shape as a set item: "secret", or its Text ("text", "empty", a type name).
local function Token(value)
    return ((issecretvalue(value) and "secret") or Text(value))
end

-- Whose a GUID is, as seen from you: "you", "pet", "other", or "secret".
local function Whose(guid)
    if issecretvalue(guid) then
        return "secret"
    end

    local me = UnitGUID("player")
    local pet = UnitGUID("pet")

    if not issecretvalue(me) and (guid == me) then
        return "you"
    end

    if not issecretvalue(pet) and (pet ~= nil) and (guid == pet) then
        return "pet"
    end

    return "other"
end

--- Adds needs ({ [key] = need }); a key that's already defined is an error.
function Probes.AddNeeds(needs)
    for key, need in pairs(needs) do
        assert(not Needs[key], "duplicate need " .. key)
        Needs[key] = need
    end
end

--- The client build as "<version> (<build>)".
function Probes.Build()
    local version, build = GetBuildInfo()

    return ("%s (%s)"):format(version, build)
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

--- The situation a probe runs in: "combat" or "idle" for combat lockdown, a slash, and the active restrictions
--- (Probes.Restrictions), as in "idle/none" or "combat/Combat".
function Probes.Context()
    return (((InCombatLockdown() and "combat/") or "idle/") .. Probes.Restrictions())
end

--- Adds probes to the end of the run order; a duplicate name or an unknown need is an error.
function Probes.Define(probes)
    for _, probe in ipairs(probes) do
        assert(not ByName[probe.name], "duplicate probe " .. probe.name)

        for _, key in ipairs(probe.needs) do
            assert(Needs[key], ("probe %s: unknown need %s"):format(probe.name, key))
        end

        local version = probe.version

        assert((version == nil) or ((type(version) == "number") and (version >= 2) and ((version % 1) == 0)),
            ("probe %s: version must be a whole number from 2 (leave it out for 1)"):format(probe.name))

        List[#List + 1] = probe
        ByName[probe.name] = probe
    end
end

--- Keeps a CHAT_MSG_ADDON payload's field shapes for comms.addonMessageInLockdown, under the restrictions in force
--- (DevTools.lua passes every one).
function Probes.NoteAddonMessage(...)
    local fields = AddonMessages[Restricted.text]

    if not fields then
        fields = {}
        AddonMessages[Restricted.text] = fields
    end

    for i, field in ipairs(AddonMessageFields) do
        Note(fields, field, Token((select(i, ...))))
    end
end

--- Keeps a UNIT_AURA unit token's shape for units.secretTokenInAuraEvent, under the restrictions in force (DevTools.lua
--- passes the player's and the target's): "secret", or the plain token.
function Probes.NoteAuraToken(unit)
    local shape = "secret"

    if not issecretvalue(unit) then
        shape = ((((type(unit) == "string") and (unit ~= "")) and unit) or Text(unit))
    end

    Note(AuraTokens, Restricted.text, shape)
end

--- Notes a step of entering or leaving combat for combat.edges (DevTools.lua passes PLAYER_REGEN_DISABLED,
--- PLAYER_REGEN_ENABLED, and ADDON_RESTRICTION_STATE_CHANGED with the Combat restriction's state):
--- "<step>[lockdown=<InCombatLockdown()> affecting=<UnitAffectingCombat ("player")>
--- restricted=<IsAddOnRestrictionActive(Combat)>]". PLAYER_REGEN_DISABLED and the restriction's Activating and Active
--- enter, the rest leave; a step of the other edge than the last one's starts that edge over.
---@param state number? the Combat restriction's Enum.AddOnRestrictionState
function Probes.NoteCombatEdge(event, state)
    local label = event
    local kind = (((event == "PLAYER_REGEN_DISABLED") and "enter") or "leave")

    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        label = ("Combat " .. tostring(EnumName(Enum.AddOnRestrictionState, state)))
        kind = (((state == Enum.AddOnRestrictionState.Inactive) and "leave") or "enter")
    end

    if CombatEdges.current ~= kind then
        CombatEdges[kind], CombatEdges.current = {}, kind
    end

    local steps = CombatEdges[kind]

    if #steps >= MaxEdgeSteps then
        return
    end

    local restricted = C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)

    steps[#steps + 1] = ("%s[lockdown=%s affecting=%s restricted=%s]"):format(label, Flag(InCombatLockdown()),
        Flag(UnitAffectingCombat("player")), Flag(restricted))
end

--- Notes your death (DevTools.lua passes PLAYER_DEAD): the meter's updates count for a while.
function Probes.NoteDeath()
    AfterDeath.diedAt = GetTime()
end

--- Keeps a chat event's discordInfo shape for names.chatDiscordInfo (DevTools.lua passes each chat event's 18th payload
--- value), and each field's when it's a table: a boolean as "true" or "false", anything else as its Token.
---@param event string
function Probes.NoteDiscordInfo(event, info)
    Note(DiscordInfo.shapes, event, Token(info))

    if issecretvalue(info) or (type(info) ~= "table") then
        return
    end

    for key, value in pairs(info) do
        if type(key) == "string" then
            local shape = Token(value)

            Note(DiscordInfo.fields, key, ((shape == "boolean") and tostring(value)) or shape)
        end
    end
end

--- Keeps what a kill event says for kills.seen (DevTools.lua passes each one): for PARTY_KILL, whose blow and the
--- victim's kind; for UNIT_DIED, the unit's kind; for PLAYER_TARGET_DIED, that it fired.
function Probes.NoteKill(event, ...)
    if event == "PARTY_KILL" then
        local attacker, target = ...

        Kills.partyKill = (Kills.partyKill or {})
        Note(Kills.partyKill, "attacker", Whose(attacker))
        Note(Kills.partyKill, "target", GUIDKind(target))
        Note(Kills.partyKill, "attackerKind", GUIDKind(attacker))
    elseif event == "UNIT_DIED" then
        Kills.unitDied = (Kills.unitDied or {})
        Note(Kills.unitDied, "unit", GUIDKind((...)))
    elseif event == "PLAYER_TARGET_DIED" then
        Kills.targetDied = true
    end
end

--- Notes a damage meter update (DevTools.lua passes DAMAGE_METER_COMBAT_SESSION_UPDATED's type) shortly after your
--- death: its DamageMeterType's name, "secret", or "unknown".
function Probes.NoteMeterUpdate(meterType)
    local diedAt = AfterDeath.diedAt

    if not diedAt or ((GetTime() - diedAt) > AfterDeathSeconds) then
        return
    end

    local name = "secret"

    if not issecretvalue(meterType) then
        name = "unknown"

        for key, value in pairs(Enum.DamageMeterType) do
            if value == meterType then
                name = key
            end
        end
    end

    AfterDeath.types[name] = true
end

--- Follows an ADDON_RESTRICTION_STATE_CHANGED (DevTools.lua passes each): a restriction counts from Activating, which
--- the client enforces once that dispatch ends, until Inactive. Cheaper than Probes.Restrictions for the listeners that
--- key what they hear by it.
function Probes.NoteRestriction(kind, state)
    local name = EnumName(Enum.AddOnRestrictionType, kind)

    if not name then
        return
    end

    local active = (state ~= Enum.AddOnRestrictionState.Inactive)

    Restricted.active[name] = (active or nil)

    if active then
        Restricted.seen[name] = true
    end

    Restricted.text = RestrictedText()
end

--- Keeps a chat event's sender shape for names.chatSenders (DevTools.lua passes each one).
---@param event string
function Probes.NoteSender(event, sender)
    Note(Senders, event, (issecretvalue(sender) and "secret") or NameShape(sender))
end

--- Keeps a UNIT_COMBAT payload's shapes for unitCombat.seen: per unit and action, each field's shapes, and the plain
--- action and flag strings seen. DevTools.lua passes every payload it registers for, so unit is "player" or "target"
--- (UNIT_COMBAT carries no secret flags).
function Probes.NoteUnitCombat(unit, action, flagText, amount, schoolMask)
    local byAction = UnitCombat.units[unit]
    local plainAction = (not issecretvalue(action) and (type(action) == "string") and (action ~= ""))
    local key = ((plainAction and action) or Token(action))
    local fields = byAction[key]

    if not fields then
        fields = {}
        byAction[key] = fields
    end

    Note(fields, "action", Token(action))
    Note(fields, "flagText", Token(flagText))
    Note(fields, "amount", (issecretvalue(amount) and "secret") or type(amount))
    Note(fields, "schoolMask", (issecretvalue(schoolMask) and "secret") or type(schoolMask))

    if (unit == "player") and InCombatLockdown() then
        UnitCombat.amountInCombat = ((issecretvalue(amount) and "secret") or type(amount))
    end

    if plainAction then
        UnitCombat.actions[action] = true
    end

    if not issecretvalue(flagText) and (type(flagText) == "string") and (flagText ~= "") then
        UnitCombat.flagTexts[flagText] = true
    end
end

--- The active addon restrictions: "none", or their Enum.AddOnRestrictionType names, sorted and joined by commas.
function Probes.Restrictions()
    local active = {}

    for name, value in pairs(Enum.AddOnRestrictionType) do
        if C_RestrictedActions.IsAddOnRestrictionActive(value) then
            active[#active + 1] = name
        end
    end

    table.sort(active)

    return (((#active > 0) and table.concat(active, ",")) or "none")
end

--- The step of the play session that meets all of the probe's needs: the latest of their steps, or the first step for a
--- probe that runs anywhere.
function Probes.Step(probe)
    local step = 1

    for _, key in ipairs(probe.needs) do
        step = math.max(step, Needs[key].step)
    end

    return step
end

--- Reads the restrictions in force from the client, for when no event said (DevTools.lua calls it at load and on
--- PLAYER_ENTERING_WORLD).
function Probes.SyncRestrictions()
    for name, value in pairs(Enum.AddOnRestrictionType) do
        local active = C_RestrictedActions.IsAddOnRestrictionActive(value)

        Restricted.active[name] = (active or nil)

        if active then
            Restricted.seen[name] = true
        end
    end

    Restricted.text = RestrictedText()
end

--- The listeners' helpers, for the probe files' own listeners (ProbesCombat.lua's and ProbesOrder.lua's).
Probes.EnumName, Probes.Flag, Probes.Note, Probes.Token = EnumName, Flag, Note, Token

-- The probe's needs' field (text or label) joined with " + ", or none for a probe that runs anywhere.
local function NeedsJoined(probe, field, none)
    local parts = {}

    for i, key in ipairs(probe.needs) do
        parts[i] = Needs[key][field]
    end

    return (((#parts > 0) and table.concat(parts, " + ")) or none)
end

--- Where two records (or any values of the kind a record holds) differ: a list of { path, a, b }, sorted by path; empty
--- when they're equal.
function Probes.Diff(a, b)
    return Differences(a, b, "", {})
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

--- Whether a record was made by the probe's current version, so it answers the probe's question.
---@param record table? a record, or nil
function Probes.IsCurrent(probe, record)
    return ((type(record) == "table") and ((record.version or 1) == Probes.Version(probe)))
end

--- Shape sets (Note's) as a record holds them: each set joined by commas, a table of sets likewise, key by key.
---@param sets table
---@return table
function Probes.JoinSets(sets)
    local out = {}

    for key, set in pairs(sets) do
        local _, first = next(set)

        out[key] = (((type(first) == "table") and Probes.JoinSets(set)) or Joined(set))
    end

    return out
end

--- Folds a new record into the saved one by the rules in the header: the record to save, and how it differs from the
--- saved one: "new" (nothing current was saved), "changed" (another result), "confirmed" (the same result in a new
--- context or on another build) or "same".
---@param previous table? the saved record, or nil
---@param record table a record Probes.Record just made; Keep may change it
---@return table saved
---@return string outcome
---@return table differences the results' (Probes.Diff), for "changed"
function Probes.Keep(probe, previous, record)
    if not Probes.IsCurrent(probe, previous) then
        return record, "new", {}
    end

    local sameBuild = (previous.build == record.build)

    if probe.accumulates and sameBuild then
        record.result = Merge(previous.result, record.result)
    end

    local differences = Differences(previous.result, record.result, "", {})

    if sameBuild and (probe.accumulates or (#differences == 0)) then
        record.contexts = Merge(previous.contexts, record.contexts)
    end

    if #differences > 0 then
        return record, "changed", differences
    end

    return record, (((#Differences(previous, record, "", {}) > 0) and "confirmed") or "same"), differences
end

--- The needs' short labels joined with " + ", or "anywhere" for a probe that runs anywhere.
function Probes.NeedsLabel(probe)
    return NeedsJoined(probe, "label", "anywhere")
end

--- The needs' texts joined with " + ", or "nothing" for a probe that runs anywhere.
function Probes.NeedsText(probe)
    return NeedsJoined(probe, "text", "nothing")
end

--- Runs the probe and returns its record, or nil and why it failed (an error or a result that can't be saved).
---@return table? record { build, contexts, result, version? }, its contexts the one it ran in
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

    -- Nil for a version 1 probe, so its records match the ones that carry no version.
    local version = probe.version

    return { build = Probes.Build(), contexts = { [context] = true }, result = result, version = version }, nil
end

--- Recreates the probe's needs in a test harness, in the order the probe lists them.
function Probes.Setup(probe, h)
    for _, key in ipairs(probe.needs) do
        Needs[key].setup(h)
    end
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

    return ("{ " .. table.concat(parts, ", ") .. " }")
end

--- The probe's version: probe.version, or 1.
function Probes.Version(probe)
    return (probe.version or 1)
end

ns.Probes = Probes
