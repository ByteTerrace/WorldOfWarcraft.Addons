local addonName, ns = ...

-- The reading generators: one function per reading kind in ScholarWords.kinds, registered in Kit.Generators for
-- Generate (ScholarPuzzles.lua, which loads first). Their text and word banks are ns.ScholarReadingWords
-- (ScholarReadingWords.lua) and their stories ns.ScholarStoryWords (ScholarStoryWords.lua), which load first too. Like
-- ScholarPuzzles.lua, they're pure.
--
-- Every riddle teaches: each wrong choice carries why it's wrong, and the wrong choices are the real confusions where a
-- bank has them: a word that starts like the target but ends differently, a letter whose sound is close, the same
-- letters turned around, a word with the new letter in the wrong place, the opposite in a synonym riddle, one letter of
-- a letter team or a team split into two sounds, and a blend with a letter dropped. A why never names the answer.
--
-- A heard story (reading.listenStory) is never shown: its speech is the story and the question, and its text sets
-- speakChoices, so ScholarView says each choice after it.

-- The two-letter spellings of one first sound (sh in ship), so "ship" never starts like "sun".
local Digraphs = { ch = true, kn = true, ph = true, sh = true, th = true, wh = true, wr = true }
-- A three-letter word's why templates, by the first place a look-alike differs from it.
local Places = { "whyStart", "whyMiddle", "whyEnd" }

-- How a riddle names the two places a letter team can be in a word, and swap is the other place.
local TeamPlaces = {
    finish = { has = "ends with", place = "end", swap = "start", which = "last" },
    start = { has = "starts with", place = "start", swap = "finish", which = "first" },
}

local concat = table.concat
local find = string.find
local gmatch = string.gmatch
local gsub = string.gsub
local insert = table.insert
local ipairs = ipairs
local max = math.max
local min = math.min
local pairs = pairs
local remove = table.remove
local sort = table.sort
local sub = string.sub
local type = type
local unpack = unpack

local Kit = ns.Puzzles.Kit
local Chance = Kit.Chance
local Fill = Kit.Fill
local Finish = Kit.Finish
local Generators = Kit.Generators
local Pick = Kit.Pick
local ScholarReadingWords = ns.ScholarReadingWords
local ScholarStoryWords = ns.ScholarStoryWords
local Shuffle = Kit.Shuffle
local Text = ScholarReadingWords.text
local Words = Kit.Words

-- Each letter team by its letters, and every team and place a riddle may ask where its sound is.
local PlaceRiddles = {}
local Teams = {}

for _, team in ipairs(ScholarReadingWords.digraphs) do
    Teams[team[1]] = team

    for _, place in ipairs({ "start", "finish" }) do
        if team[place] and not team.like then
            PlaceRiddles[#PlaceRiddles + 1] = { team, place }
        end
    end
end

-- How many of each letter word has.
local function Counts(word)
    local counts = {}

    for i = 1, #word do
        local letter = sub(word, i, i)

        counts[letter] = ((counts[letter] or 0) + 1)
    end

    return counts
end

-- Where long has the one letter short leaves out, or nil when short isn't long with one letter left out.
local function DroppedAt(short, long)
    if #long ~= (#short + 1) then
        return nil
    end

    for i = 1, #long do
        if (sub(long, 1, i - 1) .. sub(long, i + 1)) == short then
            return i
        end
    end
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

-- Each look-alike of target with why it isn't target: the first place it differs, from text's whyStart, whyMiddle, or
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
    elseif DroppedAt(choice, word) then
        return text.whyDropped
    elseif DroppedAt(word, choice) then
        return text.whyAdded
    end

    return text.whySounds
end

-- Up to three sounds groups other than group, for wrong choices, and whether the first sounds close to it (p for b). A
-- group spelling group's own sound with another letter (k for c) is never one.
local function SoundGroups(state, group)
    local groups = ScholarReadingWords.sounds
    local out = {}
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
    local name = state.context.name
    local zone = state.context.zone

    return {
        hero = ((name and Chance(state, 2) and name) or entry.hero or Pick(state, Words.heroes)[2]),
        place = ((zone and Chance(state, 2) and zone) or entry.place or Pick(state, Words.places)),
    }
end

-- The wrong choices for changing vars.was to vars.now in vars.from: the word unchanged, then bank words with the new
-- letter that changed too much or put it in the wrong place, then look-alikes without it when the bank runs short.
local function SwapWrongs(state, text, vars)
    local target = vars.target
    local now = vars.now
    local wrongs = { { vars.from, why = Fill(text.whySame, vars) } }
    local taken = { [vars.from] = true, [target] = true }

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

-- Distractors never look like rhymes (no shared last two letters or rime), so the ear decides. One starts like the
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

-- Blending sounds ("c - a - t"), or at higher levels changing one letter ("cat" to "hat"). A short word is said aloud.
-- The four choices are it and three words that look alike.
Generators["reading.listen"] = function(state)
    local text = Text.listen
    local target = Pick(state, ScholarReadingWords.cvc)
    local wrongs = LookAlikeWhys(text, target, LookAlikes(state, target))
    local vars = { first = sub(target, 1, 1), sounds = concat(Letters(target), " - "), target = target }

    vars.said = Fill(Pick(state, text.speeches), vars)

    return Finish(state, "reading.listen", text, vars, target, wrongs)
end

-- A word is said aloud. The four choices are its first letter and three others, one of them a letter whose sound is
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
-- unscrambling finds the answer. The clue is the second miss's step.
Generators["reading.unscramble"] = function(state)
    local text = Text.unscramble
    local tier = (((state.grade == 2) and ({ 1, 1, 2 })[state.level]) or ({ 2, 3, 3 })[state.level])
    local entry = Pick(state, Tier(ScholarReadingWords.unscramble, tier, tier))
    local word = entry[1]
    local letters = Shuffle(state, Letters(entry[1]))

    if concat(letters) == word then
        local first = remove(letters, 1)

        letters[#letters + 1] = first
    end

    local have = Counts(word)
    local wrongs = {}

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
    local word = entry[1]
    local twin = entry[5 - field]
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

-- Level 1 asks each story's first (most literal) question. A question's type (literal, inference, main, sequence, or
-- vocab) picks its hint, step, explanation, and praise. Its clue is the part of the story that holds the answer. Grades
-- 2 and 3 read the short stories (tier 1), and grades 4 to 6 the longer ones. Grade 3's level 3 reaches up to the
-- longer ones, and the older grades' level 1 reaches down to the short ones.
Generators["reading.story"] = function(state)
    local lo = ((((state.grade >= 4) and (state.level > 1)) and 2) or 1)
    local hi = ((((state.grade <= 2) or ((state.grade == 3) and (state.level < 3))) and 1) or 2)
    local story = Pick(state, Tier(ScholarStoryWords.stories, lo, hi))
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

    return Finish(state, "reading.story", ScholarStoryWords.text.story[question.type], vars, vars.answer, wrongs)
end

-- The sentence or sentences of story that hold clue, trimmed: what a heard story's explanation shows.
local function Line(story, clue)
    local from, to = find(story, clue, 1, true)
    local out = {}

    for first, sentence, last in gmatch(story, "()([^%.!%?]*[%.!%?]+\"?)()") do
        if (first <= to) and (last > from) then
            out[#out + 1] = (gsub(sentence, "^%s+", ""))
        end
    end

    return concat(out, " ")
end

-- A story the Owl Sage says aloud, for children still learning to read: the speech is the story and the question, and
-- the choices are said after it (speakChoices). Level 1 asks each story's first (most literal) question. The step
-- quotes the clue, which never holds a literal or inference answer.
Generators["reading.listenStory"] = function(state)
    local story = Pick(state, ScholarStoryWords.heard)
    local question = (((state.level == 1) and story[2]) or story[state.roll(2, #story)])

    local vars = {
        clue = (gsub(question.clue, "[%.!%?]+$", "")), line = Line(story[1], question.clue), question = question[1],
        story = story[1],
    }

    local text = ScholarStoryWords.text.heard[question.type]

    return Finish(state, "reading.listenStory", text, vars, question[2], { question[3], question[4], question[5] })
end

-- The letters at a word's start or end ("start" or "finish"), n of them.
local function AtPlace(word, place, n)
    return (((place == "start") and sub(word, 1, n)) or sub(word, -n))
end

-- The letter team a word is built around and where it is ("start" or "finish").
local function TeamOf(word)
    for _, team in ipairs(ScholarReadingWords.digraphs) do
        for _, place in ipairs({ "start", "finish" }) do
            if team[place] and (AtPlace(word, place, 2) == team[1]) then
                return team, place
            end
        end
    end
end

-- Which letters spell a word's first (or last) sound: the team, among one of its letters, a near sound, and another
-- team.
local function TeamSpell(state, text)
    local team = Pick(state, ScholarReadingWords.digraphs)
    local place = ((team.start and "start") or "finish")

    if team.start and team.finish and Chance(state, 2) then
        place = "finish"
    end

    local said = TeamPlaces[place]

    local vars = {
        digraph = team[1], has = said.has, note = team.note, sound = team.sound,
        team = ((team.like and text.spell.likeTeam) or text.spell.newTeam), which = said.which,
        word = Pick(state, team[place]),
    }

    local wrongs = {}

    for i, wrong in ipairs(team.spell) do
        wrongs[i] = { wrong[1], why = Fill(wrong.why, vars) }
    end

    return Finish(state, "reading.digraph", text.spell, vars, team[1], wrongs)
end

-- A word's sounds, in order: the team is one, and every other letter one each ("sh", "i", "p" for ship).
local function TeamUnits(word, team, place)
    local units = Letters(((place == "start") and sub(word, 3)) or sub(word, 1, -3))

    insert(units, ((place == "start") and 1) or (#units + 1), team[1])

    return units
end

-- A copy of vars with extra's fields on top.
local function With(vars, extra)
    local out = {}

    for key, value in pairs(vars) do
        out[key] = value
    end

    for key, value in pairs(extra) do
        out[key] = value
    end

    return out
end

-- Which word starts (or ends) with a team's sound. The wrong choices are words with only one of its letters there, a
-- near sound, another team, or the team at the other end. The step tries the first of them.
local function TeamPlace(state, text)
    local riddle = Pick(state, PlaceRiddles)
    local team = riddle[1]
    local place = riddle[2]
    local said = TeamPlaces[place]
    local words = Shuffle(state, team[place])

    local named = {
        digraph = team[1], has = said.has, otherPlace = TeamPlaces[said.swap].place, place = said.place,
        which = said.which,
    }

    local first = nil
    local rest = {}

    local function Add(list, template, extra, sound)
        if list and list[place] then
            local word = Pick(state, list[place])
            local candidate = { word, sound = sound, why = Fill(template, With(named, With(extra, { choice = word }))) }

            first = (first or (sound and candidate))

            if candidate ~= first then
                rest[#rest + 1] = candidate
            end
        end
    end

    Add(team.alone, text.whyAlone, { letter = sub(team[1], 1, 1) }, sub(team[1], 1, 1))
    Add(team.half, text.whyAlone, { letter = sub(team[1], 2, 2) }, sub(team[1], 2, 2))

    if team.close then
        Add(team.close, team.close.why, {}, team.close.letters)
    end

    for _, other in ipairs(team.other) do
        Add(Teams[other], text.whyOther, { other = other }, other)
    end

    if team[said.swap] then
        Add({ [place] = team[said.swap] }, text.whyPlace, {})
    end

    local wrongs = { first }

    for _, candidate in ipairs(Shuffle(state, rest)) do
        if #wrongs < 3 then
            wrongs[#wrongs + 1] = candidate
        end
    end

    local vars = With(named, {
        example = words[2], note = team.note, target = words[1], tried = first[1], triedSound = first.sound,
    })

    return Finish(state, "reading.digraph", text.place, vars, words[1], wrongs)
end

-- Which shows a word's sounds one by one: "sh - i - p". The team split into two sounds is always a choice; the others
-- keep one of its letters, put another team in, or leave a chunk of sounds together.
local function TeamSplit(state, text)
    local word = Pick(state, ScholarReadingWords.digraphWords)[1]
    local team, place = TeamOf(word)
    local units = TeamUnits(word, team, place)
    local at = (((place == "start") and 1) or #units)
    local first = sub(team[1], 1, 1)
    local second = sub(team[1], 2, 2)

    -- The sounds with the team's place holding parts instead.
    local function Swapped(...)
        local out = {}

        for i, unit in ipairs(units) do
            if i == at then
                for _, part in ipairs({ ... }) do
                    out[#out + 1] = part
                end
            else
                out[#out + 1] = unit
            end
        end

        return concat(out, " - ")
    end

    local named = { digraph = team[1], first = first, second = second }
    local split = { Swapped(first, second), why = Fill(text.split.whySplit, named) }
    local others = {}

    if not team.like then
        others[#others + 1] = { Swapped(first), why = Fill(text.split.whyAlone, { letter = first }) }
    end

    if team.other[1] then
        local other = team.other[1]

        others[#others + 1] = { Swapped(other), why = Fill(text.split.whyOther, With(named, { other = other })) }
    end

    local chunk = (((place == "start") and concat(units, "", 2)) or concat(units, "", 1, #units - 1))
    local chunked = (((place == "start") and { units[1], chunk }) or { chunk, units[#units] })

    others[#others + 1] = { concat(chunked, " - "), why = Fill(text.split.whyChunk, { chunk = chunk }) }
    local wrongs = { split }

    for _, other in ipairs(Shuffle(state, others)) do
        if #wrongs < 3 then
            wrongs[#wrongs + 1] = other
        end
    end

    local vars = { count = #units, digraph = team[1], note = team.note, sounds = concat(units, " - "), word = word }

    return Finish(state, "reading.digraph", text.split, vars, vars.sounds, wrongs)
end

-- Why choice isn't a team riddle's word: the team in its place but other sounds changed, a near sound or another team
-- in the team's place, or one of its letters alone there. Nil for any other change, which the kind's wrong template
-- names.
local function TeamWhy(text, team, place, choice)
    local named = { choice = choice, digraph = team[1], has = TeamPlaces[place].has }
    local two = AtPlace(choice, place, 2)
    local close = team.close

    if two == team[1] then
        return Fill(text.whyRest, named)
    elseif close and (AtPlace(choice, place, #close.letters) == close.letters) then
        return Fill(close.why, named)
    elseif Teams[two] and Teams[two][place] then
        return Fill(text.whyOther, With(named, { other = two }))
    end

    local one = AtPlace(choice, place, 1)

    if not team.like and ((one == sub(team[1], 1, 1)) or (one == sub(team[1], 2, 2))) then
        return Fill(text.whyAlone, With(named, { letter = one }))
    end
end

-- Blending a word with a letter team in it: "sh - i - p".
local function TeamJoin(state, text)
    local entry = Pick(state, ScholarReadingWords.digraphWords)
    local target = entry[1]
    local team, place = TeamOf(target)
    local units = TeamUnits(target, team, place)
    local wrongs = {}

    for i = 2, 4 do
        wrongs[#wrongs + 1] = { entry[i], why = TeamWhy(text, team, place, entry[i]) }
    end

    local vars = {
        back = concat(units, "", 3), digraph = team[1], front = (units[1] .. units[2]), note = team.note,
        place = TeamPlaces[place].place, sounds = concat(units, " - "), target = target,
    }

    return Finish(state, "reading.digraph", text.join, vars, target, wrongs)
end

-- Letter teams (sh, ch, th, wh, ck, ng): level 1 blends a word or finds where a team's sound is. Higher levels also
-- spell a sound and split a word into its sounds.
Generators["reading.digraph"] = function(state)
    local variants = { TeamJoin, TeamPlace, TeamSpell, TeamSplit }

    return variants[state.roll(1, ((state.level == 1) and 2) or 4)](state, Text.digraph)
end

-- Whether a letter is a consonant: y counts as a vowel, and no blend word has one.
local function Consonant(letter)
    return not find("aeiouy", letter, 1, true)
end

-- The consonant blend of word that holds position i (its first two letters or its last two), or nil.
local function Pair(word, i)
    local n = #word

    if (i <= 2) and Consonant(sub(word, 1, 1)) and Consonant(sub(word, 2, 2)) then
        return sub(word, 1, 2)
    elseif (i >= (n - 1)) and Consonant(sub(word, n - 1, n - 1)) and Consonant(sub(word, n, n)) then
        return sub(word, n - 1)
    end
end

-- Why choice isn't the blend word target: a letter of a blend dropped, a sound added, the letters turned around, or a
-- sound swapped (in the blend or elsewhere). Nil for any other change, which the kind's wrong template names.
local function BlendWhy(text, target, choice)
    local dropped = DroppedAt(choice, target)
    local added = DroppedAt(target, choice)

    if dropped and Pair(target, dropped) then
        local named = { choice = choice, letter = sub(target, dropped, dropped), pair = Pair(target, dropped) }

        return Fill(text.whyDropped, named)
    elseif added then
        return Fill(text.whyAdded, { choice = choice, letter = sub(choice, added, added) })
    elseif Sorted(choice) == Sorted(target) then
        return Fill(text.whyOrder, { choice = choice })
    elseif #choice == #target then
        local i = FirstDifference(choice, target)
        local named = { choice = choice, has = sub(choice, i, i), pair = Pair(target, i), want = sub(target, i, i) }

        return Fill(((named.pair and text.whySwap) or text.whyLetter), named)
    end
end

-- Consonant blends: blending a word's sounds ("f - l - a - g"), or at higher levels adding the sound a word dropped
-- from a blend ("lag" with "f" at the start). The dropped-letter word is always a choice.
Generators["reading.blend"] = function(state)
    local text = Text.consonantBlend
    local entry = Pick(state, ScholarReadingWords.blends)
    local target = entry[1]
    local sounds = concat(Letters(target), " - ")
    local wrongs = {}
    local froms = {}

    for i = 2, 4 do
        local dropped = DroppedAt(entry[i], target)

        if dropped and Pair(target, dropped) then
            froms[#froms + 1] = entry[i]
        end
    end

    if (state.level == 1) or Chance(state, 2) then
        local cut = ((Pair(target, 1) and 3) or (#target - 2))

        for i = 2, 4 do
            wrongs[#wrongs + 1] = { entry[i], why = BlendWhy(text, target, entry[i]) }
        end

        local vars = {
            back = sub(target, cut + 1), front = sub(target, 1, cut), pair = (Pair(target, 1) or Pair(target, #target)),
            sounds = sounds, target = target,
        }

        return Finish(state, "reading.blend", text.join, vars, target, wrongs)
    end

    local from = Pick(state, froms)
    local at = DroppedAt(from, target)
    local where = Fill(text.add.whereAfter, { prev = sub(target, at - 1, at - 1) })

    if at == 1 then
        where = text.add.whereStart
    elseif at == #target then
        where = text.add.whereEnd
    end

    local vars = {
        from = from, fromSounds = concat(Letters(from), " - "), letter = sub(target, at, at), pair = Pair(target, at),
        sounds = sounds, target = target, where = where,
    }

    wrongs[1] = { from, why = Fill(text.add.whySame, With(vars, { choice = from })) }

    for i = 2, 4 do
        if entry[i] ~= from then
            wrongs[#wrongs + 1] = { entry[i], why = BlendWhy(text, target, entry[i]) }
        end
    end

    return Finish(state, "reading.blend", text.add, vars, target, wrongs)
end
