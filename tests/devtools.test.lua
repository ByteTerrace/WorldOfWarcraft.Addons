-- ByteTerrace_DevTools' probe commands: /btdev probe records the probes whose needs are met into
-- ByteTerraceDevToolsDB.probes and lists what the rest need; /btdev probe list shows what's left,
-- in play-session order. DevTools also collects UNIT_COMBAT payloads for unitCombat.seen.

local function Printed(h, from)
    return table.concat(h.printed, "\n", from or 1)
end

local function Load(saved)
    local h = Harness.New({ saved = saved })
    h:LoadAddon("ByteTerrace_DevTools")
    return h
end

local function Records(h)
    return h.env.ByteTerraceDevToolsDB.probes
end

local function DieToDamage(h, spells)
    h:MeterFight({ duration = 12, sources = {
        { unit = "player", spells = { DamageTaken = spells }, death = { maxHealth = 55 } },
    } })
    h:Slash("/btdev probe")
    return Records(h)["deathRecap.events"].result
end

local function Hit(spellID, name)
    return {
        spellID = spellID, name = name, totalAmount = 60, overkillAmount = 5, isDeadly = true,
        details = { unitName = "Kobold Vermin", classification = "normal", isMob = true },
    }
end

test("death recap common shapes are stable for melee, spell and mixed deaths in either order", function()
    local baseline
    for _, spells in ipairs({
        { Hit(6603) }, { Hit(11976, "Strike") },
        { Hit(11976, "Strike"), Hit(6603) }, { Hit(6603), Hit(11976, "Strike") },
    }) do
        local h = Load()
        local result = DieToDamage(h, spells)
        truthy(result.commonFields, "the result describes common fields, never the event union")
        eq(result.fields, nil)
        eq(result.killingBlow.amount, "number")
        eq(result.killingBlow.sourceName, "string")
        eq(result.killingBlow.spellId, nil, "spell fields have their own event-kind probe")
        if baseline then eq(#h.ns.Probes.Diff(baseline, result), 0) end
        baseline = result
    end
end)

test("death recap spell-field probes require the event kind and keep false booleans", function()
    local h = Load()
    DieToDamage(h, { Hit(6603) })
    eq(Records(h)["deathRecap.spellFields"], nil, "no spell event means no spell evidence")
    local swing = Records(h)["deathRecap.swingFields"].result
    for _, field in ipairs({ "spellId", "spellName", "spellSchool", "avoidable", "deadly" }) do
        eq(swing[field], "nil", field)
    end
    local spellHarness = Load()
    DieToDamage(spellHarness, { Hit(11976, "Strike") })
    eq(Records(spellHarness)["deathRecap.swingFields"], nil, "no swing event means no swing evidence")
    local spell = Records(spellHarness)["deathRecap.spellFields"].result
    eq(spell.spellId, "number")
    eq(spell.spellName, "string")
    eq(spell.spellSchool, "number")
    eq(spell.avoidable, "boolean")
    eq(spell.deadly, "boolean")
    local events = spellHarness.env.C_DeathRecap.GetRecapEvents()
    eq(events[1].avoidable, false)
    eq(events[1].deadly, true)
    local mixed = Load()
    DieToDamage(mixed, { Hit(11976, "Strike"), Hit(6603) })
    eq(#mixed.ns.Probes.Diff(Records(mixed)["deathRecap.spellFields"].result, spell), 0)
    eq(#mixed.ns.Probes.Diff(Records(mixed)["deathRecap.swingFields"].result, swing), 0)
end)

test("scripted swing recaps carry no spell fields even when the damage fixture supplies them", function()
    local h = Load()
    h:MeterFight({ duration = 1, sources = { { unit = "player", death = { events = {
        { event = "SWING_DAMAGE", amount = 60, spellId = 6603, spellName = "Attack", spellSchool = 1,
            avoidable = false, deadly = true },
    } } } } })
    local event = h.env.C_DeathRecap.GetRecapEvents()[1]
    eq(event.event, "SWING_DAMAGE")
    eq(event.amount, 60)
    for _, field in ipairs({ "spellId", "spellName", "spellSchool", "avoidable", "deadly" }) do
        eq(event[field], nil, field)
    end
    h:Slash("/btdev probe")
    eq(Records(h)["deathRecap.swingFields"].result.spellId, "nil")
end)

test("common recap fields exclude optional mitigation and require presence in every event", function()
    local h = Load()
    local baseline = DieToDamage(h, { Hit(11976, "Strike"), Hit(6603) })
    local events = h.env.C_DeathRecap.GetRecapEvents()
    events[1].absorbed, events[1].blocked, events[2].resisted = 1, 2, 3
    local function Record()
        h:MeterFight({ duration = 1, sources = { { unit = "player", death = {
            maxHealth = 55, events = { events[2], events[1] },
        } } } })
        h:Slash("/btdev probe")
        return Records(h)["deathRecap.events"].result
    end
    eq(#h.ns.Probes.Diff(baseline, Record()), 0, "optional mitigation doesn't alter common shapes")
    events[2].amount = nil
    local result = Record()
    falsy(("," .. result.commonFields .. ","):find(",amount,", 1, true), "one event lacks amount")
    eq(result.killingBlow.amount, "number", "the killing blow retains its own shape")
end)

test("spell-field probes reject inconsistent events and preserve secret markers", function()
    local h = Load()
    h:MeterFight({ duration = 1, sources = { { unit = "player", death = { events = {
        { event = "SPELL_DAMAGE", spellId = 11976, spellName = "Strike", spellSchool = 1 },
        { event = "SPELL_DAMAGE", spellId = 11976, spellSchool = 1 },
    } } } } })
    h:Slash("/btdev probe")
    eq(Records(h)["deathRecap.spellFields"], nil, "inconsistent samples don't become calibrated evidence")
    truthy(Printed(h):find("SPELL_DAMAGE.spellName varies between recap events", 1, true), Printed(h))
    local secretHarness = Load()
    secretHarness:MeterFight({ duration = 1, sources = { { unit = "player", death = { events = {
        { event = "SPELL_DAMAGE", spellId = Secret(11976), amount = Secret(60) },
    } } } } })
    secretHarness:Slash("/btdev probe")
    local result = Records(secretHarness)["deathRecap.spellFields"].result
    eq(result.spellId.secret, true)
    eq(result.spellId.type, "number")
    eq(Records(secretHarness)["deathRecap.events"].result.killingBlow.amount.secret, true)
end)

test("/btdev probe records the probes whose needs are met, with build and context", function()
    local h = Load()
    h:Slash("/btdev probe")
    local record = Records(h)["chatTypeInfo.raidWarning"]
    eq(record.build, Harness.BUILD)
    eq(record.context.combat, false)
    eq(record.context.restrictions, "none")
    eq(record.result.g, 72)
    eq(record.result.hasMetatable, true)
    truthy(Records(h)["chat.lockdownIdle"], "an idle probe runs out of combat")
    eq(Records(h)["unitIdentity.npcTarget"], nil, "no target: skipped")
    eq(Records(h)["quest.offer"], nil, "no quest dialog: skipped")
    local text = Printed(h)
    truthy(text:find("recorded %d+ probes %(%d+ new, 0 changed%)"), text)
    truthy(text:find("target a living NPC (a quest giver or a mob): unitIdentity.npcTarget, unitHealth.npcTarget", 1, true), text)
    truthy(text:find("/reload to write them", 1, true), text)
end)

test("a probe that fails isn't recorded and its error is printed", function()
    local h = Load()
    h:Slash("/btdev probe")
    eq(Records(h)["fonts.scholar"], nil, "the harness has no font objects, so the probe errors")
    truthy(Printed(h):find("probe fonts.scholar failed:", 1, true), Printed(h))
end)

test("running again merges: new probes are added, unchanged ones stay, changes are printed", function()
    local h = Load()
    h:Slash("/btdev probe")
    local before = 0
    for _ in pairs(Records(h)) do before = before + 1 end
    Records(h)["chatTypeInfo.raidWarning"].result.g = 1
    Records(h)["chatTypeInfo.raidWarning"].result.r = { secret = true, type = "number" }
    h:SetTarget({ name = "Kobold Vermin", classFile = "WARRIOR" })
    local from = #h.printed + 1
    h:Slash("/btdev probe")
    local text = Printed(h, from)
    local after = 0
    for _ in pairs(Records(h)) do after = after + 1 end
    truthy(after > before, "the target's probes are added")
    truthy(text:find(("(%d new, 1 changed)"):format(after - before), 1, true), "the summary counts what was added: " .. text)
    truthy(text:find("probe chatTypeInfo.raidWarning changed at result.g: was 1, now 72", 1, true), text)
    truthy(text:find('probe chatTypeInfo.raidWarning changed at result.r: was { secret = true, type = "number" }, now 255',
        1, true), "a table prints with its keys sorted: " .. text)
    truthy(Records(h)["unitIdentity.npcTarget"], "now recorded")
    truthy(Records(h)["unitClassification.npcTarget"], "now recorded")
    truthy(Records(h)["power.npcTarget"], "now recorded")
    eq(Records(h)["chatTypeInfo.raidWarning"].result.g, 72)
end)

test("probes survive a reload, and a dump already saved is kept", function()
    local h = Load({ ByteTerraceDevToolsDB = { build = { version = "1.60.1", build = "70009" }, globals = { UnitName = { type = "function" } } } })
    h:Slash("/btdev probe")
    h:Reload()
    local db = h.env.ByteTerraceDevToolsDB
    eq(db.globals.UnitName.type, "function", "the dump is untouched")
    eq(db.probes["chatTypeInfo.raidWarning"].result.r, 255)
end)

test("in combat, records carry the combat context", function()
    local h = Load()
    h:SetTarget({ name = "Kobold Vermin", classFile = "WARRIOR" })
    h:EnterCombat()
    h:Slash("/btdev probe")
    local record = Records(h)["unitHealth.npcTargetInCombat"]
    eq(record.context.combat, true)
    eq(record.context.restrictions, "Combat")
    eq(record.result.health.secret, true)
    eq(Records(h)["unitHealth.npcTarget"], nil, "the idle probe waits for combat to end")
end)

test("/btdev probe list shows the probes still without a result, grouped by what they need", function()
    local h = Load()
    h:Slash("/btdev probe list")
    local text = Printed(h)
    local count = #h.ns.Probes.List
    truthy(text:find(("%d of %d probes have no result for %s yet"):format(count, count, Harness.BUILD), 1, true), text)
    truthy(text:find("in a guild: guild.player", 1, true), text)
    h:Slash("/btdev probe")
    local from = #h.printed + 1
    h:Slash("/btdev probe list")
    text = Printed(h, from)
    falsy(text:find("chatTypeInfo.raidWarning", 1, true), "recorded probes aren't listed")
    truthy(text:find("nothing: fonts.scholar", 1, true), text)
end)

test("/btdev probe list prints its groups under the play-session steps, in order", function()
    local h = Load()
    h:Slash("/btdev probe list")
    local text = Printed(h)
    local steps = h.ns.Probes.Steps
    local last = 0
    for i, step in ipairs(steps) do
        local at = text:find(("\n  %d. %s\n"):format(i, step), 1, true)
        truthy(at, "step " .. i .. " heads its group: " .. text)
        truthy(at > last, "steps print in order")
        last = at
    end
    local anywhere, questGiver = text:find("nothing: ", 1, true), text:find("a quest offer open", 1, true)
    truthy(anywhere < questGiver, "a probe that runs anywhere comes before one that needs a quest giver")
    truthy(text:find("dead or a ghost after letting a mob kill you", 1, true) > text:find("  5. ", 1, true), text)
end)

test("UNIT_COMBAT on the player and the target is kept as shapes, from load, for unitCombat.seen", function()
    local h = Load()
    local registered = {}
    for _, frame in ipairs(h.frames) do
        for event, units in pairs(Harness.State(frame).events) do
            local names = {}
            for unit in pairs(type(units) == "table" and units or {}) do names[#names + 1] = unit end
            table.sort(names)
            registered[#registered + 1] = event .. "(" .. table.concat(names, ",") .. ")"
        end
    end
    table.sort(registered)
    eq(table.concat(registered, " "), "CHAT_MSG_ADDON() CHAT_MSG_CHANNEL() CHAT_MSG_GUILD() CHAT_MSG_PARTY() "
        .. "CHAT_MSG_RAID() CHAT_MSG_SAY() CHAT_MSG_WHISPER() CHAT_MSG_YELL() DAMAGE_METER_COMBAT_SESSION_UPDATED() PARTY_KILL() "
        .. "PLAYER_DEAD() PLAYER_TARGET_DIED() UNIT_COMBAT(player,target) UNIT_DIED()",
        "the chat senders, UNIT_COMBAT for two units, the kill events, and deaths with the meter's updates")
    h:Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 42, 1)
    h:Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
    h:Slash("/btdev probe")
    eq(Records(h)["unitCombat.seen"], nil, "waits until the player has been hit too")
    h:Fire("UNIT_COMBAT", "player", "WOUND", "", 7, 1)
    h:Fire("UNIT_COMBAT", "party1", "PARRY", "", 0, 1)
    h:Slash("/btdev probe")
    local result = Records(h)["unitCombat.seen"].result
    eq(result.actions, "DODGE,WOUND", "party1's payload never arrives")
    eq(result.flagTexts, "CRITICAL")
    eq(result.target.WOUND.flagText, "text")
    eq(result.target.WOUND.amount, "number")
    eq(result.target.DODGE.flagText, "empty")
    eq(result.player.WOUND.amount, "number")
    eq(result.player.WOUND.schoolMask, "number")
    eq(result.amountInCombat, nil, "no hit on you in combat yet")
    h:EnterCombat()
    h:Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
    h:Slash("/btdev probe")
    eq(Records(h)["unitCombat.seen"].result.amountInCombat, nil, "a hit on the target isn't one on you")
    h:Fire("UNIT_COMBAT", "player", "WOUND", "", 12, 1)
    h:Slash("/btdev probe")
    eq(Records(h)["unitCombat.seen"].result.amountInCombat, "number", "the amount of a hit on you in combat")
end)

test("a record from another build counts as missing", function()
    local h = Load({ ByteTerraceDevToolsDB = { probes = { classColors = { build = "1.60.0 (69000)", context = {}, result = {} } } } })
    h:Slash("/btdev probe list")
    truthy(Printed(h):find("nothing: chatTypeInfo.raidWarning, classColors", 1, true), Printed(h))
end)

test("a record from another version of its probe counts as missing, and a new run replaces it", function()
    local old = { build = Harness.BUILD, context = { combat = false, restrictions = "none" }, result = { fields = "amount" } }
    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["deathRecap.events"] = old } } })
    h:Slash("/btdev probe list")
    truthy(Printed(h):find("deathRecap.events", 1, true), Printed(h))
    local from = #h.printed + 1
    DieToDamage(h, { Hit(133, "Fireball") })
    local text = Printed(h, from)
    falsy(text:find("probe deathRecap.events changed", 1, true), "an old version's record isn't compared: " .. text)
    local record = Records(h)["deathRecap.events"]
    eq(record.version, 2)
    eq(record.result.fields, nil, "version 2 records common fields")
    truthy(h.ns.Probes.IsCurrent(h.ns.Probes.ByName["deathRecap.events"], record))
end)

test("/btdev alone prints the commands", function()
    local h = Load()
    h:Slash("/btdev")
    local text = Printed(h)
    truthy(text:find("/btdev probe list", 1, true) and text:find("/btdev dump", 1, true), text)
end)

test("kill events are kept for kills.seen: whose blow, and what died", function()
    local h = Load()
    local pet = { name = "Wolf", playerControlled = true }
    h:SetUnit("pet", pet)
    h:Fire("PARTY_KILL", h:GUID(pet), h:GUID({ name = "Kobold" }))
    h:Fire("UNIT_DIED", h:GUID({ name = "Kobold" }))
    h:Fire("PLAYER_TARGET_DIED")
    local kills = h.ns.Probes.ByName["kills.seen"].run()
    eq(kills.partyKill.attacker, "pet")
    eq(kills.partyKill.target, "Creature")
    eq(kills.unitDied.unit, "Creature")
    truthy(kills.targetDied)
end)

test("chat senders are kept as name shapes, never names", function()
    local h = Harness.New()
    local ns = h:LoadAddon("ByteTerrace_DevTools")
    h:Fire("CHAT_MSG_SAY", "hello", "Dh Taketwo-Realm")
    h:Fire("CHAT_MSG_CHANNEL", "hi", "Bob")
    h:Fire("CHAT_MSG_ADDON", "TLK", "HELLO", "PARTY", "Cara Doe-Realm")
    local senders = ns.Probes.ByName["names.chatSenders"].run()
    eq(senders.CHAT_MSG_SAY, "Aa Aa-Aa")
    eq(senders.CHAT_MSG_CHANNEL, "Aa")
    eq(senders.CHAT_MSG_ADDON, "Aa Aa-Aa", "an addon message's sender is its fourth argument")
end)

test("kill events accumulate: a player kill after a mob kill keeps both kinds", function()
    local h = Load()
    local me = h:GUID(h.player)
    h:Fire("PARTY_KILL", me, h:GUID({ name = "Kobold" }))
    h:Fire("PARTY_KILL", me, h:GUID({ name = "Cara", isPlayer = true }))
    local kills = h.ns.Probes.ByName["kills.seen"].run()
    eq(kills.partyKill.attacker, "you")
    eq(kills.partyKill.target, "Creature,Player")
end)

test("an accumulating probe's record grows across sessions and reloads", function()
    local record = { build = Harness.BUILD, context = { combat = false, restrictions = "none" },
        result = { partyKill = { attacker = "pet", attackerKind = "Pet", target = "Creature" }, targetDied = true } }
    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["kills.seen"] = record } } })
    h:Fire("PARTY_KILL", h:GUID(h.player), h:GUID({ name = "Cara", isPlayer = true }))
    h:Fire("PLAYER_TARGET_DIED")
    h:Fire("CHAT_MSG_SAY", "hi", "Bob")
    h:Slash("/btdev probe")
    local result = Records(h)["kills.seen"].result
    eq(result.partyKill.attacker, "pet,you")
    eq(result.partyKill.target, "Creature,Player")
    eq(result.targetDied, true, "kept from the earlier session")
    h:Reload()
    h:Fire("CHAT_MSG_CHANNEL", "hi", "Dh Taketwo-Realm")
    h:Slash("/btdev probe")
    local senders = Records(h)["names.chatSenders"].result
    eq(senders.CHAT_MSG_SAY, "Aa", "a reload keeps what the last session heard")
    eq(senders.CHAT_MSG_CHANNEL, "Aa Aa-Aa")
end)

test("a fight in which you dealt no damage doesn't count as after a fight", function()
    local h = Load()
    local hit = { spellID = 6603, totalAmount = 24, details = { unitName = "Kobold Vermin", classification = "normal", isMob = true } }
    h:MeterFight({ duration = 6, sources = { { unit = "player", amounts = { DamageDone = 300 } } } })
    h:MeterFight({ duration = 4, sources = { { unit = "player", spells = { DamageTaken = { hit } } } } })
    h:Slash("/btdev probe")
    eq(Records(h)["damageMeter.enemySource"], nil, "no enemy you hit, so no enemy source to describe")
    eq(Records(h)["damageMeter.afterFight"], nil)
    eq(Records(h)["damageMeter.typesIdle"], nil, "the latest fight isn't one you fought")
end)

test("a secret never erases what was seen before it, nor what's seen after", function()
    local h = Load()
    local Probes = h.ns.Probes
    local marker = Probes.Marker(Secret("x"))
    eq(Probes.Merge("Aa", marker), "Aa,secret")
    eq(Probes.Merge(marker, "Aa"), "Aa,secret")
    eq(Probes.Merge("Aa,Aa Aa", "Aa"), "Aa,Aa Aa")
    h:Fire("CHAT_MSG_SAY", "hi", "Bob")
    h:Fire("CHAT_MSG_SAY", "hi", Secret("Cara Doe"))
    h:Fire("CHAT_MSG_SAY", "hi", "Dh Taketwo")
    eq(Probes.ByName["names.chatSenders"].run().CHAT_MSG_SAY, "Aa,Aa Aa,secret")
end)

test("a saved accumulating record keeps its items when a session saw a secret", function()
    local record = { build = Harness.BUILD, context = { combat = false, restrictions = "none" },
        result = { CHAT_MSG_SAY = "Aa,Aa Aa" } }
    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["names.chatSenders"] = record } } })
    h:Fire("CHAT_MSG_SAY", "hi", Secret("Cara Doe"))
    h:Slash("/btdev probe")
    eq(Records(h)["names.chatSenders"].result.CHAT_MSG_SAY, "Aa,Aa Aa,secret")
end)

test("a name's shape keeps no digits: realms like Area 52 compare with any other", function()
    local h = Load()
    eq(h.ns.Probes.NameShape("Dh Taketwo-Area 52"), "Aa Aa-Aa 0")
end)

test("the latest recap matches the meter's, a differing field doesn't, and one that met a secret isn't a match", function()
    local h = Load()
    DieToDamage(h, { Hit(133, "Fireball") })
    local latest = h.ns.Probes.ByName["deathRecap.latest"]
    eq(latest.run().sameAsMeter, true)
    local recap = h.env.C_DeathRecap
    local getEvents = recap.GetRecapEvents
    local Alter
    rawset(recap, "GetRecapEvents", function(id)
        local events = getEvents(id)
        if id == nil and events[1] then
            Alter(events[1])
        end
        return events
    end)
    Alter = function(blow) blow.timestamp = Secret(blow.timestamp) end
    eq(latest.run().sameAsMeter, "secret")
    Alter = function(blow) blow.timestamp, blow.amount = Secret(blow.timestamp), blow.amount + 1 end
    eq(latest.run().sameAsMeter, false, "a plain field that differs decides, whatever else was secret")
end)

test("another player's kill doesn't count as a mob you killed yourself", function()
    local h = Load()
    local Probes = h.ns.Probes
    h:Fire("PARTY_KILL", h:GUID({ name = "Mom", isPlayer = true }), h:GUID({ name = "Kobold" }))
    h:Fire("PLAYER_TARGET_DIED")
    falsy((Probes.Check(Probes.ByName["kills.seen"])), "someone else's blow")
    h:Fire("PARTY_KILL", h:GUID(h.player), h:GUID({ name = "Kobold" }))
    truthy((Probes.Check(Probes.ByName["kills.seen"])), "yours")
end)

test("/btdev probe lists only what's still to do, and a new context alone isn't news", function()
    local h = Load()
    h:Slash("/btdev probe")
    h:EnterCombat()
    local from = #h.printed + 1
    h:Slash("/btdev probe")
    local text = Printed(h, from)
    falsy(text:find("changed at context", 1, true), "combat context alone: " .. text)
    falsy(text:find("classColors", 1, true), "an answered probe isn't listed again: " .. text)
end)

test("the meter's updates in the seconds after your death are kept by type, for damageMeter.afterDeath", function()
    local h = Load()
    local types = h.env.Enum.DamageMeterType
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.DamageDone, 1) -- no death yet: not kept
    h:Fire("PLAYER_DEAD")
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.Deaths, 1)
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.DamageTaken, 1)
    h:Advance(6)
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.HealingDone, 1) -- too long after
    eq(h.ns.Probes.ByName["damageMeter.afterDeath"].run().types, "DamageTaken,Deaths")
end)

test("the shape helpers record a secret as its marker and anything else by its type", function()
    local h = Load()
    local Probes = h.ns.Probes
    for _, helper in ipairs({ "Value", "Shape", "NameShape", "Text", "Byte", "Fields" }) do
        local marker = Probes[helper](Secret(7))
        eq(marker.secret, true, helper)
        eq(marker.type, "number", helper)
    end
    eq(Probes.NameShape(42), "number")
    eq(Probes.Text(false), "boolean")
    eq(Probes.Byte(nil), "nil")
    eq(Probes.Byte(1), 255)
    eq(Probes.Fields("x"), "string")
    eq(Probes.First(Secret({ 1 })), nil, "a secret list has no first entry")
    eq(Probes.First(nil), nil)
end)

test("a result that can't be saved fails its probe with the path that's wrong, and isn't recorded", function()
    local h = Load()
    h.ns.Probes.Define({
        { name = "test.secret", needs = {}, run = function() return { nested = { health = Secret(5) } } end },
        { name = "test.function", needs = {}, run = function() return { fn = function() end } end },
        { name = "test.list", needs = {}, run = function() return { list = { "a" } } end },
    })
    h:Slash("/btdev probe")
    local text = Printed(h)
    truthy(text:find("probe test.secret failed: result.nested.health is a secret", 1, true), text)
    truthy(text:find("probe test.function failed: result.fn is a function", 1, true), text)
    truthy(text:find("probe test.list failed: result.list has a key that isn't a string", 1, true), text)
    for _, name in ipairs({ "test.secret", "test.function", "test.list" }) do
        eq(Records(h)[name], nil, name)
    end
end)

test("kill events under an instance restriction keep their secret GUIDs as secret, and no blow counts as yours", function()
    local h = Load()
    local Probes = h.ns.Probes
    h:SetRestriction("Encounter", true)
    h:Fire("PARTY_KILL", h:GUID(h.player), h:GUID({ name = "Kobold" }))
    h:Fire("UNIT_DIED", h:GUID({ name = "Kobold" }))
    h:Fire("PLAYER_TARGET_DIED")
    local kills = Probes.ByName["kills.seen"].run()
    eq(kills.partyKill.attacker, "secret")
    eq(kills.partyKill.attackerKind, "secret")
    eq(kills.partyKill.target, "secret")
    eq(kills.unitDied.unit, "secret")
    falsy((Probes.Check(Probes.ByName["kills.seen"])), "a secret attacker isn't known to be you")
end)

test("a death the damage meter has no entry for records no local death and no recap", function()
    local h = Load()
    h:Die()
    h:Slash("/btdev probe")
    eq(Records(h)["damageMeter.death"].result.localPlayer, false)
    eq(Records(h)["deathRecap.events"].result.recapID, "nil")
    eq(Records(h)["deathRecap.latest"].result.sameAsMeter, nil, "nothing to compare the latest recap with")
end)

test("an enemy hunter's Feign Death is recorded only while they feign or lie dead", function()
    local function Hunter(fields)
        local unit = { name = "Rexxar", isPlayer = true, canAttack = true, classFile = "HUNTER", race = "Orc",
            faction = "Horde", level = 20 }
        for key, value in pairs(fields) do unit[key] = value end
        return unit
    end
    local h = Load()
    h:SetTarget(Hunter({}))
    h:Slash("/btdev probe")
    eq(Records(h)["feign.enemyHunter"], nil, "standing")
    h:SetTarget(Hunter({ feign = true }))
    h:Slash("/btdev probe")
    local result = Records(h)["feign.enemyHunter"].result
    eq(result.feigning, true)
    eq(result.dead, false)
    local dead = Load()
    dead:SetTarget(Hunter({ dead = true }))
    dead:Slash("/btdev probe")
    eq(Records(dead)["feign.enemyHunter"].result.dead, true, "dead counts too: the client may report a feign as one")
end)

test("a quest log whose quests have no objectives records that it has none", function()
    local h = Load()
    h:AutoAcceptQuest({ title = "Report to Goldshire" })
    h:Slash("/btdev probe")
    eq(Records(h)["questLog.objectives"].result.hasObjectives, false)
    eq(Records(h)["questLog.countForm"].result.forms, "", "no objective text, so no count form")
end)

test("/btdev probe list says so when every probe has a result for this build", function()
    local h = Load()
    local records = {}
    for _, probe in ipairs(h.ns.Probes.List) do
        records[probe.name] = { build = Harness.BUILD, context = { combat = false, restrictions = "none" }, result = {},
            version = probe.version }
    end
    h.env.ByteTerraceDevToolsDB = { probes = records }
    local from = #h.printed + 1
    h:Slash("/btdev probe list")
    eq(Printed(h, from), "ByteTerrace DevTools: every probe has a result for " .. Harness.BUILD .. ".")
end)
