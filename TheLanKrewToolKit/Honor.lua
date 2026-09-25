local addonName, ns = ...

-- Honor: your honorable kills, your deaths and who dealt them, as rows, for any feature that
-- reacts to them (Warband's vengeance, grudges and rivalry records; Streaks' announcer).
--
--   Honor.kills   honorable kills this session, one per kill message. The client gives addons no
--                 combat log; CHAT_MSG_COMBAT_HONOR_GAIN is how it says you got credit for a
--                 kill, your group's kills included.
--   Honor.victim  the last victim's name as the message printed it: "Name", or "Name-Realm" for
--                 another realm. It's set in the same publish that bumps Honor.kills.
--                 Everyone in your group nearby gets the same honorable kill, whoever landed it.
--   Honor.killingBlows  your killing blows on players this session (yours or your pet's), from
--                 PARTY_KILL, the event killing-blow addons read since the combat log closed. Its
--                 GUIDs are secret while unit identity is restricted (in instances); those don't
--                 count.
--   Honor.streak  killing blows since you last died (or since the module started).
--   Honor.deaths  your deaths this session.
--
-- Who killed you comes from Blizzard's death recap: the damage meter's Deaths lists (the current
-- session, else the overall one) hold your death with its recap ID (readable even in combat), and
-- the recap's newest event is the killing blow, a plain combat log event (probed in game). An
-- attacker the recap hides (hideCaster, which Blizzard's recap window honors) is unknown. The
-- recap may land a moment after PLAYER_DEAD, so the module looks again on the meter's updates and
-- at RecapRetries, at most RecapWait seconds; a recap that comes later (within LateWait) is set
-- aside, so the next death doesn't take it for its own.
--   Honor.killedBy       the Honor.deaths count the killer rows below describe; it bumps once per
--                        death, after they're set, even when the killer stays unknown.
--   Honor.killer         the killer's name as the recap printed it ("Name" or "Name-Realm"); ""
--                        when unknown.
--   Honor.killerKind     "player", "self" (your own blow: a sapper charge, say), "pet" (anything
--                        else a player controls: a pet, a totem), "npc", or "" when unknown.
--   Honor.killerClass    a player killer's class file ("ROGUE"), else "".
--   Honor.killerFaction  a player killer's faction ("Alliance" or "Horde"), else "".
--   Honor.killerSpell    the killing blow's spell name; "" for a melee swing or unknown.
--   Honor.killerDamage   the killing blow's damage; 0 when unknown.
--
-- It runs while a feature that reads it is on: Warband or Streaks (add yours to its active rule).
-- React to a kill or death by watching Honor.kills, Honor.killingBlows, Honor.deaths or
-- Honor.killedBy with skipInitial and acting when the count goes up: a stopped module resets its
-- rows.

local RecapWait = 3 -- seconds to wait for the damage meter to record your death
local LateWait = 30 -- seconds after that in which a late recap is still your last death's
local RecapRetries = { 0.3, 1 } -- seconds after the death to look again, whatever the meter says
local PlayerControlled = 0x100 -- COMBATLOG_OBJECT_CONTROL_PLAYER in a combat log event's flags
-- UnitRace's raceFile for each race a Forever character can be, by faction.
local RaceFactions = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde",
}

local C_DamageMeter, C_DeathRecap, C_Timer, Enum = C_DamageMeter, C_DeathRecap, C_Timer, Enum
local GetPlayerInfoByGUID, issecretvalue, UnitGUID = GetPlayerInfoByGUID, issecretvalue, UnitGUID
local floor, ipairs, max, type = math.floor, ipairs, math.max, type

local Addon = ns.Addon

local Handled = 0  -- the highest recap ID already attributed (or there when the module started)
local WaitHandle   -- the meter-update handler while a death waits for its recap
local WaitTimer    -- gives up on the recap after RecapWait, and stops setting a late one aside after LateWait
local Late = false -- the wait gave up: a recap that arrives now belongs to a death already published

-- A Lua pattern from a client format string ("%s dies (Honorable Kill: %s). ..."): each %s is a
-- capture, so the first capture is the victim's name.
local function Pattern(formatString)
    if type(formatString) ~= "string" then
        return nil
    end
    local pattern = formatString:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%%d?%$?s", "(.-)"):gsub("%%%d?%$?d", "%%d+")
    return "^" .. pattern .. "$"
end

local HonorPatterns = { Pattern(COMBATLOG_HONORGAIN), Pattern(COMBATLOG_HONORGAIN_NO_RANK) }

-- The victim's name in an honorable kill message, or nil (bonus honor names no one).
local function Victim(text)
    for _, pattern in ipairs(HonorPatterns) do
        local victim = text:match(pattern)
        if victim and victim ~= "" then
            return victim
        end
    end
    return nil
end

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

Addon:Module("Honor", {
    toggle = false,
    active = {
        reads = { "Warband.enabled", "Streaks.enabled" },
        when = function(state) return state:Get("Warband.enabled") or state:Get("Streaks.enabled") end,
    },
    state = {
        { name = "kills", kind = "number", default = 0, persist = false },
        { name = "victim", kind = "string", default = "", persist = false },
        { name = "killingBlows", kind = "number", default = 0, persist = false },
        { name = "streak", kind = "number", default = 0, persist = false },
        { name = "deaths", kind = "number", default = 0, persist = false },
        { name = "killedBy", kind = "number", default = 0, persist = false },
        { name = "killer", kind = "string", default = "", persist = false },
        { name = "killerKind", kind = "string", default = "", persist = false },
        { name = "killerClass", kind = "string", default = "", persist = false },
        { name = "killerFaction", kind = "string", default = "", persist = false },
        { name = "killerSpell", kind = "string", default = "", persist = false },
        { name = "killerDamage", kind = "number", default = 0, persist = false },
    },
    OnEnable = function(module)
        local state = Addon.State
        local kills, victim, streak, deaths = module:Id("kills"), module:Id("victim"), module:Id("streak"), module:Id("deaths")
        Handled = NewestDeath()

        local function StopWaiting()
            Late = false
            if WaitHandle then
                module:Off(WaitHandle)
                WaitHandle = nil
            end
            if WaitTimer then
                WaitTimer:Cancel()
                WaitTimer = nil
            end
        end

        -- Publishes the killer of your latest death (nil: unknown).
        local function Attribute(killer)
            killer = killer or {}
            state:BeginBatch()
            module:Set("killer", killer.name or "")
            module:Set("killerKind", killer.kind or "")
            module:Set("killerClass", killer.class or "")
            module:Set("killerFaction", killer.faction or "")
            module:Set("killerSpell", killer.spell or "")
            module:Set("killerDamage", killer.damage or 0)
            module:Set("killedBy", state.Values[deaths])
            state:EndBatch()
        end

        -- Attributes the death once the meter holds a recap newer than the last one; a late one
        -- only moves Handled past it.
        local function TryRecap()
            local id = NewestDeath()
            if id <= Handled then
                return false
            end
            Handled = id
            local late = Late
            StopWaiting()
            if not late then
                Attribute(Killer(id))
            end
            return true
        end

        module:On("CHAT_MSG_COMBAT_HONOR_GAIN", function(text)
            local name = not issecretvalue(text) and type(text) == "string" and Victim(text)
            if not name then
                return
            end
            state:BeginBatch()
            state:Set(victim, name)
            state:Set(kills, state.Values[kills] + 1)
            state:EndBatch()
        end)
        module:On("PARTY_KILL", function(attackerGUID, targetGUID)
            if issecretvalue(attackerGUID) or issecretvalue(targetGUID) or type(targetGUID) ~= "string"
                or not targetGUID:find("^Player%-") then
                return
            end
            local me, pet = UnitGUID("player"), UnitGUID("pet")
            if issecretvalue(me) or issecretvalue(pet) then
                return
            end
            if attackerGUID ~= me and (pet == nil or attackerGUID ~= pet) then
                return -- a groupmate's blow
            end
            state:BeginBatch()
            state:Set(streak, state.Values[streak] + 1)
            module:Set("killingBlows", module:Get("killingBlows") + 1)
            state:EndBatch()
        end)
        module:On("PLAYER_DEAD", function()
            StopWaiting()
            state:BeginBatch()
            state:Set(streak, 0)
            state:Set(deaths, state.Values[deaths] + 1)
            state:EndBatch()
            if TryRecap() then
                return
            end
            WaitHandle = module:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", TryRecap)
            local death = state.Values[deaths]
            for _, delay in ipairs(RecapRetries) do
                C_Timer.After(delay, function()
                    if WaitHandle and not Late and state.Values[deaths] == death then
                        TryRecap()
                    end
                end)
            end
            WaitTimer = C_Timer.NewTimer(RecapWait, function()
                Late = true
                WaitTimer = C_Timer.NewTimer(LateWait, StopWaiting)
                Attribute(nil)
            end)
        end)
        -- After a /reload, deaths already in the session aren't new.
        module:On("PLAYER_ENTERING_WORLD", function()
            if not WaitHandle then
                Handled = max(Handled, NewestDeath())
            end
        end)
    end,
    OnDisable = function()
        if WaitTimer then
            WaitTimer:Cancel()
            WaitTimer = nil
        end
        WaitHandle, Late = nil, false -- the module's handlers go with it
    end,
})
