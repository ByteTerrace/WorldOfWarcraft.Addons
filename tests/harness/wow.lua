-- A fake WoW: Forever client for behavioral tests, run in real Lua 5.1.
--
-- Fidelity rules, each enforced so a test fails where the client would:
--   * Secret values: in combat, every function the API snapshot flags as returning secrets
--     returns an opaque value that throws on comparison, arithmetic, concatenation and length.
--     Widgets accept them; tests read them back with Reveal(). (Lua 5.1 can't intercept a
--     boolean test of a table, so that one misuse isn't caught.)
--   * Only real API: registering an event, or calling a widget method, that the snapshot
--     doesn't list is an error. Reading an undefined global is an error unless the TOC
--     declares it as SavedVariables.
--   * InCombatLockdown() is still false while PLAYER_REGEN_DISABLED handlers run.
--   * Every widget method call is counted, so tests can assert work per event.
--
-- Usage (see tests/*.test.lua):
--   local h = Harness.new({ class = "ROGUE" })
--   h:LoadAddon("TheLanKrewToolKit")
--   h:EnterCombat()

local SNAPSHOT = __snapshot -- set by tools/verbs/test.mjs: { functions, events, methods }
local ADDONS = __addons     -- set by tools/verbs/test.mjs: { [name] = { files, sources, metadata } }

-- JS arrays arrive 0-based; make them Lua sequences.
local function Sequence(t)
    if t[0] == nil then
        return t
    end
    local out, i = {}, 0
    while t[i] ~= nil do
        out[i + 1] = t[i]
        i = i + 1
    end
    return out
end
for _, addon in pairs(ADDONS) do
    addon.files, addon.sources, addon.savedVariables = Sequence(addon.files), Sequence(addon.sources), Sequence(addon.savedVariables)
end

Harness = {}
Harness.__index = Harness

-- Secret values ------------------------------------------------------------

local secretMeta = {}
local function secretError()
    error("attempt to compute with a secret value", 2)
end
secretMeta.__lt, secretMeta.__le, secretMeta.__eq = secretError, secretError, secretError
secretMeta.__add, secretMeta.__sub, secretMeta.__mul, secretMeta.__div = secretError, secretError, secretError, secretError
secretMeta.__mod, secretMeta.__pow, secretMeta.__unm = secretError, secretError, secretError
secretMeta.__concat, secretMeta.__len = secretError, secretError
secretMeta.__index = function() secretError() end
secretMeta.__newindex = secretMeta.__index
secretMeta.__tostring = function() return "<secret>" end

local secretValues = setmetatable({}, { __mode = "k" })

function Secret(value)
    local box = setmetatable({}, secretMeta)
    secretValues[box] = { value = value }
    return box
end

local function IsSecret(value)
    return type(value) == "table" and secretValues[value] ~= nil
end

function Reveal(value)
    if IsSecret(value) then
        return secretValues[value].value
    end
    return value
end

-- Harness ------------------------------------------------------------------

local UNIT_FIELDS = { "exists", "isPlayer", "canAttack", "dead", "feign", "health", "maxHealth" }

function Harness.new(player)
    local h = setmetatable({}, Harness)
    h.time = 0
    h.inCombat = false
    h.lockdown = false
    h.frames = {}
    h.handles = 0
    h.printed = {}
    h.sounds = {}       -- { path, channel, handle } per PlaySoundFile that played
    h.stopped = {}      -- { handle, fade } per StopSound
    h.files = {}        -- [path] = true for media that exists
    h.led = nil         -- current light bar color {r,g,b}, nil when cleared
    h.vibrations = {}   -- { type, intensity }
    h.opened = {}       -- Settings.OpenToCategory ids
    h.settings = {}     -- [variable] = setting
    h.spellNames = { [5308] = "Execute" }
    h.usable = {}       -- [spellName] = { isUsable, insufficientPower }
    h.player = {
        exists = true, isPlayer = true, canAttack = false, dead = false, feign = false,
        class = player and player.class or "ROGUE",
        afk = false,
        health = 100, maxHealth = 100,
        powerType = player and player.powerType or 3, -- Enum.PowerType.Energy
        power = { [3] = 100 }, powerMax = { [3] = 100 },
    }
    h.target = nil
    h.declared = {}     -- globals the TOC declares (SavedVariables); nil reads allowed
    h.errors = {}       -- messages passed to the error handler; a test fails if any are unexpected
    h.expectedErrors = 0
    h.propagated = {}   -- gamepad buttons no frame consumed
    h.labelStyle = nil  -- C_GamePad labelStyle of the connected controller; nil = none connected
    h.loaded = {}
    h.saved = player and player.saved or {} -- [SavedVariable name] = table, as the client restores it
    h.env = h:BuildEnvironment()
    Harness.created[#Harness.created + 1] = h
    return h
end

Harness.created = {}

-- Declares that the test deliberately causes n reported errors.
function Harness:ExpectErrors(n)
    self.expectedErrors = n
end

-- Registers a unit table as the target (nil clears) and fires PLAYER_TARGET_CHANGED.
function Harness:SetTarget(unit)
    if unit then
        for _, field in ipairs(UNIT_FIELDS) do
            if unit[field] == nil then
                unit[field] = (field == "exists") or (field == "health" and 100) or (field == "maxHealth" and 100) or false
            end
        end
    end
    self.target = unit
    self:Fire("PLAYER_TARGET_CHANGED")
end

function Harness:EnterCombat()
    self.inCombat = true
    self:Fire("PLAYER_REGEN_DISABLED")
    self.lockdown = true
end

function Harness:LeaveCombat()
    self.lockdown = false
    self.inCombat = false
    self:Fire("PLAYER_REGEN_ENABLED")
end

function Harness:Advance(seconds)
    self.time = self.time + seconds
end

function Harness:AddMedia(path)
    self.files[path] = true
end

-- Frames and events --------------------------------------------------------

local WIDGET_APIS = {
    Frame = { "SimpleFrameAPI", "SimpleRegionAPI", "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleObjectAPI", "FrameScriptObject" },
    StatusBar = { "SimpleStatusBarAPI", "SimpleFrameAPI", "SimpleRegionAPI", "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleObjectAPI", "FrameScriptObject" },
    Button = { "SimpleButtonAPI", "SimpleFrameAPI", "SimpleRegionAPI", "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleObjectAPI", "FrameScriptObject" },
    FontString = { "SimpleFontStringAPI", "SimpleRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleObjectAPI", "FrameScriptObject" },
    Texture = { "SimpleTextureAPI", "SimpleTextureBaseAPI", "SimpleRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleObjectAPI", "FrameScriptObject" },
}

-- Template-provided methods that aren't C API (BackdropTemplateMixin).
local TEMPLATE_METHODS = { BackdropTemplate = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true } }

local function IsRealMethod(widgetType, template, method)
    if template and TEMPLATE_METHODS[template] and TEMPLATE_METHODS[template][method] then
        return true
    end
    for _, api in ipairs(WIDGET_APIS[widgetType]) do
        local methods = SNAPSHOT.methods[api]
        if methods and methods[method] ~= nil then
            return true
        end
    end
    return false
end

-- Behavior for methods whose results tests or addons read back. Everything else just records.
local behaviors = {}
function behaviors.Show(w) w.shown = true end
function behaviors.Hide(w) w.shown = false end
function behaviors.SetShown(w, shown) w.shown = shown and true or false end
function behaviors.IsShown(w) return w.shown end
function behaviors.SetScript(w, script, fn) w.scripts[script] = fn end
function behaviors.GetScript(w, script) return w.scripts[script] end
function behaviors.HookScript(w, script, fn)
    local previous = w.scripts[script]
    w.scripts[script] = previous and function(...) previous(...); fn(...) end or fn
end
function behaviors.SetText(w, text) w.text = text end
function behaviors.GetText(w) return w.text end
function behaviors.SetValue(w, value) w.value = value end
function behaviors.GetValue(w) return w.value end
function behaviors.SetMinMaxValues(w, min, max) w.min, w.max = min, max end
function behaviors.GetMinMaxValues(w) return w.min, w.max end
function behaviors.GetName(w) return w.name end
function behaviors.GetObjectType(w) return w.widgetType end
function behaviors.CreateFontString(w) return w.harness:CreateWidget("FontString", nil, w) end
function behaviors.CreateTexture(w) return w.harness:CreateWidget("Texture", nil, w) end
function behaviors.RegisterEvent(w, event)
    assert(SNAPSHOT.events[event], "RegisterEvent: unknown event " .. tostring(event))
    w.events[event] = true
end
function behaviors.RegisterUnitEvent(w, event, unit1, unit2)
    assert(SNAPSHOT.events[event], "RegisterUnitEvent: unknown event " .. tostring(event))
    w.events[event] = { [unit1] = true, [unit2 or unit1] = true }
end
function behaviors.UnregisterEvent(w, event) w.events[event] = nil end
function behaviors.UnregisterAllEvents(w) w.events = {} end
function behaviors.IsEventRegistered(w, event) return w.events[event] ~= nil end
function behaviors.EnableGamePadButton(w, enable) w.gamepadButtons = enable end
function behaviors.IsGamePadButtonEnabled(w) return w.gamepadButtons or false end

function Harness:CreateWidget(widgetType, name, parent, template)
    assert(WIDGET_APIS[widgetType], "CreateFrame: unsupported widget type " .. tostring(widgetType))
    local widget = {
        harness = self, widgetType = widgetType, name = name, parent = parent, template = template,
        shown = true, scripts = {}, events = {}, calls = {},
    }
    setmetatable(widget, {
        __index = function(w, method)
            if not IsRealMethod(widgetType, template, method) then
                error(("%s has no method %s"):format(widgetType, tostring(method)), 2)
            end
            local behavior = behaviors[method]
            local fn = function(self_, ...)
                self_.calls[method] = (self_.calls[method] or 0) + 1
                if behavior then
                    return behavior(self_, ...)
                end
            end
            rawset(w, method, fn)
            return fn
        end,
    })
    if widgetType ~= "FontString" and widgetType ~= "Texture" then
        self.frames[#self.frames + 1] = widget
    end
    return widget
end

function Harness:Fire(event, ...)
    assert(SNAPSHOT.events[event], "Fire: unknown event " .. tostring(event))
    local unit = ...
    for _, frame in ipairs(self.frames) do
        local registration = frame.events[event]
        if registration and (registration == true or registration[unit]) then
            local handler = frame.scripts.OnEvent
            if handler then
                handler(frame, event, ...)
            end
        end
    end
end

-- Resets every widget's call counters (for per-event work assertions).
function Harness:ResetCalls()
    for _, frame in ipairs(self.frames) do
        frame.calls = {}
    end
end

-- Addon loading ------------------------------------------------------------

-- Loads one addon's files (dependencies first) and fires its ADDON_LOADED, like the client.
function Harness:LoadFiles(name)
    if self.loaded[name] then
        return self.loaded[name]
    end
    local addon = assert(ADDONS[name], "unknown addon " .. tostring(name))
    for dependency in (addon.metadata.Dependencies or ""):gmatch("[^,%s]+") do
        self:LoadFiles(dependency)
    end
    for _, variable in ipairs(addon.savedVariables) do
        self.declared[variable] = true
        rawset(self.env, variable, self.saved[variable])
    end
    local ns = {}
    self.loading = addon
    for i, file in ipairs(addon.files) do
        local chunk = assert(loadstring(addon.sources[i], "@" .. name .. "/" .. file))
        setfenv(chunk, self.env)
        chunk(name, ns)
    end
    self.loaded[name] = ns
    self:Fire("ADDON_LOADED", name)
    return ns
end

-- Loads an addon and runs the login sequence. Returns the addon's namespace table.
function Harness:LoadAddon(name)
    local ns = self:LoadFiles(name)
    self.ns = ns
    self:Fire("PLAYER_LOGIN")
    self:Fire("PLAYER_ENTERING_WORLD", true, false)
    return ns
end

-- Presses (down = true) or releases a gamepad key like "PAD1". Frames with gamepad buttons
-- enabled get it newest first until one consumes it (its script doesn't return true).
function Harness:Gamepad(key, down)
    local script = down and "OnGamePadButtonDown" or "OnGamePadButtonUp"
    for i = #self.frames, 1, -1 do
        local frame = self.frames[i]
        local handler = frame.scripts[script]
        if rawget(frame, "gamepadButtons") and frame.shown and handler and handler(frame, key) ~= true then
            return
        end
    end
    self.propagated[#self.propagated + 1] = key
end

-- Every widget created, flattened, for assertions over all of them.
function Harness:CountCalls(method)
    local total = 0
    for _, frame in ipairs(self.frames) do
        total = total + (frame.calls[method] or 0)
    end
    return total
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

