local addonName, ns = ...

-- WarbandUtil: Warband's pure helpers over the WoW API. It creates ns.Warband, the table the
-- Warband files share; Warband.lua adds the collections, the standing rules and the ledger actions.
--
--   Identity   KeyOf, Short, MyKey, Identify, Hostile, GuildKey, GuildName
--   Messages   ValidKey, ValidGuildKey, CleanText, CleanClass, CleanLevel, CleanFaction,
--              InfoFields, InfoFrom
--   Places     Where, Position, SetWaypoint
--   Alerts     Alert
--
-- A player's key is "Name-Realm" and a guild's is "Guild Name-Realm". An info is what Identify
-- returns: { key, class, level, faction, guild }. Every field of a Krew message goes through a
-- Valid or Clean function before use, and none of them passes a "|": someone else's message never
-- puts a link, texture or color on your screen.

local MaxText = 60 -- longest zone or subzone accepted from a message
local Factions = { Alliance = true, Horde = true }

local C_Map, C_Sound, C_SuperTrack = C_Map, C_Sound, C_SuperTrack
local Ambiguate, ChatTypeInfo, GetGuildInfo, GetNormalizedRealmName, RaidWarningUtil, UiMapPoint = Ambiguate, ChatTypeInfo, GetGuildInfo, GetNormalizedRealmName, RaidWarningUtil, UiMapPoint
local UnitClass, UnitFactionGroup, UnitIsEnemy, UnitIsPlayer, UnitLevel, UnitName = UnitClass, UnitFactionGroup, UnitIsEnemy, UnitIsPlayer, UnitLevel, UnitName
local issecretvalue, floor, tonumber, tostring, type = issecretvalue, math.floor, tonumber, tostring, type

local function MyRealm()
    return GetNormalizedRealmName() or ""
end

--- A player's key from a name that may lack its realm (a player on your own realm).
---@param name string "Name" or "Name-Realm"
---@return string
local function KeyOf(name)
    if name:find("-", 1, true) then
        return name
    end
    return name .. "-" .. MyRealm()
end

--- A key's short form for display: "Bob" on your realm, "Bob-Other" elsewhere.
---@param key string
---@return string
local function Short(key)
    return Ambiguate(key, "none")
end

--- A guild's key. Guild names have no hyphens, so the last one in a key starts the realm.
---@param name string the guild's name
---@param realm string? nil or "" for your own realm
---@return string
local function GuildKey(name, realm)
    return name .. "-" .. ((realm and realm ~= "") and realm or MyRealm())
end

--- A guild key's name, for display.
---@param key string
---@return string
local function GuildName(key)
    return key:match("^(.*)%-[^%-]*$") or key
end

-- The unit's guild key, or "" for none or a secret one.
local function GuildOf(unit)
    local name, _, _, realm = GetGuildInfo(unit)
    if issecretvalue(name) or issecretvalue(realm) or type(name) ~= "string" or name == "" then
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
    local name, realm = UnitName(unit)
    if issecretvalue(name) then
        return nil
    end
    if issecretvalue(realm) then
        return nil
    end
    if not name or name == "" then
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
        key = name .. "-" .. ((realm and realm ~= "") and realm or MyRealm()),
        class = class,
        level = (level and level > 0) and level or 0,
        faction = Factions[faction] and faction or "",
        guild = GuildOf(unit),
    }
end

--- Whether the unit is an enemy of yours.
---@param unit string
---@return boolean
local function Hostile(unit)
    return UnitIsEnemy("player", unit) and true or false
end

--- Your own key, or "" while your name is unreadable.
---@return string
local function MyKey()
    local name = UnitName("player")
    if issecretvalue(name) or not name then
        return ""
    end
    return name .. "-" .. MyRealm()
end

--- Whether a message field is a player key: "Name-Realm", at most 64 bytes, no spaces or "|".
---@param key string?
---@return boolean
local function ValidKey(key)
    return key and #key <= 64 and key:match("^[^%s|%-]+%-[^%s|]+$") ~= nil
end

--- Whether a message field is a guild key: at most 64 bytes, no "|" or control characters, and a
--- realm without spaces.
---@param key string?
---@return boolean
local function ValidGuildKey(key)
    return key and #key <= 64 and key:match("^[^|%c%-]+%-[^%s|%-]+$") ~= nil
end

--- A zone or subzone from a message, or "" when it's too long or contains "|".
---@param text string?
---@return string
local function CleanText(text)
    if not text or #text > MaxText or text:find("|", 1, true) then
        return ""
    end
    return text
end

--- A class file from a message (up to 12 capital letters), or "".
---@param class string?
---@return string
local function CleanClass(class)
    return (class and #class <= 12 and class:match("^%u+$")) and class or ""
end

--- A level from a message (a whole number from 0 to 200), or 0.
---@param level string|number?
---@return integer
local function CleanLevel(level)
    level = tonumber(level)
    return (level and level >= 0 and level <= 200 and level == floor(level)) and level or 0
end

--- "Alliance" or "Horde" from a message, or "".
---@param faction string?
---@return string
local function CleanFaction(faction)
    return Factions[faction] and faction or ""
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

--- A place for display: "Subzone (Zone)", the zone alone, or "somewhere".
---@param zone string cleaned
---@param subZone string cleaned
---@return string
local function Where(zone, subZone)
    if subZone ~= "" and zone ~= "" and subZone ~= zone then
        return subZone .. " (" .. zone .. ")"
    end
    return zone ~= "" and zone or "somewhere"
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
    return mapID, floor(x * 10000 + 0.5), floor(y * 10000 + 0.5)
end

--- Sets and tracks a map waypoint from message fields (see Position). Refuses fields out of range
--- and maps that take no waypoint.
---@param mapID string|number
---@param x string|number
---@param y string|number
---@return boolean set
local function SetWaypoint(mapID, x, y)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not (mapID and mapID > 0 and x and y and x >= 0 and x <= 10000 and y >= 0 and y <= 10000) then
        return false
    end
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 10000, y / 10000))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    return true
end

--- A raid warning on your own screen.
---@param text string
---@param sound integer? a SOUNDKIT id
local function Alert(text, sound)
    RaidWarningUtil.AddMessage(text, ChatTypeInfo.RAID_WARNING)
    if sound then
        C_Sound.PlaySound(sound)
    end
end

ns.Warband = {
    KeyOf = KeyOf, Short = Short, MyKey = MyKey, Identify = Identify, Hostile = Hostile, GuildKey = GuildKey,
    GuildName = GuildName, ValidKey = ValidKey, ValidGuildKey = ValidGuildKey, CleanText = CleanText,
    CleanClass = CleanClass, CleanLevel = CleanLevel, CleanFaction = CleanFaction, InfoFields = InfoFields,
    InfoFrom = InfoFrom, Where = Where, Position = Position, SetWaypoint = SetWaypoint,
    Alert = Alert,
}
