-- The death fact (Facts.lua): your deaths and who dealt them, for features that react to them. A demand fact: it runs
-- only while a module that uses it runs (uses = { "death" }). React with module:OnIncrease on death.count (you died) or
-- death.attributed (the killer rows are set).
--
--   death.count          your deaths this session.
--   death.attributed     the death.count the killer rows describe. It rises once per death, after
--                        they're set, even when the killer stays unknown.
--   death.killer         the killer's name as the recap printed it (a player's "First Last"),
--                        or "" when unknown.
--   death.killerKind     "player", "self" (your own blow, such as a sapper charge), "pet"
--                        (anything else a player controls, such as a pet or a totem), "npc", or "" when unknown.
--   death.killerClass    a player killer's class file ("ROGUE"), else "".
--   death.killerFaction  a player killer's faction ("Alliance" or "Horde"), else "".
--   death.killerSpell    the killing blow's spell name, or "" for a melee swing or unknown.
--   death.killerDamage   the killing blow's damage, or 0 when unknown.
--
-- Who killed you comes from Blizzard's death recap: the damage meter's Deaths lists (the current session, else the
-- overall one) hold your death with its recap ID (readable even in combat). This adapter uses events[1] as the killing
-- blow, following Gethe/wow-ui-source's forever branch:
-- Interface/AddOns/Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua, DeathRecapMixin:BuildDataProvider iterates
-- C_DeathRecap.GetRecapEvents with ipairs and sets elementData.causedDeath = i == 1. Its TOC gates it with
-- [AllowLoadGameType mainline], which covers camelot: Forever's TOCs add [ExcludeLoadGameType camelot] wherever Forever
-- leaves out a mainline addon. An attacker the recap hides (hideCaster, which Blizzard's recap window honors) is
-- unknown. The recap may land a moment after PLAYER_DEAD, so the fact looks again on the meter's updates and at
-- RecapRetries, at most RecapWait seconds, then publishes the death as unknown. Recap IDs rise with each death, so
-- deaths take the new recaps in order: each new ID, oldest first, belongs to the oldest death still owed one. A death
-- that gave up still takes its recap if it comes within LateWait, and sets it aside, so a later death never takes
-- another death's recap.

-- Seconds after RecapWait in which a late recap is still your last death's.
local LateWait = 30
-- The COMBATLOG_OBJECT_CONTROL_PLAYER bit in a combat log event's flags.
local PlayerControlled = 0x100

-- UnitRace's raceFile for each race a Forever character can be, by faction.
local RaceFactions = {
    Dwarf = "Alliance", Gnome = "Alliance", Human = "Alliance", NightElf = "Alliance", Orc = "Horde", Scourge = "Horde",
    Tauren = "Horde", Troll = "Horde",
}

-- Seconds after the death to look again, whatever the meter says.
local RecapRetries = { 0.3, 1 }
-- Seconds to wait for the damage meter to record your death.
local RecapWait = 3

local ByteTerrace = ByteTerrace
local C_DamageMeter = C_DamageMeter
local C_DeathRecap = C_DeathRecap
local Enum = Enum
local floor = math.floor
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local ipairs = ipairs
local issecretvalue = issecretvalue
local max = math.max
local remove = table.remove
local sort = table.sort
local type = type
local UnitGUID = UnitGUID

local function Plain(value, kind)
    if issecretvalue(value) or (type(value) ~= kind) then
        return nil
    end

    return value
end

-- Adds the recap IDs of your deaths above after in one meter session type to found ([id] = true).
local function DeathsIn(sessionType, after, found)
    local session = C_DamageMeter.GetCombatSessionFromType(sessionType, Enum.DamageMeterType.Deaths)

    if issecretvalue(session) or (type(session) ~= "table") then
        return
    end

    for _, source in ipairs(Plain(session.combatSources, "table") or {}) do
        local id = Plain(source.deathRecapID, "number")

        if Plain(source.isLocalPlayer, "boolean") and id and (id > after) then
            found[id] = true
        end
    end
end

-- Returns the recap IDs of your deaths in the damage meter above after, oldest first.
local function DeathsAfter(after)
    local found = {}
    local list = {}

    if C_DamageMeter.IsDamageMeterAvailable() then
        local types = Enum.DamageMeterSessionType

        DeathsIn(types.Current, after, found)
        DeathsIn(types.Overall, after, found)
    end

    for id in pairs(found) do
        list[#list + 1] = id
    end

    sort(list)

    return list
end

-- Returns what the killing blow of a recap says about your killer: { name, kind, class, faction, spell, damage }, or
-- nil for a recap without events.
local function Killer(recapID)
    local events = Plain(C_DeathRecap.GetRecapEvents(recapID), "table")
    local blow = (events and Plain(events[1], "table"))

    if not blow then
        return nil
    end

    local guid = Plain(blow.sourceGUID, "string")
    local flags = Plain(blow.sourceFlags, "number")

    local killer = { class = "", damage = (Plain(blow.amount, "number") or 0), faction = "", kind = "",
        name = (Plain(blow.sourceName, "string") or ""), spell = (Plain(blow.spellName, "string") or "") }

    local me = UnitGUID("player")

    if guid and not issecretvalue(me) and (guid == me) then
        killer.kind = "self"
    elseif guid and guid:find("^Player%-") then
        killer.kind = "player"
        local _, classFile, _, raceFile = GetPlayerInfoByGUID(guid)

        killer.class = (Plain(classFile, "string") or "")
        killer.faction = (RaceFactions[Plain(raceFile, "string") or ""] or "")
    elseif flags and ((floor(flags / PlayerControlled) % 2) == 1) then
        killer.kind = "pet"
    elseif guid then
        killer.kind = "npc"
    end

    if (killer.name == "") or Plain(blow.hideCaster, "boolean") then
        killer.name, killer.kind, killer.class, killer.faction = "", "", "", ""
    end

    return killer
end

-- Returns the recap ID of your newest death in the damage meter, or 0.
local function NewestDeath()
    local list = DeathsAfter(0)

    return (list[#list] or 0)
end

ByteTerrace.Facts.death = {
    demand = true,
    OnEnable = function(module)
        local state = module.Addon.State
        local count = module:Id("count")
        -- The highest recap ID a death took, or the one there at start.
        local handled = NewestDeath()
        -- The deaths still owed a recap, oldest first. Each is { number, gaveUp, settled, timers }.
        local owed = {}
        -- The meter-update handler, held while any death is owed a recap.
        local waitHandle

        -- Publishes the killer of death number (nil: unknown).
        local function Attribute(number, killer)
            killer = (killer or {})
            module:Set("killer", killer.name or "")
            module:Set("killerKind", killer.kind or "")
            module:Set("killerClass", killer.class or "")
            module:Set("killerFaction", killer.faction or "")
            module:Set("killerSpell", killer.spell or "")
            module:Set("killerDamage", killer.damage or 0)
            module:Set("attributed", number)
        end

        -- A death stops being owed a recap: its timers go, and the meter handler with the last one.
        local function Settle(death)
            death.settled = true

            for i = #owed, 1, -1 do
                if owed[i] == death then
                    remove(owed, i)
                end
            end

            for _, timer in ipairs(death.timers) do
                module:Cancel(timer)
            end

            if (#owed == 0) and waitHandle then
                module:Off(waitHandle)
                waitHandle = nil
            end
        end

        -- Gives each new recap, oldest first, to the oldest death owed one. A death that gave up takes it without a
        -- word. A recap no death is owed (none waiting) only moves handled.
        local function TryRecap()
            for _, id in ipairs(DeathsAfter(handled)) do
                handled = id
                local death = owed[1]

                if death then
                    Settle(death)

                    if not death.gaveUp then
                        Attribute(death.number, Killer(id))
                    end
                end
            end
        end

        -- A meter update: only the Deaths meter's can carry a new recap, so the others cost nothing.
        local function OnMeterUpdate(meterType)
            if issecretvalue(meterType) or (meterType ~= Enum.DamageMeterType.Deaths) then
                return
            end

            TryRecap()
        end

        module:On("PLAYER_DEAD", function()
            local number = (state.Values[count] + 1)

            state:Set(count, number)
            local death = { gaveUp = false, number = number, timers = {} }

            owed[#owed + 1] = death
            TryRecap()

            if death.settled then
                -- Its recap was already there.
                return
            end

            waitHandle = (waitHandle or module:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", OnMeterUpdate))

            for i, delay in ipairs(RecapRetries) do
                death.timers[i] = module:After(delay, TryRecap)
            end

            death.timers[#death.timers + 1] = module:After(RecapWait, function()
                death.gaveUp = true
                Attribute(number, nil)
                -- Still owed: a recap landing late is this death's, set aside, not the next one's.
                death.timers[#death.timers + 1] = module:After(LateWait, function() Settle(death) end)
            end)
        end)

        -- After a /reload, deaths already in the session aren't new.
        module:On("PLAYER_ENTERING_WORLD", function()
            if #owed == 0 then
                handled = max(handled, NewestDeath())
            end
        end)
    end,
    state = {
        { default = 0, kind = "number", name = "count", persist = false },
        { default = 0, kind = "number", name = "attributed", persist = false },
        { default = "", kind = "string", name = "killer", persist = false },
        { default = "", kind = "string", name = "killerKind", persist = false },
        { default = "", kind = "string", name = "killerClass", persist = false },
        { default = "", kind = "string", name = "killerFaction", persist = false },
        { default = "", kind = "string", name = "killerSpell", persist = false },
        { default = 0, kind = "number", name = "killerDamage", persist = false },
    },
    toggle = false,
}
