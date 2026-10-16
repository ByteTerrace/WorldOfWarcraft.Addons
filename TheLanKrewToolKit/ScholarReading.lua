local addonName, ns = ...

-- The reading generators: one function per reading kind in ScholarWords.kinds, registered in Kit.Generators for
-- Generate (ScholarPuzzles.lua, which loads first). Their text and word banks are ns.ScholarReadingWords
-- (ScholarReadingWords.lua, which loads first too). Pure like ScholarPuzzles.lua.
--
-- Every riddle teaches: each wrong choice carries why it's wrong, and the wrong choices are the real confusions where a
-- bank has them: a word that starts like the target but ends differently, a letter whose sound is close, the same
-- letters turned around, a word with the new letter in the wrong place, the opposite in a synonym riddle. A why never
-- names the answer.

-- The two-letter spellings of one first sound (sh in ship), so "ship" never starts like "sun".
local Digraphs = { ch = true, kn = true, ph = true, sh = true, th = true, wh = true, wr = true }
-- A three-letter word's why templates, by the first place a look-alike differs from it.
local Places = { "whyStart", "whyMiddle", "whyEnd" }

local concat, remove, sort = table.concat, table.remove, table.sort
local find, gsub, sub = string.find, string.gsub, string.sub
local ipairs, type, unpack = ipairs, type, unpack
local max, min = math.max, math.min

local Kit = ns.Puzzles.Kit
local Chance, Fill, Finish, Pick, Shuffle = Kit.Chance, Kit.Fill, Kit.Finish, Kit.Pick, Kit.Shuffle
local ScholarReadingWords = ns.ScholarReadingWords
local Generators, Text, Words = Kit.Generators, ScholarReadingWords.text, Kit.Words

-- How many of each letter word has.
local function Counts(word)
    local counts = {}

    for i = 1, #word do
        local letter = sub(word, i, i)

        counts[letter] = ((counts[letter] or 0) + 1)
    end

    return counts
end

-- Whether short is long with one letter left out.
local function Dropped(short, long)
    if #long ~= (#short + 1) then
        return false
    end

    local at = 1

    for i = 1, #long do
        if sub(short, at, at) == sub(long, i, i) then
            at = (at + 1)
        end
    end

    return (at > #short)
end

-- The first place two same-length words differ.
local function FirstDifference(a, b)
    for i = 1, #a do
        if sub(a, i, i) ~= sub(b, i, i) then
            return i
        end
    end
end

-- The letter or digraph a word's first sound is spelled with: "sh" for ship, "s" for sun.
local function FirstSound(word)
    local two = sub(word, 1, 2)

    return ((Digraphs[two] and two) or sub(word, 1, 1))
end

local function Letters(word)
    local list = {}

    for i = 1, #word do
        list[i] = sub(word, i, i)
    end

    return list
end

-- Each look-alike of target with why it isn't target: the first place it differs, from text's whyStart, whyMiddle or
-- whyEnd ({has} is its letter there, {want} target's).
local function LookAlikeWhys(text, target, words)
    local out = {}

    for i, word in ipairs(words) do
        local at = FirstDifference(word, target)
        local vars = { choice = word, has = sub(word, at, at), want = sub(target, at, at) }

        out[i] = { word, why = Fill(text[Places[at]], vars) }
    end

    return out
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
        for _, word in ipairs(Shuffle(state, ScholarReadingWords.cvc)) do
            if (#out < 3) and (word ~= target) and (word ~= except) and (Matches(word, target) == want) then
                out[#out + 1] = word
            end
        end
    end

    return out
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

-- A word from its first vowel on: "at" in cat, "ight" in night.
local function Rime(word)
    return (gsub(word, "^[^aeiou]+", ""))
end

-- Whether two words rhyme, or look as if they might: the same last two letters, or the same rime.
local function Rhymes(a, b)
    return ((sub(a, -2) == sub(b, -2)) or (Rime(a) == Rime(b)))
end

local function Sorted(word)
    local list = Letters(word)

    sort(list)

    return concat(list)
end

-- Why a misspelling of word is wrong: the right letters in the wrong order, one left out, one added, or a spelling that
-- only sounds right.
local function MisspellingWhy(text, word, choice)
    if Sorted(choice) == Sorted(word) then
        return text.whyOrder
    elseif Dropped(choice, word) then
        return text.whyDropped
    elseif Dropped(word, choice) then
        return text.whyAdded
    end

    return text.whySounds
end

-- Up to three sounds groups other than group, for wrong choices, and whether the first sounds close to it (p for b). A
-- group spelling group's own sound with another letter (k for c) is never one.
local function SoundGroups(state, group)
    local groups, out = ScholarReadingWords.sounds, {}
    local near = (group.near or "")

    local function Other(other)
        return ((other ~= group) and (other[1] ~= group.like) and (other ~= out[1]))
    end

    for _, other in ipairs(Shuffle(state, groups)) do
        if (#out == 0) and Other(other) and find(near, other[1], 1, true) then
            out[1] = other
        end
    end

    local close = (out[1] ~= nil)

    for _, other in ipairs(Shuffle(state, groups)) do
        if (#out < 3) and Other(other) then
            out[#out + 1] = other
        end
    end

    return out, close
end

-- The sound a sounds group's letter makes, as a riddle names it: "b", or short "a".
local function SoundName(group)
    return (group.name or ("\"" .. group[1] .. "\""))
end

-- A word that starts like target but doesn't rhyme with it ("dog" for dig), from the short-word banks, or nil.
local function StartsLike(state, target)
    local pool = {}

    for _, family in ipairs(ScholarReadingWords.rhymes) do
        for _, word in ipairs(family) do
            pool[#pool + 1] = word
        end
    end

    for _, word in ipairs(ScholarReadingWords.cvc) do
        pool[#pool + 1] = word
    end

    for _, word in ipairs(Shuffle(state, pool)) do
        if (FirstSound(word) == FirstSound(target)) and not Rhymes(word, target) then
            return word
        end
    end
end

-- The player's name and zone sometimes, else the entry's defaults or stock ones.
local function StoryVars(state, entry)
    local name, zone = state.context.name, state.context.zone

    return {
        hero = ((name and Chance(state, 2) and name) or entry.hero or Pick(state, Words.heroes)[2]),
        place = ((zone and Chance(state, 2) and zone) or entry.place or Pick(state, Words.places)),
    }
end

-- The wrong choices for changing vars.was to vars.now in vars.from: the word unchanged, then bank words with the new
-- letter that changed too much or put it in the wrong place, then look-alikes without it when the bank runs short.
local function SwapWrongs(state, text, vars)
    local target, now = vars.target, vars.now
    local wrongs, taken = { { vars.from, why = Fill(text.whySame, vars) } }, { [vars.from] = true, [target] = true }

    local function Add(word, template)
        if (#wrongs < 3) and not taken[word] then
            local named = { choice = word, now = now, was = vars.was }

            taken[word], wrongs[#wrongs + 1] = true, { word, why = Fill(template, named) }
        end
    end

    for want = 2, 0, -1 do
        for _, word in ipairs(Shuffle(state, ScholarReadingWords.cvc)) do
            if find(word, now, 1, true) and (Matches(word, target) == want) then
                Add(word, (((sub(word, vars.at, vars.at) == now) and text.whyMore) or text.whyPlace))
            end
        end
    end

    for _, word in ipairs(LookAlikes(state, target, vars.from)) do
        Add(word, text.whyMissing)
    end

    return wrongs
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

-- An entry of a grade 4 to 6 bank, two tiers wide, climbing with grade and level.
local function Advanced(state, bank)
    local cap = min(3, (state.grade - 4) + state.level)

    return Pick(state, Tier(bank, max(1, cap - 1), cap))
end

-- Distractors never look like rhymes (no shared last two letters or rime), so the ear decides; one starts like the
-- target, when a bank has such a word, for the child who matches the start instead of the end.
Generators["reading.rhyme"] = function(state)
    local text = Text.rhyme
    local families = Tier(ScholarReadingWords.rhymes, 1, (((state.grade == 0) or (state.level == 1)) and 1) or 2)
    local family = Pick(state, families)
    local words = Shuffle(state, family)
    local target = words[1]
    local onset = StartsLike(state, target)
    local wrongs = {}

    if onset then
        wrongs[1] = { onset, why = Fill(text.whyOnset, { choice = onset, target = target }) }
    end

    local others = OneFromEach(state, families, family, 1, function(word)
        return ((word ~= onset) and not Rhymes(word, target))
    end)

    for _, word in ipairs(Shuffle(state, others)) do
        if #wrongs < 3 then
            wrongs[#wrongs + 1] = word
        end
    end

    local vars = { correct = words[2], rime = Rime(target), target = target }

    return Finish(state, "reading.rhyme", text, vars, words[2], wrongs)
end

Generators["reading.sound"] = function(state)
    local text = Text.sound
    local group = Pick(state, ScholarReadingWords.sounds)
    local words = Shuffle(state, { unpack(group, 2) })
    local vars = { correct = words[2], sound = SoundName(group), target = words[1] }
    local others, close = SoundGroups(state, group)
    local wrongs = {}

    for i, other in ipairs(others) do
        local word = other[state.roll(2, #other)]
        local named = { choice = word, other = SoundName(other), sound = vars.sound }

        wrongs[i] = { word, why = Fill((((i == 1) and close) and text.whyClose) or text.whyOther, named) }
    end

    return Finish(state, "reading.sound", text, vars, words[2], wrongs)
end

-- The wrong choices are real words: the confusables a reader mixes up (was and saw, the and they), sound-alikes with
-- their own whys in the bank, and words with the same letters turned around. A heart word (one part breaks the rules)
-- gets a hint naming that part.
Generators["reading.sight"] = function(state)
    local lo = ((((state.grade == 1) and (state.level > 1)) and 2) or 1)
    local hi = ((((state.grade == 0) and (state.level < 3)) and 1) or 2)
    local entry = Pick(state, Tier(ScholarReadingWords.sight, lo, hi))
    local word = entry[1]
    local text = ((entry.heart and Text.heart) or Text.sight)
    local wrongs = {}

    for i = 3, 5 do
        local wrong = entry[i]
        local choice = (((type(wrong) == "table") and wrong[1]) or wrong)
        local turned = ((Sorted(choice) == Sorted(word)) and Fill(text.whyOrder, { choice = choice }))

        wrongs[#wrongs + 1] = { choice, why = (((type(wrong) == "table") and wrong.why) or turned or nil) }
    end

    local vars = {
        count = #word, filled = (gsub(entry[2], "___", word)), heart = entry.heart, sentence = entry[2],
        spelled = concat(Letters(word), "-"), start = FirstSound(word), word = word,
    }

    return Finish(state, "reading.sight", text, vars, word, wrongs)
end

-- Blending sounds ("c - a - t"), or at higher levels changing one letter ("cat" to "hat"). A short word is said aloud;
-- the four choices are it and three words that look alike.
Generators["reading.listen"] = function(state)
    local text = Text.listen
    local target = Pick(state, ScholarReadingWords.cvc)
    local wrongs = LookAlikeWhys(text, target, LookAlikes(state, target))
    local vars = { first = sub(target, 1, 1), sounds = concat(Letters(target), " - "), target = target }

    vars.said = Fill(Pick(state, text.speeches), vars)

    return Finish(state, "reading.listen", text, vars, target, wrongs)
end

-- A word is said aloud; the four choices are its first letter and three others, one of them a letter whose sound is
-- close, when there is one.
Generators["reading.listenSound"] = function(state)
    local text = Text.listenSound
    local group = Pick(state, ScholarReadingWords.sounds)
    local target = group[state.roll(2, #group)]
    local others, close = SoundGroups(state, group)
    local wrongs = {}

    for i, other in ipairs(others) do
        local named = { choice = other[1], example = other[2], other = SoundName(other) }

        wrongs[i] = { other[1], why = Fill((((i == 1) and close) and text.whyClose) or text.whyOther, named) }
    end

    local vars = { letter = group[1], sound = SoundName(group), target = target }

    vars.said = Fill(Pick(state, text.speeches), vars)

    return Finish(state, "reading.listenSound", text, vars, group[1], wrongs)
end

Generators["reading.cvc"] = function(state)
    local cvc = ScholarReadingWords.cvc
    local target = Pick(state, cvc)

    if ((state.grade == 1) and (state.level > 1)) or ((state.grade == 0) and (state.level == 3)) then
        for _, from in ipairs(Shuffle(state, cvc)) do
            if Matches(from, target) == 2 then
                local at = FirstDifference(from, target)
                local rest = (sub(from, 1, at - 1) .. "-" .. sub(from, at + 1))
                local vars = { at = at, from = from, now = sub(target, at, at), rest = rest, target = target, was = sub(from, at, at) }

                return Finish(state, "reading.cvc", Text.swap, vars, target, SwapWrongs(state, Text.swap, vars))
            end
        end
    end

    local text = Text.blend
    local vars = { firstTwo = sub(target, 1, 2), last = sub(target, 3), sounds = concat(Letters(target), " - "), target = target }

    return Finish(state, "reading.cvc", text, vars, target, LookAlikeWhys(text, target, LookAlikes(state, target)))
end

-- The wrong choices are near misses: the same length, sharing all but a letter or two with the scrambled ones, so only
-- unscrambling finds the answer; the clue is the second miss's step.
Generators["reading.unscramble"] = function(state)
    local text = Text.unscramble
    local tier = (((state.grade == 2) and ({ 1, 1, 2 })[state.level]) or ({ 2, 3, 3 })[state.level])
    local entry = Pick(state, Tier(ScholarReadingWords.unscramble, tier, tier))
    local word, letters = entry[1], Shuffle(state, Letters(entry[1]))

    if concat(letters) == word then
        local first = remove(letters, 1)

        letters[#letters + 1] = first
    end

    local have, wrongs = Counts(word), {}

    -- Each near miss needs a tile the scramble doesn't have: the why names the first, in the word's order.
    for i = 3, 5 do
        local choice = entry[i]
        local need = Counts(choice)

        for _, letter in ipairs(Letters(choice)) do
            if (need[letter] > (have[letter] or 0)) and not wrongs[i - 2] then
                local named = { choice = choice, have = (have[letter] or 0), letter = letter, need = need[letter] }

                wrongs[i - 2] = { choice, why = Fill(((named.have == 0) and text.whyNone) or text.whyFewer, named) }
            end
        end
    end

    local vars = { clue = entry[2], letters = concat(letters, " "), word = word }
    local puzzle = Finish(state, "reading.unscramble", text, vars, word, wrongs)

    -- ScholarView draws them as letter tiles.
    puzzle.tiles = letters

    return puzzle
end

-- Synonym or antonym (field 2 or 3 of an entry). The other kind of match (the opposite in a synonym riddle) is always a
-- distractor, and so are the entry's near words: related, but not the meaning asked for. Other entries fill in, and no
-- two entries share a meaning.
local function Meaning(state, kind, field)
    local text = Text[kind]
    local pool = Tier(ScholarReadingWords.synonyms, 1, (((state.grade == 2) and (state.level < 3)) and 1) or 2, field)
    local entry = Pick(state, pool)
    local word, twin = entry[1], entry[5 - field]
    local wrongs = {}

    if twin then
        wrongs[1] = { twin, why = Fill(text.whyTwin, { choice = twin, word = word }) }
    end

    for _, near in ipairs(Shuffle(state, entry.near)) do
        wrongs[#wrongs + 1] = { near, why = Fill(text.whyNear, { choice = near, word = word }) }
    end

    for _, other in ipairs(Shuffle(state, pool)) do
        if (other ~= entry) and (#wrongs < 3) then
            wrongs[#wrongs + 1] = other[field]
        end
    end

    return Finish(state, "reading." .. kind, text, { correct = entry[field], word = word }, entry[field], wrongs)
end

Generators["reading.synonym"] = function(state)
    return Meaning(state, "synonym", 2)
end

Generators["reading.antonym"] = function(state)
    return Meaning(state, "antonym", 3)
end

-- The entry is { word, sentence, three misspellings, part (where the tricky part is), tip (how it's spelled) }.
Generators["reading.spelling"] = function(state)
    local text = Text.spelling
    local tier = ((((state.grade == 2) or (state.level == 1)) and 1) or 2)
    local entry = Pick(state, Tier(ScholarReadingWords.spelling, tier, tier))
    local word = entry[1]
    local wrongs = {}

    for i = 3, 5 do
        wrongs[#wrongs + 1] = { entry[i], why = Fill(MisspellingWhy(text, word, entry[i]), { choice = entry[i] }) }
    end

    local vars = { part = entry.part, sentence = entry[2], spelled = concat(Letters(word), "-"), tip = entry.tip, word = word }

    return Finish(state, "reading.spelling", text, vars, word, wrongs)
end

Generators["reading.vocab"] = function(state)
    local entry = Advanced(state, ScholarReadingWords.vocab)
    local vars = { clue = entry.clue, meaning = entry[3], sentence = entry[2], word = entry[1] }

    return Finish(state, "reading.vocab", Text.vocab, vars, entry[3], { entry[4], entry[5], entry[6] })
end

Generators["reading.blank"] = function(state)
    local entry = Advanced(state, ScholarReadingWords.blanks)
    local named = StoryVars(state, entry)
    local sentence = Fill(entry[1], named)
    local vars = { clue = Fill(entry.clue, named), filled = (gsub(sentence, "___", entry[2])), sentence = sentence }

    return Finish(state, "reading.blank", Text.blank, vars, entry[2], { entry[3], entry[4], entry[5] })
end

-- Level 1 asks each story's first (most literal) question. A question's type (literal, inference, main, sequence or
-- vocab) picks its hint, step, explanation and praise; its clue is the part of the story that holds the answer.
Generators["reading.story"] = function(state)
    local story = Pick(state, ScholarReadingWords.stories)
    local named = StoryVars(state, story)
    local question = (((state.level == 1) and story[2]) or story[state.roll(2, #story)])
    local wrongs = {}

    for i = 3, 5 do
        local wrong = question[i]

        if type(wrong) == "table" then
            wrongs[#wrongs + 1] = { Fill(wrong[1], named), why = Fill(wrong.why, named) }
        else
            wrongs[#wrongs + 1] = Fill(wrong, named)
        end
    end

    local vars = {
        answer = Fill(question[2], named), clue = Fill(question.clue, named), question = Fill(question[1], named),
        story = Fill(story[1], named),
    }

    return Finish(state, "reading.story", Text.story[question.type], vars, vars.answer, wrongs)
end
