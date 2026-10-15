-- Fixture for the HYGIENE rule: each line ending in "-- !" trips exactly one rule (the expected
-- findings are in tests/check.test.mjs).
local Unread = 1 -- !
local function Uncalled() end -- !
local function Recurse(n) return n > 0 and Recurse(n - 1) end -- !
local function Leading(first, second) return second end -- !
local function Trailing(first, second) return first end -- !
local function BeforeVararg(first, ...) return ... end -- !
local Table = {}
Table.Callback = function(self, event) return event end -- !
for index = 1, 3 do print("tick") end -- !
for key, value in pairs(Table) do print(key) end -- !
for key, value in pairs(Table) do print(value) end -- !
local First, Second = Table.a, Table.b -- !
local Written -- !
Written = 1
local function Outer(value) print(value) return function(value) return value end end -- !
for _, entry in ipairs({}) do for _, entry in ipairs(entry) do print(entry) end end -- !
local Level = 1
do
    local Level = 2 -- !
    print(Level)
end
local Twice = Level
print(Twice)
local Twice = 2 -- !
function Table:Method()
    return function(self) return self end -- !
end
local function Early()
    do return end
    print("never") -- !
end
local function Either(flag)
    if flag then return 1 else return 2 end
    print("never") -- !
end
while Table.go do
    do break end
    print("never") -- !
end
if Table.a then end -- !
if Table.a then print(1) elseif Table.b then else print(2) end -- !
if Table.e then print(1) else end -- !
do end -- !
while Table.c do end -- !
for _ = 1, 2 do end -- !
repeat until Table.d -- !
local function Overwrite()
    local total = 1 -- !
    total = 2
    return total
end
print(Leading, Trailing, BeforeVararg, Second, Outer, Twice, Early, Either, Overwrite)
