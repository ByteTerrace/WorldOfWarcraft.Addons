-- The death fact (Facts.lua): your deaths and who dealt them, for features that react to them. A
-- demand fact: it runs only while a module that uses it runs (uses = { "death" }). React with
-- module:OnIncrease on death.count (you died) or death.attributed (the killer rows are set).
--
--   death.count          your deaths this session.
--   death.attributed     the death.count the killer rows describe; it rises once per death, after
--                        they're set, even when the killer stays unknown.
--   death.killer         the killer's name as the recap printed it (a player's "First Last"); ""
--                        when unknown.
--   death.killerKind     "player", "self" (your own blow: a sapper charge, say), "pet" (anything
--                        else a player controls: a pet, a totem), "npc", or "" when unknown.
--   death.killerClass    a player killer's class file ("ROGUE"), else "".
--   death.killerFaction  a player killer's faction ("Alliance" or "Horde"), else "".
--   death.killerSpell    the killing blow's spell name; "" for a melee swing or unknown.
--   death.killerDamage   the killing blow's damage; 0 when unknown.
--
-- Who killed you comes from Blizzard's death recap: the damage meter's Deaths lists (the current
-- session, else the overall one) hold your death with its recap ID (readable even in combat).
-- This adapter uses events[1] as the killing blow, following Gethe/wow-ui-source's forever branch:
-- Interface/AddOns/Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua,
-- DeathRecapMixin:BuildDataProvider iterates C_DeathRecap.GetRecapEvents with ipairs and sets
-- elementData.causedDeath = i == 1. Its TOC gates it with [AllowLoadGameType mainline], which
-- covers camelot: Forever's TOCs add [ExcludeLoadGameType camelot] wherever mainline shouldn't.
-- An attacker the recap hides (hideCaster, which Blizzard's recap window honors) is unknown. The
-- recap may land a moment after PLAYER_DEAD, so the fact looks again on the meter's updates and at
-- RecapRetries, at most RecapWait seconds; a recap that comes later (within LateWait) is set aside,
-- so the next death doesn't take it for its own.

local RecapWait = 3 -- seconds to wait for the damage meter to record your death
local LateWait = 30 -- seconds after that in which a late recap is still your last death's
local RecapRetries = { 0.3, 1 } -- seconds after the death to look again, whatever the meter says
local PlayerControlled = 0x100 -- COMBATLOG_OBJECT_CONTROL_PLAYER in a combat log event's flags
-- UnitRace's raceFile for each race a Forever character can be, by faction.
local RaceFactions = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde",
}

local ByteTerrace = ByteTerrace
local C_DamageMeter, C_DeathRecap, Enum = C_DamageMeter, C_DeathRecap, Enum
local GetPlayerInfoByGUID, issecretvalue, UnitGUID = GetPlayerInfoByGUID, issecretvalue, UnitGUID
local floor, ipairs, max, type = math.floor, ipairs, math.max, type

local function Plain(value, kind)
    if issecretvalue(value) or type(value) ~= kind then
        return nil
    end
    return value
end

-- The recap ID of your newest death in one meter session type, or 0.
local function NewestDeathIn(sessionType)
    local session = C_DamageMeter.GetCombatSessionFromType(sessionType, Enum.DamageMeterType.Deaths)
    if issecretvalue(session) or type(session) ~= "table" then
        return 0
    end
    local sources = Plain(session.combatSources, "table")
    local newest = 0
    for _, source in ipairs(sources or {}) do
        local id = Plain(source.deathRecapID, "number")
        if Plain(source.isLocalPlayer, "boolean") and id and id > newest then
            newest = id
        end
    end
    return newest
end

-- The recap ID of your newest death in the damage meter, or 0.
local function NewestDeath()
    if not C_DamageMeter.IsDamageMeterAvailable() then
        return 0
    end
    local types = Enum.DamageMeterSessionType
    return max(NewestDeathIn(types.Current), NewestDeathIn(types.Overall))
end

-- What the killing blow of a recap says about your killer: { name, kind, class, faction, spell,
-- damage }, or nil for a recap without events.
local function Killer(recapID)
    local events = Plain(C_DeathRecap.GetRecapEvents(recapID), "table")
    local blow = events and Plain(events[1], "table")
    if not blow then
        return nil
    end
    local guid, flags = Plain(blow.sourceGUID, "string"), Plain(blow.sourceFlags, "number")
    local killer = { name = Plain(blow.sourceName, "string") or "", kind = "", class = "", faction = "",
        spell = Plain(blow.spellName, "string") or "", damage = Plain(blow.amount, "number") or 0 }
    local me = UnitGUID("player")
    if guid and not issecretvalue(me) and guid == me then
        killer.kind = "self"
    elseif guid and guid:find("^Player%-") then
        killer.kind = "player"
        local _, classFile, _, raceFile = GetPlayerInfoByGUID(guid)
        killer.class = Plain(classFile, "string") or ""
        killer.faction = RaceFactions[Plain(raceFile, "string") or ""] or ""
    elseif flags and floor(flags / PlayerControlled) % 2 == 1 then
        killer.kind = "pet"
    elseif guid then
        killer.kind = "npc"
    end
    if killer.name == "" or Plain(blow.hideCaster, "boolean") then
        killer.name, killer.kind, killer.class, killer.faction = "", "", "", ""
    end
    return killer
end

ByteTerrace.Facts.death = {
    toggle = false,
    demand = true,
    state = {
        { name = "count", kind = "number", default = 0, persist = false },
        { name = "attributed", kind = "number", default = 0, persist = false },
        { name = "killer", kind = "string", default = "", persist = false },
        { name = "killerKind", kind = "string", default = "", persist = false },
        { name = "killerClass", kind = "string", default = "", persist = false },
        { name = "killerFaction", kind = "string", default = "", persist = false },
        { name = "killerSpell", kind = "string", default = "", persist = false },
        { name = "killerDamage", kind = "number", default = 0, persist = false },
    },
    OnEnable = function(module)
        local state = module.Addon.State
        local count = module:Id("count")
        local handled = NewestDeath() -- the highest recap ID already attributed (or there at start)
        local waitHandle -- the meter-update handler while a death waits for its recap
        local waitTimer  -- gives up after RecapWait, then stops setting a late recap aside after LateWait
        local retries = {}
        local late = false -- the wait gave up: a recap that arrives now is a published death's

        local function StopWaiting()
            late = false
            if waitHandle then
                module:Off(waitHandle)
                waitHandle = nil
            end
            module:Cancel(waitTimer)
            waitTimer = nil
            for i = #retries, 1, -1 do
                module:Cancel(retries[i])
                retries[i] = nil
            end
        end

        -- Publishes the killer of your latest death (nil: unknown).
        local function Attribute(killer)
            killer = killer or {}
            module:Set("killer", killer.name or "")
            module:Set("killerKind", killer.kind or "")
            module:Set("killerClass", killer.class or "")
            module:Set("killerFaction", killer.faction or "")
            module:Set("killerSpell", killer.spell or "")
            module:Set("killerDamage", killer.damage or 0)
            module:Set("attributed", state.Values[count])
        end

        -- Attributes the death once the meter holds a recap newer than the last one; a late one
        -- only moves handled past it.
        local function TryRecap()
            local id = NewestDeath()
            if id <= handled then
                return false
            end
            handled = id
            local wasLate = late
            StopWaiting()
            if not wasLate then
                Attribute(Killer(id))
            end
            return true
        end

        module:On("PLAYER_DEAD", function()
            StopWaiting()
            state:Set(count, state.Values[count] + 1)
            if TryRecap() then
                return
            end
            waitHandle = module:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", TryRecap)
            for i, delay in ipairs(RecapRetries) do
                retries[i] = module:After(delay, TryRecap)
            end
            waitTimer = module:After(RecapWait, function()
                late = true
                -- The meter handler stays: a recap landing late must be set aside before the next
                -- death, which could otherwise take it for its own.
                waitTimer = module:After(LateWait, StopWaiting)
                Attribute(nil)
            end)
        end)
        -- After a /reload, deaths already in the session aren't new.
        module:On("PLAYER_ENTERING_WORLD", function()
            if not waitHandle then
                handled = max(handled, NewestDeath())
            end
        end)
    end,
}
