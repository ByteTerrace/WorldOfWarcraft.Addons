local addonName, ns = ...

-- The money generators: math.coins (copper within 100) and math.money (silver and copper), registered in Kit.Generators
-- like ScholarMath.lua's, which loads right before this file and lends the functions they build with. Pure like
-- ScholarPuzzles.lua. Both sometimes count with the player's own purse (state.context.copper).

local floor = math.floor
local insert = table.insert
local max = math.max
local min = math.min

local Kit = ns.Puzzles.Kit
local AddMistakes = Kit.AddMistakes
local AddParts = Kit.AddParts
local Chance = Kit.Chance
local Coins = Kit.Coins
local Generators = Kit.Generators
local Numeric = Kit.Numeric
local With = Kit.With

-- Copper within 100; sometimes the player's own copper when they have less than 90.
Generators["math.coins"] = function(state)
    local mine = state.context.copper
    local a = nil
    local b = nil
    local change = false

    if mine and (mine >= 1) and (mine <= 90) and Chance(state, 2) then
        a = mine
        b = state.roll(1, min(50, 100 - a))
    elseif state.level < 3 then
        a = (((state.level == 1) and (10 * state.roll(1, 5))) or state.roll(11, 60))
        b = (((state.level == 1) and (10 * state.roll(1, 9 - (a / 10)))) or state.roll(5, 100 - a))
        mine = nil
    else
        a, b, change, mine = 100, state.roll(5, 95), true, nil
    end

    local options = { format = function(n) return (n .. " copper") end, lo = 1 }

    if change then
        local v = (a - b)
        local ob = (b % 10)
        local ten = (10 * (floor(b / 10) + 1))
        local vars = { a = a, b = b, b10 = (b + 10), ob = ob, rest = (100 - ten), tb = floor(b / 10), ten = ten, up = (ten - b), v = v }
        local named = { { b, why = "price" }, { (a + b), why = "added" } }

        if ob > 0 then
            insert(named, 1, { (v + 10), why = "borrow" })
        end

        options.cases = ((((ob == 0) and { "tens" }) or ((b > 90) and { "near" })) or nil)

        return Numeric(state, "math.coins", "coinsChange", vars, With(named, (v + 1), (v - 1), (v - 10)), options)
    end

    local parts = AddParts(a, b)
    local v = parts.v

    options.cases = {}

    if parts.ones >= 10 then
        options.cases[#options.cases + 1] = "carry"
    end

    if mine then
        options.cases[#options.cases + 1] = "mine"
    end

    return Numeric(state, "math.coins", "coinsAdd", parts, With(AddMistakes(parts), (v + 10), (v - 10), (v + 1), (v - 1)),
        options)
end

-- Silver and copper; sometimes the player's own purse when it's under 100 silver.
Generators["math.money"] = function(state)
    local mine = state.context.copper

    mine = ((mine and (mine >= 100) and (mine <= 9999) and Chance(state, 2) and mine) or nil)
    local cases = {}
    local key = nil
    local a = nil
    local b = nil
    local v = nil
    local named = nil

    if (state.level == 3) or (mine and (mine > 9000)) then
        a = (mine or ((100 * state.roll(3, 9)) + state.roll(0, 49)))
        local copper = ((((a % 100) < 99) and state.roll((a % 100) + 1, 99)) or state.roll(0, 98))

        b = ((100 * state.roll(1, max(1, floor(a / 100) - 1))) + copper)
        b = (((b < a) and b) or state.roll(1, a - 1))
        key, v, named = "moneySubtract", (a - b), { { (a + b), why = "added" } }

        if (b % 100) > (a % 100) then
            insert(named, 1, { (((floor(a / 100) - floor(b / 100)) * 100) + ((b % 100) - (a % 100))), why = "noTrade" })
        else
            cases[#cases + 1] = "even"
        end

        With(named, (v + 100), (v - 100), (v + 10), (v - 10))
    elseif (state.level == 2) or mine then
        a, b = (mine or state.roll(101, 599)), state.roll(101, 599)
        key, v = "moneyAdd", (a + b)

        if ((a % 100) + (b % 100)) >= 100 then
            cases[#cases + 1], named = "trade", { { (v - 100), why = "lost" } }
        else
            named = { { ((floor(a / 100) + floor(b / 100)) * 100), why = "silverOnly" }, { (v + 100), why = "extra" } }
        end

        With(named, (v - 100), (v + 100), (v + 10), (v - 10), (v - (v % 100)))
    else
        a = state.roll(101, 999)
        key, v = "moneyConvert", a

        named = {
            { ((floor(a / 10) * 100) + (a % 10)), why = "tens" }, { ((floor(a / 100) * 100) + floor((a % 100) / 10)), why = "ones" },
            (a + 100), (a - 100), (a + 1),
        }
    end

    if mine then
        cases[#cases + 1] = "mine"
    end

    local pa = (a % 100)
    local pb = ((b or 0) % 100)

    local vars = {
        a = a, b = b, ca = Coins(a), cb = (b and Coins(b)), cr = (v % 100), cs = (pa + pb), cv = Coins(v), h = (100 * floor(a / 100)),
        pa = pa, pb = pb, px = (pa + 100), sa = floor(a / 100), sa1 = (floor(a / 100) - 1), sb = floor((b or 0) / 100),
        ss = floor(v / 100), tens = floor(a / 10), v = v,
    }

    return Numeric(state, "math.money", key, vars, named, { cases = cases, format = Coins, lo = 1 })
end
