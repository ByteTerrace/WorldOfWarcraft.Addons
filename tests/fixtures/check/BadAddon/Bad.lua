-- Fixture for the check gate's own tests: each line ending in "-- !" trips exactly one rule
-- (the expected findings are in tests/check.test.mjs). Everything else must stay clean.
local UnitHealth = UnitHealth
local Frame = CreateFrame("Frame")
Frame:RegisterEvent("NOT_A_REAL_EVENT") -- !
local Health = UnitHealth("player") -- !
C_GamePad.NotARealFunction() -- !
print(NotARealGlobal) -- !
LeakedGlobal = Health -- !
BadAddonDB = BadAddonDB or {}
BadAddonCharDB = BadAddonCharDB or {}
local Guarded = UnitHealth("player") -- secret: fixture shows the annotation is honored
local Trailing = 1 -- ! 
local Fake = UnitHealth("player"), "-- secret: a string literal isn't an annotation" -- !
local function ScopedAlias()
    local readHealth = UnitHealth
    return readHealth("target") -- !
end
pcall(UnitHealth, "player") -- !
local Holder = {}
Holder.f = UnitHealth -- !
local Caption = Frame:CreateFontString()
local Text = Caption:GetText() -- !
local function Partial()
    local className, classFile = UnitClass("target") -- !
    return issecretvalue(className) and classFile
end
_G.LeakedViaG = 1 -- !
_G["LeakedViaIndex"] = 1 -- !
_G[Text] = 1 -- !
getfenv().LeakedViaFenv = 1 -- !
rawset(_G, "LeakedViaRawset", 1) -- !
setglobal("LeakedViaSetglobal", 1) -- !
print(getglobal("NotARealGlobal2")) -- !
string.trimall = function() end -- !
C_GamePad.Hijack = print -- !
CreateFrame("Frame", "UIParent") -- !
print(_G.NotARealGlobal3) -- !
print(ToggleCollision) -- !
print(Enum.PowerType.NotAPowerType) -- !
local PowerType = Enum.PowerType
print(PowerType.AlsoNotAPowerType) -- !
print(C_Spell["NotASpellFunction"]) -- !
print(C_Macro.SetMacroExecuteLineCallback) -- !
print(string.dump) -- !
local UnknownEvent = "NOT_REAL_EITHER"
Frame:RegisterEvent(UnknownEvent) -- !
Settings.OpenToCategory(1) -- !
C_AuctionHouse.PlaceBid(1, 1) -- !
local Secure = CreateFrame("Button", "BadAddonSecure", UIParent, "SecureActionButtonTemplate")
Secure:SetPoint("CENTER") -- !
local function Deeper()
    function string:Helper() end -- !
end
print(ScopedAlias, Partial, Deeper, Guarded, Trailing, Fake)
Caption:SetText("a setter that can make the Text aspect secret, so GetText above counts")
