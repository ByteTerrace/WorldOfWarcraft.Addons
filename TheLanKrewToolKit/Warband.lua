local addonName, ns = ...

-- Warband: the Krew's war against the other faction, remembered and shared.
--
-- Three account-wide collections:
--   ledger   the people the Krew chose: grudge (someone who killed one of us), mark (marked for
--            death), and glory (a champion the Krew aids, whatever their faction). It never forgets
--            anyone: at LedgerLimit it refuses newcomers, and says so, until you forgive someone.
--   wars     guilds the Krew is at war with: every member counts as an enemy of the Krew.
--   people   rivalry records for every enemy player you've met: class, level, guild, times seen,
--            where, and the score (our kills of them against their kills of us). At PeopleLimit
--            the strangers seen longest ago make room, PeopleTrim at a time. Ledger people stay.
--
-- What it does with them:
--   Sightings  when a ledger player or a member of a guild at war shows up (nameplate, target, or
--              mouseover), a raid warning says so. For a mark or grudge, the Krew hears where, and
--              a champion in a fight asks the Krew for aid. Nameplate badges (WarbandBadges.lua)
--              and the nearby-enemies window (WarbandRadar.lua) show the same standing. Each
--              person alerts once per AlertCooldown, and a brawl doesn't stack warnings: the
--              alerts that follow one within AlertWindow merge into one summary with one sound
--              when it ends ("3 more grudges nearby: ..."), ordered mark, grudge, war, then
--              champion. The Krew still hears of each sighting.
--   Vengeance  an honorable kill on a marked or grudge enemy settles the score, for everyone.
--   Grudges    WarbandDeaths.lua names who killed you and offers to hold a grudge.
--   Rally      /tlk rally calls the Krew to your position: a raid warning and a map waypoint.
--   Intel      several enemy players gathering near you are reported to the Krew with a waypoint.
--
-- What it adds to ns.Warband (WarbandUtil.lua) for the other Warband files:
--   Ledger, Wars, People    the collections, usable once the addon has loaded
--   Status, Score, Known    a person's standing, their score line, and what their record knows
--   Describe, Subject       "Bob Doe (60 Rogue)"; the player a command's argument is about
--   Remember, CountDeath    update a rivalry record; count a Krew member's death to someone
--   TakeFoe                 the prime suspect when you die
--   IdentifyNow(unit)       Identify, reusing this frame's reading of the same player (tooltips)
--   Labels, Icons, Order    each standing's display name, raid-target icon, and sort rank
--   Mark, HoldGrudge, Glory, Forgive, DeclareWar, MakePeace   the ledger and war actions (the
--                           first three answer false when the full ledger refused a newcomer)
--   Module                  the Warband module, for WarbandMessages.lua's listeners
--   SetKind, Avenge, HeardSighting, FreshGathering   what the Krew's messages do to the ledger,
--                           the kill tally, and the report cooldowns (WarbandMessages.lua)
--   OnNearby(info)          set by WarbandRadar.lua while it runs: each hostile player seen
--   OnPlate(unit, info)     set by WarbandBadges.lua while it runs: each nameplate that appears,
--                           with its info (nil for no readable player), so a plate is read once
--
-- Everything shared goes through ns.Krew (Krew.lua): hidden addon messages to your own group only, rate-limited, never
-- during chat messaging lockdown. WarbandMessages.lua hears the Krew's messages and shares your marks and wars with
-- members who join. Names come from nameplates, your target, and mouseover, which the client keeps readable for players
-- outside PvP matches. Your honorable kills come from ByteTerrace_Core's kills fact, and your killers from its death
-- fact (WarbandDeaths.lua).

-- How long, in seconds, before the same person alerts again.
local AlertCooldown = 90
-- How long, in seconds, after an alert further alerts merge into one summary.
local AlertWindow = 3
-- How long, in seconds, a foe you targeted stays the prime suspect.
local FoeMemory = 30
-- How long, in seconds, before the same guild at war alerts again.
local GuildAlertCooldown = 60
-- How long, in seconds, before the same subzone is reported again, by you or the Krew.
local IntelCooldown = 300
-- How many enemy players make a gathering.
local IntelThreshold = 5
-- How long, in seconds, a nameplate counts toward a gathering.
local IntelWindow = 60
-- How long, in seconds, kills of the same person count once.
local KillDedupe = 15
local Labels = { glory = "Champion", grudge = "Grudge", mark = "Marked for death", war = "At war" }
local LedgerLimit = 300
local PeopleLimit = 1000
-- How many strangers' records one trim drops when the rivalry records are full.
local PeopleTrim = 100
-- How long, in seconds, before you can call a rally again.
local RallyCooldown = 15
-- How long, in seconds, before the same person's rivalry record updates again.
local SeenWriteInterval = 60
-- How long, in seconds, before the Krew hears about the same person again.
local SightCooldown = 120
local WarsLimit = 50

-- Each standing's raid-target icon: a star for glory, a cross for grudge, a skull for mark, and a square for war.
local Icons = {
    glory = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    grudge = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    mark = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    war = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
}

-- Each standing's color code in alert text.
local Colors = { glory = "|cff40c0ff", grudge = "|cffff8000", mark = "|cffff2020", war = "|cffff8000" }

-- How an alert summary counts each standing: { one, more than one }.
local Counted = {
    glory = { "champion", "champions" },
    grudge = { "grudge", "grudges" },
    mark = { "marked for death", "marked for death" },
    war = { "enemy at war", "enemies at war" },
}

local Order = { glory = 4, grudge = 2, mark = 1, war = 3 }

local concat = table.concat
local GetServerTime = GetServerTime
local GetTime = GetTime
local Names = ByteTerrace.Names
local next = next
local pairs = pairs
local sort = table.sort
local SOUNDKIT = SOUNDKIT
local tostring = tostring
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local wipe = wipe

local Addon = ns.Addon
local Alert = ns.Cards.Alert
local Krew = ns.Krew
local ShowCard = ns.Cards.Show
local Warband = ns.Warband
local GuildName = Warband.GuildName
local GuildNamed = Warband.GuildNamed
local Here = Warband.Here
local Hostile = Warband.Hostile
local Identify = Warband.Identify
local InfoFields = Warband.InfoFields
local KeyOf = Warband.KeyOf
local MyKey = Warband.MyKey
local PlayerNamed = Warband.PlayerNamed
local Position = Warband.Position
local Typed = Warband.Typed

-- The pending end of the alert window: while it's set, alerts are held for a summary.
local AlertTimer
-- Maps each key to the GetTime() of a hostile player's nameplate in the place you're in.
local Gathering = {}
-- Maps each key to the standing of its alert held in this window.
local Held = {}
-- Maps each held champion in a fight to true.
local HeldFighting = {}
-- Each maps a key to the GetTime() of its last alert, counted kill, and Krew report, in that order.
local LastAlert = {}
-- The info of the hostile player you last targeted, plus its time.
local LastFoe
-- Maps each guild key to the GetTime() of its last alert.
local LastGuildAlert = {}
-- Maps each zone .. "/" .. subZone to the GetTime() of its last report, yours or the Krew's.
local LastIntel = {}
local LastKill = {}
-- The GetTime() of your last rally call.
local LastRally
-- The last player unit Seen read, and the GetTime() it was read at.
local LastSeen
local LastSeenAt
local LastShared = {}
-- The module's collections, bound when it's declared.
local Ledger
local People
local PlaceSubZone
-- Here(), read once per place: zone changes and loading screens forget it.
local PlaceZone
local WarbandModule
local Wars

-- Sorts held keys by standing (Order), then by name.
local function ByStanding(a, b)
    local first = Order[Held[a]]
    local second = Order[Held[b]]

    if first ~= second then
        return (first < second)
    end

    return (a < b)
end

--- Counts a Krew member's death (yours or theirs) to key, against them and their guild at war.
---@param key string
local function CountDeath(key)
    People:Set(key, { deaths = (People:Field(key, "deaths") + 1) })
    local guild = People:Field(key, "guild")

    if (guild ~= "") and Wars:Has(guild) then
        Wars:Set(guild, { deaths = (Wars:Field(guild, "deaths") + 1) })
    end
end

--- Declares war on a guild, with the Krew.
---@param guild string a guild key
local function DeclareWar(guild)
    if not Wars:Has(guild) then
        Wars:Set(guild, { by = MyKey(), since = GetServerTime() })
    end

    Krew:Send("WAR", guild)
    Addon:Print("The Krew is at war with <" .. GuildName(guild) .. ">.")
end

--- Returns "Bob Doe (60 Rogue)", with whatever the rivalry record knows.
---@param key string
---@return string
local function Describe(key)
    local level = People:Field(key, "level")
    local class = People:Field(key, "class")
    local who = key

    if (level > 0) or (class ~= "") then
        local detail = {}

        if level > 0 then
            detail[#detail + 1] = tostring(level)
        end

        if class ~= "" then
            detail[#detail + 1] = (class:sub(1, 1) .. class:sub(2):lower())
        end

        who = (who .. " (" .. table.concat(detail, " ") .. ")")
    end

    return who
end

--- Removes a player from your ledger. The Krew isn't told: each member forgives for themselves.
---@param key string
local function Forgive(key)
    Ledger:Remove(key)
    Addon:Print("Forgave " .. key .. ".")
end

--- Returns whether a gathering in a subzone is news: not reported, by you or the Krew, in the last IntelCooldown
--- seconds. News counts as reported from now on.
---@param zone string
---@param subZone string
---@return boolean fresh
local function FreshGathering(zone, subZone)
    local place = (zone .. "/" .. subZone)
    local now = GetTime()

    if LastIntel[place] and ((now - LastIntel[place]) < IntelCooldown) then
        return false
    end

    LastIntel[place] = now

    return true
end

-- The guild a war command is about: a typed guild name (Warband.GuildNamed), or your target's guild.
local function GuildSubject(arg)
    local name = Typed(arg)

    if name ~= nil then
        return ((name and GuildNamed(name, Wars, People)) or nil)
    end

    local info = (UnitExists("target") and Identify("target"))

    return ((info and (info.guild ~= "") and info.guild) or nil)
end

--- Records that the Krew was just told about key (a SIGHT message), so you don't report them again for SightCooldown
--- seconds.
---@param key string
local function HeardSighting(key)
    LastShared[key] = GetTime()
end

-- The summary of the held alerts and its one sound: "3 more grudges nearby: ..." for one standing, else each standing's
-- names under its label, in Order.
local function HeldSummary()
    local keys = {}

    for key in pairs(Held) do
        keys[#keys + 1] = key
    end

    sort(keys, ByStanding)
    -- Glory sorts last, so the summary plays a raid warning unless every held alert is a champion.
    local sound = (((Held[keys[1]] ~= "glory") and SOUNDKIT.RAID_WARNING) or nil)
    local segments = {}
    local names = nil
    local status = nil

    for _, key in ipairs(keys) do
        if Held[key] ~= status then
            if status then
                segments[#segments + 1] = (Colors[status] .. Labels[status] .. ":|r " .. concat(names, ", "))
            end

            status, names = Held[key], {}
        end

        if HeldFighting[key] then
            names[#names + 1] = (key .. " (in a fight)")
            sound = (sound or SOUNDKIT.READY_CHECK)
        else
            names[#names + 1] = key
        end
    end

    if #segments == 0 then
        local counted = Counted[status][((#keys == 1) and 1) or 2]

        return ("%s%d more %s nearby:|r %s"):format(Colors[status], #keys, counted, concat(names, ", ")), sound
    end

    segments[#segments + 1] = (Colors[status] .. Labels[status] .. ":|r " .. concat(names, ", "))

    return ("%d more nearby: %s"):format(#keys, concat(segments, "; ")), sound
end

-- The alert window ends: the alerts held in it show as one summary, which opens the next window.
local function EndWindow()
    AlertTimer = nil

    if next(Held) == nil then
        return
    end

    if WarbandModule:Get("alerts") then
        AlertTimer = WarbandModule:After(AlertWindow, EndWindow)
        Alert(HeldSummary())
    end

    wipe(Held)
    wipe(HeldFighting)
end

--- Returns what the client lets addons know about a player unit (Identify), reusing Seen's reading of the same player
--- in the same frame: a mouseover's tooltip follows its UPDATE_MOUSEOVER_UNIT.
---@param unit string
---@return table? info
local function IdentifyNow(unit)
    if LastSeen and (LastSeenAt == GetTime()) and (Names.OfUnit(unit) == LastSeen.key) then
        return LastSeen
    end

    return Identify(unit)
end

--- Returns what someone's rivalry record knows about them, as an info (Identify's shape, with blank fields for a
--- stranger).
---@param key string
---@return table info
local function Known(key)
    return { class = People:Field(key, "class"), faction = People:Field(key, "faction"),
        guild = People:Field(key, "guild"), key = key, level = People:Field(key, "level") }
end

--- Makes peace with a guild, with the Krew.
---@param guild string a guild key
local function MakePeace(guild)
    Wars:Remove(guild)
    Krew:Send("PEACE", guild)
    Addon:Print("The Krew made peace with <" .. GuildName(guild) .. ">.")
end

-- Makes room for a new rivalry record: at the limit, drops the PeopleTrim strangers seen longest ago in one pass
-- (EvictionOrder sorts once), so a busy zone doesn't scan every record per new face. EvictionOrder puts strangers
-- first, and LedgerLimit leaves at least PeopleTrim of them in a full collection, so the keys dropped are all
-- strangers.
local function MakeRoom()
    if People:Count() < PeopleLimit then
        return
    end

    local order = People:EvictionOrder()

    for i = 1, PeopleTrim do
        People:Remove(order[i])
    end
end

-- Where you are (Here), read once per place while Warband runs.
local function Place()
    if not PlaceZone then
        PlaceZone, PlaceSubZone = Here()
    end

    return PlaceZone, PlaceSubZone
end

-- Counts hostile players on nameplates. Enough of them in a subzone is a gathering worth reporting.
local function CountGathering(info)
    if not WarbandModule:Get("intel") then
        return
    end

    local now = GetTime()

    Gathering[info.key] = now
    local count = 0

    for key, time in pairs(Gathering) do
        if (now - time) > IntelWindow then
            Gathering[key] = nil
        else
            count = (count + 1)
        end
    end

    if count < IntelThreshold then
        return
    end

    local zone, subZone = Place()

    if FreshGathering(zone, subZone) then
        local mapID, x, y = Position()

        Krew:Send("INTEL", { tostring(count), info.faction, tostring(mapID or 0), tostring(x or 0), tostring(y or 0), zone, subZone })
    end
end

local function Rally()
    if not Krew:Ready() then
        return Addon:Print("Rally calls go to your group through Krew messages: join a group and turn Krew messages on.")
    end

    local now = GetTime()

    if LastRally and ((now - LastRally) < RallyCooldown) then
        return Addon:Print("Your rally call is still ringing out.")
    end

    LastRally = now
    local mapID, x, y = Position()
    local zone, subZone = Place()

    Krew:Send("RALLY", { tostring(mapID or 0), tostring(x or 0), tostring(y or 0), zone, subZone }, true)
    Addon:Print("Rally call sent to the Krew.")
end

--- Updates someone's rivalry record with what the info knows, on top of values.
---@param key string
---@param info table? an info (Identify's shape)
---@param values table? record fields to set as well
local function Remember(key, info, values)
    values = (values or {})

    if info then
        if info.class ~= "" then
            values.class = info.class
        end

        if info.level > 0 then
            values.level = info.level
        end

        if info.faction ~= "" then
            values.faction = info.faction
        end

        if info.guild and (info.guild ~= "") then
            values.guild = info.guild
        end
    end

    if not People:Has(key) then
        values.seen = (values.seen or GetServerTime())
        MakeRoom()
    end

    People:Set(key, values)
end

-- Counts a kill of key against them and their guild at war. Returns false when the kill was already counted.
local function CountKill(key)
    local now = GetTime()

    if LastKill[key] and ((now - LastKill[key]) < KillDedupe) then
        return false
    end

    LastKill[key] = now
    Remember(key, nil, { kills = (People:Field(key, "kills") + 1), seen = GetServerTime() })
    local guild = People:Field(key, "guild")

    if (guild ~= "") and Wars:Has(guild) then
        Wars:Set(guild, { kills = (Wars:Field(guild, "kills") + 1) })
    end

    return true
end

--- Returns a person's score line: "Krew 3 : 5 Bob" is our kills of them against their kills of us.
---@param key string
---@return string
local function Score(key)
    return ("Krew %d : %d %s"):format(People:Field(key, "kills"), People:Field(key, "deaths"), key)
end

-- The card for a hunted enemy (IsHunted) taken down, by you or by a Krew member.
local function Avenged(key, by)
    local kind = Ledger:Field(key, "kind")

    ShowCard({ body = (((by and (by .. " took down ")) or "You took down ") .. key .. ". " .. Score(key)),
        icon = "Interface\\Icons\\Ability_Rogue_Eviscerate", sound = SOUNDKIT.UI_EPICLOOT_TOAST,
        title = (((kind == "mark") and "The mark is paid!") or "Vengeance!") })
end

-- Raises a sighting alert, within the budget: the first opens an AlertWindow, and the ones that follow in it are held
-- for one summary when it ends.
local function Raise(key, status, guild, fighting)
    if not WarbandModule:Get("alerts") then
        return
    end

    if AlertTimer then
        Held[key], HeldFighting[key] = status, (fighting or nil)

        return
    end

    AlertTimer = WarbandModule:After(AlertWindow, EndWindow)
    local color = Colors[status]

    if status == "war" then
        Alert(color .. "At war:|r " .. Describe(key) .. " of <" .. GuildName(guild) .. "> is here!", SOUNDKIT.RAID_WARNING)
    elseif status == "mark" then
        Alert(color .. "Marked for death:|r " .. Describe(key) .. " is here!", SOUNDKIT.RAID_WARNING)
    elseif status == "grudge" then
        Alert(color .. "Grudge:|r " .. Describe(key) .. " is here. " .. Score(key), SOUNDKIT.RAID_WARNING)
    elseif fighting then
        Alert(color .. "Champion|r " .. Describe(key) .. " is in a fight. Aid them!", SOUNDKIT.READY_CHECK)
    else
        Alert(color .. "Champion|r " .. Describe(key) .. " is nearby.")
    end
end

local function AlertFor(key, status, info, unit)
    local now = GetTime()

    if LastAlert[key] and ((now - LastAlert[key]) < AlertCooldown) then
        return
    end

    LastAlert[key] = now

    if status == "war" then
        -- A guild shows up in numbers: one alert per guild per cooldown, not one per member.
        local guild = info.guild

        if LastGuildAlert[guild] and ((now - LastGuildAlert[guild]) < GuildAlertCooldown) then
            return
        end

        LastGuildAlert[guild] = now
        Raise(key, status, guild, false)

        return
    end

    local fighting = ((status == "glory") and UnitAffectingCombat(unit))

    Raise(key, status, nil, fighting)

    if WarbandModule:Get("shareSightings") and ((status ~= "glory") or fighting)
        and not (LastShared[key] and ((now - LastShared[key]) < SightCooldown)) then
        LastShared[key] = now
        local zone, subZone = Place()

        Krew:Send("SIGHT", { key, zone, subZone, ((fighting and "1") or "0") })
    end
end

--- Puts someone in the ledger as kind, without telling the Krew. A grudge doesn't lift a mark, and keeps who put them
--- on the ledger. A full ledger refuses newcomers rather than forgetting anyone: it says so, and the answer is false.
---@param key string
---@param kind string "grudge", "mark" or "glory"
---@param by string? who marked or honored them; a grudge ignores it
---@return boolean entered
local function SetKind(key, kind, by)
    if kind == "grudge" then
        kind, by = (((Ledger:Field(key, "kind") == "mark") and "mark") or "grudge"), Ledger:Field(key, "by")
    end

    local values = { by = by, kind = kind }

    if not Ledger:Has(key) then
        if Ledger:Count() >= LedgerLimit then
            Addon:Print(("The ledger is full (%d), so %s isn't on it. Make room with %s forgive <name>.")
                :format(LedgerLimit, key, Addon.Slash[1]))

            return false
        end

        values.since = GetServerTime()
    end

    Ledger:Set(key, values)

    return true
end

-- Puts a player in the ledger as kind, from you, and tells the Krew with message. Returns false when the full ledger
-- refused them (the Krew isn't told).
local function Choose(info, kind, message)
    Remember(info.key, info)

    if not SetKind(info.key, kind, MyKey()) then
        return false
    end

    Krew:Send(message, InfoFields(info))

    return true
end

--- Grants a player glory, with the Krew: a champion the Krew aids.
---@param info table
---@return boolean granted false when the full ledger refused them (the Krew isn't told)
local function Glory(info)
    return Choose(info, "glory", "GLORY")
end

--- Holds a grudge against a player, with the Krew. A marked player stays marked.
---@param info table
---@param died boolean whether they killed you, which counts in their score (and the Krew's)
---@param counted boolean? your death already counts in your record (the death recap named them)
---@return boolean held false when the full ledger refused them (the Krew isn't told)
local function HoldGrudge(info, died, counted)
    local key = info.key

    Remember(key, info)

    if died and not counted then
        CountDeath(key)
    end

    if not SetKind(key, "grudge") then
        return false
    end

    local fields = InfoFields(info)

    fields[5] = ((died and "1") or "0")
    Krew:Send("GRUDGE", fields)

    return true
end

--- Marks a player for death, with the Krew.
---@param info table
---@return boolean marked false when the full ledger refused them (the Krew isn't told)
local function Mark(info)
    return Choose(info, "mark", "MARK")
end

--- Returns a person's standing with the Krew: their ledger kind, else "war" when their guild is at war with the Krew,
--- else nil.
---@param key string
---@param guild string? their guild key; the rivalry record's when omitted
---@return string? status "mark", "grudge", "glory" or "war"
local function Status(key, guild)
    if Ledger:Has(key) then
        return Ledger:Field(key, "kind")
    end

    guild = (guild or People:Field(key, "guild"))

    if (guild ~= "") and Wars:Has(guild) then
        return "war"
    end

    return nil
end

-- Whether the Krew hunts key: marked for death, or a grudge.
local function IsHunted(key)
    local status = Status(key)

    return ((status == "mark") or (status == "grudge"))
end

--- Handles a Krew member taking down key (a KILL message): when the Krew hunts them, the kill counts (once, however
--- many tell of it), and the vengeance card names who did it.
---@param key string
---@param by string the Krew member
local function Avenge(key, by)
    if IsHunted(key) and CountKill(key) then
        Avenged(key, by)
    end
end

-- An honorable kill of victim (kills.victim).
local function OnKill(victim)
    local key = KeyOf(victim)

    if CountKill(key) and IsHunted(key) then
        Avenged(key)
        Krew:Send("KILL", key)
    end
end

-- A player unit came into view: a nameplate (plate), your target, or mouseover. It's read once, for the badges
-- (Warband.OnPlate) and the prime suspect too. The suspect argument marks a hostile player you engage, or is "fighting"
-- for one that's in combat (asked only of a hostile player).
local function Seen(unit, plate, suspect)
    local info = Identify(unit)

    if plate and Warband.OnPlate then
        Warband.OnPlate(unit, info)
    end

    if not info then
        return
    end

    LastSeen, LastSeenAt = info, GetTime()
    local key = info.key
    local hostile = Hostile(unit)

    if hostile then
        if suspect == "fighting" then
            suspect = UnitAffectingCombat(unit)
        end

        if suspect then
            info.time = GetTime()
            LastFoe = info
        end

        if plate then
            CountGathering(info)
        end

        if Warband.OnNearby then
            Warband.OnNearby(info)
        end
    end

    local status = Status(key, info.guild)

    if not hostile and not status then
        -- Friendly strangers aren't rivals.
        return
    end

    local now = GetServerTime()

    -- The first sighting always counts: a record a command or the Krew made has a seen time, but no sighting yet. After
    -- it, one update per SeenWriteInterval.
    if not People:Has(key) or (People:Field(key, "sightings") == 0) or ((now - People:Field(key, "seen")) >= SeenWriteInterval) then
        Remember(key, info, { seen = now, sightings = (People:Field(key, "sightings") + 1), zone = (Place()) })
    end

    if status then
        AlertFor(key, status, info, unit)
    end
end

--- Returns the player a command is about: a typed name (Warband.PlayerNamed), or your target.
---@param arg string? the command's argument: a full name ("First Last")
---@return table? info nil for a bad name, or no name and no player target
local function Subject(arg)
    local name = Typed(arg)

    if name ~= nil then
        local key = (name and PlayerNamed(name, Ledger, People))

        return ((key and Known(key)) or nil)
    end

    if UnitExists("target") then
        return Identify("target")
    end
end

--- Returns the prime suspect when you die: the hostile player you target, else the one you last targeted (or moused
--- over in combat) within FoeMemory seconds. Taking it forgets the last one.
---@return table? info
local function TakeFoe()
    local suspect

    if UnitExists("target") and Hostile("target") then
        suspect = Identify("target")
    end

    if not suspect and LastFoe and ((GetTime() - LastFoe.time) <= FoeMemory) then
        suspect = LastFoe
    end

    LastFoe = nil

    return suspect
end

local function Usage(verb, what)
    Addon:Print("Target a player, or name " .. (what or "them") .. ": " .. Addon.Slash[1] .. " " .. verb .. " <name>")
end

-- A command's run that acts on the subject its argument names (your target without one), then prints done (a format of
-- the subject's key) when act says it changed anything.
local function OnSubject(verb, act, done)
    return function(arg)
        local info = Subject(arg)

        if not info then
            return Usage(verb)
        end

        if act(info) then
            Addon:Print(done:format(info.key))
        end
    end
end

Warband.Avenge, Warband.FreshGathering, Warband.HeardSighting, Warband.SetKind = Avenge, FreshGathering, HeardSighting, SetKind
Warband.CountDeath, Warband.Remember = CountDeath, Remember
Warband.DeclareWar, Warband.MakePeace = DeclareWar, MakePeace
Warband.Describe, Warband.IdentifyNow, Warband.Subject = Describe, IdentifyNow, Subject
Warband.Forgive, Warband.Glory, Warband.HoldGrudge, Warband.Mark = Forgive, Glory, HoldGrudge, Mark
Warband.Icons, Warband.Labels, Warband.Order = Icons, Labels, Order
Warband.Known, Warband.Score, Warband.Status, Warband.TakeFoe = Known, Score, Status, TakeFoe

WarbandModule = Addon:Module("Warband", {
    commands = {
        { label = "Mark your target (or a name) for death, with the Krew", name = "mark",
            run = OnSubject("mark", Mark, "%s is marked for death."),
            slash = "mark" },
        { label = "Lift a mark for death", name = "unmark",
            run = function(arg)
                local subject = Subject(arg)
                local key = (subject and subject.key)

                if not key then
                    return Usage("unmark")
                elseif Status(key) ~= "mark" then
                    return Addon:Print(key .. " isn't marked for death.")
                end

                Ledger:Set(key, { kind = "grudge" })
                Krew:Send("UNMARK", key)
                Addon:Print(key .. " is no longer marked.")
            end,
            slash = "unmark" },
        { label = "Hold a grudge against your target (or a name)", name = "grudge",
            run = OnSubject("grudge", function(info) return HoldGrudge(info, false) end, "The Krew holds a grudge against %s."),
            slash = "grudge" },
        { label = "Grant glory to your target (or a name): a champion the Krew aids", name = "glory",
            run = OnSubject("glory", Glory, "%s is a champion of the Krew."),
            slash = "glory" },
        { label = "Remove someone from your ledger", name = "forgive",
            run = function(arg)
                local subject = Subject(arg)

                if not subject then
                    return Usage("forgive")
                elseif not Ledger:Has(subject.key) then
                    return Addon:Print(subject.key .. " isn't on the ledger.")
                end

                Forgive(subject.key)
            end,
            slash = "forgive" },
        { label = "Declare war on your target's guild (or a guild by name), with the Krew", name = "war",
            run = function(arg)
                local guild = GuildSubject(arg)

                if not guild then
                    return Usage("war", "the guild")
                end

                DeclareWar(guild)
            end,
            slash = "war" },
        { label = "Make peace with a guild", name = "peace",
            run = function(arg)
                local guild = GuildSubject(arg)

                if not guild or not Wars:Has(guild) then
                    return Usage("peace", "the guild")
                end

                MakePeace(guild)
            end,
            slash = "peace" },
        { label = "List the ledger and the Krew's wars", name = "ledger",
            run = function()
                Warband.PrintLedger()
            end,
            slash = "ledger" },
        { label = "Show your record against your target (or a name)", name = "rival",
            run = function(arg)
                Warband.PrintRival(arg)
            end,
            slash = "rival" },
        { label = "Call the Krew to your position", name = "rally", run = Rally, slash = "rally" },
    },
    description = "A ledger of grudges, marks for death, champions and guild wars, shared with your Krew: sightings, vengeance, rallies and enemy gatherings.",
    label = "Warband (world PvP)",
    OnDisable = function()
        Warband.DisableMenus()
        Warband.DisableMessages()
        LastFoe, LastSeen, PlaceZone, PlaceSubZone = nil, nil, nil, nil
        -- The module's timers stop with it, so only the handles are forgotten.
        AlertTimer = nil
        wipe(Gathering)
        wipe(Held)
        wipe(HeldFighting)
    end,
    OnEnable = function(module)
        Warband.EnableMenus()

        module:On("NAME_PLATE_UNIT_ADDED", function(unit)
            Seen(unit, true, false)
        end)

        module:On("PLAYER_TARGET_CHANGED", function()
            if UnitExists("target") then
                Seen("target", false, true)
            end
        end)

        -- A gathering is in one place: enemies seen before you moved on don't count toward the next.
        local function MovedOn()
            PlaceZone, PlaceSubZone = nil, nil
            wipe(Gathering)
        end

        module:On("ZONE_CHANGED", MovedOn)
        module:On("ZONE_CHANGED_INDOORS", MovedOn)
        module:On("ZONE_CHANGED_NEW_AREA", MovedOn)
        module:On("PLAYER_ENTERING_WORLD", MovedOn)

        module:On("UPDATE_MOUSEOVER_UNIT", function()
            if UnitExists("mouseover") then
                Seen("mouseover", false, "fighting")
            end
        end)

        Warband.EnableMessages()

        module:OnIncrease("kills.honorable", function(state)
            OnKill(state:Get("kills.victim"))
        end)
    end,
    page = "Warband",
    records = {
        { fields = {
                { default = "grudge", kind = "string", name = "kind", values = { "grudge", "mark", "glory" } },
                -- The Krew member who marked or honored them.
                { default = "", kind = "string", name = "by" },
                { default = 0, kind = "number", min = 0, name = "since" },
            },
            limit = LedgerLimit, name = "ledger" },
        { evict = "since",
            fields = {
                { default = "", kind = "string", name = "by" },
                { default = 0, kind = "number", min = 0, name = "since" },
                { default = 0, kind = "number", min = 0, name = "kills", step = 1 },
                { default = 0, kind = "number", min = 0, name = "deaths", step = 1 },
            },
            limit = WarsLimit, name = "wars" },
        { evict = "seen",
            fields = {
                { default = "", kind = "string", name = "class" },
                { default = 0, kind = "number", max = 200, min = 0, name = "level", step = 1 },
                { default = "", kind = "string", name = "faction", values = { "", "Alliance", "Horde" } },
                { default = "", kind = "string", name = "guild" },
                -- How many times the Krew killed them.
                { default = 0, kind = "number", min = 0, name = "kills", step = 1 },
                -- How many times they killed the Krew.
                { default = 0, kind = "number", min = 0, name = "deaths", step = 1 },
                { default = 0, kind = "number", min = 0, name = "sightings", step = 1 },
                { default = 0, kind = "number", min = 0, name = "seen" },
                { default = "", kind = "string", name = "zone" },
            },
            keep = function(key) return Ledger:Has(key) end, limit = PeopleLimit, name = "people" },
    },
    state = {
        { default = true,
            description = "A raid warning when someone on the ledger, or a member of a guild at war, shows up: a nameplate, your target or mouseover.",
            kind = "boolean", label = "Sighting alerts", name = "alerts" },
        { default = true,
            description = "Report sightings of marked and grudge enemies (and champions in a fight) to your group.",
            kind = "boolean", label = "Tell the Krew what I see", name = "shareSightings" },
        { default = true,
            description = "When an enemy player kills you, a card names them and offers to hold a grudge. When the game can't say who, it asks about the enemy player you were fighting.",
            kind = "boolean", label = "Ask who killed me", name = "deathPrompt" },
        { default = true, description = "When a Krew member rallies, set a map waypoint to them.", kind = "boolean",
            label = "Waypoint to rallies", name = "rallyWaypoint" },
        { default = true,
            description = ("When " .. IntelThreshold .. " or more enemy players gather near you, tell the Krew where."),
            kind = "boolean", label = "Report enemy gatherings", name = "intel" },
    },
    uses = { "kills" },
})

Ledger, Wars, People = WarbandModule.Records.ledger, WarbandModule.Records.wars, WarbandModule.Records.people
Warband.Ledger, Warband.Wars, Warband.People = Ledger, Wars, People
Warband.Module = WarbandModule
