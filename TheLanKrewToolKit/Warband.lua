local addonName, ns = ...

-- Warband: the Krew's war against the other faction, remembered and shared.
--
-- Three account-wide collections:
--   ledger   the people the Krew chose: grudge (someone who killed one of us), mark (marked for
--            death) and glory (a champion the Krew aids, whatever their faction). It never forgets
--            anyone: at LedgerLimit it refuses newcomers, and says so, until you forgive someone.
--   wars     guilds the Krew is at war with: every member counts as an enemy of the Krew.
--   people   rivalry records for every enemy player you've met: class, level, guild, times seen,
--            where, and the score (our kills of them against their kills of us). At PeopleLimit
--            the strangers seen longest ago make room, PeopleTrim at a time; ledger people stay.
--
-- What it does with them:
--   Sightings  when a ledger player or a member of a guild at war shows up (nameplate, target or
--              mouseover), a raid warning says so and the Krew hears where. A champion in a fight
--              asks for aid. Nameplate badges (WarbandBadges.lua) and the nearby-enemies window
--              (WarbandRadar.lua) show the same standing.
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
--   Labels, Icons, Order    each standing's display name, raid-target icon and sort rank
--   Mark, HoldGrudge, Glory, Forgive, DeclareWar, MakePeace   the ledger and war actions (the
--                           first three answer false when the full ledger refused a newcomer)
--   Module                  the Warband module, for WarbandMessages.lua's listeners
--   SetKind, Avenge, HeardSighting, FreshGathering   what the Krew's messages do to the ledger,
--                           the kill tally and the report cooldowns (WarbandMessages.lua)
--   OnNearby(info)          set by WarbandRadar.lua while it runs: each hostile player seen
--   OnPlate(unit, info)     set by WarbandBadges.lua while it runs: each nameplate that appears,
--                           with its info (nil for no readable player), so a plate is read once
--
-- Everything shared goes through ns.Krew (Krew.lua): hidden addon messages to your own group only,
-- rate-limited, never during chat messaging lockdown; WarbandMessages.lua hears the Krew's messages
-- and shares your marks and wars with members who join. Names come from nameplates, your target and
-- mouseover, which the client keeps readable for players outside PvP matches. Your honorable kills
-- come from ByteTerrace_Core's kills fact, and your killers from its death fact (WarbandDeaths.lua).

local LedgerLimit = 300
local PeopleLimit = 1000
local PeopleTrim = 100        -- strangers' records dropped at once when the rivalry records are full
local WarsLimit = 50
local AlertCooldown = 90      -- seconds between alerts about the same person
local GuildAlertCooldown = 60 -- seconds between alerts about the same guild at war
local SightCooldown = 120     -- seconds between Krew reports about the same person
local SeenWriteInterval = 60  -- seconds between rivalry updates for the same person
local FoeMemory = 30          -- seconds a foe you targeted stays the prime suspect
local KillDedupe = 15         -- seconds in which kills of the same person count once
local RallyCooldown = 15      -- seconds between your rally calls
local IntelWindow = 60        -- seconds of nameplates counted for a gathering
local IntelThreshold = 5      -- enemy players that make a gathering
local IntelCooldown = 300     -- seconds between reports for the same subzone, yours or the Krew's
local Labels = { grudge = "Grudge", mark = "Marked for death", glory = "Champion", war = "At war" }
local Icons = {
    mark = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",   -- skull
    grudge = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", -- cross
    war = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",    -- square
    glory = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",  -- star
}
local Order = { mark = 1, grudge = 2, war = 3, glory = 4 }

local GetServerTime, GetTime, SOUNDKIT = GetServerTime, GetTime, SOUNDKIT
local UnitAffectingCombat, UnitExists = UnitAffectingCombat, UnitExists
local tostring, wipe = tostring, wipe

local Warband = ns.Warband
local KeyOf, Identify, Hostile, MyKey = Warband.KeyOf, Warband.Identify, Warband.Hostile, Warband.MyKey
local GuildName, InfoFields = Warband.GuildName, Warband.InfoFields
local Typed, PlayerNamed, GuildNamed = Warband.Typed, Warband.PlayerNamed, Warband.GuildNamed
local Here, Position = Warband.Here, Warband.Position
local Addon = ns.Addon
local Krew, ShowCard, Alert = ns.Krew, ns.Cards.Show, ns.Cards.Alert

local WarbandModule
local Ledger, Wars, People -- the module's collections, bound when it's declared
local LastAlert, LastShared, LastKill = {}, {}, {} -- [key] = GetTime() of the last alert, Krew report, counted kill
local LastGuildAlert = {} -- [guild key] = GetTime()
local Gathering = {}      -- [key] = GetTime() of a hostile player's nameplate
local LastIntel = {}      -- [zone .. "/" .. subZone] = GetTime() of the last report, yours or the Krew's
local LastFoe             -- the info of the hostile player you last targeted, plus its time
local LastRally           -- GetTime() of your last rally call

--- A person's standing with the Krew: their ledger kind, else "war" when their guild is at war
--- with the Krew, else nil.
---@param key string
---@param guild string? their guild key; the rivalry record's when omitted
---@return string? status "mark", "grudge", "glory" or "war"
local function Status(key, guild)
    if Ledger:Has(key) then
        return Ledger:Field(key, "kind")
    end
    guild = guild or People:Field(key, "guild")
    if guild ~= "" and Wars:Has(guild) then
        return "war"
    end
    return nil
end

-- Whether the Krew hunts key: marked for death, or a grudge.
local function IsHunted(key)
    local status = Status(key)
    return status == "mark" or status == "grudge"
end

--- What someone's rivalry record knows about them, as an info (Identify's shape; blank fields for
--- a stranger).
---@param key string
---@return table info
local function Known(key)
    return { key = key, class = People:Field(key, "class"), level = People:Field(key, "level"),
        faction = People:Field(key, "faction"), guild = People:Field(key, "guild") }
end

--- "Bob Doe (60 Rogue)", with whatever the rivalry record knows.
---@param key string
---@return string
local function Describe(key)
    local level, class = People:Field(key, "level"), People:Field(key, "class")
    local who = key
    if level > 0 or class ~= "" then
        local detail = {}
        if level > 0 then
            detail[#detail + 1] = tostring(level)
        end
        if class ~= "" then
            detail[#detail + 1] = class:sub(1, 1) .. class:sub(2):lower()
        end
        who = who .. " (" .. table.concat(detail, " ") .. ")"
    end
    return who
end

--- A person's score line: "Krew 3 : 5 Bob" is our kills of them against their kills of us.
---@param key string
---@return string
local function Score(key)
    return ("Krew %d : %d %s"):format(People:Field(key, "kills"), People:Field(key, "deaths"), key)
end

-- Makes room for a new rivalry record: at the limit, drops the PeopleTrim strangers seen longest
-- ago in one pass (EvictionOrder sorts once), so a busy zone doesn't scan every record per new face.
local function MakeRoom()
    if People:Count() < PeopleLimit then
        return
    end
    local order = People:EvictionOrder() -- strangers first, the longest unseen first
    for i = 1, PeopleTrim do
        local key = order[i]
        if not key or Ledger:Has(key) then
            return
        end
        People:Remove(key)
    end
end

--- Updates someone's rivalry record with what the info knows, on top of values.
---@param key string
---@param info table? an info (Identify's shape)
---@param values table? record fields to set as well
local function Remember(key, info, values)
    values = values or {}
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
        if info.guild and info.guild ~= "" then
            values.guild = info.guild
        end
    end
    if not People:Has(key) then
        values.seen = values.seen or GetServerTime()
        MakeRoom()
    end
    People:Set(key, values)
end

--- Puts someone in the ledger as kind, without telling the Krew. A grudge doesn't lift a mark, and
--- keeps who put them on the ledger. A full ledger refuses newcomers rather than forgetting anyone:
--- it says so, and the answer is false.
---@param key string
---@param kind string "grudge", "mark" or "glory"
---@param by string? who marked or honored them; a grudge ignores it
---@return boolean entered
local function SetKind(key, kind, by)
    if kind == "grudge" then
        kind, by = Ledger:Field(key, "kind") == "mark" and "mark" or "grudge", Ledger:Field(key, "by")
    end
    local values = { kind = kind, by = by }
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

--- Counts a Krew member's death (yours or theirs) to key, against them and their guild at war.
---@param key string
local function CountDeath(key)
    People:Set(key, { deaths = People:Field(key, "deaths") + 1 })
    local guild = People:Field(key, "guild")
    if guild ~= "" and Wars:Has(guild) then
        Wars:Set(guild, { deaths = Wars:Field(guild, "deaths") + 1 })
    end
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
    fields[5] = died and "1" or "0"
    Krew:Send("GRUDGE", fields)
    return true
end

-- Puts a player in the ledger as kind, from you, and tells the Krew with message; false when the
-- full ledger refused them (the Krew isn't told).
local function Choose(info, kind, message)
    Remember(info.key, info)
    if not SetKind(info.key, kind, MyKey()) then
        return false
    end
    Krew:Send(message, InfoFields(info))
    return true
end

--- Marks a player for death, with the Krew.
---@param info table
---@return boolean marked false when the full ledger refused them (the Krew isn't told)
local function Mark(info)
    return Choose(info, "mark", "MARK")
end

--- Grants a player glory, with the Krew: a champion the Krew aids.
---@param info table
---@return boolean granted false when the full ledger refused them (the Krew isn't told)
local function Glory(info)
    return Choose(info, "glory", "GLORY")
end

--- Removes a player from your ledger. The Krew isn't told: each member forgives for themselves.
---@param key string
local function Forgive(key)
    Ledger:Remove(key)
    Addon:Print("Forgave " .. key .. ".")
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

--- Makes peace with a guild, with the Krew.
---@param guild string a guild key
local function MakePeace(guild)
    Wars:Remove(guild)
    Krew:Send("PEACE", guild)
    Addon:Print("The Krew made peace with <" .. GuildName(guild) .. ">.")
end

--- The Krew was just told about key (a SIGHT message): you don't report them again for
--- SightCooldown seconds.
---@param key string
local function HeardSighting(key)
    LastShared[key] = GetTime()
end

local function AlertFor(key, status, info, unit)
    local now = GetTime()
    if LastAlert[key] and now - LastAlert[key] < AlertCooldown then
        return
    end
    LastAlert[key] = now
    if status == "war" then
        -- A guild shows up in numbers: one alert per guild per cooldown, not one per member.
        local guild = info.guild
        if LastGuildAlert[guild] and now - LastGuildAlert[guild] < GuildAlertCooldown then
            return
        end
        LastGuildAlert[guild] = now
        if WarbandModule:Get("alerts") then
            Alert("|cffff8000At war:|r " .. Describe(key) .. " of <" .. GuildName(guild) .. "> is here!", SOUNDKIT.RAID_WARNING)
        end
        return
    end
    local fighting = status == "glory" and UnitAffectingCombat(unit)
    if WarbandModule:Get("alerts") then
        if status == "mark" then
            Alert("|cffff2020Marked for death:|r " .. Describe(key) .. " is here!", SOUNDKIT.RAID_WARNING)
        elseif status == "grudge" then
            Alert("|cffff8000Grudge:|r " .. Describe(key) .. " is here. " .. Score(key), SOUNDKIT.RAID_WARNING)
        elseif fighting then
            Alert("|cff40c0ffChampion|r " .. Describe(key) .. " is in a fight. Aid them!", SOUNDKIT.READY_CHECK)
        else
            Alert("|cff40c0ffChampion|r " .. Describe(key) .. " is nearby.")
        end
    end
    if WarbandModule:Get("shareSightings") and (status ~= "glory" or fighting)
        and not (LastShared[key] and now - LastShared[key] < SightCooldown) then
        LastShared[key] = now
        local zone, subZone = Here()
        Krew:Send("SIGHT", { key, zone, subZone, fighting and "1" or "0" })
    end
end

--- Whether a gathering in a subzone is news: not reported, by you or the Krew, in the last
--- IntelCooldown seconds. News counts as reported from now on.
---@param zone string
---@param subZone string
---@return boolean fresh
local function FreshGathering(zone, subZone)
    local place, now = zone .. "/" .. subZone, GetTime()
    if LastIntel[place] and now - LastIntel[place] < IntelCooldown then
        return false
    end
    LastIntel[place] = now
    return true
end

-- Counts hostile players on nameplates; enough of them in a subzone is a gathering worth reporting.
local function CountGathering(info)
    if not WarbandModule:Get("intel") then
        return
    end
    local now = GetTime()
    Gathering[info.key] = now
    local count = 0
    for key, time in pairs(Gathering) do
        if now - time > IntelWindow then
            Gathering[key] = nil
        else
            count = count + 1
        end
    end
    if count < IntelThreshold then
        return
    end
    local zone, subZone = Here()
    if FreshGathering(zone, subZone) then
        local mapID, x, y = Position()
        Krew:Send("INTEL", { tostring(count), info.faction, tostring(mapID or 0), tostring(x or 0), tostring(y or 0), zone, subZone })
    end
end

-- A player unit came into view: a nameplate (plate), your target, or mouseover. It's read once, for
-- the badges (Warband.OnPlate) and the prime suspect too (suspect: a hostile player you engage).
local function Seen(unit, plate, suspect)
    local info = Identify(unit)
    if plate and Warband.OnPlate then
        Warband.OnPlate(unit, info)
    end
    if not info then
        return
    end
    local key, hostile = info.key, Hostile(unit)
    if hostile then
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
        return -- friendly strangers aren't rivals
    end
    local now = GetServerTime()
    if not People:Has(key) or now - People:Field(key, "seen") >= SeenWriteInterval then
        Remember(key, info, { seen = now, zone = (Here()), sightings = People:Field(key, "sightings") + 1 })
    end
    if status then
        AlertFor(key, status, info, unit)
    end
end

--- The prime suspect when you die: the hostile player you target, else the one you last
--- targeted (or moused over in combat) within FoeMemory seconds. Taking it forgets the last one.
---@return table? info
local function TakeFoe()
    local suspect
    if UnitExists("target") and Hostile("target") then
        suspect = Identify("target")
    end
    if not suspect and LastFoe and GetTime() - LastFoe.time <= FoeMemory then
        suspect = LastFoe
    end
    LastFoe = nil
    return suspect
end

-- Counts a kill of key against them and their guild at war; false when it was already counted.
local function CountKill(key)
    local now = GetTime()
    if LastKill[key] and now - LastKill[key] < KillDedupe then
        return false
    end
    LastKill[key] = now
    People:Set(key, { kills = People:Field(key, "kills") + 1, seen = GetServerTime() })
    local guild = People:Field(key, "guild")
    if guild ~= "" and Wars:Has(guild) then
        Wars:Set(guild, { kills = Wars:Field(guild, "kills") + 1 })
    end
    return true
end

-- The card for a hunted enemy (IsHunted) taken down, by you or by a Krew member.
local function Avenged(key, by)
    local kind = Ledger:Field(key, "kind")
    ShowCard({ icon = "Interface\\Icons\\Ability_Rogue_Eviscerate", sound = SOUNDKIT.UI_EPICLOOT_TOAST,
        title = kind == "mark" and "The mark is paid!" or "Vengeance!",
        body = (by and (by .. " took down ") or "You took down ") .. key .. ". " .. Score(key) })
end

--- A Krew member took down key (a KILL message): when the Krew hunts them, the kill counts (once,
--- however many tell of it) and the vengeance card names who did it.
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

--- The player a command is about: a typed name (Warband.PlayerNamed), or your target.
---@param arg string? the command's argument: a full name ("First Last")
---@return table? info nil for a bad name, or no name and no player target
local function Subject(arg)
    local name = Typed(arg)
    if name ~= nil then
        local key = name and PlayerNamed(name, Ledger, People)
        return key and Known(key) or nil
    end
    if UnitExists("target") then
        return Identify("target")
    end
end

-- The guild a war command is about: a typed guild name (Warband.GuildNamed), or your target's guild.
local function GuildSubject(arg)
    local name = Typed(arg)
    if name ~= nil then
        return name and GuildNamed(name, Wars, People) or nil
    end
    local info = UnitExists("target") and Identify("target")
    return info and info.guild ~= "" and info.guild or nil
end

local function Usage(verb, what)
    Addon:Print("Target a player, or name " .. (what or "them") .. ": " .. Addon.Slash[1] .. " " .. verb .. " <name>")
end

local function Rally()
    if not Krew:Ready() then
        return Addon:Print("Rally calls go to your group through Krew messages: join a group and turn Krew messages on.")
    end
    local now = GetTime()
    if LastRally and now - LastRally < RallyCooldown then
        return Addon:Print("Your rally call is still ringing out.")
    end
    LastRally = now
    local mapID, x, y = Position()
    local zone, subZone = Here()
    Krew:Send("RALLY", { tostring(mapID or 0), tostring(x or 0), tostring(y or 0), zone, subZone }, true)
    Addon:Print("Rally call sent to the Krew.")
end

Warband.Status, Warband.Score, Warband.Known, Warband.TakeFoe = Status, Score, Known, TakeFoe
Warband.Describe, Warband.Subject = Describe, Subject
Warband.Remember, Warband.CountDeath = Remember, CountDeath
Warband.Labels, Warband.Icons, Warband.Order = Labels, Icons, Order
Warband.Mark, Warband.HoldGrudge, Warband.Glory, Warband.Forgive = Mark, HoldGrudge, Glory, Forgive
Warband.DeclareWar, Warband.MakePeace = DeclareWar, MakePeace
Warband.SetKind, Warband.Avenge, Warband.HeardSighting, Warband.FreshGathering = SetKind, Avenge, HeardSighting, FreshGathering

WarbandModule = Addon:Module("Warband", {
    label = "Warband (world PvP)",
    page = "Warband",
    uses = { "kills" },
    description = "A ledger of grudges, marks for death, champions and guild wars, shared with your Krew: sightings, vengeance, rallies and enemy gatherings.",
    records = {
        { name = "ledger", limit = LedgerLimit, fields = {
            { name = "kind", kind = "string", default = "grudge", values = { "grudge", "mark", "glory" } },
            { name = "by", kind = "string", default = "" }, -- who marked or honored them
            { name = "since", kind = "number", default = 0, min = 0 },
        } },
        { name = "wars", limit = WarsLimit, evict = "since", fields = {
            { name = "by", kind = "string", default = "" },
            { name = "since", kind = "number", default = 0, min = 0 },
            { name = "kills", kind = "number", default = 0, min = 0, step = 1 },
            { name = "deaths", kind = "number", default = 0, min = 0, step = 1 },
        } },
        { name = "people", limit = PeopleLimit, evict = "seen", keep = function(key) return Ledger:Has(key) end, fields = {
            { name = "class", kind = "string", default = "" },
            { name = "level", kind = "number", default = 0, min = 0, max = 200, step = 1 },
            { name = "faction", kind = "string", default = "", values = { "", "Alliance", "Horde" } },
            { name = "guild", kind = "string", default = "" },
            { name = "kills", kind = "number", default = 0, min = 0, step = 1 },  -- times the Krew killed them
            { name = "deaths", kind = "number", default = 0, min = 0, step = 1 }, -- times they killed the Krew
            { name = "sightings", kind = "number", default = 0, min = 0, step = 1 },
            { name = "seen", kind = "number", default = 0, min = 0 },
            { name = "zone", kind = "string", default = "" },
        } },
    },
    state = {
        { name = "alerts", kind = "boolean", default = true, label = "Sighting alerts",
            description = "A raid warning when someone on the ledger, or a member of a guild at war, shows up: a nameplate, your target or mouseover." },
        { name = "shareSightings", kind = "boolean", default = true, label = "Tell the Krew what I see",
            description = "Report sightings of marked and grudge enemies (and champions in a fight) to your group." },
        { name = "deathPrompt", kind = "boolean", default = true, label = "Ask who killed me",
            description = "When an enemy player kills you, a card names them and offers to hold a grudge. When the game can't say who, it asks about the enemy player you were fighting." },
        { name = "rallyWaypoint", kind = "boolean", default = true, label = "Waypoint to rallies",
            description = "When a Krew member rallies, set a map waypoint to them." },
        { name = "intel", kind = "boolean", default = true, label = "Report enemy gatherings",
            description = "When " .. IntelThreshold .. " or more enemy players gather near you, tell the Krew where." },
    },
    commands = {
        { name = "mark", slash = "mark", label = "Mark your target (or a name) for death, with the Krew", run = function(arg)
            local info = Subject(arg)
            if not info then
                return Usage("mark")
            end
            if Mark(info) then
                Addon:Print(info.key .. " is marked for death.")
            end
        end },
        { name = "unmark", slash = "unmark", label = "Lift a mark for death", run = function(arg)
            local subject = Subject(arg)
            local key = subject and subject.key
            if not key or Status(key) ~= "mark" then
                return Usage("unmark")
            end
            Ledger:Set(key, { kind = "grudge" })
            Krew:Send("UNMARK", key)
            Addon:Print(key .. " is no longer marked.")
        end },
        { name = "grudge", slash = "grudge", label = "Hold a grudge against your target (or a name)", run = function(arg)
            local info = Subject(arg)
            if not info then
                return Usage("grudge")
            end
            if HoldGrudge(info, false) then
                Addon:Print("The Krew holds a grudge against " .. info.key .. ".")
            end
        end },
        { name = "glory", slash = "glory", label = "Grant glory to your target (or a name): a champion the Krew aids", run = function(arg)
            local info = Subject(arg)
            if not info then
                return Usage("glory")
            end
            if Glory(info) then
                Addon:Print(info.key .. " is a champion of the Krew.")
            end
        end },
        { name = "forgive", slash = "forgive", label = "Remove someone from your ledger", run = function(arg)
            local subject = Subject(arg)
            local key = subject and Ledger:Has(subject.key) and subject.key
            if not key then
                return Usage("forgive")
            end
            Forgive(key)
        end },
        { name = "war", slash = "war", label = "Declare war on your target's guild (or a guild by name), with the Krew", run = function(arg)
            local guild = GuildSubject(arg)
            if not guild then
                return Usage("war", "the guild")
            end
            DeclareWar(guild)
        end },
        { name = "peace", slash = "peace", label = "Make peace with a guild", run = function(arg)
            local guild = GuildSubject(arg)
            if not guild or not Wars:Has(guild) then
                return Usage("peace", "the guild")
            end
            MakePeace(guild)
        end },
        { name = "ledger", slash = "ledger", label = "List the ledger and the Krew's wars", run = function()
            Warband.PrintLedger()
        end },
        { name = "rival", slash = "rival", label = "Show your record against your target (or a name)", run = function(arg)
            Warband.PrintRival(arg)
        end },
        { name = "rally", slash = "rally", label = "Call the Krew to your position", run = Rally },
    },
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
        module:On("UPDATE_MOUSEOVER_UNIT", function()
            if UnitExists("mouseover") then
                Seen("mouseover", false, UnitAffectingCombat("mouseover"))
            end
        end)
        Warband.EnableMessages()
        module:OnIncrease("kills.honorable", function(state)
            OnKill(state:Get("kills.victim"))
        end)
    end,
    OnDisable = function()
        Warband.DisableMenus()
        Warband.DisableMessages()
        LastFoe = nil
        wipe(Gathering)
    end,
})
Ledger, Wars, People = WarbandModule.Records.ledger, WarbandModule.Records.wars, WarbandModule.Records.people
Warband.Ledger, Warband.Wars, Warband.People = Ledger, Wars, People
Warband.Module = WarbandModule
