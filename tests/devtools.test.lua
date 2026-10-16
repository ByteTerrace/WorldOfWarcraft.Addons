-- ByteTerrace_DevTools' probe commands: /btdev probe records the probes whose needs are met into
-- ByteTerraceDevToolsDB.probes and lists what the rest need; /btdev probe list shows what's left, in play-session
-- order. DevTools also collects, from load, what the listening probes need: UNIT_COMBAT payloads, the steps into and
-- out of combat, UNIT_AURA tokens, addon messages and chat payloads.

-- A record's contexts, sorted and joined by spaces.
local function Contexts(record)
    local list = {}

    for context in pairs(record.contexts) do list[#list + 1] = context end

    table.sort(list)

    return table.concat(list, " ")
end

local function Hit(spellID, name)
    return {
        details = { classification = "normal", isMob = true, unitName = "Kobold Vermin" }, isDeadly = true, name = name,
        overkillAmount = 5, spellID = spellID, totalAmount = 60,
    }
end

local function Load(saved)
    local h = Harness.New({ saved = saved })

    h:LoadAddon("ByteTerrace_DevTools")

    return h
end

local function Printed(h, from)
    return table.concat(h.printed, "\n", from or 1)
end

local function Records(h)
    return h.env.ByteTerraceDevToolsDB.probes
end

local function DieToDamage(h, spells)
    h:MeterFight({ duration = 12, sources = {
        { death = { maxHealth = 55 }, spells = { DamageTaken = spells }, unit = "player" },
    } })

    h:Slash("/btdev probe")

    return Records(h)["deathRecap.events"].result
end

test("death recap fields are kept per kind of event: the same for a kind, however you died", function()
    local byKind = {}

    for _, spells in ipairs({
        { Hit(6603) }, { Hit(11976, "Strike") },
        { Hit(11976, "Strike"), Hit(6603) }, { Hit(6603), Hit(11976, "Strike") },
    }) do
        local h = Load()
        local result = DieToDamage(h, spells)

        eq(result.fields, nil)
        eq(result.killingBlow.amount, "number")
        eq(result.killingBlow.sourceName, "string")
        eq(result.killingBlow.spellId, nil, "spell fields have their own event-kind probe")

        for kind, fields in pairs(result.fieldsByKind) do
            if byKind[kind] then eq(fields, byKind[kind], kind .. " carries the same fields in every death") end

            byKind[kind] = fields
        end
    end

    truthy(byKind.SWING_DAMAGE and byKind.SPELL_DAMAGE, "melee and spells each have their own list")
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

    h:MeterFight({ duration = 1, sources = { { death = { events = {
            { amount = 60, avoidable = false, deadly = true, event = "SWING_DAMAGE", spellId = 6603,
                spellName = "Attack", spellSchool = 1 },
        } },
        unit = "player" } } })

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
        h:MeterFight({ duration = 1, sources = { { death = {
            events = { events[2], events[1] }, maxHealth = 55,
        },
            unit = "player" } } })

        h:Slash("/btdev probe")

        return Records(h)["deathRecap.events"].result
    end

    eq(#h.ns.Probes.Diff(baseline, Record()), 0, "optional mitigation doesn't alter common shapes")
    events[2].amount = nil
    -- The record grows across deaths, so this one starts afresh.
    Records(h)["deathRecap.events"] = nil
    local result = Record()
    local missing = 0

    for _, fields in pairs(result.fieldsByKind) do
        if not ("," .. fields .. ","):find(",amount,", 1, true) then missing = (missing + 1) end
    end

    eq(missing, 1, "the kind whose event lacks amount drops it; the other keeps it")
    eq(result.killingBlow.amount, "number", "the killing blow retains its own shape")
end)

test("spell-field probes reject inconsistent events and preserve secret markers", function()
    local h = Load()

    h:MeterFight({ duration = 1, sources = { { death = { events = {
            { event = "SPELL_DAMAGE", spellId = 11976, spellName = "Strike", spellSchool = 1 },
            { event = "SPELL_DAMAGE", spellId = 11976, spellSchool = 1 },
        } },
        unit = "player" } } })

    h:Slash("/btdev probe")
    eq(Records(h)["deathRecap.spellFields"], nil, "inconsistent samples don't become calibrated evidence")
    truthy(Printed(h):find("SPELL_DAMAGE.spellName varies between recap events", 1, true), Printed(h))
    local secretHarness = Load()

    secretHarness:MeterFight({ duration = 1, sources = { { death = { events = {
            { amount = Secret(60), event = "SPELL_DAMAGE", spellId = Secret(11976) },
        } },
        unit = "player" } } })

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
    eq(Contexts(record), "idle/none")
    eq(record.result.g, 72)
    eq(record.result.hasMetatable, true)
    truthy(Records(h)["chat.lockdownIdle"], "an idle probe runs out of combat")
    eq(Records(h)["unitIdentity.npcTarget"], nil, "no target: skipped")
    eq(Records(h)["quest.offer"], nil, "no quest dialog: skipped")
    local text = Printed(h)

    truthy(text:find("recorded %d+ probes %(%d+ new, 0 changed, 0 confirmed in a new context or build%)"), text)
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

    for _ in pairs(Records(h)) do before = (before + 1) end

    Records(h)["chatTypeInfo.raidWarning"].result.g = 1
    Records(h)["chatTypeInfo.raidWarning"].result.r = { secret = true, type = "number" }
    h:SetTarget({ classFile = "WARRIOR", name = "Kobold Vermin" })
    local from = (#h.printed + 1)

    h:Slash("/btdev probe")
    local text = Printed(h, from)
    local after = 0

    for _ in pairs(Records(h)) do after = (after + 1) end

    truthy(after > before, "the target's probes are added")
    truthy(text:find(("(%d new, 1 changed, 0 confirmed"):format(after - before), 1, true), "the summary counts what was added: " .. text)
    truthy(text:find("probe chatTypeInfo.raidWarning changed at result.g: was 1, now 72", 1, true), text)

    truthy(text:find('probe chatTypeInfo.raidWarning changed at result.r: was { secret = true, type = "number" }, now 255',
        1, true), "a table prints with its keys sorted: " .. text)

    truthy(Records(h)["unitIdentity.npcTarget"], "now recorded")
    truthy(Records(h)["unitClassification.npcTarget"], "now recorded")
    truthy(Records(h)["power.npcTarget"], "now recorded")
    eq(Records(h)["chatTypeInfo.raidWarning"].result.g, 72)
end)

test("probes survive a reload, and a dump already saved is kept", function()
    local h = Load({ ByteTerraceDevToolsDB = { build = { build = "70009", version = "1.60.1" }, globals = { UnitName = { type = "function" } } } })

    h:Slash("/btdev probe")
    h:Reload()
    local db = h.env.ByteTerraceDevToolsDB

    eq(db.globals.UnitName.type, "function", "the dump is untouched")
    eq(db.probes["chatTypeInfo.raidWarning"].result.r, 255)
end)

test("in combat, records carry the combat context", function()
    local h = Load()

    h:SetTarget({ classFile = "WARRIOR", name = "Kobold Vermin" })
    h:EnterCombat()
    h:Slash("/btdev probe")
    local record = Records(h)["unitHealth.npcTargetInCombat"]

    eq(Contexts(record), "combat/Combat")
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
    local from = (#h.printed + 1)

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

            for unit in pairs(((type(units) == "table") and units) or {}) do names[#names + 1] = unit end

            table.sort(names)
            registered[#registered + 1] = (event .. "(" .. table.concat(names, ",") .. ")")
        end
    end

    table.sort(registered)

    eq(table.concat(registered, " "), "ADDON_RESTRICTION_STATE_CHANGED() CHAT_MSG_ADDON() CHAT_MSG_CHANNEL() "
        .. "CHAT_MSG_GUILD() CHAT_MSG_PARTY() CHAT_MSG_RAID() CHAT_MSG_SAY() CHAT_MSG_WHISPER() CHAT_MSG_YELL() "
        .. "DAMAGE_METER_COMBAT_SESSION_UPDATED() DAMAGE_METER_CURRENT_SESSION_UPDATED() ENCOUNTER_START() ENCOUNTER_WARNING() GAME_PAD_ACTIVE_CHANGED() "
        .. "GAME_PAD_CONFIGS_CHANGED() GAME_PAD_CONNECTED() GAME_PAD_DISCONNECTED() GAME_PAD_POWER_CHANGED() "
        .. "INPUT_DEVICE_INTERFACE_TRANSITION() NAME_PLATE_UNIT_ADDED() NAME_PLATE_UNIT_REMOVED() PARTY_KILL() PLAYER_DEAD() "
        .. "PLAYER_ENTERING_WORLD() PLAYER_REGEN_DISABLED() PLAYER_REGEN_ENABLED() PLAYER_TARGET_DIED() QUEST_TURNED_IN() "
        .. "UNIT_AURA(player,target) UNIT_COMBAT(player,target) UNIT_DIED()",
        "the chat events, restriction changes and combat edges, UNIT_AURA and UNIT_COMBAT for two units, the kill "
        .. "events, deaths with the meter's updates, and encounters with their warnings")

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
    local h = Load({ ByteTerraceDevToolsDB = { probes = { classColors = { build = "1.60.0 (69000)", contexts = { ["idle/none"] = true }, result = {} } } } })

    h:Slash("/btdev probe list")
    truthy(Printed(h):find("nothing: chatTypeInfo.raidWarning, classColors", 1, true), Printed(h))
end)

test("a record from another version of its probe counts as missing, and a new run replaces it", function()
    local old = { build = Harness.BUILD, contexts = { ["idle/none"] = true }, result = { fields = "amount" } }
    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["deathRecap.events"] = old } } })

    h:Slash("/btdev probe list")
    truthy(Printed(h):find("deathRecap.events", 1, true), Printed(h))
    local from = (#h.printed + 1)

    DieToDamage(h, { Hit(133, "Fireball") })
    local text = Printed(h, from)

    falsy(text:find("probe deathRecap.events changed", 1, true), "an old version's record isn't compared: " .. text)
    local record = Records(h)["deathRecap.events"]

    eq(record.version, 3)
    truthy(record.result.fieldsByKind and record.result.fieldsByKind.SPELL_DAMAGE, "version 3 keeps fields per kind of event")
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

    h:FireChat("CHAT_MSG_SAY", "hello", "Dh Taketwo-Realm")
    h:FireChat("CHAT_MSG_CHANNEL", "hi", "Bob")
    h:Fire("CHAT_MSG_ADDON", "TLK", "HELLO", "PARTY", "Cara Doe-Realm", "", 0, 0, "", 0)
    local senders = ns.Probes.ByName["names.chatSenders"].run()

    eq(senders.CHAT_MSG_SAY, "Aa Aa-Aa")
    eq(senders.CHAT_MSG_CHANNEL, "Aa")
    eq(senders.CHAT_MSG_ADDON, "Aa Aa-Aa", "an addon message's sender is its fourth argument")
end)

test("kill events accumulate: a player kill after a mob kill keeps both kinds", function()
    local h = Load()
    local me = h:GUID(h.player)

    h:Fire("PARTY_KILL", me, h:GUID({ name = "Kobold" }))
    h:Fire("PARTY_KILL", me, h:GUID({ isPlayer = true, name = "Cara" }))
    local kills = h.ns.Probes.ByName["kills.seen"].run()

    eq(kills.partyKill.attacker, "you")
    eq(kills.partyKill.target, "Creature,Player")
end)

test("an accumulating probe's record grows across sessions and reloads", function()
    local record = { build = Harness.BUILD, contexts = { ["combat/Combat"] = true },
        result = { partyKill = { attacker = "pet", attackerKind = "Pet", target = "Creature" }, targetDied = true } }

    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["kills.seen"] = record } } })

    h:Fire("PARTY_KILL", h:GUID(h.player), h:GUID({ isPlayer = true, name = "Cara" }))
    h:Fire("PLAYER_TARGET_DIED")
    h:FireChat("CHAT_MSG_SAY", "hi", "Bob")
    h:Slash("/btdev probe")
    local result = Records(h)["kills.seen"].result

    eq(result.partyKill.attacker, "pet,you")
    eq(result.partyKill.target, "Creature,Player")
    eq(result.targetDied, true, "kept from the earlier session")
    eq(Contexts(Records(h)["kills.seen"]), "combat/Combat idle/none", "and so is its context, joined by this one")
    h:Reload()
    h:FireChat("CHAT_MSG_CHANNEL", "hi", "Dh Taketwo-Realm")
    h:Slash("/btdev probe")
    local senders = Records(h)["names.chatSenders"].result

    eq(senders.CHAT_MSG_SAY, "Aa", "a reload keeps what the last session heard")
    eq(senders.CHAT_MSG_CHANNEL, "Aa Aa-Aa")
end)

test("a fight in which you dealt no damage doesn't count as after a fight", function()
    local h = Load()
    local hit = { details = { classification = "normal", isMob = true, unitName = "Kobold Vermin" }, spellID = 6603, totalAmount = 24 }

    h:MeterFight({ duration = 6, sources = { { amounts = { DamageDone = 300 }, unit = "player" } } })
    h:MeterFight({ duration = 4, sources = { { spells = { DamageTaken = { hit } }, unit = "player" } } })
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
    h:FireChat("CHAT_MSG_SAY", "hi", "Bob")
    h:FireChat("CHAT_MSG_SAY", "hi", Secret("Cara Doe"))
    h:FireChat("CHAT_MSG_SAY", "hi", "Dh Taketwo")
    eq(Probes.ByName["names.chatSenders"].run().CHAT_MSG_SAY, "Aa,Aa Aa,secret")
end)

test("a saved accumulating record keeps its items when a session saw a secret", function()
    local record = { build = Harness.BUILD, contexts = { ["idle/none"] = true },
        result = { CHAT_MSG_SAY = "Aa,Aa Aa" } }

    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["names.chatSenders"] = record } } })

    h:FireChat("CHAT_MSG_SAY", "hi", Secret("Cara Doe"))
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

        if (id == nil) and events[1] then
            Alter(events[1])
        end

        return events
    end)

    Alter = function(blow) blow.timestamp = Secret(blow.timestamp) end
    eq(latest.run().sameAsMeter, "secret")
    Alter = function(blow) blow.timestamp, blow.amount = Secret(blow.timestamp), (blow.amount + 1) end
    eq(latest.run().sameAsMeter, false, "a plain field that differs decides, whatever else was secret")
end)

test("another player's kill doesn't count as a mob you killed yourself", function()
    local h = Load()
    local Probes = h.ns.Probes

    h:Fire("PARTY_KILL", h:GUID({ isPlayer = true, name = "Mom" }), h:GUID({ name = "Kobold" }))
    h:Fire("PLAYER_TARGET_DIED")
    falsy((Probes.Check(Probes.ByName["kills.seen"])), "someone else's blow")
    h:Fire("PARTY_KILL", h:GUID(h.player), h:GUID({ name = "Kobold" }))
    truthy((Probes.Check(Probes.ByName["kills.seen"])), "yours")
end)

test("/btdev probe lists only what's still to do, and a new context alone isn't news", function()
    local h = Load()

    h:Slash("/btdev probe")
    h:EnterCombat()
    local from = (#h.printed + 1)

    h:Slash("/btdev probe")
    local text = Printed(h, from)

    falsy(text:find("changed at", 1, true), "combat context alone: " .. text)
    falsy(text:find("classColors", 1, true), "an answered probe isn't listed again: " .. text)
    truthy(text:find("%(%d+ new, 0 changed, %d+ confirmed in a new context or build%)"), text)
    eq(Contexts(Records(h)["chatTypeInfo.raidWarning"]), "combat/Combat idle/none", "the same result in combat adds the context")
end)

test("/btdev probe again in a known context changes no record and reports nothing changed", function()
    local h = Load()

    h:Slash("/btdev probe")
    local before = {}

    for name, record in pairs(Records(h)) do before[name] = h.ns.Probes.Show(record) end

    local from = (#h.printed + 1)

    h:Slash("/btdev probe")
    local text = Printed(h, from)

    truthy(text:find("(0 new, 0 changed, 0 confirmed in a new context or build)", 1, true), text)
    falsy(text:find("changed at", 1, true), text)

    for name, record in pairs(Records(h)) do eq(h.ns.Probes.Show(record), before[name], name) end
end)

test("a different result replaces the record and its contexts, and says which contexts it replaced", function()
    local stale = { build = Harness.BUILD, contexts = { ["combat/Combat"] = true, ["idle/none"] = true },
        result = { b = 0, g = 1, hasMetatable = true, r = 255, sticky = 0 } }

    local h = Load({ ByteTerraceDevToolsDB = { probes = { ["chatTypeInfo.raidWarning"] = stale } } })

    h:Slash("/btdev probe")
    local text = Printed(h)

    truthy(text:find("probe chatTypeInfo.raidWarning changed at result.g: was 1, now 72", 1, true), text)
    truthy(text:find("probe chatTypeInfo.raidWarning now holds only idle/none; the new result replaced combat/Combat", 1, true), text)
    eq(Contexts(Records(h)["chatTypeInfo.raidWarning"]), "idle/none")
end)

test("a record from another build is replaced, contexts and all, even with the same result", function()
    local h = Load()

    h:Slash("/btdev probe")
    local record = Records(h)["chatTypeInfo.raidWarning"]

    record.build, record.contexts = "1.60.0 (69000)", { ["combat/Combat"] = true }
    h:Slash("/btdev probe")
    eq(Contexts(Records(h)["chatTypeInfo.raidWarning"]), "idle/none", "only this build's context vouches for it")
    eq(Records(h)["chatTypeInfo.raidWarning"].build, Harness.BUILD)
end)

test("the meter's updates in the seconds after your death are kept by type, for damageMeter.afterDeath", function()
    local h = Load()
    local types = h.env.Enum.DamageMeterType

    -- An update before any death isn't kept.
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.DamageDone, 1)
    h:Fire("PLAYER_DEAD")
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.Deaths, 1)
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.DamageTaken, 1)
    h:Advance(6)
    -- An update more than AfterDeathSeconds after the death isn't kept.
    h:Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", types.HealingDone, 1)
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
        local unit = { canAttack = true, classFile = "HUNTER", faction = "Horde", isPlayer = true, level = 20,
            name = "Rexxar", race = "Orc" }

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
        records[probe.name] = { build = Harness.BUILD, contexts = { ["idle/none"] = true }, result = {},
            version = probe.version }
    end

    h.env.ByteTerraceDevToolsDB = { probes = records }
    local from = (#h.printed + 1)

    h:Slash("/btdev probe list")
    eq(Printed(h, from), "ByteTerrace DevTools: every probe has a result for " .. Harness.BUILD .. ".")
end)

-- Every wrapped client call the harness counted so far.
local function ApiCalls(h)
    local total = 0

    for _, count in pairs(h.apiCalls) do total = (total + count) end

    return total
end

test("the steps into and out of combat are kept in order with what each signal said, for combat.edges", function()
    local h = Load()

    h:EnterCombat()
    h:Slash("/btdev probe")
    eq(Records(h)["combat.edges"], nil, "in combat: the leave edge is still to come")
    h:LeaveCombat()
    h:Slash("/btdev probe")
    local result = Records(h)["combat.edges"].result

    eq(result.enter, "PLAYER_REGEN_DISABLED[lockdown=false affecting=true restricted=false] > "
        .. "Combat Activating[lockdown=false affecting=true restricted=false]",
        "as the client did: PLAYER_REGEN_DISABLED first, then Activating, and no Active")

    eq(result.leave, "Combat Inactive[lockdown=false affecting=false restricted=false] > "
        .. "PLAYER_REGEN_ENABLED[lockdown=false affecting=false restricted=false]",
        "the Combat restriction lifts before PLAYER_REGEN_ENABLED")

    h:EnterCombat()
    h:LeaveCombat()
    h:Slash("/btdev probe")
    eq(#h.ns.Probes.Diff(Records(h)["combat.edges"].result, result), 0, "the same order again changes nothing")
end)

test("combat.edges keeps another order as it came, adds it to a saved record, and caps an edge's steps", function()
    local h = Load()
    local types, states = h.env.Enum.AddOnRestrictionType, h.env.Enum.AddOnRestrictionState

    h:Fire("PLAYER_REGEN_DISABLED")
    h:Fire("PLAYER_REGEN_ENABLED")
    h:Fire("ADDON_RESTRICTION_STATE_CHANGED", types.Combat, states.Inactive)
    -- Another restriction's change isn't a step.
    h:Fire("ADDON_RESTRICTION_STATE_CHANGED", types.Map, states.Inactive)

    local leave = ("PLAYER_REGEN_ENABLED[lockdown=false affecting=false restricted=false] > "
        .. "Combat Inactive[lockdown=false affecting=false restricted=false]")

    eq(h.ns.Probes.ByName["combat.edges"].run().leave, leave)

    local record = { build = Harness.BUILD, contexts = { ["idle/none"] = true },
        result = { enter = "PLAYER_REGEN_DISABLED[lockdown=false affecting=false restricted=false]", leave = leave } }

    local saved = Load({ ByteTerraceDevToolsDB = { probes = { ["combat.edges"] = record } } })

    saved:EnterCombat()
    saved:LeaveCombat()
    saved:Slash("/btdev probe")
    local merged = Records(saved)["combat.edges"].result.leave
    local harnessOrder = "Combat Inactive[lockdown=false affecting=false restricted=false] > PLAYER_REGEN_ENABLED"

    truthy(merged:find(leave, 1, true) and merged:find(harnessOrder, 1, true), "both orders are kept: " .. merged)

    for _ = 1, 10 do h:Fire("PLAYER_REGEN_DISABLED") end

    local _, separators = h.ns.Probes.ByName["combat.edges"].run().enter:gsub(" > ", "")

    eq(separators + 1, 8, "an edge keeps at most eight steps")
end)

test("UNIT_AURA's token is kept per restriction for two units, asking the client nothing", function()
    local h = Load()

    h:Fire("UNIT_AURA", "player", { isFullUpdate = true })
    h:Slash("/btdev probe")
    eq(Records(h)["units.secretTokenInAuraEvent"], nil, "no aura restriction yet")
    h:EnterCombat()
    local before, checks = ApiCalls(h), h:CountApiCalls("issecretvalue")

    h:Fire("UNIT_AURA", "target", { isFullUpdate = true })
    h:Fire("UNIT_AURA", "party1", { isFullUpdate = true })
    eq(h:CountApiCalls("issecretvalue") - checks, 1, "the one aura change delivered checks its token once")
    eq(ApiCalls(h) - before, 1, "and asks the client nothing else, the restrictions included")
    h.ns.Probes.NoteAuraToken(Secret("player"))
    h:Slash("/btdev probe")
    local result = Records(h)["units.secretTokenInAuraEvent"].result

    eq(result.none, "player")
    eq(result.Combat, "secret,target", "party1's aura never arrives; a secret token is kept as secret")
end)

test("a restriction in force when DevTools loads keys what the listeners hear", function()
    local h = Harness.New()

    h:SetRestriction("Map", true)
    h:LoadAddon("ByteTerrace_DevTools")
    h:Fire("UNIT_AURA", "player", { isFullUpdate = true })
    eq(h.ns.Probes.ByName["units.secretTokenInAuraEvent"].run().Map, "player")
end)

test("addon messages are kept as field shapes per restriction, for comms.addonMessageInLockdown", function()
    local h = Load()

    local function Receive()
        h:Fire("CHAT_MSG_ADDON", "TLK", "HELLO", "PARTY", "Cara Doe", "", 0, 0, "", 0)
    end

    Receive()
    h:JoinGroup("party", { "Friend" })
    h:EnterCombat()
    h:LeaveCombat()
    h:Slash("/btdev probe")
    eq(Records(h)["comms.addonMessageInLockdown"], nil, "combat alone isn't a messaging restriction")
    h:SetRestriction("Encounter", true)
    Receive()
    h.ns.Probes.NoteAddonMessage("TLK", Secret("HELLO"), "PARTY", "Cara Doe", "", 0, 0, "", 0)
    h:SetRestriction("Encounter", false)
    h:Slash("/btdev probe")
    local result = Records(h)["comms.addonMessageInLockdown"].result

    eq(result.restrictionsSeen, "Combat,Encounter")
    eq(result.heard.none.sender, "text")
    eq(result.heard.none.target, "empty")
    eq(result.heard.none.zoneChannelID, "number")
    eq(result.heard.Encounter.text, "secret,text")
    eq(result.heard.Encounter.instanceID, "number")
end)

test("xp.atMaxLevel records the signs of UnitXP and UnitXPMax once you're at the max level", function()
    local h = Load()

    h:Slash("/btdev probe")
    eq(Records(h)["xp.atMaxLevel"], nil, "level 1")
    h.player.level, h.player.xp, h.player.xpMax = h.maxLevel, 0, 0
    h:Slash("/btdev probe")
    local result = Records(h)["xp.atMaxLevel"].result

    eq(result.xp, "zero")
    eq(result.xpMax, "zero")
end)

test("chat events' discordInfo is kept as shapes, with a table's fields, for names.chatDiscordInfo", function()
    local h = Load()

    h:Fire("CHAT_MSG_ADDON", "TLK", "HELLO", "PARTY", "Cara Doe", "", 0, 0, "", 0)
    h:Slash("/btdev probe")
    eq(Records(h)["names.chatDiscordInfo"], nil, "an addon message has no discordInfo and isn't chat heard")
    h:FireChat("CHAT_MSG_SAY", "hi", "Bob")

    h:Fire("CHAT_MSG_GUILD", "hi", "Bob", "", "", "", "", 0, 0, "", 0, 2, "", 0, false, false, false, false,
        { fromDiscord = true, globalName = "Bob", hasPoll = true, userID = 7 })

    h:Slash("/btdev probe")
    local result = Records(h)["names.chatDiscordInfo"].result

    eq(result.shapes.CHAT_MSG_SAY .. " " .. result.shapes.CHAT_MSG_GUILD, "table table")
    eq(result.fields.userID, "number")
    eq(result.fields.globalName, "empty,text", "each field keeps every shape it showed")
    eq(result.fields.hasPoll, "false,true")
    eq(result.fields.fromDiscord, "false,true")
end)

test("leaving combat in a PvP match keeps the meter's totals' shapes then and later, for damageMeter.pvpSecrecy", function()
    -- The sweeps' probes read the meter too; this counts the listener's reads alone.
    local h = Load({ ByteTerraceDevToolsDB = { autoProbe = false } })
    local Probes, probe = h.ns.Probes, h.ns.Probes.ByName["damageMeter.pvpSecrecy"]

    local function Reads() return h:CountApiCalls("C_DamageMeter.GetCombatSessionFromType") end

    h:MeterFight({ duration = 10, sources = { { amounts = { DamageDone = 420 }, unit = "player" } } })
    h:Advance(Probes.PvPLaterSeconds + 1)
    eq(Reads(), 0, "a fight outside PvP reads nothing")
    h:SetLocation({ instance = "arena" })
    h:SetRestriction("PvPMatch", true)
    h:MeterFight({ duration = 10, sources = { { amounts = { DamageDone = 420 }, unit = "player" } } })
    eq(Reads(), 1, "one read on leaving combat")
    falsy((Probes.Check(probe)), "the read a few seconds later is still to come")
    h:Advance(Probes.PvPLaterSeconds)
    eq(Reads(), 2, "and one more then")
    local shapes = '{ arena/PvPMatch = { localTotalAmount = "number", totalAmount = "number" } }'

    eq(Probes.Show(probe.run().leftCombat) .. " " .. Probes.Show(probe.run().later), shapes .. " " .. shapes)
    h:EnterCombat()
    h:LeaveCombat()
    eq(probe.run().leftCombat["arena/PvPMatch"].localTotalAmount, "none,number", "no entry of yours without damage dealt")
    h:EnterCombat()
    h:MeterAdd({ amounts = { DamageDone = 50 }, unit = "player" })
    -- The note is taken as if PLAYER_REGEN_ENABLED came while the Combat restriction still held.
    Probes.NotePvPLeftCombat()
    local read = probe.run().leftCombat["arena/Combat,PvPMatch"]

    eq(read.totalAmount .. " " .. read.localTotalAmount, "secret secret", "your entry is found by isLocalPlayer, never secret")
end)

test("auraSound.api registers an aura sound and removes it, idle only; the fake follows the docs", function()
    local h = Load()

    h:Slash("/btdev probe")

    eq(h.ns.Probes.Show(Records(h)["auraSound.api"].result), '{ addAuraSound = "function", added = { auraSoundID = '
        .. '"number", errors = false, removeErrors = false }, invalidThrottle = { auraSoundID = "nil", errors = false }, '
        .. 'removeAuraSound = "function" }', "a throttle past five seconds rejects registration without an error")

    eq(next(h.auraSounds), nil, "nothing stays registered")
    local auras, triggers = h.env.C_UnitAuras, h.env.Enum.UnitAuraSoundTrigger
    local sound = { soundFileID = 1, spellID = 1126, throttleSeconds = 0, unitToken = "player" }

    falsy(pcall(auras.AddAuraSound, 7, sound), "a trigger that isn't an enum value")
    local id = auras.AddAuraSound(triggers.Removed, sound)

    eq(h.auraSounds[id].sound.spellID, 1126)
    auras.RemoveAuraSound(id)
    eq(next(h.auraSounds), nil)
    h:EnterCombat()
    local adds = h:CountApiCalls("C_UnitAuras.AddAuraSound")

    h:Slash("/btdev probe")
    eq(h:CountApiCalls("C_UnitAuras.AddAuraSound"), adds, "the probe waits for idle")
    h:ExpectBlocked("^C_UnitAuras%.AddAuraSound$")
    eq(auras.AddAuraSound(triggers.Added, sound), nil, "registering is blocked in combat lockdown")
end)

test("ENCOUNTER_WARNING's payload is kept as field shapes once an encounter started, for encounterWarning.seen", function()
    local h = Load()
    local Probes, probe = h.ns.Probes, h.ns.Probes.ByName["encounterWarning.seen"]

    falsy((Probes.Check(probe)), "no encounter yet")
    h:StartEncounter({ name = "Hogger" })
    eq(Probes.Show(probe.run()), "{ featureAvailable = false, featureEnabled = false, heard = false }")
    local severity = h.env.Enum.EncounterEventSeverity
    local before, checks = ApiCalls(h), h:CountApiCalls("issecretvalue")

    h:EncounterWarning({ duration = 5, severity = severity.High, shouldPlaySound = false, text = "Hogger enrages!" })
    eq(ApiCalls(h) - before, h:CountApiCalls("issecretvalue") - checks, "a warning asks the client nothing else")
    h:EncounterWarning({ severity = severity.Low })
    local result = probe.run()
    local fields = result.fields

    eq(table.concat({ result.info, fields.text, fields.targetGUID, fields.isDeadly, fields.color, fields.duration,
        fields.severity, fields.shouldPlaySound }, " "), "table secret secret secret secret number High,Low false,true")
end)
