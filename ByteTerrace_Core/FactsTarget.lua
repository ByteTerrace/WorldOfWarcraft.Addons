-- The target fact (Facts.lua): what your target is, for features that react to it. A demand fact: it runs only while a
-- module that uses it runs (uses = { "target" }).
--
--   target.serial       bumps on every target change.
--   target.enemyPlayer  the target is an attackable player (re-checked when a duel or PvP flag
--                       changes attackability).
--   target.formidable   the target is attackable and elite, rare elite, a world boss, a boss mob,
--                       or skull level (too far above you to show its level).
--   target.alive        the target is alive.
--   target.died         the enemy player target died while targeted (not a corpse you selected).
--   target.duelEnded    a duel with the target ended without you fleeing out of bounds. Duels end
--                       at 1 HP, not death, and DUEL_FINISHED says neither who won nor with whom:
--                       it counts for a target that became attackable while you targeted it (the
--                       duel starting), never for one attackable when you targeted it or reloaded.
--
-- Health changes are the hot path in a fight: they re-read only whether the target lives (one API call). Attackability
-- and rank re-read on the events that change them, and attackability on health changes too while the target is a player
-- who isn't an enemy yet (a duel about to start), in case the client doesn't say so otherwise. Whether the target is a
-- player is read once per target, and its rank once per target too, only when it's attackable.

local FormidableClassifications = { elite = true, rareelite = true, worldboss = true }
-- UnitLevel's answer for a unit too far above you to show its level.
local SkullLevel = -1

local issecretvalue = issecretvalue
local UnitCanAttack = UnitCanAttack
local UnitClassification = UnitClassification
local UnitExists = UnitExists
local UnitIsBossMob = UnitIsBossMob
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsPlayer = UnitIsPlayer
local UnitLevel = UnitLevel

local function IsTrue(value)
    return (not issecretvalue(value) and (value == true))
end

-- Whether the target is elite, rare elite, a world boss, a boss mob, or skull level.
local function IsFormidable()
    local classification = UnitClassification("target")

    if not issecretvalue(classification) and FormidableClassifications[classification] then
        return true
    end

    if IsTrue(UnitIsBossMob("target")) then
        return true
    end

    local level = UnitLevel("target")

    return (not issecretvalue(level) and (level == SkullLevel))
end

ByteTerrace.Facts.target = {
    demand = true,
    OnEnable = function(module)
        local state = module.Addon.State
        local serial = module:Id("serial")
        local enemy = module:Id("enemyPlayer")
        local formidable = module:Id("formidable")
        local alive = module:Id("alive")
        local died = module:Id("died")
        local duelEnded = module:Id("duelEnded")
        -- Whether the target is a player, as of the last target change.
        local isPlayer = false
        -- Whether the target's rank is formidable, or nil until it's read for this target.
        local rank
        -- Whether the target became attackable while targeted, which makes it your duel partner.
        local dueling = false

        -- Whether the target is an attackable player, formidable, and alive.
        local function Read()
            if not IsTrue(UnitExists("target")) then
                return false, false, false
            end

            local hostile = IsTrue(UnitCanAttack("player", "target"))

            if hostile and (rank == nil) then
                rank = IsFormidable()
            end

            return (hostile and isPlayer), (hostile and rank), not IsTrue(UnitIsDeadOrGhost("target"))
        end

        -- The same target lives or dies. wasEnemy says it was an enemy player while alive, since one may stop being
        -- attackable as it dies.
        local function Live(isAlive, wasEnemy)
            if isAlive and not state.Values[alive] then
                -- The target was resurrected, so a death from here on counts again.
                state:Set(died, false)
            elseif not isAlive and state.Values[alive] and wasEnemy and not IsTrue(UnitIsFeignDeath("target")) then
                state:Set(died, true)
            end

            state:Set(alive, isAlive)
        end

        -- Same target, new facts: attackability, rank, death, and resurrection.
        local function Refresh()
            local isEnemy, isFormidable, isAlive = Read()

            Live(isAlive, isEnemy or state.Values[enemy])

            if isEnemy and isAlive and not state.Values[enemy] then
                dueling = true
            end

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
            isPlayer, rank, dueling = IsTrue(UnitIsPlayer("target")), nil, false
            local isEnemy, isFormidable, isAlive = Read()

            state:Set(serial, state.Values[serial] + 1)
            state:Set(died, false)
            state:Set(duelEnded, false)
            state:Set(enemy, isEnemy)
            state:Set(formidable, isFormidable)
            state:Set(alive, isAlive)
        end)

        -- Duels end at 1 HP. Fleeing out of bounds forfeits, so that doesn't count. DUEL_FINISHED names no one (it also
        -- ends a declined request), so it counts only for your duel partner.
        local outOfBounds = false

        module:On("DUEL_OUTOFBOUNDS", function() outOfBounds = true end)
        module:On("DUEL_INBOUNDS", function() outOfBounds = false end)

        module:On("DUEL_FINISHED", function()
            if dueling and state.Values[enemy] and state.Values[alive] and not outOfBounds then
                state:Set(duelEnded, true)
            end

            outOfBounds = false
        end)

        module:On("UNIT_FACTION", Refresh, "target")
        module:On("UNIT_FLAGS", Refresh, "target")

        local function RankChanged()
            rank = nil
            Refresh()
        end

        module:On("UNIT_CLASSIFICATION_CHANGED", RankChanged, "target")
        module:On("UNIT_LEVEL", RankChanged, "target")
        isPlayer = IsTrue(UnitIsPlayer("target"))
        Refresh()
        -- An attackable target at a /reload may be anyone, so it isn't taken for a duel partner.
        dueling = false
    end,
    state = {
        { default = 0, kind = "number", name = "serial", persist = false },
        { default = false, kind = "boolean", name = "enemyPlayer", persist = false },
        { default = false, kind = "boolean", name = "formidable", persist = false },
        { default = false, kind = "boolean", name = "alive", persist = false },
        { default = false, kind = "boolean", name = "died", persist = false },
        { default = false, kind = "boolean", name = "duelEnded", persist = false },
    },
    toggle = false,
}
