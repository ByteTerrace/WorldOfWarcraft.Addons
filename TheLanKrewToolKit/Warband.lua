local addonName, ns = ...

-- Warband: the Krew's war against the other faction, remembered and shared.
--
-- Three account-wide collections:
--   ledger   the people the Krew chose: grudge (someone who killed one of us), mark (marked for
--            death) and glory (a champion the Krew aids, whatever their faction).
--   wars     guilds the Krew is at war with: every member counts as an enemy of the Krew.
--   people   rivalry records for every enemy player you've met: class, level, guild, times seen,
--            where, and the score (our kills of them against their kills of us). Ledger people
--            are never evicted.
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
--   Status, Score, Subject  a person's standing, their score line, and who a command is about
--   Remember, CountDeath    update a rivalry record; count a Krew member's death to someone
--   TakeFoe                 the prime suspect when you die
--   Labels, Icons, Order    each standing's display name, raid-target icon and sort rank
--   Mark, HoldGrudge, Glory, Forgive, DeclareWar, MakePeace   the ledger and war actions
--   OnNearby                WarbandRadar.lua sets it while it runs; called with the info of each
--                           hostile player seen
--
-- Everything shared goes through ns.Krew (Krew.lua): hidden addon messages to your own group only,
-- rate-limited, never during chat messaging lockdown. Names come from nameplates, your target and
-- mouseover, which the client keeps readable for players outside PvP matches. Your honorable kills
-- and your killers come from Honor.lua's rows.

local LedgerLimit = 300
local PeopleLimit = 1000
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
local IntelCooldown = 300     -- seconds between reports for the same subzone
local SyncCount = 3           -- your own marks (and wars) shared with a Krew member who joins
local SyncAge = 7 * 24 * 3600 -- seconds: older marks and wars aren't shared with one who joins
local Labels = { grudge = "Grudge", mark = "Marked for death", glory = "Champion", war = "At war" }
local Icons = {
    mark = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",   -- skull
    grudge = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", -- cross
    war = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",    -- square
    glory = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",  -- star
}
local Order = { mark = 1, grudge = 2, war = 3, glory = 4 }

local GetRealZoneText, GetServerTime, GetSubZoneText, GetTime, SOUNDKIT = GetRealZoneText, GetServerTime, GetSubZoneText, GetTime, SOUNDKIT
local UnitAffectingCombat, UnitExists = UnitAffectingCombat, UnitExists
local tostring = tostring
local sort = table.sort

local Warband = ns.Warband
local KeyOf, Short, Identify, Hostile, MyKey = Warband.KeyOf, Warband.Short, Warband.Identify, Warband.Hostile, Warband.MyKey
local GuildKey, GuildName, ValidGuildKey = Warband.GuildKey, Warband.GuildName, Warband.ValidGuildKey
local ValidKey, CleanText, CleanLevel, CleanFaction = Warband.ValidKey, Warband.CleanText, Warband.CleanLevel, Warband.CleanFaction
local InfoFields, InfoFrom = Warband.InfoFields, Warband.InfoFrom
local Where, Position, SetWaypoint, Alert = Warband.Where, Warband.Position, Warband.SetWaypoint, Warband.Alert
local Addon = ns.Addon
local Krew, ShowCard = ns.Krew, ns.Cards.Show

local WarbandModule
local Ledger, Wars, People -- the module's collections, bound when it's declared
local LastAlert, LastShared, LastKill = {}, {}, {} -- [key] = GetTime() of the last alert, Krew report, counted kill
local LastGuildAlert = {} -- [guild key] = GetTime()
local Gathering = {}      -- [key] = GetTime() of a hostile player's nameplate
local LastIntel = {}      -- [zone .. "/" .. subZone] = GetTime() of the last report
local LastFoe             -- the info of the hostile player you last targeted, plus its time
local LastRally           -- GetTime() of your last rally call
local Synced = {}         -- [sender] = true once a Krew member who joined has heard your marks and wars

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

-- "Bob (60 Rogue)", with whatever the rivalry record knows.
local function Describe(key)
    local level, class = People:Field(key, "level"), People:Field(key, "class")
    local who = Short(key)
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
    return ("Krew %d : %d %s"):format(People:Field(key, "kills"), People:Field(key, "deaths"), Short(key))
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
    end
    People:Set(key, values)
end

local function SetKind(key, kind, by)
    local values = { kind = kind, by = by or "" }
    if not Ledger:Has(key) then
        values.since = GetServerTime()
    end
    Ledger:Set(key, values)
end

-- The kind a grudge sets: a mark stays a mark.
local function GrudgeKind(key)
    return Ledger:Has(key) and Ledger:Field(key, "kind") == "mark" and "mark" or "grudge"
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
local function HoldGrudge(info, died, counted)
    local key = info.key
    Remember(key, info)
    SetKind(key, GrudgeKind(key), Ledger:Has(key) and Ledger:Field(key, "by") or "")
    if died and not counted then
        CountDeath(key)
    end
    local fields = InfoFields(info)
    fields[5] = died and "1" or "0"
    Krew.Send("GRUDGE", fields)
end

--- Marks a player for death, with the Krew.
---@param info table
local function Mark(info)
    Remember(info.key, info)
    SetKind(info.key, "mark", Short(MyKey()))
    Krew.Send("MARK", InfoFields(info))
end

--- Grants a player glory, with the Krew: a champion the Krew aids.
---@param info table
local function Glory(info)
    Remember(info.key, info)
    SetKind(info.key, "glory", Short(MyKey()))
    Krew.Send("GLORY", InfoFields(info))
end

--- Removes a player from your ledger. The Krew isn't told: each member forgives for themselves.
---@param key string
local function Forgive(key)
    Ledger:Remove(key)
    Addon:Print("Forgave " .. Short(key) .. ".")
end

--- Declares war on a guild, with the Krew.
---@param guild string a guild key
local function DeclareWar(guild)
    if not Wars:Has(guild) then
        Wars:Set(guild, { by = Short(MyKey()), since = GetServerTime() })
    end
    Krew.Send("WAR", guild)
    Addon:Print("The Krew is at war with <" .. GuildName(guild) .. ">.")
end

--- Makes peace with a guild, with the Krew.
---@param guild string a guild key
local function MakePeace(guild)
    Wars:Remove(guild)
    Krew.Send("PEACE", guild)
    Addon:Print("The Krew made peace with <" .. GuildName(guild) .. ">.")
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
        Krew.Send("SIGHT", { key, CleanText(GetRealZoneText()), CleanText(GetSubZoneText()), fighting and "1" or "0" })
    end
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
    local zone, subZone = CleanText(GetRealZoneText()), CleanText(GetSubZoneText())
    local place = zone .. "/" .. subZone
    if count >= IntelThreshold and not (LastIntel[place] and now - LastIntel[place] < IntelCooldown) then
        local mapID, x, y = Position()
        LastIntel[place] = now
        Krew.Send("INTEL", { tostring(count), info.faction, tostring(mapID or 0), tostring(x or 0), tostring(y or 0), zone, subZone })
    end
end

-- A player unit came into view (nameplate, target or mouseover).
local function Seen(unit, fromNameplate)
    local info = Identify(unit)
    if not info then
        return
    end
    local key, hostile = info.key, Hostile(unit)
    if hostile and fromNameplate then
        CountGathering(info)
    end
    if hostile and Warband.OnNearby then
        Warband.OnNearby(info)
    end
    local status = Status(key, info.guild)
    if not hostile and not status then
        return -- friendly strangers aren't rivals
    end
    local now = GetServerTime()
    if not People:Has(key) or now - People:Field(key, "seen") >= SeenWriteInterval then
        Remember(key, info, { seen = now, zone = CleanText(GetRealZoneText()), sightings = People:Field(key, "sightings") + 1 })
    end
    if status then
        AlertFor(key, status, info, unit)
    end
end

-- Hostile players you target (or mouse over in combat) are the prime suspect if you die.
local function Suspect(unit)
    if Hostile(unit) then
        local info = Identify(unit)
        if info then
            info.time = GetTime()
            LastFoe = info
        end
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

local function Avenged(key, by)
    local kind = Ledger:Has(key) and Ledger:Field(key, "kind")
    if kind ~= "mark" and kind ~= "grudge" then
        return
    end
    ShowCard({ icon = "Interface\\Icons\\Ability_Rogue_Eviscerate", sound = SOUNDKIT.UI_EPICLOOT_TOAST,
        title = kind == "mark" and "The mark is paid!" or "Vengeance!",
        body = (by and (by .. " took down ") or "You took down ") .. Short(key) .. ". " .. Score(key) })
end

-- An honorable kill of victim (Honor.victim, Honor.lua).
local function OnKill(victim)
    local key = KeyOf(victim)
    if CountKill(key) then
        Avenged(key)
        if Status(key) == "mark" or Status(key) == "grudge" then
            Krew.Send("KILL", key)
        end
    end
end

--- The player a command is about: a typed name, or your target.
---@param arg string? the command's argument; a name with or without its realm
---@return table? info nil for a bad name, or no name and no player target
local function Subject(arg)
    arg = arg and arg:match("^%s*(%S+)%s*$")
    if arg then
        if arg:find("|", 1, true) or #arg > 64 then
            return nil
        end
        local key = KeyOf(arg)
        return ValidKey(key) and { key = key, class = "", level = 0, faction = "", guild = "" } or nil
    end
    if UnitExists("target") then
        return Identify("target")
    end
end

local function Usage(verb, what)
    Addon:Print("Target a player, or name " .. (what or "them") .. ": " .. Addon.Slash[1] .. " " .. verb .. " <name>")
end

-- The key in a collection matching a typed name, ignoring case ("bob" finds "Bob-Realm").
local function Find(collection, key)
    if collection:Has(key) then
        return key
    end
    local wanted = key:lower()
    for _, candidate in ipairs(collection:Keys()) do
        if candidate:lower() == wanted then
            return candidate
        end
    end
end

-- The guild a war command is about: a typed guild name, or your target's guild.
local function GuildSubject(arg)
    local name = arg and arg:match("^%s*(.-)%s*$")
    if name and name ~= "" then
        local key = name:find("-", 1, true) and name or GuildKey(name)
        return ValidGuildKey(key) and (Find(Wars, key) or key) or nil
    end
    local info = UnitExists("target") and Identify("target")
    return info and info.guild ~= "" and info.guild or nil
end

local function PrintLedger()
    local keys = Ledger:Keys()
    if #keys == 0 and Wars:Count() == 0 then
        Addon:Print("The ledger is empty. Mark someone with " .. Addon.Slash[1] .. " mark.")
        return
    end
    sort(keys, function(a, b)
        local rankA, rankB = Order[Ledger:Field(a, "kind")], Order[Ledger:Field(b, "kind")]
        if rankA ~= rankB then
            return rankA < rankB
        end
        return People:Field(a, "seen") > People:Field(b, "seen")
    end)
    Addon:Print(("The ledger (%d):"):format(#keys))
    for _, key in ipairs(keys) do
        local kind, zone = Ledger:Field(key, "kind"), People:Field(key, "zone")
        local line = "  " .. Labels[kind] .. ": " .. Describe(key)
        if kind ~= "glory" then
            line = line .. " - " .. Score(key)
        end
        if zone ~= "" then
            line = line .. " - last seen in " .. zone
        end
        print(line)
    end
    for _, guild in ipairs(Wars:Keys()) do
        print(("  At war: <%s> - Krew %d : %d them"):format(GuildName(guild), Wars:Field(guild, "kills"), Wars:Field(guild, "deaths")))
    end
end

local function PrintRival(arg)
    local subject = Subject(arg)
    local key = subject and Find(People, subject.key)
    if not key then
        return Addon:Print("No record of " .. (subject and Short(subject.key) or "them") .. " yet.")
    end
    local guild, status = People:Field(key, "guild"), Status(key)
    Addon:Print(Describe(key) .. (guild ~= "" and (" of <" .. GuildName(guild) .. ">") or "")
        .. (status and (" - " .. Labels[status]) or ""))
    print(("  %s. Seen %d times, last in %s."):format(Score(key), People:Field(key, "sightings"),
        People:Field(key, "zone") ~= "" and People:Field(key, "zone") or "parts unknown"))
end

local function Rally()
    if not Krew.Ready() then
        return Addon:Print("Rally calls go to your group through Krew messages: join a group and turn Krew messages on.")
    end
    local now = GetTime()
    if LastRally and now - LastRally < RallyCooldown then
        return Addon:Print("Your rally call is still ringing out.")
    end
    LastRally = now
    local mapID, x, y = Position()
    Krew.Send("RALLY", { tostring(mapID or 0), tostring(x or 0), tostring(y or 0),
        CleanText(GetRealZoneText()), CleanText(GetSubZoneText()) }, true)
    Addon:Print("Rally call sent to the Krew.")
end

Warband.Status, Warband.Score, Warband.Subject, Warband.TakeFoe = Status, Score, Subject, TakeFoe
Warband.Remember, Warband.CountDeath = Remember, CountDeath
Warband.Labels, Warband.Icons, Warband.Order = Labels, Icons, Order
Warband.Mark, Warband.HoldGrudge, Warband.Glory, Warband.Forgive = Mark, HoldGrudge, Glory, Forgive
Warband.DeclareWar, Warband.MakePeace = DeclareWar, MakePeace

WarbandModule = Addon:Module("Warband", {
    label = "Warband (world PvP)",
    page = "Warband",
    description = "A ledger of grudges, marks for death, champions and guild wars, shared with your Krew: sightings, vengeance, rallies and enemy gatherings.",
    records = {
        { name = "ledger", limit = LedgerLimit, evict = "since", fields = {
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
            Mark(info)
            Addon:Print(Short(info.key) .. " is marked for death.")
        end },
        { name = "unmark", slash = "unmark", label = "Lift a mark for death", run = function(arg)
            local subject = Subject(arg)
            local key = subject and Find(Ledger, subject.key)
            if not key or Ledger:Field(key, "kind") ~= "mark" then
                return Usage("unmark")
            end
            Ledger:Set(key, { kind = "grudge" })
            Krew.Send("UNMARK", key)
            Addon:Print(Short(key) .. " is no longer marked.")
        end },
        { name = "grudge", slash = "grudge", label = "Hold a grudge against your target (or a name)", run = function(arg)
            local info = Subject(arg)
            if not info then
                return Usage("grudge")
            end
            HoldGrudge(info, false)
            Addon:Print("The Krew holds a grudge against " .. Short(info.key) .. ".")
        end },
        { name = "glory", slash = "glory", label = "Grant glory to your target (or a name): a champion the Krew aids", run = function(arg)
            local info = Subject(arg)
            if not info then
                return Usage("glory")
            end
            Glory(info)
            Addon:Print(Short(info.key) .. " is a champion of the Krew.")
        end },
        { name = "forgive", slash = "forgive", label = "Remove someone from your ledger", run = function(arg)
            local subject = Subject(arg)
            local key = subject and Find(Ledger, subject.key)
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
            guild = guild and Find(Wars, guild)
            if not guild then
                return Usage("peace", "the guild")
            end
            MakePeace(guild)
        end },
        { name = "ledger", slash = "ledger", label = "List the ledger and the Krew's wars", run = PrintLedger },
        { name = "rival", slash = "rival", label = "Show your record against your target (or a name)", run = PrintRival },
        { name = "rally", slash = "rally", label = "Call the Krew to your position", run = Rally },
    },
    OnEnable = function(module)
        Warband.EnableMenus()
        module:On("NAME_PLATE_UNIT_ADDED", function(unit)
            Seen(unit, true)
        end)
        module:On("PLAYER_TARGET_CHANGED", function()
            if UnitExists("target") then
                Suspect("target")
                Seen("target", false)
            end
        end)
        module:On("UPDATE_MOUSEOVER_UNIT", function()
            if UnitExists("mouseover") then
                if UnitAffectingCombat("mouseover") then
                    Suspect("mouseover")
                end
                Seen("mouseover", false)
            end
        end)
        local kills = module:Get("Honor.kills")
        module:Watch({ "Honor.kills" }, function(state)
            local now = state:Get("Honor.kills")
            if now > kills then
                OnKill(state:Get("Honor.victim"))
            end
            kills = now
        end, true)
    end,
    OnDisable = function()
        Warband.DisableMenus()
        LastFoe = nil
        wipe(Gathering)
    end,
})
Ledger, Wars, People = WarbandModule.Records.ledger, WarbandModule.Records.wars, WarbandModule.Records.people
Warband.Ledger, Warband.Wars, Warband.People = Ledger, Wars, People

-- Messages from the Krew only update the collections and show an alert or card; none acts on your
-- behalf, and none is heard while Warband is off.

Krew.Listen("GRUDGE", function(sender, fields)
    local info = WarbandModule.Enabled and InfoFrom(fields)
    if not info then
        return
    end
    local key, died = info.key, fields[5] == "1"
    Remember(key, info)
    SetKind(key, GrudgeKind(key), Ledger:Has(key) and Ledger:Field(key, "by") or "")
    if died then
        CountDeath(key)
        ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_Rampage", sound = SOUNDKIT.RAID_WARNING,
            title = Short(key) .. " killed " .. sender .. "!", body = "The Krew remembers. " .. Score(key) })
    end
end)

Krew.Listen("MARK", function(sender, fields)
    local info = WarbandModule.Enabled and InfoFrom(fields)
    if not info then
        return
    end
    local known = Status(info.key) == "mark"
    Remember(info.key, info)
    if known then
        return -- a mark synced again when someone joins
    end
    SetKind(info.key, "mark", sender)
    ShowCard({ icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", sound = SOUNDKIT.RAID_WARNING,
        title = "Marked for death", body = sender .. " marked " .. Describe(info.key) .. ". Hunt them down." })
end)

Krew.Listen("UNMARK", function(_, fields)
    local key = WarbandModule.Enabled and ValidKey(fields[1]) and fields[1]
    if key and Ledger:Has(key) and Ledger:Field(key, "kind") == "mark" then
        Ledger:Set(key, { kind = "grudge" })
    end
end)

Krew.Listen("GLORY", function(sender, fields)
    local info = WarbandModule.Enabled and InfoFrom(fields)
    if not info then
        return
    end
    Remember(info.key, info)
    SetKind(info.key, "glory", sender)
    ShowCard({ icon = "Interface\\Icons\\Achievement_PVP_H_01", sound = SOUNDKIT.LFG_REWARDS,
        title = "A champion of the Krew", body = sender .. " granted glory to " .. Describe(info.key) .. ". Aid them when you see them." })
end)

Krew.Listen("WAR", function(sender, fields)
    local guild = WarbandModule.Enabled and ValidGuildKey(fields[1]) and fields[1]
    if not guild or Wars:Has(guild) then
        return
    end
    Wars:Set(guild, { by = sender, since = GetServerTime() })
    ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = SOUNDKIT.RAID_WARNING,
        title = "War!", body = sender .. " declared war on <" .. GuildName(guild) .. ">. Every member is an enemy of the Krew." })
end)

Krew.Listen("PEACE", function(_, fields)
    local guild = WarbandModule.Enabled and ValidGuildKey(fields[1]) and fields[1]
    if guild then
        Wars:Remove(guild)
    end
end)

Krew.Listen("SIGHT", function(sender, fields)
    local key = WarbandModule.Enabled and ValidKey(fields[1]) and fields[1]
    local status = key and Status(key)
    if not status then
        return
    end
    LastShared[key] = GetTime() -- someone already told the Krew
    if not WarbandModule:Get("alerts") then
        return
    end
    local where = Where(CleanText(fields[2]), CleanText(fields[3]))
    if status == "glory" then
        Alert(sender .. ": champion " .. Short(key) .. " needs aid at " .. where .. "!", SOUNDKIT.READY_CHECK)
    else
        Alert(sender .. " spotted " .. Describe(key) .. " at " .. where .. "!", SOUNDKIT.RAID_WARNING)
    end
end)

Krew.Listen("KILL", function(sender, fields)
    local key = WarbandModule.Enabled and ValidKey(fields[1]) and fields[1]
    local status = key and Status(key)
    if (status == "mark" or status == "grudge") and CountKill(key) then
        Avenged(key, sender)
    end
end)

Krew.Listen("RALLY", function(sender, fields)
    if not WarbandModule.Enabled then
        return
    end
    local where = Where(CleanText(fields[4]), CleanText(fields[5]))
    Alert("|cffff2020RALLY!|r " .. sender .. " needs the Krew at " .. where .. "!", SOUNDKIT.READY_CHECK)
    if WarbandModule:Get("rallyWaypoint") and SetWaypoint(fields[1], fields[2], fields[3]) then
        Addon:Print("Waypoint set to " .. sender .. "'s rally.")
    end
end)

Krew.Listen("INTEL", function(sender, fields)
    local count = WarbandModule.Enabled and CleanLevel(fields[1])
    if not count or count < 1 then
        return
    end
    local faction, where = CleanFaction(fields[2]), Where(CleanText(fields[6]), CleanText(fields[7]))
    local mapID, x, y = fields[3], fields[4], fields[5]
    ShowCard({ icon = "Interface\\Icons\\Ability_Hunter_SniperShot", sound = SOUNDKIT.RAID_WARNING,
        title = "Enemy gathering",
        body = sender .. " sees " .. count .. " " .. (faction ~= "" and faction or "enemy") .. " players at " .. where .. ". Click for a waypoint.",
        onClick = function()
            SetWaypoint(mapID, x, y)
        end })
end)

-- A Krew member who joins hears about the marks and wars you declared recently.
Krew.Listen("HELLO", function(sender)
    if not WarbandModule.Enabled or Synced[sender] then
        return
    end
    Synced[sender] = true
    local me, now = Short(MyKey()), GetServerTime()
    local function Recent(collection, predicate)
        local found = {}
        for _, key in ipairs(collection:Keys()) do
            if collection:Field(key, "by") == me and now - collection:Field(key, "since") <= SyncAge and predicate(key) then
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
        local key = marks[i]
        Krew.Send("MARK", { key, People:Field(key, "class"), tostring(People:Field(key, "level")), People:Field(key, "faction") })
    end
    local declared = Recent(Wars, function()
        return true
    end)
    for i = 1, math.min(SyncCount, #declared) do
        Krew.Send("WAR", declared[i])
    end
end)
