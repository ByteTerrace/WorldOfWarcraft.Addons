-- Names: players' names as Forever gives them, the one way every ByteTerrace addon reads them.
--
-- Forever's character names are unique in the region and carry a surname (RegionalUniqueNames-
-- Enabled() is true). UnitName, UnitNameUnmodified and UnitFullName return (first, surname) where
-- retail returns (name, realm); GetPlayerInfoByGUID's name and chat's sender are "First Last" with
-- no realm (all probed in game). Blizzard's frames show "First Last" joined with
-- Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR (a space), and read a
-- name up to its first "-" (Camelot NameUtil.lua), so a "-Realm" suffix never tells two players
-- apart. A player's identity is the full name without it: that's what these functions return.
--
--   ByteTerrace.Names.Full(first, surname)  "First Last", or first alone without a surname.
--   ByteTerrace.Names.OfUnit(unit)          the unit's full name, or nil (no unit, or secret).
--   ByteTerrace.Names.Mine()                your full name, or nil while it's secret.
--   ByteTerrace.Names.Plain(text)           a name from text (a chat sender, a recap, a message)
--                                           without any "-Realm" suffix.

local ByteTerrace = ByteTerrace
local Constants, issecretvalue, UnitName = Constants, issecretvalue, UnitName
local type = type

local Separators = Constants.CharacterNameSeparatorConsts
local Separator = Separators and Separators.CHARACTERNAME_SURNAME_SEPARATOR or " "

--- "First Last", or first alone when there's no surname (an NPC).
---@param first string
---@param surname string?
---@return string
local function Full(first, surname)
    if type(surname) == "string" and surname ~= "" then
        return first .. Separator .. surname
    end
    return first
end

--- The unit's full name, or nil when there's no unit or its name is secret.
---@param unit string
---@return string?
local function OfUnit(unit)
    local first, surname = UnitName(unit)
    if issecretvalue(first) or issecretvalue(surname) or type(first) ~= "string" or first == "" then
        return nil
    end
    return Full(first, surname)
end

--- Your full name, or nil while it's secret.
---@return string?
local function Mine()
    return OfUnit("player")
end

--- A name from text without its "-Realm" suffix, if any.
---@param text string
---@return string
local function Plain(text)
    return text:match("^[^%-]+") or text
end

ByteTerrace.Names = { Full = Full, OfUnit = OfUnit, Mine = Mine, Plain = Plain }
