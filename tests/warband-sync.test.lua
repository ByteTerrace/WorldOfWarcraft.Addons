-- Warband: your marks and wars shared with Krew members who say hello, packed into few messages.

local Kit = use("toolkit")

local Enemy = Kit.Enemy
local Grouped = Kit.Grouped
local Key = Kit.Key
local Ledger = Kit.Ledger
local Load = Kit.Load
local People = Kit.People
local Prefix = Kit.Prefix
local Receive = Kit.Receive
local Sent = Kit.Sent

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

    -- Entries returns the message's entries sorted, since marks placed in one second tie.
    local function Entries(text, kind)
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
        -- "Aaaa... Doe" is 60 bytes, so an entry is 84.
        names[i] = (letter .. string.rep("a", 55))
        h:SetTarget(Enemy(names[i], { classFile = "DEATHKNIGHT" }))
        h:Slash("/tlk mark")
    end

    h:Advance(20)
    Receive(h, "Mom", "HELLO", "0.1.0", "1")
    h:Advance(10)
    local sent = Sent(h, "MARKS")

    eq(#sent, 2, "three entries and two tabs make 254 bytes, past the 249 after MARKS:")
    truthy((#sent[1] <= 255) and (#sent[2] <= 255))
    local other, otherAddon = Grouped()

    for _, text in ipairs(sent) do
        other:ReceiveAddonMessage(Prefix, text, "PARTY", "Mom")
    end

    for _, name in ipairs(names) do
        eq(Ledger(otherAddon):Field(Key(other, name), "kind"), "mark", name)
    end
end)
