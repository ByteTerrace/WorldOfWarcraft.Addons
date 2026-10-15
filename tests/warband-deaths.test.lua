-- Who killed you: the death fact's recap attribution, Warband's grudge cards and rivalry records,
-- and Streaks' spree endings.

local Prefix = "TLKKrew1"

local function Grouped()
    local h = Harness.New({ saved = {} })
    local ns = h:LoadAddon("TheLanKrewToolKit")

    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)
    return h, ns.Addon
end

local function Enemy(name, extra)
    local unit = { canAttack = true, classFile = "ROGUE", className = "Rogue", faction = "Alliance", isEnemy = true,
        isPlayer = true, level = 60, name = (name or "Bob"), playerControlled = true }

    for key, value in pairs(extra or {}) do unit[key] = value end
    return unit
end

-- A player's key: Forever's full name (every test player's surname is the harness default).
local function Key(_, name)
    return (name .. " " .. Harness.DEFAULT_SURNAME)
end

local function People(addon)
    return addon.Modules.Warband.Records.people
end

local function Card(h)
    local card = rawget(h.env, "TheLanKrewToolKitCard")

    if not (card and card:IsShown()) then
        return nil
    end
    return (Reveal(Harness.State(card.Title).text) .. "\n" .. Reveal(Harness.State(card.Body).text)), card
end

local function Sent(h, kind)
    local found = {}

    for _, message in ipairs(h.addonMessages) do
        if (message.prefix == Prefix) and message.message:find("^" .. kind .. ":") then
            found[#found + 1] = message.message
        end
    end
    return found
end

-- Your killing blow on an enemy player: PARTY_KILL(your GUID, theirs).
local function Blow(h, name)
    h:Fire("PARTY_KILL", h.env.UnitGUID("player"), h:GUID({ isPlayer = true, name = name }))
end

-- The player's source in a fight they die in, killed by attacker (a unit table) with one blow.
local function KilledBy(attacker, blow)
    blow = (blow or {})
    return {
        death = {},
        spells = { DamageTaken = { {
            details = { isMob = not attacker.isPlayer, isPet = (blow.isPet == true), unit = attacker,
                unitName = attacker.name },
            name = blow.name, overkillAmount = 200, spellID = (blow.spellID or 8676),
            totalAmount = (blow.amount or 700),
        } } },
        unit = "player",
    }
end

test("the death recap names the enemy player who killed you: it counts, and a card offers the grudge", function()
    local h, addon = Grouped()
    local bob = Enemy("Bob", { race = "Human" })

    h:MeterFight({ duration = 5, sources = { KilledBy(bob, { name = "Ambush" }) } })
    local key = Key(h, "Bob")

    eq(addon.State:Get("death.killer"), "Bob Doe")
    eq(addon.State:Get("death.killerKind"), "player")
    eq(People(addon):Field(key, "deaths"), 1, "a certain kill counts without a click")
    eq(People(addon):Field(key, "class"), "ROGUE", "the class, from the killer's GUID")
    eq(People(addon):Field(key, "faction"), "Alliance", "the faction, from the killer's race")
    local text, card = Card(h)

    truthy(text:find("Slain by Bob Doe\n", 1, true), text)
    truthy(text:find("Ambush for 700. Krew 0 : 1 Bob Doe.", 1, true), text)
    h:Click(card)
    eq(People(addon):Field(key, "deaths"), 1, "holding the grudge doesn't count the death twice")
    eq(addon.Modules.Warband.Records.ledger:Field(key, "kind"), "grudge")
    h:Advance(3)
    eq(Sent(h, "GRUDGE")[1], "GRUDGE:" .. key .. "\tROGUE\t0\tAlliance\t1", "the Krew counts it too")
end)

test("a melee killing blow reads as a melee hit, and the suspect fills in what the recap can't", function()
    local h, addon = Grouped()
    local bob = Enemy("Bob") -- no race: the recap can't tell the faction

    h:SetTarget(bob)
    h:MeterFight({ duration = 5, sources = { KilledBy(bob, { amount = 90, spellID = 6603 }) } })
    truthy(Card(h):find("A melee hit for 90.", 1, true), Card(h))
    local key = Key(h, "Bob")

    eq(People(addon):Field(key, "level"), 60, "the level of the player you had targeted")
    eq(People(addon):Field(key, "faction"), "Alliance")
end)

test("a creature's kill asks nothing, even with an enemy player targeted", function()
    local h, addon = Grouped()

    h:SetTarget(Enemy("Bob"))
    h:MeterFight({ duration = 5, sources = { KilledBy({ canAttack = true, name = "Kobold Vermin" }) } })
    eq(addon.State:Get("death.killerKind"), "npc")
    eq(Card(h), nil)
    eq(People(addon):Field(Key(h, "Bob"), "deaths"), 0)
end)

test("a pet's kill falls back to asking about the enemy player you were fighting", function()
    local h = Grouped()

    h:SetTarget(Enemy("Bob"))
    h:MeterFight({ duration = 5, sources = { KilledBy({ canAttack = true, name = "Wolf" }, { isPet = true }) } })
    truthy(Card(h):find("Slain by Bob Doe?", 1, true), Card(h))
end)

test("a recap that lands after the death still names the killer, with the suspect from the moment of death", function()
    local h, addon = Grouped()
    local bob = Enemy("Bob")

    h:SetTarget(bob)
    h:EnterCombat()
    h:Fire("PLAYER_DEAD")
    truthy(addon.Events.Frame:IsEventRegistered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "waiting for the meter")
    h:SetTarget(nil)
    h:MeterAdd(KilledBy(bob))
    h:LeaveCombat() -- cards wait out combat
    truthy(Card(h):find("Slain by Bob Doe\n", 1, true), Card(h))
    eq(People(addon):Field(Key(h, "Bob"), "level"), 60)
    falsy(addon.Events.Frame:IsEventRegistered("DAMAGE_METER_COMBAT_SESSION_UPDATED"), "done waiting")
end)

test("the Ask who killed me setting silences the cards; the record still counts", function()
    local h, addon = Grouped()

    addon.State:Set("Warband.deathPrompt", false)
    h:MeterFight({ duration = 5, sources = { KilledBy(Enemy("Bob")) } })
    eq(Card(h), nil)
    eq(People(addon):Field(Key(h, "Bob"), "deaths"), 1)
end)

test("a spree's end names who ended it, for you and the Krew", function()
    local h = Grouped()

    for i = 1, 5 do
        Blow(h, "Foe" .. i)
        h:Advance(20)
    end
    h:MeterFight({ duration = 5, sources = { KilledBy(Enemy("Bob")) } })
    h:Advance(2)
    truthy(h.printed[#h.printed]:find("Your spree ended at 5 kills. Bob Doe ended it.", 1, true), h.printed[#h.printed])
    eq(Sent(h, "STREAK")[#Sent(h, "STREAK")], "STREAK:ended\t5\tBob Doe")
    h:ReceiveAddonMessage(Prefix, "STREAK:ended\t7\tCid", "PARTY", "Mom")
    h:ReceiveAddonMessage(Prefix, "STREAK:ended\t7\t|cffff0000Evil", "PARTY", "Mom")
    local notices = {}

    for _, notice in ipairs(h.raidNotices) do
        notices[#notices + 1] = notice.text
    end
    truthy(table.concat(notices, "\n"):find("Mom Doe's spree ended at 7 kills by Cid.", 1, true))
    truthy(notices[#notices] == "Mom Doe's spree ended at 7 kills.", "a name with markup is dropped: " .. notices[#notices])
end)

test("your own blow is no one's kill", function()
    local h, addon = Grouped()

    h:SetTarget(Enemy("Bob"))
    h:MeterFight({ duration = 5, sources = { KilledBy(h.player, { name = "Goblin Sapper Charge", spellID = 13241 }) } })
    eq(addon.State:Get("death.killerKind"), "self")
    eq(Card(h), nil)
    local me = (h.player.name .. " " .. h.player.surname)

    eq(People(addon):Field(me, "deaths"), 0)
    eq(People(addon):Field(Key(h, "Bob"), "deaths"), 0)
end)

test("a recap that comes too late is set aside, not given to your next death", function()
    local h, addon = Grouped()

    h:EnterCombat()
    h:Fire("PLAYER_DEAD")
    h:Advance(3) -- given up: unknown
    eq(addon.State:Get("death.attributed"), 1)
    eq(addon.State:Get("death.killer"), "")
    h:MeterAdd(KilledBy(Enemy("Bob"))) -- the first death's recap, late
    h:LeaveCombat()
    eq(People(addon):Field(Key(h, "Bob"), "deaths"), 0, "a late recap counts for no one")
    falsy(addon.Events.Frame:IsEventRegistered("DAMAGE_METER_COMBAT_SESSION_UPDATED"))
    h:Fire("PLAYER_DEAD") -- a fall, out of combat: no new meter session, no new recap
    h:Advance(3)
    eq(addon.State:Get("death.attributed"), 2)
    eq(addon.State:Get("death.killer"), "", "the fall isn't Bob's")
    eq(People(addon):Field(Key(h, "Bob"), "deaths"), 0)
end)

test("a death inside the late window takes its own recap, not the death before's", function()
    local h, addon = Grouped()

    h:EnterCombat()
    h:Fire("PLAYER_DEAD")
    h:Advance(3) -- the first death gives up: unknown
    h:Advance(7)
    h:Fire("PLAYER_DEAD") -- a second death, still in the first one's late window
    h:MeterAdd(KilledBy(Enemy("Bob")))   -- the first death's recap, late
    h:MeterAdd(KilledBy(Enemy("Alice"))) -- the second death's
    eq(addon.State:Get("death.attributed"), 2)
    eq(addon.State:Get("death.killer"), "Alice Doe")
    eq(People(addon):Field(Key(h, "Bob"), "deaths"), 0, "the late recap counts for no one")
    h:LeaveCombat()
    h:Fire("PLAYER_DEAD") -- a fall, with no recap of its own
    h:Advance(3)
    eq(addon.State:Get("death.attributed"), 3)
    eq(addon.State:Get("death.killer"), "", "nobody's recap is left over for it")
end)

test("two deaths before either recap lands each get their own killer, in order", function()
    local h, addon = Grouped()
    local killers = {}

    addon.State:Watch({ "death.attributed" }, function(state) killers[#killers + 1] = state:Get("death.killer") end, true)
    h:EnterCombat()
    h:Fire("PLAYER_DEAD")
    h:Advance(1)
    h:Fire("PLAYER_DEAD")
    h:MeterAdd(KilledBy(Enemy("Bob")))
    h:MeterAdd(KilledBy(Enemy("Alice")))
    eq(table.concat(killers, ","), "Bob Doe,Alice Doe")
end)

test("an attacker the recap hides is unknown: the card asks about the suspect", function()
    local h, addon = Grouped()
    local bob = Enemy("Bob")

    h:SetTarget(bob)
    h:MeterFight({ duration = 5, sources = { { unit = "player", death = { events = {
        { event = "SPELL_DAMAGE", spellId = 8676, spellName = "Ambush", amount = 700, hideCaster = true,
            sourceName = h:FullName(bob), sourceGUID = h:GUID(bob) },
    } } } } })
    eq(addon.State:Get("death.killer"), "")
    truthy(Card(h):find("Slain by Bob Doe?", 1, true), Card(h))
end)

-- Blizzard_DeathRecap.lua guards its damage line with "if elementData.amount": a recap event may
-- have no amount.
test("a killing blow the recap gives no amount for names the killer without a damage line", function()
    local h, addon = Grouped()
    local bob = Enemy("Bob")

    h:MeterFight({ duration = 5, sources = { { unit = "player", death = { events = {
        { event = "SPELL_INSTAKILL", spellId = 8676, spellName = "Ambush", sourceName = Key(h, "Bob"),
            sourceGUID = h:GUID(bob), sourceFlags = 0x548 },
    } } } } })
    eq(addon.State:Get("death.killer"), "Bob Doe")
    eq(addon.State:Get("death.killerDamage"), 0)
    local text = Card(h)

    truthy(text:find("Slain by Bob Doe\nKrew 0 : 1 Bob Doe.", 1, true), text)
end)

test("the recap is read again shortly after the death, even without a meter update", function()
    local h, addon = Grouped()

    h:EnterCombat()
    h:SetMeterAvailable(false, "")
    h:Fire("PLAYER_DEAD")
    h:MeterAdd(KilledBy(Enemy("Bob")))
    h:SetMeterAvailable(true, "")
    eq(addon.State:Get("death.killer"), "", "no meter update came after it was back")
    h:Advance(1)
    eq(addon.State:Get("death.killer"), "Bob Doe")
end)
