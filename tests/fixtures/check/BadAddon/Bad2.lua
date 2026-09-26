-- Fixture for the check gate's own tests (round-two cases): each line ending in "-- !" trips
-- exactly one rule (the expected findings are in tests/check.test.mjs).
local Annotated = UnitHealth("player") -- secret: a trailing annotation covers only its own line
local Unannotated = UnitHealth("target") -- !
--[[ secret: block comments aren't annotations ]]
local BlockCommented = UnitHealth("target") -- !
local function Reassigned(flag)
    local get = UnitHealth -- !
    if flag then get = UnitHealthMax end -- !
    return get("target")
end
local function Late()
    local hp = UnitHealth("target") -- !
    local low = hp < 50
    if issecretvalue(hp) then return nil end
    return low
end
local Stored = {}
local function Store()
    local hp = UnitHealth("target") -- !
    Stored.hp = hp
    if issecretvalue(hp) then return end
end
local function Discarded()
    local hp = UnitHealth("target") -- !
    issecretvalue(hp)
    return hp
end
local function Recomputed()
    local hp = UnitHealth("target") -- !
    if issecretvalue(hp) then return end
    hp = hp + 1
    return hp
end
local function NoExit()
    local hp = UnitHealth("target") -- !
    if issecretvalue(hp) then print("secret") end
    return hp > 1
end
local Bar = CreateFrame("StatusBar")
Bar:SetValue(1)
local BarValue = Bar.GetValue(Bar) -- !
local GetBarValue = Bar.GetValue -- !
local ViaGetglobal = getglobal("UnitHealth")("target") -- !
getfenv(2).LeakFenv2 = 1 -- !
loadstring("x = 1") -- !
setfenv(1, {}) -- !
local function Leak(f) return getfenv(f) end -- !
loadstring("y = 1") -- global: fixture shows the annotation is honored
local function Ignored()
    local _ = InCombatLockdown()
    C_AuctionHouse.PlaceBid(1, 1) -- !
end
local function NoReturn()
    if InCombatLockdown() then print("later") end
    C_AuctionHouse.PlaceBid(1, 1) -- !
end
local function Later()
    if InCombatLockdown() then return end
    C_Timer.After(1, function() C_AuctionHouse.PlaceBid(1, 1) end) -- !
end
local Holder = {}
Holder.button = CreateFrame("Button", "BadTwoSecure", UIParent, "SecureActionButtonTemplate")
Holder.button:SetPoint("CENTER") -- !
local SecureButton = CreateFrame("Button", "BadTwoSecureToo", UIParent, "SecureActionButtonTemplate")
local SecureAlias = SecureButton
SecureAlias:Show() -- !
local function Param(f) f:Hide() end -- !
local Plain = CreateFrame("Frame")
Plain:Hide()
Plain:SetPropagateKeyboardInput(true) -- !
local Chat = CreateFrame("Frame")
Chat:RegisterEvent("CHAT_MSG_AFK")
Chat:SetScript("OnEvent", function(_, _, text)
    if text == "brb" then print("away") end -- !
end)
local Events = {}
Events:On("CHAT_MSG_AFK", function(text) return #text end) -- !
Events:On("CHAT_MSG_AFK", function(text) local copy = text print(copy) end) -- !
Events:On("CHAT_MSG_AFK", function(text) Events.last = text end) -- !
Events:On("CHAT_MSG_AFK", function(text) return { text } end) -- !
local function Discard() local _ = UnitHealth("target") return _ + 1 end -- !
print(Discard)
print(Annotated, Unannotated, BlockCommented, Reassigned, Late, Store, Discarded, Recomputed, NoExit, BarValue, GetBarValue, ViaGetglobal, Leak, Ignored, NoReturn, Later, Param)
local function Mark() if InCombatLockdown() then return end SetRaidTarget("target", 8) end -- !
print(Mark)
Events:On("CHAT_MSG_AFK", function(text) Events[text] = true end) -- !
Events:On("CHAT_MSG_AFK", function(text) local kept = Events.on and text or nil return kept end) -- !
local function Low()
    local cur = UnitPower("player", 3) -- secret: widget sink
    if cur == 0 then return true end -- !
end
print(Low)
Chat:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- !
SettingsPanel:OpenToCategory(1) -- !
