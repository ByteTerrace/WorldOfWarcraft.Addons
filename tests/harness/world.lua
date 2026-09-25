-- The world around the player in the fake client: location and maps, the user waypoint, honor,
-- the client icon flash and raid warnings (see wow.lua for the rest).
--
-- State: h.zone, h.subZone (GetZoneText, GetSubZoneText), h.mapID (the uiMapID the player is on),
-- h.mapPosition = { x, y } (normalized to h.mapID), h.instance (nil, or IsInInstance's type:
-- "party", "raid", "pvp", "arena", "scenario"), h.maps = { [uiMapID] = { name, mapType, parentMapID,
-- flags, canSetWaypoint } } (h:AddMap; C_Map.GetMapInfo), h.waypoint
-- ({ uiMapID, x, y, z } or nil), h.superTracked (the user waypoint is super tracked), h.flashes
-- ({ briefly } per FlashClientIcon) and h.raidNotices ({ frame, text, color, displayTime } per
-- raid warning message).
--
-- Modeling decisions ([D] documented, [G] a guess where the docs are silent):
--   Zones       [D] ZONE_CHANGED_NEW_AREA fires on entering a new zone, ZONE_CHANGED on entering
--               an outdoors subzone (warcraft.wiki.gg event pages). [G] h:SetLocation fires only
--               ZONE_CHANGED_NEW_AREA when the zone changes (even if the subzone does too), and
--               ZONE_CHANGED when only the subzone does; indoor changes aren't modeled.
--   Maps        [D] GetBestMapForUnit and GetPlayerMapPosition only work for the player and party
--               members (MapDocumentation); GetPlayerMapPosition returns a Vector2DMixin, and nil
--               inside instances (the API page's 7.1.0 note). [G] The position exists only on the
--               unit's own map (parent maps aren't projected); a party member's comes from its
--               mapID / mapPosition fields. GetBestMapForUnit still answers in an instance
--               (the instance's map, if the test sets one).
--   Map IDs     The harness knows no uiMapIDs of its own: a test adds each map it uses with
--               h:AddMap. Like a unit the test hasn't set, a map it hasn't added doesn't exist:
--               GetMapInfo returns nothing and no waypoint can go on it (the client answers the
--               same for an ID that isn't a map).
--   Waypoints   [D] SetUserWaypoint(point) returns wasSet and fires USER_WAYPOINT_UPDATED
--               (SynchronousEvent: inside the call); GetUserWaypoint returns a UiMapPoint
--               ({ uiMapID, position = vector2, z }, UiMapPoint.lua) or nothing. [G] It refuses a map
--               CanSetUserWaypointOnMap denies: true only for a map in h.maps whose canSetWaypoint
--               is true, or, when unset, whose mapType is Zone, Continent or Micro or whose flags
--               include AlwaysAllowUserWaypoints. [G] ClearUserWaypoint fires USER_WAYPOINT_UPDATED
--               when there was one and ends super tracking it; super tracking needs a waypoint;
--               SUPER_TRACKING_CHANGED fires when super tracking changes.
--   Honor       [D] CHAT_MSG_COMBAT_HONOR_GAIN carries the documented 18-field chat payload and
--               no secret flags. The text uses COMBATLOG_HONORGAIN (or _NO_RANK) and
--               COMBATLOG_HONORAWARD with the Forever client's enUS GlobalStrings
--               (Ketho/BlizzardInterfaceResources, forever branch, 1.60.1 (70009); the two HONORGAIN
--               strings also printed identically in game). [G] The sender
--               fields are empty ("" / 0 / false), guid is "" (documented non-nil), discordInfo nil,
--               and lineID counts up from 1.
--   Raid notice [D] RaidNotice_AddMessage(frame, text, colorInfo, displayTime) is Blizzard's
--               deprecation fallback (Blizzard_DeprecatedRaidWarning, only while the
--               loadDeprecationFallbacks CVar is on; Harness.new{ loadDeprecationFallbacks = false }
--               leaves it undefined). It ignores the frame and calls RaidWarningUtil.AddMessage, which
--               adds the message to RaidWarningFrame: SetText(text) takes a secret (the Text aspect
--               turns secret), SetTextColor(colorInfo.r, .g, .b) takes secrets, and displayTime is
--               compared and computed with (GetHoldTime), so a secret one errors. The frame then
--               adds up its messages' GetNumLines, which is secret once a message's text is
--               (SecretWhenAnchoringSecret; RaidWarning.lua's ResetString comment), so a secret text
--               errors in tainted code. The harness checks those steps and records the message
--               instead of running the fading frame. ChatTypeInfo.RAID_WARNING's color is
--               r = 1, g = 0.282, b = 0 (printed in game); its other fields are
--               ChatTypeInfoConstants.lua's.

-- The Forever client's enUS GlobalStrings for honor (see the header).
Harness.GLOBAL_STRINGS = {
    COMBATLOG_HONORAWARD = "You have been awarded %d Honor.",
    COMBATLOG_HONORGAIN = "%s dies (Honorable Kill: %s). You gain %d Honor.",
    COMBATLOG_HONORGAIN_NO_RANK = "%s dies (Honorable Kill). You gain %d Honor.",
    FACTION_ALLIANCE = "Alliance",
    FACTION_HORDE = "Horde",
}

local INSTANCE_TYPES = { party = true, raid = true, pvp = true, arena = true, scenario = true }

-- World state, from Harness.new's player spec (see the header).
function Harness:InitWorld(player)
    self:InitUnits(player)
    self.mapID = player.mapID
    self.mapPosition = nil
    self.instance = nil
    self.maps = {}
    self.waypoint = nil
    self.superTracked = false
    self.flashes = {}
    self.raidNotices = {}
    self.chatLineID = 0
    self.deprecationFallbacks = player.loadDeprecationFallbacks ~= false
end

-- Location ------------------------------------------------------------------

-- Moves the player: spec = { zone, subZone, mapID, x, y, instance } (a missing field keeps its
-- value; subZone = "" leaves subzones; instance = false leaves an instance). Fires
-- ZONE_CHANGED_NEW_AREA when the zone changes, otherwise ZONE_CHANGED when the subzone does.
function Harness:SetLocation(spec)
    local zoneChanged = spec.zone ~= nil and spec.zone ~= self.zone
    local subZoneChanged = spec.subZone ~= nil and spec.subZone ~= self.subZone
    if spec.instance ~= nil then
        assert(spec.instance == false or INSTANCE_TYPES[spec.instance], "SetLocation: unknown instance type " .. tostring(spec.instance))
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

-- Maps and waypoints -------------------------------------------------------

local VECTOR_METHODS = {}
function VECTOR_METHODS:OnLoad(x, y) self:SetXY(x, y) end
function VECTOR_METHODS:GetXY() return self.x, self.y end
function VECTOR_METHODS:SetXY(x, y) self.x, self.y = x, y end
function VECTOR_METHODS:IsEqualTo(other) return self.x == other.x and self.y == other.y end
function VECTOR_METHODS:Clone() return Harness.Vector2D(self.x, self.y) end
Harness.VECTOR_METHODS = VECTOR_METHODS

-- CreateVector2D (Blizzard_SharedXML/Vector2D.lua): a table with Vector2DMixin's methods copied in.
-- Only the methods above are modeled; the rest of the mixin is absent.
function Harness.Vector2D(x, y)
    local vector = {}
    for name, fn in pairs(VECTOR_METHODS) do
        vector[name] = fn
    end
    vector:OnLoad(x, y)
    return vector
end

-- UiMapPoint (Blizzard_ObjectAPI/Mainline/UiMapPoint.lua).
local UI_MAP_POINT = {
    CreateFromCoordinates = function(mapID, x, y, z)
        return { uiMapID = mapID, position = Harness.Vector2D(x, y), z = z }
    end,
    CreateFromVector2D = function(mapID, position, z)
        return { uiMapID = mapID, position = position, z = z }
    end,
    CreateFromVector3D = function(mapID, position)
        return { uiMapID = mapID, position = Harness.Vector2D(position.x, position.y), z = position.z }
    end,
}

local WAYPOINT_MAP_TYPES = { Zone = true, Continent = true, Micro = true }

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
        if value == map.mapType and WAYPOINT_MAP_TYPES[name] then
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
        GetMapInfo = function(mapID)
            local map = h.maps[mapID]
            if not map then return end
            return { mapID = mapID, name = map.name, mapType = map.mapType, parentMapID = map.parentMapID or 0, flags = map.flags or 0 }
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
        ClearUserWaypoint = function()
            if not h.waypoint then return end
            h.waypoint = nil
            SetSuperTracked(h, false)
            h:Fire("USER_WAYPOINT_UPDATED")
        end,
        HasUserWaypoint = function() return h.waypoint ~= nil end,
        GetUserWaypoint = function()
            local w = h.waypoint
            if w then return UI_MAP_POINT.CreateFromCoordinates(w.uiMapID, w.x, w.y, w.z) end
        end,
    }
end

-- Honor ---------------------------------------------------------------------

-- CHAT_MSG_COMBAT_HONOR_GAIN with the documented 18-field payload around text.
function Harness:FireHonorMessage(text)
    self.chatLineID = self.chatLineID + 1
    self:Fire("CHAT_MSG_COMBAT_HONOR_GAIN", text, "", "", "", "", "", 0, 0, "", 0, self.chatLineID, "", 0,
        false, false, false, false, nil)
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

-- Raid warnings -------------------------------------------------------------

-- RaidWarningFrameMixin:AddMessage's checks on its arguments (see the header), then the record.
local function AddRaidNotice(h, frame, text, colorInfo, displayTime)
    if type(colorInfo) ~= "table" then
        error("attempt to index local 'colorInfo' (a " .. type(Reveal(colorInfo)) .. " value)", 3)
    end
    if IsSecret(displayTime) then
        error("attempt to compare a secret value (RaidWarningFrame's hold time reads displayTime)", 3)
    end
    if IsSecret(text) then
        error("attempt to compute with a secret value (RaidWarningFrame adds up GetNumLines, secret with secret text)", 3)
    end
    h.raidNotices[#h.raidNotices + 1] = { frame = frame, text = text, color = colorInfo, displayTime = displayTime }
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

-- Fakes ---------------------------------------------------------------------

-- The world fakes, merged into the env (env.lua) before it wraps them. uiParent parents
-- RaidWarningFrame.
function Harness:WorldFakes(uiParent)
    local h = self
    local fakes = {
        C_Map = MapFakes(h),
        C_SuperTrack = {
            SetSuperTrackedUserWaypoint = function(tracked) SetSuperTracked(h, tracked) end,
            IsSuperTrackingUserWaypoint = function() return h.superTracked end,
        },
        IsInInstance = function()
            return h.instance ~= nil, h.instance or "none"
        end,
        FlashClientIcon = function(briefly)
            h.flashes[#h.flashes + 1] = { briefly = briefly == true }
        end,
        CreateVector2D = Harness.Vector2D,
        Vector2DMixin = {},
        UiMapPoint = {},
        ChatTypeInfo = ChatTypeInfo(),
        RaidWarningUtil = {
            MessageType = { RaidWarning = 1, BossEmote = 2, BGSystem = 3 },
            AddMessage = function(text, colorInfo, displayTime)
                AddRaidNotice(h, rawget(h.env, "RaidWarningFrame"), text, colorInfo, displayTime)
            end,
        },
    }
    for name, fn in pairs(VECTOR_METHODS) do fakes.Vector2DMixin[name] = fn end
    for name, fn in pairs(UI_MAP_POINT) do fakes.UiMapPoint[name] = fn end
    for name, value in pairs(Harness.GLOBAL_STRINGS) do fakes[name] = value end
    local raidWarningFrame = h:CreateWidget("Frame", "RaidWarningFrame", uiParent)
    Harness.State(raidWarningFrame).shown = false
    fakes.RaidWarningFrame = raidWarningFrame
    if h.deprecationFallbacks then
        fakes.RaidNotice_AddMessage = function(frame, text, colorInfo, displayTime)
            AddRaidNotice(h, frame, text, colorInfo, displayTime)
        end
    end
    return fakes
end
