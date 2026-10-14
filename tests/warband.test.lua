-- Warband: the ledger of grudges, marks and champions, sightings, vengeance, rallies and intel.

local Prefix = "TLKKrew1"

local function Load(saved)
    local h = Harness.New({ saved = saved or {} })
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

-- A player's key: Forever's full name (every test player's surname is the harness default).
local function Key(h, name)
    return name .. " " .. Harness.DEFAULT_SURNAME
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
        if message.prefix == Prefix and message.message:find("^" .. kind .. ":") then
            found[#found + 1] = message.message
        end
    end
    return found
end

local function Receive(h, sender, kind, ...)
    h:ReceiveAddonMessage(Prefix, kind .. ":" .. table.concat({ ... }, "\t"), "PARTY", sender)
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
    h:Slash("/tlk grudge Bob Doe")
    h:Relog(60)
    truthy(Ledger(h.ns.Addon):Has(Key(h, "Bob")), "kept under the typed full name")
    eq(Ledger(h.ns.Addon):Field(Key(h, "Bob"), "kind"), "grudge")
end)

test("names are matched ignoring case, and forgiving removes them", function()
    local h, addon = Load()
    h:Slash("/tlk glory Cara Doe")
    truthy(Ledger(addon):Has(Key(h, "Cara")))
    h:Slash("/tlk forgive cara doe")
    falsy(Ledger(addon):Has(Key(h, "Cara")))
end)

test("a mark can be lifted; the enemy stays a grudge", function()
    local h, addon = Grouped()
    h:Slash("/tlk mark Bob Doe")
    h:Slash("/tlk unmark Bob Doe")
    truthy(Ledger(addon):Has(Key(h, "Bob")))
    eq(Ledger(addon):Field(Key(h, "Bob"), "kind"), "grudge")
    h:Advance(3)
    eq(#Sent(h, "UNMARK"), 1)
end)

test("a marked enemy's nameplate raises one alert and one Krew report, and never a raid icon", function()
    local h, addon = Grouped()
    h:Slash("/tlk mark Bob Doe")
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
    h:Slash("/tlk glory Cara Doe")
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
    h:Slash("/tlk mark Bob Doe")
    Receive(h, "Mom", "SIGHT", Key(h, "Bob"), "Hillsbrad Foothills", "Tarren Mill", "0")
    truthy(Notices(h):find("Mom Doe spotted Bob Doe", 1, true), Notices(h))
    truthy(Notices(h):find("Tarren Mill (Hillsbrad Foothills)", 1, true))
    h:AddNamePlate(Enemy())
    h:Advance(3)
    eq(#Sent(h, "SIGHT"), 0, "Mom already told the Krew")
end)

test("dying to the enemy you targeted asks for a grudge; a click holds it with the Krew", function()
    local h, addon = Grouped()
    h:SetTarget(Enemy())
    h:Die()
    eq(Card(h), nil, "waits for the death recap")
    h:Advance(3) -- none came: ask about the suspect
    local text, card = Card(h)
    truthy(text and text:find("Slain by Bob Doe?", 1, true), text)
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
    h:Slash("/tlk grudge Bob Doe")
    h:HonorKill(Key(h, "Bob"), "Private", 12)
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
    h:HonorKill(Key(h, "Stranger"), "Private", 12)
    eq(Ledger(addon):Count(), 0)
    eq(People(addon):Field(Key(h, "Stranger"), "kills"), 1)
    eq(Card(h), nil)
    h:Advance(3)
    eq(#Sent(h, "KILL"), 0)
end)

test("a Krew member's death is the Krew's grudge", function()
    local h, addon = Grouped()
    local key = Key(h, "Bob")
    Receive(h, "Mom", "GRUDGE", key, "ROGUE", "60", "Alliance", "1")
    eq(People(addon):Field(key, "deaths"), 1)
    truthy(Card(h):find("Bob Doe killed Mom Doe!", 1, true), Card(h))
end)

test("a Krew mark joins the ledger with one card, however often it's synced", function()
    local h, addon = Grouped()
    local key = Key(h, "Bob")
    Receive(h, "Mom", "MARK", key, "ROGUE", "60", "Alliance")
    eq(Ledger(addon):Field(key, "by"), "Mom Doe", "the sender's full name")
    local _, card = Card(h)
    h:Click(card, "RightButton")
    Receive(h, "Mom", "MARK", key, "ROGUE", "60", "Alliance")
    eq(Card(h), nil)
end)

test("a joining Krew member hears the marks you placed", function()
    local h = Grouped()
    h:Slash("/tlk mark Bob Doe")
    h:Advance(3)
    local before = #Sent(h, "MARK")
    Receive(h, "Mom", "HELLO", "0.1.0")
    h:Advance(5)
    eq(#Sent(h, "MARK"), before + 1)
end)

test("bad messages are ignored: foreign keys, escape codes, junk numbers", function()
    local h, addon = Grouped()
    local key = Key(h, "Bob")
    Receive(h, "Mom", "MARK", key .. "-Realm", "ROGUE", "60", "Alliance") -- a key never carries a realm
    Receive(h, "Mom", "MARK", "Bob|Hlink|h Doe", "ROGUE", "60", "Alliance")
    Receive(h, "Mom", "GRUDGE", key, "rogue|T", "banana", "Martians", "1")
    eq(Ledger(addon):Count(), 1)
    truthy(Ledger(addon):Has(key), "only the well-formed key")
    eq(People(addon):Field(key, "class"), "")
    eq(People(addon):Field(key, "level"), 0)
    eq(People(addon):Field(key, "faction"), "")
    Receive(h, "Mom", "RALLY", "1", "1", "1", "Hillsbrad|Tinterface\\x|t", "")
    truthy(not Notices(h):find("|T", 1, true), "escape codes never reach the screen")
end)

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

test("a gathering counts the enemies of one place: moving on starts the count over", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Southshore", mapID = 1424, x = 0.5, y = 0.5 })
    for i = 1, 4 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Darrow Hill", mapID = 1424, x = 0.4, y = 0.4 })
    h:AddNamePlate(Enemy("Foe5"))
    h:Advance(3)
    eq(#Sent(h, "INTEL"), 0, "four at Southshore and one at Darrow Hill aren't five at Darrow Hill")
end)

test("a reported gathering costs no zone reads while it lasts; the next place is read afresh", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Southshore", mapID = 1424, x = 0.5, y = 0.5 })
    for i = 1, 6 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    h.apiCalls = {}
    for i = 7, 11 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    eq(h:CountApiCalls("GetSubZoneText") + h:CountApiCalls("GetRealZoneText"), 0, "the place is known")
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Darrow Hill", mapID = 1424, x = 0.4, y = 0.4 })
    for i = 12, 16 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    h:Advance(3)
    local intel = Sent(h, "INTEL")
    eq(#intel, 2)
    truthy(intel[2]:find("Darrow Hill", 1, true), intel[2])
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

test("the right-click menu marks an enemy player", function()
    local h, addon = Load()
    h:SetTarget(Enemy())
    local menu = h:OpenTargetMenu()
    menu:Click("Mark for death")
    eq(Ledger(addon):Field(Key(h, "Bob"), "kind"), "mark")
end)

test("the tooltip shows the ledger", function()
    local h, addon = Load()
    h:Slash("/tlk grudge Bob Doe")
    local plate = h:AddNamePlate(Enemy())
    h:ShowUnitTooltip(plate)
    local lines = table.concat(Harness.State(h.env.GameTooltip).lines, "\n")
    truthy(lines:find("\nGrudge\n", 1, true), lines)
    truthy(lines:find("Krew 0 : 0 Bob Doe", 1, true), lines)
end)

test("switched off, Warband listens to nothing", function()
    local h, addon = Load()
    addon.State:Set("Warband.enabled", false)
    addon.State:Set("Streaks.enabled", false) -- kill streaks read honor kills too
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
        falsy(addon.Events.Frame:IsEventRegistered(event), event)
    end
end)

test("the right-click menu offers glory on a friendly player, by their full name", function()
    local h, addon = Load()
    local menu = h:OpenMenu("MENU_UNIT_PLAYER", { which = "PLAYER", name = "Cara", surname = "Other" })
    menu:Click("Grant glory")
    eq(Ledger(addon):Field("Cara Other", "kind"), "glory")
end)

test("a typed name in any case means who it names", function()
    local h, addon = Grouped()
    h:Slash("/tlk mark cara doe")
    truthy(Ledger(addon):Has("Cara Doe"), "capitalized as the client writes names")
    h:AddNamePlate(Enemy("Cara"))
    truthy(Notices(h):find("Marked for death", 1, true), Notices(h))
    h:AddNamePlate(Enemy("Bob"))
    h:Slash("/tlk grudge BOB DOE")
    eq(Ledger(addon):Field(Key(h, "Bob"), "kind"), "grudge", "the rivalry record's key")
    eq(Ledger(addon):Count(), 2)
    h:Advance(5)
    eq(Sent(h, "GRUDGE")[1], "GRUDGE:" .. Key(h, "Bob") .. "\tROGUE\t60\tAlliance\t0", "with what the record knows")
end)

test("a full ledger refuses newcomers and forgets no one, for you and from the Krew", function()
    local h, addon = Load()
    for i = 1, 300 do
        h:Slash("/tlk grudge Foe" .. i .. " Doe")
    end
    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)
    h:Slash("/tlk mark Bob Doe")
    truthy(h.printed[#h.printed]:find("The ledger is full (300), so Bob Doe isn't on it.", 1, true), h.printed[#h.printed])
    Receive(h, "Mom", "MARK", Key(h, "Cara"), "MAGE", "60", "Alliance")
    eq(Ledger(addon):Count(), 300)
    truthy(Ledger(addon):Has("Foe1 Doe"), "the oldest grudge stays")
    falsy(Ledger(addon):Has(Key(h, "Bob")))
    falsy(Ledger(addon):Has(Key(h, "Cara")))
    eq(Card(h), nil, "no card for a mark the ledger refused")
    h:Advance(5)
    eq(#Sent(h, "MARK"), 0, "a refused mark isn't sent")
    h:Slash("/tlk forgive foe1 doe")
    h:Slash("/tlk mark Bob Doe")
    eq(Ledger(addon):Field(Key(h, "Bob"), "kind"), "mark", "forgiving made room")
end)

test("a nameplate or mouseover reads the unit once", function()
    local h = Grouped()
    h.apiCalls = {}
    h:AddNamePlate(Enemy())
    eq(h:CountApiCalls("UnitName"), 1, "Warband, its badges and the radar share one reading")
    h.apiCalls = {}
    h:SetMouseover(Enemy("Cara", { inCombat = true }))
    eq(h:CountApiCalls("UnitName"), 1, "the sighting and the prime suspect share one reading")
end)

test("mousing over a creature or a friend never asks whether it's fighting", function()
    local h = Grouped()
    h.apiCalls = {}
    h:SetMouseover({ name = "Kobold", canAttack = true, inCombat = true })
    h:SetMouseover({ name = "Pal", isPlayer = true, playerControlled = true })
    eq(h:CountApiCalls("UnitAffectingCombat"), 0)
end)

test("a player's tooltip reuses what the mouseover just read", function()
    local h = Grouped()
    h.apiCalls = {}
    h:SetMouseover(Enemy())
    h:ShowUnitTooltip("mouseover")
    eq(h:CountApiCalls("UnitClass"), 1, "one reading")
    eq(h:CountApiCalls("GetGuildInfo"), 1)
end)

test("nameplates below a gathering never read the zone", function()
    local h = Grouped()
    local plates = {}
    for i = 1, 4 do
        plates[i] = h:AddNamePlate(Enemy("Foe" .. i))
    end
    for i = 1, 4 do
        h:RemoveNamePlate(plates[i])
    end
    h:Advance(5)
    h.apiCalls = {}
    for i = 1, 4 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    eq(h:CountApiCalls("GetSubZoneText"), 0)
end)

test("a gathering the Krew reported shows once, and isn't reported again", function()
    local h = Grouped()
    h:AddMap(1424, { name = "Hillsbrad Foothills", mapType = "Zone" })
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Southshore", mapID = 1424, x = 0.5, y = 0.5 })
    Receive(h, "Mom", "INTEL", "7", "Alliance", "1424", "5000", "5000", "Hillsbrad Foothills", "Southshore")
    local _, card = Card(h)
    h:Click(card, "RightButton")
    Receive(h, "Mom", "INTEL", "8", "Alliance", "1424", "5000", "5000", "Hillsbrad Foothills", "Southshore")
    eq(Card(h), nil, "the Krew already knows")
    for i = 1, 6 do
        h:AddNamePlate(Enemy("Foe" .. i))
    end
    h:Advance(3)
    eq(#Sent(h, "INTEL"), 0, "Mom already told the Krew")
end)

test("counts from the Krew are whole numbers in digits; text holds no control characters", function()
    local h = Grouped()
    for _, count in ipairs({ "0x10", "1e2", "inf", "7.0", "-7", "0" }) do
        Receive(h, "Mom", "INTEL", count, "Alliance", "1424", "5000", "5000", "Hillsbrad Foothills", "Southshore")
    end
    eq(Card(h), nil)
    Receive(h, "Mom", "RALLY", "1", "1", "1", "Hills\7brad", "")
    truthy(Notices(h):find("needs the Krew at somewhere!", 1, true), Notices(h))
end)

test("a burst of Krew members joining hears your marks and wars once; a new group hears them again", function()
    local h = Load()
    h:JoinGroup("party", { "Mom", "Dad", "Sis", "Bro" })
    h:Echo(false)
    for _, name in ipairs({ "Bob", "Cara", "Dan" }) do
        h:Slash("/tlk mark " .. name .. " Doe")
    end
    for _, guild in ipairs({ "Red", "Blue", "Gold" }) do
        h:Slash("/tlk war " .. guild)
    end
    h:Advance(20)
    local marks, wars = #Sent(h, "MARK"), #Sent(h, "WAR")
    for _, name in ipairs({ "Mom", "Dad", "Sis", "Bro" }) do
        Receive(h, name, "HELLO", "0.1.0")
    end
    h:Advance(20)
    eq(#Sent(h, "MARK"), marks + 3, "one sync for the burst")
    eq(#Sent(h, "WAR"), wars + 3)
    h:LeaveGroup()
    h:JoinGroup("party", { "Mom" })
    h:Advance(40)
    Receive(h, "Mom", "HELLO", "0.1.0")
    h:Advance(20)
    eq(#Sent(h, "MARK"), marks + 6, "a new group hears them again")
end)

test("a menu whose surname is secret offers nothing", function()
    local h = Load()
    local menu = h:OpenMenu("MENU_UNIT_PLAYER", { which = "PLAYER", name = "Cara", surname = Secret("Other") })
    eq(menu:Find("Grant glory"), nil)
end)
