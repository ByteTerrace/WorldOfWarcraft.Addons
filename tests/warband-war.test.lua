-- Warband: guild wars, rivalry records, nameplate badges and the nearby-enemies window.

local PREFIX = "TLKKrew1"

local function Load()
    local h = Harness.new()
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

local function Grouped()
    local h, addon = Load()
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

local function Collection(addon, name)
    return addon.Modules.Warband.Records[name]
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

local function Notices(h)
    local texts = {}
    for _, notice in ipairs(h.raidNotices) do
        texts[#texts + 1] = notice.text
    end
    return table.concat(texts, "\n")
end

local function Card(h)
    local card = rawget(h.env, "TheLanKrewToolKitCard")
    if not (card and card:IsShown()) then
        return nil
    end
    return Reveal(Harness.State(card.Title).text) .. "\n" .. Reveal(Harness.State(card.Body).text), card
end

-- Guild wars ----------------------------------------------------------------------------

test("war on your target's guild makes every member an enemy of the Krew, and tells the Krew", function()
    local h, addon = Grouped()
    h:SetTarget(Enemy("Bob", { guild = "Knights of Light" }))
    h:Slash("/tlk war")
    local guild = "Knights of Light-" .. h.env.GetNormalizedRealmName()
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
    truthy(Card(h):find("Mom declared war on <Knights of Light>", 1, true), Card(h))
    Receive(h, "Mom", "WAR", "Bad|cffGuild-Realm")
    Receive(h, "Mom", "WAR", "NoRealm")
    eq(Collection(addon, "wars"):Count(), 1)
end)

test("kills and deaths against a guild at war are tallied", function()
    local h, addon = Grouped()
    h:Slash("/tlk war Knights of Light")
    h:AddNamePlate(Enemy("Cara", { guild = "Knights of Light" }))
    h:HonorKill("Cara", "Private", 12)
    local guild = "Knights of Light-" .. h.env.GetNormalizedRealmName()
    eq(Collection(addon, "wars"):Field(guild, "kills"), 1)
end)

-- Rivalry records -----------------------------------------------------------------------

test("every enemy you meet gets a record: sightings, where, and the score", function()
    local h, addon = Load()
    h:SetLocation({ zone = "Hillsbrad Foothills", subZone = "Tarren Mill" })
    local plate = h:AddNamePlate(Enemy())
    h:RemoveNamePlate(plate)
    h:Advance(90)
    h:AddNamePlate(Enemy())
    local people, key = Collection(addon, "people"), Key(h, "Bob")
    eq(people:Field(key, "sightings"), 2, "once per minute at most")
    eq(people:Field(key, "zone"), "Hillsbrad Foothills")
    h:Slash("/tlk rival Bob")
    local printed = table.concat(h.printed, "\n")
    truthy(printed:find("Krew 0 : 0 Bob. Seen 2 times, last in Hillsbrad Foothills.", 1, true), printed)
end)

test("the tooltip shows the record of anyone the Krew has fought", function()
    local h = Load()
    local plate = h:AddNamePlate(Enemy())
    h:HonorKill("Bob", "Private", 12)
    h:ShowUnitTooltip(plate)
    local lines = table.concat(Harness.State(h.env.GameTooltip).lines, "\n")
    truthy(lines:find("Krew 1 : 0 Bob - seen 1 times", 1, true), lines)
end)

test("ledger people are never evicted from the records", function()
    local h, addon = Load()
    h:Slash("/tlk grudge Bob")
    local people = Collection(addon, "people")
    truthy(people.Keep(Key(h, "Bob")))
    falsy(people.Keep(Key(h, "Stranger")))
end)

-- Nameplate badges ----------------------------------------------------------------------

local function Badge(h, plate)
    local frame = h.env.C_NamePlate.GetNamePlateForUnit(plate)
    for _, child in ipairs({ frame:GetChildren() }) do
        if rawget(child, "Icon") then -- Blizzard's UnitFrame rides on the plate too
            return child
        end
    end
end

test("a marked enemy's nameplate wears a skull; a mark lifted changes it; strangers wear nothing", function()
    local h = Load()
    h:Slash("/tlk mark Bob")
    local plate = h:AddNamePlate(Enemy())
    local badge = Badge(h, plate)
    truthy(badge and badge:IsShown())
    truthy(Harness.State(badge.Icon).texture:find("RaidTargetingIcon_8", 1, true))
    h:Slash("/tlk unmark Bob")
    truthy(Harness.State(badge.Icon).texture:find("RaidTargetingIcon_7", 1, true), "a grudge now: the cross")
    h:Slash("/tlk forgive Bob")
    falsy(badge:IsShown())
    local stranger = h:AddNamePlate(Enemy("Stranger"))
    eq(Badge(h, stranger), nil)
end)

test("a badge leaves with its nameplate and a recycled plate doesn't keep it", function()
    local h = Load()
    h:Slash("/tlk mark Bob")
    local plate = h:AddNamePlate(Enemy())
    local badge = Badge(h, plate)
    h:RemoveNamePlate(plate)
    falsy(badge:IsVisible())
    local again = h:AddNamePlate(Enemy("Stranger"))
    eq(again, plate, "the same token and plate, recycled")
    falsy(badge:IsVisible(), "a stranger on the recycled plate wears no badge")
end)

test("badges switched off leave no badge and no events", function()
    local h, addon = Load()
    addon.State:Set("Badges.enabled", false)
    h:Slash("/tlk mark Bob")
    local plate = h:AddNamePlate(Enemy())
    eq(Badge(h, plate), nil)
    falsy(addon.Events.Frame:IsEventRegistered("NAME_PLATE_UNIT_REMOVED"))
end)

-- The nearby-enemies window -------------------------------------------------------------

local function Window(h)
    return rawget(h.env, "TheLanKrewToolKitRadar")
end

local function Rows(h)
    local names = {}
    for _, row in ipairs(Window(h).Rows) do
        if row:IsShown() then
            names[#names + 1] = Reveal(Harness.State(row.Name).text) .. " | " .. Reveal(Harness.State(row.Detail).text)
        end
    end
    return names
end

test("enemies you see are listed, marked ones first, and the list empties after two minutes", function()
    local h = Load()
    h:Slash("/tlk mark Cara")
    h:AddNamePlate(Enemy("Bob"))
    h:Advance(1)
    h:AddNamePlate(Enemy("Cara", { classFile = "MAGE", level = 58 }))
    truthy(Window(h):IsShown())
    local rows = Rows(h)
    eq(rows[1], "Cara | 58 - 0s")
    eq(rows[2], "Bob | 60 - 1s")
    h:Advance(125)
    falsy(Window(h):IsShown())
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
    Receive(h, "Mom", "NEARBY", "Hillsbrad Foothills", "Southshore", "Dan-Realm;WARRIOR;60", "bad|key;X;1")
    local rows = table.concat(Rows(h), "\n")
    truthy(rows:find("Dan-Realm | 60 - 0s - Mom", 1, true), rows)
    falsy(rows:find("bad", 1, true))
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
    local x, y = addon.State:Get("Radar.x"), addon.State:Get("Radar.y")
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
        for _, count in pairs(Harness.State(unused).calls) do total = total + count end
        return total
    end
    local before = Calls()
    h:AddNamePlate(Enemy("Cara"))
    h:Advance(5) -- five redraws on the ticker
    eq(Calls(), before, "a row nobody uses isn't touched")
end)
