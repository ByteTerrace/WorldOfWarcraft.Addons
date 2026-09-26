-- Fixture for the check gate's own tests: every construct here is allowed, so this file must
-- produce no findings.
local UnitHealth, UnitClass, UnitIsAFK, issecretvalue = UnitHealth, UnitClass, UnitIsAFK, issecretvalue
local Energy = Enum.PowerType.Energy
local format = string.format
local Frame = CreateFrame("Frame")
local GoodEvent = "PLAYER_LOGIN"
Frame:RegisterEvent(GoodEvent)
Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Frame:SetPoint("CENTER")

GoodAddonDB = GoodAddonDB or {}
_G.GoodAddonDB = GoodAddonDB
GoodAddonAPI = {}
GoodAddonAPI.version = 1
function GoodAddonAPI.Describe() return format("%d", Energy) end
_G["SLASH_GOODADDON1"] = "/good"
SlashCmdList.GOODADDON = function() end
local DynamicKey = "GoodAddonDynamic"
_G[DynamicKey] = true -- global: fixture shows the annotation is honored
local Parent = _G.UIParent

local function PlayerClass()
    local _, class = UnitClass("player")
    if issecretvalue(class) then
        return nil
    end
    return class
end

local function Away()
    return issecretvalue(UnitIsAFK("player"))
end

local function Sink(fs)
    -- secret: widget sink
    fs:SetText(UnitHealth("player"))
end

local function OpenSettings()
    if InCombatLockdown() then
        return
    end
    C_AuctionHouse.PlaceBid(1, 1)
end

local function OpenAnyway()
    C_AuctionHouse.PlaceBid(1, 1) -- protected: fixture shows the annotation is honored
end

if C_Spell.GetSpellName then
    print(Parent, PlayerClass, Away, Sink, OpenSettings, OpenAnyway)
end

-- Guards the gate accepts (the patterns this repository's addons use).
local function AtFullHealth()
    local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
    if issecretvalue(health) or issecretvalue(maxHealth) then
        return nil
    end
    return health >= maxHealth
end

local function AwayFlag()
    local afk = UnitIsAFK("player")
    if not issecretvalue(afk) then
        print(afk and true or false)
    end
end

local function Warrior()
    local _, class = UnitClass("player")
    if issecretvalue(class) or class ~= "WARRIOR" then
        return
    end
    print(class)
end

local function NameOr()
    local name = UnitName("player")
    if issecretvalue(name) or not name then
        return "adventurer"
    end
    return name
end

local function Accessible()
    local hp = UnitHealth("target")
    if canaccessvalue(hp) then
        return hp + 1
    end
end

local function Otherwise()
    local hp = UnitHealth("target")
    if issecretvalue(hp) then
        print("hidden")
    else
        return hp > 1
    end
    return not issecretvalue(UnitHealth("focus")) and false
end

local function Inline()
    local hp = UnitHealth("target")
    return not issecretvalue(hp) and hp > 1
end

local function GuardedBid(other)
    if InCombatLockdown() or other then
        return
    end
    C_AuctionHouse.PlaceBid(1, 1)
    if not InCombatLockdown() then
        Frame:SetPropagateKeyboardInput(true)
    end
end

local Chat = CreateFrame("Frame")
Chat:RegisterEvent("CHAT_MSG_AFK")
Chat:SetScript("OnEvent", function(_, _, text)
    if issecretvalue(text) then
        return
    end
    if text == "brb" then
        print("away")
    end
end)
local Events = {}
Events:On("UNIT_AURA", function(unit) return unit == "player" end)
Events:On("PLAYER_ENTERING_WORLD", function(isLogin) return isLogin and 1 end)

print(AtFullHealth, AwayFlag, Warrior, NameOr, Accessible, Otherwise, Inline, GuardedBid)
local function Sink(bar)
    local cur = UnitPower("player", 3) -- secret: widget sink
    bar:SetValue(cur)
    return cur
end
print(Sink)
