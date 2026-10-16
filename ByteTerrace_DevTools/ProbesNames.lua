local addonName, ns = ...

-- Calibration probes about player names. Forever's characters carry a surname: Blizzard's Forever code reads UnitName
-- as (name, surname) where retail reads (name, realm), and shows "First Last" with
-- Constants.CharacterNameSeparatorConsts' separator (Blizzard_FrameXMLUtil/Camelot/ NameUtil.lua). These probes record
-- which shape each source of names has: the unit APIs, the GUID lookup, and the senders of chat events (DevTools.lua
-- passes those to Probes.NoteSender from load), with the shape of their discordInfo (Probes.NoteDiscordInfo).
--
-- Names are recorded as shapes, never as names (Probes.NameShape): each run of letters becomes "Aa", so "Dh
-- Taketwo-Realm" records as "Aa Aa-Aa" and no character's name reaches the file.

local Probes = ns.Probes
local JoinSets = Probes.JoinSets
local NameShape = Probes.NameShape
local Senders = Probes.Senders
local Value = Probes.Value

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
    -- secret: only passed on to GetPlayerInfoByGUID when plain
    local guid = UnitGUID(unit)
    local byGUID

    if not issecretvalue(guid) and (type(guid) == "string") then
        -- secret: recorded as shapes
        local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)

        byGUID = { name = NameShape(name), realm = NameShape(realm) }
    end

    return {
        byGUID = byGUID,
        -- secret: recorded as shapes
        unitFullName = Returns(UnitFullName(unit)),
        -- secret: recorded as shapes
        unitName = Returns(UnitName(unit)),
        -- secret: recorded as shapes
        unitNameUnmodified = Returns(UnitNameUnmodified(unit)),
    }
end

Probes.Define({
    {
        name = "names.player",
        needs = {},
        run = function()
            local separators = Constants.CharacterNameSeparatorConsts
            local names = Names("player")
            local separator = (separators and separators.CHARACTERNAME_SURNAME_SEPARATOR)

            names.separator = (((type(separator) == "string") and ("[" .. separator .. "]")) or Probes.Shape(separator))
            names.regionalUnique = Value(RegionalUniqueNamesEnabled())
            names.realm = NameShape(GetNormalizedRealmName())

            return names
        end,
    },
    {
        -- Shapes can't tell a surname from a realm: this compares the second parts with your realm without recording
        -- either.
        name = "names.secondPart",
        needs = {},
        run = function()
            -- secret: only compared when plain
            local _, second = UnitName("player")
            -- secret: only compared when plain
            local _, fullSecond = UnitFullName("player")

            if issecretvalue(second) or issecretvalue(fullSecond) then
                return { secret = true }
            end

            local realm = GetRealmName()
            local normalized = GetNormalizedRealmName()

            return {
                unitFullNameIsRealm = ((fullSecond ~= nil) and ((fullSecond == realm) or (fullSecond == normalized))),
                unitNameIsRealm = ((second ~= nil) and ((second == realm) or (second == normalized))),
            }
        end,
    },
    {
        name = "names.otherPlayer",
        needs = { "playerTarget" },
        run = function() return Names("target") end,
    },
    {
        accumulates = true,
        -- The sender argument of each chat event heard since load: what CHAT_MSG_ADDON (the Krew's messages) and the
        -- chat channels say a player's name is.
        name = "names.chatSenders",
        needs = { "heardChat" },
        run = function() return JoinSets(Senders) end,
    },
    {
        accumulates = true,
        -- The shape of each chat event's 18th payload value, discordInfo, heard since load (the docs say it's never
        -- nil; h:FireChat sends what the client did). fields holds each field's shapes when it's a table. A message
        -- bridged from Discord would add its own shapes.
        name = "names.chatDiscordInfo",
        needs = { "heardChat" },
        run = function()
            local info = Probes.DiscordInfo

            return { fields = JoinSets(info.fields), shapes = JoinSets(info.shapes) }
        end,
    },
})
