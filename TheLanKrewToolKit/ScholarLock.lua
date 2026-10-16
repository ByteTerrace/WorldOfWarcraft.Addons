local addonName, ns = ...

-- ScholarLock: the parent's PIN lock on Scholar's settings. /tlk lock 1234 locks them, and /tlk unlock 1234 unlocks
-- them for the session. While they're locked, the PIN can't be changed, and after three wrong PINs unlocking waits a
-- minute. The rows it writes (pin, pinMisses, pinWait, unlocked, and locked) are the Scholar module's, declared in
-- ScholarSettings.lua, and the module sets locked as it starts.
--
--   ns.ScholarLock.Commands   the lock and unlock commands, for the Scholar module's spec
--   ns.ScholarLock.Try(pin)   whether pin is the parent's PIN, with the same wait after three wrong ones

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

--- Returns whether pin is the parent's PIN, saying what's wrong when it isn't. Three wrong PINs in a row make every try
--- wait PinWaitSeconds, unlocking's included. It reads and writes the account-wide rows by name, so it works on a
--- character the challenge isn't on.
---@param pin string
---@return boolean
local function Try(pin)
    local state = Addon.State
    local wait = (state:Get("Scholar.pinWait") - GetServerTime())

    if wait > 0 then
        Addon:Print(("Too many wrong PINs. Try again in %d seconds."):format(wait))
    elseif PinHash(pin) == state:Get("Scholar.pin") then
        state:Set("Scholar.pinMisses", 0)

        return true
    elseif (state:Get("Scholar.pinMisses") + 1) >= MaxPinMisses then
        state:Set("Scholar.pinMisses", 0)
        state:Set("Scholar.pinWait", GetServerTime() + PinWaitSeconds)
        Addon:Print(("That PIN isn't right. Try again in %d seconds."):format(PinWaitSeconds))
    else
        state:Set("Scholar.pinMisses", state:Get("Scholar.pinMisses") + 1)
        Addon:Print("That PIN isn't right.")
    end

    return false
end

local function Unlock(pin)
    local scholar = Scholar()

    if scholar:Get("pin") == 0 then
        Addon:Print("Scholar settings aren't locked.")
    elseif not pin and ((scholar:Get("pinWait") - GetServerTime()) <= 0) then
        Addon:Print("Usage: " .. Addon.Slash[1] .. " unlock <pin>.")
    elseif Try(pin or "") then
        scholar:Set("unlocked", true)
        scholar:Set("locked", false)
        Addon:Print("Scholar settings unlocked for this session.")
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
    Try = Try,
}
