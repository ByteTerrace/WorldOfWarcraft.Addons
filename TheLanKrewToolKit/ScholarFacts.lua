local addonName, ns = ...

-- Riddles made from the player's own game: their quest log, their bags, the merchant in front of
-- them, the XP they need. Real numbers make real stakes. Pure like ScholarPuzzles.lua: the caller
-- reads the game and passes facts in; nothing here touches the WoW API.
--
--   ns.Puzzles.FromFact(fact, options) -> puzzle or nil
--     options: grade (0..6) and random, as for Generate.
--     fact, one of:
--       { type = "objective", quest, item, have, need }   an item a quest asks for
--       { type = "questRead", quest, item, others }       which item a quest asks for (others: the
--                                                         items other quests ask for, as distractors)
--       { type = "stacks", item, stacks, size }           full stacks in your bags
--       { type = "sell", item, count, price }             selling to a merchant (price: copper each)
--       { type = "xp", need, per }                        quests (per XP each) to the next level
--   Returns nil when the fact doesn't suit the grade (numbers too big, an operation not taught yet)
--   or its text isn't plain. The puzzle has Generate's fields; its kind is "math.<type>" or
--   "reading.questRead".

local MaxQuest, MaxItem = 40, 30
-- The biggest answer each grade's math handles: the bands tests/scholar.test.lua holds the
-- generators to.
local Band = { [0] = 10, 20, 100, 100, 9999, 1000, 1000 }

local Text = {
    objective = {
        titles = { "Quest Math", "Adventure Count", "Almost There!" },
        prompt = "Your quest \"{quest}\" needs {item} x{need}. You have {have}. How many more do you need?",
        hint = "Start at {have} and count up to {need}.",
        explain = "{need} - {have} = {v}. Go get them!",
    },
    questRead = {
        titles = { "Quest Reader", "Read the Scroll" },
        prompt = "Read your quest log! What does \"{quest}\" ask you to bring?",
        hint = "Open your quest log (press L) and read the goal of \"{quest}\".",
        explain = "\"{quest}\" asks for {item}.",
    },
    stacks = {
        titles = { "Bag Count", "Pack Math" },
        prompt = "You have {stacks} full stacks of {item}. Each stack holds {size}. How many {item} is that in all?",
        hint = "{stacks} groups of {size}. Skip count by {size}!",
        explain = "{stacks} x {size} = {v}.",
    },
    stacksAdd = {
        titles = { "Bag Count", "Pack Math" },
        prompt = "You have {stacks} full stacks of {item}. Each stack holds {size}. How many {item} is that in all?",
        hint = "Add {size} one time for each stack.",
        explain = "{sum} = {v}.",
    },
    sell = {
        titles = { "Merchant Math", "Gold Counter" },
        prompt = "The merchant pays {price} copper for each {item}. You sell {count}. How much do you get?",
        hint = "Multiply {count} by {price}. Every 100 copper is 1 silver.",
        explain = "{count} x {price} = {total} copper, which is {v}.",
    },
    xp = {
        titles = { "Level Up Math", "Road to the Next Level" },
        prompt = "You need {need} more XP to level up. Each quest gives {per} XP. What is the fewest quests you need?",
        hint = "Divide {need} by {per}. If there's any XP left over, you need one more quest!",
        explain = "{need} / {per} = {whole} with {left} XP left over, so {v} quests.",
        explainExact = "{need} / {per} = {v} quests exactly.",
    },
}

local ceil, floor, max = math.ceil, math.floor, math.max
local concat = table.concat
local upper = string.upper
local ipairs, tostring, type = ipairs, tostring, type

local Puzzles = ns.Puzzles
local Kit = Puzzles.Kit
local Pick, Fill, Arrange, WrongNumbers, Mentions = Kit.Pick, Kit.Fill, Kit.Arrange, Kit.WrongNumbers, Kit.Mentions
local Clean, WholeNumber, Coins, Shuffle, Words = Kit.Clean, Kit.WholeNumber, Kit.Coins, Kit.Shuffle, Kit.Words

local function Build(options, kind, text, vars, correct, wrongs, extra)
    local state = { roll = options.random }
    local choices, answer = Arrange(state, correct, wrongs)
    local hint = Fill(text.hint, vars)
    if Mentions(hint, correct) then
        hint = Words.hintFallback
    end
    local puzzle = {
        subject = kind:match("^(%a+)%."), kind = kind, title = Pick(state, text.titles),
        prompt = Fill(text.prompt, vars), choices = choices, answer = answer, hint = hint,
        explanation = Fill(extra and extra.explain or text.explain, vars) .. " " .. Pick(state, Words.praise),
        value = vars.value,
    }
    if #puzzle.prompt > Kit.MaxPrompt then
        return nil
    end
    for _, choice in ipairs(choices) do
        if #choice > Kit.MaxChoice then
            return nil
        end
    end
    return puzzle
end

local function Numbers(options, value, candidates, lo, hi, format)
    local wrongs = {}
    for i, n in ipairs(WrongNumbers({ roll = options.random }, value, candidates, lo, hi)) do
        wrongs[i] = (format or tostring)(n)
    end
    return wrongs
end

local function FromObjective(fact, grade, options)
    local quest, item = Clean(fact.quest, MaxQuest), Clean(fact.item, MaxItem)
    local need, have = WholeNumber(fact.need, 2, Band[grade]), WholeNumber(fact.have, 0, 1e6)
    if not (quest and item and need and have and have < need) then
        return nil
    end
    local v = need - have
    local vars = { quest = quest, item = item, need = need, have = have, v = v, value = v }
    return Build(options, "math.objective", Text.objective, vars, tostring(v),
        Numbers(options, v, { need + have, need, have, v + 1, v - 1, v + 2 }, 1, max(need + have, v + 10)))
end

local function FromQuestRead(fact, grade, options)
    local quest, item = Clean(fact.quest, MaxQuest), Clean(fact.item, MaxItem)
    if grade < 1 or not (quest and item) or type(fact.others) ~= "table" then
        return nil
    end
    local wrongs, seen = {}, { [item:lower()] = true }
    local function Add(name)
        if name and not seen[name:lower()] then
            seen[name:lower()] = true
            wrongs[#wrongs + 1] = name
        end
    end
    for _, other in ipairs(fact.others) do
        Add(Clean(other, MaxItem))
    end
    -- Stock adventure items ("Potion") fill in when the log doesn't have three other items.
    local stock = Shuffle({ roll = options.random }, Words.items.adventure)
    for i = 1, #stock do
        if #wrongs >= 3 then
            break
        end
        Add((stock[i][1]:gsub("^%l", upper)))
    end
    local vars = { quest = quest, item = item }
    return Build(options, "reading.questRead", Text.questRead, vars, item, wrongs)
end

local function FromStacks(fact, grade, options)
    local item = Clean(fact.item, MaxItem)
    local stacks, size = WholeNumber(fact.stacks, 2, 12), WholeNumber(fact.size, 2, 200)
    if grade < 2 or not (item and stacks and size) then
        return nil
    end
    local v = stacks * size
    if v > Band[grade] then
        return nil
    end
    local vars = { item = item, stacks = stacks, size = size, v = v, value = v }
    local text = Text.stacks
    if grade == 2 then
        if stacks > 3 then
            return nil -- repeated addition only for a few stacks before multiplication is taught
        end
        local terms = {}
        for i = 1, stacks do
            terms[i] = tostring(size)
        end
        vars.sum, text = concat(terms, " + "), Text.stacksAdd
    end
    return Build(options, "math.stacks", text, vars, tostring(v),
        Numbers(options, v, { stacks + size, v + size, v - size, stacks * (size - 1), v + stacks }, 1, v * 2))
end

local function FromSell(fact, grade, options)
    local item = Clean(fact.item, MaxItem)
    local count, price = WholeNumber(fact.count, 2, 20), WholeNumber(fact.price, 1, 9999)
    if grade < 3 or not (item and count and price) then
        return nil
    end
    local total = count * price
    if total > Band[grade] or (grade == 3 and total >= 100) then
        return nil -- grade 3 stays under a silver, so the answer is plain copper
    end
    local vars = { item = item, count = count, price = price, total = total, v = Coins(total), value = total }
    return Build(options, "math.sell", Text.sell, vars, Coins(total),
        Numbers(options, total, { count + price, total + price, total - price, count * (price + 1), total * 10 },
            1, total * 10 + 10, Coins))
end

local function FromXP(fact, grade, options)
    local need, per = WholeNumber(fact.need, 1, 999999), WholeNumber(fact.per, 1, 999999)
    if grade < 4 or not (need and per) then
        return nil
    end
    local whole, left = floor(need / per), need % per
    local v = ceil(need / per)
    if v < 2 or v > 12 or need > Band[grade] * 10 then
        return nil
    end
    local vars = { need = need, per = per, whole = whole, left = left, v = v, value = v }
    return Build(options, "math.xp", Text.xp, vars, tostring(v),
        Numbers(options, v, { whole, v + 1, v - 1, v + 2, whole - 1 }, 1, v + 10),
        left == 0 and { explain = Text.xp.explainExact } or nil)
end

local Makers = {
    objective = FromObjective, questRead = FromQuestRead, stacks = FromStacks, sell = FromSell, xp = FromXP,
}

--- A riddle made from a fact about the player's game, or nil when the fact doesn't suit the grade
--- or its text isn't plain (see the file header).
---@param fact table
---@param options table grade (0..6) and random, as for Generate
---@return table? puzzle
function Puzzles.FromFact(fact, options)
    if type(fact) ~= "table" or type(options) ~= "table" or type(options.random) ~= "function" then
        return nil
    end
    local make = Makers[fact.type]
    local grade = WholeNumber(options.grade, 0, 6)
    if not make or not grade then
        return nil
    end
    return make(fact, grade, options)
end
