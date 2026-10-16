-- The global environment an addon sees inside the harness: fakes for the WoW API it uses, backed by the Harness world
-- state (see wow.lua). Every fake names a real global (the test runner checks each against the client dump).
-- Harness:WrapFunction wraps every global and C_* fake, so secret returns, secret arguments, and restrictions follow
-- its snapshot entry, and an undocumented one (PlaySoundFile, PlaySound, StopSound) refuses secret arguments.
--
-- Formatting helpers (GetMoneyString, SecondsToTime) are deterministic stand-ins, not Blizzard's exact output (no coin
-- textures, English unit names). date() and time() run in UTC.
--
-- Names [E]: Forever's names are regionally unique "First Last". UnitName, UnitNameUnmodified and UnitFullName return
-- (first, surname) for a player and (name, nil) for an NPC; no realm. GetPlayerInfoByGUID's name is "First Last" with
-- realm "" on your realm.

local Snapshot = __snapshot

-- [E] The client build the API snapshot was dumped from ("1.60.1 (70374)"), so the harness is the client its snapshot
-- describes and probes record that build. [G] The build date, which nothing reads.
Harness.BUILD = (((__build ~= "") and __build) or "0.0.0 (0)")
local BuildVersion, BuildNumber = Harness.BUILD:match("^(%S+) %((%d+)%)$")

local function Color(r, g, b, a)
    return {
        a = (a or 1), b = b, g = g, GetRGB = function(self) return self.r, self.g, self.b end,
        GetRGBA = function(self) return self.r, self.g, self.b, self.a end, r = r,
    }
end

-- UnitPowerType's token per Enum.PowerType value.
local PowerTokens = {
    [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [4] = "COMBO_POINTS", [5] = "RUNES",
    [6] = "RUNIC_POWER", [7] = "SOUL_SHARDS", [8] = "LUNAR_POWER", [9] = "HOLY_POWER", [10] = "ALTERNATE",
    [11] = "MAELSTROM", [12] = "CHI", [13] = "INSANITY", [16] = "ARCANE_CHARGES", [17] = "FURY", [18] = "PAIN",
    [19] = "ESSENCE",
}

-- UnitClass: className (enUS), classFile, classID.
local Classes = {
    DEATHKNIGHT = { "Death Knight", 6 }, DEMONHUNTER = { "Demon Hunter", 12 }, DRUID = { "Druid", 11 },
    EVOKER = { "Evoker", 13 }, HUNTER = { "Hunter", 3 }, MAGE = { "Mage", 8 }, MONK = { "Monk", 10 },
    PALADIN = { "Paladin", 2 }, PRIEST = { "Priest", 5 }, ROGUE = { "Rogue", 4 }, SHAMAN = { "Shaman", 7 },
    WARLOCK = { "Warlock", 9 }, WARRIOR = { "Warrior", 1 },
}

-- A few real SOUNDKIT entries (Blizzard_SharedXML/Mainline/SoundKitConstants.lua). Reading any other key is an error:
-- add it here, with its real value, when an addon needs it.
local Soundkits = {
    IG_QUEST_LIST_COMPLETE = 878, IG_QUEST_LOG_OPEN = 844, IG_SPELLBOOK_OPEN = 829, LFG_REWARDS = 17316,
    RAID_WARNING = 8959, READY_CHECK = 8960, UI_EPICLOOT_TOAST = 31578,
}

-- Lua libraries, limited to the members the client has (it removes some, such as string.dump).
local Libraries = {
    math = { "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor", "fmod", "frexp",
        "huge", "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow", "rad", "random", "sin", "sinh", "sqrt", "tan", "tanh" },
    string = { "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper" },
    table = { "concat", "insert", "maxn", "remove", "sort" },
}

-- Seconds since the epoch for a UTC date table (time{...} in the harness's UTC world).
local function EpochFromDate(t)
    local year = t.year
    local month = t.month

    if month <= 2 then year, month = (year - 1), (month + 12) end

    local era = math.floor(year / 400)
    local yoe = (year - (era * 400))
    local doy = ((math.floor(((153 * (month - 3)) + 2) / 5) + t.day) - 1)
    local doe = ((((yoe * 365) + math.floor(yoe / 4)) - math.floor(yoe / 100)) + doy)
    local days = (((era * 146097) + doe) - 719468)

    return ((((days * 86400) + ((t.hour or 12) * 3600)) + ((t.min or 0) * 60)) + (t.sec or 0))
end

local function Library(name)
    local lib = {}

    for _, member in ipairs(Libraries[name]) do
        lib[member] = _G[name][member]
    end

    return lib
end

local function MoneyString(money)
    local gold = math.floor(money / 10000)
    local silver = (math.floor(money / 100) % 100)
    local copper = (money % 100)
    local parts = {}

    if gold > 0 then parts[#parts + 1] = (gold .. "g") end

    if silver > 0 then parts[#parts + 1] = (silver .. "s") end

    if (copper > 0) or (#parts == 0) then parts[#parts + 1] = (copper .. "c") end

    return table.concat(parts, " ")
end

local function Refuse(name, ...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then
            error(name .. ": argument #" .. i .. " is a secret value", 3)
        end
    end
end

local function Strtrim(s, chars)
    local set = ((chars and ("[" .. chars:gsub("[%]%[%^%-%%]", "%%%0") .. "]")) or "%s")

    return (s:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
end

local TimeUnits = {
    { 86400, "Day", "Day", "Days" }, { 3600, "Hr", "Hour", "Hours" }, { 60, "Min", "Minute", "Minutes" },
    { 1, "Sec", "Second", "Seconds" },
}

local function SecondsToTime(seconds, noSeconds, notAbbreviated, maxCount)
    maxCount = (maxCount or 2)
    seconds = math.floor(seconds)
    local parts = {}

    for i, unit in ipairs(TimeUnits) do
        local isSeconds = (i == #TimeUnits)
        local count = math.floor(seconds / unit[1])

        if (count > 0) and (#parts < maxCount) and not (isSeconds and noSeconds) then
            local label = ((notAbbreviated and (((count == 1) and unit[3]) or unit[4])) or unit[2])

            parts[#parts + 1] = (count .. " " .. label)
            seconds = (seconds - (count * unit[1]))
        end
    end

    return table.concat(parts, " ")
end

-- Every fake's name ("Name" or "Table.member"), for the test runner's check that each one exists in the client dump.
-- Tables whose members are data (Enum values, SOUNDKIT) list one level.
function Harness.FakeNames()
    local h = Harness.New()

    Harness.created = {}
    local names = {}

    for name, value in pairs(h.env) do
        names[#names + 1] = name

        if (type(value) == "table") and (name ~= "_G") and not Harness.State(value) then
            for member in pairs(value) do
                if type(member) == "string" then
                    names[#names + 1] = (name .. "." .. member)
                end
            end
        end
    end

    table.sort(names)

    return table.concat(names, "\n")
end

function Harness:BuildEnvironment()
    local h = self

    local function Unit(token) return h:Unit(token) end

    local function Field(token, name, default)
        local unit = Unit(token)

        if unit == nil then
            return default
        end

        return unit[name]
    end

    -- A unit's amount from one of its power tables (power or powerMax), of powerType or else its primary power type. A
    -- unit without power has none.
    local function Power(token, field, powerType)
        local unit = Unit(token)

        if not unit then return 0 end

        return ((unit[field] or {})[powerType or unit.powerType or 0] or 0)
    end

    local function Handle(entry)
        local handle = {}

        function handle.Cancel() entry.cancelled = true end

        function handle.IsCancelled() return (entry.cancelled == true) end

        return handle
    end

    local function PlayKit(kit, channel)
        assert(type(kit) == "number", "PlaySound: soundKitID must be a number, got " .. type(kit))
        h.handles = (h.handles + 1)
        h.soundKits[#h.soundKits + 1] = { channel = (channel or "SFX"), handle = h.handles, kit = kit }

        return true, h.handles
    end

    -- order: grouped by the part of the client each fake models
    local fakes = {
        -- Lua, as the client exposes it. type() reports a secret's underlying type, like the client. tostring and
        -- string.format turn a secret into a secret string (secrets.lua), and tonumber and print refuse one.
        assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall,
        select = select, setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
        rawequal = rawequal, unpack = unpack,
        -- WoW's xpcall passes extra arguments to the function (Lua 5.1's doesn't).
        xpcall = function(fn, handler, ...)
            local args = { ... }
            local count = select("#", ...)

            return xpcall(function() return fn(unpack(args, 1, count)) end, handler)
        end,
        type = function(value)
            return type(Reveal(value))
        end,
        tostring = SecretToString,
        tonumber = function(value, base)
            Refuse("tonumber", value)

            return tonumber(value, base)
        end,
        math = Library("math"), string = Library("string"), table = Library("table"),
        tinsert = table.insert, tremove = table.remove,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        strtrim = Strtrim,
        print = function(...)
            Refuse("print", ...)
            local parts = {}

            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end

            h.printed[#h.printed + 1] = table.concat(parts, " ")
        end,

        issecretvalue = function(value) return IsSecret(value) end,
        geterrorhandler = function()
            return function(message) h:ReportError(message) end
        end,
        GetTime = function() return h.time end,
        -- [D] Blizzard_SharedXML/PixelUtil.lua (forever): GetNearestPixelSize rounds a size in UI units at a layout
        -- scale to whole pixels (at least minPixels, away from 0), and returns it in UI units. A pixel is 768 / the
        -- screen's height (GetPhysicalScreenSize) UI units at scale 1. Round is Blizzard's: half away from 0. [G] The
        -- screen is h.physicalScreen ({ width, height } in pixels), by default 768 high, so a unit at scale 1 is a
        -- pixel.
        PixelUtil = {
            GetNearestPixelSize = function(uiUnitSize, layoutScale, minPixels)
                if (uiUnitSize == 0) and (not minPixels or (minPixels == 0)) then
                    return 0
                end

                local factor = (768 / h.physicalScreen[2])
                local exact = ((uiUnitSize * layoutScale) / factor)
                local pixels = (((exact < 0) and math.ceil(exact - 0.5)) or math.floor(exact + 0.5))

                if minPixels then
                    if uiUnitSize < 0 then
                        pixels = math.min(pixels, -minPixels)
                    else
                        pixels = math.max(pixels, minPixels)
                    end
                end

                return ((pixels * factor) / layoutScale)
            end,
        },
        -- [G] The client's high-resolution clock in milliseconds; the snapshot records only that it exists. It runs
        -- with GetTime, plus h.workTime: the milliseconds a test says the work in the current frame has taken, since
        -- GetTime holds still within a frame and this clock doesn't. debugprofilestart, which resets it for every
        -- addon, isn't faked.
        debugprofilestop = function() return ((h.time * 1000) + h.workTime) end,
        GetServerTime = function() return h.serverTime end,
        time = function(t) return ((t and EpochFromDate(t)) or h.serverTime) end,
        date = function(fmt, t)
            fmt = (fmt or "%c")

            if fmt:sub(1, 1) == "!" then fmt = fmt:sub(2) end

            return os.date("!" .. fmt, t or h.serverTime)
        end,
        InCombatLockdown = function() return h.lockdown end,
        IsLoggedIn = function() return h.loggedIn end,
        GetBuildInfo = function() return BuildVersion, BuildNumber, "Oct 1 2026", 16001 end,
        -- The harness is an enUS client: its GlobalStrings (world.lua) are the enUS ones. A test of another locale sets
        -- h.locale and rawsets the GlobalStrings it reads to that locale's.
        GetLocale = function() return h.locale end,

        -- Frames.
        CreateFrame = function(widgetType, name, parent, template)
            local frame = h:CreateWidget(widgetType, name, parent, template)

            if name then
                rawset(h.env, name, frame)
            end

            return frame
        end,
        CreateColor = Color,
        SlashCmdList = {},
        -- The chat frame's imported commands, each handler under its uppercased alias.
        hash_SlashCmdList = {},

        -- Units.
        UnitExists = function(u) return Field(u, "exists", false) end,
        UnitIsPlayer = function(u) return Field(u, "isPlayer", false) end,
        -- Hostility, death, combat, race, faction, GUIDs, and raid icons: units.lua.
        UnitIsFeignDeath = function(u) return Field(u, "feign", false) end,
        UnitIsAFK = function(u) return Field(u, "afk", false) end,
        UnitHealth = function(u) return Field(u, "health", 0) end,
        UnitHealthMax = function(u) return Field(u, "maxHealth", 0) end,
        -- [D] UnitHealthMax() - UnitHealth() (its doc string). Predicted healing isn't modeled, so usePredicted changes
        -- nothing.
        UnitHealthMissing = function(u) return (Field(u, "maxHealth", 0) - Field(u, "health", 0)) end,
        -- [D] "percent of health remaining", scaled by an optional curve. [G] Without a curve it's the 0-1 fraction
        -- (the client's CurveConstants offer ScaleTo100), and 0 for a unit without max health. Curves aren't modeled:
        -- passing one is a harness error.
        UnitHealthPercent = function(u, _, curve)
            assert(curve == nil, "UnitHealthPercent: the harness doesn't model curves")
            local max = Field(u, "maxHealth", 0)

            return (((max > 0) and (Field(u, "health", 0) / max)) or 0)
        end,
        UnitName = function(u)
            local unit = Unit(u)

            if unit then return unit.name, unit.surname end
        end,
        UnitNameUnmodified = function(u)
            local unit = Unit(u)

            if unit then return unit.name, unit.surname end
        end,
        -- [E] Forever's separator for "First Last" (names.player).
        Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } },
        RegionalUniqueNamesEnabled = function() return true end,
        UnitFullName = function(u)
            local unit = Unit(u)

            if unit then return unit.name, unit.surname end
        end,
        -- Group membership (group.lua).
        IsInGroup = function(category) return h:InGroupCategory(category) end,
        IsInRaid = function(category) return (h:InGroupCategory(category) and h:GroupIsRaid()) end,
        GetNumGroupMembers = function(category)
            return ((h:InGroupCategory(category) and (#h.group.members + 1)) or 0)
        end,
        -- A unit's classFile is its classFile field; className defaults to the class's enUS name.
        UnitClass = function(u)
            local unit = Unit(u)
            local classFile = (unit and unit.classFile)
            local class = Classes[classFile or ""]

            if class then return (unit.className or class[1]), classFile, class[2] end
        end,
        UnitLevel = function(u) return Field(u, "level", 0) end,
        GetPlayerInfoByGUID = function(guid)
            local unit = h.guidUnits[guid]

            if not unit or not unit.isPlayer or not unit.name then return end

            local class = Classes[unit.classFile or ""]
            local race = (unit.race and Harness.RACES[unit.race])
            local realm = ((((unit.realm == nil) or (unit.realm == h.player.realm)) and "") or unit.realm)

            return (class and (unit.className or class[1])), unit.classFile, race, unit.race, (unit.sex or 2),
                Harness.DisplayName(unit), realm
        end,
        UnitIsBossMob = function(u)
            local unit = Unit(u)

            return ((unit ~= nil) and (unit.boss == true))
        end,
        UnitClassification = function(u)
            local unit = Unit(u)

            if unit then return (unit.classification or "normal") end
        end,
        UnitXP = function(u) return (((u == "player") and h.player.xp) or 0) end,
        UnitXPMax = function(u) return (((u == "player") and h.player.xpMax) or 0) end,
        GetXPExhaustion = function() return (((h.player.rested > 0) and h.player.rested) or nil) end,
        GetMaxPlayerLevel = function() return h.maxLevel end,
        IsResting = function() return h.player.resting end,
        GetMoney = function() return h.player.money end,
        UnitPowerType = function(u)
            -- Every unit has a primary power type.
            local powerType = (Field(u, "powerType", 0) or 0)

            return powerType, (PowerTokens[powerType] or "MANA")
        end,
        UnitPower = function(u, powerType) return Power(u, "power", powerType) end,
        GetComboPoints = function(u, target)
            local unit = ((u == "player") and Unit(target))

            return ((unit and unit.comboPoints) or 0)
        end,
        UnitPowerMax = function(u, powerType) return Power(u, "powerMax", powerType) end,

        -- Zones.
        GetRealZoneText = function() return h.zone end,
        GetSubZoneText = function() return h.subZone end,

        -- Formatting.
        GetMoneyString = MoneyString,
        SecondsToTime = SecondsToTime,

        -- Spells.
        C_Spell = {
            GetSpellName = function(id) return h.spellNames[id] end,
            IsSpellUsable = function(name)
                local state = h.usable[name]

                if not state then return false, false end

                return state[1], state[2]
            end,
        },

        -- Timers, run by h:Advance.
        C_Timer = {
            After = function(seconds, callback)
                h:Schedule(seconds, callback)
            end,
            NewTicker = function(seconds, callback, iterations)
                local state = {}
                local handle = nil
                local remaining = iterations

                local function Tick()
                    if remaining then remaining = (remaining - 1) end

                    if not remaining or (remaining > 0) then
                        local nextEntry = h:Schedule(seconds, Tick)

                        state.current = nextEntry
                    end

                    callback(handle)
                end

                state.current = h:Schedule(seconds, Tick)

                handle = {
                    Cancel = function() state.cancelled = true; state.current.cancelled = true end,
                    IsCancelled = function() return (state.cancelled == true) end,
                }

                return handle
            end,
            NewTimer = function(seconds, callback)
                local handle
                local entry = h:Schedule(seconds, function() callback(handle) end)

                handle = Handle(entry)

                return handle
            end,
        },

        -- Sound.
        PlaySoundFile = function(path, channel)
            if not h.files[path] or h.mutedChannels[channel or "SFX"] then
                return false, nil
            end

            h.handles = (h.handles + 1)
            h.sounds[#h.sounds + 1] = { channel = channel, handle = h.handles, path = path }

            return true, h.handles
        end,
        C_UIFileAsset = { IsKnownFile = function(path) return (h.files[path] == true) end },
        PlaySound = PlayKit,
        C_Sound = { PlaySound = PlayKit },
        StopSound = function(handle, fade)
            h.stopped[#h.stopped + 1] = { fade = fade, handle = handle }
        end,
        SOUNDKIT = setmetatable({}, {
            __index = function(_, key) error("SOUNDKIT." .. tostring(key) .. " isn't modeled by the harness", 2) end,
        }),

        -- Override bindings, as Blizzard_GamepadSharedUtility's InputBindingStack uses them. [G] One binding per key,
        -- the last set: the harness doesn't model priority against Blizzard's own. Combat lockdown blocks both
        -- (secrets.lua's LockedUndocumented).
        ClearOverrideBindings = function(owner)
            for key, binding in pairs(h.overrideBindings) do
                if binding.owner == owner then
                    h.overrideBindings[key] = nil
                end
            end
        end,
        SetOverrideBindingClick = function(owner, isPriority, key, buttonName, mouseButton)
            h.overrideBindings[key] = { button = buttonName, mouseButton = mouseButton, owner = owner, priority = isPriority }
        end,

        -- Controller.
        C_GamePad = {
            ClearLedColor = function() h.led = nil end,
            GetActiveDeviceID = function() return ((h.labelStyle and 1) or 0) end,
            GetDeviceMappedState = function(id) return h:GamePadMappedState(id) end,
            -- [D] The device's Enum.GamePadPowerLevel (GamePadDocumentation; the ID is Nilable). [G] h.powerLevel for
            -- the connected controller, Unknown without one.
            GetPowerLevel = function()
                -- 5 is Enum.GamePadPowerLevel.Unknown.
                return ((h.labelStyle and h.powerLevel) or 5)
            end,
            SetLedColor = function(color) h.led = { color:GetRGB() } end,
            SetVibration = function(kind, intensity) h.vibrations[#h.vibrations + 1] = { kind, intensity } end,
            StopVibration = function() h.vibrationsStopped = (h.vibrationsStopped + 1) end,
        },

        -- [D] The interface style, an Enum.InputDeviceInterfaceType (InputInterfaceStyle docs). [G] h.interfaceStyle,
        -- mouse and keyboard unless a test sets it.
        C_InputInterfaceStyle = {
            GetCurrentStyle = function() return h.interfaceStyle end,
        },
        -- [D] Whether the last input came from a controller. [G] h.usingGamepad.
        IsUsingGamepad = function() return h.usingGamepad end,

        -- Addon metadata.
        C_AddOns = {
            GetAddOnMetadata = function(name, key)
                local addon = __addons[name]

                return (addon and addon.metadata[key])
            end,
        },

        -- The addon profiler and memory (Blizzard_AddOnList reads them). Metrics come from h.profiler: numbers keyed by
        -- Enum.AddOnProfilerMetric value, 0 when unset.
        C_AddOnProfiler = {
            GetAddOnMetric = function(name, metric) return ((h.profiler.addons[name] or {})[metric] or 0) end,
            GetApplicationMetric = function(metric) return (h.profiler.application[metric] or 0) end,
            GetOverallMetric = function(metric) return (h.profiler.overall[metric] or 0) end,
            IsEnabled = function() return h.profiler.enabled end,
        },
        UpdateAddOnMemoryUsage = function() h.memoryUpdates = (h.memoryUpdates + 1) end,
        GetAddOnMemoryUsage = function(name) return (h.profiler.memory[name] or 0) end,

        -- Addon messages (group.lua). The rest of C_ChatInfo is merged in below.
        C_ChatInfo = h:AddonMessageFakes(),

        -- Restrictions. IsAddOnRestrictionActive is false during ADDON_RESTRICTION_STATE_CHANGED (its doc).
        C_RestrictedActions = {
            IsAddOnRestrictionActive = function(kind)
                local name = Harness.RESTRICTIONS[(kind or -1) + 1]

                return ((name ~= nil) and (h.restrictionDispatch == 0) and (h.restrictions[name] == true))
            end,
        },
        C_SettingsUtil = {
            OpenSettingsPanel = function(categoryID) h.opened[#h.opened + 1] = categoryID end,
        },

        PowerBarColor = { ENERGY = { b = 0, g = 1, r = 1 } },
        LE_PARTY_CATEGORY_INSTANCE = Harness.PARTY_CATEGORY.INSTANCE,
    }

    -- math.random and random are Lua's until h:SeedRandom (see wow.lua).
    fakes.math.random = function(...) return h:Random(...) end
    fakes.random = fakes.math.random

    for key, value in pairs(Soundkits) do
        rawset(fakes.SOUNDKIT, key, value)
    end

    fakes.string.trim = Strtrim
    fakes.string.format = SecretFormat
    fakes.format = SecretFormat
    -- ("%d"):format(x) reaches format through the string metatable, not the env: route it too.
    local stringMethods = setmetatable({ format = SecretFormat }, { __index = string })

    getmetatable("").__index = stringMethods

    -- Enum, from the documented enumerations.
    fakes.Enum = {}

    for name, fields in pairs(Snapshot.enums) do
        local enum = {}

        for field, value in pairs(fields) do
            enum[field] = value
        end

        fakes.Enum[name] = enum
    end

    fakes.UIParent = h:CreateWidget("Frame", "UIParent")
    -- [G] The screen at UI scale 1: 768 high, whatever the resolution, and 16:9 wide. A test can change it
    -- (h.env.UIParent:SetSize).
    Harness.State(fakes.UIParent).width, Harness.State(fakes.UIParent).height = 1366, 768
    -- Blizzard's settings frame carries SettingsPanelMixin (Blizzard_SettingsPanel.lua). Addon code that opened it
    -- froze the client when it closed, so Open and OpenToCategory are forbidden (tools/api/forbidden.json). The player
    -- opens it from Esc > Options, so it starts hidden. [D] Blizzard_SettingsPanel.xml: the panel is 920 by 724, and
    -- its Container.SettingsCanvas fills the room right of the category list (199 wide at x 18, then 16 apart) to 22
    -- from the right edge, from 76 below the top to 47 above the bottom: 665 by 601. h:SelectSettingsCategory shows a
    -- canvas page there.
    fakes.SettingsPanel = h:CreateWidget("Frame", "SettingsPanel", fakes.UIParent)
    Harness.State(fakes.SettingsPanel).shown = false
    Harness.State(fakes.SettingsPanel).width, Harness.State(fakes.SettingsPanel).height = 920, 724
    fakes.SettingsPanel.Container = h:CreateWidget("Frame", nil, fakes.SettingsPanel)
    fakes.SettingsPanel.Container.SettingsCanvas = h:CreateWidget("Frame", nil, fakes.SettingsPanel.Container)
    Harness.State(fakes.SettingsPanel.Container.SettingsCanvas).width = 665
    Harness.State(fakes.SettingsPanel.Container.SettingsCanvas).height = 601

    fakes.SettingsPanel.Open = function()
        h:BlockAction("ADDON_ACTION_FORBIDDEN", "SettingsPanel:Open")
    end

    fakes.SettingsPanel.OpenToCategory = function()
        h:BlockAction("ADDON_ACTION_FORBIDDEN", "SettingsPanel:OpenToCategory")
    end

    -- units.lua, world.lua, input.lua, ui.lua, meter.lua, speech.lua, and quests.lua. A name defined twice is a harness
    -- bug.
    local sources = {
        h:UnitFakes(), h:WorldFakes(), h:ControllerUIFakes(), h:InterfaceFakes(fakes.UIParent), h:MeterFakes(), h:SpeechFakes(),
        h:QuestFakes(fakes.UIParent),
    }

    for _, more in ipairs(sources) do
        for name, value in pairs(more) do
            assert(fakes[name] == nil, "BuildEnvironment: fake " .. name .. " is defined twice")
            fakes[name] = value
        end
    end

    fakes._G = fakes

    -- Documented fakes follow their snapshot entry (secrets, secret arguments, restrictions).
    for name, value in pairs(fakes) do
        if type(value) == "function" then
            fakes[name] = h:WrapFunction(name, value)
        elseif (type(value) == "table") and name:match("^C_") then
            for member, fn in pairs(value) do
                value[member] = h:WrapFunction(name .. "." .. member, fn)
            end
        end
    end

    fakes.Settings = h:BuildSettings(fakes)

    return setmetatable(fakes, {
        __index = function(_, key)
            if h.declared[key] then
                return nil
            end

            error("read of undefined global " .. tostring(key), 2)
        end,
    })
end

-- Settings panel fake, after Blizzard_Settings_Shared (forever branch), for what the addons call:
-- - RegisterCanvasLayoutCategory(frame, name) returns a category whose page is the addon's own frame
--   (Blizzard shows it when the player selects the category: h:SelectSettingsCategory) and its layout.
-- - RegisterCanvasLayoutSubcategory(parentCategory, frame, name) does the same for a category listed
--   under parentCategory.
-- - RegisterAddOnCategory(category) lists it under Esc > Options > AddOns.
-- - OpenToCategory calls C_SettingsUtil.OpenSettingsPanel, as Blizzard_Settings.lua does, which
--   addon code must never call (tools/api/forbidden.json).
-- - The SettingsPanel global (a frame, see the env) refuses addon code's Open and OpenToCategory.
-- What tests read: h.categories (every category registered, { name, canvas, parent }, in order) and h.category (the
-- RegisterAddOnCategory argument).
function Harness:BuildSettings(env)
    local h = self

    local function Register(frame, name, parent)
        local id = (#h.categories + 1)
        local category = { canvas = frame, GetID = function() return id end, name = name, parent = parent }

        h.categories[id] = category

        return category, { frame = frame }
    end

    return {
        OpenToCategory = function(categoryID, scrollToElementName)
            env.C_SettingsUtil.OpenSettingsPanel(categoryID, scrollToElementName)
        end,
        RegisterAddOnCategory = function(category)
            h.category = category
        end,
        RegisterCanvasLayoutCategory = function(frame, name)
            return Register(frame, name, nil)
        end,
        RegisterCanvasLayoutSubcategory = function(parentCategory, frame, name)
            return Register(frame, name, parentCategory)
        end,
    }
end

-- How many timers (C_Timer callbacks and animation finishes) wait to run.
function Harness:PendingTimers()
    local count = 0

    for _, entry in ipairs(self.timers) do
        if not entry.cancelled then
            count = (count + 1)
        end
    end

    return count
end

-- The player selects a canvas category in Blizzard's settings panel, opening the panel if it's closed. [D]
-- SettingsPanelMixin:DisplayLayout's canvas branch (Blizzard_SettingsPanel.lua, forever): the shown canvas is cleared
-- (SetParent(nil), ClearAllPoints, Hide), then the category's frame is parented to Container.SettingsCanvas, fills it
-- (SetAllPoints), and shows.
function Harness:SelectSettingsCategory(category)
    local panel = self.env.SettingsPanel
    local settingsCanvas = panel.Container.SettingsCanvas
    local current = self.settingsCanvasFrame

    if current and (current ~= category.canvas) then
        current:SetParent(nil)
        current:ClearAllPoints()
        current:Hide()
    end

    self.settingsCanvasFrame = category.canvas
    panel:Show()
    category.canvas:SetParent(settingsCanvas)
    category.canvas:ClearAllPoints()
    category.canvas:SetAllPoints(settingsCanvas)
    category.canvas:Show()
end

-- Tables whose functions are Lua's own library: the runner doesn't ask whether an addon calls them.
local LuaLibraries = { _G = true, math = true, string = true, table = true }

-- Every fake that's a function ("Name", or "Table.member" at any depth), for the test runner's check that an addon
-- calls each one. Lua's functions (Harness.LUA_FAKES, Lua's libraries) and widgets' methods aren't listed.
function Harness.FakeFunctionNames()
    local h = Harness.New()

    Harness.created = {}
    local names = {}
    local seen = {}

    -- The functions in a plain table, nested tables included (each table once; widgets aside).
    local function Walk(path, t)
        if seen[t] or Harness.State(t) then
            return
        end

        seen[t] = true

        for member, value in pairs(t) do
            if type(member) == "string" then
                if type(value) == "function" then
                    names[#names + 1] = (path .. "." .. member)
                elseif type(value) == "table" then
                    Walk(path .. "." .. member, value)
                end
            end
        end
    end

    for name, value in pairs(h.env) do
        if (type(value) == "function") and not Harness.LUA_FAKES[name] then
            names[#names + 1] = name
        elseif (type(value) == "table") and not LuaLibraries[name] and (name ~= "_G") then
            Walk(name, value)
        end
    end

    table.sort(names)

    return table.concat(names, "\n")
end
