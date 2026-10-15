local addonName, ns = ...

-- Calibration probes about units: identity and health (secret or plain, idle and in combat),
-- health percent, classification, primary power, combo points, nameplate frames, and the UNIT_COMBAT payloads
-- and UNIT_AURA tokens DevTools.lua collects. Probes.lua's header is the contract; ProbeNeeds.lua defines the needs.

-- UnitClassification's documented answers (warcraft.wiki.gg API_UnitClassification).
local Classifications = {
    worldboss = true, rareelite = true, elite = true, rare = true, normal = true, trivial = true, minus = true,
}

local Probes = ns.Probes
local Value, Shape, Joined, JoinSets = Probes.Value, Probes.Shape, Probes.Joined, Probes.JoinSets
local NamePlateToken = Probes.NamePlateToken
local UnitCombat, Kills = Probes.UnitCombat, Probes.Kills

-- A unit's identity: UnitName, UnitClass and UnitGUID, as shapes. withRealm adds UnitName's realm,
-- for units whose realm is always the player's (an NPC's is nil).
local function Identity(unit, withRealm)
    local name, realm = UnitName(unit) -- secret: recorded by Shape as a marker
    local className, classFile, classID = UnitClass(unit) -- secret: recorded by Shape as a marker
    local guid = UnitGUID(unit) -- secret: recorded by Shape as a marker
    return {
        name = Shape(name), realm = withRealm and Shape(realm) or nil, className = Shape(className),
        classFile = Shape(classFile), classID = Shape(classID), guid = Shape(guid),
    }
end

local function Health(unit)
    local health = UnitHealth(unit) -- secret: recorded by Shape as a marker
    local healthMax = UnitHealthMax(unit) -- secret: recorded by Shape as a marker
    return { health = Shape(health), healthMax = Shape(healthMax) }
end

-- UnitHealthPercent and UnitHealthMissing, with and without predicted healing, as shapes.
local function HealthSignals(unit)
    local percent = UnitHealthPercent(unit) -- secret: recorded by Shape as a marker
    local percentUnpredicted = UnitHealthPercent(unit, false) -- secret: recorded by Shape as a marker
    local missing = UnitHealthMissing(unit) -- secret: recorded by Shape as a marker
    local missingUnpredicted = UnitHealthMissing(unit, false) -- secret: recorded by Shape as a marker
    return {
        percent = Shape(percent), percentUnpredicted = Shape(percentUnpredicted), missing = Shape(missing),
        missingUnpredicted = Shape(missingUnpredicted),
    }
end

-- A unit's UnitClassification and UnitLevel, as shapes; isSkull is a plain level of -1.
local function Classification(unit)
    local classification, level = UnitClassification(unit), UnitLevel(unit)
    local plainClassification = not issecretvalue(classification) and type(classification) == "string"
    local plainLevel = not issecretvalue(level) and type(level) == "number"
    return {
        classification = Shape(classification), level = Shape(level), isSkull = plainLevel and level == -1,
        isDocumented = plainClassification and Classifications[classification] == true,
    }
end

-- The player's combo points, as shapes: UnitPower and UnitPowerMax of the power type, and
-- GetComboPoints on the target.
local function ComboPoints()
    local comboPoints = Enum.PowerType.ComboPoints
    local current = UnitPower("player", comboPoints) -- secret: recorded by Shape as a marker
    local max = UnitPowerMax("player", comboPoints) -- secret: recorded by Shape as a marker
    local onTarget = GetComboPoints("player", "target") -- secret: recorded by Shape as a marker
    return { comboPoints = Shape(current), comboPointsMax = Shape(max), onTarget = Shape(onTarget) }
end

-- A unit's primary power, as shapes: UnitPowerType's number and token, UnitPower and UnitPowerMax
-- of that type (no PowerType argument). Any class answers: mana, rage and energy are all primary.
local function PrimaryPower(unit)
    local powerType, token = UnitPowerType(unit)
    local current = UnitPower(unit) -- secret: recorded by Shape as a marker
    local max = UnitPowerMax(unit) -- secret: recorded by Shape as a marker
    return { powerType = Shape(powerType), token = Shape(token), current = Shape(current), max = Shape(max) }
end

-- The nameplate frame of a non-player unit (enemy or friendly, NamePlateToken), as shapes.
local function NamePlateShape(enemy)
    local plate = C_NamePlate.GetNamePlateForUnit(NamePlateToken(enemy))
    if plate == nil then
        return { plate = "nil" }
    end
    return {
        plate = Shape(plate),
        forbidden = Value(plate:IsForbidden()), -- secret: recorded by Value as a marker
        objectType = Value(plate:GetObjectType()), -- secret: recorded by Value as a marker
        hasUnitFrame = rawget(plate, "UnitFrame") ~= nil, -- Blizzard_NamePlateBase assigns it as a plain field
    }
end

Probes.Define({
    {
        -- What addon code may do with a secret (UnitHealth("player") is always one, probed): each
        -- operation is tried in pcall, so a refusal is recorded instead of raised. The *Result
        -- fields give what an allowed operation returned (a secret's marker, or its type), or
        -- "refused".
        name = "secrets.operations",
        needs = {},
        run = function()
            local health = UnitHealth("player") -- secret: only handed to the operations under test
            local function Try(fn)
                return (pcall(fn))
            end
            local function Result(fn)
                local ok, result = pcall(fn)
                return ok and Shape(result) or "refused"
            end
            return {
                isSecret = issecretvalue(health),
                tostring = Try(function() return tostring(health) end), -- secret: the operation under test
                concat = Try(function() return "hp " .. health end), -- secret: the operation under test
                concatResult = Result(function() return "hp " .. health end), -- secret: the operation under test
                format = Try(function() return ("%d"):format(health) end), -- secret: the operation under test
                formatString = Try(function() return ("%s"):format(health) end), -- secret: the operation under test
                formatResult = Result(function() return ("%s"):format(health) end), -- secret: the operation under test
                truthTest = Try(function() return health and true end), -- secret: the operation under test
                tableValue = Try(function() return { value = health } end), -- secret: the operation under test
                arithmetic = Try(function() return health + 1 end), -- secret: the operation under test
            }
        end,
    },
    {
        -- Two uses of a secret the client refuses and Lua 5.1 can't intercept: comparing a value with
        -- itself (raw equality holds before __eq is consulted) and using it as a table key (no
        -- metamethod runs). The static SECRET rule covers both in addon code.
        name = "secrets.rawOperations",
        needs = {},
        harness = "Lua 5.1 compares a value with itself and keys a table without consulting a metamethod",
        run = function()
            local health = UnitHealth("player") -- secret: only handed to the operations under test
            local function Try(fn)
                return (pcall(fn))
            end
            return {
                compare = Try(function() return health == health end), -- secret: the operation under test
                tableKey = Try(function() return ({ [health] = true }) end), -- secret: the operation under test
            }
        end,
    },
    {
        name = "unitIdentity.npcTarget",
        needs = { "idle", "npcTarget" },
        run = function() return Identity("target", true) end,
    },
    {
        name = "unitIdentity.npcTargetInCombat",
        needs = { "combat", "npcTarget" },
        run = function() return Identity("target", true) end,
    },
    {
        -- Whether a dungeon's Map restriction alone hides an NPC's identity, as an encounter's does.
        name = "unitIdentity.npcTargetRestrictedMap",
        needs = { "restrictedMap", "npcTarget" },
        run = function() return Identity("target", true) end,
    },
    {
        name = "unitIdentity.enemyPlayer",
        needs = { "idle", "enemyPlayer" },
        run = function() return Identity("target", false) end,
    },
    {
        name = "unitIdentity.partyMember",
        needs = { "idle", "party" },
        run = function() return Identity("party1", false) end,
    },
    {
        name = "unitHealth.npcTarget",
        needs = { "idle", "npcTarget" },
        run = function() return Health("target") end,
    },
    {
        name = "unitHealth.npcTargetInCombat",
        needs = { "combat", "npcTarget" },
        run = function() return Health("target") end,
    },
    {
        name = "unitHealth.player",
        needs = { "idle" },
        run = function() return Health("player") end,
    },
    {
        name = "unitHealth.playerInCombat",
        needs = { "combat" },
        run = function() return Health("player") end,
    },
    {
        name = "unitHealth.enemyPlayer",
        needs = { "idle", "enemyPlayer" },
        run = function() return Health("target") end,
    },
    {
        name = "unitHealthPercent.player",
        needs = { "idle" },
        run = function() return HealthSignals("player") end,
    },
    {
        name = "unitHealthPercent.playerInCombat",
        needs = { "combat" },
        run = function() return HealthSignals("player") end,
    },
    {
        name = "unitClassification.npcTarget",
        needs = { "idle", "npcTarget" },
        run = function() return Classification("target") end,
    },
    {
        name = "unitClassification.npcTargetInCombat",
        needs = { "combat", "npcTarget" },
        run = function() return Classification("target") end,
    },
    {
        name = "power.player",
        needs = { "idle" },
        run = function() return PrimaryPower("player") end,
    },
    {
        name = "power.playerInCombat",
        needs = { "combat" },
        run = function() return PrimaryPower("player") end,
    },
    {
        name = "power.npcTarget",
        needs = { "idle", "npcTarget" },
        run = function() return PrimaryPower("target") end,
    },
    {
        name = "power.npcTargetInCombat",
        needs = { "combat", "npcTarget" },
        run = function() return PrimaryPower("target") end,
    },
    {
        -- The docs keep UnitPowerMax plain for player-controlled units, as they did UnitHealthMax,
        -- which the client made secret for an enemy player (unitHealth.enemyPlayer).
        name = "power.enemyPlayer",
        needs = { "idle", "enemyPlayer" },
        run = function() return PrimaryPower("target") end,
    },
    {
        name = "power.comboPoints",
        needs = { "comboPoints", "idle", "npcTarget" },
        run = ComboPoints,
    },
    {
        name = "power.comboPointsInCombat",
        needs = { "comboPoints", "combat", "npcTarget" },
        run = ComboPoints,
    },
    {
        name = "namePlate.friendlyNPC",
        needs = { "friendlyNamePlate" },
        run = function() return NamePlateShape(false) end,
    },
    {
        name = "namePlate.enemyNPC",
        needs = { "enemyNamePlate" },
        run = function() return NamePlateShape(true) end,
    },
    {
        -- An enemy hunter's Feign Death: whether the client says they're feigning, or only that
        -- they're dead (FactsTarget.lua takes a death that isn't a feign for a kill).
        name = "feign.enemyHunter",
        needs = { "enemyHunterFeigning" },
        run = function()
            return { feigning = Value(UnitIsFeignDeath("target")), dead = Value(UnitIsDeadOrGhost("target")) }
        end,
    },
    {
        name = "unitCombat.seen",
        needs = { "unitCombat" },
        accumulates = true,
        run = function()
            local units = UnitCombat.units
            return {
                player = JoinSets(units.player), target = JoinSets(units.target), actions = Joined(UnitCombat.actions),
                flagTexts = Joined(UnitCombat.flagTexts),
                amountInCombat = UnitCombat.amountInCombat,
            }
        end,
    },
    {
        -- UNIT_AURA's unit token per restriction text it came under ("secret", or the token): the
        -- event is SecretWhenAurasRestricted, and the harness never makes a unit token secret, while
        -- ByteTerrace_Core's Events.lua guards it. DevTools.lua listens for the player and the target.
        name = "units.secretTokenInAuraEvent",
        needs = { "auraRestricted" },
        accumulates = true,
        run = function() return JoinSets(Probes.AuraTokens) end,
    },
    {
        -- PARTY_KILL is how killing-blow addons read kills since the combat log closed: whose blow
        -- (you, your pet, someone else) and the victim's kind. UNIT_DIED and PLAYER_TARGET_DIED
        -- are new in the same client.
        name = "kills.seen",
        needs = { "killedMob" },
        accumulates = true,
        run = function()
            return {
                partyKill = Kills.partyKill and JoinSets(Kills.partyKill), unitDied = Kills.unitDied and JoinSets(Kills.unitDied),
                targetDied = Kills.targetDied,
            }
        end,
    },
})
