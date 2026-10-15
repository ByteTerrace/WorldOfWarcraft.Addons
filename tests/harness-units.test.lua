-- The harness's fidelity rules for units (tests/harness/units.lua): enemy players, nameplates, mouseover, death, raid
-- target icons, GUIDs and realms.

local Kit = use("harness")

local Watch = Kit.Watch

local function EnemyPlayer(fields)
    local unit = { canAttack = true, classFile = "ROGUE", faction = "Alliance", isPlayer = true, level = 60,
        name = "Bob", race = "Human" }

    for key, value in pairs(fields or {}) do unit[key] = value end

    return unit
end

test("an enemy player's identity reads plainly: name, surname, class, race, faction, level", function()
    local h = Harness.New({ faction = "Horde", race = "Orc", realm = "Home Realm" })
    local env = h.env

    h:SetTarget(EnemyPlayer({ realm = "Other Realm", surname = "Smith" }))
    local name, surname = env.UnitName("target")

    eq(name, "Bob")
    eq(surname, "Smith", "the second return is the surname, never the realm")
    eq(select("#", env.UnitName("target")), 2, "no realm return, even from another realm")
    falsy(env.issecretvalue(name), "a player-controlled unit's name is readable")
    local className, classFile, classID = env.UnitClass("target")

    eq(className, "Rogue")
    eq(classFile, "ROGUE")
    eq(classID, 4)
    local faction, localized = env.UnitFactionGroup("target")

    eq(faction, "Alliance")
    eq(localized, "Alliance")
    eq(env.UnitFactionGroup("player"), "Horde")
    eq(env.UnitLevel("target"), 60)
    truthy(env.UnitIsPlayer("target"))
    truthy(env.UnitPlayerControlled("target"))
    h:SetTarget(EnemyPlayer({ realm = "Home Realm" }))
    eq(select(2, env.UnitName("target")), Harness.DEFAULT_SURNAME, "no surname given: the default one")
    eq(select(2, env.UnitFullName("target")), Harness.DEFAULT_SURNAME, "UnitFullName: the surname too")
end)

test("hostility is relative to the player: canAttack, and isEnemy defaulting to it", function()
    local h = Harness.New()
    local env = h.env

    h:SetTarget(EnemyPlayer())
    truthy(env.UnitCanAttack("player", "target"))
    truthy(env.UnitCanAttack("target", "player"))
    truthy(env.UnitIsEnemy("player", "target"), "isEnemy follows canAttack")
    falsy(env.UnitIsEnemy("player", "player"))
    -- an enemy you can't attack (sanctuary)
    h:SetTarget(EnemyPlayer({ canAttack = false, isEnemy = true }))
    falsy(env.UnitCanAttack("player", "target"))
    truthy(env.UnitIsEnemy("player", "target"))
    h:SetTarget(nil)
    falsy(env.UnitIsEnemy("player", "target"), "no unit")
end)

test("combat and death are per unit; the player's combat is the harness's", function()
    local h = Harness.New()
    local env = h.env

    h:SetTarget(EnemyPlayer({ inCombat = true }))
    truthy(env.UnitAffectingCombat("target"))
    falsy(env.UnitAffectingCombat("player"))
    h:EnterCombat()
    truthy(env.UnitAffectingCombat("player"))
    h:SetTarget(EnemyPlayer({ dead = true }))
    truthy(env.UnitIsDead("target"))
    truthy(env.UnitIsDeadOrGhost("target"))
    h:SetTarget(EnemyPlayer({ ghost = true }))
    falsy(env.UnitIsDead("target"), "a ghost isn't dead")
    truthy(env.UnitIsDeadOrGhost("target"))
end)

test("UnitHealthMissing is max minus health and UnitHealthPercent the fraction left, both secret", function()
    local h = Harness.New()
    local env = h.env

    h:SetTarget(EnemyPlayer({ health = 30, maxHealth = 120 }))
    local missing, percent = env.UnitHealthMissing("target"), env.UnitHealthPercent("target", false)

    truthy(env.issecretvalue(missing) and env.issecretvalue(percent), "SecretReturns, like UnitHealth")
    eq(Reveal(missing), 90)
    eq(Reveal(percent), 0.25)
    eq(Reveal(env.UnitHealthPercent("player")), 1)
    eq(Reveal(env.UnitHealthPercent("focus")), 0, "no unit")
    throws(function() env.UnitHealthPercent("player", true, {}) end, "curves")
end)

test("GUIDs: players and NPCs have their formats, NPC GUIDs are secret, and the token comes back", function()
    local h = Harness.New()
    local env = h.env

    h:SetTarget(EnemyPlayer())
    local guid = env.UnitGUID("target")

    falsy(env.issecretvalue(guid))
    truthy(guid:find("^Player%-%d+%-%x+$"), guid)
    eq(env.UnitGUID("target"), guid, "stable")
    eq(h:UnitTokenForGUID(guid), "target")
    eq(h:UnitTokenForGUID(env.UnitGUID("player")), "player")
    eq(h:UnitTokenForGUID("Player-1-DEADBEEF"), nil)
    h:SetTarget({ guid = "Creature-0-1465-0-2105-448-000043F59F", name = "Hogger" })
    falsy(env.issecretvalue(env.UnitGUID("target")), "plain in the open world")
    h:SetRestriction("Encounter", true)
    local npc = env.UnitGUID("target")

    truthy(env.issecretvalue(npc), "an NPC's GUID is identity-restricted in an encounter")
    eq(Reveal(npc), "Creature-0-1465-0-2105-448-000043F59F")
    eq(h:UnitTokenForGUID(npc), "target", "a secret GUID still names its unit")
end)

test("a secret token passed where secrets are allowed names the unit, and the answer is secret", function()
    local h = Harness.New()

    h:SetTarget({ name = "Hogger" })
    h:SetRestriction("Encounter", true)
    local token = Secret("target")
    -- UnitName allows secret arguments
    local name = h.env.UnitName(token)

    truthy(h.env.issecretvalue(name))
    eq(Reveal(name), "Hogger")
end)

test("UnitTokenPvPRestrictedForAddOns: in a PvP match an enemy's GUID is secret, the group's isn't", function()
    local h = Harness.New()
    local env = h.env

    h:SetTarget(EnemyPlayer())
    h:JoinGroup("party", { "Mom" })
    falsy(env.issecretvalue(env.UnitGUID("target")), "outside a match")
    h:SetRestriction("PvPMatch", true)
    truthy(env.issecretvalue(env.UnitGUID("target")), "an enemy player in a match")
    falsy(env.issecretvalue(env.UnitGUID("party1")))
    falsy(env.issecretvalue(env.UnitGUID("player")))
    falsy(env.issecretvalue(env.UnitName("target")), "UnitName takes a plain UnitToken: players stay named")
end)

test("nameplates take the lowest free token, exist for every unit API, and fire added and removed", function()
    local h = Harness.New()
    local env = h.env
    local seen = Watch(h, "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED")
    local during
    local frame = env.CreateFrame("Frame")

    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:SetScript("OnEvent", function(_, _, token) during = env.UnitName(token) end)
    local first = h:AddNamePlate(EnemyPlayer({ name = "Foe1" }))
    local second = h:AddNamePlate(EnemyPlayer({ name = "Foe2" }))

    eq(first, "nameplate1")
    eq(second, "nameplate2")
    truthy(env.UnitExists("nameplate2"))
    eq(env.UnitName("nameplate2"), "Foe2")
    truthy(env.UnitCanAttack("player", "nameplate2"))
    h:RemoveNamePlate("nameplate1")
    eq(during, "Foe1", "the unit is readable while NAME_PLATE_UNIT_REMOVED dispatches")
    falsy(env.UnitExists("nameplate1"), "gone after")
    eq(h:AddNamePlate(EnemyPlayer({ name = "Foe3" })), "nameplate1", "the freed token is reused")

    eq(table.concat(seen, ","), "NAME_PLATE_UNIT_ADDED:nameplate1,NAME_PLATE_UNIT_ADDED:nameplate2,"
        .. "NAME_PLATE_UNIT_REMOVED:nameplate1,NAME_PLATE_UNIT_ADDED:nameplate1")

    throws(function() h:RemoveNamePlate("nameplate9") end, "isn't an active nameplate")
end)

test("C_NamePlate returns each active unit's plate frame, created once with NAME_PLATE_CREATED", function()
    local h = Harness.New()
    local env = h.env
    local created = 0
    local frame = env.CreateFrame("Frame")

    frame:RegisterEvent("NAME_PLATE_CREATED")
    frame:SetScript("OnEvent", function(_, _, plate) created = (created + 1); truthy(plate:IsObjectType("Frame")) end)
    local enemy = EnemyPlayer()
    local token = h:AddNamePlate(enemy)
    local plate = env.C_NamePlate.GetNamePlateForUnit(token)

    truthy(plate)
    eq(plate:GetObjectType(), "NamePlate")
    eq(plate:IsForbidden(), false, "forbidden plates aren't modeled")
    h:SetTarget(enemy)
    eq(env.C_NamePlate.GetNamePlateForUnit("target"), plate, "the target's plate")
    h:RemoveNamePlate(token)
    eq(env.C_NamePlate.GetNamePlateForUnit("target"), nil)
    h:AddNamePlate(enemy)
    eq(created, 1, "the plate frame is reused")
    eq(plate.UnitFrame:GetParent(), plate, "Blizzard's unit frame rides on the plate")
end)

test("a plate shows before NAME_PLATE_UNIT_ADDED and hides after _REMOVED, taking its children along", function()
    local h = Harness.New()
    local env = h.env
    local seen = {}
    local watcher = env.CreateFrame("Frame")

    watcher:RegisterEvent("NAME_PLATE_CREATED")
    watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    watcher:SetScript("OnEvent", function(_, event, arg)
        local plate = (((event == "NAME_PLATE_CREATED") and arg) or env.C_NamePlate.GetNamePlateForUnit(arg))

        seen[#seen + 1] = (event .. ":" .. tostring(plate:IsShown()))
    end)

    local token = h:AddNamePlate(EnemyPlayer())
    local plate = env.C_NamePlate.GetNamePlateForUnit(token)

    eq(table.concat(seen, ","), "NAME_PLATE_CREATED:false,NAME_PLATE_UNIT_ADDED:true")
    local badge = env.CreateFrame("Frame", nil, plate)
    local log = {}

    badge:SetScript("OnHide", function() log[#log + 1] = "hide" end)
    badge:SetScript("OnShow", function() log[#log + 1] = "show" end)
    truthy(badge:IsVisible())
    h:RemoveNamePlate(token)
    eq(seen[3], "NAME_PLATE_UNIT_REMOVED:true", "still shown while the event dispatches")
    falsy(plate:IsShown())
    falsy(badge:IsVisible(), "a child hides with its plate")
    truthy(badge:IsShown())
    eq(table.concat(log, ","), "hide")
    h:AddNamePlate(EnemyPlayer({ name = "Cara" }))
    truthy(plate:IsShown(), "the recycled plate shows again")
    truthy(badge:IsVisible())
    eq(table.concat(log, ","), "hide,show")
end)

test("mouseover: a unit fires UPDATE_MOUSEOVER_UNIT, clearing it fires nothing", function()
    local h = Harness.New()
    local seen = Watch(h, "UPDATE_MOUSEOVER_UNIT")

    h:SetMouseover(EnemyPlayer())
    eq(#seen, 1)
    eq(h.env.UnitName("mouseover"), "Bob")
    h:SetMouseover(nil)
    eq(#seen, 1, "no event when the mouseover clears")
    falsy(h.env.UnitExists("mouseover"))
end)

test("death: PLAYER_DEAD in lockdown, then combat ends; release and revive fire the wiki's events", function()
    local h = Harness.New()
    local env = h.env
    local seen = Watch(h, "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST")
    local lockedAtDeath
    local frame = env.CreateFrame("Frame")

    frame:RegisterEvent("PLAYER_DEAD")
    frame:SetScript("OnEvent", function() lockedAtDeath = env.InCombatLockdown() end)
    h:EnterCombat()
    h:Die()
    truthy(lockedAtDeath, "PLAYER_DEAD dispatches before combat ends")
    falsy(env.InCombatLockdown())
    truthy(env.UnitIsDead("player"))
    truthy(env.UnitIsDeadOrGhost("player"))
    h:ReleaseSpirit()
    falsy(env.UnitIsDead("player"), "a ghost")
    truthy(env.UnitIsDeadOrGhost("player"))
    h:Revive()
    falsy(env.UnitIsDeadOrGhost("player"))
    eq(env.UnitHealth("player"), 100)
    h:Die()
    -- resurrected before releasing
    h:Revive()
    eq(table.concat(seen, ","), "PLAYER_DEAD,PLAYER_REGEN_ENABLED,PLAYER_ALIVE,PLAYER_UNGHOST,PLAYER_DEAD,PLAYER_ALIVE")
    throws(function() h:ReleaseSpirit() end, "isn't dead")
end)

test("addon code can't set raid icons: SetRaidTarget is forbidden, as the client refused it", function()
    local h = Harness.New()

    -- the call under test
    h:ExpectBlocked(1)
    local seen = Watch(h, "ADDON_ACTION_FORBIDDEN", "RAID_TARGET_UPDATE")

    h:SetTarget(EnemyPlayer())
    h.env.SetRaidTarget("target", 8)
    eq(h.forbidden[1], "SetRaidTarget")
    eq(table.concat(seen, ","), "ADDON_ACTION_FORBIDDEN:AddOn:SetRaidTarget", "refused, and no icon changed")
end)

test("joining and leaving a group fires RAID_TARGET_UPDATE after GROUP_ROSTER_UPDATE", function()
    local h = Harness.New()
    local seen = Watch(h, "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE")

    h:JoinGroup("party", { "Mom" })
    h:LeaveGroup()
    eq(table.concat(seen, ","), "GROUP_ROSTER_UPDATE,RAID_TARGET_UPDATE,GROUP_ROSTER_UPDATE,RAID_TARGET_UPDATE")
end)

test("realm names: GetRealmName as is, GetNormalizedRealmName without spaces or hyphens", function()
    local h = Harness.New({ realm = "Blood-Moon Keep" })

    eq(h.env.GetRealmName(), "Blood-Moon Keep")
    eq(h.env.GetNormalizedRealmName(), "BloodMoonKeep")
end)

test("GetGuildInfo returns name, rank, rank index and another realm's name; nothing without a guild", function()
    local h = Harness.New({ guild = "The Lan Krew", guildRank = "Officer", guildRankIndex = 1, realm = "Home Realm" })
    local env = h.env
    local name, rank, index, realm = env.GetGuildInfo("player")

    eq(name, "The Lan Krew")
    eq(rank, "Officer")
    eq(index, 1)
    eq(realm, nil, "the player's own realm is nil")

    h:SetTarget(EnemyPlayer({ guild = "Knights of Light", guildRank = "Guild Master", guildRankIndex = 0,
        guildRealm = "Other Realm" }))

    name, rank, index, realm = env.GetGuildInfo("target")
    eq(name, "Knights of Light")
    eq(rank, "Guild Master")
    eq(index, 0)
    eq(realm, "Other Realm")
    falsy(env.issecretvalue(name))
    h:SetTarget(EnemyPlayer({ guild = "Home Guild", guildRealm = "HomeRealm" }))
    eq(select(4, env.GetGuildInfo("target")), nil, "the player's realm, however it's written")
    eq(select(2, env.GetGuildInfo("target")), "Member", "the default rank")
    h:SetTarget(EnemyPlayer())
    eq(select("#", env.GetGuildInfo("target")), 0, "no guild: nothing")
    eq(select("#", env.GetGuildInfo("focus")), 0, "no unit: nothing")
    throws(function() env.GetGuildInfo(Secret("target")) end, "secret argument #1 refused")
end)

test("IsInGuild follows the player's guild; GUILD addon messages need one", function()
    local h = Harness.New({ guild = "The Lan Krew" })
    local env = h.env

    truthy(env.IsInGuild())
    local results = env.Enum.SendAddonMessageResult

    eq(env.C_ChatInfo.SendAddonMessage("K", "hi", "GUILD"), results.Success)
    local alone = Harness.New()

    falsy(alone.env.IsInGuild())
    eq(alone.env.C_ChatInfo.SendAddonMessage("K", "hi", "GUILD"), results.NotInGuild)
end)

test("an NPC's name is plain with no restriction active and secret under one (seen in game)", function()
    local h = Harness.New()
    local env = h.env

    h:SetTarget({ name = "Aramis Hammerhand" })
    local name = env.UnitName("target")

    falsy(env.issecretvalue(name))
    eq(name, "Aramis Hammerhand")
    h:EnterCombat()
    falsy(env.issecretvalue(env.UnitName("target")), "open-world combat doesn't hide it (probed)")
    h:SetRestriction("Encounter", true)
    truthy(env.issecretvalue(env.UnitName("target")), "an encounter does")
end)

test("GetPlayerInfoByGUID knows the player units a test made, and nothing else", function()
    local h = Harness.New()
    local env = h.env
    local bob = { classFile = "ROGUE", isPlayer = true, name = "Bob", race = "Human", realm = "Other" }

    h:SetTarget(bob)
    local className, classFile, raceName, raceFile, sex, name, realm = env.GetPlayerInfoByGUID(env.UnitGUID("target"))

    eq(table.concat({ className, classFile, raceName, raceFile, sex, name, realm }, ","), "Rogue,ROGUE,Human,Human,2,Bob Doe,Other")
    eq(select(6, env.GetPlayerInfoByGUID(env.UnitGUID("player"))), "Tester Doe", "the name is \"First Last\"")
    eq(select(7, env.GetPlayerInfoByGUID(env.UnitGUID("player"))), "", "your own realm is empty")
    h:SetTarget({ canAttack = true, name = "Wolf" })
    eq(env.GetPlayerInfoByGUID(env.UnitGUID("target")), nil, "a creature")
    eq(env.GetPlayerInfoByGUID("Player-5000-DEADBEEF"), nil, "a GUID the client never saw")
end)

test("a relog starts with no target, focus, mouseover, nameplates or combo points; a reload drops the quest giver", function()
    local h = Harness.New()

    h:LoadAddon("ByteTerrace_DevTools")
    h:SetTarget({ canAttack = true, isPlayer = true, name = "Bob" })
    h:SetUnit("focus", { isPlayer = true, name = "Cara" })
    h:SetMouseover({ isPlayer = true, name = "Dan" })
    h:AddNamePlate({ canAttack = true, name = "Kobold" })
    h:SetComboPoints(3)
    h:OfferQuest({ title = "Wolves" }, "Eagan Peltskinner")
    h:Reload()
    falsy(h.env.UnitExists("questnpc"), "the dialog closed with the old UI, and its giver with it")
    truthy(h.env.UnitExists("target"), "a /reload keeps the world")
    h:Relog()

    for _, unit in ipairs({ "target", "focus", "mouseover", "nameplate1" }) do
        falsy(h.env.UnitExists(unit), unit .. " after a fresh login")
    end

    eq(h.env.GetComboPoints("player", "target"), 0)
end)
