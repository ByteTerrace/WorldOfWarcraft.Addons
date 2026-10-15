local addonName, ns = ...

-- The situations calibration probes need (Probes.lua's header says what a need holds), added
-- with Probes.AddNeeds. Keys are what probes name in their needs; step places each in one play
-- session in a starting zone (Probes.Steps). A check only reads, and its harness setup recreates
-- the situation in the fake client from the harness's own scripting (h:SetTarget, h:MeterFight).
-- NamePlateToken and FirstBagItem are shared with the probes that read the same things, and
-- PvPLaterSeconds with ProbesCombat.lua's PvP listener.

-- The restrictions that make auras secret (SecretPredicatesDocumentation's
-- SecretWhenAurasRestricted).
local AuraRestrictions = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }

-- Seconds after leaving combat in a PvP match at which damageMeter.pvpSecrecy reads the meter again.
local PvPLaterSeconds = 5

local Probes = ns.Probes
local AfterDeath, Kills, UnitCombat = Probes.AfterDeath, Probes.Kills, Probes.UnitCombat
local AuraTokens, CombatEdges, Restricted = Probes.AuraTokens, Probes.CombatEdges, Probes.Restricted

--- The nameplate token of a non-player unit on screen that the player can attack (enemy true) or
--- can't (enemy false), or nil.
local function NamePlateToken(enemy)
    for i = 1, 40 do
        local token = ("nameplate" .. i)

        if UnitExists(token) and not UnitIsPlayer(token) and (UnitCanAttack("player", token) == enemy) then
            return token
        end
    end
    return nil
end

--- The backpack's first item (C_Container.GetContainerItemInfo), or nil.
local function FirstBagItem()
    local bag = Enum.BagIndex.Backpack

    for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)

        if info then
            return info
        end
    end
    return nil
end

-- Event-kind probes wait for an actual sample; no spell in a recap isn't spell-field evidence.
local function HasRecapEvent(kind)
    for _, event in ipairs(C_DeathRecap.GetRecapEvents()) do
        local eventKind = event.event

        if not issecretvalue(eventKind) and (eventKind == kind) then
            return true
        end
    end
    return false
end

-- Whether the damage meter's current session of a type has a source: someone in it.
local function HasSources(meterType)
    local current = Enum.DamageMeterSessionType.Current
    -- secret: only the sources list is read, checked with issecretvalue
    local sources = C_DamageMeter.GetCombatSessionFromType(current, meterType).combatSources

    return (not issecretvalue(sources) and (type(sources) == "table") and (sources[1] ~= nil))
end

-- Whether a UNIT_AURA was heard while auras were restricted: a restriction text AuraTokens keys
-- by names one of AuraRestrictions.
local function HeardAuraRestricted()
    for text in pairs(AuraTokens) do
        for _, name in ipairs(AuraRestrictions) do
            if ("," .. text .. ","):find("," .. name .. ",", 1, true) then
                return true
            end
        end
    end
    return false
end

-- Out of combat (no lockdown, not fighting), with exactly these addon restrictions in force.
local function CalmWith(restrictions)
    return (not InCombatLockdown() and not UnitAffectingCombat("player") and (Probes.Restrictions() == restrictions))
end

local Needs = {
    idle = {
        check = function() return CalmWith("none") end,
        label = "idle",
        setup = function() end,
        step = 1,
        text = "out of combat in the open world (no addon restrictions active)",
    },
    restrictedMap = {
        check = function() return CalmWith("Map") end,
        label = "restricted map",
        setup = function(h) h:SetRestriction("Map", true) end,
        step = 6,
        text = "out of combat in a dungeon, between pulls (the Map restriction alone)",
    },
    enUS = {
        check = function() return (GetLocale() == "enUS") end,
        label = "enUS client",
        setup = function() end,
        step = 1,
        text = "an English (enUS) client",
    },
    openWorld = {
        check = function() return not IsInInstance() end,
        label = "open world",
        setup = function(h)
            h:AddMap(1429, { name = "Elwynn Forest" })
            h:SetLocation({ mapID = 1429, x = 0.42, y = 0.65 })
        end,
        step = 1,
        text = "outdoors in the open world (not in an instance)",
    },
    questLog = {
        check = function() return (select(2, C_QuestLog.GetNumQuestLogEntries()) > 0) end,
        label = "quests in log",
        setup = function(h)
            h:AutoAcceptQuest({ header = "Elwynn Forest",
                objectives = {
                    { required = 4, text = "Gold Dust", type = "item" },
                    { required = 1, text = "Report to Marshal McBride", type = "log" },
                },
                title = "Kobold Camp Cleanup" })
        end,
        step = 1,
        text = "at least one quest in your quest log",
    },
    bagItem = {
        check = function() return (FirstBagItem() ~= nil) end,
        harness = "the harness doesn't model bags (C_Container)",
        label = "item in backpack",
        step = 1,
        text = "an item in your backpack (your hearthstone counts)",
    },
    controller = {
        check = function() return (C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()) ~= nil) end,
        label = "controller",
        setup = function(h) h.labelStyle = "Letters" end,
        step = 1,
        text = "a controller connected (press one of its buttons first)",
    },
    npcTarget = {
        check = function()
            return (UnitExists("target") and not UnitPlayerControlled("target") and not UnitIsDead("target"))
        end,
        label = "NPC target",
        setup = function(h) h:SetTarget({ classFile = "WARRIOR", level = 12, name = "Marshal Dughan" }) end,
        step = 2,
        text = "target a living NPC (a quest giver or a mob)",
    },
    questOffer = {
        check = function() return QuestFrameDetailPanel:IsVisible() end,
        label = "quest offer open",
        setup = function(h)
            h:OfferQuest({ goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.",
                text = "The wolves grow bolder each night.", title = "Wolves Across the Border" }, "Eagan Peltskinner")
        end,
        step = 2,
        text = "a quest offer open (talk to a quest giver and open a quest you haven't accepted)",
    },
    questTurnIn = {
        check = function() return QuestFrameRewardPanel:IsVisible() end,
        label = "quest turn-in open",
        setup = function(h)
            local id = h:AutoAcceptQuest({ title = "Report to Goldshire" })

            h:OpenTurnIn(id, "Marshal Dughan", "Ah, you made it.")
        end,
        step = 2,
        text = "a quest turn-in open (the reward panel, before you click Complete Quest)",
    },
    friendlyNamePlate = {
        check = function() return (NamePlateToken(false) ~= nil) end,
        label = "friendly nameplate",
        setup = function(h) h:AddNamePlate({ classFile = "WARRIOR", level = 10, name = "Marshal McBride" }) end,
        step = 2,
        text = "a friendly NPC's nameplate on screen (Shift+V shows friendly nameplates; face a quest giver)",
    },
    merchant = {
        check = function() return MerchantFrame:IsVisible() end,
        harness = "the harness doesn't model vendors (MerchantFrame, C_MerchantFrame)",
        label = "vendor open",
        step = 3,
        text = "a vendor's window open (talk to a vendor)",
    },
    trainer = {
        check = function()
            local count = GetNumTrainerServices()

            return (not issecretvalue(count) and (type(count) == "number") and (count > 0))
        end,
        harness = "the harness doesn't model trainers",
        label = "trainer open",
        step = 3,
        text = "a trainer's window open (talk to your class trainer or a profession trainer)",
    },
    enemyNamePlate = {
        check = function() return (NamePlateToken(true) ~= nil) end,
        label = "enemy nameplate",
        setup = function(h)
            h:AddNamePlate({ canAttack = true, classFile = "WARRIOR", level = 2, name = "Kobold Vermin" })
        end,
        step = 4,
        text = "a hostile mob's nameplate on screen (V shows enemy nameplates; face a mob)",
    },
    combat = {
        check = function() return UnitAffectingCombat("player") end,
        label = "in combat",
        setup = function(h) h:EnterCombat() end,
        step = 4,
        text = "in combat (pull a mob and type the command mid-fight)",
    },
    meterInCombat = {
        check = function()
            if not UnitAffectingCombat("player") then
                return false
            end
            return HasSources(Enum.DamageMeterType.DamageDone)
        end,
        label = "hit something in combat",
        setup = function(h)
            h:EnterCombat()
            h:MeterAdd({ amounts = { DamageDone = 50 }, unit = "player" })
        end,
        step = 4,
        text = "in combat after you've hit something (pull a mob, hit it, and type the command mid-fight)",
    },
    unitCombat = {
        check = function() return ((next(UnitCombat.units.player) ~= nil) and (next(UnitCombat.units.target) ~= nil)) end,
        harness = "the harness doesn't raise UNIT_COMBAT from fights, and which actions a fight shows varies",
        label = "traded blows",
        step = 4,
        text = "a few seconds of trading blows with a mob (hit it and let it hit you; type it mid-fight or after)",
    },
    combatEdges = {
        check = function() return ((CombatEdges.enter[1] ~= nil) and (CombatEdges.leave[1] ~= nil)) end,
        label = "in and out of combat",
        setup = function(h)
            h:EnterCombat()
            h:LeaveCombat()
        end,
        step = 4,
        text = "entered and left combat since DevTools loaded (pull a mob, kill it, and type it once the fight ends)",
    },
    auraRestricted = {
        check = HeardAuraRestricted,
        label = "aura change in combat",
        setup = function(h)
            h:EnterCombat()
            h:Fire("UNIT_AURA", "player", { isFullUpdate = true })
            h:LeaveCombat()
        end,
        step = 4,
        text = "an aura changed on you or your target in combat (a buff or debuff mid-fight; type it then or after)",
    },
    killedMob = {
        check = function() return ((Kills.partyKill ~= nil) and (Kills.partyKill.attacker.you == true) and Kills.targetDied) end,
        harness = "the harness doesn't raise kill events from fights",
        label = "killed a mob",
        step = 4,
        text = "a mob you targeted and killed yourself since logging in (type it after the kill)",
    },
    afterFight = {
        check = function()
            local types = Enum.DamageMeterType
            -- A fight you were hit in but dealt no damage in (a death on the run) has no enemy to show.
            return (not UnitAffectingCombat("player") and HasSources(types.DamageTaken)
                and HasSources(types.DamageDone) and HasSources(types.EnemyDamageTaken))
        end,
        label = "after a fight",
        setup = function(h)
            h:MeterFight({
                duration = 8,
                sources = {
                    {
                        amounts = { DamageDone = 180 },
                        spells = { DamageTaken = { {
                            details = { classification = "normal", isMob = true, unitName = "Kobold Vermin" },
                            spellID = 6603, totalAmount = 24,
                        } } },
                        unit = "player",
                    },
                    {
                        amounts = { EnemyDamageTaken = 180 }, classification = "normal", creatureID = 6,
                        name = "Kobold Vermin",
                    },
                },
            })
        end,
        step = 4,
        text = "right after killing a mob that hit you (out of combat, before the next pull)",
    },
    twoFights = {
        check = function()
            return ((#C_DamageMeter.GetAvailableCombatSessions() >= 2) and HasSources(Enum.DamageMeterType.DamageDone))
        end,
        label = "after two fights",
        setup = function(h)
            h:MeterFight({ duration = 6, sources = { { amounts = { DamageDone = 300 }, unit = "player" } } })
            h:MeterFight({ duration = 9, sources = { { amounts = { DamageDone = 700 }, unit = "player" } } })
        end,
        step = 4,
        text = "two fights since logging in (kill two mobs), the latest one you dealt damage in",
    },
    deathWatched = {
        label = "a death watched",
        text = ("a death since DevTools loaded, over %d seconds ago (die, wait, then type it)"):format(Probes.AfterDeathSeconds),
        step = 5,
        check = function()
            return ((AfterDeath.diedAt ~= nil) and ((GetTime() - AfterDeath.diedAt) > Probes.AfterDeathSeconds))
        end,
        setup = function(h) h:Advance(Probes.AfterDeathSeconds + 1) end,
    },
    enemyHunterFeigning = {
        check = function()
            local _, class = UnitClass("target")

            if issecretvalue(class) or (class ~= "HUNTER") or not UnitIsPlayer("target") or not UnitCanAttack("player", "target") then
                return false
            end
            local dead, feigning = UnitIsDeadOrGhost("target"), UnitIsFeignDeath("target")

            return ((not issecretvalue(dead) and (dead == true)) or (not issecretvalue(feigning) and (feigning == true)))
        end,
        harness = "only the client can say what it reports for an enemy's Feign Death",
        label = "enemy hunter feigning",
        step = 6,
        text = "target a hunter of the other faction while they Feign Death",
    },
    diedToMob = {
        check = function() return (UnitIsDeadOrGhost("player") and not UnitAffectingCombat("player")) end,
        label = "killed by a mob",
        setup = function(h)
            h:MeterFight({
                duration = 12,
                sources = {
                    {
                        amounts = { DamageDone = 40 }, death = { maxHealth = 55 },
                        spells = { DamageTaken = {
                            {
                                details = { classification = "normal", isMob = true, unitName = "Kobold Vermin" },
                                name = "Strike", spellID = 11976, totalAmount = 20,
                            },
                            {
                                creatureName = "Kobold Vermin",
                                details = { classification = "normal", isMob = true, unitName = "Kobold Vermin" },
                                isDeadly = true, overkillAmount = 5, spellID = 6603, totalAmount = 60,
                            },
                        } },
                        unit = "player",
                    },
                    {
                        amounts = { DamageDone = 60 }, classification = "normal", creatureID = 6,
                        name = "Kobold Vermin",
                    },
                },
            })
        end,
        step = 5,
        text = "dead or a ghost after letting a mob kill you (type it before you resurrect)",
    },
    recapSwingDamage = {
        label = "melee in recap",
        text = "a melee swing in your death recap (let the mob hit you before it kills you)",
        step = 5,
        check = function() return HasRecapEvent("SWING_DAMAGE") end,
        setup = function() end, -- diedToMob scripts both swing and spell damage.
    },
    recapSpellDamage = {
        label = "spell in recap",
        text = "a direct damage spell in your death recap (let a mob use a spell before it kills you)",
        step = 5,
        check = function() return HasRecapEvent("SPELL_DAMAGE") end,
        setup = function() end, -- diedToMob scripts both swing and spell damage.
    },
    enemyPlayer = {
        check = function()
            return (UnitExists("target") and UnitIsPlayer("target") and UnitIsEnemy("player", "target"))
        end,
        label = "enemy player target",
        setup = function(h)
            h:SetTarget({
                canAttack = true, classFile = "WARRIOR", faction = "Horde", isPlayer = true, level = 20,
                name = "Grommash", race = "Orc",
            })
        end,
        step = 6,
        text = "target a player of the other faction",
    },
    playerTarget = {
        check = function()
            local target, me = UnitGUID("target"), UnitGUID("player")

            if issecretvalue(target) or issecretvalue(me) then
                return false
            end
            return (UnitIsPlayer("target") and (target ~= nil) and (target ~= me))
        end,
        label = "player target",
        setup = function(h) h:SetTarget({ classFile = "WARRIOR", isPlayer = true, level = 20, name = "Grommash", race = "Orc" }) end,
        step = 1,
        text = "target another player (any faction; one whose name shows a surname is best)",
    },
    heardChat = {
        label = "heard chat",
        text = "someone spoke in say, a channel (General), your group or guild since you logged in",
        step = 1,
        check = function() return (next(Probes.DiscordInfo.shapes) ~= nil) end, -- any chat event but an addon message
        setup = function(h)
            h:FireChat("CHAT_MSG_SAY", "hello", "Bob Doe")
            h:FireChat("CHAT_MSG_CHANNEL", "hi", "Cara Doe")
        end,
    },
    party = {
        check = function() return (IsInGroup() and not IsInRaid() and UnitExists("party1")) end,
        label = "in a party",
        setup = function(h) h:JoinGroup("party", { "Friend" }) end,
        step = 6,
        text = "in a party (not a raid) with another player",
    },
    messagingRestricted = {
        check = function()
            if not IsInGroup() then
                return false
            end
            for name in pairs(Restricted.seen) do
                if name ~= "Combat" then
                    return true
                end
            end
            return false
        end,
        label = "group through a restriction",
        setup = function(h)
            h:JoinGroup("party", { "Friend" })
            h:SetRestriction("Map", true)
        end,
        step = 6,
        text = "in a party with a Krew member (The Lan Krew ToolKit), in a dungeon or boss fight since DevTools loaded",
    },
    pvpFight = {
        label = "after a PvP fight",
        text = ("a fight in a battleground or arena since DevTools loaded, over %d seconds ago (deal damage, "
            .. "leave combat, wait, then type it)"):format(PvPLaterSeconds),
        step = 6,
        check = function()
            local meter = Probes.PvPMeter -- ProbesCombat.lua's, which loads after this file

            return ((next(meter.leftCombat) ~= nil) and (next(meter.later) ~= nil))
        end,
        setup = function(h)
            h:SetLocation({ instance = "pvp" })
            h:SetRestriction("PvPMatch", true)
            h:MeterFight({ duration = 10, sources = { { amounts = { DamageDone = 420 }, unit = "player" } } })
            h:Advance(PvPLaterSeconds + 1)
        end,
    },
    encounter = {
        label = "boss encounter",
        text = "a boss encounter started since DevTools loaded (pull a dungeon or raid boss; type it during or after)",
        step = 6,
        check = function() return Probes.EncounterWarnings.started end, -- ProbesCombat.lua's
        setup = function(h) h:StartEncounter({ name = "Hogger" }) end,
    },
    maxLevel = {
        check = function() return (UnitLevel("player") >= GetMaxPlayerLevel()) end,
        label = "max level",
        setup = function(h) h.player.level = h.maxLevel end,
        step = 6,
        text = "playing a character at the max level (GetMaxPlayerLevel)",
    },
    guild = {
        check = function() return IsInGuild() end,
        label = "in a guild",
        setup = function(h) h.player.guild, h.player.guildRank, h.player.guildRankIndex = "The Lan Krew", "Member", 1 end,
        step = 6,
        text = "in a guild",
    },
    resting = {
        check = function() return IsResting() end,
        label = "resting",
        setup = function(h) h.player.resting = true end,
        step = 6,
        text = "resting in an inn or a city (Zzz on your portrait)",
    },
    onTaxi = {
        check = function() return UnitOnTaxi("player") end,
        label = "on a flight",
        setup = function(h) h:TakeFlight() end,
        step = 6,
        text = "on a flight path (type it mid-flight)",
    },
    comboPoints = {
        check = function()
            local max = UnitPowerMax("player", Enum.PowerType.ComboPoints) -- secret: checked with issecretvalue

            return (not issecretvalue(max) and (max > 0))
        end,
        label = "combo points",
        setup = function(h)
            local comboPoints = Enum.PowerType.ComboPoints

            h.player.power[comboPoints], h.player.powerMax[comboPoints] = 0, 5
        end,
        step = 6,
        text = "playing a rogue, or a druid in cat form (a class with combo points)",
    },
}

Probes.NamePlateToken = NamePlateToken
Probes.FirstBagItem = FirstBagItem
Probes.PvPLaterSeconds = PvPLaterSeconds
Probes.AddNeeds(Needs)
