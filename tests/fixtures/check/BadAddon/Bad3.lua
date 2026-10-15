-- Fixture for the check gate's own tests (round-three cases: forms a call can take): each line
-- ending in "-- !" trips exactly one rule (the expected findings are in tests/check.test.mjs).
local Frame = CreateFrame("Frame")
Frame.RegisterEvent(Frame, "NOT_A_REAL_EVENT_X") -- !
Frame.RegisterEvent(Frame, "COMBAT_LOG_EVENT_UNFILTERED") -- !
SettingsPanel.Open(SettingsPanel) -- !
SettingsPanel["Open"](SettingsPanel) -- !
local Open = SettingsPanel.Open -- !
pcall(SetRaidTarget, "target", 1) -- !
C_GamePad:NotARealFunction() -- !
Frame:RegisterEvent("CHAT_MSG_AFK")
Frame:HookScript("OnEvent", function(_, _, text)
    if text == "afk" then -- !
        print(Open)
    end
end)
Frame:SetScript("OnEvent", function(_, _, ...)
    local said = ...
    if said == "afk" then -- !
        print(said)
    end
end)
local Health
Health = UnitHealth("target") -- secret: shown on a bar
if Health > 0 then -- !
    print(Health)
end
local Label = Frame:CreateFontString()
Label:SetText("shown")
print(Label["GetText"](Label)) -- !
local Button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
Button["SetPoint"](Button, "CENTER") -- !
local AtLoad = InCombatLockdown() -- read once, at load
local function StaleGuard()
    if AtLoad then
        return
    end
    C_AuctionHouse.PlaceBid(1, 1) -- !
end
print(StaleGuard)
