local addonName, ns = ...

-- WarbandMessages: what the Krew's Warband messages do, and your marks and wars shared with Krew
-- members who join. Warband.lua sends the messages and owns the collections and rules these use.
--
-- Messages from the Krew only update the collections, show an alert or card, and (a rally, with
-- rallyWaypoint on) set a map waypoint; none acts on your behalf, and none is heard while Warband
-- is off. A Krew member who joins (HELLO) hears your SyncCount most recent marks and wars once per
-- group; a burst of joins gets one sync.
--
-- What it sets on ns.Warband, for Warband.lua's OnEnable and OnDisable:
--   Warband.EnableMessages()    forgets who heard your marks and wars when you leave the group
--   Warband.DisableMessages()   forgets them, and the pending sync, when Warband stops

local MaxIntel = 999          -- the largest gathering accepted from a message
local SyncCount = 3           -- your own marks (and wars) shared with Krew members who join
local SyncAge = 7 * 24 * 3600 -- seconds: older marks and wars aren't shared with one who joins
local SyncDelay = 2           -- seconds that gather a burst of joining Krew members into one sync

local GetServerTime, SOUNDKIT = GetServerTime, SOUNDKIT
local ipairs = ipairs
local sort, wipe = table.sort, wipe

local Warband = ns.Warband
local MyKey, GuildName, ValidKey, ValidGuildKey = Warband.MyKey, Warband.GuildName, Warband.ValidKey, Warband.ValidGuildKey
local CleanFaction, InfoFields, InfoFrom = Warband.CleanFaction, Warband.InfoFields, Warband.InfoFrom
local Where, SetWaypoint = Warband.Where, Warband.SetWaypoint
local Status, Score, Known, Describe = Warband.Status, Warband.Score, Warband.Known, Warband.Describe
local Remember, CountDeath, SetKind = Warband.Remember, Warband.CountDeath, Warband.SetKind
local Avenge, HeardSighting, FreshGathering = Warband.Avenge, Warband.HeardSighting, Warband.FreshGathering
local CleanText, CleanCount = ns.KrewFields.CleanText, ns.KrewFields.CleanCount
local Addon = ns.Addon
local Krew, ShowCard, Alert = ns.Krew, ns.Cards.Show, ns.Cards.Alert
local WarbandModule, Ledger, Wars = Warband.Module, Warband.Ledger, Warband.Wars

local Synced = {} -- [sender] = true once a Krew member who joined has heard your marks and wars
local SyncTimer   -- pending timer that answers a burst of joins with one sync

-- Your most recent marks and wars (SyncCount of each, within SyncAge), for the Krew members who
-- joined in the last SyncDelay seconds: one sync per burst of joins, not one per member.
local function Sync()
    SyncTimer = nil
    local me, now = MyKey(), GetServerTime()
    local function Recent(collection, predicate)
        local found = {}
        for _, key in ipairs(collection:Keys()) do
            if collection:Field(key, "by") == me and now - collection:Field(key, "since") <= SyncAge
                and (not predicate or predicate(key)) then
                found[#found + 1] = key
            end
        end
        sort(found, function(a, b)
            return collection:Field(a, "since") > collection:Field(b, "since")
        end)
        return found
    end
    local marks = Recent(Ledger, function(key)
        return Ledger:Field(key, "kind") == "mark"
    end)
    for i = 1, math.min(SyncCount, #marks) do
        Krew:Send("MARK", InfoFields(Known(marks[i])))
    end
    local declared = Recent(Wars)
    for i = 1, math.min(SyncCount, #declared) do
        Krew:Send("WAR", declared[i])
    end
end

--- Owns the Warband message subscriptions and forgets group sync on leaving. Called by OnEnable.
function Warband.EnableMessages()
    WarbandModule:On("GROUP_LEFT", function()
        wipe(Synced)
    end)
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
                title = key .. " killed " .. sender .. "!", body = "The Krew remembers. " .. Score(key) })
        end
    end)

    WarbandModule:Listen(Krew, "MARK", function(sender, fields)
        local info = InfoFrom(fields)
        if not info then
            return
        end
        local known = Status(info.key) == "mark"
        Remember(info.key, info)
        if known or not SetKind(info.key, "mark", sender) then
            return -- a mark synced again when someone joins, or a full ledger
        end
        ShowCard({ icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", sound = SOUNDKIT.RAID_WARNING,
            title = "Marked for death", body = sender .. " marked " .. Describe(info.key) .. ". Hunt them down." })
    end)

    WarbandModule:Listen(Krew, "UNMARK", function(_, fields)
        local key = ValidKey(fields[1]) and fields[1]
        if key and Status(key) == "mark" then
            Ledger:Set(key, { kind = "grudge" })
        end
    end)

    WarbandModule:Listen(Krew, "GLORY", function(sender, fields)
        local info = InfoFrom(fields)
        if not info then
            return
        end
        Remember(info.key, info)
        if SetKind(info.key, "glory", sender) then
            ShowCard({ icon = "Interface\\Icons\\Achievement_PVP_H_01", sound = SOUNDKIT.LFG_REWARDS,
                title = "A champion of the Krew", body = sender .. " granted glory to " .. Describe(info.key) .. ". Aid them when you see them." })
        end
    end)

    WarbandModule:Listen(Krew, "WAR", function(sender, fields)
        local guild = ValidGuildKey(fields[1]) and fields[1]
        if not guild or Wars:Has(guild) then
            return
        end
        Wars:Set(guild, { by = sender, since = GetServerTime() })
        ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = SOUNDKIT.RAID_WARNING,
            title = "War!", body = sender .. " declared war on <" .. GuildName(guild) .. ">. Every member is an enemy of the Krew." })
    end)

    WarbandModule:Listen(Krew, "PEACE", function(_, fields)
        local guild = ValidGuildKey(fields[1]) and fields[1]
        if guild then
            Wars:Remove(guild)
        end
    end)

    WarbandModule:Listen(Krew, "SIGHT", function(sender, fields)
        local key = ValidKey(fields[1]) and fields[1]
        local status = key and Status(key)
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
        local key = ValidKey(fields[1]) and fields[1]
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
            body = sender .. " sees " .. count .. " " .. (faction ~= "" and faction or "enemy") .. " players at " .. Where(zone, subZone) .. ". Click for a waypoint.",
            onClick = WarbandModule:Callback(SetWaypoint, mapID, x, y) })
    end)

    WarbandModule:Listen(Krew, "HELLO", function(sender)
        if Synced[sender] then
            return
        end
        Synced[sender] = true
        if not SyncTimer then
            SyncTimer = WarbandModule:After(SyncDelay, Sync)
        end
    end)
end

--- Forgets group sync and the pending timer; OnDisable calls it after subscriptions are removed.
function Warband.DisableMessages()
    SyncTimer = nil -- the module's timers stop with it
    wipe(Synced)
end
