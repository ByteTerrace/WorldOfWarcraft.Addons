-- Blizzard's damage meter (C_DamageMeter) and death recaps (C_DeathRecap) in the fake client (see
-- wow.lua for the rest). Sources: DamageMeterDocumentation.lua, DamageMeterConstantsDocumentation.lua
-- and DeathRecapDocumentation.lua, and how Blizzard_DamageMeter and Blizzard_DeathRecap (the
-- forever branch of Gethe/wow-ui-source) consume them. [D] marks a documented decision, [G] a guess
-- where the docs and Blizzard's code are silent.
--
-- Sessions:
--   [G] Every combat is a session: h:EnterCombat starts one (the next sessionID, counting from 1)
--       after PLAYER_REGEN_DISABLED and fires DAMAGE_METER_CURRENT_SESSION_UPDATED; h:LeaveCombat
--       ends it before PLAYER_REGEN_ENABLED, freezing its duration. A relog clears every session
--       and recap; a /reload keeps them (they're the client's, not the UI's).
--   [G] Current is the latest session, in progress or ended, until the next combat starts one.
--       [E] Expired is empty after ordinary fights (damageMeter.typesIdle: no sources and no
--       duration, idle after two kills); what it holds later isn't known yet. Overall merges every session:
--       sources merge by GUID (else creature ID, else name), amounts add up, and its duration is
--       the sum of the sessions' durations.
--   [G] GetAvailableCombatSessions lists every session oldest first ({ sessionID, name,
--       durationSeconds }; third-party meters read the newest as the last). [E] name is never
--       empty in the client (damageMeter.sessions); its format isn't known, so it's what the test
--       gave (h:MeterFight's name), else "Combat <id>".
--       The client's cap on kept sessions is unknown; the harness keeps them all.
--   [D] Adding data fires DAMAGE_METER_COMBAT_SESSION_UPDATED twice per changed type: (type, 0)
--       for Overall, then (type, sessionID) for the current session (DamageMeterSessionWindow.lua:
--       "Two events are always dispatched"). [G] A DamageDone change also fires for Dps and a
--       HealingDone change for Hps (Blizzard's window filters by its own type); a death fires for
--       Deaths. Ending a session fires nothing. [P] damageMeter.afterDeath: your own death reaches
--       the meter after PLAYER_DEAD (its DamageTaken and Deaths updates came in the seconds after),
--       so h:MeterFight adds the local player's dying source then; [G] at once, before combat ends.
--   [G] No session of the asked kind returns an empty session: no sources,
--       amounts 0, durationSeconds nil (the return isn't Nilable). An unknown source returns no
--       spells and amounts 0.
-- Data:
--   [G] Dps and Hps read DamageDone's and HealingDone's entries: the rate is each entry's
--       amountPerSecond (third-party meters found the same totals under Dps in game).
--   [G] combatSources are sorted by totalAmount, largest first; maxAmount is the largest entry,
--       totalAmount their sum; amountPerSecond is totalAmount over the session's duration so far
--       (0 while it's 0). combatSpells sort the same way.
--   [D] Deaths lists one entry per death (Blizzard's window draws each as a death with its time):
--       deathRecapID ~= 0, totalAmount 0, deathTimeSeconds the seconds into the session ([G]),
--       and -1 in Overall (DamageMeterEntry.lua: "no timestamps for overall session"). Every
--       other type's entries carry deathRecapID 0 and deathTimeSeconds 0 ([G]).
--   [D] combatSpellDetails is one DamageMeterCombatSpellUnitDetails per spell, not a list.
--   [E] Forever has no specializations: sources and spell details carry no specIconID
--       (damageMeter.enemySource, damageMeter.playerDamageTaken). A mob in EnemyDamageTaken has
--       sourceDisplayType None, and a mob's melee in your DamageTaken has an empty creatureName
--       (its name is in the details' unitName).
--   [E] The local player's entry has no factionGroup (damageMeter.death), and a Deaths entry
--       carries specIconID 0 though other types carry none.
--   [G] Defaults: classFilename "", classification "", isLocalPlayer false,
--       sourceDisplayType None, factionGroup nil (another player's unit fills it in); a player source without a GUID gets one (the
--       same one for the same name, so Overall merges it across fights), a creature (creatureID)
--       has sourceGUID nil.
-- Secrets:
--   [D] The two session getters are SecretWhenInCombat: while the Combat restriction holds, their
--       fields are secret except the NeverSecret ones (classFilename, specIconID, isLocalPlayer,
--       deathRecapID, classification; the details' unitClassFilename, classification,
--       specIconID). [G] ConditionalSecret fields (name, sourceGUID) are secret whenever the
--       predicate holds, since the docs don't name their condition; the tables and lists stay
--       plain (Blizzard's untainted window ipairs them in combat, and nothing documents secret
--       tables here). GetAvailableCombatSessions has no flags.
--   [D] SecretArguments AllowedWhenUntainted: addon code can't pass back a secret GUID (a
--       third-party meter hit exactly that refusal in game).
-- Death recaps:
--   [G] Each death h:MeterFight or h:MeterAdd scripts gets the next recap ID (from 1). The API has
--       no secret flags. GetRecapEvents returns the events newest first (Blizzard_DeathRecap
--       treats the first as the killing blow). [E] DeathRecapEventInfo is a combat log event
--       (deathRecap.events): timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags,
--       sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, amount, overkill, school,
--       critical, glancing, crushing, isOffHand and currentHP, all plain, for a mob's melee
--       killing blow; [E] spell events add spellId, spellName, spellSchool, avoidable and deadly
--       (deathRecap.events, a mob's spell before its melee killing blow); [D] environmental ones
--       add environmentalType (what Blizzard_DeathRecap.lua reads), and absorbed, resisted and
--       blocked may appear. A death without scripted events gets one per DamageTaken spell: the
--       Auto Attack spell (6603) is a SWING_DAMAGE with no spell fields, any other a
--       SPELL_DAMAGE. Scripted SWING_DAMAGE also omits spell fields: Blizzard_DeathRecap's
--       GetEventInfo supplies the swing's display spell itself. [G] school 1 unless the spell
--       gives one, critical, glancing, crushing and
--       isOffHand false, raid flags 0, flags 0xA48 for a hostile mob, 0x548 for a hostile player,
--       0x1148 for a hostile player's pet and 0x511 for the player dying, and currentHP the health left after the hit (0
--       for the killing blow). An unknown ID returns no events and max health 0.
--       [D] A nil ID means your latest death: Blizzard's death popup calls HasRecapEvents() and
--       OpenDeathRecapUI() with none (GameDialogDefs.lua). [G] Deaths of other units don't count.
-- Availability: [D] IsDamageMeterAvailable returns isAvailable, failureReason; true, "" by default
-- (the real client returned true in game). h:SetMeterAvailable(false, reason) changes it.
--
-- Scripting a fight (see the functions below): h:MeterFight{ name, duration, endCombat, sources =
-- { source, ... } } with a source:
--   { unit = "player" or a unit table (fills name, GUID, class, isLocalPlayer, faction),
--     name, guid, creatureID, classFilename, specIconID, isLocalPlayer, classification,
--     factionGroup, sourceDisplayType,
--     amounts = { DamageDone = 1200, [Enum.DamageMeterType.HealingDone] = 5000, ... },
--     spells = { DamageTaken = { { spellID, name (the recap's spellName; else h.spellNames), totalAmount,
--       creatureName, overkillAmount, isAvoidable,
--       isDeadly, details = { unitName, unitClassFilename, classification, isPet, isMob, amount,
--       specIconID, unit (a unit table: the recap's attacker is that unit, GUID and all) } }, ... } },
--     death = { time, maxHealth, events = { oldest first, each { event, amount, sourceName, ... } } } }
-- A type with spells but no amount gets the spells' sum. A death without events gets one event
-- per DamageTaken spell (SWING_DAMAGE for Auto Attack, SPELL_DAMAGE otherwise, in the given
-- order, the last the killing blow).

local Snapshot = __snapshot
local Types = Snapshot.enums.DamageMeterType
local SessionTypes = Snapshot.enums.DamageMeterSessionType
local DisplayTypes = Snapshot.enums.DamageMeterSourceDisplayType

-- Rate types read their base type's entries; a base type's change also updates its rate type.
local Base = { [Types.Dps] = Types.DamageDone, [Types.Hps] = Types.HealingDone }
local Rate = { [Types.DamageDone] = Types.Dps, [Types.HealingDone] = Types.Hps }

local NeverSecretSource = { classFilename = true, specIconID = true, isLocalPlayer = true, deathRecapID = true, classification = true }
local NeverSecretDetails = { unitClassFilename = true, classification = true, specIconID = true }
local RecapFields = {
    "timestamp", "event", "hideCaster", "sourceGUID", "sourceName", "sourceFlags", "sourceRaidFlags", "destGUID",
    "destName", "destFlags", "destRaidFlags", "spellId", "spellName", "spellSchool", "environmentalType", "amount",
    "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing", "isOffHand",
    "currentHP", "avoidable", "deadly",
}
local RecapSpellFields = { spellId = true, spellName = true, spellSchool = true, avoidable = true, deadly = true }
local AutoAttack = 6603
-- Combat log object flags (COMBATLOG_OBJECT_*): a hostile outsider NPC, player and player's pet,
-- and you.
local Flags = { mob = 0xA48, enemyPlayer = 0x548, enemyPet = 0x1148, player = 0x511 }

function Harness:InitMeter()
    self.meter = { sessions = {}, nextID = 1, recaps = {}, nextRecap = 1, available = true, failureReason = "" }
    self.meterGUIDs = self.meterGUIDs or {} -- [name], or ["mob:"|"player:" .. name] for a recap attacker, = its GUID
end

function Harness:SetMeterAvailable(isAvailable, failureReason)
    self.meter.available, self.meter.failureReason = isAvailable and true or false, failureReason or ""
end

-- A DamageMeterType from its value or name.
local function MeterType(key)
    local value = type(key) == "string" and Types[key] or key
    for _, known in pairs(Types) do
        if known == value then
            return value
        end
    end
    error("unknown DamageMeterType " .. tostring(key), 3)
end

local function Duration(h, session)
    return (session.finish or h.time) - session.start
end

-- The session in progress, or nil.
function Harness:MeterActive()
    local latest = self.meter.sessions[#self.meter.sessions]
    if latest and not latest.finish then
        return latest
    end
end

-- Starts a session (h:EnterCombat calls this) and fires DAMAGE_METER_CURRENT_SESSION_UPDATED.
function Harness:MeterStartSession()
    local m = self.meter
    local session = { id = m.nextID, name = "Combat " .. m.nextID, start = self.time, startServer = self.serverTime, sources = {}, order = {} }
    m.nextID = m.nextID + 1
    m.sessions[#m.sessions + 1] = session
    self:Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    return session
end

-- Ends the session in progress (h:LeaveCombat calls this); fires nothing.
function Harness:MeterEndSession()
    local session = self:MeterActive()
    if session then
        session.finish = self.time
    end
end

-- The sessions a DamageMeterSessionType covers.
local function SessionsOfType(h, sessionType)
    local list = h.meter.sessions
    if sessionType == SessionTypes.Overall then
        return list
    elseif sessionType == SessionTypes.Current then
        return { list[#list] }
    elseif sessionType == SessionTypes.Expired then
        return {}
    end
    error("C_DamageMeter: unknown DamageMeterSessionType " .. tostring(sessionType), 4)
end

-- A source's identity from its spec (see the header).
local function Identity(h, spec)
    local unit = type(spec.unit) == "string" and assert(h:Unit(spec.unit), "MeterAdd: no unit " .. spec.unit) or spec.unit
    local id = {
        name = spec.name, sourceGUID = spec.guid, sourceCreatureID = spec.creatureID, classFilename = spec.classFilename,
        specIconID = spec.specIconID, isLocalPlayer = spec.isLocalPlayer, classification = spec.classification or "",
        factionGroup = spec.factionGroup, sourceDisplayType = spec.sourceDisplayType or DisplayTypes.None,
    }
    if unit then
        id.name = id.name or unit.name
        id.classFilename = id.classFilename or unit.classFile
        if id.isLocalPlayer == nil then id.isLocalPlayer = unit == h.player end
        if unit ~= h.player then
            id.factionGroup = id.factionGroup or unit.faction
        end
        if unit.isPlayer or unit.playerControlled then
            id.sourceGUID = id.sourceGUID or h:GUID(unit)
        else
            id.sourceCreatureID = id.sourceCreatureID or unit.npcID or 0
        end
    end
    assert(id.name, "MeterAdd: a source needs a name or a unit")
    id.classFilename = id.classFilename or ""
    id.isLocalPlayer = id.isLocalPlayer == true
    if id.sourceGUID == nil and id.sourceCreatureID == nil then
        h.meterGUIDs[id.name] = h.meterGUIDs[id.name] or h:GUID({ isPlayer = true })
        id.sourceGUID = h.meterGUIDs[id.name]
    end
    id.key = id.sourceGUID or ("Creature-" .. id.sourceCreatureID .. "-" .. id.name)
    return id
end

local function Spell(spell)
    assert(type(spell.spellID) == "number", "MeterAdd: a spell needs a spellID")
    local total = spell.totalAmount or 0
    local d = spell.details or {}
    return {
        spellID = spell.spellID, totalAmount = total, creatureName = spell.creatureName or "", school = spell.school,
        name = spell.name,
        overkillAmount = spell.overkillAmount or 0, isAvoidable = spell.isAvoidable == true, isDeadly = spell.isDeadly == true,
        details = {
            unitName = d.unitName or "", unitClassFilename = d.unitClassFilename or "", classification = d.classification or "",
            isPet = d.isPet == true, isMob = d.isMob == true, amount = d.amount or total, specIconID = d.specIconID,
            unit = d.unit,
        },
    }
end

-- The recap events for a death, newest first. victim is the dying unit's table, if any.
local function RecapEvents(h, session, record, death, time, victim)
    local events = {}
    if death.events then
        for _, given in ipairs(death.events) do
            local event = {}
            for _, field in ipairs(RecapFields) do
                if given.event ~= "SWING_DAMAGE" or not RecapSpellFields[field] then
                    event[field] = given[field]
                end
            end
            event.timestamp = event.timestamp or session.startServer + (given.time or time)
            table.insert(events, 1, event)
        end
    else
        local spells = record.spells[Types.DamageTaken] or {}
        local health = 0
        for _, spell in ipairs(spells) do
            health = health + spell.totalAmount - spell.overkillAmount
        end
        for _, spell in ipairs(spells) do
            local d = spell.details
            local from = d.unitName ~= "" and d.unitName or spell.creatureName
            local key = (d.isMob and "mob:" or "player:") .. from
            if d.unit then
                h.meterGUIDs[key] = h:GUID(d.unit)
                from = h:FullName(d.unit) -- [G] a recap names a player as chat does
            end
            h.meterGUIDs[key] = h.meterGUIDs[key] or h:GUID({ isPlayer = not d.isMob })
            health = health - spell.totalAmount + spell.overkillAmount
            local swing = spell.spellID == AutoAttack
            table.insert(events, 1, {
                timestamp = session.startServer + time, event = swing and "SWING_DAMAGE" or "SPELL_DAMAGE",
                hideCaster = false, sourceGUID = h.meterGUIDs[key], sourceName = from,
                sourceFlags = (d.isPet and Flags.enemyPet) or (d.isMob and Flags.mob) or Flags.enemyPlayer, sourceRaidFlags = 0,
                destGUID = record.sourceGUID or (victim and h:GUID(victim)) or "", destName = record.name,
                destFlags = Flags.player, destRaidFlags = 0, spellId = not swing and spell.spellID or nil,
                spellName = not swing and (spell.name or h.spellNames[spell.spellID]) or nil,
                spellSchool = not swing and (spell.school or 1) or nil,
                avoidable = (not swing or nil) and spell.isAvoidable, deadly = (not swing or nil) and spell.isDeadly,
                amount = spell.totalAmount, overkill = spell.overkillAmount, school = spell.school or 1,
                critical = false, glancing = false, crushing = false, isOffHand = false, currentHP = math.max(health, 0),
            })
        end
    end
    return events
end

local function Sorted(set)
    local list = {}
    for t in pairs(set) do list[#list + 1] = t end
    table.sort(list)
    return list
end

-- Adds a source's amounts, spells and death to the session in progress and fires
-- DAMAGE_METER_COMBAT_SESSION_UPDATED for each changed type. fightLeft (seconds still to come,
-- h:MeterFight's duration) places a death without a time at the fight's end. Returns the
-- source's record and its death's recap ID, if any.
function Harness:MeterAdd(spec, fightLeft)
    local session = assert(self:MeterActive(), "MeterAdd: no damage meter session (enter combat first)")
    local id = Identity(self, spec)
    local record = session.sources[id.key]
    if not record then
        record = { amounts = {}, spells = {}, deaths = {} }
        session.sources[id.key] = record
        session.order[#session.order + 1] = id.key
    end
    for field, value in pairs(id) do
        record[field] = value
    end
    local touched, given = {}, {}
    for key, amount in pairs(spec.amounts or {}) do
        local t = MeterType(key)
        assert(not Base[t] and t ~= Types.Deaths, "MeterAdd: give DamageDone/HealingDone (Dps/Hps read them) and deaths as death")
        record.amounts[t] = (record.amounts[t] or 0) + amount
        given[t], touched[t] = true, true
    end
    for key, spells in pairs(spec.spells or {}) do
        local t = MeterType(key)
        record.spells[t] = record.spells[t] or {}
        for _, raw in ipairs(spells) do
            local spell = Spell(raw)
            table.insert(record.spells[t], spell)
            if not given[t] then
                record.amounts[t] = (record.amounts[t] or 0) + spell.totalAmount
            end
        end
        touched[t] = true
    end
    local recapID
    if spec.death then
        local m, death = self.meter, spec.death
        recapID = m.nextRecap
        m.nextRecap = m.nextRecap + 1
        local time = death.time or (Duration(self, session) + (fightLeft or 0))
        record.deaths[#record.deaths + 1] = { recapID = recapID, time = time }
        if record.isLocalPlayer then
            m.latestLocal = recapID
        end
        local unit = type(spec.unit) == "string" and self:Unit(spec.unit) or spec.unit
        m.recaps[recapID] = {
            maxHealth = death.maxHealth or (unit and unit.maxHealth) or 0,
            events = RecapEvents(self, session, record, death, time, unit),
        }
        touched[Types.Deaths] = true
    end
    for t, rate in pairs(Rate) do
        if touched[t] then touched[rate] = true end
    end
    for _, t in ipairs(Sorted(touched)) do
        self:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", t, 0)
        self:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", t, session.id)
    end
    return record, recapID
end

-- A source spec split in two: everything but its DamageTaken and death, and its identity with
-- only those.
local function SplitDamageTaken(source)
    local during, after = { amounts = {}, spells = {} }, { amounts = {}, spells = {}, death = source.death }
    for key, value in pairs(source) do
        if key ~= "amounts" and key ~= "spells" and key ~= "death" then
            during[key], after[key] = value, value
        end
    end
    for _, field in ipairs({ "amounts", "spells" }) do
        for key, value in pairs(source[field] or {}) do
            local side = MeterType(key) == Types.DamageTaken and after or during
            side[field][key] = value
        end
    end
    return during, after
end

-- Scripts a whole fight: enters combat (starting a session) unless already in combat, names the
-- session, adds every source (h:MeterAdd), lets duration seconds pass (h:Advance), then, unless
-- endCombat is false, ends combat: h:Die() when the local player's source died, adding that source
-- after PLAYER_DEAD (see the header), else h:LeaveCombat(). Returns { sessionID, recaps =
-- { [source name] = recapID } }.
function Harness:MeterFight(spec)
    if not self.inCombat then
        self:EnterCombat()
    end
    local session = assert(self:MeterActive(), "MeterFight: no damage meter session")
    session.name = spec.name or session.name
    local fight, dying = { sessionID = session.id, recaps = {} }, nil
    local function Add(source, fightLeft)
        local record, recapID = self:MeterAdd(source, fightLeft)
        if recapID then
            fight.recaps[record.name] = recapID
        end
    end
    local alive = not self.player.dead and not self.player.ghost
    for _, source in ipairs(spec.sources or {}) do
        local isLocal = source.isLocalPlayer or (source.isLocalPlayer == nil and (source.unit == "player" or source.unit == self.player))
        if source.death and isLocal and alive and spec.endCombat ~= false and not dying then
            -- What you dealt reaches the meter in the fight; the hits on you and your death after PLAYER_DEAD.
            local during
            during, dying = SplitDamageTaken(source)
            Add(during, spec.duration or 0)
        else
            Add(source, spec.duration or 0)
        end
    end
    self:Advance(spec.duration or 0)
    if dying then
        self:Die(function() Add(dying, 0) end)
    elseif spec.endCombat ~= false and self.inCombat then
        self:LeaveCombat()
    end
    return fight
end

-- The sources of a list of sessions, merged by key in order of first appearance, and their
-- total duration (nil for no sessions).
local function Merge(h, sessions)
    local records, order, duration = {}, {}, nil
    for _, session in ipairs(sessions) do
        duration = (duration or 0) + Duration(h, session)
        for _, key in ipairs(session.order) do
            local r = session.sources[key]
            local merged = records[key]
            if not merged then
                merged = { amounts = {}, spells = {}, deaths = {} }
                for field, value in pairs(r) do
                    if type(value) ~= "table" then merged[field] = value end
                end
                records[key] = merged
                order[#order + 1] = merged
            end
            for t, amount in pairs(r.amounts) do
                merged.amounts[t] = (merged.amounts[t] or 0) + amount
            end
            for t, spells in pairs(r.spells) do
                merged.spells[t] = merged.spells[t] or {}
                for _, spell in ipairs(spells) do table.insert(merged.spells[t], spell) end
            end
            for _, death in ipairs(r.deaths) do table.insert(merged.deaths, death) end
        end
    end
    return order, duration
end

local function PerSecond(amount, duration)
    return (duration or 0) > 0 and amount / duration or 0
end

-- Largest first; equal amounts keep their order.
local function SortByAmount(list)
    for i, entry in ipairs(list) do entry.__order = i end
    table.sort(list, function(a, b)
        if a.totalAmount ~= b.totalAmount then return a.totalAmount > b.totalAmount end
        return a.__order < b.__order
    end)
    for _, entry in ipairs(list) do entry.__order = nil end
end

local function Entry(record, total, duration)
    return {
        sourceGUID = record.sourceGUID, sourceCreatureID = record.sourceCreatureID, name = record.name,
        classFilename = record.classFilename, specIconID = record.specIconID, totalAmount = total,
        amountPerSecond = PerSecond(total, duration), isLocalPlayer = record.isLocalPlayer, deathRecapID = 0,
        deathTimeSeconds = 0, classification = record.classification, sourceDisplayType = record.sourceDisplayType,
        factionGroup = record.factionGroup,
    }
end

-- A DamageMeterCombatSession of these sessions for a type.
local function CombatSession(h, sessions, meterType, overall)
    local t = MeterType(meterType)
    local records, duration = Merge(h, sessions)
    local sources, max, sum = {}, 0, 0
    for _, record in ipairs(records) do
        if t == Types.Deaths then
            for _, death in ipairs(record.deaths) do
                local entry = Entry(record, 0, duration)
                entry.deathRecapID, entry.deathTimeSeconds = death.recapID, overall and -1 or death.time
                entry.specIconID = entry.specIconID or 0
                sources[#sources + 1] = entry
            end
        else
            local amount = record.amounts[Base[t] or t]
            if amount then
                sources[#sources + 1] = Entry(record, amount, duration)
                max, sum = math.max(max, amount), sum + amount
            end
        end
    end
    if t ~= Types.Deaths then
        SortByAmount(sources)
    end
    return { combatSources = sources, maxAmount = max, totalAmount = sum, durationSeconds = duration }
end

-- A DamageMeterCombatSessionSource: one source's spells for a type.
local function SessionSource(h, sessions, meterType, guid, creatureID)
    local t = Base[MeterType(meterType)] or MeterType(meterType)
    local records, duration = Merge(h, sessions)
    local result = { combatSpells = {}, maxAmount = 0, totalAmount = 0 }
    for _, record in ipairs(records) do
        local matches = (guid ~= nil and record.sourceGUID == guid)
            or (guid == nil and creatureID ~= nil and record.sourceCreatureID == creatureID)
        if matches and t ~= Types.Deaths then
            for _, spell in ipairs(record.spells[t] or {}) do
                local d = spell.details
                result.combatSpells[#result.combatSpells + 1] = {
                    spellID = spell.spellID, totalAmount = spell.totalAmount,
                    amountPerSecond = PerSecond(spell.totalAmount, duration), creatureName = spell.creatureName,
                    overkillAmount = spell.overkillAmount, isAvoidable = spell.isAvoidable, isDeadly = spell.isDeadly,
                    combatSpellDetails = {
                        unitName = d.unitName, unitClassFilename = d.unitClassFilename, classification = d.classification,
                        isPet = d.isPet, isMob = d.isMob, amount = d.amount, specIconID = d.specIconID,
                    },
                }
                result.maxAmount = math.max(result.maxAmount, spell.totalAmount)
            end
            result.totalAmount = record.amounts[t] or 0
        end
    end
    SortByAmount(result.combatSpells)
    return result
end

-- Per-field secrecy (see the header and Harness.SECRET_SHAPES in secrets.lua).
local function WrapFields(t, never)
    for field, value in pairs(t) do
        if not never[field] and type(value) ~= "table" then
            t[field] = Secret(value)
        end
    end
end

local function ShapeSession(session)
    WrapFields(session, {})
    for _, source in ipairs(session.combatSources) do
        WrapFields(source, NeverSecretSource)
    end
    return session
end

local function ShapeSessionSource(source)
    WrapFields(source, {})
    for _, spell in ipairs(source.combatSpells) do
        WrapFields(spell, {})
        WrapFields(spell.combatSpellDetails, NeverSecretDetails)
    end
    return source
end

Harness.SECRET_SHAPES["C_DamageMeter.GetCombatSessionFromType"] = ShapeSession
Harness.SECRET_SHAPES["C_DamageMeter.GetCombatSessionSourceFromType"] = ShapeSessionSource

local function CopyEvents(events)
    local out = {}
    for i, event in ipairs(events) do
        local copy = {}
        for field, value in pairs(event) do copy[field] = value end
        out[i] = copy
    end
    return out
end

-- The damage meter and death recap fakes, merged into the env (env.lua) before it wraps them.
function Harness:MeterFakes()
    local h = self
    local function Recap(id) return h.meter.recaps[id == nil and h.meter.latestLocal or id] end
    return {
        C_DamageMeter = {
            IsDamageMeterAvailable = function() return h.meter.available, h.meter.failureReason end,
            GetAvailableCombatSessions = function()
                local list = {}
                for i, session in ipairs(h.meter.sessions) do
                    list[i] = { sessionID = session.id, name = session.name, durationSeconds = Duration(h, session) }
                end
                return list
            end,
            GetCombatSessionFromType = function(sessionType, meterType)
                return CombatSession(h, SessionsOfType(h, sessionType), meterType, sessionType == SessionTypes.Overall)
            end,
            GetCombatSessionSourceFromType = function(sessionType, meterType, guid, creatureID)
                return SessionSource(h, SessionsOfType(h, sessionType), meterType, guid, creatureID)
            end,
        },
        C_DeathRecap = {
            GetRecapEvents = function(id)
                local recap = Recap(id)
                return recap and CopyEvents(recap.events) or {}
            end,
            HasRecapEvents = function(id)
                local recap = Recap(id)
                return recap ~= nil and #recap.events > 0
            end,
            GetRecapMaxHealth = function(id)
                local recap = Recap(id)
                return recap and recap.maxHealth or 0
            end,
        },
    }
end
