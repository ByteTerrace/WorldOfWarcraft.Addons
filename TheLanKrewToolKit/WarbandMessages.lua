local addonName, ns = ...

-- WarbandMessages: what the Krew's Warband messages do, and your marks and wars shared with Krew
-- members who join. Warband.lua sends the messages and owns the collections and rules these use.
--
-- Messages from the Krew only update the collections, show an alert or card, and (a rally, with
-- rallyWaypoint on) set a map waypoint; none acts on your behalf, and none is heard while Warband
-- is off. Every hello (a Krew member joining, coming back, or reloading, and the replies to yours)
-- brings your SyncCount most recent marks and wars; a burst of hellos gets one sync, and what a
-- member already knows changes nothing for them. A sync packs the marks into MARKS messages,
-- entries "First Last;CLASS;level;faction", and the wars into WARS messages, one guild key per
-- field, each as few as fit Comms' MaxMessage bytes. A mark or war placed live goes as one MARK
-- or WAR (Warband.lua), and both forms do the same.
--
-- What it sets on ns.Warband, for Warband.lua's OnEnable and OnDisable:
--   Warband.EnableMessages()    listens for the Krew's messages
--   Warband.DisableMessages()   forgets the pending sync when Warband stops

local MaxIntel = 999          -- the largest gathering accepted from a message
local MaxMessage = ByteTerrace.Comms.MaxMessage
local SyncAge = ((7 * 24) * 3600) -- seconds: older marks and wars aren't shared with one who joins
local SyncCount = 3           -- your own marks (and wars) shared with Krew members who join
local SyncDelay = 2           -- seconds that gather a burst of hellos into one sync

local concat, sort = table.concat, table.sort
local GetServerTime, SOUNDKIT = GetServerTime, SOUNDKIT
local ipairs, min = ipairs, math.min

local Addon = ns.Addon
local Alert, Krew, ShowCard = ns.Cards.Alert, ns.Krew, ns.Cards.Show
local CleanCount, CleanText = ns.KrewFields.CleanCount, ns.KrewFields.CleanText
local Warband = ns.Warband
local Avenge, FreshGathering, HeardSighting = Warband.Avenge, Warband.FreshGathering, Warband.HeardSighting
local CleanFaction, InfoFields, InfoFrom = Warband.CleanFaction, Warband.InfoFields, Warband.InfoFrom
local CountDeath, Remember, SetKind = Warband.CountDeath, Warband.Remember, Warband.SetKind
local Describe, Known, Score, Status = Warband.Describe, Warband.Known, Warband.Score, Warband.Status
local GuildName, MyKey, ValidGuildKey, ValidKey = Warband.GuildName, Warband.MyKey, Warband.ValidGuildKey, Warband.ValidKey
local Ledger, WarbandModule, Wars = Warband.Ledger, Warband.Module, Warband.Wars
local SetWaypoint, Where = Warband.SetWaypoint, Warband.Where

local SyncTimer -- pending timer that answers a burst of hellos with one sync

-- Sends entries as kind's messages, as many entries to a message as fit in MaxMessage bytes.
local function SendPacked(kind, entries)
    local room = ((MaxMessage - #kind) - 1) -- "KIND:"
    local fields, left = {}, room

    for _, entry in ipairs(entries) do
        local size = (((#fields > 0) and (#entry + 1)) or #entry) -- a tab before every entry but the first

        if size > left then
            Krew:Send(kind, fields)
            fields, left, size = {}, room, #entry
        end
        fields[#fields + 1] = entry
        left = (left - size)
    end
    if #fields > 0 then
        Krew:Send(kind, fields)
    end
end

-- Your most recent marks and wars (SyncCount of each, within SyncAge), for the Krew members who
-- said hello in the last SyncDelay seconds: one sync per burst, not one per member.
local function Sync()
    SyncTimer = nil
    local me, now = MyKey(), GetServerTime()

    local function Recent(collection, predicate)
        local found = {}

        for _, key in ipairs(collection:Keys()) do
            if (collection:Field(key, "by") == me) and ((now - collection:Field(key, "since")) <= SyncAge)
                and (not predicate or predicate(key)) then
                found[#found + 1] = key
            end
        end
        sort(found, function(a, b)
            return (collection:Field(a, "since") > collection:Field(b, "since"))
        end)
        return found
    end
    local marks = Recent(Ledger, function(key)
        return (Ledger:Field(key, "kind") == "mark")
    end)
    local entries = {}

    for i = 1, min(SyncCount, #marks) do
        entries[i] = concat(InfoFields(Known(marks[i])), ";")
    end
    SendPacked("MARKS", entries)
    local declared = Recent(Wars)

    for i = SyncCount + 1, #declared do
        declared[i] = nil
    end
    SendPacked("WARS", declared)
end

-- A mark from the Krew: fields are key, class, level and faction (InfoFrom).
local function HeardMark(sender, fields)
    local info = InfoFrom(fields)

    if not info then
        return
    end
    local known = (Status(info.key) == "mark")

    Remember(info.key, info)
    if known or not SetKind(info.key, "mark", sender) then
        return -- a mark synced again when someone joins, or a full ledger
    end
    ShowCard({ icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", sound = SOUNDKIT.RAID_WARNING,
        title = "Marked for death", body = (sender .. " marked " .. Describe(info.key) .. ". Hunt them down.") })
end

-- A war the Krew declared on a guild key.
local function HeardWar(sender, field)
    local guild = (ValidGuildKey(field) and field)

    if not guild or Wars:Has(guild) then
        return
    end
    Wars:Set(guild, { by = sender, since = GetServerTime() })
    ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = SOUNDKIT.RAID_WARNING,
        title = "War!", body = (sender .. " declared war on <" .. GuildName(guild) .. ">. Every member is an enemy of the Krew.") })
end

--- Owns the Warband message subscriptions. Called by OnEnable.
function Warband.EnableMessages()
    WarbandModule:Listen(Krew, "GRUDGE", function(sender, fields)
        local info = InfoFrom(fields)

        if not info then
            return
        end
        local key = info.key

        Remember(key, info)
        SetKind(key, "grudge")
        if fields[5] == "1" then
            CountDeath(key)
            ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_Rampage", sound = SOUNDKIT.RAID_WARNING,
                title = (key .. " killed " .. sender .. "!"), body = ("The Krew remembers. " .. Score(key)) })
        end
    end)

    WarbandModule:Listen(Krew, "MARK", HeardMark)

    WarbandModule:Listen(Krew, "MARKS", function(sender, fields)
        for i = 1, #fields do
            local key, class, level, faction = fields[i]:match("^([^;]*);([^;]*);([^;]*);([^;]*)$")

            if key then
                HeardMark(sender, { key, class, level, faction })
            end
        end
    end)

    WarbandModule:Listen(Krew, "UNMARK", function(_, fields)
        local key = (ValidKey(fields[1]) and fields[1])

        if key and (Status(key) == "mark") then
            Ledger:Set(key, { kind = "grudge" })
        end
    end)

    WarbandModule:Listen(Krew, "GLORY", function(sender, fields)
        local info = InfoFrom(fields)

        if not info then
            return
        end
        local known = (Status(info.key) == "glory")

        Remember(info.key, info)
        if SetKind(info.key, "glory", sender) and not known then
            ShowCard({ icon = "Interface\\Icons\\Achievement_PVP_H_01", sound = SOUNDKIT.LFG_REWARDS,
                title = "A champion of the Krew", body = (sender .. " granted glory to " .. Describe(info.key) .. ". Aid them when you see them.") })
        end
    end)

    WarbandModule:Listen(Krew, "WAR", function(sender, fields)
        HeardWar(sender, fields[1])
    end)

    WarbandModule:Listen(Krew, "WARS", function(sender, fields)
        for i = 1, #fields do
            HeardWar(sender, fields[i])
        end
    end)

    WarbandModule:Listen(Krew, "PEACE", function(_, fields)
        local guild = (ValidGuildKey(fields[1]) and fields[1])

        if guild then
            Wars:Remove(guild)
        end
    end)

    WarbandModule:Listen(Krew, "SIGHT", function(sender, fields)
        local key = (ValidKey(fields[1]) and fields[1])
        local status = (key and Status(key))

        if not status then
            return
        end
        HeardSighting(key)
        if not WarbandModule:Get("alerts") then
            return
        end
        local where = Where(CleanText(fields[2]), CleanText(fields[3]))

        if status == "glory" then
            Alert(sender .. ": champion " .. key .. " needs aid at " .. where .. "!", SOUNDKIT.READY_CHECK)
        else
            Alert(sender .. " spotted " .. Describe(key) .. " at " .. where .. "!", SOUNDKIT.RAID_WARNING)
        end
    end)

    WarbandModule:Listen(Krew, "KILL", function(sender, fields)
        local key = (ValidKey(fields[1]) and fields[1])

        if key then
            Avenge(key, sender)
        end
    end)

    WarbandModule:Listen(Krew, "RALLY", function(sender, fields)
        local where = Where(CleanText(fields[4]), CleanText(fields[5]))

        Alert("|cffff2020RALLY!|r " .. sender .. " needs the Krew at " .. where .. "!", SOUNDKIT.READY_CHECK)
        if WarbandModule:Get("rallyWaypoint") and SetWaypoint(fields[1], fields[2], fields[3]) then
            Addon:Print("Waypoint set to " .. sender .. "'s rally.")
        end
    end)

    -- A gathering the Krew already reported (or you did) in the last IntelCooldown shows no card, and
    -- you don't report it again (Warband.FreshGathering).
    WarbandModule:Listen(Krew, "INTEL", function(sender, fields)
        local count = CleanCount(fields[1], MaxIntel)

        if not count then
            return
        end
        local zone, subZone = CleanText(fields[6]), CleanText(fields[7])

        if not FreshGathering(zone, subZone) then
            return
        end
        local faction, mapID, x, y = CleanFaction(fields[2]), fields[3], fields[4], fields[5]

        ShowCard({ icon = "Interface\\Icons\\Ability_Hunter_SniperShot", sound = SOUNDKIT.RAID_WARNING,
            title = "Enemy gathering",
            body = (sender .. " sees " .. count .. " " .. (((faction ~= "") and faction) or "enemy") .. " players at " .. Where(zone, subZone) .. ". Click for a waypoint."),
            onClick = WarbandModule:Callback(SetWaypoint, mapID, x, y) })
    end)

    WarbandModule:Listen(Krew, "HELLO", function()
        if not SyncTimer then
            SyncTimer = WarbandModule:After(SyncDelay, Sync)
        end
    end)
end

--- Forgets the pending sync; OnDisable calls it after subscriptions are removed.
function Warband.DisableMessages()
    SyncTimer = nil -- the module's timers stop with it
end
