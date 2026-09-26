-- The global environment an addon sees inside the harness: fakes for the WoW API it uses,
-- backed by the Harness world state (see wow.lua). Every fake names a real global (the test
-- runner checks each against the client dump); every global and C_* fake is wrapped by
-- Harness:WrapFunction, so secret returns, secret arguments and restrictions follow its snapshot
-- entry, and an undocumented one (PlaySoundFile, PlaySound, StopSound) refuses secret arguments.
--
-- Formatting helpers (GetMoneyString, SecondsToTime) are deterministic stand-ins, not
-- Blizzard's exact output (no coin textures, English unit names). date() and time() run in UTC.
--
-- Names [E]: Forever's names are regionally unique "First Last". UnitName, UnitNameUnmodified and
-- UnitFullName return (first, surname) for a player and (name, nil) for an NPC; no realm.
-- GetPlayerInfoByGUID's name is "First Last" with realm "" on your realm. Ambiguate follows the
-- documented context table (all, guild, mail, none, short, craftingorder). The harness has no
-- guild roster, so no name counts as a guildmate: "all" and "guild" act like "none", dropping the
-- realm only for the player's own realm.

local Snapshot = __snapshot

local function Color(r, g, b, a)
    return {
        r = r, g = g, b = b, a = a or 1,
        GetRGB = function(self) return self.r, self.g, self.b end,
        GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
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
    WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
    PRIEST = { "Priest", 5 }, DEATHKNIGHT = { "Death Knight", 6 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 },
    WARLOCK = { "Warlock", 9 }, MONK = { "Monk", 10 }, DRUID = { "Druid", 11 }, DEMONHUNTER = { "Demon Hunter", 12 },
    EVOKER = { "Evoker", 13 },
}

-- A few real SOUNDKIT entries (Blizzard_SharedXML/Mainline/SoundKitConstants.lua). Reading any
-- other key is an error: add it here, with its real value, when an addon needs it.
local Soundkits = {
    IG_SPELLBOOK_OPEN = 829, IG_QUEST_LOG_OPEN = 844, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
    IG_QUEST_LIST_COMPLETE = 878, RAID_WARNING = 8959, READY_CHECK = 8960, LFG_REWARDS = 17316,
    UI_EPICLOOT_TOAST = 31578,
}

-- Lua libraries, limited to the members the client has (it removes some, e.g. string.dump).
local Libraries = {
    math = { "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor", "fmod", "frexp",
        "huge", "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow", "rad", "random", "sin", "sinh", "sqrt", "tan", "tanh" },
    string = { "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper" },
    table = { "concat", "insert", "maxn", "remove", "sort" },
}

local function Refuse(name, ...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then
            error(name .. ": argument #" .. i .. " is a secret value", 3)
        end
    end
end

local function Library(name)
    local lib = {}
    for _, member in ipairs(Libraries[name]) do
        lib[member] = _G[name][member]
    end
    return lib
end

-- WoW's strsplit: every character of delimiter separates (a set, not a sequence).
local function Strsplit(delimiter, s, limit)
    local set = "[" .. delimiter:gsub("[%]%[%^%-%%]", "%%%0") .. "]"
    local parts, start = {}, 1
    while not limit or #parts < limit - 1 do
        local i = s:find(set, start)
        if not i then break end
        parts[#parts + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    parts[#parts + 1] = s:sub(start)
    return unpack(parts)
end

local function Strtrim(s, chars)
    local set = chars and ("[" .. chars:gsub("[%]%[%^%-%%]", "%%%0") .. "]") or "%s"
    return (s:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
end

-- Seconds since the epoch for a UTC date table (time{...} in the harness's UTC world).
local function EpochFromDate(t)
    local year, month = t.year, t.month
    if month <= 2 then year, month = year - 1, month + 12 end
    local era = math.floor(year / 400)
    local yoe = year - era * 400
    local doy = math.floor((153 * (month - 3) + 2) / 5) + t.day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468
    return days * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
end

local function MoneyString(money)
    local gold, silver, copper = math.floor(money / 10000), math.floor(money / 100) % 100, money % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. "c" end
    return table.concat(parts, " ")
end

local TimeUnits = {
    { 86400, "Day", "Day", "Days" }, { 3600, "Hr", "Hour", "Hours" }, { 60, "Min", "Minute", "Minutes" },
    { 1, "Sec", "Second", "Seconds" },
}

local function SecondsToTime(seconds, noSeconds, notAbbreviated, maxCount)
    maxCount = maxCount or 2
    seconds = math.floor(seconds)
    local parts = {}
    for i, unit in ipairs(TimeUnits) do
        local isSeconds = i == #TimeUnits
        local count = math.floor(seconds / unit[1])
        if count > 0 and #parts < maxCount and not (isSeconds and noSeconds) then
            local label = notAbbreviated and (count == 1 and unit[3] or unit[4]) or unit[2]
            parts[#parts + 1] = count .. " " .. label
            seconds = seconds - count * unit[1]
        end
    end
    return table.concat(parts, " ")
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
    local function Handle(entry)
        local handle = {}
        function handle.Cancel() entry.cancelled = true end
        function handle.IsCancelled() return entry.cancelled == true end
        return handle
    end
    local function PlayKit(kit, channel)
        assert(type(kit) == "number", "PlaySound: soundKitID must be a number, got " .. type(kit))
        h.handles = h.handles + 1
        h.soundKits[#h.soundKits + 1] = { kit = kit, channel = channel or "SFX", handle = h.handles }
        return true, h.handles
    end

    local fakes = {
        -- Lua, as the client exposes it. type() reports a secret's underlying type, like the
        -- client; tostring, tonumber, print and string.format refuse secrets.
        assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall,
        select = select, setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
        rawequal = rawequal, unpack = unpack,
        -- WoW's xpcall passes extra arguments to the function (Lua 5.1's doesn't).
        xpcall = function(fn, handler, ...)
            local args, count = { ... }, select("#", ...)
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
        strtrim = Strtrim, strsplit = Strsplit, strjoin = function(sep, ...) return table.concat({ ... }, sep) end,
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
        GetServerTime = function() return h.serverTime end,
        time = function(t) return t and EpochFromDate(t) or h.serverTime end,
        date = function(fmt, t)
            fmt = fmt or "%c"
            if fmt:sub(1, 1) == "!" then fmt = fmt:sub(2) end
            return os.date("!" .. fmt, t or h.serverTime)
        end,
        InCombatLockdown = function() return h.lockdown end,
        IsLoggedIn = function() return h.loggedIn end,
        GetBuildInfo = function() return "1.60.1", "70009", "Sep 22 2025", 16001 end,
        -- The harness is an enUS client: its GlobalStrings (world.lua) are the enUS ones.
        GetLocale = function() return "enUS" end,

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
        hash_SlashCmdList = {}, -- the chat frame's imported commands, [uppercased alias] = handler

        -- Units.
        UnitExists = function(u) return Field(u, "exists", false) end,
        UnitIsPlayer = function(u) return Field(u, "isPlayer", false) end,
        -- Hostility, death, combat, race, faction, GUIDs and raid icons: units.lua.
        UnitIsFeignDeath = function(u) return Field(u, "feign", false) end,
        UnitIsAFK = function(u) return Field(u, "afk", false) end,
        UnitHealth = function(u) return Field(u, "health", 0) end,
        UnitHealthMax = function(u) return Field(u, "maxHealth", 0) end,
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
        -- Group membership (group.lua). UnitInParty is true for the player in any group and for
        -- the members of their party (in a raid, their subgroup); UnitInRaid is a raid member's
        -- raid index.
        IsInGroup = function(category) return h:InGroupCategory(category) end,
        IsInRaid = function(category) return h:InGroupCategory(category) and h:GroupIsRaid() end,
        GetNumGroupMembers = function(category)
            return h:InGroupCategory(category) and #h.group.members + 1 or 0
        end,
        UnitInParty = function(u)
            local unit = Unit(u)
            if not unit or not h.group.kind then return false end
            if unit == h.player then return true end
            for _, member in ipairs(h.group.members) do
                if member == unit then return not h:GroupIsRaid() or member.partyUnit ~= nil end
            end
            return false
        end,
        UnitInRaid = function(u)
            local unit = Unit(u)
            if not unit or not h:GroupIsRaid() then return nil end
            if unit == h.player then return #h.group.members + 1 end
            for i, member in ipairs(h.group.members) do
                if member == unit then return i end
            end
            return nil
        end,
        Ambiguate = function(name, context)
            local short, realm = name:match("^([^%-]+)%-(.+)$")
            if not short then return name end
            if context == "short" then return short end
            if context == "mail" or context == "craftingorder" then return name end
            if context == "none" or context == "all" or context == "guild" then
                return realm == Harness.NormalizeRealm(h.player.realm) and short or name
            end
            error("Ambiguate: unknown context " .. tostring(context), 3)
        end,
        -- A unit's classFile is its classFile field; className defaults to
        -- the class's enUS name.
        UnitClass = function(u)
            local unit = Unit(u)
            local classFile = unit and unit.classFile
            local class = Classes[classFile or ""]
            if class then return unit.className or class[1], classFile, class[2] end
        end,
        UnitLevel = function(u) return Field(u, "level", 0) end,
        GetPlayerInfoByGUID = function(guid)
            local unit = h.guidUnits[guid]
            if not unit or not unit.isPlayer or not unit.name then return end
            local class, race = Classes[unit.classFile or ""], unit.race and Harness.RACES[unit.race]
            local realm = (unit.realm == nil or unit.realm == h.player.realm) and "" or unit.realm
            return class and (unit.className or class[1]), unit.classFile, race and race[1], unit.race, unit.sex or 2,
                Harness.DisplayName(unit), realm
        end,
        UnitIsBossMob = function(u)
            local unit = Unit(u)
            return unit ~= nil and unit.boss == true
        end,
        UnitClassification = function(u)
            local unit = Unit(u)
            if unit then return unit.classification or "normal" end
        end,
        UnitXP = function(u) return u == "player" and h.player.xp or 0 end,
        UnitXPMax = function(u) return u == "player" and h.player.xpMax or 0 end,
        GetXPExhaustion = function() return h.player.rested > 0 and h.player.rested or nil end,
        GetMaxPlayerLevel = function() return h.maxLevel end,
        IsResting = function() return h.player.resting end,
        GetMoney = function() return h.player.money end,
        UnitPowerType = function(u)
            local powerType = Field(u, "powerType", 0) or 0 -- every unit has a primary power type
            return powerType, PowerTokens[powerType] or "MANA"
        end,
        UnitPower = function(u, powerType)
            local unit = Unit(u)
            if not unit then return 0 end
            return (unit.power or {})[powerType or unit.powerType or 0] or 0 -- a unit without power has none
        end,
        GetComboPoints = function(u, target)
            local unit = u == "player" and Unit(target)
            return unit and unit.comboPoints or 0
        end,
        UnitPowerMax = function(u, powerType)
            local unit = Unit(u)
            if not unit then return 0 end
            return (unit.powerMax or {})[powerType or unit.powerType or 0] or 0
        end,

        -- Zones.
        GetZoneText = function() return h.zone end,
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
            NewTimer = function(seconds, callback)
                local handle
                local entry = h:Schedule(seconds, function() callback(handle) end)
                handle = Handle(entry)
                return handle
            end,
            NewTicker = function(seconds, callback, iterations)
                local state, handle = {}, nil
                local remaining = iterations
                local function Tick()
                    if remaining then remaining = remaining - 1 end
                    if not remaining or remaining > 0 then
                        local nextEntry = h:Schedule(seconds, Tick)
                        state.current = nextEntry
                    end
                    callback(handle)
                end
                state.current = h:Schedule(seconds, Tick)
                handle = {
                    Cancel = function() state.cancelled = true; state.current.cancelled = true end,
                    IsCancelled = function() return state.cancelled == true end,
                }
                return handle
            end,
        },

        -- Sound.
        PlaySoundFile = function(path, channel)
            if not h.files[path] or h.mutedChannels[channel or "SFX"] then
                return false, nil
            end
            h.handles = h.handles + 1
            h.sounds[#h.sounds + 1] = { path = path, channel = channel, handle = h.handles }
            return true, h.handles
        end,
        C_UIFileAsset = { IsKnownFile = function(path) return h.files[path] == true end },
        PlaySound = PlayKit,
        C_Sound = { PlaySound = PlayKit },
        StopSound = function(handle, fade)
            h.stopped[#h.stopped + 1] = { handle = handle, fade = fade }
        end,
        SOUNDKIT = setmetatable({}, {
            __index = function(_, key) error("SOUNDKIT." .. tostring(key) .. " isn't modeled by the harness", 2) end,
        }),

        -- Controller.
        C_GamePad = {
            SetLedColor = function(color) h.led = { color:GetRGB() } end,
            ClearLedColor = function() h.led = nil end,
            SetVibration = function(kind, intensity) h.vibrations[#h.vibrations + 1] = { kind, intensity } end,
            StopVibration = function() h.vibrationsStopped = h.vibrationsStopped + 1 end,
            GetActiveDeviceID = function() return h.labelStyle and 1 or 0 end,
            GetDeviceMappedState = function(id) return h:GamePadMappedState(id) end,
        },

        -- Addon metadata.
        C_AddOns = {
            GetAddOnMetadata = function(name, key)
                local addon = __addons[name]
                return addon and addon.metadata[key]
            end,
        },

        -- The addon profiler and memory (Blizzard_AddOnList reads them). Metrics come from
        -- h.profiler: numbers keyed by Enum.AddOnProfilerMetric value, 0 when unset.
        C_AddOnProfiler = {
            IsEnabled = function() return h.profiler.enabled end,
            GetAddOnMetric = function(name, metric) return (h.profiler.addons[name] or {})[metric] or 0 end,
            GetApplicationMetric = function(metric) return h.profiler.application[metric] or 0 end,
            GetOverallMetric = function(metric) return h.profiler.overall[metric] or 0 end,
        },
        UpdateAddOnMemoryUsage = function() h.memoryUpdates = h.memoryUpdates + 1 end,
        GetAddOnMemoryUsage = function(name) return h.profiler.memory[name] or 0 end,

        -- Addon messages (group.lua); the rest of C_ChatInfo is merged in below.
        C_ChatInfo = h:AddonMessageFakes(),

        -- Restrictions.
        -- IsAddOnRestrictionActive is false during ADDON_RESTRICTION_STATE_CHANGED (its doc).
        C_RestrictedActions = {
            IsAddOnRestrictionActive = function(kind)
                local name = Harness.RESTRICTIONS[(kind or -1) + 1]
                return name ~= nil and h.restrictionDispatch == 0 and h.restrictions[name] == true
            end,
            GetAddOnRestrictionState = function(kind)
                local name = Harness.RESTRICTIONS[(kind or -1) + 1]
                return name and h:RestrictionState(name) or 0
            end,
        },
        C_SettingsUtil = {
            OpenSettingsPanel = function(categoryID) h.opened[#h.opened + 1] = categoryID end,
        },

        PowerBarColor = { ENERGY = { r = 1, g = 1, b = 0 } },
        LE_PARTY_CATEGORY_HOME = Harness.PARTY_CATEGORY.HOME,
        LE_PARTY_CATEGORY_INSTANCE = Harness.PARTY_CATEGORY.INSTANCE,
    }
    -- math.random and random are Lua's until h:SeedRandom (see wow.lua).
    fakes.math.random = function(...) return h:Random(...) end
    fakes.random = fakes.math.random
    for key, value in pairs(Soundkits) do
        rawset(fakes.SOUNDKIT, key, value)
    end
    fakes.string.trim, fakes.string.split, fakes.string.join = Strtrim, Strsplit, fakes.strjoin
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
    -- Blizzard's settings frame carries SettingsPanelMixin (Blizzard_SettingsPanel.lua). Addon code
    -- that opened it froze the client when it closed, so Open and OpenToCategory are forbidden
    -- (tools/api/forbidden.json); the player opens it from Esc > Options.
    fakes.SettingsPanel = h:CreateWidget("Frame", "SettingsPanel", fakes.UIParent)
    fakes.SettingsPanel.Open = function()
        h:BlockAction("ADDON_ACTION_FORBIDDEN", "SettingsPanel:Open")
    end
    fakes.SettingsPanel.OpenToCategory = function()
        h:BlockAction("ADDON_ACTION_FORBIDDEN", "SettingsPanel:OpenToCategory")
    end
    -- units.lua, world.lua, ui.lua, meter.lua and speech.lua; a name defined twice is a harness bug.
    local sources = {
        h:UnitFakes(), h:WorldFakes(fakes.UIParent), h:InterfaceFakes(fakes.UIParent), h:MeterFakes(), h:SpeechFakes(),
    }
    for _, more in ipairs(sources) do
        for name, value in pairs(more) do
            assert(fakes[name] == nil, "BuildEnvironment: fake " .. name .. " is defined twice")
            fakes[name] = value
        end
    end
    fakes.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
    fakes._G = fakes

    -- Documented fakes follow their snapshot entry (secrets, secret arguments, restrictions).
    for name, value in pairs(fakes) do
        if type(value) == "function" then
            fakes[name] = h:WrapFunction(name, value)
        elseif type(value) == "table" and name:match("^C_") then
            for member, fn in pairs(value) do
                value[member] = h:WrapFunction(name .. "." .. member, fn)
            end
        end
    end
    local header
    fakes.Settings, header = h:BuildSettings(fakes)
    fakes.CreateSettingsListSectionHeaderInitializer = h:WrapFunction("CreateSettingsListSectionHeaderInitializer", header)

    return setmetatable(fakes, {
        __index = function(_, key)
            if h.declared[key] then
                return nil
            end
            error("read of undefined global " .. tostring(key), 2)
        end,
    })
end

-- Settings panel fake, after Blizzard_Settings_Shared (forever branch):
-- - RegisterVerticalLayoutCategory(name) and RegisterVerticalLayoutSubcategory(parent, name) return a
--   category and its vertical layout; layout:AddInitializer appends to the page in order.
-- - CreateCheckbox / CreateDropdown / CreateSlider add their control's initializer to the
--   category's own layout (SettingsPanel:GetLayout(category)), so a category must have one.
-- - CreateSettingsListSectionHeaderInitializer (a global) wraps Settings.CreateElementInitializer
--   with "SettingsListSectionHeaderTemplate".
-- - RegisterAddOnSetting stores into the variable table like SettingsInbound.CreateAddOnSetting.
-- - OpenToCategory calls C_SettingsUtil.OpenSettingsPanel, as Blizzard_Settings.lua does, which
--   addon code must never call (tools/api/forbidden.json).
-- - The SettingsPanel global (a frame, see the env) refuses addon code's Open and OpenToCategory.
-- What tests read: h.settings[variable] (with control, options and tooltip once a control is made),
-- h.settingsOrder (proxy settings in registration order), h.category (the RegisterAddOnCategory
-- argument) and h.settingsPages, each { name, parent (the parent page's name, or nil),
-- entries = { { header = text } or { variable = setting variable }, ... } } in registration order.
-- Returns the Settings table and the header initializer global.
function Harness:BuildSettings(env)
    local h = self
    local nextID = 0
    local layouts = {} -- [category] = layout

    local function NewInitializer(template, data)
        return { template = template, data = data, GetData = function(self) return self.data end }
    end

    local function RegisterCategory(name, parent)
        nextID = nextID + 1
        local id = nextID
        local category = { name = name, parent = parent, GetID = function() return id end }
        local page = { name = name, parent = parent and parent.name or nil, entries = {} }
        h.settingsPages[#h.settingsPages + 1] = page
        local layout = { initializers = {} }
        function layout:AddInitializer(initializer)
            self.initializers[#self.initializers + 1] = initializer
            local data = initializer:GetData()
            if initializer.template == "SettingsListSectionHeaderTemplate" then
                page.entries[#page.entries + 1] = { header = data.name }
            elseif data.setting then
                page.entries[#page.entries + 1] = { variable = data.setting.variable }
            end
            return initializer
        end
        layouts[category] = layout
        return category, layout
    end

    local function AddControl(control, template, category, setting, options, tooltip)
        local layout = layouts[category]
        assert(layout, "Settings.Create" .. control .. ": the category has no layout")
        setting.control, setting.options, setting.tooltip = control:lower(), options, tooltip
        local initializer = NewInitializer(template, { setting = setting, options = options, tooltip = tooltip })
        return layout:AddInitializer(initializer)
    end

    local settings
    settings = {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            return RegisterCategory(name, nil)
        end,
        -- A canvas page: the addon's own frame shown as the category's content (Blizzard shows it
        -- when the player chooses the category; tests show it directly).
        RegisterCanvasLayoutCategory = function(frame, name)
            local category = RegisterCategory(name, nil)
            category.canvas = frame
            layouts[category] = nil
            h.settingsPages[#h.settingsPages].canvas = frame
            return category, { frame = frame }
        end,
        RegisterVerticalLayoutSubcategory = function(parentCategory, name)
            assert(layouts[parentCategory], "RegisterVerticalLayoutSubcategory: unknown parent category")
            return RegisterCategory(name, parentCategory)
        end,
        CreateElementInitializer = NewInitializer,
        RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
            assert(type(default) == varType, ("setting %s: default is %s, declared %s"):format(variable, type(default), varType))
            assert(h.settings[variable] == nil, "duplicate setting variable " .. variable)
            local setting = { variable = variable, key = key, name = name, default = default, category = category }
            function setting:GetValue() return tbl[key] end
            function setting:SetValue(value)
                tbl[key] = value
                if self.callback then self.callback(self, value) end
            end
            function setting:SetValueChangedCallback(fn) self.callback = fn end
            h.settings[variable] = setting
            return setting
        end,
        RegisterProxySetting = function(category, variable, varType, name, default, getValue, setValue)
            assert(layouts[category], "RegisterProxySetting: unknown category")
            assert(type(default) == varType, ("setting %s: default is %s, declared %s"):format(variable, type(default), varType))
            assert(h.settings[variable] == nil, "duplicate setting variable " .. variable)
            local setting = { variable = variable, name = name, default = default, category = category }
            function setting:GetValue() return getValue() end
            function setting:SetValue(value) setValue(value) end
            h.settings[variable] = setting
            h.settingsOrder = h.settingsOrder or {}
            h.settingsOrder[#h.settingsOrder + 1] = variable
            return setting
        end,
        CreateCheckbox = function(category, setting, tooltip)
            return AddControl("Checkbox", "SettingsCheckboxControlTemplate", category, setting, nil, tooltip)
        end,
        CreateDropdown = function(category, setting, options, tooltip)
            return AddControl("Dropdown", "SettingsDropdownControlTemplate", category, setting, options(), tooltip)
        end,
        CreateSliderOptions = function(minValue, maxValue, rate)
            return {
                minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate,
                SetLabelFormatter = function(self, label, formatter) self.label, self.formatter = label, formatter end,
            }
        end,
        CreateSlider = function(category, setting, options, tooltip)
            return AddControl("Slider", "SettingsSliderControlTemplate", category, setting, options, tooltip)
        end,
        NotifyUpdate = function(variable)
            h.notified[variable] = (h.notified[variable] or 0) + 1
        end,
        CreateControlTextContainer = function()
            local data = {}
            return {
                Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
                GetData = function() return data end,
            }
        end,
        RegisterAddOnCategory = function(category)
            assert(category.parent == nil, "RegisterAddOnCategory: a subcategory is listed under its parent already")
            h.category = category
        end,
        OpenToCategory = function(categoryID, scrollToElementName)
            env.C_SettingsUtil.OpenSettingsPanel(categoryID, scrollToElementName)
        end,
    }
    local function CreateSettingsListSectionHeaderInitializer(name, tooltip, newTagID)
        local data = { name = name, tooltip = tooltip, newTagID = newTagID }
        return settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", data)
    end
    return settings, CreateSettingsListSectionHeaderInitializer
end

-- Every fake's name ("Name" or "Table.member"), for the test runner's check that each one exists
-- in the client dump. Tables whose members are data (Enum values, SOUNDKIT) list one level.
function Harness.FakeNames()
    local h = Harness.New()
    Harness.created = {}
    local names = {}
    for name, value in pairs(h.env) do
        names[#names + 1] = name
        if type(value) == "table" and name ~= "_G" and not Harness.State(value) then
            for member in pairs(value) do
                if type(member) == "string" then
                    names[#names + 1] = name .. "." .. member
                end
            end
        end
    end
    table.sort(names)
    return table.concat(names, "\n")
end
