local addonName, ns = ...

-- ScholarLock: the parent's PIN lock on Scholar's settings. /tlk lock 1234 locks them, and /tlk unlock 1234 unlocks
-- them for the session. While they're locked, the PIN can't be changed, and after three wrong PINs unlocking waits a
-- minute. The rows it writes (pin, pinMisses, pinWait, unlocked, and locked) are the Scholar module's, declared in
-- ScholarSettings.lua, and the module sets locked as it starts.
--
--   ns.ScholarLock.Commands   the lock and unlock commands, for the Scholar module's spec

-- How many wrong PINs in a row make unlocking wait.
local MaxPinMisses = 3
-- How long unlocking waits after MaxPinMisses wrong PINs.
local PinWaitSeconds = 60

local byte = string.byte
local GetServerTime = GetServerTime

local Addon = ns.Addon

-- Kid-proofing, not security: a small hash so the PIN isn't sitting in the SavedVariables as-is.
local function PinHash(pin)
    local hash = 5381
    local text = ("tlk:" .. pin)

    for i = 1, #text do
        hash = (((hash * 33) + byte(text, i)) % 2147483647)
    end

    return hash
end

-- The Scholar module, which Scholar.lua declares after this file loads.
local function Scholar()
    return Addon.Modules.Scholar
end

local function Unlock(pin)
    local scholar = Scholar()
    local wait = (scholar:Get("pinWait") - GetServerTime())

    if scholar:Get("pin") == 0 then
        Addon:Print("Scholar settings aren't locked.")
    elseif wait > 0 then
        Addon:Print(("Too many wrong PINs. Try again in %d seconds."):format(wait))
    elseif not pin then
        Addon:Print("Usage: " .. Addon.Slash[1] .. " unlock <pin>.")
    elseif PinHash(pin) == scholar:Get("pin") then
        scholar:Set("pinMisses", 0)
        scholar:Set("unlocked", true)
        scholar:Set("locked", false)
        Addon:Print("Scholar settings unlocked for this session.")
    elseif (scholar:Get("pinMisses") + 1) >= MaxPinMisses then
        scholar:Set("pinMisses", 0)
        scholar:Set("pinWait", GetServerTime() + PinWaitSeconds)
        Addon:Print(("That PIN isn't right. Try again in %d seconds."):format(PinWaitSeconds))
    else
        scholar:Set("pinMisses", scholar:Get("pinMisses") + 1)
        Addon:Print("That PIN isn't right.")
    end
end

local function ValidPin(pin)
    return (pin and (pin:match("^%d%d%d%d%d?%d?%d?%d?$") ~= nil))
end

local function Lock(pin)
    local scholar = Scholar()

    if scholar:Get("locked") then
        Addon:Print("Scholar settings are locked. Unlock them first to change the PIN.")
    elseif (scholar:Get("pin") ~= 0) and not pin then
        scholar:Set("unlocked", false)
        scholar:Set("locked", true)
        Addon:Print("Scholar settings locked.")
    elseif ValidPin(pin) then
        scholar:Set("pin", PinHash(pin))
        scholar:Set("unlocked", false)
        scholar:Set("locked", true)
        Addon:Print("Scholar settings locked. Unlock with " .. Addon.Slash[1] .. " unlock <pin>.")
    else
        Addon:Print("Usage: " .. Addon.Slash[1] .. " lock <pin> (4 to 8 digits).")
    end
end

ns.ScholarLock = {
    Commands = {
        { label = "Parents: lock Scholar settings with a PIN (lock <pin>)", name = "lock", run = Lock, slash = "lock" },
        { label = "Parents: unlock Scholar settings (unlock <pin>)", name = "unlock", run = Unlock, slash = "unlock" },
    },
}
