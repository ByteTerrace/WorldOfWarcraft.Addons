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
-- SoundBank:WhileOn). Adapters (event handlers) are the only code that reads the WoW API; the
-- sounds are rules over the rows they publish. What your target is comes from ByteTerrace_Core's
-- target fact (target.serial, target.enemyPlayer, target.formidable, target.alive, target.died,
-- target.duelEnded), which runs only while a module here uses it. DUEL_FINISHED doesn't say who
-- won, but you can't lose a duel you took no damage in, so Victory only counts a flawless one.
--   Kombat    the settings, and class facts: Kombat.execute (warriors), Kombat.combo (rogues and
--             druids) and Kombat.finisher (either).
--   Destiny   plays choose your destiny and test your might as your target changes.
--   Finish    Finish.comboPoints (yours on the target), Finish.ready (in finishing range) and
--             Finish.announced (the target.serial finishing range was last reached on).
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
local OpeningHitWindow = 1 -- seconds: a hit this soon before combat starts opened the fight
local ConfirmTries = 10 -- damage meter reads at the end of a fight, while its numbers are secret
local ConfirmInterval = 0.5 -- seconds between them

local C_DamageMeter, C_Spell, Enum, GetComboPoints, GetTime = C_DamageMeter, C_Spell, Enum, GetComboPoints, GetTime
local ipairs, issecretvalue, type, UnitClass = ipairs, issecretvalue, type, UnitClass

local Addon = ns.Addon
local SoundBank = ns.SoundBank

local function IsTrue(value)
    return not issecretvalue(value) and value == true
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

SoundBank:Define("chooseYourDestiny", { file = "ChooseYourDestiny", word = "destiny", label = "Choose your destiny",
    row = "Kombat.chooseYourDestiny", cooldown = TargetCooldown })
SoundBank:Define("testYourMight", { file = "TestYourMight", word = "might", label = "Test your might",
    row = "Kombat.testYourMight", cooldown = TargetCooldown })
SoundBank:Define("finishHim", { file = "FinishHim", word = "finish", label = "Finish him", row = "Kombat.finishHim",
    needs = "Kombat.finisher" })
for points = 1, FullComboPoints do
    SoundBank:Define("comboPoint" .. points, { file = "ComboPoint" .. points, word = "combo" .. points,
        label = points .. " combo point" .. (points > 1 and "s" or ""), row = "Kombat.comboPoints", needs = "Kombat.combo" })
end
SoundBank:Define("flawlessVictory", { file = "FlawlessVictory", word = "flawless", label = "Flawless victory", row = "Kombat.flawlessVictory" })
SoundBank:Define("fatality", { file = "Fatality", word = "fatality", label = "Fatality", row = "Kombat.fatality", needs = "Kombat.finisher" })
SoundBank:Define("superbVictory", { file = "SuperbVictory", word = "superb", label = "Superb victory", row = "Kombat.superbVictory" })
SoundBank:Define("deathTaunt", { file = "DeathTaunt", word = "taunt", label = "Death taunt", row = "Kombat.deathTaunt" })

local ComboSounds = {}
for points = 1, FullComboPoints do
    ComboSounds[points] = "comboPoint" .. points
end

Addon:Module("Kombat", {
    label = "Mortal Kombat",
    page = "Sounds",
    toggle = false,
    state = {
        SoundBank:Row("chooseYourDestiny", "Choose your destiny",
            "When a living enemy player becomes your target, or your target becomes one (a duel starts). At most every 10 seconds.",
            { "chooseYourDestiny" }),
        SoundBank:Row("testYourMight", "Test your might",
            "When a living elite, rare elite, boss or skull-level enemy becomes your target (players far above your level too). Plays instead of destiny.",
            { "testYourMight" }),
        SoundBank:Row("finishHim", "Finish him",
            "Warriors, rogues and druids: when your enemy player target is in finishing range, once per target. Warriors: Execute is usable (below 20% health; not in Defensive Stance). Rogues and druids: 5 combo points.",
            { "finishHim" }),
        SoundBank:Row("comboPoints", "Combo points",
            "Rogues and druids: a callout for each combo point you add (finish him takes the fifth on an enemy player).",
            ComboSounds),
        SoundBank:Row("flawlessVictory", "Flawless victory",
            "When your enemy player target dies, or yields a duel, during a fight in which you haven't been hit.",
            { "flawlessVictory" }),
        SoundBank:Row("fatality", "Fatality", "When your enemy player target dies in your fight after finish him.", { "fatality" }),
        SoundBank:Row("superbVictory", "Superb victory",
            "When your enemy player target dies in your fight, if it wasn't flawless or a fatality.", { "superbVictory" }),
        SoundBank:Row("deathTaunt", "Death taunt", "When you die. Pathetic.", { "deathTaunt" }),
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

Addon:Module("Destiny", {
    toggle = false,
    uses = { "target" },
    active = SoundBank:WhileOn("chooseYourDestiny", "testYourMight"),
    OnEnable = function(module)
        local serial, enemy = module:Id("target.serial"), module:Id("target.enemyPlayer")
        local formidable, alive = module:Id("target.formidable"), module:Id("target.alive")

        -- A foe worth announcing appears as the target: a new target, or the same one becoming
        -- attackable. Test your might wins over destiny; if it's off or has no file, destiny plays.
        local lastSerial, wasMighty, wasEnemy = module:Get(serial), false, module:Get(enemy)
        module:Watch({ serial, enemy, formidable, alive }, function(state)
            local fresh = state.Values[serial] ~= lastSerial
            local isMighty = state.Values[formidable] and state.Values[alive]
            local isEnemy = state.Values[enemy] and state.Values[alive]
            local played = isMighty and (fresh or not wasMighty) and SoundBank:Play("testYourMight")
            if not played and isEnemy and (fresh or not wasEnemy) then
                SoundBank:Play("chooseYourDestiny")
            end
            lastSerial, wasMighty, wasEnemy = state.Values[serial], isMighty, isEnemy
        end, true)
    end,
})

Addon:Module("Finish", {
    toggle = false,
    uses = { "target" },
    active = SoundBank:WhileOn("finishHim", "comboPoint1", "fatality"),
    state = {
        { name = "comboPoints", kind = "number", default = 0, persist = false },
        { name = "ready", kind = "boolean", default = false, persist = false },
        { name = "announced", kind = "number", default = -1, persist = false },
    },
    OnEnable = function(module)
        local state = Addon.State
        local points, ready, announced = module:Id("comboPoints"), module:Id("ready"), module:Id("announced")
        local enemy, alive, serial = module:Id("target.enemyPlayer"), module:Id("target.alive"), module:Id("target.serial")
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
        -- "target") on UNIT_POWER_FREQUENT and PLAYER_TARGET_CHANGED). Points that move to
        -- another unit keep their count and fire only COMBO_TARGET_CHANGED.
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
            module:On("COMBO_TARGET_CHANGED", ReadPoints)
            ReadPoints()
        end
        module:Watch({ enemy, alive, serial, points }, Update)

        -- A callout for each point added to the same target; spending or losing them is silent.
        local lastPoints, pointsSerial = state.Values[points], state.Values[serial]
        module:Watch({ points, serial }, function(state)
            local count, same = state.Values[points], state.Values[serial] == pointsSerial
            local finishing = count == FullComboPoints and state.Values[enemy] and state.Values[alive]
                and state.Values[announced] ~= state.Values[serial] and SoundBank:IsOn("finishHim")
            if same and count > lastPoints and count <= FullComboPoints and not finishing then
                SoundBank:Play(ComboSounds[count])
            end
            lastPoints, pointsSerial = count, state.Values[serial]
        end, true)

        -- Once per target: a stance dance that flips usability doesn't repeat it.
        module:Watch({ ready, serial }, function(state)
            if state.Values[ready] and state.Values[announced] ~= state.Values[serial] then
                state:Set(announced, state.Values[serial])
                if not SoundBank:Play("finishHim") and state.Values[points] >= FullComboPoints then
                    SoundBank:Play(ComboSounds[FullComboPoints]) -- finish him has no file: the fifth point still calls out
                end
            end
        end, true)
    end,
})

Addon:Module("Victory", {
    toggle = false,
    uses = { "target" },
    active = SoundBank:WhileOn("flawlessVictory", "fatality", "superbVictory"),
    state = {
        { name = "flawless", kind = "boolean", default = false, persist = false },
        { name = "flawlessWins", kind = "number", default = 0, persist = false },
    },
    OnEnable = function(module)
        local state = Addon.State
        local flawless, combat = module:Id("flawless"), module:Id("combat.active")
        local died, duelEnded = module:Id("target.died"), module:Id("target.duelEnded")
        local serial, announced = module:Id("target.serial"), module:Id("Finish.announced")
        local wins = 0 -- flawless kills this fight, waiting for the meter to confirm them
        local lastHit = -math.huge -- GetTime() of your last hit

        -- Counts a fight's flawless kills once the meter says you took no damage (or can't say).
        local function Confirm(count, tries)
            local taken, final = DamageTakenLastFight()
            if not final and tries > 1 then
                module:After(ConfirmInterval, function() Confirm(count, tries - 1) end)
            elseif taken == nil or taken == 0 then
                module:Set("flawlessWins", module:Get("flawlessWins") + count)
            end
        end

        local function Outcome()
            if state.Values[flawless] and SoundBank:IsOn("flawlessVictory") then
                return "flawlessVictory"
            elseif state.Values[announced] == state.Values[serial] and SoundBank:IsOn("fatality") then
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
                SoundBank:Play(outcome)
            end,
        })
    end,
})

Addon:Module("DeathTaunt", {
    toggle = false,
    active = SoundBank:WhileOn("deathTaunt"),
    OnEnable = function(module)
        module:On("PLAYER_DEAD", function()
            SoundBank:Play("deathTaunt")
        end)
    end,
})
