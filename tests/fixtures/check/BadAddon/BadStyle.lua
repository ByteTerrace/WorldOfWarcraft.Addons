-- Fixture for the NAMING and COMMENT rules: each line ending in "-- !" trips exactly one rule
-- (the expected findings are in tests/check.test.mjs).
local MAX_ITEMS = 3 -- !
local itemCount = 0 -- !
local function helper() end -- !
local Handlers = {}
function Handlers.on_event() end -- !
function Handlers:Run(Count) return Count end -- !
local function Tally()
    local Total = 0 -- !
    for Index = 1, 3 do Total = Total + Index end -- !
    return Total
end
for Key in pairs(Handlers) do print(Key) end -- !
for _, entry in ipairs({ 1 }) do
    local Doubled = entry * 2 -- !
    print(Doubled)
end
local later -- !
function later() end -- !
-- Totals ---------------------------------------------------------------- !
-- TODO: count the handlers -- !
-- Good enough for now -- !
print(MAX_ITEMS, itemCount, helper, Tally, later)
