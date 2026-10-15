-- Fixture for the check gate's FRAMEWORK rule: an addon built on ByteTerrace_Core reaching past
-- the framework. Each line marked "-- !" is one finding; BadAddon's C_Timer call isn't one, since
-- BadAddon doesn't depend on the framework.
local addonName, ns = ...
local C_Timer = C_Timer
local Frame = CreateFrame("Frame")
C_Timer.After(1, print) -- !
C_Timer.NewTicker(1, print) -- !
Frame:RegisterEvent("CHAT_MSG_ADDON") -- !
C_ChatInfo.SendAddonMessage("Prefix1", "HI", "PARTY") -- !
PlaySoundFile("Interface\AddOns\FrameworkAddon\Media\Hi.ogg") -- !
local NewTimer = C_Timer.NewTimer -- !
print(addonName, ns, ByteTerrace, NewTimer, C_Timer) -- the namespace itself is fine
C_ChatInfo.SendAddonMessageLogged("Prefix1", "HI", "PARTY") -- !
Frame:RegisterEvent("CHAT_MSG_ADDON_LOGGED") -- !
Settings.RegisterVerticalLayoutCategory("Mine") -- !
Settings.RegisterCanvasLayoutCategory(Frame, "Mine") -- !
