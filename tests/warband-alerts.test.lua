-- Warband: the sighting alerts' budget. A brawl's alerts merge into one summary with one sound.

local Kit = use("toolkit")

local Enemy = Kit.Enemy
local Grouped = Kit.Grouped
local Sent = Kit.Sent

local function Sounds(h, kit)
    local count = 0

    for _, sound in ipairs(h.soundKits) do
        if sound.kit == kit then
            count = (count + 1)
        end
    end

    return count
end

test("five marked enemies at once: one alert now, one summary after, every name told", function()
    local h = Grouped()
    local names = { "Bob", "Cara", "Dan", "Eve", "Finn" }

    for _, name in ipairs(names) do
        h:Slash("/tlk mark " .. name .. " Doe")
    end

    -- Six seconds on, the marks have reached the Krew.
    h:Advance(6)
    local sounds = Sounds(h, h.env.SOUNDKIT.RAID_WARNING)

    for _, name in ipairs(names) do
        h:AddNamePlate(Enemy(name))
    end

    eq(#h.raidNotices, 1, "the first alert shows now")
    eq(h.raidNotices[1].text, "|cffff2020Marked for death:|r Bob Doe (60 Rogue) is here!")
    h:Advance(10)
    eq(#h.raidNotices, 2, "the rest merge into one summary")
    eq(h.raidNotices[2].text, "|cffff20204 more marked for death nearby:|r Cara Doe, Dan Doe, Eve Doe, Finn Doe")
    eq(Sounds(h, h.env.SOUNDKIT.RAID_WARNING) - sounds, 2, "one sound each")
    eq(#Sent(h, "SIGHT"), 5, "the Krew hears of every one")
end)

test("a summary lists marks, grudges, wars and champions in that order, with one sound", function()
    local h = Grouped()

    h:Slash("/tlk mark Bob Doe")
    h:Slash("/tlk glory Dan Doe")
    h:Slash("/tlk grudge Cara Doe")
    h:Slash("/tlk war Knights of Light")
    h:Slash("/tlk mark Finn Doe")
    local warnings, checks = Sounds(h, h.env.SOUNDKIT.RAID_WARNING), Sounds(h, h.env.SOUNDKIT.READY_CHECK)

    h:AddNamePlate(Enemy("Bob"))
    h:AddNamePlate(Enemy("Dan", { canAttack = false, faction = "Horde", inCombat = true, isEnemy = false }))
    h:AddNamePlate(Enemy("Eve", { guild = "Knights of Light" }))
    h:AddNamePlate(Enemy("Cara"))
    h:AddNamePlate(Enemy("Finn"))
    h:Advance(5)
    eq(#h.raidNotices, 2)

    eq(h.raidNotices[2].text, "4 more nearby: |cffff2020Marked for death:|r Finn Doe; |cffff8000Grudge:|r Cara Doe; "
        .. "|cffff8000At war:|r Eve Doe; |cff40c0ffChampion:|r Dan Doe (in a fight)")

    eq(Sounds(h, h.env.SOUNDKIT.RAID_WARNING) - warnings, 2, "the first alert's, and the summary's")
    eq(Sounds(h, h.env.SOUNDKIT.READY_CHECK) - checks, 0, "the champion's is in the summary's")
end)

test("a quiet moment ends the alert budget: the next sighting alerts at once", function()
    local h = Grouped()

    h:Slash("/tlk mark Bob Doe")
    h:Slash("/tlk grudge Cara Doe")
    h:Slash("/tlk grudge Dan Doe")
    h:AddNamePlate(Enemy("Bob"))
    h:AddNamePlate(Enemy("Cara"))
    h:Advance(5)
    eq(h.raidNotices[2].text, "|cffff80001 more grudge nearby:|r Cara Doe")
    h:Advance(5)
    h:AddNamePlate(Enemy("Dan"))
    eq(#h.raidNotices, 3)
    eq(h.raidNotices[3].text, "|cffff8000Grudge:|r Dan Doe (60 Rogue) is here. Krew 0 : 0 Dan Doe")
end)

test("alerts switched off mid-brawl drop the held summary", function()
    local h, addon = Grouped()

    h:Slash("/tlk mark Bob Doe")
    h:Slash("/tlk mark Cara Doe")
    h:AddNamePlate(Enemy("Bob"))
    h:AddNamePlate(Enemy("Cara"))
    addon.State:Set("Warband.alerts", false)
    h:Advance(10)
    eq(#h.raidNotices, 1)
end)
