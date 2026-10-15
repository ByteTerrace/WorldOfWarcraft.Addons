-- The world around the player in the fake client: location and maps, the user waypoint, honor
-- and raid warnings (see wow.lua for the rest). Only what the addons call is modeled.
--
-- State: h.zone, h.subZone (GetRealZoneText, GetSubZoneText), h.mapID (the uiMapID the player is on),
-- h.mapPosition = { x, y } (normalized to h.mapID), h.instance (nil, or IsInInstance's type:
-- "party", "raid", "pvp", "arena", "scenario"), h.maps = { [uiMapID] = { name, mapType, parentMapID,
-- flags, canSetWaypoint } } (h:AddMap), h.waypoint ({ uiMapID, x, y, z } or nil), h.superTracked
-- (the user waypoint is super tracked) and h.raidNotices ({ text, color, displayTime } per raid
-- warning message).
--
-- Modeling decisions ([D] documented, [G] a guess where the docs are silent):
--   Zones       [D] ZONE_CHANGED_NEW_AREA fires on entering a new zone, ZONE_CHANGED on entering
--               an outdoors subzone (warcraft.wiki.gg event pages). [G] h:SetLocation fires only
--               ZONE_CHANGED_NEW_AREA when the zone changes (even if the subzone does too), and
--               ZONE_CHANGED when only the subzone does; indoor changes aren't modeled.
--   Maps        [D] GetBestMapForUnit and GetPlayerMapPosition only work for the player and party
--               members (MapDocumentation); GetPlayerMapPosition returns a Vector2DMixin (only its
--               GetXY is modeled), and nil
--               inside instances (the API page's 7.1.0 note). [G] The position exists only on the
--               unit's own map (parent maps aren't projected); a party member's comes from its
--               mapID / mapPosition fields. GetBestMapForUnit still answers in an instance
--               (the instance's map, if the test sets one).
--   Map IDs     The harness knows no uiMapIDs of its own: a test adds each map it uses with
--               h:AddMap. Like a unit the test hasn't set, a map it hasn't added doesn't exist: no
--               waypoint can go on it (the client answers the same for an ID that isn't a map).
--   Waypoints   [D] SetUserWaypoint(point) takes a UiMapPoint ({ uiMapID, position = vector2, z },
--               UiMapPoint.lua), returns wasSet and fires USER_WAYPOINT_UPDATED (SynchronousEvent:
--               inside the call). [G] It refuses a map CanSetUserWaypointOnMap denies: true only for
--               a map in h.maps whose canSetWaypoint is true, or, when unset, whose mapType is Zone,
--               Continent or Micro or whose flags include AlwaysAllowUserWaypoints. [G] Super
--               tracking needs a waypoint; SUPER_TRACKING_CHANGED fires when super tracking changes.
--   Honor       [D] CHAT_MSG_COMBAT_HONOR_GAIN carries the documented 18-field chat payload and
--               no secret flags. The text uses COMBATLOG_HONORGAIN (or _NO_RANK) and
--               COMBATLOG_HONORAWARD with the Forever client's enUS GlobalStrings
--               (Ketho/BlizzardInterfaceResources, forever branch, 1.60.1 (70009); the two HONORGAIN
--               strings also printed identically in game). [G] The other fields are as
--               h:FireChat fills them.
--   Quests      [D] QUEST_ITEMS_NEEDED, QUEST_MONSTERS_KILLED and QUEST_OBJECTS_FOUND are the same
--               resources' enUS strings, with positional arguments (name, fulfilled, required);
--               quests.lua writes the log's objective texts with them.
--   Raid notice [D] RaidWarningUtil.AddMessage(text, colorInfo, displayTime) adds the message to
--               RaidWarningFrame: SetText(text) takes a secret (the Text aspect
--               turns secret), SetTextColor(colorInfo.r, .g, .b) takes secrets, and displayTime is
--               compared and computed with (GetHoldTime), so a secret one errors. The frame then
--               adds up its messages' GetNumLines, which is secret once a message's text is
--               (SecretWhenAnchoringSecret; RaidWarning.lua's ResetString comment), so a secret text
--               errors in tainted code. The harness checks those steps and records the message
--               instead of running the fading frame. ChatTypeInfo.RAID_WARNING's color is
--               r = 1, g = 0.282, b = 0 (printed in game); its other fields are
--               ChatTypeInfoConstants.lua's.

-- The Forever client's enUS GlobalStrings for honor and quest objectives (see the header).
Harness.GLOBAL_STRINGS = {
    COMBATLOG_HONORAWARD = "You have been awarded %d Honor.",
    COMBATLOG_HONORGAIN = "%s dies (Honorable Kill: %s). You gain %d Honor.",
    COMBATLOG_HONORGAIN_NO_RANK = "%s dies (Honorable Kill). You gain %d Honor.",
    FACTION_ALLIANCE = "Alliance",
    FACTION_HORDE = "Horde",
    QUEST_ITEMS_NEEDED = "%2$d/%3$d %1$s",
    QUEST_MONSTERS_KILLED = "%2$d/%3$d %1$s slain",
    QUEST_OBJECTS_FOUND = "%2$d/%3$d %1$s",
}

local InstanceTypes = { party = true, raid = true, pvp = true, arena = true, scenario = true }

-- World state, from Harness.New's player spec (see the header).
function Harness:InitWorld(player)
    self:InitUnits(player)
    self.mapID = player.mapID
    self.mapPosition = nil
    self.instance = nil
    self.maps = {}
    self.waypoint = nil
    self.superTracked = false
    self.raidNotices = {}
    self.chatLineID = 0
end

-- Moves the player: spec = { zone, subZone, mapID, x, y, instance } (a missing field keeps its
-- value; subZone = "" leaves subzones; instance = false leaves an instance). Fires
-- ZONE_CHANGED_NEW_AREA when the zone changes, otherwise ZONE_CHANGED when the subzone does.
function Harness:SetLocation(spec)
    local zoneChanged = spec.zone ~= nil and spec.zone ~= self.zone
    local subZoneChanged = spec.subZone ~= nil and spec.subZone ~= self.subZone
    if spec.instance ~= nil then
        assert(spec.instance == false or InstanceTypes[spec.instance], "SetLocation: unknown instance type " .. tostring(spec.instance))
        self.instance = spec.instance or nil
    end
    if spec.mapID ~= nil then
        self.mapID = spec.mapID
    end
    if spec.x ~= nil or spec.y ~= nil then
        assert(spec.x and spec.y, "SetLocation: give both x and y")
        self.mapPosition = { x = spec.x, y = spec.y }
    end
    self.zone = spec.zone or self.zone
    self.subZone = spec.subZone or self.subZone
    if zoneChanged then
        self:Fire("ZONE_CHANGED_NEW_AREA")
    elseif subZoneChanged then
        self:Fire("ZONE_CHANGED")
    end
end

local function GetXY(vector)
    return vector.x, vector.y
end

-- A vector as CreateVector2D (Blizzard_SharedXML/Vector2D.lua) makes it: x, y and Vector2DMixin's
-- methods copied in. Only GetXY is modeled; the rest of the mixin is absent.
function Harness.Vector2D(x, y)
    return { x = x, y = y, GetXY = GetXY }
end

-- UiMapPoint (Blizzard_ObjectAPI/Mainline/UiMapPoint.lua); only CreateFromCoordinates is modeled.
local function UiMapPoint()
    return {
        CreateFromCoordinates = function(mapID, x, y, z)
            return { uiMapID = mapID, position = Harness.Vector2D(x, y), z = z }
        end,
    }
end

local WaypointMapTypes = { Zone = true, Continent = true, Micro = true }

-- Adds a map the C_Map fakes know: spec = { name, mapType (an Enum.UIMapType name, "Zone"),
-- parentMapID, flags (Enum.UIMapFlag bits), canSetWaypoint (overrides the mapType rule) }.
function Harness:AddMap(mapID, spec)
    assert(type(mapID) == "number" and type(spec) == "table" and type(spec.name) == "string", "AddMap(mapID, { name, mapType, ... })")
    local mapType = __snapshot.enums.UIMapType[spec.mapType or "Zone"]
    assert(mapType, "AddMap: unknown mapType " .. tostring(spec.mapType) .. " (an Enum.UIMapType name)")
    self.maps[mapID] = { name = spec.name, mapType = mapType, parentMapID = spec.parentMapID, flags = spec.flags,
        canSetWaypoint = spec.canSetWaypoint }
end

-- Whether the user waypoint may go on mapID (a map the test didn't add doesn't exist).
function Harness:CanSetWaypointOn(mapID)
    local map = self.maps[mapID]
    if not map then
        return false
    end
    if map.canSetWaypoint ~= nil then
        return map.canSetWaypoint == true
    end
    local enums = __snapshot.enums
    for name, value in pairs(enums.UIMapType) do
        if value == map.mapType and WaypointMapTypes[name] then
            return true
        end
    end
    local always = enums.UIMapFlag.AlwaysAllowUserWaypoints
    return math.floor((map.flags or 0) / always) % 2 == 1
end

-- The map and position GetBestMapForUnit / GetPlayerMapPosition see for a unit: the player's,
-- or a party member's mapID / mapPosition; nothing for anyone else.
local function Located(h, token)
    local unit = h:Unit(token)
    if unit == h.player then
        return h.mapID, h.mapPosition
    elseif unit and unit.inGroup then
        return unit.mapID, unit.mapPosition
    end
end

local function SetSuperTracked(h, tracked)
    tracked = tracked and h.waypoint ~= nil
    if h.superTracked ~= tracked then
        h.superTracked = tracked
        h:Fire("SUPER_TRACKING_CHANGED")
    end
end

local function MapFakes(h)
    return {
        GetBestMapForUnit = function(token) return (Located(h, token)) end,
        GetPlayerMapPosition = function(mapID, token)
            local unitMap, position = Located(h, token)
            if h.instance or not position or unitMap ~= mapID then return nil end
            return Harness.Vector2D(position.x, position.y)
        end,
        CanSetUserWaypointOnMap = function(mapID) return h:CanSetWaypointOn(mapID) end,
        SetUserWaypoint = function(point)
            assert(type(point) == "table" and type(point.position) == "table", "C_Map.SetUserWaypoint: point must be a UiMapPoint")
            if not h:CanSetWaypointOn(point.uiMapID) then return false end
            local x, y = point.position.x, point.position.y
            h.waypoint = { uiMapID = point.uiMapID, x = x, y = y, z = point.z }
            h:Fire("USER_WAYPOINT_UPDATED")
            return true
        end,
    }
end

-- A chat event (CHAT_MSG_SAY, CHAT_MSG_CHANNEL, ...) with the documented 18-field payload around
-- text and sender ("First Last", or "" for a system message): the other fields are empty
-- ("" / 0 / false), guid is "" (documented non-nil) and the lineID counts up from 1.
-- [P] discordInfo (names.chatDiscordInfo): for a message that isn't from Discord, a table of empty
-- strings, false flags and two numbers, without lastOnlineGUID; [G] the numbers are 0.
function Harness:FireChat(event, text, sender)
    self.chatLineID = self.chatLineID + 1
    local discordInfo = {
        userID = 0, globalName = "", type = 0, lastOnlineName = "", hasAttachment = false, hasPoll = false,
        hasEmbed = false, hasSticker = false, hasEmoji = false, hasError = false, hasForwardedMessage = false,
        forwardedMessage = "", fromDiscord = false,
    }
    self:Fire(event, text, sender or "", "", "", "", "", 0, 0, "", 0, self.chatLineID, "", 0,
        false, false, false, false, discordInfo)
end

-- CHAT_MSG_COMBAT_HONOR_GAIN around text: a system message, with no sender.
function Harness:FireHonorMessage(text)
    self:FireChat("CHAT_MSG_COMBAT_HONOR_GAIN", text)
end

-- An honorable kill: COMBATLOG_HONORGAIN (victim, rank, honor), or COMBATLOG_HONORGAIN_NO_RANK
-- (victim, honor) when rank is nil. Returns the text.
function Harness:HonorKill(victimName, rank, honor)
    local strings = Harness.GLOBAL_STRINGS
    local text
    if rank == nil then
        text = strings.COMBATLOG_HONORGAIN_NO_RANK:format(victimName, honor)
    else
        text = strings.COMBATLOG_HONORGAIN:format(victimName, rank, honor)
    end
    self:FireHonorMessage(text)
    return text
end

-- Bonus honor: COMBATLOG_HONORAWARD (honor). Returns the text.
function Harness:AwardHonor(honor)
    local text = Harness.GLOBAL_STRINGS.COMBATLOG_HONORAWARD:format(honor)
    self:FireHonorMessage(text)
    return text
end

-- RaidWarningFrameMixin:AddMessage's checks on its arguments (see the header), then the record.
local function AddRaidNotice(h, text, colorInfo, displayTime)
    if type(colorInfo) ~= "table" then
        error("attempt to index local 'colorInfo' (a " .. type(Reveal(colorInfo)) .. " value)", 3)
    end
    if IsSecret(displayTime) then
        error("attempt to compare a secret value (RaidWarningFrame's hold time reads displayTime)", 3)
    end
    if IsSecret(text) then
        error("attempt to compute with a secret value (RaidWarningFrame adds up GetNumLines, secret with secret text)", 3)
    end
    h.raidNotices[#h.raidNotices + 1] = { text = text, color = colorInfo, displayTime = displayTime }
end

-- ChatTypeInfo (Blizzard_ChatFrameBase/Shared/ChatTypeInfoConstants.lua); only RAID_WARNING is
-- modeled, reading any other type is an error.
local function ChatTypeInfo()
    local info = {
        RAID_WARNING = { r = 1, g = 0.282, b = 0, sticky = 0, flashTab = false, flashTabOnGeneral = false, ignoreChatTypeProcessing = false },
    }
    return setmetatable(info, {
        __index = function(_, key) error("ChatTypeInfo." .. tostring(key) .. " isn't modeled by the harness", 2) end,
    })
end

-- The world fakes, merged into the env (env.lua) before it wraps them.
function Harness:WorldFakes()
    local h = self
    local fakes = {
        C_Map = MapFakes(h),
        C_SuperTrack = {
            SetSuperTrackedUserWaypoint = function(tracked) SetSuperTracked(h, tracked) end,
        },
        IsInInstance = function()
            return h.instance ~= nil, h.instance or "none"
        end,
        UiMapPoint = UiMapPoint(),
        ChatTypeInfo = ChatTypeInfo(),
        RaidWarningUtil = {
            AddMessage = function(text, colorInfo, displayTime)
                AddRaidNotice(h, text, colorInfo, displayTime)
            end,
        },
    }
    for name, value in pairs(Harness.GLOBAL_STRINGS) do fakes[name] = value end
    return fakes
end
