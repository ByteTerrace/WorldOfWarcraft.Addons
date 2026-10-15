local addonName, ns = ...

-- Calibration probes about player names. Forever's characters carry a surname: Blizzard's Forever
-- code reads UnitName as (name, surname) where retail reads (name, realm), and shows "First Last"
-- with Constants.CharacterNameSeparatorConsts' separator (Blizzard_FrameXMLUtil/Camelot/
-- NameUtil.lua). These probes record which shape each source of names has: the unit APIs, the
-- GUID lookup, and the senders of chat events (DevTools.lua passes those to Probes.NoteSender
-- from load).
--
-- Names are recorded as shapes, never as names (Probes.NameShape): each run of letters becomes
-- "Aa", so "Dh Taketwo-Realm" records as "Aa Aa-Aa" and no character's name reaches the file.

local Probes = ns.Probes
local Value, NameShape, Senders, JoinSets = Probes.Value, Probes.NameShape, Probes.Senders, Probes.JoinSets

-- Every return of a name API, as name shapes: { "Aa", "Aa" } for (name, surname).
local function Returns(...)
    local shapes = {}
    for i = 1, select("#", ...) do
        shapes["r" .. i] = NameShape((select(i, ...)))
    end
    shapes.count = select("#", ...)
    return shapes
end

-- A unit's names from every API that gives one.
local function Names(unit)
    local guid = UnitGUID(unit) -- secret: only passed on to GetPlayerInfoByGUID when plain
    local byGUID
    if not issecretvalue(guid) and type(guid) == "string" then
        local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid) -- secret: recorded as shapes
        byGUID = { name = NameShape(name), realm = NameShape(realm) }
    end
    return {
        unitName = Returns(UnitName(unit)), -- secret: recorded as shapes
        unitNameUnmodified = Returns(UnitNameUnmodified(unit)), -- secret: recorded as shapes
        unitFullName = Returns(UnitFullName(unit)), -- secret: recorded as shapes
        byGUID = byGUID,
    }
end

Probes.Define({
    {
        name = "names.player",
        needs = {},
        run = function()
            local separators = Constants.CharacterNameSeparatorConsts
            local names = Names("player")
            local separator = separators and separators.CHARACTERNAME_SURNAME_SEPARATOR
            names.separator = type(separator) == "string" and ("[" .. separator .. "]") or Probes.Shape(separator)
            names.regionalUnique = Value(RegionalUniqueNamesEnabled())
            names.realm = NameShape(GetNormalizedRealmName())
            return names
        end,
    },
    {
        -- Shapes can't tell a surname from a realm: this compares the second parts with your realm
        -- without recording either.
        name = "names.secondPart",
        needs = {},
        run = function()
            local _, second = UnitName("player") -- secret: only compared when plain
            local _, fullSecond = UnitFullName("player") -- secret: only compared when plain
            if issecretvalue(second) or issecretvalue(fullSecond) then
                return { secret = true }
            end
            local realm, normalized = GetRealmName(), GetNormalizedRealmName()
            return {
                unitNameIsRealm = second ~= nil and (second == realm or second == normalized),
                unitFullNameIsRealm = fullSecond ~= nil and (fullSecond == realm or fullSecond == normalized),
            }
        end,
    },
    {
        name = "names.otherPlayer",
        needs = { "playerTarget" },
        run = function() return Names("target") end,
    },
    {
        -- The sender argument of each chat event heard since load: what CHAT_MSG_ADDON (the
        -- Krew's messages) and the chat channels say a player's name is.
        name = "names.chatSenders",
        needs = { "heardChat" },
        accumulates = true,
        run = function() return JoinSets(Senders) end,
    },
})
