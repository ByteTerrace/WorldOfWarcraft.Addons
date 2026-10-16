-- Warband: guild wars, rivalry records, nameplate badges and the nearby-enemies window.

local Kit = use("toolkit")

local Card = Kit.Card
local Enemy = Kit.Enemy
local Grouped = Kit.Grouped
local Key = Kit.Key
local Load = Kit.Load
local Notices = Kit.Notices
local Receive = Kit.Receive
local Sent = Kit.Sent

local function Collection(addon, name)
    return addon.Modules.Warband.Records[name]
end

test("war on your target's guild makes every member an enemy of the Krew, and tells the Krew", function()
    local h, addon = Grouped()

    h:SetTarget(Enemy("Bob", { guild = "Knights of Light" }))
    h:Slash("/tlk war")
    local guild = ("Knights of Light-" .. h.env.GetNormalizedRealmName())

    truthy(Collection(addon, "wars"):Has(guild))
    h:Advance(3)
    eq(Sent(h, "WAR")[1], "WAR:" .. guild)
    h:AddNamePlate(Enemy("Cara", { guild = "Knights of Light" }))
    truthy(Notices(h):find("At war:", 1, true), Notices(h))
    truthy(Notices(h):find("<Knights of Light>", 1, true))
end)

test("a guild showing up in numbers alerts once, not once per member", function()
    local h = Grouped()

    h:Slash("/tlk war Knights of Light")

    for i = 1, 4 do
        h:AddNamePlate(Enemy("Knight" .. i, { guild = "Knights of Light" }))
    end

    eq(#h.raidNotices, 1)
end)

test("making peace ends the war, for the Krew too", function()
    local h, addon = Grouped()

    h:Slash("/tlk war Knights of Light")
    h:Slash("/tlk peace knights of light")
    eq(Collection(addon, "wars"):Count(), 0)
    h:Advance(3)
    eq(#Sent(h, "PEACE"), 1)
end)

test("a Krew war declaration arrives with a card; bad guild names are ignored", function()
    local h, addon = Grouped()

    Receive(h, "Mom", "WAR", "Knights of Light-Realm")
    truthy(Card(h):find("Mom Doe declared war on <Knights of Light>", 1, true), Card(h))
    Receive(h, "Mom", "WAR", "Bad|cffGuild-Realm")
    Receive(h, "Mom", "WAR", "NoRealm")
    eq(Collection(addon, "wars"):Count(), 1)
end)

test("kills and deaths against a guild at war are tallied", function()
    local h, addon = Grouped()

    h:Slash("/tlk war Knights of Light")
    h:AddNamePlate(Enemy("Cara", { guild = "Knights of Light" }))
    h:HonorKill(Key(h, "Cara"), "Private", 12)
    local guild = ("Knights of Light-" .. h.env.GetNormalizedRealmName())

    eq(Collection(addon, "wars"):Field(guild, "kills"), 1)
    Receive(h, "Mom", "GRUDGE", Key(h, "Cara"), "ROGUE", "60", "Alliance", "1")
    eq(Collection(addon, "wars"):Field(guild, "deaths"), 1, "Cara killed Mom: the guild's tally too")
end)

test("a war's tally changing repaints no badge whose standing stays the same", function()
    local h = Load()

    h:Slash("/tlk war Knights of Light")
    h:AddNamePlate(Enemy("Cara", { guild = "Knights of Light" }))
    h:AddNamePlate(Enemy("Dan", { guild = "Knights of Light" }))
    h:ResetCalls()
    h:HonorKill(Key(h, "Cara"), "Private", 12)
    eq(h:CountCalls("SetTexture") + h:CountCalls("Show"), 0)
end)

test("identifying guilded players on your own realm asks your realm once", function()
    local h = Load()

    h.apiCalls = {}

    for i = 1, 10 do
        h:AddNamePlate(Enemy("Foe" .. i, { guild = "Knights of Light" }))
    end

    eq(h:CountApiCalls("GetNormalizedRealmName"), 1)
end)

test("every enemy you meet gets a record: sightings, where, and the score", function()
    local h, addon = Load()

    h:SetLocation({ subZone = "Tarren Mill", zone = "Hillsbrad Foothills" })
    local plate = h:AddNamePlate(Enemy())

    h:RemoveNamePlate(plate)
    h:Advance(90)
    h:AddNamePlate(Enemy())
    local people = Collection(addon, "people")
    local key = Key(h, "Bob")

    eq(people:Field(key, "sightings"), 2, "once per minute at most")
    eq(people:Field(key, "zone"), "Hillsbrad Foothills")
    h:Slash("/tlk rival Bob Doe")
    local printed = table.concat(h.printed, "\n")

    truthy(printed:find("Krew 0 : 0 Bob Doe. Seen 2 times, last in Hillsbrad Foothills.", 1, true), printed)
end)

test("the first sighting of someone marked by name counts, with where, however soon it comes", function()
    local h, addon = Load()

    h:SetLocation({ subZone = "Tarren Mill", zone = "Hillsbrad Foothills" })
    h:Slash("/tlk mark Bob Doe")
    h:Slash("/tlk glory Cara Doe")
    h:Advance(5)
    h:AddNamePlate(Enemy())
    h:AddNamePlate(Enemy("Cara", { canAttack = false, faction = "Horde", isEnemy = false }))
    local people = Collection(addon, "people")

    eq(people:Field(Key(h, "Bob"), "sightings"), 1, "the mark made the record; the sighting still counts")
    eq(people:Field(Key(h, "Bob"), "zone"), "Hillsbrad Foothills")
    eq(people:Field(Key(h, "Cara"), "sightings"), 1, "a champion seen nearby too")
end)

test("the tooltip shows the record of anyone the Krew has fought", function()
    local h = Load()
    local plate = h:AddNamePlate(Enemy())

    h:HonorKill(Key(h, "Bob"), "Private", 12)
    h:ShowUnitTooltip(plate)
    local lines = table.concat(Harness.State(h.env.GameTooltip).lines, "\n")

    truthy(lines:find("Krew 1 : 0 Bob Doe - seen 1 times", 1, true), lines)
end)

local function Badge(h, plate)
    local frame = h.env.C_NamePlate.GetNamePlateForUnit(plate)

    for _, child in ipairs({ frame:GetChildren() }) do
        -- Blizzard's UnitFrame rides on the plate too, so the badge is the child with an Icon.
        if rawget(child, "Icon") then
            return child
        end
    end
end

test("a marked enemy's nameplate wears a skull; a mark lifted changes it; strangers wear nothing", function()
    local h = Load()

    h:Slash("/tlk mark Bob Doe")
    local plate = h:AddNamePlate(Enemy())
    local badge = Badge(h, plate)

    truthy(badge and badge:IsShown())
    truthy(Harness.State(badge.Icon).texture:find("RaidTargetingIcon_8", 1, true))
    h:Slash("/tlk unmark Bob Doe")
    truthy(Harness.State(badge.Icon).texture:find("RaidTargetingIcon_7", 1, true), "a grudge now: the cross")
    h:Slash("/tlk forgive Bob Doe")
    falsy(badge:IsShown())
    local stranger = h:AddNamePlate(Enemy("Stranger"))

    eq(Badge(h, stranger), nil)
end)

test("a badge leaves with its nameplate and a recycled plate doesn't keep it", function()
    local h = Load()

    h:Slash("/tlk mark Bob Doe")
    local plate = h:AddNamePlate(Enemy())
    local badge = Badge(h, plate)

    h:RemoveNamePlate(plate)
    falsy(badge:IsVisible())
    local again = h:AddNamePlate(Enemy("Stranger"))

    eq(again, plate, "the same token and plate, recycled")
    falsy(badge:IsVisible(), "a stranger on the recycled plate wears no badge")
end)

test("a creature's nameplate costs the badges nothing", function()
    local h = Load()

    h.apiCalls = {}
    local plate = h:AddNamePlate({ canAttack = true, name = "Kobold" })

    h:RemoveNamePlate(plate)
    eq(h:CountApiCalls("C_NamePlate.GetNamePlateForUnit"), 0)
end)

test("a ledger change repaints the badges on screen without reading anyone again", function()
    local h = Load()
    local plates = {}

    for i = 1, 10 do
        plates[i] = h:AddNamePlate(Enemy("Foe" .. i))
    end

    h.apiCalls = {}
    h:Slash("/tlk mark Foe3 Doe")
    eq(h:CountApiCalls("UnitClass"), 0, "no plate is read again")
    eq(h:CountApiCalls("C_NamePlate.GetNamePlateForUnit"), 0)
    local badge = Badge(h, plates[3])

    truthy(badge and badge:IsShown(), "the marked one wears the skull")
    eq(Badge(h, plates[4]), nil, "the others wear nothing")
end)

test("badges switched off leave no badge and no events", function()
    local h, addon = Load()

    addon.State:Set("Badges.enabled", false)
    h:Slash("/tlk mark Bob Doe")
    local plate = h:AddNamePlate(Enemy())

    eq(Badge(h, plate), nil)
    falsy(addon.Events.Frame:IsEventRegistered("NAME_PLATE_UNIT_REMOVED"))
end)

test("badges switched off hide, and switched on again find the plates on screen", function()
    local h, addon = Load()

    h:Slash("/tlk mark Bob Doe")
    local plate = h:AddNamePlate(Enemy())
    local badge = Badge(h, plate)

    truthy(badge:IsShown())
    addon.State:Set("Badges.enabled", false)
    falsy(badge:IsShown(), "switched off")
    addon.State:Set("Badges.enabled", true)
    truthy(badge:IsShown(), "the plate already on screen wears its skull again")
    h:Slash("/tlk unmark Bob Doe")
    truthy(Harness.State(badge.Icon).texture:find("RaidTargetingIcon_7", 1, true), "and keeps up with the ledger")
end)

local function Window(h)
    return rawget(h.env, "TheLanKrewToolKitRadar")
end

local function Rows(h)
    local names = {}

    for _, row in ipairs(Window(h).Rows) do
        if row:IsShown() then
            names[#names + 1] = (Reveal(Harness.State(row.Name).text) .. " | " .. Reveal(Harness.State(row.Detail).text))
        end
    end

    return names
end

test("enemies you see are listed, marked ones first, and the list empties after two minutes", function()
    local h, addon = Load()

    h:Slash("/tlk mark Cara Doe")
    h:AddNamePlate(Enemy("Bob"))
    truthy(Window(h):IsShown(), "the first sighting shows the window at once")
    h:Advance(1)
    h:AddNamePlate(Enemy("Cara", { classFile = "MAGE", level = 58 }))
    -- The window redraws on its one-second tick, so the next tick draws her.
    h:Advance(1)
    local rows = Rows(h)

    eq(rows[1], "Cara Doe | 58 - 1s")
    eq(rows[2], "Bob Doe | 60 - 2s")
    h:Advance(125)
    falsy(Window(h):IsShown())
    h:AddNamePlate(Enemy("Dan"))
    truthy(Window(h):IsShown())
    addon.State:Set("Radar.enabled", false)
    falsy(Window(h):IsShown(), "switched off, the window goes")
end)

test("an enemy who leaves the list before their turn to be shared isn't shared", function()
    local h = Grouped()
    -- Long names: three to a message, one message every ten seconds, so the last wait past the two minutes they stay
    -- listed.
    local total = 45

    for i = 1, total do
        h:SetMouseover(Enemy(("B"):rep(53) .. string.char(64 + math.ceil(i / 26)) .. string.char((96 + ((i - 1) % 26)) + 1)))
    end

    h:Advance(130)
    local shared = 0

    for _, message in ipairs(Sent(h, "NEARBY")) do
        local _, count = message:gsub(";ROGUE;60", "")

        shared = (shared + count)
    end

    truthy((shared > 0) and (shared < total), shared)
    falsy(Window(h):IsShown(), "everyone has left the list")
    local sent = #Sent(h, "NEARBY")

    h:Advance(60)
    eq(#Sent(h, "NEARBY"), sent, "the rest are dropped, not sent late")
end)

test("new enemies are shared with the Krew in one batch; Krew reports join the list", function()
    local h = Grouped()

    h:AddNamePlate(Enemy("Bob"))
    h:AddNamePlate(Enemy("Cara", { classFile = "MAGE" }))
    eq(#Sent(h, "NEARBY"), 0, "batched")
    h:Advance(11)
    local nearby = Sent(h, "NEARBY")

    eq(#nearby, 1)
    truthy(nearby[1]:find(Key(h, "Bob") .. ";ROGUE;60", 1, true), nearby[1])
    truthy(nearby[1]:find(Key(h, "Cara") .. ";MAGE;60", 1, true), nearby[1])
    h:Advance(30)
    eq(#Sent(h, "NEARBY"), 1, "nothing new, nothing sent")
    Receive(h, "Mom", "NEARBY", "Dan Doe;WARRIOR;60", "bad|key;X;1")
    h:Advance(1)
    local rows = table.concat(Rows(h), "\n")

    truthy(rows:find("Dan Doe | 60 - 1s - Mom Doe", 1, true), rows)
    falsy(rows:find("bad", 1, true))
end)

test("a Krew report of a guild at war's member shows them at war, by the guild their record holds", function()
    local h = Grouped()

    h:SetTarget(Enemy("Dan", { guild = "Knights of Light" }))
    h:Slash("/tlk war")
    h:SetTarget(nil)
    -- Dan's record holds his guild; the list forgets him after two minutes.
    h:Advance(130)
    Receive(h, "Mom", "NEARBY", Key(h, "Dan") .. ";WARRIOR;60")
    h:Advance(1)
    local icon = Window(h).Rows[1].Icon:GetTexture()

    eq(icon, h.ns.Warband.Icons.war, "the war's icon, though the report names no guild")
end)

test("right-click a row for the Krew's choices", function()
    local h, addon = Load()

    h:AddNamePlate(Enemy("Bob", { guild = "Knights of Light" }))
    h:Click(Window(h).Rows[1], "RightButton")
    local menu = h:OpenContextMenu()

    menu:Click("Mark for death")
    eq(Collection(addon, "ledger"):Field(Key(h, "Bob"), "kind"), "mark")
    h:Click(Window(h).Rows[1], "RightButton")
    h:OpenContextMenu():Click("War on <Knights of Light>")
    eq(Collection(addon, "wars"):Count(), 1)
end)

test("the window remembers where you drag it", function()
    local h, addon = Load()

    h:AddNamePlate(Enemy())
    h:Drag(Window(h), -100, 50)
    local x = addon.State:Get("Radar.x")
    local y = addon.State:Get("Radar.y")

    eq(x, -160)
    eq(y, 170)
    h:Relog(60)
    h:AddNamePlate(Enemy())
    local _, _, _, px, py = Window(h):GetPoint(1)

    eq(px, -160)
    eq(py, 170)
end)

test("a redraw touches only the rows in use", function()
    local h = Load()

    h:AddNamePlate(Enemy("Bob"))
    local unused = Window(h).Rows[3]

    local function Calls()
        local total = 0

        for _, count in pairs(Harness.State(unused).calls) do total = (total + count) end

        return total
    end

    local before = Calls()

    h:AddNamePlate(Enemy("Cara"))
    -- Five seconds on the ticker are five redraws.
    h:Advance(5)
    eq(Calls(), before, "a row nobody uses isn't touched")
end)

test("a typed guild in any case means the guild you've seen", function()
    local h, addon = Grouped()

    h:AddNamePlate(Enemy("Cara", { guild = "Knights of Light" }))
    h:Slash("/tlk war knights of light")
    truthy(Collection(addon, "wars"):Has("Knights of Light-" .. h.env.GetNormalizedRealmName()))
    h:Slash("/tlk war red dawn")
    truthy(Collection(addon, "wars"):Has("Red Dawn-" .. h.env.GetNormalizedRealmName()), "an unseen guild, capitalized")
end)

test("nearby enemies go out in messages that fit, however many there are", function()
    local h = Grouped()

    h:SetLocation({ subZone = ("S"):rep(60), zone = ("Z"):rep(60) })
    local names = {}

    for i = 1, 8 do
        names[i] = (("Aaaaaaaaaaaaaaaaaaaaaaaaaaaaa"):sub(1, 20 + i) .. string.char(96 + i))
        h:AddNamePlate(Enemy(names[i]))
    end

    h:Advance(25)
    local nearby = table.concat(Sent(h, "NEARBY"), "\n")

    eq(#Sent(h, "NEARBY"), 2)

    for _, message in ipairs(Sent(h, "NEARBY")) do
        truthy(#message <= 255, #message)
    end

    for _, name in ipairs(names) do
        truthy(nearby:find(Key(h, name) .. ";ROGUE;60", 1, true), name)
    end
end)

-- Every call on the radar's window, its title and its rows' regions, summed.
local function RadarCalls(h)
    local window = Window(h)
    local total = 0
    local widgets = { window, window.Title }

    for _, row in ipairs(window.Rows) do
        widgets[#widgets + 1], widgets[#widgets + 2] = row, row.Icon
        widgets[#widgets + 1], widgets[#widgets + 2] = row.Name, row.Detail
    end

    for _, widget in ipairs(widgets) do
        for _, count in pairs(Harness.State(widget).calls) do
            total = (total + count)
        end
    end

    return total
end

test("a sighting only notes the enemy; a tick sets only the texts that moved", function()
    local h = Load()

    h:AddNamePlate(Enemy("Bob"))
    h:Advance(1)
    h:AddNamePlate(Enemy("Cara"))
    h:Advance(1)
    local dan = Enemy("Dan")

    -- Dan is the most recent, so seeing him again keeps the order.
    h:AddNamePlate(dan)
    h:Advance(1)
    h:ResetCalls()
    h:SetMouseover(dan)
    eq(RadarCalls(h), 0, "the next tick draws it")
    h:Advance(1)
    eq(RadarCalls(h), 2, "Bob's and Cara's ago texts; Dan's reads 1s again, so it isn't set")
    eq(h:CountCalls("SetText"), 2)
end)

test("full rivalry records make room a hundred strangers at a time, keeping ledger people", function()
    local h, addon = Load()
    local people = Collection(addon, "people")

    h:Slash("/tlk grudge Old Doe")

    for i = 1, 999 do
        people:Set("Foe" .. i .. " Doe", { seen = i })
    end

    people:Set("Old Doe", { seen = 0 })
    eq(people:Count(), 1000)
    local keep = people.Keep
    local calls = 0

    people.Keep = function(key)
        calls = (calls + 1)

        return keep(key)
    end

    for i = 1, 10 do
        h:RemoveNamePlate(h:AddNamePlate(Enemy("New" .. i)))
    end

    truthy(calls <= 1000, calls .. " keep checks for 10 new faces")
    eq(people:Count(), 910)
    truthy(people:Has("Old Doe"), "the grudge's record stays")
    falsy(people:Has("Foe1 Doe"))
end)

test("in the controller interface style, a radar row opens no Blizzard menu", function()
    local h = Load()

    h.interfaceStyle = h.env.Enum.InputDeviceInterfaceType.Gamepad
    h:AddNamePlate(Enemy("Bob"))
    h:Click(Window(h).Rows[1], "RightButton")
    eq(h.contextMenu, nil, "the controller UI would show it tainted")
end)
