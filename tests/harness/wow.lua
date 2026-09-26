-- A fake WoW: Forever client for behavioral tests, run in real Lua 5.1.
--
-- Fidelity rules, each enforced so a test fails where the client would:
--   * Secret values and restrictions (secrets.lua): APIs the snapshot flags return opaque secrets
--     when their documented predicate holds under h.restrictions; secret arguments, protected
--     calls and restricted functions are enforced from the snapshot entry of every wrapped API.
--     A blocked call does nothing, fires ADDON_ACTION_BLOCKED (or _FORBIDDEN) and is recorded
--     in h.blocked; the caller keeps running, like the client.
--   * Restriction changes fire ADDON_RESTRICTION_STATE_CHANGED like the client: Activating (1)
--     while the restriction isn't enforced yet, then Active (2) once it is; Inactive (0) after
--     it's lifted. IsAddOnRestrictionActive is false during every such dispatch (its doc).
--   * Only real API: registering an event, firing one, or calling a widget method the snapshot
--     doesn't list is an error, and every fake names a global the client dump has (the test
--     runner checks). Reading an undefined global is an error unless the TOC declares it as a
--     SavedVariable.
--   * SavedVariables are nil while an addon's files run and are assigned just before its
--     ADDON_LOADED, like the client.
--   * InCombatLockdown() is still false while PLAYER_REGEN_DISABLED handlers run.
--   * A script error reaches the error handler (h.errors) and the dispatch continues; a test
--     fails on any error it didn't expect (h:ExpectErrors).
--   * Every widget method call is counted, so tests can assert work per event. Widget state
--     lives in a side table (Harness.State(widget)), never in the widget's own fields.
--   * SavedVariables are written like the client writes them: finite numbers, strings, booleans
--     and tables with string or finite-number keys, copied (shared tables become separate copies;
--     a cycle's back-reference, functions, userdata, widgets, NaN and inf are dropped).
--   * h:Advance runs at most Harness.MAX_TIMER_CALLBACKS callbacks per call and then errors, so a
--     timer that keeps rescheduling itself fails the test instead of hanging it.
--   * Groups and addon messages (group.lua): party and raid tokens, IsInGroup/IsInRaid by
--     category, and C_ChatInfo.SendAddonMessage's validation, lockdown, per-prefix throttle and
--     echo of your own group messages.
--   * Keyboard input (input.lua, h:Key) reaches visible, keyboard-enabled frames topmost first; a
--     frame that doesn't propagate keyboard input (the default) consumes the key.
--   * The env's math.random is Lua's until h:SeedRandom(n) (input.lua) switches it, and random, to
--     the harness's own deterministic generator.
--   * Enemy players, nameplates, mouseover, death, raid icons and guilds (units.lua); location,
--     maps, waypoints, honor and raid warnings (world.lua); right-click and context menus, class
--     colors and the unit tooltip (ui.lua); Blizzard's damage meter and death recaps (meter.lua);
--     spoken alerts and text to speech (speech.lua).
--   * Every combat is a damage meter session: h:EnterCombat starts one, h:LeaveCombat ends it.
--   * Calibration probes (probes.lua): Harness.RunProbe runs a ByteTerrace_DevTools probe the way
--     /btdev probe does in game and compares it with the client's record (Harness.OBSERVED_PROBES).
--
-- Usage (see tests/*.test.lua):
--   local h = Harness.New({ classFile = "ROGUE" })
--   h:LoadAddon("TheLanKrewToolKit")
--   h:EnterCombat()

local Addons = __addons -- set by tools/lib/harness.mjs: { [name] = { files, sources, metadata, ... } }

-- Decodes the API snapshot tools/lib/harness.mjs passes as text into
-- { functions, events, methods = { [api] = { [method] = entry } }, enums }. An entry holds secret
-- (a set of flags), SecretArguments, IsProtectedFunction, HasRestrictions, Arguments and Payload
-- (comma-separated types), the aspect sets SecretArgumentsAddAspect / SecretReturnsForAspect and
-- the Preconditions set (RequiresFontStringTextAccess, RestrictedForMacroChatMessages, ...).
local function Set(list)
    if list == "" then
        return nil
    end
    local set = {}
    for item in list:gmatch("[^,]+") do
        set[item] = true
    end
    return set
end

local function DecodeSnapshot(text)
    local snapshot = { functions = {}, events = {}, methods = {}, enums = {} }
    for line in text:gmatch("[^\n]+") do
        local fields, i = {}, 0
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do
            i = i + 1
            fields[i] = field
        end
        local kind, name = fields[1], fields[2]
        if kind == "N" then
            local enum = {}
            for key, value in fields[3]:gmatch("([^,=]+)=([^,]+)") do
                enum[key] = tonumber(value)
            end
            snapshot.enums[name] = enum
        else
            local entry = {
                secret = Set(fields[3]), SecretArguments = fields[4] ~= "" and fields[4] or nil,
                IsProtectedFunction = fields[5] == "1" or nil, HasRestrictions = fields[6] == "1" or nil,
                Arguments = fields[7], Payload = fields[8],
                SecretArgumentsAddAspect = Set(fields[9]), SecretReturnsForAspect = Set(fields[10]),
                Preconditions = Set(fields[11] or ""),
            }
            if kind == "F" then
                snapshot.functions[name] = entry
            elseif kind == "E" then
                snapshot.events[name] = entry
            else
                local api, method = name:match("^([^.]+)%.(.+)$")
                snapshot.methods[api] = snapshot.methods[api] or {}
                snapshot.methods[api][method] = entry
            end
        end
    end
    return snapshot
end

if type(__snapshot) == "string" then
    __snapshot = DecodeSnapshot(__snapshot)
end
local Snapshot = __snapshot

-- JS arrays arrive 0-based; make them Lua sequences.
local function Sequence(t)
    if t == nil or t[0] == nil then
        return t or {}
    end
    local out, i = {}, 0
    while t[i] ~= nil do
        out[i + 1] = t[i]
        i = i + 1
    end
    return out
end
for _, addon in pairs(Addons) do
    addon.files, addon.sources = Sequence(addon.files), Sequence(addon.sources)
    addon.savedVariables, addon.savedVariablesPerCharacter = Sequence(addon.savedVariables), Sequence(addon.savedVariablesPerCharacter)
    addon.dependencies = Sequence(addon.dependencies)
    addon.missing = Sequence(addon.missing)
end

Harness = {}
Harness.__index = Harness
Harness.created = {}

-- Widget state, keyed weakly by the widget (see widgets.lua).
Harness.widgetStates = setmetatable({}, { __mode = "k" })

-- A widget's harness state ({ value, min, max, text, shown, calls, scripts, events, ... }), or
-- nil for anything that isn't a widget. Live: tests may reset calls through it.
function Harness.State(widget)
    return Harness.widgetStates[widget]
end

function Harness:WidgetState(widget)
    return Harness.widgetStates[widget]
end

-- Timer callbacks one h:Advance may run before it decides a timer reschedules itself forever.
Harness.MAX_TIMER_CALLBACKS = 10000

-- Unit tokens a test can populate with h:SetUnit (absent until set: UnitExists is false).
local ConfigurableUnits = { pet = true, focus = true, mouseover = true, vehicle = true }
for i = 1, 4 do ConfigurableUnits["party" .. i] = true end
for i = 1, 40 do ConfigurableUnits["nameplate" .. i] = true end

-- Defines a test-only addon (for the harness's own tests): spec = { sources = { "lua", ... },
-- savedVariables, savedVariablesPerCharacter, dependencies, metadata, missing = { TOC files the disk lacks } }.
function Harness.DefineAddOn(name, spec)
    local files = {}
    for i in ipairs(spec.sources) do
        files[i] = "File" .. i .. ".lua"
    end
    Addons[name] = {
        files = files, sources = spec.sources, metadata = spec.metadata or {},
        savedVariables = spec.savedVariables or {}, savedVariablesPerCharacter = spec.savedVariablesPerCharacter or {},
        dependencies = spec.dependencies or {}, missing = spec.missing or {},
    }
end

-- A fixed server clock start (2025-09-25 12:00:00 UTC), so date-based output is deterministic.
Harness.SERVER_EPOCH = 1758801600

local UnitDefaults = {
    exists = true, isPlayer = false, canAttack = false, dead = false, feign = false, afk = false,
    health = 100, maxHealth = 100, level = 1, inGroup = false,
}

local function FillUnit(unit)
    for field, default in pairs(UnitDefaults) do
        if unit[field] == nil then
            unit[field] = default
        end
    end
    if unit.isPlayer and unit.surname == nil then
        unit.surname = Harness.DEFAULT_SURNAME -- [E] every Forever character has a surname
    end
    if unit.playerControlled == nil then
        unit.playerControlled = unit.isPlayer -- players (and their pets) are player-controlled
    end
    return unit
end
Harness.FillUnit = FillUnit

-- The surname a player unit gets when a test gives none.
Harness.DEFAULT_SURNAME = "Doe"

-- [E] A unit's full name as Forever shows it: "First Last" for a player, the name alone for an NPC
-- (GetPlayerInfoByGUID and chat senders say "Aa Aa", probed in game).
function Harness.DisplayName(unit)
    return unit.surname and (unit.name .. " " .. unit.surname) or unit.name
end

function Harness.New(player)
    player = player or {}
    local h = setmetatable({}, Harness)
    h.time = 0                -- GetTime()
    h.serverTime = Harness.SERVER_EPOCH -- GetServerTime(), time()
    h.inCombat = false        -- the player is in combat (mirrors restrictions.Combat)
    h.lockdown = false        -- InCombatLockdown()
    h.restrictions = {}       -- [Enum.AddOnRestrictionType name] = true while active
    for _, name in ipairs(Harness.RESTRICTIONS) do
        h.restrictions[name] = false
    end
    h.restrictionStates = {}  -- [name] = Enum.AddOnRestrictionState while changing or active
    h.restrictionDispatch = 0 -- > 0 while ADDON_RESTRICTION_STATE_CHANGED dispatches
    h.blocked = {}            -- API names blocked (ADDON_ACTION_BLOCKED) or forbidden (_FORBIDDEN)
    h.forbidden = {}          -- API names refused with ADDON_ACTION_FORBIDDEN
    h.frames = {}             -- frames (event and input receivers), in creation order
    h.widgets = {}            -- every widget: frames, regions, animations
    h.methodCache = {}
    h.timers = {}             -- pending C_Timer callbacks and animations, see Advance
    h.timerSerial = 0
    h.handles = 0
    h.apiCalls = {}           -- [API name] = calls to that wrapped function (h:CountApiCalls)
    -- C_AddOnProfiler's answers: enabled, and [metric] = number for each addon, the application
    -- and all addons together; memory is GetAddOnMemoryUsage's KB by addon.
    h.profiler = { enabled = false, addons = {}, application = {}, overall = {}, memory = {} }
    h.memoryUpdates = 0       -- UpdateAddOnMemoryUsage calls
    h.printed = {}
    h.sounds = {}             -- { path, channel, handle } per PlaySoundFile that played
    h.soundKits = {}          -- { kit, channel, handle } per PlaySound / C_Sound.PlaySound
    h.stopped = {}            -- { handle, fade } per StopSound
    h.files = {}              -- [path] = true for media that exists (C_UIFileAsset.IsKnownFile knows it)
    h.mutedChannels = {}      -- [channel] = true: PlaySoundFile won't play on it (willPlay false)
    h.led = nil               -- current light bar color {r,g,b}, nil when cleared
    h.vibrations = {}         -- { type, intensity }
    h.vibrationsStopped = 0   -- C_GamePad.StopVibration calls
    h.opened = {}             -- Settings.OpenToCategory ids
    h.settings = {}           -- [variable] = setting
    h.settingsPages = {}      -- the Settings fake's pages and their entries (env.lua)
    h.spellNames = { [5308] = "Execute" }
    h.usable = {}             -- [spellName] = { isUsable, insufficientPower }
    h.zone = player.zone or "Elwynn Forest"   -- GetRealZoneText / GetZoneText
    h.subZone = player.subZone or ""          -- GetSubZoneText
    h.maxLevel = 60           -- GetMaxPlayerLevel
    local powerType = player.powerType or 3   -- Enum.PowerType.Energy
    h.player = FillUnit({
        isPlayer = true, playerControlled = true,
        classFile = player.classFile or "ROGUE", name = player.name or "Tester", surname = player.surname,
        realm = player.realm or "Forever",
        level = player.level or 1, xp = player.xp or 0, xpMax = player.xpMax or 400, rested = player.rested or 0,
        money = player.money or 0, resting = player.resting or false,
        powerType = powerType,
        power = { [3] = 100, [powerType] = 100 }, powerMax = { [3] = 100, [powerType] = 100 },
    })
    h.target = nil
    h.units = {}              -- [token] = unit table for h:SetUnit tokens (pet, focus, party1, ...)
    h.declared = {}           -- globals the TOC declares (SavedVariables); nil reads allowed
    h.errors = {}             -- messages passed to the error handler; a test fails if any are unexpected
    h.notified = {}           -- [settings variable] = Settings.NotifyUpdate calls
    h.expectedErrors = 0      -- a count, or a list of patterns (see ExpectErrors)
    h.propagated = {}         -- gamepad buttons no frame consumed
    h.propagatedKeys = {}     -- keys no frame consumed (h:Key)
    h.group = { kind = nil, members = {} } -- see group.lua
    h.partySerial = 0
    h.prefixes = {}           -- [prefix] = true once registered (C_ChatInfo); a UI restart clears them
    h.prefixOrder = {}
    h.addonMessages = {}      -- { prefix, message, chatType, target, result } per SendAddonMessage
    h.throttle = {}           -- [prefix] = { allowance, time } after its last successful send
    h.echo = true             -- your own group addon messages come back to you (h:Echo)
    h.rng = nil               -- h:SeedRandom state; nil = Lua's math.random
    h.labelStyle = nil        -- C_GamePad labelStyle of the connected controller; nil = none connected
    h.loaded = {}
    h.loadOrder = {}
    h.loggedIn = false        -- IsLoggedIn(): true from PLAYER_LOGIN on
    h.saved = player.saved or {} -- [SavedVariable name] = value, as the client restores it
    h:InitWorld(player)       -- units, maps, waypoints, honor, raid notices (units.lua, world.lua)
    h:InitMeter()             -- damage meter sessions and death recaps (meter.lua)
    h:InitSpeech(player)      -- h.spoken and the speech settings (speech.lua)
    h.env = h:BuildEnvironment()
    Harness.created[#Harness.created + 1] = h
    return h
end

-- The harness unit table for a token, or nil (the unit doesn't exist). A secret token (passed to
-- an API that allows secret arguments) names the same unit.
function Harness:Unit(token)
    token = Reveal(token)
    if token == "player" then
        return self.player
    elseif token == "target" then
        return self.target
    elseif type(token) == "string" then
        return self.units[token] or self:GroupUnit(token)
    end
end

-- Sets (or with nil, removes) a unit other than the player and target: pet, focus, mouseover,
-- vehicle, party1-4 or nameplate1-40 (a party token set here wins over h:JoinGroup's). Missing fields default like SetTarget's. Fires nothing;
-- fire the event the change would cause (PLAYER_FOCUS_CHANGED, UNIT_PET, ...) if the test needs it.
function Harness:SetUnit(token, unit)
    assert(ConfigurableUnits[token], "SetUnit: " .. tostring(token) .. " isn't a configurable unit (use h.player or h:SetTarget)")
    self.units[token] = unit and FillUnit(unit) or nil
end

-- Declares the errors this test deliberately causes: a count (h:ExpectErrors(2)) or Lua patterns
-- (h:ExpectErrors("did not settle", "boom")), each matching one reported error, in any order.
function Harness:ExpectErrors(first, ...)
    if type(first) == "number" then
        self.expectedErrors = first
    else
        self.expectedErrors = { first, ... }
    end
end

-- Returns nil when the reported errors are what the test expected, else a description.
function Harness:UnexpectedErrors()
    local expected = self.expectedErrors
    if type(expected) == "number" then
        if #self.errors ~= expected then
            return ("reported errors (expected %d): %s"):format(expected, table.concat(self.errors, " | "))
        end
        return nil
    end
    local unmatched = {}
    for _, message in ipairs(self.errors) do
        unmatched[#unmatched + 1] = message
    end
    for _, pattern in ipairs(expected) do
        local found
        for i, message in ipairs(unmatched) do
            if message:find(pattern) then
                found = i
                break
            end
        end
        if not found then
            return ("no reported error matches %q (reported: %s)"):format(pattern, table.concat(self.errors, " | "))
        end
        table.remove(unmatched, found)
    end
    if #unmatched > 0 then
        return "unexpected reported errors: " .. table.concat(unmatched, " | ")
    end
    return nil
end

function Harness:ReportError(message)
    self.errors[#self.errors + 1] = tostring(message)
end

-- Registers a unit table as the target (nil clears) and fires PLAYER_TARGET_CHANGED. Missing
-- fields default: an existing, living, full-health NPC; playerControlled follows isPlayer.
function Harness:SetTarget(unit)
    self.target = unit and FillUnit(unit) or nil
    self:Fire("PLAYER_TARGET_CHANGED")
end

function Harness:FireRestriction(index, state)
    self.restrictionDispatch = self.restrictionDispatch + 1
    self:Fire("ADDON_RESTRICTION_STATE_CHANGED", index, state)
    self.restrictionDispatch = self.restrictionDispatch - 1
end

-- Activates or clears an addon restriction (Enum.AddOnRestrictionType name). Activating fires
-- ADDON_RESTRICTION_STATE_CHANGED(type, Activating) while the restriction isn't enforced, then
-- enforces it and fires Active; clearing lifts it, then fires Inactive.
function Harness:SetRestriction(name, active)
    local index
    for i, known in ipairs(Harness.RESTRICTIONS) do
        if known == name then
            index = i - 1
        end
    end
    assert(index, "unknown restriction " .. tostring(name))
    active = active and true or false
    if self.restrictions[name] == active then
        return
    end
    if active then
        self.restrictionStates[name] = 1
        self:FireRestriction(index, 1) -- Activating: not enforced during this dispatch
        self.restrictions[name] = true
        self.restrictionStates[name] = 2
        self:FireRestriction(index, 2) -- Active
    else
        self.restrictions[name] = false
        self.restrictionStates[name] = 0
        self:FireRestriction(index, 0) -- Inactive
    end
end

-- Enum.AddOnRestrictionState of a restriction.
function Harness:RestrictionState(name)
    return self.restrictionStates[name] or (self.restrictions[name] and 2 or 0)
end

-- Combat: the Combat restriction and PLAYER_REGEN_DISABLED, then lockdown and a new damage meter
-- session (meter.lua).
function Harness:EnterCombat()
    self.inCombat = true
    self:SetRestriction("Combat", true)
    self:Fire("PLAYER_REGEN_DISABLED")
    self.lockdown = true
    self:MeterStartSession()
end

-- Leaving combat ends the damage meter session before PLAYER_REGEN_ENABLED.
function Harness:LeaveCombat()
    self.lockdown = false
    self.inCombat = false
    self:MeterEndSession()
    self:SetRestriction("Combat", false)
    self:Fire("PLAYER_REGEN_ENABLED")
end

function Harness:AddMedia(path)
    self.files[path] = true
end

-- Schedules fn at h.time + delay; returns the entry (entry.cancelled stops it).
function Harness:Schedule(delay, fn)
    self.timerSerial = self.timerSerial + 1
    local entry = { due = self.time + math.max(delay or 0, 0), serial = self.timerSerial, fn = fn }
    self.timers[#self.timers + 1] = entry
    return entry
end

-- Advances GetTime and the server clock by seconds, running every C_Timer callback and
-- animation finish that falls due, in due order (ties in scheduling order). A callback's error
-- reaches the error handler. More than MAX_TIMER_CALLBACKS callbacks in one call is an error.
function Harness:Advance(seconds)
    local target = self.time + seconds
    local ran = 0
    while true do
        local nextIndex
        for i, entry in ipairs(self.timers) do
            if not entry.cancelled and entry.due <= target then
                local best = nextIndex and self.timers[nextIndex]
                if not best or entry.due < best.due or (entry.due == best.due and entry.serial < best.serial) then
                    nextIndex = i
                end
            end
        end
        if not nextIndex then
            break
        end
        ran = ran + 1
        if ran > Harness.MAX_TIMER_CALLBACKS then
            error(("h:Advance ran %d timer callbacks without reaching time %s: a timer keeps rescheduling itself")
                :format(Harness.MAX_TIMER_CALLBACKS, tostring(target)), 2)
        end
        local entry = table.remove(self.timers, nextIndex)
        self.serverTime = self.serverTime + (entry.due - self.time)
        self.time = entry.due
        self:Protect(entry.fn)
    end
    for i = #self.timers, 1, -1 do
        if self.timers[i].cancelled then
            table.remove(self.timers, i)
        end
    end
    self.serverTime = self.serverTime + (target - self.time)
    self.time = target
end

-- Runs fn(...) like the client runs a script: an error goes to the error handler.
function Harness:Protect(fn, ...)
    local args, n = { ... }, select("#", ...)
    local ok, err = pcall(function() return fn(unpack(args, 1, n)) end)
    if not ok then
        self:ReportError(err)
    end
    return ok
end

-- Dispatches an event to every frame registered for it when the dispatch starts (frames created
-- or registered during it wait for the next one). Unit registrations filter on the raw unit
-- token, before any wrapping. A payload the snapshot flags as secret is wrapped when its
-- predicate holds, except its unit-token fields. Handler errors reach the error handler.
function Harness:Fire(event, ...)
    local entry = Snapshot.events[event]
    assert(entry, "Fire: unknown event " .. tostring(event))
    local payload = { n = select("#", ...), ... }
    local unit = payload[1]
    local receivers = {}
    for _, frame in ipairs(self.frames) do
        local registration = Harness.State(frame).events[event]
        if registration and (registration == true or (unit ~= nil and registration[unit])) then
            receivers[#receivers + 1] = frame
        end
    end
    if entry.secret and self:SecretFor(entry.secret, Harness.CallContext(entry, "Payload", payload)) then
        local types = Harness.Types(entry, "Payload")
        for i = 1, payload.n do
            if not Harness.IsUnitType(Harness.TypeAt(types, i)) then
                payload[i] = Secret(payload[i])
            end
        end
    end
    for _, frame in ipairs(receivers) do
        local state = Harness.State(frame)
        local handler = state.scripts.OnEvent
        if handler and state.events[event] then
            self:Protect(handler, frame, event, unpack(payload, 1, payload.n))
        end
    end
end

-- Resets every widget's call counters (for per-event work assertions).
function Harness:ResetCalls()
    for _, widget in ipairs(self.widgets) do
        Harness.State(widget).calls = {}
    end
end

-- Calls to a wrapped API function ("UnitHealth", "C_Spell.IsSpellUsable") since the harness was
-- made or the count was reset (h.apiCalls = {}), so tests can assert the work per event.
function Harness:CountApiCalls(name)
    return self.apiCalls[name] or 0
end

-- Every widget's (frames, regions, animations) calls to method, summed.
function Harness:CountCalls(method)
    local total = 0
    for _, widget in ipairs(self.widgets) do
        total = total + (Harness.State(widget).calls[method] or 0)
    end
    return total
end

local function SavedNames(addon)
    local names = {}
    for _, list in ipairs({ addon.savedVariables, addon.savedVariablesPerCharacter }) do
        for _, name in ipairs(list) do
            names[#names + 1] = name
        end
    end
    return names
end

-- Loads one addon's files (dependencies first), assigns its SavedVariables (account and
-- per-character, from h.saved) and fires its ADDON_LOADED, like the client. The SavedVariables
-- are nil while the files run; a restored value replaces whatever the files assigned.
function Harness:LoadFiles(name)
    if self.loaded[name] then
        return self.loaded[name]
    end
    local addon = assert(Addons[name], "unknown addon " .. tostring(name))
    assert(#addon.missing == 0, ("%s: the TOC lists %s, which doesn't exist"):format(name, table.concat(addon.missing, ", ")))
    for _, dependency in ipairs(addon.dependencies) do
        self:LoadFiles(dependency)
    end
    local saved = SavedNames(addon)
    for _, variable in ipairs(saved) do
        self.declared[variable] = true
        rawset(self.env, variable, nil)
    end
    local ns = {}
    self.loading = addon
    for i, file in ipairs(addon.files) do
        local chunk = assert(loadstring(addon.sources[i], "@" .. name .. "/" .. file))
        setfenv(chunk, self.env)
        self:Protect(chunk, name, ns) -- like the client: a file that errors is reported, the rest still load
    end
    self.loading = nil
    self.loaded[name] = ns
    self.loadOrder[#self.loadOrder + 1] = name
    for _, variable in ipairs(saved) do
        if self.saved[variable] ~= nil then
            rawset(self.env, variable, self.saved[variable])
        end
    end
    self:Fire("ADDON_LOADED", name, false)
    return ns
end

-- Loads an addon and runs the login sequence. Returns the addon's namespace table.
function Harness:LoadAddon(name)
    local ns = self:LoadFiles(name)
    self.ns, self.mainAddon = ns, name
    self:Login(true, false)
    return ns
end

function Harness:Login(isInitialLogin, isReloadingUi)
    self.loggedIn = true
    self:Fire("PLAYER_LOGIN")
    self:Fire("PLAYER_ENTERING_WORLD", isInitialLogin, isReloadingUi)
end

local function Finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

-- What the client writes to disk and reads back: finite numbers, strings, booleans, and tables
-- keyed by strings or finite numbers, written out as text, so every table read back is a fresh
-- copy (shared references become separate tables). Functions, widgets, NaN, inf and a cycle's
-- back-reference aren't saved. A secret is an error [C]: what the client does with one is
-- unknown, and an addon that lets a secret reach its SavedVariables broke the secret rule anyway.
-- path holds the tables being written.
local function Serialize(value, path)
    if IsSecret(value) then
        error("a secret value reached SavedVariables", 0)
    end
    local kind = type(value)
    if kind == "string" or kind == "boolean" then
        return value
    elseif kind == "number" then
        return Finite(value) and value or nil
    elseif kind ~= "table" or Harness.State(value) then
        return nil
    end
    path = path or {}
    if path[value] then
        return nil
    end
    path[value] = true
    local copy = {}
    for k, v in pairs(value) do
        if type(k) == "string" or (type(k) == "number" and Finite(k)) then
            local saved = Serialize(v, path)
            if saved ~= nil then
                copy[k] = saved
            end
        end
    end
    path[value] = nil
    return copy
end
Harness.Serialize = Serialize

-- Logs out and back in (or reloads the UI): fires PLAYER_LOGOUT, writes every loaded addon's
-- SavedVariables, then starts a fresh UI (new frames and environment, same world) that loads
-- the same addons and runs the login sequence with the given PLAYER_ENTERING_WORLD arguments.
-- whileAway (optional) runs after logout and before the files load again: the world can change
-- while the player is gone (time passes, rested XP accrues).
function Harness:Restart(isInitialLogin, isReloadingUi, whileAway)
    self:Fire("PLAYER_LOGOUT")
    for _, name in ipairs(self.loadOrder) do
        for _, variable in ipairs(SavedNames(Addons[name])) do
            self.saved[variable] = Serialize(rawget(self.env, variable))
        end
    end
    if whileAway then
        whileAway(self)
    end
    local order, main = self.loadOrder, self.mainAddon
    self.frames, self.widgets, self.timers, self.loaded, self.loadOrder, self.declared = {}, {}, {}, {}, {}, {}
    self.loggedIn, self.ns = false, nil
    self.settings, self.settingsOrder, self.settingsPages, self.category = {}, nil, {}, nil
    self.prefixes, self.prefixOrder = {}, {}
    self.env = self:BuildEnvironment()
    for _, name in ipairs(order) do
        local ns = self:LoadFiles(name)
        if name == main or not main then
            self.ns = ns
        end
    end
    self:Login(isInitialLogin, isReloadingUi)
end

-- /reload: PLAYER_ENTERING_WORLD(false, true).
function Harness:Reload()
    self:Restart(false, true)
end

-- Logs out, waits serverSecondsLater (default 60) and logs back in: PLAYER_ENTERING_WORLD(true, false).
-- Logging out ends combat, lockdown and every restriction, and clears the damage meter's sessions
-- and recaps. whileAway(h), if given, runs while logged out, after the time has passed.
function Harness:Relog(serverSecondsLater, whileAway)
    local seconds = serverSecondsLater or 60
    self:Restart(true, false, function()
        self.inCombat, self.lockdown = false, false
        for _, name in ipairs(Harness.RESTRICTIONS) do
            self.restrictions[name] = false
        end
        self.restrictionStates = {}
        self:InitMeter()
        self.serverTime = self.serverTime + seconds
        self.time = self.time + seconds
        if whileAway then
            whileAway(self)
        end
    end)
end

-- Presses (down = true) or releases a gamepad key like "PAD1". Visible frames (every ancestor
-- shown) with gamepad buttons enabled get it newest first until one consumes it (its script
-- doesn't return true).
function Harness:Gamepad(key, down)
    local script = down and "OnGamePadButtonDown" or "OnGamePadButtonUp"
    for i = #self.frames, 1, -1 do
        local frame = self.frames[i]
        local state = Harness.State(frame)
        local handler = state.scripts[script]
        if state.gamepadButtons and self:IsVisibleWidget(frame) and handler and handler(frame, key) ~= true then
            return
        end
    end
    self.propagated[#self.propagated + 1] = key
end

-- Clicks a widget with the mouse (button defaults to "LeftButton"): OnMouseDown, OnMouseUp and,
-- for a Button, OnClick. Only a visible, mouse-enabled widget receives clicks (a Button is
-- mouse-enabled from creation, like the client's). Returns whether the click landed.
function Harness:Click(widget, button)
    button = button or "LeftButton"
    local state = Harness.State(widget)
    if not self:IsVisibleWidget(widget) or not state.mouseEnabled then
        return false
    end
    local scripts = state.scripts
    if scripts.OnMouseDown then self:Protect(scripts.OnMouseDown, widget, button) end
    if scripts.OnMouseUp then self:Protect(scripts.OnMouseUp, widget, button, true) end
    if state.widgetType == "Button" and state.enabled ~= false and scripts.OnClick then
        self:Protect(scripts.OnClick, widget, button, false)
    end
    return true
end

-- Moves the mouse onto (entering = true) or off a widget: OnEnter(widget, true) or
-- OnLeave(widget, true). Like clicks, only a visible, mouse-enabled widget gets them. Returns
-- whether the script ran.
function Harness:Hover(widget, entering)
    local state = Harness.State(widget)
    local handler = state.scripts[entering == false and "OnLeave" or "OnEnter"]
    if not self:IsVisibleWidget(widget) or not state.mouseEnabled or not handler then
        return false
    end
    self:Protect(handler, widget, true)
    return true
end

-- Runs a slash command as if typed, e.g. h:Slash("/tlk fom").
function Harness:Slash(line)
    local command, rest = line:match("^(/%S+)%s*(.-)$")
    for key, handler in pairs(self.env.SlashCmdList) do
        for i = 1, 9 do
            local alias = rawget(self.env, "SLASH_" .. key .. i)
            if alias == nil then break end
            if alias:lower() == command:lower() then
                return handler(rest)
            end
        end
    end
    error("no slash command " .. command)
end
