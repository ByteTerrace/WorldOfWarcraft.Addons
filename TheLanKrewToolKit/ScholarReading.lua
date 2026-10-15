local addonName, ns = ...

-- The reading generators: one function per reading kind in ScholarWords.kinds, registered in Kit.Generators for
-- Generate (ScholarPuzzles.lua, which loads first). Pure like ScholarPuzzles.lua.

local concat, sort = table.concat, table.sort
local gsub, sub = string.gsub, string.sub
local ipairs, unpack = ipairs, unpack
local max, min = math.max, math.min

local Kit = ns.Puzzles.Kit
local Chance, Fill, Finish, Pick, Shuffle = Kit.Chance, Kit.Fill, Kit.Finish, Kit.Pick, Kit.Shuffle
local Generators, Words = Kit.Generators, Kit.Words

local function Letters(word)
    local list = {}

    for i = 1, #word do
        list[i] = sub(word, i, i)
    end

    return list
end

-- A random word (from index first on) from each entry of a bank but one, for distractors.
local function OneFromEach(state, bank, except, first, keep)
    local out = {}

    for _, entry in ipairs(bank) do
        local word = ((entry ~= except) and entry[state.roll(first, #entry)])

        if word and (not keep or keep(word)) then
            out[#out + 1] = word
        end
    end

    return out
end

-- Entries of a tiered bank with lo <= t <= hi (and, when given, a value at index field).
local function Tier(list, lo, hi, field)
    local out = {}

    for _, entry in ipairs(list) do
        if (entry.t >= lo) and (entry.t <= hi) and (not field or entry[field]) then
            out[#out + 1] = entry
        end
    end

    return out
end

-- Distractors never look like rhymes (no shared last two letters), so the ear decides.
Generators["reading.rhyme"] = function(state)
    local families = Tier(Words.rhymes, 1, (((state.grade == 0) or (state.level == 1)) and 1) or 2)
    local family = Pick(state, families)
    local words = Shuffle(state, family)
    local ending = sub(words[1], -2)
    local wrongs = OneFromEach(state, families, family, 1, function(word) return (sub(word, -2) ~= ending) end)

    return Finish(state, "reading.rhyme", Words.reading.rhyme, { correct = words[2], target = words[1] }, words[2], wrongs)
end

Generators["reading.sound"] = function(state)
    local group = Pick(state, Words.sounds)
    local words = Shuffle(state, { unpack(group, 2) })
    local vars = { correct = words[2], letter = group[1], target = words[1] }

    return Finish(state, "reading.sound", Words.reading.sound, vars, words[2], OneFromEach(state, Words.sounds, group, 2))
end

-- The entry is { word, sentence, three misspellings }.
local function Spelling(state, kind, key, entry)
    local vars = { sentence = entry[2], spelled = concat(Letters(entry[1]), "-"), word = entry[1] }

    return Finish(state, kind, Words.reading[key], vars, entry[1], { entry[3], entry[4], entry[5] })
end

Generators["reading.sight"] = function(state)
    local lo = ((((state.grade == 1) and (state.level > 1)) and 2) or 1)
    local hi = ((((state.grade == 0) and (state.level < 3)) and 1) or 2)

    return Spelling(state, "reading.sight", "sight", Pick(state, Tier(Words.sight, lo, hi)))
end

-- How many positions of two same-length words match.
local function Matches(a, b)
    local n = 0

    for i = 1, #a do
        if sub(a, i, i) == sub(b, i, i) then
            n = (n + 1)
        end
    end

    return n
end

-- Three bank words that look like target: two letters in place first, then one.
local function LookAlikes(state, target, except)
    local out = {}

    for want = 2, 1, -1 do
        for _, word in ipairs(Shuffle(state, Words.cvc)) do
            if (#out < 3) and (word ~= target) and (word ~= except) and (Matches(word, target) == want) then
                out[#out + 1] = word
            end
        end
    end

    return out
end

-- Blending sounds ("c - a - t"), or at higher levels changing one letter ("cat" to "hat").
Generators["reading.cvc"] = function(state)
    local target = Pick(state, Words.cvc)

    if ((state.grade == 1) and (state.level > 1)) or ((state.grade == 0) and (state.level == 3)) then
        for _, from in ipairs(Shuffle(state, Words.cvc)) do
            if Matches(from, target) == 2 then
                local i = 1

                while sub(from, i, i) == sub(target, i, i) do
                    i = (i + 1)
                end

                local wrongs = LookAlikes(state, target, from)

                wrongs[3] = from
                local vars = { from = from, now = sub(target, i, i), target = target, was = sub(from, i, i) }

                return Finish(state, "reading.cvc", Words.reading.swap, vars, target, wrongs)
            end
        end
    end

    local vars = { sounds = concat(Letters(target), " - "), target = target }

    return Finish(state, "reading.cvc", Words.reading.blend, vars, target, LookAlikes(state, target))
end

local function Sorted(word)
    local list = Letters(word)

    sort(list)

    return concat(list)
end

-- Distractors are other bank words of about the same length that aren't anagrams of the answer.
Generators["reading.unscramble"] = function(state)
    local tier = (((state.grade == 2) and ({ 1, 1, 2 })[state.level]) or ({ 2, 3, 3 })[state.level])
    local entry = Pick(state, Tier(Words.unscramble, tier, tier))
    local word, letters = entry[1], Shuffle(state, Letters(entry[1]))

    if concat(letters) == word then
        letters[1], letters[#letters] = letters[#letters], letters[1]
    end

    local wrongs = {}

    for pass = 1, 2 do
        for _, other in ipairs(Shuffle(state, Words.unscramble)) do
            local near = (((#other[1] - #word) ^ 2) <= 1)

            if (#wrongs < 3) and (near == (pass == 1)) and (Sorted(other[1]) ~= Sorted(word)) then
                wrongs[#wrongs + 1] = other[1]
            end
        end
    end

    local key = ((((state.grade == 3) and (state.level == 3)) and "unscrambleNoClue") or "unscramble")
    local vars = { clue = entry[2], letters = concat(letters, " "), word = word }
    local puzzle = Finish(state, "reading.unscramble", Words.reading[key], vars, word, wrongs)

    -- ScholarView draws them as letter tiles.
    puzzle.tiles = letters

    return puzzle
end

-- Synonym or antonym (field 2 or 3 of an entry). The other kind of match is always one of the distractors; the rest
-- come from other entries, which never share a meaning.
local function Meaning(state, kind, field)
    local pool = Tier(Words.synonyms, 1, (((state.grade == 2) and (state.level < 3)) and 1) or 2, field)
    local entry = Pick(state, pool)
    local wrongs = { entry[5 - field] }

    for _, other in ipairs(Shuffle(state, pool)) do
        if (other ~= entry) and (#wrongs < 3) then
            wrongs[#wrongs + 1] = other[field]
        end
    end

    local vars = { correct = entry[field], word = entry[1] }

    return Finish(state, "reading." .. kind, Words.reading[kind], vars, entry[field], wrongs)
end

Generators["reading.synonym"] = function(state)
    return Meaning(state, "synonym", 2)
end

Generators["reading.antonym"] = function(state)
    return Meaning(state, "antonym", 3)
end

Generators["reading.spelling"] = function(state)
    local tier = ((((state.grade == 2) or (state.level == 1)) and 1) or 2)

    return Spelling(state, "reading.spelling", "spelling", Pick(state, Tier(Words.spelling, tier, tier)))
end

-- An entry of a grade 4 to 6 bank, two tiers wide, climbing with grade and level.
local function Advanced(state, bank)
    local cap = min(3, (state.grade - 4) + state.level)

    return Pick(state, Tier(bank, max(1, cap - 1), cap))
end

-- The player's name and zone sometimes, else the entry's defaults or stock ones.
local function StoryVars(state, entry)
    local name, zone = state.context.name, state.context.zone

    return {
        hero = ((name and Chance(state, 2) and name) or entry.hero or Pick(state, Words.heroes)[2]),
        place = ((zone and Chance(state, 2) and zone) or entry.place or Pick(state, Words.places)),
    }
end

Generators["reading.vocab"] = function(state)
    local entry = Advanced(state, Words.vocab)
    local vars = { meaning = entry[3], sentence = entry[2], word = entry[1] }

    return Finish(state, "reading.vocab", Words.reading.vocab, vars, entry[3], { entry[4], entry[5], entry[6] })
end

Generators["reading.blank"] = function(state)
    local entry = Advanced(state, Words.blanks)
    local sentence = Fill(entry[1], StoryVars(state, entry))
    local vars = { filled = (gsub(sentence, "___", entry[2])), sentence = sentence }

    return Finish(state, "reading.blank", Words.reading.blank, vars, entry[2], { entry[3], entry[4], entry[5] })
end

-- Level 1 asks each story's first (most literal) question.
Generators["reading.story"] = function(state)
    local story = Pick(state, Words.stories)
    local vars = StoryVars(state, story)
    local question = (((state.level == 1) and story[2]) or story[state.roll(2, #story)])
    local out = { answer = Fill(question[2], vars), question = Fill(question[1], vars), story = Fill(story[1], vars) }
    local wrongs = { Fill(question[3], vars), Fill(question[4], vars), Fill(question[5], vars) }

    return Finish(state, "reading.story", Words.reading.story, out, out.answer, wrongs)
end
