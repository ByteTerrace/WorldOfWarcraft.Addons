-- Warband: your marks and wars shared with Krew members who say hello, packed into few messages.

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
local function Key(_, name)
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

test("a joining Krew member hears the marks you placed", function()
    local h = Grouped()
    h:Slash("/tlk mark Bob Doe")
    h:Advance(3)
    eq(#Sent(h, "MARKS"), 0)
    Receive(h, "Mom", "HELLO", "0.1.0")
    h:Advance(5)
    eq(table.concat(Sent(h, "MARKS"), " | "), "MARKS:Bob Doe;;0;", "what the record knows: here, only the name")
end)

test("a Krew member who leaves and comes back hears the marks placed while they were away", function()
    local h = Load()
    h:JoinGroup("party", { "Mom", "Dad" })
    h:Echo(false)
    h:Advance(2)
    Receive(h, "Mom", "HELLO", "0.1.0", "0")
    h:Advance(5)
    h:RemoveMember("Mom")
    h:Slash("/tlk mark Bob Doe")
    h:AddMember("Mom")
    h:Advance(3)
    local before = #Sent(h, "MARKS")
    Receive(h, "Mom", "HELLO", "0.1.0", "0")
    h:Advance(5)
    eq(#Sent(h, "MARKS"), before + 1)
end)

test("a raid's worth of Krew members joining hears your marks and wars once; a new group hears them again", function()
    local h = Load()
    local names = { "Mom", "Dad", "Sis", "Bro", "Aunt", "Uncle" }
    h:JoinGroup("raid", names)
    h:Echo(false)
    for _, name in ipairs({ "Bob", "Cara", "Dan" }) do
        h:Slash("/tlk mark " .. name .. " Doe")
    end
    for _, guild in ipairs({ "Red", "Blue", "Gold" }) do
        h:Slash("/tlk war " .. guild)
    end
    h:Advance(20)
    eq(#Sent(h, "MARKS") + #Sent(h, "WARS"), 0)
    for _, name in ipairs(names) do
        Receive(h, name, "HELLO", "0.1.0")
    end
    h:Advance(30)
    eq(#Sent(h, "MARKS"), 1, "one sync for the burst, so the send queue has room")
    eq(#Sent(h, "WARS"), 1)
    h:LeaveGroup()
    h:JoinGroup("party", { "Mom" })
    h:Advance(40)
    Receive(h, "Mom", "HELLO", "0.1.0")
    h:Advance(20)
    eq(#Sent(h, "MARKS"), 2, "a new group hears them again")
end)

test("a sync packs three marks and three wars into two messages, and a Krew member learns all six", function()
    local h = Grouped()
    for _, name in ipairs({ "Bob", "Cara", "Dan" }) do
        h:SetTarget(Enemy(name))
        h:Slash("/tlk mark")
    end
    for _, guild in ipairs({ "Red", "Blue", "Gold" }) do
        h:Slash("/tlk war " .. guild)
    end
    h:Advance(20)
    local before = #h.addonMessages
    Receive(h, "Mom", "HELLO", "0.1.0", "1")
    h:Advance(10)
    local synced = {}
    for i = before + 1, #h.addonMessages do
        synced[#synced + 1] = h.addonMessages[i].message
    end
    eq(#synced, 2, table.concat(synced, " | "))
    local function Entries(text, kind) -- the message's entries, sorted: marks placed in one second tie
        local entries = {}
        for entry in text:gsub("^" .. kind .. ":", ""):gmatch("[^\t]+") do
            entries[#entries + 1] = entry
        end
        table.sort(entries)
        return table.concat(entries, " | ")
    end
    eq(Entries(synced[1], "MARKS"), "Bob Doe;ROGUE;60;Alliance | Cara Doe;ROGUE;60;Alliance | Dan Doe;ROGUE;60;Alliance",
        "each with what its record knows")
    local realm = h.env.GetNormalizedRealmName()
    eq(Entries(synced[2], "WARS"), ("Blue-%s | Gold-%s | Red-%s"):format(realm, realm, realm))

    local other, otherAddon = Grouped()
    for _, text in ipairs(synced) do
        other:ReceiveAddonMessage(Prefix, text, "PARTY", "Mom")
    end
    for _, name in ipairs({ "Bob", "Cara", "Dan" }) do
        eq(Ledger(otherAddon):Field(Key(other, name), "kind"), "mark", name)
        eq(Ledger(otherAddon):Field(Key(other, name), "by"), "Mom Doe")
        eq(People(otherAddon):Field(Key(other, name), "class"), "ROGUE")
    end
    for _, guild in ipairs({ "Red", "Blue", "Gold" }) do
        truthy(otherAddon.Modules.Warband.Records.wars:Has(guild .. "-" .. realm), guild)
    end
end)

test("marks too long for one message go in as few as fit", function()
    local h = Grouped()
    local names = {}
    for i, letter in ipairs({ "A", "B", "C" }) do
        names[i] = letter .. string.rep("a", 55) -- "Aaaa... Doe": 60 bytes, so an entry is 84
        h:SetTarget(Enemy(names[i], { classFile = "DEATHKNIGHT" }))
        h:Slash("/tlk mark")
    end
    h:Advance(20)
    Receive(h, "Mom", "HELLO", "0.1.0", "1")
    h:Advance(10)
    local sent = Sent(h, "MARKS")
    eq(#sent, 2, "three entries and two tabs make 254 bytes, past the 249 after MARKS:")
    truthy(#sent[1] <= 255 and #sent[2] <= 255)
    local other, otherAddon = Grouped()
    for _, text in ipairs(sent) do
        other:ReceiveAddonMessage(Prefix, text, "PARTY", "Mom")
    end
    for _, name in ipairs(names) do
        eq(Ledger(otherAddon):Field(Key(other, name), "kind"), "mark", name)
    end
end)
