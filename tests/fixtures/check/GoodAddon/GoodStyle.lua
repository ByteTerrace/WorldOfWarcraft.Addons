-- Fixture for the NAMING and COMMENT rules: every construct here is allowed, so this file must
-- produce no findings.
local addonName, ns = ...

local MaxItems = 8

local floor, format = math.floor, string.format
local C_Timer = C_Timer

local Queue = {}
local Pump

--- A doc comment's third dash isn't a banner.
---@param count integer
---@return integer
local function Clamp(count)
    local _, rest = floor(count), count % 1
    return count > MaxItems and MaxItems or count + rest
end

function Pump()
    for i = 1, #Queue do
        Queue[i] = nil
    end
end

local Methods = {}

function Methods:Run(...)
    local first = ...
    local OnDone = function() return first end
    local Finish
    function Finish() return OnDone() end
    return Finish()
end

function Methods.__index() end

do
    local Calls = 0 -- a top-level do block scopes file-level state
    function Methods.Next()
        Calls = Calls + 1
        return Calls
    end
end

for _, name in ipairs({ "a" }) do
    local upper = name:upper()
    Queue[#Queue + 1] = upper
end

-- Debt markers are the capitalized words: a hack or a revisit in prose is fine.
print(addonName, ns, format, C_Timer, Clamp, Pump)
