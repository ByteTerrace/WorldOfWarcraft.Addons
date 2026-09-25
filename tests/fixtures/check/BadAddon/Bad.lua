-- Fixture for the check gate's own tests: every line below trips exactly one rule.
local UnitHealth = UnitHealth
local frame = CreateFrame("Frame")
frame:RegisterEvent("NOT_A_REAL_EVENT")
local health = UnitHealth("player")
C_GamePad.NotARealFunction()
print(NotARealGlobal)
LeakedGlobal = health
BadAddonDB = BadAddonDB or {}
local guarded = UnitHealth("player") -- secret: fixture shows the annotation is honored
local function Guarded()
    local value = UnitHealth("player")
    return issecretvalue(value)
end
local trailing = 1 
