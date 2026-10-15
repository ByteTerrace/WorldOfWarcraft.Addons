local addonName, ns = ...

-- Calibration probes about Blizzard's damage meter (C_DamageMeter) and death recaps
-- (C_DeathRecap): what a session holds idle, in combat and right after a fight, the local
-- player's damage taken, the enemies' sources, and a death. Recaps record common fields and
-- the killing blow's common shape; separate swing/spell probes require that event kind before
-- recording its spell fields. Also the order of the steps into and out of combat (combat.edges),
-- whether the meter's totals are secret on leaving a PvP fight (damageMeter.pvpSecrecy), and
-- ENCOUNTER_WARNING's payload (encounterWarning.seen), from what DevTools.lua heard. Probes.lua's
-- header is the contract; ProbeNeeds.lua defines needs.
--
-- The last two keep what they hear here, as Probes.lua's listeners do (sets of shapes):
-- DevTools.lua passes each PLAYER_REGEN_ENABLED to Probes.NotePvPLeftCombat, which in a PvP match
-- reads the damage meter then and PvPLaterSeconds later, and ENCOUNTER_START and ENCOUNTER_WARNING
-- to Probes.NoteEncounterStart and NoteEncounterWarning.

-- Spell and environmental payloads depend on the event kind; mitigation is optional in
-- Blizzard_DeathRecap's damage tooltip. Neither belongs in the common event shape.
local ConditionalRecapFields = {
    absorbed = true, avoidable = true, blocked = true, deadly = true, environmentalType = true, resisted = true,
    spellId = true, spellName = true, spellSchool = true,
}
local RecapSpellFields = { "spellId", "spellName", "spellSchool", "avoidable", "deadly" }

local Probes = ns.Probes
local EnumName, Note, Restricted, Token = Probes.EnumName, Probes.Note, Probes.Restricted, Probes.Token
local Fields, FieldShapes, Same = Probes.Fields, Probes.FieldShapes, Probes.Same
local First, Joined, JoinSets = Probes.First, Probes.Joined, Probes.JoinSets
local Marker, Shape, Text, Value = Probes.Marker, Probes.Shape, Probes.Text, Probes.Value

-- The current DamageDone session's totals read on leaving combat in a PvP match
-- (Probes.NotePvPLeftCombat): leftCombat (at PLAYER_REGEN_ENABLED) and later (PvPLaterSeconds on)
-- each map where the read was ("<IsInInstance type>/<restrictions>", as in "pvp/PvPMatch") to the
-- set of shapes of totalAmount (the session's) and localTotalAmount (the local player's entry's,
-- "none" without one).
local PvPMeter = { later = {}, leftCombat = {} }

-- Boss encounters and their warnings since load (Probes.NoteEncounterStart, NoteEncounterWarning):
-- whether ENCOUNTER_START fired, and the sets of ENCOUNTER_WARNING's info shapes and of each of
-- its fields' shapes.
local EncounterWarnings = { fields = {}, shapes = {}, started = false }

-- IsInInstance's type ("none", "pvp", "arena", ...), or "secret".
local function InstanceType()
    local _, instanceType = IsInInstance()

    return ((issecretvalue(instanceType) and "secret") or tostring(instanceType))
end

-- Keeps the shapes of the current DamageDone session's totals under when ("leftCombat" or
-- "later"), keyed by where you are and the restrictions in force.
local function NotePvPMeter(when)
    local types = Enum.DamageMeterSessionType
    -- secret: totals go through Token; the sources list and isLocalPlayer are checked with issecretvalue
    local session = C_DamageMeter.GetCombatSessionFromType(types.Current, Enum.DamageMeterType.DamageDone)
    local where = (InstanceType() .. "/" .. Restricted.text)
    local fields = PvPMeter[when][where]

    if not fields then
        fields = {}
        PvPMeter[when][where] = fields
    end
    Note(fields, "totalAmount", Token(session.totalAmount))
    local localTotal, sources = "none", session.combatSources

    if not issecretvalue(sources) and (type(sources) == "table") then
        for _, source in ipairs(sources) do
            local isLocalPlayer = source.isLocalPlayer

            if not issecretvalue(isLocalPlayer) and (isLocalPlayer == true) then
                localTotal = Token(source.totalAmount)
            end
        end
    end
    Note(fields, "localTotalAmount", localTotal)
end

--- The PvP meter reads and the encounters and warnings seen (above), for their probes and needs.
Probes.PvPMeter, Probes.EncounterWarnings = PvPMeter, EncounterWarnings

--- On leaving combat (DevTools.lua passes each PLAYER_REGEN_ENABLED) in a PvP match (the PvPMatch
--- restriction, a battleground or an arena), keeps the shapes of the damage meter's totals for
--- damageMeter.pvpSecrecy, then and again PvPLaterSeconds later. Elsewhere it does nothing.
function Probes.NotePvPLeftCombat()
    local instanceType = InstanceType()

    if not Restricted.active.PvPMatch and (instanceType ~= "pvp") and (instanceType ~= "arena") then
        return
    end
    NotePvPMeter("leftCombat")
    C_Timer.After(Probes.PvPLaterSeconds, function() NotePvPMeter("later") end)
end

--- Notes a boss encounter's start (DevTools.lua passes ENCOUNTER_START), for encounterWarning.seen.
function Probes.NoteEncounterStart()
    EncounterWarnings.started = true
end

--- Keeps an ENCOUNTER_WARNING payload's shapes for encounterWarning.seen (DevTools.lua passes each):
--- the info's Token, and each field's: "secret", a boolean as "true" or "false", a plain severity
--- as its Enum.EncounterEventSeverity name, anything else as its Token.
function Probes.NoteEncounterWarning(info)
    EncounterWarnings.shapes[Token(info)] = true
    if issecretvalue(info) or (type(info) ~= "table") then
        return
    end
    for key, value in pairs(info) do
        if type(key) == "string" then
            local shape = Token(value)

            if shape == "boolean" then
                shape = tostring(value)
            elseif (key == "severity") and (shape == "number") then
                shape = (EnumName(Enum.EncounterEventSeverity, value) or "unknown")
            end
            Note(EncounterWarnings.fields, key, shape)
        end
    end
end

-- Which damage meter session a session's duration matches in the available list (oldest
-- first): "latest", "previous", "neither", "none" (no duration) or "secret".
local function WhichSession(durationSeconds, sessions)
    if issecretvalue(durationSeconds) then
        return "secret"
    elseif durationSeconds == nil then
        return "none"
    end
    local latest, previous = sessions[#sessions], sessions[#sessions - 1]

    if latest and (Same(latest.durationSeconds, durationSeconds) == true) then
        return "latest"
    elseif previous and (Same(previous.durationSeconds, durationSeconds) == true) then
        return "previous"
    end
    return "neither"
end

-- A damage meter session's session-level fields.
local function SessionShape(session)
    local sources = session.combatSources

    return {
        durationSeconds = Shape(session.durationSeconds),
        totalAmount = Shape(session.totalAmount),
        maxAmount = Shape(session.maxAmount),
        combatSources = Shape(sources),
        hasSources = (not issecretvalue(sources) and (type(sources) == "table") and (sources[1] ~= nil)),
    }
end

-- The current damage meter session of a DamageMeterType.
local function CurrentSession(meterType)
    local types = Enum.DamageMeterSessionType

    return C_DamageMeter.GetCombatSessionFromType(types.Current, meterType) -- secret: fields go through Shape
end

-- A damage meter spell (DamageMeterCombatSpell) and its details, as shapes.
local function SpellShape(spell)
    local details = spell.combatSpellDetails
    local plainDetails = ((not issecretvalue(details) and (type(details) == "table") and details) or {})

    return {
        fields = Fields(spell), spellID = Shape(spell.spellID), creatureName = Text(spell.creatureName),
        isDeadly = Shape(spell.isDeadly), isAvoidable = Shape(spell.isAvoidable),
        overkillAmount = Shape(spell.overkillAmount), details = Fields(details), unitName = Text(plainDetails.unitName),
        isMob = Shape(plainDetails.isMob), classification = Text(plainDetails.classification),
    }
end

-- The local player's entry in the current session's Deaths list, or nil.
local function LocalDeath()
    local sources = CurrentSession(Enum.DamageMeterType.Deaths).combatSources

    if issecretvalue(sources) or (type(sources) ~= "table") then
        return nil
    end
    for _, source in ipairs(sources) do
        local isLocalPlayer = source.isLocalPlayer

        if not issecretvalue(isLocalPlayer) and (isLocalPlayer == true) then
            return source
        end
    end
    return nil
end

local function CommonRecapShape(event)
    local shapes = FieldShapes(event)

    for field in pairs(ConditionalRecapFields) do
        shapes[field] = nil
    end
    return shapes
end

-- Every sample of the requested kind must agree on its field shapes, including nil. The need
-- guarantees at least one sample, so a missing kind never becomes a successful observation.
local function RecapSpellShapes(kind)
    local result = {}

    for _, event in ipairs(C_DeathRecap.GetRecapEvents()) do
        local eventKind = event.event

        if not issecretvalue(eventKind) and (eventKind == kind) then
            for _, field in ipairs(RecapSpellFields) do
                local shape = Shape(event[field])

                assert((result[field] == nil) or (#Probes.Diff(result[field], shape) == 0),
                    kind .. "." .. field .. " varies between recap events")
                result[field] = shape
            end
        end
    end
    return result
end

Probes.Define({
    {
        name = "damageMeter.available",
        needs = {},
        run = function()
            local isAvailable, failureReason = C_DamageMeter.IsDamageMeterAvailable()

            return { isAvailable = Value(isAvailable), failureReason = Value(failureReason) }
        end,
    },
    {
        name = "damageMeter.sessions",
        needs = { "idle", "twoFights" },
        run = function()
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            local first, last = sessions[1], sessions[#sessions]
            local oldestFirst = ((Same(first.sessionID, last.sessionID) == false) and (first.sessionID < last.sessionID))

            return {
                fields = Fields(last), sessionID = Shape(last.sessionID), name = Text(last.name),
                durationSeconds = Shape(last.durationSeconds), oldestFirst = oldestFirst,
            }
        end,
    },
    {
        name = "damageMeter.typesIdle",
        needs = { "idle", "twoFights" },
        run = function()
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            local types = Enum.DamageMeterSessionType
            local current = CurrentSession(Enum.DamageMeterType.DamageDone)
            local expired = C_DamageMeter.GetCombatSessionFromType(types.Expired, Enum.DamageMeterType.DamageDone) -- secret: fields go through Shape
            local currentShape, expiredShape = SessionShape(current), SessionShape(expired)

            currentShape.session = WhichSession(current.durationSeconds, sessions)
            expiredShape.session = WhichSession(expired.durationSeconds, sessions)
            return { current = currentShape, expired = expiredShape }
        end,
    },
    {
        name = "damageMeter.currentInCombat",
        needs = { "meterInCombat" },
        run = function()
            return SessionShape(CurrentSession(Enum.DamageMeterType.DamageDone))
        end,
    },
    {
        name = "damageMeter.afterFight",
        needs = { "afterFight" },
        run = function()
            local types = Enum.DamageMeterType

            return {
                damageTaken = SessionShape(CurrentSession(types.DamageTaken)),
                enemyDamageTaken = SessionShape(CurrentSession(types.EnemyDamageTaken)),
            }
        end,
    },
    {
        name = "damageMeter.playerDamageTaken",
        needs = { "afterFight" },
        run = function()
            local guid = UnitGUID("player") -- secret: checked with issecretvalue before it goes back to the API

            if issecretvalue(guid) then
                return { guid = Marker(guid) }
            end
            local current, damageTaken = Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageTaken
            -- secret: fields go through Shape
            local source = C_DamageMeter.GetCombatSessionSourceFromType(current, damageTaken, guid)
            local spell = First(source.combatSpells)

            return {
                fields = Fields(source), totalAmount = Shape(source.totalAmount), hasSpells = (spell ~= nil),
                combatSpells = Shape(source.combatSpells), spell = ((spell and SpellShape(spell)) or nil),
            }
        end,
    },
    {
        name = "damageMeter.enemySource",
        needs = { "afterFight" },
        -- The need saw a plain sources list with an entry, so the first source is there.
        run = function()
            local source = First(CurrentSession(Enum.DamageMeterType.EnemyDamageTaken).combatSources)

            return {
                hasSources = true, fields = Fields(source), name = Text(source.name),
                sourceGUID = Shape(source.sourceGUID), sourceCreatureID = Shape(source.sourceCreatureID),
                sourceDisplayType = Value(source.sourceDisplayType),
                factionGroup = Shape(source.factionGroup), classification = Text(source.classification),
                isLocalPlayer = Value(source.isLocalPlayer),
            }
        end,
    },
    {
        name = "damageMeter.death",
        needs = { "diedToMob" },
        run = function()
            local death = LocalDeath()

            if not death then
                return { localPlayer = false }
            end
            local recapID = death.deathRecapID

            return {
                localPlayer = true, fields = Fields(death), deathRecapID = Shape(recapID),
                hasRecapID = (not issecretvalue(recapID) and (type(recapID) == "number") and (recapID ~= 0)),
                deathTimeSeconds = Shape(death.deathTimeSeconds),
            }
        end,
    },
    {
        -- The fields each kind of recap event carries (SWING_DAMAGE, SPELL_DAMAGE, ENVIRONMENTAL_DAMAGE,
        -- ...): a field counts for a kind when every event of that kind in the recap had it. Kept per
        -- kind and across deaths, since which kinds a recap holds depends on how you died.
        name = "deathRecap.events",
        version = 3, -- versions 1 and 2 kept one field list for every event, which depended on how you died
        needs = { "diedToMob" },
        accumulates = true,
        run = function()
            local death = LocalDeath()
            local recapID = (death and death.deathRecapID)

            if issecretvalue(recapID) or (type(recapID) ~= "number") or (recapID == 0) then
                return { recapID = Shape(recapID) }
            end
            local events = C_DeathRecap.GetRecapEvents(recapID)
            local killingBlow = First(events)
            local byKind = {}

            for _, event in ipairs((killingBlow and events) or {}) do
                local kind = event.event

                if not issecretvalue(kind) and (type(kind) == "string") then
                    local fields = CommonRecapShape(event)
                    local kept = byKind[kind]

                    if kept then
                        for key in pairs(kept) do
                            if fields[key] == nil then
                                kept[key] = nil
                            end
                        end
                    else
                        byKind[kind] = fields
                    end
                end
            end
            local fieldsByKind = {}

            for kind, fields in pairs(byKind) do
                fieldsByKind[kind] = Joined(fields)
            end
            return {
                recapID = "number", hasRecapEvents = Value(C_DeathRecap.HasRecapEvents(recapID)),
                events = Shape(events), fieldsByKind = fieldsByKind,
                killingBlow = ((killingBlow and CommonRecapShape(killingBlow)) or nil),
                sourceName = ((killingBlow and Text(killingBlow.sourceName)) or nil),
                maxHealth = Shape(C_DeathRecap.GetRecapMaxHealth(recapID)),
            }
        end,
    },
    {
        name = "deathRecap.swingFields",
        needs = { "diedToMob", "recapSwingDamage" },
        run = function() return RecapSpellShapes("SWING_DAMAGE") end,
    },
    {
        name = "deathRecap.spellFields",
        needs = { "diedToMob", "recapSpellDamage" },
        run = function() return RecapSpellShapes("SPELL_DAMAGE") end,
    },
    {
        -- Which damage meter updates follow a death: whether the death fact could listen for the
        -- Deaths type alone while it waits for your recap (FactsDeath.lua reads on every update).
        name = "damageMeter.afterDeath",
        needs = { "diedToMob", "deathWatched" },
        accumulates = true,
        run = function()
            return { types = ((next(Probes.AfterDeath.types) and Joined(Probes.AfterDeath.types)) or "none") }
        end,
    },
    {
        -- Blizzard's death popup asks for the recap with no ID (GameDialogDefs.lua): your latest.
        name = "deathRecap.latest",
        needs = { "diedToMob" },
        run = function()
            local death = LocalDeath()
            local recapID = (death and death.deathRecapID)
            local latest = C_DeathRecap.GetRecapEvents()
            local blow = First(latest)
            local result = { hasLatest = Value(C_DeathRecap.HasRecapEvents()), latest = Shape(latest) }

            if blow and not issecretvalue(recapID) and (type(recapID) == "number") and (recapID ~= 0) then
                local byID = First(C_DeathRecap.GetRecapEvents(recapID))
                -- false when a plain field differs, else "secret" when one couldn't be compared.
                local same = (byID ~= nil)

                for _, field in ipairs((byID and { "timestamp", "sourceName", "amount" }) or {}) do
                    local verdict = Same(blow[field], byID[field])

                    if verdict == false then
                        same = false
                        break
                    elseif verdict == "secret" then
                        same = "secret"
                    end
                end
                result.sameAsMeter = same
            end
            return result
        end,
    },
    {
        -- The steps of your latest entering and leaving of combat, in the order they came, each with
        -- what InCombatLockdown, UnitAffectingCombat("player") and IsAddOnRestrictionActive(Combat)
        -- said then (Probes.NoteCombatEdge). Kombat.lua's victory waits for the damage meter on the
        -- assumption that the Combat restriction can outlast PLAYER_REGEN_ENABLED; the leave edge
        -- says whether it does. A session whose order differs adds its own sequence.
        name = "combat.edges",
        needs = { "idle", "combatEdges" },
        accumulates = true,
        run = function()
            local edges = Probes.CombatEdges

            return { enter = table.concat(edges.enter, " > "), leave = table.concat(edges.leave, " > ") }
        end,
    },
    {
        -- Whether the damage meter's totals stay secret in a PvP match once you leave combat: the
        -- current DamageDone session's totalAmount and your own entry's, read at
        -- PLAYER_REGEN_ENABLED (leftCombat) and PvPLaterSeconds later (later), each under where it
        -- was read ("pvp/PvPMatch"). The docs flag the session getters SecretWhenInCombat only;
        -- Details! treats arena sessions as secret, which may be its main-game path.
        name = "damageMeter.pvpSecrecy",
        needs = { "pvpFight" },
        accumulates = true,
        run = function()
            local meter = Probes.PvPMeter

            return { leftCombat = JoinSets(meter.leftCombat), later = JoinSets(meter.later) }
        end,
    },
    {
        -- Whether the client fires ENCOUNTER_WARNING in boss encounters, and its
        -- EncounterWarningInfo's fields' shapes (the docs mark text, the caster's and target's
        -- names and GUIDs, the icon, spell, isDeadly and color SecretValue; severity,
        -- duration and the should* flags not). BigWigs listens for it on Forever, DBM only in the
        -- main game. Also whether C_EncounterWarnings says the feature is there and turned on.
        name = "encounterWarning.seen",
        needs = { "encounter" },
        accumulates = true,
        run = function()
            local seen = Probes.EncounterWarnings
            local warnings = C_EncounterWarnings
            local result = {
                heard = (next(seen.shapes) ~= nil),
                featureAvailable = Value(warnings.IsFeatureAvailable()),
                featureEnabled = Value(warnings.IsFeatureEnabled()),
            }

            if result.heard then
                result.info, result.fields = Joined(seen.shapes), JoinSets(seen.fields)
            end
            return result
        end,
    },
})
