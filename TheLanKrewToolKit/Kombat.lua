local addonName, ns = ...

-- Kombat: a Mortal Kombat announcer for your fights, from player-supplied sounds (Sounds.lua).
--
-- Sounds, each with a Kombat.* setting (the five combo point sounds share Kombat.comboPoints):
--   chooseYourDestiny  a living enemy player becomes your target, or your target becomes one (a
--                      duel starts). At most every 10 seconds.
--   testYourMight      a living, attackable elite, rare elite, world boss, boss or skull-level enemy
--                      (a player 10 or more levels above you, too) becomes your target; it plays
--                      instead of destiny. At most every 10 seconds.
--   finishHim          your enemy player target is in finishing range, once per target: Execute is
--                      usable (warriors: below 20% health), or you have 5 combo points on it.
--   comboPoint1-5      each combo point you add to your target. At 5 on an enemy player not yet
--                      announced, finish him plays instead (ComboPoint5 if it has no file).
--   flawlessVictory    your enemy player target dies (or a duel with it ends) in a fight in which
--                      you weren't hit.
--   fatality           it dies in your fight after finish him was announced on it.
--   superbVictory      any other enemy player kill in your fight.
--   deathTaunt         you die.
-- A kill plays one victory sound: flawless, else fatality, else superb, the first that's on. A duel
-- only plays flawless: a duel you were hit in may be one you lost.
--
-- Modules, each running only while a sound needs it (their active rules come from
-- SoundBank.WhileOn). Adapters (event handlers) are the only code that reads the WoW API; the
-- sounds are rules over the rows they publish:
--   Kombat    the settings, and class facts: Kombat.execute (warriors), Kombat.combo (rogues and
--             druids) and Kombat.finisher (either).
--   Target    facts about your target, for any feature that needs them. A feature that reads
--             these rows adds its sounds to Target's active rule.
--     Target.serial       bumps on every target change.
--     Target.enemyPlayer  the target is an attackable player (re-checked when a duel or PvP flag
--                         changes attackability).
--     Target.mighty       the target is attackable and elite, rare elite, a world boss, a boss mob or
--                         skull level.
--     Target.alive        the target is alive.
--     Target.died         the enemy player target died while targeted (not a corpse you selected).
--     Target.duelEnded    a duel with the target ended without you fleeing out of bounds. Duels end
--                         at 1 HP, not death, and DUEL_FINISHED doesn't say who won; but you can't
--                         lose a duel you took no damage in, so Victory only counts a flawless one.
--   Finish    Finish.comboPoints (yours on the target), Finish.ready (in finishing range) and
--             Finish.announced (the Target.serial finishing range was last reached on).
--   Victory   Victory.flawless: you're in combat and haven't been hit. Addons can never read your
--             health (UnitHealth is always secret, probed in game), so the signal is UNIT_COMBAT on
--             you with action "WOUND", the event Blizzard's player frame shows hits from: heals and
--             regeneration don't count, nor a hit fully absorbed, blocked or resisted (amount 0).
--             A hit in the second before combat starts (an ambush) counts for the fight.
--             Victory.flawlessWins: flawless victories this session; Krew shares them. The sound
--             plays at the kill; the victory counts when the fight ends, once Blizzard's damage
--             meter confirms you took no damage (or can't say). Its numbers can stay secret a
--             moment after combat ends, so the check waits for them, at most ConfirmTries times.
--   DeathTaunt  plays deathTaunt on PLAYER_DEAD.

local ExecuteSpellID = 5308
local FullComboPoints = 5 -- Forever's rogues and druids hold at most 5 (ComboFrame shows 5 unless the max is 6 or 9)
local TargetCooldown = 10
local MightyClassifications = { elite = true, rareelite = true, worldboss = true }
local SkullLevel = -1 -- UnitLevel of a unit too far above you to show its level
local OpeningHitWindow = 1 -- seconds: a hit this soon before combat starts opened the fight
local ConfirmTries = 10 -- damage meter reads at the end of a fight, while its numbers are secret
local ConfirmInterval = 0.5 -- seconds between them

local C_DamageMeter, C_Spell, C_Timer, Enum, GetComboPoints, GetTime = C_DamageMeter, C_Spell, C_Timer, Enum, GetComboPoints, GetTime
local issecretvalue, UnitCanAttack, UnitClass, UnitClassification = issecretvalue, UnitCanAttack, UnitClass, UnitClassification
local UnitExists, UnitIsBossMob, UnitIsDeadOrGhost, UnitIsFeignDeath = UnitExists, UnitIsBossMob, UnitIsDeadOrGhost, UnitIsFeignDeath
local UnitIsPlayer, UnitLevel = UnitIsPlayer, UnitLevel

local Addon = ns.Addon
local SoundBank = ns.SoundBank
local Define, Row, IsOn, Play, WhileOn = SoundBank.Define, SoundBank.Row, SoundBank.IsOn, SoundBank.Play, SoundBank.WhileOn

local function IsTrue(value)
    return not issecretvalue(value) and value == true
end

-- Whether the attackable target is elite, rare elite, a world boss, a boss mob or skull level.
local function IsMighty()
    local classification = UnitClassification("target")
    if not issecretvalue(classification) and MightyClassifications[classification] then
        return true
    end
    if IsTrue(UnitIsBossMob("target")) then
        return true
    end
    local level = UnitLevel("target")
    return not issecretvalue(level) and level == SkullLevel
end

-- The damage you took in the fight that just ended, from Blizzard's damage meter, and whether
-- that answer is final: nil, true when the meter can't say (it's off); nil, false while its
-- numbers are still secret.
local function DamageTakenLastFight()
    if not C_DamageMeter.IsDamageMeterAvailable() then
        return nil, true
    end
    local types = Enum.DamageMeterSessionType
    local session = C_DamageMeter.GetCombatSessionFromType(types.Current, Enum.DamageMeterType.DamageTaken)
    if issecretvalue(session) or type(session) ~= "table" then
        return nil, false
    end
    local sources = session.combatSources
    if issecretvalue(sources) or type(sources) ~= "table" then
        return nil, false
    end
    for _, source in ipairs(sources) do
        if IsTrue(source.isLocalPlayer) then
            local total = source.totalAmount
            if issecretvalue(total) then
                return nil, false
            end
            return total, true
        end
    end
    return 0, true
end

-- Whether a UNIT_COMBAT payload on you is a hit that got through: a WOUND, unless its amount is a
-- plain 0 (fully absorbed, blocked or resisted).
local function IsHit(action, amount)
    if issecretvalue(action) or action ~= "WOUND" then
        return false
    end
    return issecretvalue(amount) or amount ~= 0
end

Define("chooseYourDestiny", { file = "ChooseYourDestiny", word = "destiny", label = "Choose your destiny",
    row = "Kombat.chooseYourDestiny", cooldown = TargetCooldown })
Define("testYourMight", { file = "TestYourMight", word = "might", label = "Test your might",
    row = "Kombat.testYourMight", cooldown = TargetCooldown })
Define("finishHim", { file = "FinishHim", word = "finish", label = "Finish him", row = "Kombat.finishHim",
    needs = "Kombat.finisher" })
for points = 1, FullComboPoints do
    Define("comboPoint" .. points, { file = "ComboPoint" .. points, word = "combo" .. points,
        label = points .. " combo point" .. (points > 1 and "s" or ""), row = "Kombat.comboPoints", needs = "Kombat.combo" })
end
Define("flawlessVictory", { file = "FlawlessVictory", word = "flawless", label = "Flawless victory", row = "Kombat.flawlessVictory" })
Define("fatality", { file = "Fatality", word = "fatality", label = "Fatality", row = "Kombat.fatality", needs = "Kombat.finisher" })
Define("superbVictory", { file = "SuperbVictory", word = "superb", label = "Superb victory", row = "Kombat.superbVictory" })
Define("deathTaunt", { file = "DeathTaunt", word = "taunt", label = "Death taunt", row = "Kombat.deathTaunt" })

local ComboSounds = {}
for points = 1, FullComboPoints do
    ComboSounds[points] = "comboPoint" .. points
end

Addon:Module("Kombat", {
    label = "Mortal Kombat",
    page = "Sounds",
    toggle = false,
    state = {
        Row("chooseYourDestiny", "Choose your destiny",
            "When a living enemy player becomes your target, or your target becomes one (a duel starts). At most every 10 seconds.",
            { "chooseYourDestiny" }),
        Row("testYourMight", "Test your might",
            "When a living elite, rare elite, boss or skull-level enemy becomes your target (players far above your level too). Plays instead of destiny.",
            { "testYourMight" }),
        Row("finishHim", "Finish him",
            "Warriors, rogues and druids: when your enemy player target is in finishing range, once per target. Warriors: Execute is usable (below 20% health; not in Defensive Stance). Rogues and druids: 5 combo points.",
            { "finishHim" }),
        Row("comboPoints", "Combo points",
            "Rogues and druids: a callout for each combo point you add (finish him takes the fifth on an enemy player).",
            ComboSounds),
        Row("flawlessVictory", "Flawless victory",
            "When your enemy player target dies, or yields a duel, during a fight in which you haven't been hit.",
            { "flawlessVictory" }),
        Row("fatality", "Fatality", "When your enemy player target dies in your fight after finish him.", { "fatality" }),
        Row("superbVictory", "Superb victory",
            "When your enemy player target dies in your fight, if it wasn't flawless or a fatality.", { "superbVictory" }),
        Row("deathTaunt", "Death taunt", "When you die. Pathetic.", { "deathTaunt" }),
        { name = "execute", kind = "boolean", default = false, persist = false },
        { name = "combo", kind = "boolean", default = false, persist = false },
        { name = "finisher", kind = "boolean", default = false, persist = false },
    },
    OnEnable = function(module)
        local _, class = UnitClass("player")
        if issecretvalue(class) then
            return
        end
        local execute, combo = class == "WARRIOR", class == "ROGUE" or class == "DRUID"
        module:Set("execute", execute)
        module:Set("combo", combo)
        module:Set("finisher", execute or combo)
    end,
})

Addon:Module("Target", {
    toggle = false,
    active = WhileOn("chooseYourDestiny", "testYourMight", "finishHim", "comboPoint1", "flawlessVictory", "fatality", "superbVictory"),
    state = {
        { name = "serial", kind = "number", default = 0, persist = false },
        { name = "enemyPlayer", kind = "boolean", default = false, persist = false },
        { name = "mighty", kind = "boolean", default = false, persist = false },
        { name = "alive", kind = "boolean", default = false, persist = false },
        { name = "died", kind = "boolean", default = false, persist = false },
        { name = "duelEnded", kind = "boolean", default = false, persist = false },
    },
    OnEnable = function(module)
        local state = Addon.State
        local serial, enemy, mighty = module:Id("serial"), module:Id("enemyPlayer"), module:Id("mighty")
        local alive, died, duelEnded = module:Id("alive"), module:Id("died"), module:Id("duelEnded")

        local function Read()
            if not IsTrue(UnitExists("target")) then
                return false, false, false
            end
            local hostile = IsTrue(UnitCanAttack("player", "target"))
            return hostile and IsTrue(UnitIsPlayer("target")), hostile and IsMighty(), not IsTrue(UnitIsDeadOrGhost("target"))
        end

        -- Same target, new facts: attackability, death, resurrection.
        local function Refresh()
            local isEnemy, isMighty, isAlive = Read()
            if isAlive and not state.Values[alive] then
                state:Set(died, false) -- resurrected: a death from here on counts again
            elseif not isAlive and state.Values[alive] and (isEnemy or state.Values[enemy])
                and not IsTrue(UnitIsFeignDeath("target")) then
                -- An enemy may stop being attackable as it dies; it was one while alive.
                state:Set(died, true)
            end
            state:Set(enemy, isEnemy)
            state:Set(mighty, isMighty)
            state:Set(alive, isAlive)
        end

        -- A new target: its facts start fresh, so a corpse you select never "died while targeted".
        local function Retarget()
            local isEnemy, isMighty, isAlive = Read()
            state:BeginBatch()
            state:Set(serial, state.Values[serial] + 1)
            state:Set(died, false)
            state:Set(duelEnded, false)
            state:Set(enemy, isEnemy)
            state:Set(mighty, isMighty)
            state:Set(alive, isAlive)
            state:EndBatch()
        end

        module:On("PLAYER_TARGET_CHANGED", Retarget)

        -- Duels end at 1 HP. Fleeing out of bounds forfeits, so that doesn't count as a win.
        local outOfBounds = false
        module:On("DUEL_OUTOFBOUNDS", function() outOfBounds = true end)
        module:On("DUEL_INBOUNDS", function() outOfBounds = false end)
        module:On("DUEL_FINISHED", function()
            if state.Values[enemy] and state.Values[alive] and not outOfBounds then
                state:Set(duelEnded, true)
            end
            outOfBounds = false
        end)
        module:On("UNIT_HEALTH", Refresh, "target")
        module:On("UNIT_FACTION", Refresh, "target")
        module:On("UNIT_FLAGS", Refresh, "target")
        module:On("UNIT_CLASSIFICATION_CHANGED", Refresh, "target")
        module:On("UNIT_LEVEL", Refresh, "target")
        Refresh()

        -- A foe worth announcing appears as the target: a new target, or the same one becoming
        -- attackable. Test your might wins over destiny; if it's off or has no file, destiny plays.
        local lastSerial, wasMighty, wasEnemy = state.Values[serial], false, state.Values[enemy]
        module:Watch({ serial, enemy, mighty, alive }, function(state)
            local fresh = state.Values[serial] ~= lastSerial
            local isMighty = state.Values[mighty] and state.Values[alive]
            local isEnemy = state.Values[enemy] and state.Values[alive]
            local played = isMighty and (fresh or not wasMighty) and Play("testYourMight")
            if not played and isEnemy and (fresh or not wasEnemy) then
                Play("chooseYourDestiny")
            end
            lastSerial, wasMighty, wasEnemy = state.Values[serial], isMighty, isEnemy
        end, true)
    end,
})

Addon:Module("Finish", {
    toggle = false,
    active = WhileOn("finishHim", "comboPoint1", "fatality"),
    state = {
        { name = "comboPoints", kind = "number", default = 0, persist = false },
        { name = "ready", kind = "boolean", default = false, persist = false },
        { name = "announced", kind = "number", default = -1, persist = false },
    },
    OnEnable = function(module)
        local state = Addon.State
        local points, ready, announced = module:Id("comboPoints"), module:Id("ready"), module:Id("announced")
        local enemy, alive, serial = module:Id("Target.enemyPlayer"), module:Id("Target.alive"), module:Id("Target.serial")
        local executeName = state:Get("Kombat.execute") and C_Spell.GetSpellName(ExecuteSpellID)
        local combo = state:Get("Kombat.combo")

        -- Usable only; insufficientPower isn't proof of range (the client may check rage first).
        local function Update()
            local inRange = false
            if state.Values[enemy] and state.Values[alive] then
                inRange = state.Values[points] >= FullComboPoints
                    or (executeName and IsTrue((C_Spell.IsSpellUsable(executeName)))) or false
            end
            state:Set(ready, inRange)
        end

        -- Combo points sit on the target (Blizzard's ComboFrame reads GetComboPoints("player",
        -- "target") on UNIT_POWER_FREQUENT and PLAYER_TARGET_CHANGED).
        local function ReadPoints(_, powerType)
            if powerType and powerType ~= "COMBO_POINTS" then
                return -- a druid's mana or energy tick
            end
            local count = GetComboPoints("player", "target")
            state:Set(points, not issecretvalue(count) and count or 0)
        end

        if executeName then
            module:On("SPELL_UPDATE_USABLE", Update)
            module:On("UPDATE_SHAPESHIFT_FORM", Update)
            module:On("UNIT_HEALTH", Update, "target")
        end
        if combo then
            module:On("UNIT_POWER_FREQUENT", ReadPoints, "player")
            module:On("PLAYER_TARGET_CHANGED", ReadPoints)
            ReadPoints()
        end
        module:Watch({ enemy, alive, serial, points }, Update)

        -- A callout for each point added to the same target; spending or losing them is silent.
        local lastPoints, pointsSerial = state.Values[points], state.Values[serial]
        module:Watch({ points, serial }, function(state)
            local count, same = state.Values[points], state.Values[serial] == pointsSerial
            local finishing = count == FullComboPoints and state.Values[enemy] and state.Values[alive]
                and state.Values[announced] ~= state.Values[serial] and IsOn("finishHim")
            if same and count > lastPoints and count <= FullComboPoints and not finishing then
                Play(ComboSounds[count])
            end
            lastPoints, pointsSerial = count, state.Values[serial]
        end, true)

        -- Once per target: a stance dance that flips usability doesn't repeat it.
        module:Watch({ ready, serial }, function(state)
            if state.Values[ready] and state.Values[announced] ~= state.Values[serial] then
                state:Set(announced, state.Values[serial])
                if not Play("finishHim") and state.Values[points] >= FullComboPoints then
                    Play(ComboSounds[FullComboPoints]) -- finish him has no file: the fifth point still calls out
                end
            end
        end, true)
    end,
})

Addon:Module("Victory", {
    toggle = false,
    active = WhileOn("flawlessVictory", "fatality", "superbVictory"),
    state = {
        { name = "flawless", kind = "boolean", default = false, persist = false },
        { name = "flawlessWins", kind = "number", default = 0, persist = false },
    },
    OnEnable = function(module)
        local state = Addon.State
        local flawless, combat = module:Id("flawless"), module:Id("combat.active")
        local died, duelEnded = module:Id("Target.died"), module:Id("Target.duelEnded")
        local serial, announced = module:Id("Target.serial"), module:Id("Finish.announced")
        local wins = 0 -- flawless kills this fight, waiting for the meter to confirm them
        local lastHit = -math.huge -- GetTime() of your last hit

        -- Counts a fight's flawless kills once the meter says you took no damage (or can't say).
        local function Confirm(count, tries)
            if not module.Enabled then
                return
            end
            local taken, final = DamageTakenLastFight()
            if not final and tries > 1 then
                C_Timer.After(ConfirmInterval, function() Confirm(count, tries - 1) end)
            elseif taken == nil or taken == 0 then
                module:Set("flawlessWins", module:Get("flawlessWins") + count)
            end
        end

        local function Outcome()
            if state.Values[flawless] and IsOn("flawlessVictory") then
                return "flawlessVictory"
            elseif state.Values[announced] == state.Values[serial] and IsOn("fatality") then
                return "fatality"
            end
            return "superbVictory"
        end

        module:On("UNIT_COMBAT", function(_, action, _, amount)
            if not IsHit(action, amount) then
                return
            end
            lastHit = GetTime()
            if state.Values[combat] and state.Values[flawless] then
                state:Set(flawless, false)
            end
        end, "player")
        module:Rule({
            reads = { combat }, when = function(state) return state.Values[combat] end,
            changed = function(active)
                state:Set(flawless, active and GetTime() - lastHit > OpeningHitWindow)
                if active then
                    wins = 0
                elseif wins > 0 then
                    Confirm(wins, ConfirmTries)
                    wins = 0
                end
            end,
        })
        module:Rule({
            reads = { died, duelEnded }, when = function(state) return state.Values[died] or state.Values[duelEnded] end,
            changed = function(active, state)
                if not active or not state.Values[combat] then
                    return -- someone else's kill, out of combat
                end
                local outcome = Outcome()
                if state.Values[duelEnded] and not state.Values[died] and outcome ~= "flawlessVictory" then
                    return -- a duel you were hit in may be one you lost
                end
                if outcome == "flawlessVictory" then
                    wins = wins + 1
                end
                Play(outcome)
            end,
        })
    end,
})

Addon:Module("DeathTaunt", {
    toggle = false,
    active = WhileOn("deathTaunt"),
    OnEnable = function(module)
        module:On("PLAYER_DEAD", function()
            Play("deathTaunt")
        end)
    end,
})
