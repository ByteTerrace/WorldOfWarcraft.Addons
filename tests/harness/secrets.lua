-- Secret values and the addon restriction model of the fake client (see wow.lua for the rest).
--
-- A secret is a userdata proxy (newproxy), as opaque as the client's: indexing it, taking its
-- length, comparing it with another secret, arithmetic and calling it all throw, and
-- pairs/ipairs/tonumber/print refuse it (the env wraps the last two). As in the client
-- (secrets.operations), concatenation, tostring and string.format (the env's, and the string
-- methods') accept secrets and return secret strings. The env's type() reports the underlying
-- type, like the client. Four misuses the client refuses but Lua 5.1 can't route through a
-- metamethod aren't caught here, so the static SECRET rule covers them: a boolean test (`if
-- secret then`, always true; the client refuses it only for a secret boolean), `secret ==
-- nonSecret` (mixed types compare false without consulting __eq), a secret compared with itself
-- (`x == x` is true without __eq; the client refuses it, secrets.rawOperations: compare) and a
-- secret as a table key (the client refuses it, secrets.rawOperations: tableKey).
--
-- Restrictions (h.restrictions) mirror Enum.AddOnRestrictionType: Combat, Encounter,
-- ChallengeMode, PvPMatch, Map, Chat. Whether a flagged API returns secrets is decided per call
-- by the predicate for each of its flags. [D] marks a predicate that follows its
-- SecretPredicatesDocumentation text; [E] marks behavior observed in the real client that
-- narrows the doc; [C] marks a conservative fallback where the doc is silent
-- or leaves the condition open (per-spell or per-token exceptions the harness doesn't model):
--
--   SecretReturns                     [E] always: UnitHealth and UnitHealthPercent came back secret
--                                         with no restriction at all (unitHealth.player,
--                                         unitHealth.npcTarget, unitHealthPercent.player)
--   SecretWhenAurasRestricted         [D] Combat, Encounter, ChallengeMode or PvPMatch
--   SecretWhenUnitAuraRestricted,     [C] the same, ignoring the per-spell never/always flags
--     ...CooldownsRestricted, ...TotemSlotSecret
--   SecretWhenInCombat                [D] Combat
--   SecretInActivePvPMatch            [D] PvPMatch
--   SecretOnRestrictedMaps            [D] Map
--   SecretInChatMessagingLockdown     [D] Encounter, ChallengeMode, PvPMatch or Map (the doc's
--                                         "communication-restricted map"), plus Chat [C]
--   SecretWhenUnitIdentityRestricted  [D] the unit isn't player-controlled or in the group
--                                         (compound tokens aren't modeled). A WOWGUID argument
--                                         (UnitTokenFromGUID) names the unit that has that GUID;
--                                         with several (PARTY_KILL), any restricted one counts,
--                                         and a GUID of no known unit is restricted [C].
--                                         [E] and only under an instance restriction (Encounter,
--                                         ChallengeMode or PvPMatch): probes of an NPC target's
--                                         name, class and GUID came back plain in the open world,
--                                         in combat and out (unitIdentity.npcTarget*)
--   SecretWhenUnitNameIdentityRestricted [D] identity rule, except players during a PvP match;
--                                         [E] under the same instance restrictions only
--   Observed per API                  [E] Harness.OBSERVED_SECRET[api](h, ctx) adds secrecy the
--                                         flags don't explain: UnitHealthMax is secret for every
--                                         existing unit but the player, an enemy player too
--                                         (unitHealth.enemyPlayer)
--   SecretWhenUnitHealthMaxRestricted, [D] the unit isn't player-controlled
--     SecretWhenUnitPowerMaxRestricted     (per-power-type flags aren't modeled)
--   SecretWhenUnitPowerRestricted     [D] the power type (the PowerType argument, else the one the
--                                         API implies, else the unit's)
--                                         isn't a never-secret secondary resource, and the unit
--                                         has it. The doc names no restriction: always.
--   SecretWhenUnitSpellCastRestricted [D] the unit isn't the player or their pet
--   SecretWhenLossOfControlInfoRestricted [D] the unit isn't the player (spectators not modeled)
--   SecretWhenUnitPossessionRestricted [D] aura restrictions, unless the unit is under the
--                                         player's direct control (player, pet, vehicle)
--   SecretWhenUnitThreat*Restricted   [C] any restriction, unless one unit is given or one is
--                                         the player
--   SecretWhenAnchoringSecret         [C] (methods) the widget holds any secret aspect
--   anything else                     [C] any restriction is active
--
-- When a predicate holds, every return value is secret, except for structures with a shape
-- (Harness.SECRET_SHAPES, below): C_DamageMeter's structures keep their NeverSecret fields plain
-- and wrap every other field, lists and nested structures staying plain tables (meter.lua).
--
-- A unit-based predicate is false for a unit that doesn't exist: the API returns nothing to
-- hide (UnitExists is false, not secret).
--
-- Two more conservative rules [C], where the docs name a restriction without saying how it works:
--   UnitTokenPvPRestrictedForAddOns   an argument of this type is restricted for addons during a
--                                     PvP match, and nothing says how. While PvPMatch is active, a
--                                     call whose such argument names an existing unit that isn't
--                                     the player, their pet or a group member returns secrets.
--   Secret in, secret out             a function that accepts a secret argument (AllowedWhenTainted)
--                                     returns secrets: UnitName(secretToken) is secret.
--
-- Every wrapped API (a fake whose name the snapshot documents, and every widget method) also
-- enforces, from the snapshot entry:
--   SecretArguments      addon code is tainted, so a secret argument (or a secret held one level
--                        deep in a table argument, like a color's r/g/b) is an error unless the
--                        policy is "AllowedWhenTainted" (a missing policy means NotAllowed).
--                        Arguments documented as LuaValueReference are passed by reference, never
--                        read, so a secret passes (issecretvalue takes one). LuaValueVariant is
--                        read (SerializeJSON, SerializeCBOR), so it enforces.
--   Undocumented fakes   (PlaySoundFile, PlaySound, StopSound, strsplit, ...) enforce the default,
--                        NotAllowed. Lua's own functions and Blizzard's Lua (CreateColor,
--                        GetMoneyString, SecondsToTime) are exempt (Harness.LUA_FAKES): the
--                        secret itself refuses whatever they do with it.
--   SecretArgumentsAddAspect / SecretReturnsForAspect
--                        a secret argument marks those aspects secret on the widget until
--                        SetToDefaults; a getter for a marked aspect returns secrets.
--   Preconditions        RequiresFontStringTextAccess: on a FontString whose Text aspect is
--                        secret, the (tainted) call returns nothing (FailureMode ReturnNothing).
--   Protection           a blocked call does nothing and returns nothing, like the client: it
--                        fires ADDON_ACTION_BLOCKED (or ADDON_ACTION_FORBIDDEN) with the addon
--                        and function names, and is recorded in h.blocked (Blizzard_Game's
--                        handler only shows a message; the caller keeps running).
--     IsProtectedFunction  a global is forbidden to addon code: ADDON_ACTION_FORBIDDEN, always.
--     Verified in game     Harness.FORBIDDEN_IN_GAME (tools/api/forbidden.json, which the PROTECTED
--                        rule reads too) lists functions the docs don't mark protected that addon
--                        code must never call: the Forever client refused them, or calling one
--                        led to a freeze (C_SettingsUtil.OpenSettingsPanel), each with its
--                        evidence. A
--                        freeze can't be modeled, so the harness forbids them like
--                        IsProtectedFunction globals, which fails any test that calls one. Which of
--                        the two events the client fired wasn't captured; FORBIDDEN is a guess.
--                        A method on a protected widget (a Secure template, or a parent of
--                        one) is blocked during combat lockdown: ADDON_ACTION_BLOCKED.
--     HasRestrictions    the docs don't say what the restriction is. With a specific marker the
--                        harness models the marker: RestrictedForMacroChatMessages applies to
--                        macros only, so addon calls pass. Without one it's blocked during combat
--                        lockdown, a guess: some of these (AssistUnit, TargetUnit) may be
--                        forbidden to addons at all times, or need a hardware event.

local Snapshot = __snapshot

local Boxes = setmetatable({}, { __mode = "k" })
local Template = newproxy(true)
local SecretMeta = getmetatable(Template)

local function Refuse(what)
    return function()
        error("attempt to " .. what .. " a secret value", 2)
    end
end
SecretMeta.__index, SecretMeta.__newindex = Refuse("index"), Refuse("index")
SecretMeta.__len = Refuse("take the length of")
SecretMeta.__eq, SecretMeta.__lt, SecretMeta.__le = Refuse("compare"), Refuse("compare"), Refuse("compare")
SecretMeta.__add, SecretMeta.__sub, SecretMeta.__mul = Refuse("compute with"), Refuse("compute with"), Refuse("compute with")
SecretMeta.__div, SecretMeta.__mod, SecretMeta.__pow = Refuse("compute with"), Refuse("compute with"), Refuse("compute with")
SecretMeta.__unm = Refuse("compute with")
SecretMeta.__call = Refuse("call")
SecretMeta.__tostring = function() return "<secret>" end -- harness diagnostics; the env's tostring refuses
SecretMeta.__metatable = false

-- Wraps a value as a secret (nil stays nil: an API that returns nothing returns nothing).
function Secret(value)
    if value == nil then
        return nil
    end
    local box = newproxy(Template)
    Boxes[box] = { value = value }
    return box
end

function IsSecret(value)
    return type(value) == "userdata" and Boxes[value] ~= nil
end

function Reveal(value)
    if IsSecret(value) then
        return Boxes[value].value
    end
    return value
end

-- Concatenation with a secret yields a secret string [E] (secrets.operations: concat). Lua's own
-- rules still apply: only strings and numbers concatenate.
SecretMeta.__concat = function(left, right)
    local a, b = Reveal(left), Reveal(right)
    for _, value in ipairs({ a, b }) do
        local kind = type(value)
        if kind ~= "string" and kind ~= "number" then
            error("attempt to concatenate a " .. kind .. " value", 2)
        end
    end
    return Secret(a .. b)
end

-- string.format that takes secrets, as the client's does: a secret format or argument makes the
-- result a secret string [E] (secrets.operations: format, formatString). A precision on %s with a
-- secret input is refused [C]: the client closed it in 12.0.1 (warcraft.wiki.gg Patch_12.0.1/
-- API_changes), and no probe covers it yet.
local RawFormat = string.format

function SecretFormat(fmt, ...)
    local n, secret = select("#", ...), IsSecret(fmt)
    local args = { ... }
    for i = 1, n do
        if IsSecret(args[i]) then
            secret = true
            args[i] = Reveal(args[i])
        end
    end
    if not secret then
        return RawFormat(fmt, ...)
    end
    local plainFormat = Reveal(fmt)
    if type(plainFormat) == "string" and plainFormat:find("%%[-+ #0]*%d*%.%d*s") then
        error("attempt to format a secret value with a precision", 2)
    end
    return Secret(RawFormat(plainFormat, unpack(args, 1, n)))
end

-- tostring of a secret is a secret string [E] (secrets.operations: tostring).
function SecretToString(value, ...)
    if IsSecret(value) then
        return Secret(tostring(Reveal(value)))
    end
    return tostring(value, ...)
end

Harness.RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }

local Aura = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
local Chat = { "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }
-- The restrictions of instanced content, under which unit identity is hidden [E].
local Instance = { "Encounter", "ChallengeMode", "PvPMatch" }

-- Power types flagged never secret (Enum.PowerType): combo points, runes, soul shards, holy
-- power, chi, arcane charges, essence.
Harness.NEVER_SECRET_POWER = { [4] = true, [5] = true, [7] = true, [9] = true, [12] = true, [16] = true, [19] = true }

-- The power type an API reads when it takes no PowerType argument: GetComboPoints reads combo
-- points (Enum.PowerType.ComboPoints), not the unit's primary power.
Harness.IMPLIED_POWER_TYPE = { GetComboPoints = 4 }

local function AnyOf(h, list)
    for _, name in ipairs(list) do
        if h.restrictions[name] then
            return true
        end
    end
    return false
end

local function AnyRestriction(h)
    return AnyOf(h, Harness.RESTRICTIONS)
end

-- A missing unit has nothing to hide.
local function PlayerControlled(h, token)
    local unit = h:Unit(token)
    return unit == nil or unit.playerControlled == true
end

-- The unit a call names: its unit argument, else the unit with its WOWGUID argument.
local function ContextUnit(h, ctx)
    if ctx.unit == nil and ctx.guid ~= nil then
        return h:UnitTokenForGUID(ctx.guid)
    end
    return ctx.unit
end

local function IdentityAccessible(h, token)
    local unit = h:Unit(token)
    return unit == nil or unit.playerControlled == true or unit.inGroup == true
end

local Predicates = {
    SecretReturns = function() return true end,
    SecretWhenAurasRestricted = function(h) return AnyOf(h, Aura) end,
    SecretWhenUnitAuraRestricted = function(h) return AnyOf(h, Aura) end,
    SecretWhenCooldownsRestricted = function(h) return AnyOf(h, Aura) end,
    SecretWhenTotemSlotSecret = function(h) return AnyOf(h, Aura) end,
    SecretWhenInCombat = function(h) return h.restrictions.Combat end,
    SecretInActivePvPMatch = function(h) return h.restrictions.PvPMatch end,
    SecretOnRestrictedMaps = function(h) return h.restrictions.Map end,
    SecretInChatMessagingLockdown = function(h) return AnyOf(h, Chat) end,
    SecretWhenUnitIdentityRestricted = function(h, ctx)
        if not AnyOf(h, Instance) then
            return false
        end
        if ctx.unit == nil and ctx.guids then
            -- Every GUID counts (PARTY_KILL carries two). A GUID names someone even when the
            -- harness has no unit for them, so an unknown one is restricted [C].
            for _, guid in ipairs(ctx.guids) do
                local token = h:UnitTokenForGUID(guid)
                if token == nil or not IdentityAccessible(h, token) then
                    return true
                end
            end
            return false
        end
        return not IdentityAccessible(h, ContextUnit(h, ctx))
    end,
    SecretWhenUnitNameIdentityRestricted = function(h, ctx)
        if not AnyOf(h, Instance) then
            return false
        end
        local unit = h:Unit(ctx.unit)
        if h.restrictions.PvPMatch and unit and unit.isPlayer then
            return false
        end
        return not IdentityAccessible(h, ctx.unit)
    end,
    SecretWhenUnitHealthMaxRestricted = function(h, ctx) return not PlayerControlled(h, ctx.unit) end,
    SecretWhenUnitPowerMaxRestricted = function(h, ctx) return not PlayerControlled(h, ctx.unit) end,
    SecretWhenUnitPowerRestricted = function(h, ctx)
        local unit = h:Unit(ctx.unit)
        local powerType = ctx.powerType
        if powerType == nil and unit then
            powerType = unit.powerType
        end
        if not unit or Harness.NEVER_SECRET_POWER[powerType] then
            return false
        end
        return not (unit.power and unit.power[powerType] == nil)
    end,
    SecretWhenUnitSpellCastRestricted = function(h, ctx)
        return h:Unit(ctx.unit) ~= nil and ctx.unit ~= "player" and ctx.unit ~= "pet"
    end,
    SecretWhenLossOfControlInfoRestricted = function(h, ctx) return h:Unit(ctx.unit) ~= nil and ctx.unit ~= "player" end,
    SecretWhenUnitPossessionRestricted = function(h, ctx)
        return AnyOf(h, Aura) and h:Unit(ctx.unit) ~= nil and ctx.unit ~= "player" and ctx.unit ~= "pet" and ctx.unit ~= "vehicle"
    end,
    SecretWhenUnitThreatStateRestricted = function(h, ctx)
        local a, b = ctx.units[1], ctx.units[2]
        return AnyRestriction(h) and b ~= nil and a ~= "player" and b ~= "player"
    end,
    SecretWhenAnchoringSecret = function(h, ctx)
        if ctx.widget then
            return next(ctx.widget.secretAspects) ~= nil -- ctx.widget is the widget's state
        end
        return AnyRestriction(h)
    end,
}
Predicates.SecretWhenUnitThreatValuesRestricted = Predicates.SecretWhenUnitThreatStateRestricted
Harness.PREDICATES = Predicates

-- True when an entry's secret flags (a set) make this call's results secret.
function Harness:SecretFor(flags, ctx)
    if not flags then
        return false
    end
    for flag in pairs(flags) do
        local predicate = Predicates[flag] or AnyRestriction
        if predicate(self, ctx) then
            return true
        end
    end
    return false
end

-- Structures whose docs mark fields NeverSecret or ConditionalSecret are secret field by field:
-- Harness.SECRET_SHAPES[api name] = function(result) returns the result with its secret fields
-- wrapped (it may wrap in place: every call returns fresh tables). Lists and structures stay
-- plain tables. An API without a shape wraps each whole return value.
Harness.SECRET_SHAPES = {}

-- Secrecy the real client showed that no flag predicate explains (see the header), by API name.
Harness.OBSERVED_SECRET = {
    UnitHealthMax = function(h, ctx)
        local unit = h:Unit(ctx.unit)
        return unit ~= nil and unit ~= h.player -- a unit that doesn't exist has nothing to hide
    end,
}

local function Pack(...)
    return { n = select("#", ...), ... }
end

-- An entry's documented argument (or payload) types, in order; parsed once per entry.
local function Types(entry, key)
    local cacheKey = key .. "List"
    local list = rawget(entry, cacheKey)
    if not list then
        list = {}
        for kind in (entry[key] or ""):gmatch("[^,]+") do
            list[#list + 1] = kind
        end
        entry[cacheKey] = list
    end
    return list
end

-- A vararg repeats the last documented type (StrideIndex).
local function TypeAt(types, i)
    return types[i] or types[#types]
end
Harness.Types, Harness.TypeAt = Types, TypeAt

-- The Lua type each primitive documented type arrives as.
local PayloadLuaTypes = {
    number = "number", luaIndex = "number", time_t = "number", BigUInteger = "number",
    cstring = "string", string = "string", WOWGUID = "string", bool = "boolean",
}

-- Errors (at Fire's caller) on a payload the client couldn't send: more values than the event
-- documents, a nil where the docs say Nilable = false (missing trailing values included), a
-- secret in an event without secret flags, or a primitive of another type than documented.
function Harness.CheckPayload(event, entry, payload)
    local types = Types(entry, "Payload")
    if payload.n > #types then
        error(("Fire: %s documents %d payload values, got %d"):format(event, #types, payload.n), 3)
    end
    for i = 1, #types do
        if payload[i] == nil and not entry.PayloadNilable[i] then
            error(("Fire: %s payload #%d (%s) isn't nilable"):format(event, i, types[i]), 3)
        end
    end
    for i = 1, payload.n do
        local value, want = payload[i], PayloadLuaTypes[types[i]]
        if IsSecret(value) then
            if not entry.secret then
                error(("Fire: %s has no secret flags, so payload #%d can't be secret"):format(event, i), 3)
            end
        elseif want and value ~= nil and type(value) ~= want then
            error(("Fire: %s payload #%d is a %s (%s), got a %s"):format(event, i, types[i], want, type(value)), 3)
        end
    end
end

-- Arguments passed by reference: the client never reads them, so a secret passes through (this
-- is how issecretvalue, AllowedWhenUntainted, still takes a secret from addon code).
local PassThrough = { LuaValueReference = true }

local function IsUnitType(kind)
    return kind == "UnitToken" or kind == "UnitTokenVariant" or kind == "UnitTokenNamePlate"
        or kind == "UnitTokenPvPRestrictedForAddOns" or kind == "UnitTokenRestrictedForAddOns"
end
Harness.IsUnitType = IsUnitType

-- A secret, or a (non-widget) table holding one as a key or value, one level deep.
local function HoldsSecret(value)
    if IsSecret(value) then
        return true
    end
    if type(value) == "table" and not Harness.State(value) then
        for k, v in next, value do
            if IsSecret(k) or IsSecret(v) then
                return true
            end
        end
    end
    return false
end
Harness.HoldsSecret = HoldsSecret

-- The predicate context for a call or event: the unit arguments (by documented type; without
-- types, the first string argument), the PowerType argument and the widget's state.
function Harness.CallContext(entry, key, args, widgetState)
    local types = Types(entry, key)
    local ctx = { args = args, units = {}, widget = widgetState }
    for i = 1, args.n or #args do
        local kind = TypeAt(types, i)
        if kind and IsUnitType(kind) and type(args[i]) == "string" then
            ctx.units[#ctx.units + 1] = args[i]
            if kind == "UnitTokenPvPRestrictedForAddOns" then
                ctx.pvpRestricted = ctx.pvpRestricted or {}
                ctx.pvpRestricted[#ctx.pvpRestricted + 1] = args[i]
            end
        elseif kind == "WOWGUID" and type(args[i]) == "string" then
            ctx.guid = ctx.guid or args[i]
            ctx.guids = ctx.guids or {}
            ctx.guids[#ctx.guids + 1] = args[i]
        elseif kind == "PowerType" then
            ctx.powerType = args[i]
        end
    end
    if #types == 0 and type(args[1]) == "string" then
        ctx.units[1] = args[1]
    end
    ctx.unit = ctx.units[1]
    return ctx
end

-- The UnitTokenPvPRestrictedForAddOns rule (see the header): during a PvP match, a restricted
-- token naming a unit outside the player's control and group makes the results secret.
local UnderControl = { player = true, pet = true, vehicle = true }

function Harness:PvPRestrictedToken(ctx)
    if not self.restrictions.PvPMatch or not ctx.pvpRestricted then
        return false
    end
    for _, token in ipairs(ctx.pvpRestricted) do
        local unit = self:Unit(token)
        if unit and not UnderControl[token] and unit ~= self.player and not unit.inGroup then
            return true
        end
    end
    return false
end

-- Fakes that are Lua (Lua's base library, or Blizzard's Lua) rather than client C API: exempt
-- from the undocumented default. A secret refuses whatever they do with it by itself.
Harness.LUA_FAKES = {
    assert = true, error = true, ipairs = true, next = true, pairs = true, pcall = true, select = true,
    setmetatable = true, getmetatable = true, rawget = true, rawset = true, rawequal = true, unpack = true,
    xpcall = true, type = true, tostring = true, format = true, tonumber = true, print = true, tinsert = true, tremove = true,
    wipe = true, CreateColor = true, GetMoneyString = true, SecondsToTime = true, random = true, date = true,
}

-- An undocumented C API fake gets the default policy: no secret arguments.
local Undocumented = { SecretArguments = "undocumented, so the default NotAllowed" }

-- Markers that say what an API's restriction is, replacing the generic HasRestrictions rule.
local SpecificRestrictions = { RestrictedForMacroChatMessages = true }

local function HasSpecificRestriction(entry)
    for marker in pairs(entry.Preconditions or {}) do
        if SpecificRestrictions[marker] then
            return true
        end
    end
    return false
end

-- Functions the Forever client refused to addon code when tried in game, though the docs don't
-- mark them IsProtectedFunction (see the header): tools/api/forbidden.json.
Harness.FORBIDDEN_IN_GAME = type(__forbidden) == "string" and assert(loadstring("return " .. __forbidden))() or {}

-- The event a call fires instead of running (nil = it runs): addon code is always tainted.
function Harness:BlockedBy(entry, isMethod, widget, name)
    if not isMethod and Harness.FORBIDDEN_IN_GAME[name] then
        return "ADDON_ACTION_FORBIDDEN"
    end
    if entry.IsProtectedFunction and not isMethod then
        return "ADDON_ACTION_FORBIDDEN"
    end
    if not self.lockdown then
        return nil
    end
    if entry.IsProtectedFunction and self:IsProtectedWidget(widget) then
        return "ADDON_ACTION_BLOCKED"
    end
    if entry.HasRestrictions and not HasSpecificRestriction(entry) then
        return "ADDON_ACTION_BLOCKED"
    end
    return nil
end

-- The client's response to a blocked call: the call does nothing, the event fires, and the
-- caller keeps running. h.blocked records every blocked or forbidden call; h.forbidden the latter.
function Harness:BlockAction(event, name)
    self.blocked[#self.blocked + 1] = name
    if event == "ADDON_ACTION_FORBIDDEN" then
        self.forbidden[#self.forbidden + 1] = name
    end
    self:Fire(event, self.mainAddon or self.loadOrder[#self.loadOrder] or "AddOn", name)
end

-- Wraps fn as the API `name` documented by `entry` (a snapshot entry; nil = undocumented, which
-- gets the default policy unless the fake is Lua). For a widget method, the first argument is
-- the widget.
function Harness:WrapApi(name, entry, fn, isMethod)
    if not entry then
        if Harness.LUA_FAKES[name] then
            return fn
        end
        entry = Undocumented
    end
    local h = self
    local policy = entry.SecretArguments
    local preconditions = entry.Preconditions or {}
    return function(...)
        if not isMethod then
            h.apiCalls[name] = (h.apiCalls[name] or 0) + 1
        end
        local args = Pack(...)
        local widget = isMethod and args[1] or nil
        local first = isMethod and 2 or 1
        local blocked = h:BlockedBy(entry, isMethod, widget, name)
        if blocked then
            h:BlockAction(blocked, name)
            return
        end
        local receivedSecret = false
        local types = Types(entry, "Arguments")
        local nilable = entry.ArgumentsNilable
        if nilable and not isMethod then -- widget methods have overloads the docs can't state (SetPoint("CENTER"))
            for i = 1, #types do
                if args[first + i - 1] == nil and not nilable[i] and not PassThrough[types[i]] then -- a reference may be nil
                    error(("%s: argument #%d (%s) isn't nilable"):format(name, i, types[i]), 2)
                end
            end
        end
        for i = first, args.n do
            if not PassThrough[TypeAt(types, i - first + 1) or ""] and HoldsSecret(args[i]) then
                if policy ~= "AllowedWhenTainted" then
                    error(("%s: secret argument #%d refused (SecretArguments %s; addon code is tainted)")
                        :format(name, i - first + 1, policy or "missing, so NotAllowed"), 2)
                end
                receivedSecret = true
            end
        end
        local state = widget and Harness.State(widget)
        if preconditions.RequiresFontStringTextAccess and state and state.secretAspects.Text then
            return -- FailureMode ReturnNothing for a tainted caller
        end
        if receivedSecret and state and entry.SecretArgumentsAddAspect then
            for aspect in pairs(entry.SecretArgumentsAddAspect) do
                state.secretAspects[aspect] = true
            end
        end
        local results = Pack(fn(...))
        local callArgs = isMethod and Pack(select(2, ...)) or args
        local ctx = Harness.CallContext(entry, "Arguments", callArgs, state)
        ctx.powerType = ctx.powerType or Harness.IMPLIED_POWER_TYPE[name]
        local observed = Harness.OBSERVED_SECRET[name]
        local secret = (entry.secret ~= nil and h:SecretFor(entry.secret, ctx)) or h:PvPRestrictedToken(ctx)
            or (observed ~= nil and observed(h, ctx))
            or (receivedSecret and not isMethod)
        if not secret and state and entry.SecretReturnsForAspect then
            for aspect in pairs(entry.SecretReturnsForAspect) do
                if state.secretAspects[aspect] then
                    secret = true
                end
            end
        end
        if secret then
            local shape = Harness.SECRET_SHAPES[name]
            for i = 1, results.n do
                if shape and type(results[i]) == "table" then
                    results[i] = shape(results[i])
                elseif not IsSecret(results[i]) then
                    results[i] = Secret(results[i])
                end
            end
        end
        return unpack(results, 1, results.n)
    end
end

-- Wraps a global (or Namespace.member) fake by its snapshot entry.
function Harness:WrapFunction(name, fn)
    return self:WrapApi(name, Snapshot.functions[name], fn, false)
end
