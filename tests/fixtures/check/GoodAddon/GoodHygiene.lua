-- Fixture for the HYGIENE and ARGS rules: every construct here is allowed, so this file must
-- produce no findings.
local addonName, ns = ...
local Noop = function() end
local Handlers = { OnShow = function() end }

local function Recursive(n)
    if n > 0 then
        return Recursive(n - 1)
    end
    return n
end

local function Callback(_, event)
    return event
end

local function Count(...)
    local _ignored, second = ...
    local _ = second
    return select("#", ...), second
end

Handlers.OnEvent = function(_, _, payload) return payload end

local Pump
function Pump() return Noop() end

local Total = 0
local function Bump() Total = Total + 1 end

-- docs/Conventions.md: a callback may name its parameter `state` where an outer `state` holds it.
local function Watch(state)
    print(state)
    return function(state) return state end
end

local function Conditional(flag)
    local value = 1
    if flag then
        value = 2
    end
    return value
end

local function ReadFirst()
    local value = 1
    value = value + 1
    return value
end

local function Captured()
    local value
    local function Show() return value end
    value = 1
    Show()
    value = 2
    return Show()
end

local function Ahead()
    local cached = nil
    cached = 1
    local later
    later = 2
    return cached + later
end

local function Guard(flag)
    if flag then
        return 1
    end
    do
        local scoped = 2
        print(scoped)
    end
    while flag do
        break
    end
    return 3
end

for _, value in ipairs({}) do
    print(value)
end

local function Pick() return 1, 2 end
local function Spread(...) return C_Spell.GetSpellName(...) end
local GetSpellName = C_Spell.GetSpellName
local Reassigned = C_Spell.GetSpellName
print(Reassigned)
Reassigned = print
Reassigned(1, 2, 3)
print(C_Spell.GetSpellName(1), GetSpellName(2), UnitExists(), GetTime(), Mixin({}, Handlers, Handlers))
print(C_Spell.GetSpellName(Pick()), Spread(1), C_Item.GetItemCount(1), C_CVar.SetCVar("name"))

print(Recursive(2), Callback, Count, Pump, Bump, Watch, Conditional, ReadFirst, Captured, Ahead, Guard)
