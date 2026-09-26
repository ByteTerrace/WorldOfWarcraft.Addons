-- The target fact (Facts.lua): what your target is, for features that react to it. A demand
-- fact: it runs only while a module that uses it runs (uses = { "target" }).
--
--   target.serial       bumps on every target change.
--   target.enemyPlayer  the target is an attackable player (re-checked when a duel or PvP flag
--                       changes attackability).
--   target.formidable   the target is attackable and elite, rare elite, a world boss, a boss mob
--                       or skull level (too far above you to show its level).
--   target.alive        the target is alive.
--   target.died         the enemy player target died while targeted (not a corpse you selected).
--   target.duelEnded    a duel with the target ended without you fleeing out of bounds. Duels end
--                       at 1 HP, not death, and DUEL_FINISHED doesn't say who won.
--
-- Health changes are the hot path in a fight: they only re-read whether the target lives (one
-- API call). Attackability and rank re-read on the events that change them, and on health
-- changes too while the target is a player who isn't an enemy yet (a duel about to start), in
-- case the client doesn't say so otherwise.

local FormidableClassifications = { elite = true, rareelite = true, worldboss = true }
local SkullLevel = -1 -- UnitLevel of a unit too far above you to show its level

local issecretvalue, UnitCanAttack, UnitClassification = issecretvalue, UnitCanAttack, UnitClassification
local UnitExists, UnitIsBossMob, UnitIsDeadOrGhost = UnitExists, UnitIsBossMob, UnitIsDeadOrGhost
local UnitIsFeignDeath, UnitIsPlayer, UnitLevel = UnitIsFeignDeath, UnitIsPlayer, UnitLevel

local function IsTrue(value)
    return not issecretvalue(value) and value == true
end

-- Whether the target is elite, rare elite, a world boss, a boss mob or skull level.
local function IsFormidable()
    local classification = UnitClassification("target")
    if not issecretvalue(classification) and FormidableClassifications[classification] then
        return true
    end
    if IsTrue(UnitIsBossMob("target")) then
        return true
    end
    local level = UnitLevel("target")
    return not issecretvalue(level) and level == SkullLevel
end

-- Whether the target is an attackable player, formidable, and alive.
local function Read()
    if not IsTrue(UnitExists("target")) then
        return false, false, false
    end
    local hostile = IsTrue(UnitCanAttack("player", "target"))
    return hostile and IsTrue(UnitIsPlayer("target")), hostile and IsFormidable(), not IsTrue(UnitIsDeadOrGhost("target"))
end

ByteTerrace.Facts.target = {
    toggle = false,
    demand = true,
    state = {
        { name = "serial", kind = "number", default = 0, persist = false },
        { name = "enemyPlayer", kind = "boolean", default = false, persist = false },
        { name = "formidable", kind = "boolean", default = false, persist = false },
        { name = "alive", kind = "boolean", default = false, persist = false },
        { name = "died", kind = "boolean", default = false, persist = false },
        { name = "duelEnded", kind = "boolean", default = false, persist = false },
    },
    OnEnable = function(module)
        local state = module.Addon.State
        local serial, enemy, formidable = module:Id("serial"), module:Id("enemyPlayer"), module:Id("formidable")
        local alive, died, duelEnded = module:Id("alive"), module:Id("died"), module:Id("duelEnded")
        local isPlayer = false -- the target is a player, as of the last target change

        -- The same target lives or dies; wasEnemy says it was an enemy player while alive (one may
        -- stop being attackable as it dies).
        local function Live(isAlive, wasEnemy)
            if isAlive and not state.Values[alive] then
                state:Set(died, false) -- resurrected: a death from here on counts again
            elseif not isAlive and state.Values[alive] and wasEnemy and not IsTrue(UnitIsFeignDeath("target")) then
                state:Set(died, true)
            end
            state:Set(alive, isAlive)
        end

        -- Same target, new facts: attackability, rank, death, resurrection.
        local function Refresh()
            local isEnemy, isFormidable, isAlive = Read()
            Live(isAlive, isEnemy or state.Values[enemy])
            state:Set(enemy, isEnemy)
            state:Set(formidable, isFormidable)
        end

        -- The client sends the target's health events only while you have one.
        module:On("UNIT_HEALTH", function()
            if isPlayer and not state.Values[enemy] then
                Refresh()
            else
                Live(not IsTrue(UnitIsDeadOrGhost("target")), state.Values[enemy])
            end
        end, "target")

        -- A new target: its facts start fresh, so a corpse you select never "died while targeted".
        module:On("PLAYER_TARGET_CHANGED", function()
            isPlayer = IsTrue(UnitIsPlayer("target"))
            local isEnemy, isFormidable, isAlive = Read()
            state:Set(serial, state.Values[serial] + 1)
            state:Set(died, false)
            state:Set(duelEnded, false)
            state:Set(enemy, isEnemy)
            state:Set(formidable, isFormidable)
            state:Set(alive, isAlive)
        end)

        -- Duels end at 1 HP. Fleeing out of bounds forfeits, so that doesn't count.
        local outOfBounds = false
        module:On("DUEL_OUTOFBOUNDS", function() outOfBounds = true end)
        module:On("DUEL_INBOUNDS", function() outOfBounds = false end)
        module:On("DUEL_FINISHED", function()
            if state.Values[enemy] and state.Values[alive] and not outOfBounds then
                state:Set(duelEnded, true)
            end
            outOfBounds = false
        end)
        module:On("UNIT_FACTION", Refresh, "target")
        module:On("UNIT_FLAGS", Refresh, "target")
        module:On("UNIT_CLASSIFICATION_CHANGED", Refresh, "target")
        module:On("UNIT_LEVEL", Refresh, "target")
        isPlayer = IsTrue(UnitIsPlayer("target"))
        Refresh()
    end,
}
