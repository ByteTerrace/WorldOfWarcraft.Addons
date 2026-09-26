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

test("/btdev probe records the probes whose needs are met, with build and context", function()
    local h = Load()
    h:Slash("/btdev probe")
    local record = Records(h)["chatTypeInfo.raidWarning"]
    eq(record.build, "1.60.1 (70009)")
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
    h:SetTarget({ name = "Kobold Vermin", classFile = "WARRIOR" })
    local from = #h.printed + 1
    h:Slash("/btdev probe")
    local text = Printed(h, from)
    truthy(text:find("(3 new, 1 changed)", 1, true), text)
    truthy(text:find("probe chatTypeInfo.raidWarning changed at result.g: was 1, now 72", 1, true), text)
    truthy(Records(h)["unitIdentity.npcTarget"], "now recorded")
    truthy(Records(h)["unitClassification.npcTarget"], "now recorded")
    eq(Records(h)["chatTypeInfo.raidWarning"].result.g, 72)
    local after = 0
    for _ in pairs(Records(h)) do after = after + 1 end
    eq(after, before + 3)
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
    truthy(text:find(("%d of %d probes have no result for 1.60.1 (70009) yet"):format(count, count), 1, true), text)
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
        .. "CHAT_MSG_RAID() CHAT_MSG_SAY() CHAT_MSG_WHISPER() CHAT_MSG_YELL() PARTY_KILL() PLAYER_TARGET_DIED() "
        .. "UNIT_COMBAT(player,target) UNIT_DIED()", "the chat senders, UNIT_COMBAT for two units, and the kill events")
    h:Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 42, 1)
    h:Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
    h:Slash("/btdev probe")
    eq(Records(h)["unitCombat.seen"], nil, "waits until the player has been hit too")
    h:Fire("UNIT_COMBAT", "player", "WOUND", "", Secret(7), 1)
    h:Fire("UNIT_COMBAT", "party1", "PARRY", "", 0, 1)
    h:Slash("/btdev probe")
    local result = Records(h)["unitCombat.seen"].result
    eq(result.actions, "DODGE,WOUND", "party1's payload never arrives")
    eq(result.flagTexts, "CRITICAL")
    eq(result.target.WOUND.flagText, "text")
    eq(result.target.WOUND.amount, "number")
    eq(result.target.DODGE.flagText, "empty")
    eq(result.player.WOUND.amount.secret, true, "a secret amount is recorded as its marker")
    eq(result.player.WOUND.amount.type, "number")
    eq(result.player.WOUND.schoolMask, "number")
end)

test("a record from another build counts as missing", function()
    local h = Load({ ByteTerraceDevToolsDB = { probes = { classColors = { build = "1.60.0 (69000)", context = {}, result = {} } } } })
    h:Slash("/btdev probe list")
    truthy(Printed(h):find("nothing: chatTypeInfo.raidWarning, classColors", 1, true), Printed(h))
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
    local kills = h.ns.Probes.Kills
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
    eq(ns.Probes.Senders.CHAT_MSG_SAY, "Aa Aa-Aa")
    eq(ns.Probes.Senders.CHAT_MSG_CHANNEL, "Aa")
end)
