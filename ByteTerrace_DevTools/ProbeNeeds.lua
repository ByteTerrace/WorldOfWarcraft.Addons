local addonName, ns = ...

-- The situations calibration probes need (Probes.lua's header says what a need holds), added
-- with Probes.AddNeeds. Keys are what probes name in their needs; step places each in one play
-- session in a starting zone (Probes.Steps). A check only reads, and its harness setup recreates
-- the situation in the fake client from the harness's own scripting (h:SetTarget, h:MeterFight).
-- NamePlateToken and FirstBagItem are shared with the probes that read the same things.

local Probes = ns.Probes
local UnitCombat, Kills = Probes.UnitCombat, Probes.Kills

--- The nameplate token of a non-player unit on screen that the player can attack (enemy true) or
--- can't (enemy false), or nil.
local function NamePlateToken(enemy)
    for i = 1, 40 do
        local token = "nameplate" .. i
        if UnitExists(token) and not UnitIsPlayer(token) and UnitCanAttack("player", token) == enemy then
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

local Needs = {
    idle = {
        label = "idle",
        text = "out of combat in the open world (no addon restrictions active)",
        step = 1,
        check = function()
            return not InCombatLockdown() and not UnitAffectingCombat("player") and Probes.Restrictions() == "none"
        end,
        setup = function() end,
    },
    enUS = {
        label = "enUS client",
        text = "an English (enUS) client",
        step = 1,
        check = function() return GetLocale() == "enUS" end,
        setup = function() end,
    },
    openWorld = {
        label = "open world",
        text = "outdoors in the open world (not in an instance)",
        step = 1,
        check = function() return not IsInInstance() end,
        setup = function(h)
            h:AddMap(1429, { name = "Elwynn Forest" })
            h:SetLocation({ mapID = 1429, x = 0.42, y = 0.65 })
        end,
    },
    questLog = {
        label = "quests in log",
        text = "at least one quest in your quest log",
        step = 1,
        check = function() return select(2, C_QuestLog.GetNumQuestLogEntries()) > 0 end,
        harness = "the harness doesn't model the quest log (C_QuestLog)",
    },
    bagItem = {
        label = "item in backpack",
        text = "an item in your backpack (your hearthstone counts)",
        step = 1,
        check = function() return FirstBagItem() ~= nil end,
        harness = "the harness doesn't model bags (C_Container)",
    },
    controller = {
        label = "controller",
        text = "a controller connected (press one of its buttons first)",
        step = 1,
        check = function() return C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()) ~= nil end,
        setup = function(h) h.labelStyle = "Letters" end,
    },
    npcTarget = {
        label = "NPC target",
        text = "target a living NPC (a quest giver or a mob)",
        step = 2,
        check = function()
            return UnitExists("target") and not UnitPlayerControlled("target") and not UnitIsDead("target")
        end,
        setup = function(h) h:SetTarget({ name = "Marshal Dughan", classFile = "WARRIOR", level = 12 }) end,
    },
    questOffer = {
        label = "quest offer open",
        text = "a quest offer open (talk to a quest giver and open a quest you haven't accepted)",
        step = 2,
        check = function() return QuestFrameDetailPanel:IsVisible() end,
        harness = "the harness doesn't model quest dialogs",
    },
    questTurnIn = {
        label = "quest turn-in open",
        text = "a quest turn-in open (the reward panel, before you click Complete Quest)",
        step = 2,
        check = function() return QuestFrameRewardPanel:IsVisible() end,
        harness = "the harness doesn't model quest dialogs",
    },
    friendlyNamePlate = {
        label = "friendly nameplate",
        text = "a friendly NPC's nameplate on screen (Shift+V shows friendly nameplates; face a quest giver)",
        step = 2,
        check = function() return NamePlateToken(false) ~= nil end,
        setup = function(h) h:AddNamePlate({ name = "Marshal McBride", classFile = "WARRIOR", level = 10 }) end,
    },
    merchant = {
        label = "vendor open",
        text = "a vendor's window open (talk to a vendor)",
        step = 3,
        check = function() return MerchantFrame:IsVisible() end,
        harness = "the harness doesn't model vendors (MerchantFrame, C_MerchantFrame)",
    },
    trainer = {
        label = "trainer open",
        text = "a trainer's window open (talk to your class trainer or a profession trainer)",
        step = 3,
        check = function()
            local count = GetNumTrainerServices()
            return not issecretvalue(count) and type(count) == "number" and count > 0
        end,
        harness = "the harness doesn't model trainers",
    },
    enemyNamePlate = {
        label = "enemy nameplate",
        text = "a hostile mob's nameplate on screen (V shows enemy nameplates; face a mob)",
        step = 4,
        check = function() return NamePlateToken(true) ~= nil end,
        setup = function(h)
            h:AddNamePlate({ name = "Kobold Vermin", classFile = "WARRIOR", level = 2, canAttack = true })
        end,
    },
    combat = {
        label = "in combat",
        text = "in combat (pull a mob and type the command mid-fight)",
        step = 4,
        check = function() return UnitAffectingCombat("player") end,
        setup = function(h) h:EnterCombat() end,
    },
    meterInCombat = {
        label = "hit something in combat",
        text = "in combat after you've hit something (pull a mob, hit it, and type the command mid-fight)",
        step = 4,
        check = function()
            if not UnitAffectingCombat("player") then
                return false
            end
            local current, damageDone = Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone
            -- secret: only the sources list is read, checked with issecretvalue
            local session = C_DamageMeter.GetCombatSessionFromType(current, damageDone)
            local sources = session.combatSources
            return not issecretvalue(sources) and type(sources) == "table" and sources[1] ~= nil
        end,
        setup = function(h)
            h:EnterCombat()
            h:MeterAdd({ unit = "player", amounts = { DamageDone = 50 } })
        end,
    },
    unitCombat = {
        label = "traded blows",
        text = "a few seconds of trading blows with a mob (hit it and let it hit you; type it mid-fight or after)",
        step = 4,
        check = function() return next(UnitCombat.units.player) ~= nil and next(UnitCombat.units.target) ~= nil end,
        harness = "the harness doesn't raise UNIT_COMBAT from fights, and which actions a fight shows varies",
    },
    killedMob = {
        label = "killed a mob",
        text = "a mob you targeted and killed yourself since logging in (type it after the kill)",
        step = 4,
        check = function() return Kills.partyKill ~= nil end,
        harness = "the harness doesn't raise kill events from fights",
    },
    afterFight = {
        label = "after a fight",
        text = "right after killing a mob that hit you (out of combat, before the next pull)",
        step = 4,
        check = function()
            if UnitAffectingCombat("player") then
                return false
            end
            local current, damageTaken = Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageTaken
            -- secret: only the sources list is read, checked with issecretvalue
            local session = C_DamageMeter.GetCombatSessionFromType(current, damageTaken)
            local sources = session.combatSources
            return not issecretvalue(sources) and type(sources) == "table" and sources[1] ~= nil
        end,
        setup = function(h)
            h:MeterFight({
                duration = 8,
                sources = {
                    {
                        unit = "player", amounts = { DamageDone = 180 },
                        spells = { DamageTaken = { {
                            spellID = 6603, totalAmount = 24,
                            details = { unitName = "Kobold Vermin", classification = "normal", isMob = true },
                        } } },
                    },
                    {
                        name = "Kobold Vermin", creatureID = 6, classification = "normal",
                        amounts = { EnemyDamageTaken = 180 },
                    },
                },
            })
        end,
    },
    twoFights = {
        label = "after two fights",
        text = "two fights since logging in (kill two mobs)",
        step = 4,
        check = function() return #C_DamageMeter.GetAvailableCombatSessions() >= 2 end,
        setup = function(h)
            h:MeterFight({ duration = 6, sources = { { unit = "player", amounts = { DamageDone = 300 } } } })
            h:MeterFight({ duration = 9, sources = { { unit = "player", amounts = { DamageDone = 700 } } } })
        end,
    },
    diedToMob = {
        label = "killed by a mob",
        text = "dead or a ghost after letting a mob kill you (type it before you resurrect)",
        step = 5,
        check = function() return UnitIsDeadOrGhost("player") and not UnitAffectingCombat("player") end,
        setup = function(h)
            h:MeterFight({
                duration = 12,
                sources = {
                    {
                        unit = "player", amounts = { DamageDone = 40 },
                        spells = { DamageTaken = {
                            {
                                spellID = 11976, name = "Strike", totalAmount = 20,
                                details = { unitName = "Kobold Vermin", classification = "normal", isMob = true },
                            },
                            {
                                spellID = 6603, totalAmount = 60, creatureName = "Kobold Vermin", overkillAmount = 5,
                                isDeadly = true,
                                details = { unitName = "Kobold Vermin", classification = "normal", isMob = true },
                            },
                        } },
                        death = { maxHealth = 55 },
                    },
                    {
                        name = "Kobold Vermin", creatureID = 6, classification = "normal",
                        amounts = { DamageDone = 60 },
                    },
                },
            })
        end,
    },
    enemyPlayer = {
        label = "enemy player target",
        text = "target a player of the other faction",
        step = 6,
        check = function()
            return UnitExists("target") and UnitIsPlayer("target") and UnitIsEnemy("player", "target")
        end,
        setup = function(h)
            h:SetTarget({
                name = "Grommash", isPlayer = true, canAttack = true, classFile = "WARRIOR", race = "Orc",
                faction = "Horde", level = 20,
            })
        end,
    },
    party = {
        label = "in a party",
        text = "in a party (not a raid) with another player",
        step = 6,
        check = function() return IsInGroup() and not IsInRaid() and UnitExists("party1") end,
        setup = function(h) h:JoinGroup("party", { "Friend" }) end,
    },
    guild = {
        label = "in a guild",
        text = "in a guild",
        step = 6,
        check = function() return IsInGuild() end,
        setup = function(h) h.player.guild, h.player.guildRank, h.player.guildRankIndex = "The Lan Krew", "Member", 1 end,
    },
    resting = {
        label = "resting",
        text = "resting in an inn or a city (Zzz on your portrait)",
        step = 6,
        check = function() return IsResting() end,
        setup = function(h) h.player.resting = true end,
    },
    onTaxi = {
        label = "on a flight",
        text = "on a flight path (type it mid-flight)",
        step = 6,
        check = function() return UnitOnTaxi("player") end,
        harness = "the harness doesn't model flight paths (UnitOnTaxi)",
    },
    comboPoints = {
        label = "combo points",
        text = "playing a rogue, or a druid in cat form (a class with combo points)",
        step = 6,
        check = function()
            local max = UnitPowerMax("player", Enum.PowerType.ComboPoints) -- secret: checked with issecretvalue
            return not issecretvalue(max) and max > 0
        end,
        setup = function(h)
            local comboPoints = Enum.PowerType.ComboPoints
            h.player.power[comboPoints], h.player.powerMax[comboPoints] = 0, 5
        end,
    },
}

Probes.NamePlateToken = NamePlateToken
Probes.FirstBagItem = FirstBagItem
Probes.AddNeeds(Needs)
