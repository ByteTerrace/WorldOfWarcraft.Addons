-- Warband: the ledger of grudges, marks and champions, sightings, vengeance, rallies and intel.

local PREFIX = "TLKKrew1"

local function Load(saved)
    local h = Harness.new({ saved = saved or {} })
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

-- A group with one friend, so Krew messages go out. Echo off: tests look at what we send.
local function Grouped(saved)
    local h, addon = Load(saved)
    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)
    return h, addon
end

local function Enemy(name, extra)
    local unit = { name = name or "Bob", isPlayer = true, playerControlled = true, canAttack = true, isEnemy = true,
        classFile = "ROGUE", className = "Rogue", level = 60, faction = "Alliance" }
    for key, value in pairs(extra or {}) do unit[key] = value end
    return unit
end

local function Key(h, name)
    return name .. "-" .. h.env.GetNormalizedRealmName()
end

local function Ledger(addon)
    return addon.Modules.Warband.Records.ledger
end

local function People(addon)
    return addon.Modules.Warband.Records.people
end

local function Sent(h, kind)
    local found = {}
    for _, message in ipairs(h.addonMessages) do
        if message.prefix == PREFIX and message.message:find("^" .. kind .. ":") then
            found[#found + 1] = message.message
        end
    end
    return found
end

local function Receive(h, sender, kind, ...)
    h:ReceiveAddonMessage(PREFIX, kind .. ":" .. table.concat({ ... }, "\t"), "PARTY", sender)
end

local function Card(h)
    local card = rawget(h.env, "TheLanKrewToolKitCard")
    if not (card and card:IsShown()) then
        return nil
    end
    return Reveal(Harness.State(card.Title).text) .. "\n" .. Reveal(Harness.State(card.Body).text), card
end

local function Notices(h)
    local texts = {}
    for _, notice in ipairs(h.raidNotices) do
        texts[#texts + 1] = notice.text
    end
    return table.concat(texts, "\n")
end

-- The ledger ----------------------------------------------------------------------------

test("marking your target records it and tells the Krew", function()
    local h, addon = Grouped()
    h:SetTarget(Enemy())
    h:Slash("/tlk mark")
    local key = Key(h, "Bob")
    eq(Ledger(addon):Field(key, "kind"), "mark")
    eq(People(addon):Field(key, "class"), "ROGUE")
    h:Advance(2)
    eq(Sent(h, "MARK")[1], "MARK:" .. key .. "\tROGUE\t60\tAlliance")
end)

test("the ledger is saved with the account", function()
    local h, addon = Load()
    h:Slash("/tlk grudge Bob")
    h:Relog(60)
    eq(Ledger(h.ns.Addon):Field(Key(h, "Bob"), "kind"), "grudge")
end)

test("names are matched ignoring case, and forgiving removes them", function()
    local h, addon = Load()
    h:Slash("/tlk glory Cara")
    h:Slash("/tlk forgive cara")
    falsy(Ledger(addon):Has(Key(h, "Cara")))
end)

test("a mark can be lifted; the enemy stays a grudge", function()
    local h, addon = Grouped()
    h:Slash("/tlk mark Bob")
    h:Slash("/tlk unmark Bob")
    eq(Ledger(addon):Field(Key(h, "Bob"), "kind"), "grudge")
    h:Advance(3)
    eq(#Sent(h, "UNMARK"), 1)
end)

-- Sightings ------------------------------------------------------------------------------

test("a marked enemy's nameplate raises one alert and one Krew report, and never a raid icon", function()
    local h, addon = Grouped()
    h:Slash("/tlk mark Bob")
    local plate = h:AddNamePlate(Enemy())
    truthy(Notices(h):find("Marked for death", 1, true), Notices(h))
    eq(#h.blocked, 0, "no refused SetRaidTarget")
    h:Advance(3)
    eq(#Sent(h, "SIGHT"), 1)
    h:RemoveNamePlate(plate)
    h:AddNamePlate(Enemy())
    eq(#h.raidNotices, 1, "the same person alerts once per cooldown")
    h:Advance(3)
    eq(#Sent(h, "SIGHT"), 1)
end)

test("a champion in a fight asks for aid", function()
    local h = Grouped()
    h:Slash("/tlk glory Cara")
    h:AddNamePlate(Enemy("Cara", { inCombat = true, canAttack = false, isEnemy = false, faction = "Horde" }))
    truthy(Notices(h):find("Aid them", 1, true), Notices(h))
end)

test("strangers raise no alert and join no ledger, but their rivalry record starts", function()
    local h, addon = Grouped()
    h:AddNamePlate(Enemy("Stranger"))
    eq(#h.raidNotices, 0)
    eq(Ledger(addon):Count(), 0)
    eq(People(addon):Field(Key(h, "Stranger"), "sightings"), 1)
end)

test("friendly strangers get no record at all", function()
    local h, addon = Grouped()
    h:AddNamePlate(Enemy("Pal", { canAttack = false, isEnemy = false, faction = "Horde" }))
    eq(People(addon):Count(), 0)
end)

test("a Krew sighting alerts with the place, and stops us repeating it", function()
    local h = Grouped()
    h:Slash("/tlk mark Bob")
    Receive(h, "Mom", "SIGHT", Key(h, "Bob"), "Hillsbrad Foothills", "Tarren Mill", "0")
    truthy(Notices(h):find("Mom spotted Bob", 1, true), Notices(h))
    truthy(Notices(h):find("Tarren Mill (Hillsbrad Foothills)", 1, true))
    h:AddNamePlate(Enemy())
    h:Advance(3)
    eq(#Sent(h, "SIGHT"), 0, "Mom already told the Krew")
end)

-- Grudges and vengeance -----------------------------------------------------------------

test("dying to the enemy you targeted asks for a grudge; a click holds it with the Krew", function()
    local h, addon = Grouped()
    h:SetTarget(Enemy())
    h:Die()
    eq(Card(h), nil, "waits for the death recap")
    h:Advance(3) -- none came: ask about the suspect
    local text, card = Card(h)
    truthy(text and text:find("Slain by Bob?", 1, true), text)
    h:Click(card)
    local key = Key(h, "Bob")
    eq(People(addon):Field(key, "deaths"), 1)
    eq(Ledger(addon):Field(key, "kind"), "grudge")
    h:Advance(3)
    eq(Sent(h, "GRUDGE")[1], "GRUDGE:" .. key .. "\tROGUE\t60\tAlliance\t1")
end)

test("a right-click lets it go", function()
    local h, addon = Grouped()
    h:SetTarget(Enemy())
    h:Die()
    h:Advance(3)
    local _, card = Card(h)
    h:Click(card, "RightButton")
    eq(Ledger(addon):Count(), 0)
end)

test("dying with no enemy player in sight asks nothing", function()
    local h = Grouped()
    h:SetTarget({ name = "Wolf", canAttack = true })
    h:Die()
    h:Advance(3)
    eq(Card(h), nil)
end)

test("an honorable kill on a grudge settles the score, once for the whole Krew", function()
    local h, addon = Grouped()
    h:Slash("/tlk grudge Bob")
    h:HonorKill("Bob", "Private", 12)
    local key = Key(h, "Bob")
    eq(People(addon):Field(key, "kills"), 1)
    truthy(Card(h):find("Vengeance!", 1, true), Card(h))
    h:Advance(3)
    eq(#Sent(h, "KILL"), 1)
    Receive(h, "Mom", "KILL", key)
    eq(People(addon):Field(key, "kills"), 1, "Mom's credit for the same kill doesn't count twice")
end)

test("honorable kills on strangers count in their record, quietly", function()
    local h, addon = Grouped()
    h:HonorKill("Stranger", "Private", 12)
    eq(Ledger(addon):Count(), 0)
    eq(People(addon):Field(Key(h, "Stranger"), "kills"), 1)
    eq(Card(h), nil)
    h:Advance(3)
    eq(#Sent(h, "KILL"), 0)
end)

test("a Krew member's death is the Krew's grudge", function()
    local h, addon = Grouped()
    Receive(h, "Mom", "GRUDGE", "Bob-Realm", "ROGUE", "60", "Alliance", "1")
    eq(People(addon):Field("Bob-Realm", "deaths"), 1)
    truthy(Card(h):find("Bob-Realm killed Mom!", 1, true), Card(h))
end)

-- Marks from the Krew -------------------------------------------------------------------

test("a Krew mark joins the ledger with one card, however often it's synced", function()
    local h, addon = Grouped()
    Receive(h, "Mom", "MARK", "Bob-Realm", "ROGUE", "60", "Alliance")
    eq(Ledger(addon):Field("Bob-Realm", "by"), "Mom")
    local _, card = Card(h)
    h:Click(card, "RightButton")
    Receive(h, "Mom", "MARK", "Bob-Realm", "ROGUE", "60", "Alliance")
    eq(Card(h), nil)
end)

test("a joining Krew member hears the marks you placed", function()
    local h = Grouped()
    h:Slash("/tlk mark Bob")
    h:Advance(3)
    local before = #Sent(h, "MARK")
    Receive(h, "Mom", "HELLO", "0.1.0")
    h:Advance(5)
    eq(#Sent(h, "MARK"), before + 1)
end)

test("bad messages are ignored: foreign keys, escape codes, junk numbers", function()
    local h, addon = Grouped()
    Receive(h, "Mom", "MARK", "no realm", "ROGUE", "60", "Alliance")
    Receive(h, "Mom", "MARK", "Bob|Hlink|h-Realm", "ROGUE", "60", "Alliance")
    Receive(h, "Mom", "GRUDGE", "Bob-Realm", "rogue|T", "banana", "Martians", "1")
    eq(Ledger(addon):Count(), 1)
    eq(People(addon):Field("Bob-Realm", "class"), "")
    eq(People(addon):Field("Bob-Realm", "level"), 0)
    eq(People(addon):Field("Bob-Realm", "faction"), "")
    Receive(h, "Mom", "RALLY", "1", "1", "1", "Hillsbrad|Tinterface\\x|t", "")
    truthy(not Notices(h):find("|T", 1, true), "escape codes never reach the screen")
end)

-- Rally and intel -----------------------------------------------------------------------

test("a rally goes out first, with your position", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Tarren Mill", mapID = 1424, x = 0.5, y = 0.25 })
    h:Slash("/tlk rally")
    h:Advance(2)
    eq(Sent(h, "RALLY")[1], "RALLY:1424\t5000\t2500\tHillsbrad Foothills\tTarren Mill")
    h:Slash("/tlk rally")
    h:Advance(2)
    eq(#Sent(h, "RALLY"), 1, "one call per cooldown")
end)

test("a Krew rally alerts and sets a waypoint", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    Receive(h, "Mom", "RALLY", "1424", "5000", "2500", "Hillsbrad Foothills", "Tarren Mill")
    truthy(Notices(h):find("RALLY!", 1, true))
    truthy(h.waypoint)
    eq(h.waypoint.uiMapID, 1424)
end)

test("rallying needs a group", function()
    local h = Load()
    h:Slash("/tlk rally")
    truthy(h.printed[#h.printed]:find("join a group", 1, true))
end)

test("five enemy players gathering are reported once", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Southshore", mapID = 1424, x = 0.5, y = 0.5 })
    for i = 1, 6 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    h:Advance(3)
    local intel = Sent(h, "INTEL")
    eq(#intel, 1)
    truthy(intel[1]:find("^INTEL:5\tAlliance\t1424\t"), intel[1])
end)

test("Krew intel is a card that sets a waypoint on click", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    Receive(h, "Mom", "INTEL", "7", "Alliance", "1424", "5000", "5000", "Hillsbrad Foothills", "Southshore")
    local text, card = Card(h)
    truthy(text:find("7 Alliance players at Southshore", 1, true), text)
    h:Click(card)
    eq(h.waypoint.uiMapID, 1424)
end)

-- Menus, tooltips, and off --------------------------------------------------------------

test("the right-click menu marks an enemy player", function()
    local h, addon = Load()
    h:SetTarget(Enemy())
    local menu = h:OpenTargetMenu()
    menu:Click("Mark for death")
    eq(Ledger(addon):Field(Key(h, "Bob"), "kind"), "mark")
end)

test("the tooltip shows the ledger", function()
    local h, addon = Load()
    h:Slash("/tlk grudge Bob")
    local plate = h:AddNamePlate(Enemy())
    h:ShowUnitTooltip(plate)
    local lines = table.concat(Harness.State(h.env.GameTooltip).lines, "\n")
    truthy(lines:find("\nGrudge\n", 1, true), lines)
    truthy(lines:find("Krew 0 : 0 Bob", 1, true), lines)
end)

test("switched off, Warband listens to nothing", function()
    local h, addon = Load()
    addon.State:Set("Warband.enabled", false)
    addon.State:Set("Streaks.enabled", false) -- kill streaks read honor kills too
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
        falsy(addon.Events.Frame:IsEventRegistered(event), event)
    end
end)

test("the right-click menu offers glory on a friendly player, with their realm", function()
    local h, addon = Load()
    local menu = h:OpenMenu("MENU_UNIT_PLAYER", { which = "PLAYER", name = "Cara", surname = "Other" })
    menu:Click("Grant glory")
    eq(Ledger(addon):Field("Cara-Other", "kind"), "glory")
end)
