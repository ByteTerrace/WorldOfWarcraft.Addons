-- The global environment an addon sees inside the harness: fakes for the WoW API it uses,
-- backed by the Harness world state (see wow.lua). Functions the API snapshot flags as
-- returning secrets are wrapped so their results are secret while the player is in combat.

local SNAPSHOT = __snapshot

local function Unit(h, token)
    if token == "player" then
        return h.player
    elseif token == "target" then
        return h.target
    end
end

local function field(h, token, name, default)
    local unit = Unit(h, token)
    if unit == nil then
        return default
    end
    return unit[name]
end

local function Color(r, g, b, a)
    return {
        r = r, g = g, b = b, a = a or 1,
        GetRGB = function(self) return self.r, self.g, self.b end,
        GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
    }
end

function Harness:BuildEnvironment()
    local h = self
    local fakes = {
        -- Lua and WoW string/table extensions.
        assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall,
        select = select, setmetatable = setmetatable, getmetatable = getmetatable, tonumber = tonumber,
        tostring = tostring, type = type, unpack = unpack, rawget = rawget, rawset = rawset,
        math = math, string = string, table = table,
        format = string.format, tinsert = table.insert, tremove = table.remove, wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
        strsplit = function(delimiter, s, limit)
            local parts, start = {}, 1
            while true do
                if limit and #parts == limit - 1 then break end
                local i, j = s:find(delimiter, start, true)
                if not i then break end
                parts[#parts + 1] = s:sub(start, i - 1)
                start = j + 1
            end
            parts[#parts + 1] = s:sub(start)
            return unpack(parts)
        end,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            h.printed[#h.printed + 1] = table.concat(parts, " ")
        end,

        issecretvalue = function(value) return Reveal(value) ~= value end,
        geterrorhandler = function()
            return function(message) h.errors[#h.errors + 1] = tostring(message) end
        end,
        GetTime = function() return h.time end,
        InCombatLockdown = function() return h.lockdown end,
        GetBuildInfo = function() return "1.60.1", "test", "", 16001 end,

        -- Frames.
        CreateFrame = function(widgetType, name, parent, template)
            local frame = h:CreateWidget(widgetType, name, parent, template)
            if name then
                h.env[name] = frame
            end
            return frame
        end,
        CreateColor = Color,
        SlashCmdList = {},

        -- Units.
        UnitExists = function(u) return field(h, u, "exists", false) end,
        UnitIsPlayer = function(u) return field(h, u, "isPlayer", false) end,
        UnitCanAttack = function(_, u) return field(h, u, "canAttack", false) end,
        UnitIsDead = function(u) return field(h, u, "dead", false) end,
        UnitIsDeadOrGhost = function(u) return field(h, u, "dead", false) end,
        UnitIsFeignDeath = function(u) return field(h, u, "feign", false) end,
        UnitIsAFK = function(u) return field(h, u, "afk", false) end,
        UnitAffectingCombat = function(u) return u == "player" and h.inCombat end,
        UnitHealth = function(u) return field(h, u, "health", 0) end,
        UnitHealthMax = function(u) return field(h, u, "maxHealth", 0) end,
        UnitClass = function(u)
            local class = field(h, u, "class")
            return class, class, 1
        end,
        UnitPowerType = function(u)
            local powerType = field(h, u, "powerType", 0)
            return powerType, powerType == 3 and "ENERGY" or "MANA"
        end,
        UnitPower = function(u, powerType) return Unit(h, u).power[powerType] or 0 end,
        UnitPowerMax = function(u, powerType) return Unit(h, u).powerMax[powerType] or 0 end,

        -- Spells.
        C_Spell = {
            GetSpellName = function(id) return h.spellNames[id] end,
            IsSpellUsable = function(name)
                local state = h.usable[name]
                if not state then return false, false end
                return state[1], state[2]
            end,
        },

        -- Sound.
        PlaySoundFile = function(path, channel)
            if not h.files[path] then
                return false, nil
            end
            h.handles = h.handles + 1
            h.sounds[#h.sounds + 1] = { path = path, channel = channel, handle = h.handles }
            return true, h.handles
        end,
        StopSound = function(handle, fade)
            h.stopped[#h.stopped + 1] = { handle = handle, fade = fade }
        end,

        -- Controller.
        C_GamePad = {
            SetLedColor = function(color) h.led = { color:GetRGB() } end,
            ClearLedColor = function() h.led = nil end,
            SetVibration = function(kind, intensity) h.vibrations[#h.vibrations + 1] = { kind, intensity } end,
            StopVibration = function() end,
            GetActiveDeviceID = function() return h.labelStyle and 1 or 0 end,
            GetDeviceMappedState = function(id)
                if id == 1 and h.labelStyle then
                    return { name = "Test Controller", labelStyle = h.labelStyle }
                end
            end,
        },

        -- Addon metadata.
        C_AddOns = {
            GetAddOnMetadata = function(name, key)
                local addon = __addons[name]
                return addon and addon.metadata[key]
            end,
        },

        Enum = { PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 } },
        PowerBarColor = { ENERGY = { r = 1, g = 1, b = 0 } },
        Settings = h:BuildSettings(),
    }
    fakes.UIParent = h:CreateWidget("Frame", "UIParent")
    fakes._G = fakes

    -- Secret wrapping driven by Blizzard's documentation flags.
    local function WrapSecret(name, fn)
        local flags = SNAPSHOT.functions[name]
        if not flags or flags == 0 then
            return fn
        end
        return function(...)
            if not h.inCombat then
                return fn(...)
            end
            local results = { fn(...) }
            for i = 1, #results do
                results[i] = Secret(results[i])
            end
            return unpack(results)
        end
    end
    for name, fn in pairs(fakes) do
        if type(fn) == "function" then
            fakes[name] = WrapSecret(name, fn)
        elseif type(fn) == "table" and name:match("^C_") then
            for member, memberFn in pairs(fn) do
                fn[member] = WrapSecret(name .. "." .. member, memberFn)
            end
        end
    end

    return setmetatable(fakes, {
        __index = function(_, key)
            if h.declared[key] then
                return nil
            end
            error("read of undefined global " .. tostring(key), 2)
        end,
    })
end

-- Settings panel fake: stores into the variable table like SettingsInbound.CreateAddOnSetting.
function Harness:BuildSettings()
    local h = self
    local nextID = 0
    return {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            nextID = nextID + 1
            local id = nextID
            return { name = name, GetID = function() return id end }
        end,
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
        CreateCheckbox = function(category, setting, tooltip) setting.control = "checkbox"; setting.tooltip = tooltip end,
        CreateDropdown = function(category, setting, options, tooltip)
            setting.control = "dropdown"; setting.options = options; setting.tooltip = tooltip
        end,
        CreateControlTextContainer = function()
            local data = {}
            return {
                Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
                GetData = function() return data end,
            }
        end,
        RegisterAddOnCategory = function(category) h.category = category end,
        OpenToCategory = function(id) h.opened[#h.opened + 1] = id end,
    }
end
