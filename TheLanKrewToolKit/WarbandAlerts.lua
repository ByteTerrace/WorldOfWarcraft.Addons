local addonName, ns = ...

-- WarbandAlerts: the sighting alerts' budget. When a ledger player or a member of a guild at war shows up
-- (Warband.lua's Seen: a nameplate, your target, or mouseover), a raid warning says so. For a mark or grudge, the Krew
-- hears where, and a champion in a fight asks the Krew for aid. Each person alerts once per AlertCooldown, and a guild
-- at war once per GuildAlertCooldown. A brawl doesn't stack warnings: the alerts that follow one within AlertWindow
-- merge into one summary with one sound when it ends ("3 more grudges nearby: ..."), ordered mark, grudge, war, then
-- champion. The Krew still hears of each sighting, once per SightCooldown.
--
-- What it adds to ns.Warband:
--   AlertFor(key, status, info, unit)  raises the alert for a sighting, within the budget, and tells the Krew
--   HeardSighting(key)                 the Krew was just told about key (WarbandMessages.lua)
--   DisableAlerts()                    forgets the window as Warband stops (its timer stops with the module)

-- How long, in seconds, before the same person alerts again.
local AlertCooldown = 90
-- How long, in seconds, after an alert further alerts merge into one summary.
local AlertWindow = 3
-- Each standing's color code in alert text.
local Colors = { glory = "|cff40c0ff", grudge = "|cffff8000", mark = "|cffff2020", war = "|cffff8000" }

-- How an alert summary counts each standing: { one, more than one }.
local Counted = {
    glory = { "champion", "champions" },
    grudge = { "grudge", "grudges" },
    mark = { "marked for death", "marked for death" },
    war = { "enemy at war", "enemies at war" },
}

-- How long, in seconds, before the same guild at war alerts again.
local GuildAlertCooldown = 60
-- How long, in seconds, before the Krew hears about the same person again.
local SightCooldown = 120

local concat = table.concat
local GetTime = GetTime
local ipairs = ipairs
local next = next
local pairs = pairs
local sort = table.sort
local SOUNDKIT = SOUNDKIT
local UnitAffectingCombat = UnitAffectingCombat
local wipe = wipe

local Alert = ns.Cards.Alert
local Krew = ns.Krew
local Warband = ns.Warband
local Describe = Warband.Describe
local GuildName = Warband.GuildName
local Labels = Warband.Labels
local Order = Warband.Order
local Place = Warband.Place
local Score = Warband.Score
local WarbandModule = Warband.Module

-- The pending end of the alert window: while it's set, alerts are held for a summary.
local AlertTimer
-- Maps each key to the standing of its alert held in this window.
local Held = {}
-- Maps each held champion in a fight to true.
local HeldFighting = {}
-- Maps each key to the GetTime() of its last alert.
local LastAlert = {}
-- Maps each guild key to the GetTime() of its last alert.
local LastGuildAlert = {}
-- Maps each key to the GetTime() of its last Krew report (SIGHT).
local LastShared = {}

-- Sorts held keys by standing (Order), then by name.
local function ByStanding(a, b)
    local first = Order[Held[a]]
    local second = Order[Held[b]]

    if first ~= second then
        return (first < second)
    end

    return (a < b)
end

--- Forgets the alert window as Warband stops. The module's timers stop with it, so only the handle is forgotten.
local function DisableAlerts()
    AlertTimer = nil
    wipe(Held)
    wipe(HeldFighting)
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

    if WarbandModule:Get("sightingAlerts") then
        AlertTimer = WarbandModule:After(AlertWindow, EndWindow)
        Alert(HeldSummary())
    end

    wipe(Held)
    wipe(HeldFighting)
end

-- Raises a sighting alert, within the budget: the first opens an AlertWindow, and the ones that follow in it are held
-- for one summary when it ends.
local function Raise(key, status, guild, fighting)
    if not WarbandModule:Get("sightingAlerts") then
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

--- Raises the alert for a sighting of key, whose standing is status, within the budget (see the header), and tells the
--- Krew of a mark, a grudge, or a champion in a fight.
---@param key string
---@param status string Warband.Status's
---@param info table Warband.Identify's
---@param unit string the unit they were seen as
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

    -- With nobody to tell, the share's cooldown doesn't start: the next sighting in a group goes out.
    if WarbandModule:Get("shareSightings") and ((status ~= "glory") or fighting) and Krew:Ready()
        and not (LastShared[key] and ((now - LastShared[key]) < SightCooldown)) then
        LastShared[key] = now
        local zone, subZone = Place()

        Krew:Send("SIGHT", { key, zone, subZone, ((fighting and "1") or "0") })
    end
end

Warband.AlertFor, Warband.DisableAlerts, Warband.HeardSighting = AlertFor, DisableAlerts, HeardSighting
