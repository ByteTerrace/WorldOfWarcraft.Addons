-- Scholar's reading riddles (TheLanKrewToolKit/ScholarReadingWords.lua, ScholarStoryWords.lua, and ScholarReading.lua):
-- the banks' answer keys and shapes, and gates over many generated riddles of each kind. The answer is never findable
-- by its length, no one answer crowds a kind, and the real confusions turn up: a word that starts like the target, a
-- close sound, a near word, one letter of a letter team, and a blend with a letter dropped. Like scholar.test.lua, the
-- puzzle files load on their own with a seeded LCG as the only randomness.

local Files = { "ScholarWords.lua", "ScholarPuzzles.lua", "ScholarReadingWords.lua", "ScholarStoryWords.lua", "ScholarReading.lua" }
-- Words a vocab meaning may share with its sentence.
local Plain = { about = true, from = true, have = true, that = true, their = true, them = true, they = true, very = true, with = true }
local Types = { inference = true, literal = true, main = true, sequence = true, vocab = true }

local function Fold(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""):lower())
end

local function Load()
    local addon = assert(__addons.TheLanKrewToolKit, "TheLanKrewToolKit isn't an addon")
    local sources = {}

    for i, name in ipairs(Files) do
        for j, file in ipairs(addon.files) do
            if file == name then
                sources[i] = addon.sources[j]
            end
        end

        assert(sources[i], name .. " isn't listed in TheLanKrewToolKit_Camelot.toc")
    end

    Harness.DefineAddOn("ScholarReadingOnly", { as = "TheLanKrewToolKit", files = Files, sources = sources })

    return Harness.New():LoadFiles("ScholarReadingOnly")
end

-- Every reading kind, in the order the grades list them.
local function ReadingKinds(ns)
    local out = {}
    local seen = {}

    for grade = 0, 6 do
        for _, kind in ipairs(ns.ScholarWords.kinds.reading[grade]) do
            if not seen[kind] then
                seen[kind], out[#out + 1] = true, kind
            end
        end
    end

    return out
end

-- Park and Miller's minimal standard LCG.
local function Rng(seed)
    local state = ((seed % 2147483646) + 1)

    return function(m, n)
        state = ((state * 48271) % 2147483647)

        return (m + (state % ((n - m) + 1)))
    end
end

-- Calls fn(puzzle) for seeds riddles of kind at each grade that asks it and each level.
local function EachOfKind(ns, kind, seeds, fn)
    for grade = 0, 6 do
        for _, listed in ipairs(ns.ScholarWords.kinds.reading[grade]) do
            if listed == kind then
                for level = 1, 3 do
                    for seed = 1, seeds do
                        local random = Rng(((seed * 7919) + (grade * 104729)) + (level * 1299709))

                        fn(ns.Puzzles.Generate({ grade = grade, kind = kind, level = level, random = random, subject = "reading" }))
                    end
                end
            end
        end
    end
end

-- How many letters two words share, counting repeats.
local function Shared(a, b)
    local counts = {}
    local n = 0

    for letter in a:gmatch(".") do
        counts[letter] = ((counts[letter] or 0) + 1)
    end

    for letter in b:gmatch(".") do
        if (counts[letter] or 0) > 0 then
            counts[letter], n = (counts[letter] - 1), (n + 1)
        end
    end

    return n
end

local Sorted = use("scholar").Sorted

-- The text of a wrong choice in a bank: a word, or { word, why = ... }.
local function TextOf(wrong)
    return (((type(wrong) == "table") and wrong[1]) or wrong)
end

test("the reading banks are big enough to keep riddles fresh", function()
    local ns = Load()

    local least = {
        [ns.ScholarReadingWords] = {
            blanks = 36, blends = 40, cvc = 100, digraphWords = 35, rhymes = 24, sight = 35, sounds = 24, spelling = 45,
            synonyms = 60, unscramble = 40, vocab = 36,
        },
        [ns.ScholarStoryWords] = { heard = 24, stories = 54 },
    }

    for banks, sizes in pairs(least) do
        for name, size in pairs(sizes) do
            truthy(#banks[name] >= size, ("%s has %d entries, at least %d"):format(name, #banks[name], size))
        end
    end

    local young = 0

    for _, story in ipairs(ns.ScholarStoryWords.stories) do
        young = (young + (((story.t == 1) and 1) or 0))
    end

    truthy(young >= 24, ("%d stories for younger readers, at least 24"):format(young))
end)

test("the reading banks' wrong choices are distinct, plain, short and never the answer", function()
    local ns = Load()
    local banks = ns.ScholarReadingWords

    local function Check(entry, answer, wrongs)
        local seen = { [Fold(answer)] = true }

        for _, wrong in ipairs(wrongs) do
            local text = TextOf(wrong)

            truthy(text:match("^[ -~]+$") and not text:find("[{}|]"), "plain option " .. text)
            truthy(#text <= 40, text .. " fits a choice")
            falsy(seen[Fold(text)], ("distinct option %q for %s"):format(text, entry))
            seen[Fold(text)] = true

            if type(wrong) == "table" then
                truthy(wrong.why:match("^[ -~]+$"), "plain why " .. wrong.why)
            end
        end

        truthy(#answer <= 40, answer .. " fits a choice")
    end

    for _, bank in ipairs({ banks.sight, banks.spelling }) do
        for _, entry in ipairs(bank) do
            Check(entry[1], entry[1], { entry[3], entry[4], entry[5] })
            truthy(entry[2]:find("___", 1, true), "a blank in " .. entry[2])
        end
    end

    for _, entry in ipairs(banks.vocab) do
        Check(entry[1], entry[3], { entry[4], entry[5], entry[6] })
    end

    for _, entry in ipairs(banks.blanks) do
        Check(entry[2], entry[2], { entry[3], entry[4], entry[5] })
        truthy(entry[1]:find("___", 1, true), "a blank in " .. entry[1])
    end

    for _, entry in ipairs(banks.unscramble) do
        Check(entry[1], entry[1], { entry[3], entry[4], entry[5] })
    end

    for _, entry in ipairs(banks.synonyms) do
        Check(entry[1], entry[1], { entry[2], (entry[3] or (entry[2] .. "?")), entry.near[1], entry.near[2] })
    end

    for _, entry in ipairs(banks.blends) do
        Check(entry[1], entry[1], { entry[2], entry[3], entry[4] })
    end

    for _, entry in ipairs(banks.digraphWords) do
        Check(entry[1], entry[1], { entry[2], entry[3], entry[4] })
    end

    for _, team in ipairs(banks.digraphs) do
        Check(team[1], team[1], team.spell)
    end

    for _, bank in ipairs({ ns.ScholarStoryWords.stories, ns.ScholarStoryWords.heard }) do
        for _, story in ipairs(bank) do
            for q = 2, #story do
                Check(story[q][1], story[q][2], { story[q][3], story[q][4], story[q][5] })
            end
        end
    end
end)

test("each story has 2 to 4 sentences and 1 to 3 questions, each typed, with a clue from the story", function()
    local banks = Load().ScholarStoryWords
    local all = {}

    for _, bank in ipairs({ banks.stories, banks.heard }) do
        for _, story in ipairs(bank) do
            all[#all + 1] = story
        end
    end

    for _, story in ipairs(all) do
        local function Named(text)
            return (text:gsub("{hero}", story.hero or "Pip"):gsub("{place}", story.place or "Goldshire"))
        end

        local text = Named(story[1])
        local sentences = select(2, (text .. " "):gsub("[%.!%?]\"? ", ""))

        truthy((sentences >= 2) and (sentences <= 4), ("2 to 4 sentences (%d): %s"):format(sentences, text))
        truthy((#story >= 2) and (#story <= 4), "1 to 3 questions: " .. text)
        eq(story[2].type, "literal", "the first question is literal: " .. story[2][1])

        for q = 2, #story do
            local question = story[q]
            local prompt = (text .. "\n" .. Named(question[1]))

            truthy(Types[question.type], "a known type for " .. question[1])
            truthy(text:find(Named(question.clue), 1, true), ("the clue %q is in the story"):format(question.clue))
            -- A step that equals the answer is dropped, so a clue never is the answer.
            truthy(Fold(question.clue) ~= Fold(question[2]), ("the clue %q isn't the answer"):format(question.clue))
            truthy(#prompt <= 240, ("fits the prompt limit (%d): %s"):format(#prompt, prompt))
        end
    end
end)

test("misspellings are never real words, and sight words' confusables are other real words", function()
    local banks = Load().ScholarReadingWords
    local real = {}

    local function Add(word)
        real[word:lower()] = true
    end

    for _, family in ipairs(banks.rhymes) do
        for _, word in ipairs(family) do
            Add(word)
        end
    end

    for _, group in ipairs(banks.sounds) do
        for i = 2, #group do
            Add(group[i])
        end
    end

    for _, word in ipairs(banks.cvc) do
        Add(word)
    end

    for _, entry in ipairs(banks.synonyms) do
        for _, word in ipairs(entry) do
            Add(word)
        end
    end

    for _, bank in ipairs({ banks.sight, banks.spelling }) do
        for _, entry in ipairs(bank) do
            Add(entry[1])
        end
    end

    for _, entry in ipairs(banks.sight) do
        for i = 3, 5 do
            Add(TextOf(entry[i]))
        end
    end

    for _, entry in ipairs(banks.spelling) do
        for i = 3, 5 do
            falsy(real[entry[i]], entry[i] .. " is not a real word")
        end

        truthy(entry.part and entry.tip, "the tricky part of " .. entry[1] .. " is named")
    end

    for _, entry in ipairs(banks.sight) do
        for i = 3, 5 do
            truthy(TextOf(entry[i]):match("^%l+$") and (TextOf(entry[i]) ~= entry[1]), "a real word other than " .. entry[1])
        end
    end
end)

test("a vocab meaning never repeats its sentence, and every clue comes from its sentence", function()
    local banks = Load().ScholarReadingWords

    for _, entry in ipairs(banks.vocab) do
        local sentence = entry[2]:lower()

        truthy(entry[2]:find(entry.clue, 1, true), ("the clue %q is in the sentence"):format(entry.clue))
        truthy(sentence:find("%f[%a]" .. entry[1] .. "%f[%A]"), "the sentence uses " .. entry[1])

        for word in entry[3]:lower():gmatch("%a+") do
            falsy((#word >= 4) and not Plain[word] and sentence:find("%f[%a]" .. word .. "%f[%A]"),
                ("%q in the meaning of %s gives it away"):format(word, entry[1]))
        end
    end

    for _, entry in ipairs(banks.blanks) do
        truthy(entry[1]:find(entry.clue, 1, true), ("the clue %q is in the sentence"):format(entry.clue))
    end
end)

test("an unscramble's near misses are its length, share all but a letter or two, and none is an anagram", function()
    local banks = Load().ScholarReadingWords

    for _, entry in ipairs(banks.unscramble) do
        local word = entry[1]
        local slack = (((#word >= 6) and 2) or 1)

        truthy(word:match("^%u+$"), word .. " is capitals")

        for i = 3, 5 do
            local miss = entry[i]

            eq(#miss, #word, miss .. " is as long as " .. word)
            truthy(Shared(miss, word) >= (#word - slack), ("%s shares all but %d letters with %s"):format(miss, slack, word))
            truthy(Sorted(miss) ~= Sorted(word), miss .. " isn't an anagram of " .. word)
        end
    end
end)

test("synonym entries never share a word, and near words are neither the meaning nor the opposite", function()
    local banks = Load().ScholarReadingWords
    local owner = {}

    for _, entry in ipairs(banks.synonyms) do
        for _, word in ipairs(entry) do
            falsy(owner[word], word .. " belongs to one synonym entry only")
            owner[word] = true
        end

        eq(#entry.near, 2, "two near words for " .. entry[1])

        for _, near in ipairs(entry.near) do
            truthy((near ~= entry[1]) and (near ~= entry[2]) and (near ~= entry[3]), near .. " is a near word of " .. entry[1])
        end
    end
end)

test("rhyme families don't overlap, short words are three letters, and sounds start with their letter", function()
    local banks = Load().ScholarReadingWords
    local family = {}
    local letters = {}
    local vowels = 0

    for i, words in ipairs(banks.rhymes) do
        for _, word in ipairs(words) do
            falsy(family[word], word .. " belongs to one rhyme family only")
            eq(word:sub(-2), words[1]:sub(-2), word .. " rhymes with " .. words[1])
            family[word] = i
        end
    end

    for _, word in ipairs(banks.cvc) do
        eq(#word, 3, word .. " is three letters")
        falsy(word:match("(%a).*%1"), word .. " has no repeated letter")
    end

    for _, group in ipairs(banks.sounds) do
        letters[group[1]] = group
        vowels = (vowels + (((group.name ~= nil) and 1) or 0))
        truthy(#group >= 5, "at least four words for " .. group[1])

        for i = 2, #group do
            eq(group[i]:sub(1, 1), group[1], group[i] .. " starts with " .. group[1])
        end
    end

    eq(vowels, 5, "every short vowel")

    for _, group in ipairs(banks.sounds) do
        for near in (group.near or ""):gmatch(".") do
            truthy(letters[near], ("%s's close sound %s has words"):format(group[1], near))
        end
    end

    eq(letters.c.like, "k")
    eq(letters.k.like, "c")
end)

test("the answer is the longest choice, or the shortest, in at most 35% of each kind's riddles", function()
    local ns = Load()

    for _, kind in ipairs(ReadingKinds(ns)) do
        local longest = 0
        local shortest = 0
        local total = 0

        EachOfKind(ns, kind, 60, function(p)
            local size = #p.choices[p.answer]
            local longer = true
            local shorter = true

            for i, choice in ipairs(p.choices) do
                if i ~= p.answer then
                    longer, shorter = (longer and (size > #choice)), (shorter and (size < #choice))
                end
            end

            total = (total + 1)
            longest = (longest + ((longer and 1) or 0))
            shortest = (shortest + ((shorter and 1) or 0))
        end)

        truthy(longest <= (total * 0.35), ("%s: the answer is the longest in %d of %d"):format(kind, longest, total))
        truthy(shortest <= (total * 0.35), ("%s: the answer is the shortest in %d of %d"):format(kind, shortest, total))
    end
end)

test("no one answer crowds a kind", function()
    local ns = Load()

    for _, kind in ipairs(ReadingKinds(ns)) do
        local counts = {}
        local total = 0
        local top = 0
        local most = nil

        EachOfKind(ns, kind, 60, function(p)
            local answer = p.choices[p.answer]

            counts[answer], total = ((counts[answer] or 0) + 1), (total + 1)

            if counts[answer] > top then
                top, most = counts[answer], answer
            end
        end)

        -- A letter answer (listenSound) has 24 to come from; every other kind has dozens.
        truthy(top <= (total * 0.1), ("%s: %q is the answer %d times in %d"):format(kind, tostring(most), top, total))
    end
end)

test("the real confusions turn up: a word that starts alike, a close sound, near words, a letter in the wrong place, a lone letter of a team, a dropped blend letter", function()
    local ns = Load()

    -- How many of kind's riddles have a why that finds pattern.
    local function Share(kind, pattern)
        local found = 0
        local total = 0

        EachOfKind(ns, kind, 40, function(p)
            local any = false

            for i = 1, 4 do
                any = (any or ((i ~= p.answer) and (p.whys[i]:find(pattern) ~= nil)))
            end

            found, total = (found + ((any and 1) or 0)), (total + 1)
        end)

        return found, total
    end

    for _, case in ipairs({
        { "reading.rhyme", "starts like", 0.4 }, { "reading.sound", "It's close to", 0.6 },
        { "reading.listenSound", "It's close", 0.6 }, { "reading.synonym", "goes with", 0.9 },
        { "reading.antonym", "means almost the same", 0.9 }, { "reading.sight", "sounds the same", 0.1 },
        { "reading.sight", "same letters", 0.05 }, { "reading.cvc", "has the \"", 0.2 },
        { "reading.spelling", "sounds right", 0.5 }, { "reading.digraph", "alone", 0.6 }, { "reading.digraph", "different sound from", 0.55 },
        { "reading.digraph", "splits", 0.12 }, { "reading.blend", "leaves out", 0.6 }, { "reading.blend", "where the blend has", 0.5 },
    }) do
        local found, total = Share(case[1], case[2])

        truthy(found >= (total * case[3]), ("%s: %q in %d of %d"):format(case[1], case[2], found, total))
    end
end)

test("a heard riddle's prompt and speech vary, and the speech always ends with the word", function()
    local ns = Load()

    for _, kind in ipairs({ "reading.listen", "reading.listenSound" }) do
        local prompts = {}
        local speeches = {}

        EachOfKind(ns, kind, 30, function(p)
            local word = p.speech:match("(%a+)%.$")

            prompts[p.prompt] = true
            speeches[p.speech:gsub(word, "")] = true
        end)

        local promptCount = 0
        local speechCount = 0

        for _ in pairs(prompts) do
            promptCount = (promptCount + 1)
        end

        for _ in pairs(speeches) do
            speechCount = (speechCount + 1)
        end

        truthy(promptCount >= 3, kind .. " has varied prompts")
        truthy(speechCount >= 3, kind .. " has varied speech")
    end
end)

test("a story asks more than what the story says outright", function()
    local ns = Load()
    local found = {}

    for _, story in ipairs(ns.ScholarStoryWords.stories) do
        for q = 2, #story do
            found[story[q].type] = ((found[story[q].type] or 0) + 1)
        end
    end

    for kind in pairs(Types) do
        truthy((found[kind] or 0) >= 4, ("at least 4 %s questions (%d)"):format(kind, found[kind] or 0))
    end

    truthy(found.literal < ((found.inference + found.main) + (found.sequence + found.vocab)), "fewer literal questions than the rest")
end)

-- The letters at a word's start or end ("start" or "finish"), n of them.
local function At(word, place, n)
    return (((place == "start") and word:sub(1, n)) or word:sub(-n))
end

test("letter teams' words start or end with them, their wrong words have only one letter or a near sound there", function()
    local banks = Load().ScholarReadingWords
    local teams = {}

    for _, team in ipairs(banks.digraphs) do
        teams[team[1]] = team
    end

    for _, team in ipairs(banks.digraphs) do
        local letters = team[1]

        truthy(team.note and team.sound and team.other, letters .. " has a note, a sound and its mix-ups")
        eq(#team.spell, 3, letters .. " has three wrong spellings")

        for _, place in ipairs({ "start", "finish" }) do
            for _, word in ipairs(team[place] or {}) do
                eq(At(word, place, 2), letters, ("%s has %s at its %s"):format(word, letters, place))
            end

            for _, bank in ipairs({ { team.alone, letters:sub(1, 1) }, { team.half, letters:sub(2, 2) } }) do
                for _, word in ipairs((bank[1] or {})[place] or {}) do
                    eq(At(word, place, 1), bank[2], ("%s has %s alone at its %s"):format(word, bank[2], place))
                    falsy(teams[At(word, place, 2)], word .. " has no letter team there")
                end
            end

            for _, word in ipairs((team.close or {})[place] or {}) do
                eq(At(word, place, #team.close.letters), team.close.letters, word .. " has the near sound")
            end
        end

        falsy(team.like and (team.alone or team.close), letters .. ": a letter that spells the same sound is never a wrong word")
    end
end)

test("every word blended with a letter team holds one team, and offers the team's mistake", function()
    local banks = Load().ScholarReadingWords
    local teams = {}

    for _, team in ipairs(banks.digraphs) do
        teams[team[1]] = team
    end

    for _, entry in ipairs(banks.digraphWords) do
        local word = entry[1]
        local team = nil
        local place = nil

        for letters, candidate in pairs(teams) do
            for _, where in ipairs({ "start", "finish" }) do
                if candidate[where] and (At(word, where, 2) == letters) then
                    falsy(team, word .. " holds one letter team")
                    team, place = candidate, where
                end
            end
        end

        truthy(team, word .. " starts or ends with a letter team")
        local rest = (((place == "start") and word:sub(3)) or word:sub(1, -3))
        local mistakes = {}

        falsy(word:match("(%a)%1"), word .. " has no doubled letter")

        local function Put(letters)
            mistakes[((place == "start") and (letters .. rest)) or (rest .. letters)] = true
        end

        Put(team[1]:sub(1, 1))
        Put(team[1]:sub(2, 2))

        for letters in pairs(teams) do
            falsy(rest:find(letters, 1, true), word .. ": every other sound is a single letter")
            Put(letters)
        end

        if team.close then
            Put(team.close.letters)
        end

        local found = false

        for i = 2, 4 do
            truthy(entry[i]:match("^%l+$") and (entry[i] ~= word), ("%q is a word other than %s"):format(entry[i], word))
            found = (found or (mistakes[entry[i]] and (entry[i] ~= word)))
        end

        truthy(found, word .. " offers the team's mistake: one letter, another team or a near sound in its place")
    end
end)

test("every blend word has a blend, single sounds and a wrong word that drops a letter of its blend", function()
    local banks = Load().ScholarReadingWords

    local function Consonant(letter)
        return (letter:find("[aeiouy]") == nil)
    end

    for _, entry in ipairs(banks.blends) do
        local word = entry[1]
        local start = (Consonant(word:sub(1, 1)) and Consonant(word:sub(2, 2)))
        local finish = (Consonant(word:sub(-2, -2)) and Consonant(word:sub(-1)))
        local dropped = false

        truthy(start or finish, word .. " has a blend")
        falsy(word:match("(%a)%1"), word .. " has no doubled letter")

        for _, team in ipairs(banks.digraphs) do
            falsy(word:find(team[1], 1, true), word .. " has no letter team")
        end

        for i = 2, 4 do
            truthy(entry[i]:match("^%l+$") and (entry[i] ~= word), ("%q is a word other than %s"):format(entry[i], word))

            for at = 1, #word do
                local inBlend = ((start and (at <= 2)) or (finish and (at >= (#word - 1))))

                dropped = (dropped or (inBlend and ((word:sub(1, at - 1) .. word:sub(at + 1)) == entry[i])))
            end
        end

        truthy(dropped, word .. " offers itself with a blend letter dropped")
    end
end)

test("a heard story is short, its choices are short, and a literal or inference clue never holds the answer", function()
    local banks = Load().ScholarStoryWords
    local types = { inference = true, literal = true, sequence = true }

    for _, story in ipairs(banks.heard) do
        local words = select(2, story[1]:gsub("%S+", ""))

        truthy(words <= 25, ("at most 25 words (%d): %s"):format(words, story[1]))

        for q = 2, #story do
            local question = story[q]

            truthy(types[question.type], "who, what, how someone felt or the order: " .. question[1])

            for i = 2, 5 do
                truthy(#TextOf(question[i]) <= 24, ("%q is short enough to hear"):format(TextOf(question[i])))
            end

            if question.type ~= "sequence" then
                local answer = Fold(question[2]):gsub("^an? ", ""):gsub("^the ", "")

                falsy(Fold(question.clue):find(answer, 1, true), ("the clue %q doesn't hold %q"):format(question.clue, answer))
            end
        end
    end
end)

test("stories for younger readers are short and ask a literal question, then an inference, and grades 2 and 3 get them", function()
    local ns = Load()
    local tiers = {}

    for _, story in ipairs(ns.ScholarStoryWords.stories) do
        tiers[story[1]:sub(-15)] = story.t

        if story.t == 1 then
            local words = select(2, story[1]:gsub("%S+", ""))

            truthy(words <= 30, ("at most 30 words (%d): %s"):format(words, story[1]))
            eq(#story, 3, "two questions: " .. story[1])
            eq(story[3].type, "inference", "the second is an inference: " .. story[3][1])
        else
            eq(story.t, 2, "a tier for " .. story[1])
        end
    end

    for _, case in ipairs({ { 2, 1, 1 }, { 2, 3, 1 }, { 3, 2, 1 }, { 5, 2, 2 }, { 6, 3, 2 } }) do
        for seed = 1, 40 do
            local p = ns.Puzzles.Generate({ grade = case[1], kind = "reading.story", level = case[2], random = Rng(seed), subject = "reading" })
            local story = p.prompt:match("^(.-)\n")

            eq(tiers[story:sub(-15)], case[3], ("grade %d level %d reads tier %d: %s"):format(case[1], case[2], case[3], story))
        end
    end
end)
