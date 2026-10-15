local addonName, ns = ...

-- WarbandUtil: Warband's pure helpers over the WoW API. It creates ns.Warband, the table the
-- Warband files share; Warband.lua adds the collections, the standing rules and the ledger actions.
--
--   Identity   KeyOf, MyKey, Identify, Hostile, GuildName
--   Messages   ValidKey, ValidGuildKey, CleanClass, CleanLevel, CleanFaction, InfoFields, InfoFrom
--              (text and counts go through ns.KrewFields, Krew.lua)
--   Places     Here, Where, Position, SetWaypoint
--   Commands   Typed, PlayerNamed, GuildNamed: what a command's typed name means, looked up in
--              the collections Warband.lua passes in
--
-- A player's key is their full name, "First Last" (ByteTerrace_Core's Names.lua: Forever's names
-- are unique in the region, so no realm), and a guild's is "Guild Name-Realm". An info is what
-- Identify returns: { key, class, level, faction, guild }. Every field of a Krew message goes through a
-- Valid or Clean function before use, and none of them passes a "|": someone else's message never
-- puts a link, texture or color on your screen.

local Factions = { Alliance = true, Horde = true }

local C_Map, C_SuperTrack = C_Map, C_SuperTrack
local CleanCount, CleanText, MaxLevel = ns.KrewFields.CleanCount, ns.KrewFields.CleanText, ns.KrewFields.MaxLevel
local floor, ipairs, issecretvalue, tonumber, tostring, type = math.floor, ipairs, issecretvalue, tonumber, tostring, type
local GetGuildInfo, GetNormalizedRealmName, GetRealZoneText, GetSubZoneText, UiMapPoint = GetGuildInfo, GetNormalizedRealmName, GetRealZoneText, GetSubZoneText, UiMapPoint
local Names = ByteTerrace.Names
local UnitClass, UnitFactionGroup, UnitIsEnemy, UnitIsPlayer, UnitLevel = UnitClass, UnitFactionGroup, UnitIsEnemy, UnitIsPlayer, UnitLevel

local function MyRealm()
    return (GetNormalizedRealmName() or "")
end

--- A player's key from a name as text gives it (a chat sender, a recap, an honor message, a
--- typed name): the full name, without any "-Realm" suffix.
---@param name string "First Last", maybe with "-Realm"
---@return string
local function KeyOf(name)
    return Names.Plain(name)
end

--- A guild's key. Guild names have no hyphens, so the last one in a key starts the realm.
---@param name string the guild's name
---@param realm string? nil or "" for your own realm
---@return string
local function GuildKey(name, realm)
    return (name .. "-" .. (((realm and (realm ~= "")) and realm) or MyRealm()))
end

--- A guild key's name, for display.
---@param key string
---@return string
local function GuildName(key)
    return (key:match("^(.*)%-[^%-]*$") or key)
end

-- The unit's guild key, or "" for none or a secret one.
local function GuildOf(unit)
    local name, _, _, realm = GetGuildInfo(unit)

    if issecretvalue(name) or issecretvalue(realm) or (type(name) ~= "string") or (name == "") then
        return ""
    end
    return GuildKey(name, realm)
end

--- What the client lets addons know about a player unit.
---@param unit string
---@return table? info { key, class (a class file or ""), level (0 when unknown), faction ("" when unknown), guild (a guild key or "") }; nil for a non-player or a player whose name is secret
local function Identify(unit)
    if not UnitIsPlayer(unit) then
        return nil
    end
    local key = Names.OfUnit(unit)

    if not key then
        return nil
    end
    local _, classFile = UnitClass(unit)
    local class = ""

    if not issecretvalue(classFile) and classFile then
        class = classFile
    end
    local level = UnitLevel(unit)
    local faction = UnitFactionGroup(unit)

    return {
        key = key,
        class = class,
        level = (((level and (level > 0)) and level) or 0),
        faction = ((Factions[faction] and faction) or ""),
        guild = GuildOf(unit),
    }
end

--- Whether the unit is an enemy of yours.
---@param unit string
---@return boolean
local function Hostile(unit)
    return ((UnitIsEnemy("player", unit) and true) or false)
end

--- Your own key, or "" while your name is unreadable.
---@return string
local function MyKey()
    return (Names.Mine() or "")
end

--- Whether a message field is a player key: a full name of at most 64 bytes, with no "|", "-" or
--- control characters and no space at either end.
---@param key string?
---@return boolean
local function ValidKey(key)
    return (key and (#key <= 64) and (key:match("^[^%s|%c%-][^|%c%-]*[^%s|%c%-]$") ~= nil))
end

--- Whether a message field is a guild key: at most 64 bytes, no "|" or control characters, and a
--- realm without spaces.
---@param key string?
---@return boolean
local function ValidGuildKey(key)
    return (key and (#key <= 64) and (key:match("^[^|%c%-]+%-[^%s|%-]+$") ~= nil))
end

--- A class file from a message (up to 12 capital letters), or "".
---@param class string?
---@return string
local function CleanClass(class)
    return (((class and (#class <= 12) and class:match("^%u+$")) and class) or "")
end

--- A level from a message (a whole number from 1 to MaxLevel, in digits), or 0.
---@param level string?
---@return integer
local function CleanLevel(level)
    return (CleanCount(level, MaxLevel) or 0)
end

--- "Alliance" or "Horde" from a message, or "".
---@param faction string?
---@return string
local function CleanFaction(faction)
    return ((Factions[faction] and faction) or "")
end

--- An info's first four message fields: key, class, level and faction.
---@param info table
---@return string[]
local function InfoFields(info)
    return { info.key, info.class, tostring(info.level), info.faction }
end

--- An info from the first four fields of a message (guild is left out), or nil for a bad key.
---@param fields string[]
---@return table?
local function InfoFrom(fields)
    if not ValidKey(fields[1]) then
        return nil
    end
    return { key = fields[1], class = CleanClass(fields[2]), level = CleanLevel(fields[3]), faction = CleanFaction(fields[4]) }
end

-- The key in a collection matching key, ignoring case ("bob doe" finds "Bob Doe").
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

--- A command's typed text: trimmed, nil when empty, false when it can't name anyone (a "|", or
--- over 64 bytes).
---@param arg string?
---@return string|false|nil
local function Typed(arg)
    arg = (arg and arg:match("^%s*(.-)%s*$"))
    if not arg or (arg == "") then
        return nil
    end
    return (not arg:find("|", 1, true) and (#arg <= 64) and arg)
end

--- The player key a typed name means: the key in ledger, else people, that matches it ignoring
--- case, else the name capitalized as the client writes names ("cara doe" is "Cara Doe").
---@param name string Typed's text
---@param ledger table the ledger collection
---@param people table the rivalry records
---@return string? key nil when it can't be a key
local function PlayerNamed(name, ledger, people)
    local key = KeyOf(name)

    key = (Find(ledger, key) or Find(people, key) or key:gsub("(%S)(%S*)", function(first, rest)
        return (first:upper() .. rest:lower())
    end))
    return ((ValidKey(key) and key) or nil)
end

--- The guild key a typed guild name ("Name" or "Name-Realm") means: the war, else a rivalry
--- record's guild, that matches it ignoring case, else the name as typed; typed all in lowercase,
--- with each word capitalized (guild names keep small words small: "Knights of Light").
---@param name string Typed's text
---@param wars table the wars collection
---@param people table the rivalry records
---@return string? key nil when it can't be a guild key
local function GuildNamed(name, wars, people)
    local key = ((name:find("-", 1, true) and name) or GuildKey(name))
    local found = Find(wars, key)

    if not found then
        local wanted = key:lower()

        for _, person in ipairs(people:Keys()) do
            local guild = people:Field(person, "guild")

            if guild:lower() == wanted then
                found = guild
                break
            end
        end
    end
    local guildName, realm = key:match("^(.*)%-([^%-]*)$")

    if not found and not guildName:find("%u") then
        found = (guildName:gsub("(%S)(%S*)", function(first, rest)
            return (first:upper() .. rest)
        end) .. "-" .. realm)
    end
    found = (found or key)
    return ((ValidGuildKey(found) and found) or nil)
end

--- Where you are, as a message's zone and subzone fields (each cleaned, "" when unknown).
---@return string zone
---@return string subZone
local function Here()
    return CleanText(GetRealZoneText()), CleanText(GetSubZoneText())
end

--- A place for display: "Subzone (Zone)", the zone alone, or "somewhere".
---@param zone string cleaned
---@param subZone string cleaned
---@return string
local function Where(zone, subZone)
    if (subZone ~= "") and (zone ~= "") and (subZone ~= zone) then
        return (subZone .. " (" .. zone .. ")")
    end
    return (((zone ~= "") and zone) or "somewhere")
end

--- Your position as message fields, or nothing where the map has none.
---@return integer? mapID
---@return integer? x 0 to 10000
---@return integer? y 0 to 10000
local function Position()
    local mapID = C_Map.GetBestMapForUnit("player")

    if not mapID then
        return nil
    end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")

    if not position then
        return nil
    end
    local x, y = position:GetXY()

    return mapID, floor((x * 10000) + 0.5), floor((y * 10000) + 0.5)
end

-- A message field that's a whole number from 0 to max written in digits only (no sign, exponent,
-- hex, fraction or "inf"), as a number; nil otherwise.
local function Digits(text, max)
    if (type(text) ~= "string") or (#text > 9) or not text:find("^%d+$") then
        return nil
    end
    local n = tonumber(text)

    return (((n <= max) and n) or nil)
end

--- Sets and tracks a map waypoint from message fields (see Position): each a whole number in
--- digits, the position 0 to 10000. Refuses anything else and maps that take no waypoint.
---@param mapID string
---@param x string
---@param y string
---@return boolean set
local function SetWaypoint(mapID, x, y)
    mapID, x, y = Digits(mapID, 999999999), Digits(x, 10000), Digits(y, 10000)
    if not (mapID and (mapID > 0) and x and y) then
        return false
    end
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 10000, y / 10000))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    return true
end

ns.Warband = {
    CleanClass = CleanClass, CleanFaction = CleanFaction, CleanLevel = CleanLevel, GuildName = GuildName,
    GuildNamed = GuildNamed, Here = Here, Hostile = Hostile, Identify = Identify, InfoFields = InfoFields,
    InfoFrom = InfoFrom, KeyOf = KeyOf, MyKey = MyKey, PlayerNamed = PlayerNamed, Position = Position,
    SetWaypoint = SetWaypoint, Typed = Typed, ValidGuildKey = ValidGuildKey, ValidKey = ValidKey, Where = Where,
}
