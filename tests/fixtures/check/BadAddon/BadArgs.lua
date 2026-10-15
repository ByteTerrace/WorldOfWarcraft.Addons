-- Fixture for the ARGS rule: each line ending in "-- !" trips exactly one rule (the expected
-- findings are in tests/check.test.mjs).
local C_Spell = C_Spell
local GetSpellName = C_Spell.GetSpellName
print(InCombatLockdown(true)) -- !
print(C_Spell.GetSpellName()) -- !
print(GetSpellName(1, 2)) -- !
print(C_Spell["GetSpellName"]()) -- !
print(GetTime "now") -- !
print(Mixin()) -- !
print(C_CVar.GetCVar("name", nil)) -- !
