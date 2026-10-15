local addonName, ns = ...

-- Calibration probes about Blizzard's damage meter (C_DamageMeter) and death recaps
-- (C_DeathRecap): what a session holds idle, in combat and right after a fight, the local
-- player's damage taken, the enemies' sources, and a death. Recaps record common fields and
-- the killing blow's common shape; separate swing/spell probes require that event kind before
-- recording its spell fields. Probes.lua's header is the contract; ProbeNeeds.lua defines needs.

-- Spell and environmental payloads depend on the event kind; mitigation is optional in
-- Blizzard_DeathRecap's damage tooltip. Neither belongs in the common event shape.
local ConditionalRecapFields = {
    spellId = true, spellName = true, spellSchool = true, avoidable = true, deadly = true,
    environmentalType = true, absorbed = true, resisted = true, blocked = true,
}
local RecapSpellFields = { "spellId", "spellName", "spellSchool", "avoidable", "deadly" }

local Probes = ns.Probes
local Marker, Value, Shape, Text = Probes.Marker, Probes.Value, Probes.Shape, Probes.Text
local Fields, FieldShapes, Same = Probes.Fields, Probes.FieldShapes, Probes.Same
local First, Joined = Probes.First, Probes.Joined

-- Which damage meter session a session's duration matches in the available list (oldest
-- first): "latest", "previous", "neither", "none" (no duration) or "secret".
local function WhichSession(durationSeconds, sessions)
    if issecretvalue(durationSeconds) then
        return "secret"
    elseif durationSeconds == nil then
        return "none"
    end
    local latest, previous = sessions[#sessions], sessions[#sessions - 1]
    if latest and Same(latest.durationSeconds, durationSeconds) == true then
        return "latest"
    elseif previous and Same(previous.durationSeconds, durationSeconds) == true then
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
        hasSources = not issecretvalue(sources) and type(sources) == "table" and sources[1] ~= nil,
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
    local plainDetails = not issecretvalue(details) and type(details) == "table" and details or {}
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
    if issecretvalue(sources) or type(sources) ~= "table" then
        return nil
    end
    for _, source in ipairs(sources) do
        local isLocalPlayer = source.isLocalPlayer
        if not issecretvalue(isLocalPlayer) and isLocalPlayer == true then
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
        if not issecretvalue(eventKind) and eventKind == kind then
            for _, field in ipairs(RecapSpellFields) do
                local shape = Shape(event[field])
                assert(result[field] == nil or #Probes.Diff(result[field], shape) == 0,
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
            local oldestFirst = Same(first.sessionID, last.sessionID) == false and first.sessionID < last.sessionID
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
                fields = Fields(source), totalAmount = Shape(source.totalAmount), hasSpells = spell ~= nil,
                combatSpells = Shape(source.combatSpells), spell = spell and SpellShape(spell) or nil,
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
                hasRecapID = not issecretvalue(recapID) and type(recapID) == "number" and recapID ~= 0,
                deathTimeSeconds = Shape(death.deathTimeSeconds),
            }
        end,
    },
    {
        name = "deathRecap.events",
        version = 2, -- version 1 recorded the union of every event's fields, which depends on how you died
        needs = { "diedToMob" },
        run = function()
            local death = LocalDeath()
            local recapID = death and death.deathRecapID
            if issecretvalue(recapID) or type(recapID) ~= "number" or recapID == 0 then
                return { recapID = Shape(recapID) }
            end
            local events = C_DeathRecap.GetRecapEvents(recapID)
            local killingBlow = First(events)
            local fields = killingBlow and CommonRecapShape(killingBlow) or {}
            for _, event in ipairs(killingBlow and events or {}) do
                for key in pairs(fields) do
                    local value = event[key]
                    if not issecretvalue(value) and value == nil then
                        fields[key] = nil
                    end
                end
            end
            return {
                recapID = "number", hasRecapEvents = Value(C_DeathRecap.HasRecapEvents(recapID)),
                events = Shape(events), commonFields = Joined(fields),
                killingBlow = killingBlow and CommonRecapShape(killingBlow) or nil,
                sourceName = killingBlow and Text(killingBlow.sourceName) or nil,
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
            return { types = next(Probes.AfterDeath.types) and Joined(Probes.AfterDeath.types) or "none" }
        end,
    },
    {
        -- Blizzard's death popup asks for the recap with no ID (GameDialogDefs.lua): your latest.
        name = "deathRecap.latest",
        needs = { "diedToMob" },
        run = function()
            local death = LocalDeath()
            local recapID = death and death.deathRecapID
            local latest = C_DeathRecap.GetRecapEvents()
            local blow = First(latest)
            local result = { hasLatest = Value(C_DeathRecap.HasRecapEvents()), latest = Shape(latest) }
            if blow and not issecretvalue(recapID) and type(recapID) == "number" and recapID ~= 0 then
                local byID = First(C_DeathRecap.GetRecapEvents(recapID))
                -- false when a plain field differs, else "secret" when one couldn't be compared.
                local same = byID ~= nil
                for _, field in ipairs(byID and { "timestamp", "sourceName", "amount" } or {}) do
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
})
