-- The harness's fidelity rules for Blizzard's damage meter and death recaps (tests/harness/meter.lua): sessions per
-- combat, per-field secrecy in combat, and recaps tied to the deaths in a session.

local Kit = use("harness")

local Watch = Kit.Watch

local MeterEvents = { "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }

-- "Bob hit me for 3000 and killed me; Mom healed 5000."
local function BobKillsMe(h, endCombat)
    return h:MeterFight({
        duration = 12, endCombat = endCombat, name = "Bob",
        sources = {
            { death = { maxHealth = 2800 },
                spells = { DamageTaken = {
                    { details = { unitClassFilename = "ROGUE", unitName = "Bob" }, isDeadly = true,
                        overkillAmount = 200, spellID = 1752, totalAmount = 3000 },
                } },
                unit = "player" },
            { amounts = { DamageDone = 3000 }, classFilename = "ROGUE", factionGroup = "Horde", name = "Bob",
                sourceDisplayType = h.env.Enum.DamageMeterSourceDisplayType.Enemy },
            { amounts = { HealingDone = 5000 }, classFilename = "PRIEST", name = "Mom" },
        },
    })
end

test("a combat is a session: its events, its sources sorted by amount, and its rates", function()
    local h = Harness.New({ classFile = "WARRIOR", name = "Tester" })
    local env = h.env
    local types, sessionTypes = env.Enum.DamageMeterType, env.Enum.DamageMeterSessionType
    local seen = Watch(h, unpack(MeterEvents))

    local fight = h:MeterFight({ duration = 10, sources = {
        { amounts = { DamageDone = 1000 }, unit = "player" },
        { amounts = { [types.DamageDone] = 2000 }, classFilename = "MAGE", name = "Cara" },
    } })

    eq(fight.sessionID, 1)

    local pair = ("DAMAGE_METER_COMBAT_SESSION_UPDATED:0:0,DAMAGE_METER_COMBAT_SESSION_UPDATED:0:1,"
        .. "DAMAGE_METER_COMBAT_SESSION_UPDATED:1:0,DAMAGE_METER_COMBAT_SESSION_UPDATED:1:1")

    eq(table.concat(seen, ","), "DAMAGE_METER_CURRENT_SESSION_UPDATED," .. pair .. "," .. pair,
        "each source's change fires Overall (0) then the session, for DamageDone and Dps")

    falsy(h.inCombat, "the fight ends combat")
    local session = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone)

    falsy(env.issecretvalue(session.totalAmount), "plain out of combat")
    eq(#session.combatSources, 2)
    local top, me = session.combatSources[1], session.combatSources[2]

    eq(top.name, "Cara")
    eq(top.totalAmount, 2000)
    eq(top.amountPerSecond, 200)
    eq(top.classFilename, "MAGE")
    falsy(top.isLocalPlayer)
    eq(top.deathRecapID, 0)
    eq(me.name, "Tester")
    eq(me.classFilename, "WARRIOR")
    truthy(me.isLocalPlayer)
    eq(me.sourceGUID, env.UnitGUID("player"))
    eq(session.maxAmount, 2000)
    eq(session.totalAmount, 3000)
    eq(session.durationSeconds, 10)
    local dps = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.Dps)

    eq(dps.combatSources[1].amountPerSecond, 200, "Dps reads DamageDone's entries")
    local list = env.C_DamageMeter.GetAvailableCombatSessions()

    eq(#list, 1)
    eq(list[1].sessionID, 1)
    eq(list[1].name, "Combat 1", "sessions are always named (probed); the harness's default")
    eq(list[1].durationSeconds, 10)
    eq(#env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.HealingDone).combatSources, 0)
end)

test("Bob hit me for 3000 and killed me; Mom healed 5000: deaths, spells and the recap", function()
    local h = Harness.New({ name = "Tester" })
    local env = h.env
    local types, sessionTypes = env.Enum.DamageMeterType, env.Enum.DamageMeterSessionType
    local fight = BobKillsMe(h)

    truthy(h.player.dead, "the local player's death kills the player")
    falsy(h.inCombat)
    local recapID = fight.recaps.Tester

    truthy(recapID and (recapID ~= 0))
    local deaths = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.Deaths).combatSources

    eq(#deaths, 1)
    eq(deaths[1].name, "Tester")
    eq(deaths[1].deathRecapID, recapID)
    eq(deaths[1].deathTimeSeconds, 12, "seconds into the session")
    eq(deaths[1].totalAmount, 0)

    eq(env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Overall, types.Deaths).combatSources[1].deathTimeSeconds, -1,
        "no timestamps for the overall session")

    local taken = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageTaken)

    eq(taken.combatSources[1].totalAmount, 3000, "the spells sum to the amount")
    eq(taken.combatSources[1].deathRecapID, 0, "only Deaths entries carry the recap")
    local mine = env.C_DamageMeter.GetCombatSessionSourceFromType(sessionTypes.Current, types.DamageTaken, env.UnitGUID("player"))

    eq(mine.totalAmount, 3000)
    eq(#mine.combatSpells, 1)
    local spell = mine.combatSpells[1]

    eq(spell.spellID, 1752)
    eq(spell.amountPerSecond, 250)
    truthy(spell.isDeadly)
    eq(spell.overkillAmount, 200)
    eq(spell.combatSpellDetails.unitName, "Bob")
    eq(spell.combatSpellDetails.unitClassFilename, "ROGUE")
    eq(spell.combatSpellDetails.amount, 3000)
    local healing = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.HealingDone).combatSources

    eq(healing[1].name, "Mom")
    eq(healing[1].totalAmount, 5000)
    local bob = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone).combatSources[1]

    eq(bob.sourceDisplayType, env.Enum.DamageMeterSourceDisplayType.Enemy)
    eq(bob.factionGroup, "Horde")
    eq(env.C_DamageMeter.GetAvailableCombatSessions()[1].name, "Bob")
    truthy(env.C_DeathRecap.HasRecapEvents(recapID))
    eq(env.C_DeathRecap.GetRecapMaxHealth(recapID), 2800)
    local events = env.C_DeathRecap.GetRecapEvents(recapID)

    eq(#events, 1)
    eq(events[1].event, "SPELL_DAMAGE")
    eq(events[1].sourceName, "Bob")
    eq(events[1].amount, 3000)
    eq(events[1].overkill, 200)
    eq(events[1].spellId, 1752)
    eq(events[1].timestamp, Harness.SERVER_EPOCH + 12)
    falsy(env.C_DeathRecap.HasRecapEvents(99))
    eq(#env.C_DeathRecap.GetRecapEvents(99), 0)
    eq(env.C_DeathRecap.GetRecapMaxHealth(99), 0)
end)

test("scripted recap events come back newest first, with their fields", function()
    local h = Harness.New()
    local env = h.env

    local fight = h:MeterFight({ duration = 5, sources = {
        { classFilename = "PRIEST",
            death = { events = {
                    { amount = 400, currentHP = 500, event = "SWING_DAMAGE", sourceName = "Bob", time = 2 },
                    { amount = 700, currentHP = 0, event = "SPELL_DAMAGE", overkill = 200, sourceName = "Bob",
                        spellId = 8676, spellName = "Ambush" },
                },
                maxHealth = 900, time = 4 },
            name = "Mom" },
    } })

    falsy(h.player.dead, "someone else's death doesn't kill the player")
    local events = env.C_DeathRecap.GetRecapEvents(fight.recaps.Mom)

    eq(events[1].event, "SPELL_DAMAGE", "the killing blow first")
    eq(events[1].spellName, "Ambush")
    eq(events[1].timestamp, Harness.SERVER_EPOCH + 4)
    eq(events[2].event, "SWING_DAMAGE")
    eq(events[2].currentHP, 500)
    eq(events[2].timestamp, Harness.SERVER_EPOCH + 2)
    eq(events[2].time, nil, "only DeathRecapEventInfo's fields")
    events[1].amount = 1
    eq(env.C_DeathRecap.GetRecapEvents(fight.recaps.Mom)[1].amount, 700, "each call returns fresh tables")
end)

test("in combat every field is secret except the NeverSecret ones; the tables stay plain", function()
    local h = Harness.New({ name = "Tester" })
    local env = h.env
    local types, sessionTypes = env.Enum.DamageMeterType, env.Enum.DamageMeterSessionType

    BobKillsMe(h, false)
    truthy(h.inCombat)
    local session = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.Deaths)
    local death = session.combatSources[1]

    falsy(env.issecretvalue(death.isLocalPlayer))
    falsy(env.issecretvalue(death.deathRecapID))
    falsy(env.issecretvalue(death.classFilename))
    falsy(env.issecretvalue(death.specIconID))
    falsy(env.issecretvalue(death.classification))
    truthy(env.issecretvalue(death.name), "ConditionalSecret is secret in combat")
    truthy(env.issecretvalue(death.sourceGUID))
    truthy(env.issecretvalue(death.deathTimeSeconds))
    truthy(env.issecretvalue(session.totalAmount))
    local healing = env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.HealingDone)

    truthy(env.issecretvalue(healing.combatSources[1].totalAmount))
    truthy(env.issecretvalue(healing.combatSources[1].amountPerSecond))
    truthy(env.issecretvalue(healing.durationSeconds))
    throws(function() return (healing.combatSources[1].totalAmount + 1) end, "compute with")
    local mine = env.C_DamageMeter.GetCombatSessionSourceFromType(sessionTypes.Current, types.DamageTaken, h.player.guid)
    local spell = mine.combatSpells[1]

    truthy(env.issecretvalue(spell.spellID))
    truthy(env.issecretvalue(spell.combatSpellDetails.unitName))
    falsy(env.issecretvalue(spell.combatSpellDetails.unitClassFilename))
    truthy(env.issecretvalue(mine.totalAmount))
    local list = env.C_DamageMeter.GetAvailableCombatSessions()

    falsy(env.issecretvalue(list[1].sessionID), "no secret flags")
    falsy(env.issecretvalue(env.C_DeathRecap.GetRecapMaxHealth(death.deathRecapID)))

    throws(function() env.C_DamageMeter.GetCombatSessionSourceFromType(sessionTypes.Current, types.DamageDone, death.sourceGUID) end,
        "secret argument #3 refused", "a secret GUID can't go back to the API")

    h:LeaveCombat()
    falsy(env.issecretvalue(env.C_DamageMeter.GetCombatSessionFromType(sessionTypes.Current, types.HealingDone).totalAmount))
end)

test("Current is the latest fight, Expired is empty after ordinary fights (probed), Overall merges them all", function()
    local h = Harness.New({ name = "Tester" })
    local env = h.env
    local types, sessionTypes = env.Enum.DamageMeterType, env.Enum.DamageMeterSessionType
    local damageMeter = env.C_DamageMeter

    eq(#damageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone).combatSources, 0, "no session yet: an empty one")
    eq(damageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone).totalAmount, 0)
    eq(damageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone).durationSeconds, nil)
    eq(damageMeter.GetCombatSessionFromType(sessionTypes.Expired, types.DamageDone).durationSeconds, nil)

    h:MeterFight({ duration = 10, sources = {
        { amounts = { DamageDone = 1000 }, unit = "player" }, { amounts = { HealingDone = 50 }, name = "Mom" },
    } })

    h:Advance(30)

    h:MeterFight({ duration = 5, endCombat = false, sources = {
        { amounts = { DamageDone = 500 }, unit = "player" }, { amounts = { HealingDone = 70 }, name = "Mom" },
    } })

    h:LeaveCombat()
    h:EnterCombat()
    h:Advance(2)
    eq(damageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone).durationSeconds, 2, "the fight in progress")
    eq(#damageMeter.GetCombatSessionFromType(sessionTypes.Current, types.DamageDone).combatSources, 0)
    eq(#damageMeter.GetCombatSessionFromType(sessionTypes.Expired, types.DamageDone).combatSources, 0, "Expired is empty")
    local overall = damageMeter.GetCombatSessionFromType(sessionTypes.Overall, types.DamageDone)

    eq(#overall.combatSources, 1, "one source across sessions")
    eq(overall.combatSources[1].totalAmount, 1500)
    eq(overall.durationSeconds, 17)
    local healing = damageMeter.GetCombatSessionFromType(sessionTypes.Overall, types.HealingDone).combatSources

    eq(#healing, 1, "a named source keeps its GUID across fights")
    eq(healing[1].totalAmount, 120)
    h:LeaveCombat()
    eq(#damageMeter.GetAvailableCombatSessions(), 3)
    throws(function() damageMeter.GetCombatSessionFromType(sessionTypes.Current, 99) end, "unknown DamageMeterType")
end)

test("the meter reports whether it's available; a relog clears its sessions, a reload keeps them", function()
    local h = Harness.New()
    local env = h.env
    local ok, reason = env.C_DamageMeter.IsDamageMeterAvailable()

    eq(ok, true)
    eq(reason, "")
    h:MeterFight({ duration = 3, sources = { { amounts = { DamageDone = 10 }, unit = "player" } } })
    h:Reload()
    eq(#h.env.C_DamageMeter.GetAvailableCombatSessions(), 1, "a reload keeps the client's sessions")
    h:Relog(60)
    eq(#h.env.C_DamageMeter.GetAvailableCombatSessions(), 0, "a relog clears them")
    h:SetMeterAvailable(false, "reason")
    local no, why = h.env.C_DamageMeter.IsDamageMeterAvailable()

    eq(no, false)
    eq(why, "reason")
    throws(function() h:MeterAdd({ amounts = { DamageDone = 1 }, unit = "player" }) end, "enter combat first")
    h:EnterCombat()
    throws(function() h:MeterAdd({ amounts = { Dps = 1 }, unit = "player" }) end, "Dps/Hps read them")
end)
