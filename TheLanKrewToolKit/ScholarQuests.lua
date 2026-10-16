local addonName, ns = ...

-- Scholar quest riddles: questions about a quest the player was shown, from its QuestBook record (QuestBook.lua). Pure
-- like the other puzzle files: no WoW API, and no randomness but the state's roll. ScholarPuzzles.Generate calls
-- Kit.AskQuest for the "quest" subject.
--
--   Kit.AskQuest(state, quest, known)  a puzzle about quest (a record), with known (every record,
--                                      that one included) for wrong answers; nil when nothing
--                                      fits. The puzzle's book is the quest as the player saw it.
--
-- It's an open-book test: every answer is in the quest's text, its objectives, or who and where, and the book shows
-- them all, so every riddle teaches looking it up: its hint says where in the book to look, its step walks to the line,
-- its explanation quotes it, and its praise names that. Kinds: who gave it, who took it (turned in), where it began,
-- where it ended, how many an objective asked for, what it asked, which quest a giver gave, and a word missing from its
-- text (enUS clients only: the words are split as English letters, the plain words left out are English ones, and the
-- missing word's wrong answers are words of its own kind by English endings and neighbors, from ScholarWords'
-- questWords). A kind runs only when the record holds its answer, and its three wrong answers come from the player's
-- other quests first (each saying which quest it's from), then from ScholarWords' banks for the player's faction
-- (state.context.faction), never one that is also true (the zone around the place it began, another quest the same
-- giver gave or might have, a bank quest that giver really gives). Who gave it and who took it, and where it began and
-- where it ended, are each other's first wrong answer, the mix-up a reader makes.
--
-- A title can give its answer away ("Wolves Across the Border", asking for Tough Wolf Meat): then the wrong answers
-- share the title's words too, or the riddle names the quest as the one in the quest book instead. Which quest a giver
-- gave isn't asked when the giver's name is in its title.
--
-- Which kind: what the quest asked for (how many, what, a missing word) before who and where, and not the kind last
-- asked about this quest (its askedKind; who gave it and which quest a giver gave are one kind) unless no other fits.

-- The kinds about what a quest asked for, asked before who and where.
local ContentKinds = { ["quest.count"] = true, ["quest.objective"] = true, ["quest.blank"] = true }
-- Kinds that ask the same thing another way, by the kind they count as.
local Families = { ["quest.title"] = "quest.giver" }
-- How many words before a missing word its step quotes.
local LeadWords = 3
-- The longest choice a riddle may offer, which ScholarPuzzles enforces.
local MaxLine = ns.Puzzles.MaxChoice
local MaxSentence = 140
local MaxTitle = 60
local MaxWord = 12
local MinSentence = 30
local MinWord = 5
-- The field of this quest a riddle about each is mixed up with: who took it for who gave it, where it ended for where
-- it began, and the other way round.
local Mixups = { ender = "giver", endPlace = "place", giver = "ender", place = "endPlace" }

-- Words of four letters or more too plain to tie a choice to a title.
local PlainWords = { from = true, have = true, into = true, that = true, them = true, they = true, this = true,
    what = true, will = true, with = true, your = true }

local concat = table.concat
local find = string.find
local gmatch = string.gmatch
local gsub = string.gsub
local ipairs = ipairs
local lower = string.lower
local max = math.max
local min = math.min
local next = next
local pairs = pairs
local select = select
local sub = string.sub
local tostring = tostring
local type = type

local Kit = ns.Puzzles.Kit

local Fill, Finish, Fits, Generators, Pick, Shuffle, WrongNumbers = Kit.Fill, Kit.Finish, Kit.Fits, Kit.Generators,
    Kit.Pick, Kit.Shuffle, Kit.WrongNumbers

local MaxObjectives = ns.QuestBook.MaxObjectives
local Words = Kit.Words
local QuestWords = Words.questWords

-- A quest's text from a record: line breaks kept, nothing that could be an escape or template.
local function Body(text)
    if type(text) ~= "string" then
        return ""
    end

    return (gsub(gsub(text, "[|{}\\]", ""), "[%z\1-\9\11-\31]", ""))
end

-- Whether word, lowercase, is a comparable word plus -er: "bolder", "easier", "braver", "bigger".
local function Comparative(word)
    if not find(word, "er$") then
        return false
    end

    local stem = sub(word, 1, -3)
    local comparable = QuestWords.comparable

    return ((comparable[stem] or comparable[stem .. "e"] or comparable[(gsub(stem, "i$", "y"))]
        or (find(stem, "(%a)%1$") and comparable[sub(stem, 1, -2)])) == true)
end

-- Whether hits holds every stem of wanted.
local function Covers(hits, wanted)
    for stem in pairs(wanted) do
        if not hits[stem] then
            return false
        end
    end

    return true
end

-- A one-line text from a record: no control characters, escape or template characters, trimmed, at most length; ""
-- otherwise.
local function Line(text, length)
    if type(text) ~= "string" then
        return ""
    end

    text = gsub(gsub(gsub(text, "[%c|{}\\]", " "), "%s+", " "), "^%s*(.-)%s*$", "%1")

    return (((#text <= length) and text) or "")
end

-- A set of the lowercase forms of the given values ("" left out).
local function Lowered(...)
    local set = {}

    for i = 1, select("#", ...) do
        local value = select(i, ...)

        if value ~= "" then
            set[lower(value)] = true
        end
    end

    return set
end

-- The riddle's text with the bare prompt (naming the quest as the one in the book) unless titled.
local function Prompted(text, titled)
    if titled or not text.bare then
        return text
    end

    local copy = {}

    for key, value in pairs(text) do
        copy[key] = value
    end

    copy.prompt, copy.prompts = text.bare, nil

    return copy
end

-- A word's stem, for matching it to a title's words: "wolves" and "wolf" are one, as are "kobolds" and "kobold".
local function Stem(word)
    word = gsub(gsub(lower(word), "ves$", "f"), "ies$", "y")

    return (gsub(word, "s$", ""))
end

-- The stems of title's words (four letters or more, not plain) that text has too, as a set: empty without a title.
local function TitleHits(text, title)
    local hits = {}
    local stems = {}

    for word in gmatch(title or "", "%a+") do
        if (#word >= 4) and not PlainWords[lower(word)] then
            stems[Stem(word)] = true
        end
    end

    for word in gmatch(text, "%a+") do
        if (#word >= 4) and stems[Stem(word)] then
            hits[Stem(word)] = true
        end
    end

    return hits
end

-- A sentence's words, each { word, s, e (where it starts and ends), joined (part of a longer word, by an apostrophe or
-- hyphen), spaced (only spaces since the word before), ends (punctuation or the sentence's end right after it) }.
local function Tokens(sentence)
    local tokens = {}

    for s, word, e in gmatch(sentence, "()(%a+)()") do
        local after = sub(sentence, e, e)
        local before = sub(sentence, s - 1, s - 1)
        local previous = tokens[#tokens]

        tokens[#tokens + 1] = {
            e = e,
            ends = (after ~= " "),
            joined = ((before == "'") or (before == "-") or (after == "-")
                or ((after == "'") and (sub(sentence, e + 1, e + 1) ~= "s"))),
            s = s,
            spaced = ((previous == nil) or (find(sub(sentence, previous.e, s - 1), "^ +$") ~= nil)),
            word = word,
        }
    end

    return tokens
end

-- An objective's kind as the riddles ask about it, by the log's type: an item to bring, a foe to defeat, anything else
-- a task to do.
local ObjectiveKinds = { item = "item", monster = "foe" }
local ObjectiveVerbs = { { "item", "Bring" }, { "foe", "Defeat" }, { "task", "Do" } }

-- ScholarWords' wrong answers for the player's faction (Alliance's when it's unknown).
local function Bank(state)
    return (Words.questBanks[state.context.faction] or Words.questBanks.Alliance)
end

-- The words of a kind of missing word that aren't from the quest: the faction's names or places for a name or place,
-- else questWords' kinds.
local function BlankBank(state, kind)
    if kind == "name" then
        return Bank(state).nameWords
    elseif kind == "place" then
        return Bank(state).placeWords
    end

    return QuestWords.kinds[kind]
end

-- The missing word at sentence's token i, with three wrong answers of its kind (as long, give or take three letters,
-- and not in the sentence): words of that kind from the rest of the quest's text first, then the bank's; nil when there
-- are too few, or the word is in the sentence twice (it would show through its blank).
local function Blank(state, sentence, i, pool)
    local token = sentence.tokens[i]
    local kind = sentence.kinds[i]
    local text = sentence.text
    local word = token.word
    local _, uses = gsub(text, "%f[%a]" .. word .. "%f[%A]", "")

    if uses ~= 1 then
        return nil
    end

    local wrongs = {}
    local seen = {}

    for _, other in ipairs(sentence.tokens) do
        seen[lower(other.word)] = true
    end

    local function Add(other, why)
        local key = lower(other)

        if (#wrongs < 3) and not seen[key] and (#other >= (#word - 3)) and (#other <= (#word + 3)) then
            seen[key] = true
            wrongs[#wrongs + 1] = { other, why = why }
        end
    end

    for _, other in ipairs(Shuffle(state, pool[kind] or {})) do
        Add(other, Fill(Words.quest.blank.other, { choice = other }))
    end

    for _, other in ipairs(Shuffle(state, BlankBank(state, kind))) do
        Add(other)
    end

    if #wrongs < 3 then
        return nil
    end

    local before = {}
    local after = {}

    for chunk in gmatch(sub(text, 1, token.s - 1), "%S+") do
        before[#before + 1] = chunk
    end

    for chunk in gmatch((gsub(sub(text, token.e), "^[%p%s]+", "")), "%S+") do
        after[#after + 1] = chunk
    end

    -- The words just before the blank, or just after it when one word before it is all there is ("The ___ of").
    local lead = concat(before, " ", max(1, (#before - LeadWords) + 1))
    local side = "after"

    if (#before < 2) and (#after >= 2) then
        lead, side = concat(after, " ", 1, min(#after, LeadWords)), "before"
    end

    return {
        filled = text, lead = lead, sentence = (sub(text, 1, token.s - 1) .. "___" .. sub(text, token.e)), side = side,
        word = word, wrongs = wrongs,
    }
end

-- What the quest book shows: the quest as the player saw it, every answer in it.
local function Book(quest)
    local lines = { ("\"" .. quest.title .. "\"") }

    if (quest.giver ~= "") and (quest.place ~= "") then
        lines[#lines + 1] = ("From %s, in %s."):format(quest.giver, quest.place)
    elseif quest.giver ~= "" then
        lines[#lines + 1] = ("From " .. quest.giver .. ".")
    elseif quest.place ~= "" then
        lines[#lines + 1] = ("Taken in " .. quest.place .. ".")
    end

    for _, verb in ipairs(ObjectiveVerbs) do
        local parts = {}

        for _, objective in ipairs(quest.objectives) do
            if objective.kind == verb[1] then
                parts[#parts + 1] = (((objective.required > 1) and (objective.name .. " (" .. objective.required .. ")")) or objective.name)
            end
        end

        if #parts > 0 then
            lines[#lines + 1] = (verb[2] .. ": " .. concat(parts, "; "))
        end
    end

    if quest.goal ~= "" then
        lines[#lines + 1] = quest.goal
    end

    if quest.text ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = quest.text
    end

    if quest.turnedIn and ((quest.ender ~= "") or (quest.endPlace ~= "")) then
        lines[#lines + 1] = ""

        lines[#lines + 1] = ("Turned in" .. (((quest.ender ~= "") and (" to " .. quest.ender)) or "")
            .. (((quest.endPlace ~= "") and (" at " .. quest.endPlace)) or "") .. ".")
    end

    return concat(lines, "\n")
end

-- Wrong answers from the other known quests: each value of the named fields, with the why of the field it came from
-- (Words.quest.from), which names that quest.
local function FromOthers(state, fields)
    local entries = {}

    for _, other in ipairs(state.known) do
        if other.key ~= state.quest.key then
            for _, field in ipairs(fields) do
                local value = other[field]

                if value ~= "" then
                    entries[#entries + 1] = { value, why = Fill(Words.quest.from[field], { choice = value, other = other.title }) }
                end
            end
        end
    end

    return entries
end

-- The other known quests' objectives of a kind, by name, each saying which quest it was for.
local function OtherObjectives(state, kind)
    local entries = {}

    for _, other in ipairs(state.known) do
        if other.key ~= state.quest.key then
            for _, objective in ipairs(other.objectives) do
                if objective.kind == kind then
                    local vars = { choice = objective.name, other = other.title }

                    entries[#entries + 1] = { objective.name, why = Fill(Words.quest.from.objective, vars) }
                end
            end
        end
    end

    return entries
end

-- The capitalized words a missing word can be, lowercase, by kind: "place" or "name".
local function ProperWords(state)
    local proper = {}

    for _, word in ipairs(Bank(state).nameWords) do
        proper[lower(word)] = "name"
    end

    for _, word in ipairs(Bank(state).placeWords) do
        proper[lower(word)] = "place"
    end

    return proper
end

-- A record's objective i, or nil: what it names, its count and its kind. One without a name, or without the kind the
-- book notes, isn't asked about.
local function RecordObjective(record, i)
    local name = Line(record["objective" .. i], MaxLine)
    local required = record["required" .. i]
    local logType = record["type" .. i]

    if not ((name ~= "") and (type(required) == "number") and (required >= 1) and (type(logType) == "string") and (logType ~= "")) then
        return nil
    end

    return { kind = (ObjectiveKinds[logType] or "task"), name = name, required = required }
end

-- A record as the riddles read it: { title, giver, place, zone, ender, endPlace, endZone, turnedIn, goal, text,
-- askedKind, objectives = { { name, kind, required } } }, every field cleaned; nil without a title.
local function Clean(record)
    local quest = {
        askedKind = Line(record.askedKind, MaxLine), ender = Line(record.ender, MaxLine),
        endPlace = Line(record.endPlace, MaxLine), endZone = Line(record.endZone, MaxLine),
        giver = Line(record.giver, MaxLine), goal = Line(record.goal, 200), key = record.key, objectives = {},
        place = Line(record.place, MaxLine), text = Body(record.text), title = Line(record.title, MaxTitle),
        turnedIn = (record.turnedIn == true), zone = Line(record.zone, MaxLine),
    }

    for i = 1, MaxObjectives do
        quest.objectives[#quest.objectives + 1] = RecordObjective(record, i)
    end

    return (((quest.title ~= "") and quest) or nil)
end

-- The kind of tokens[i] as a missing word (see ScholarWords' questWords): "place" or "name" (a capitalized word of the
-- faction's lists, not starting the sentence), "noun", "nouns", "ed", "ing", "ly" or "er"; nil for any other word,
-- which isn't asked or offered.
local function WordKind(tokens, i, proper)
    local token = tokens[i]
    local previous = tokens[i - 1]
    local following = tokens[i + 1]
    local word = token.word

    if token.joined or (#word < MinWord) or Words.stopWords[lower(word)] then
        return nil
    elseif find(word, "^%u") then
        return (((i > 1) and not find(word, "^%u%u") and proper[lower(word)]) or nil)
    elseif previous and token.spaced and QuestWords.nounStarts[lower(previous.word)] then
        if token.ends or (following and QuestWords.nounEnds[lower(following.word)]) then
            return ((find(word, "[^isu]s$") and "nouns") or "noun")
        end

        return nil
    elseif (#word >= 6) and find(word, "ly$") then
        return "ly"
    elseif (#word >= 6) and find(word, "ing$") then
        return "ing"
    elseif find(word, "[^e]ed$") then
        return "ed"
    elseif Comparative(word) then
        return "er"
    end

    return nil
end

-- A sentence of the quest's text with one word to blank out and three wrong answers of its kind; nil when the text has
-- none.
local function BlankCandidate(state)
    local proper = ProperWords(state)
    local sentences = {}
    local pool = {}

    for text in gmatch(gsub(state.quest.text, "\n", " ") .. " ", "%s*([^%.!?]+[%.!?])") do
        local tokens = Tokens(text)
        local sentence = { kinds = {}, text = text, tokens = tokens }

        for i, token in ipairs(tokens) do
            local kind = WordKind(tokens, i, proper)

            sentence.kinds[i] = kind

            if kind then
                pool[kind] = (pool[kind] or {})
                pool[kind][#pool[kind] + 1] = token.word
            end
        end

        if (#text >= MinSentence) and (#text <= MaxSentence) and not find(text, "\"", 1, true) then
            sentences[#sentences + 1] = sentence
        end
    end

    for _, sentence in ipairs(Shuffle(state, sentences)) do
        local candidates = {}

        for i, token in ipairs(sentence.tokens) do
            if sentence.kinds[i] and (#token.word <= MaxWord) then
                candidates[#candidates + 1] = i
            end
        end

        for _, i in ipairs(Shuffle(state, candidates)) do
            local blank = Blank(state, sentence, i, pool)

            if blank then
                return blank
            end
        end
    end

    return nil
end

-- Three wrong answers, and whether the riddle may show the title: from lists in order (each shuffled; an entry is a
-- value or { value, why }), each distinct, not the answer and (with excluded, a set of lowercase values that are also
-- true) not excluded. When the answer shares a word with title, the wrong answers must share it too or the title would
-- give the answer away: three that do are taken when there are three, and otherwise the riddle leaves the title out.
-- Finish shuffles where they sit among the choices.
local function Wrongs(state, answer, lists, excluded, title)
    local entries = {}
    local seen = { [lower(answer)] = true }

    for key in pairs(excluded or {}) do
        seen[key] = true
    end

    for _, list in ipairs(lists) do
        for _, value in ipairs(Shuffle(state, list)) do
            local entry = (((type(value) == "table") and value) or { value })
            local key = lower(entry[1])

            if (entry[1] ~= "") and (#entry[1] <= MaxLine) and not seen[key] then
                seen[key] = true
                entries[#entries + 1] = entry
            end
        end
    end

    local hits = TitleHits(answer, title)

    if next(hits) == nil then
        return { entries[1], entries[2], entries[3] }, true
    end

    local sharing = {}

    for _, entry in ipairs(entries) do
        if (#sharing < 3) and Covers(TitleHits(entry[1], title), hits) then
            sharing[#sharing + 1] = entry
        end
    end

    if #sharing == 3 then
        return sharing, true
    end

    return { entries[1], entries[2], entries[3] }, false
end

-- A generator asking for the quest's field: its first wrong answer is the field it's mixed up with, when the book shows
-- it; then the same pair of fields in other quests, then the faction bank's bankKey list, never naming the field's own
-- zone.
local function AskFor(field, pair, bankKey, zoneField)
    local kind = ("quest." .. field)

    return function(state)
        local quest = state.quest
        local text = Words.quest[field]
        local answer = quest[field]
        local mixed = Mixups[field]
        local mixups = {}

        -- Who took it and where it ended are in the book once it's turned in.
        if (quest[mixed] ~= "") and (quest.turnedIn or (mixed == "giver") or (mixed == "place")) then
            mixups[1] = { quest[mixed], why = Fill(text.mixup, { choice = quest[mixed] }) }
        end

        local excluded = (zoneField and Lowered(quest[zoneField]))
        local lists = { mixups, FromOthers(state, pair), Bank(state)[bankKey] }
        local wrongs, titled = Wrongs(state, answer, lists, excluded, quest.title)

        return Finish(state, kind, Prompted(text, titled), { answer = answer, title = quest.title }, answer, wrongs)
    end
end

Generators["quest.endPlace"] = AskFor("endPlace", { "place", "endPlace" }, "places", "endZone")
Generators["quest.ender"] = AskFor("ender", { "giver", "ender" }, "names")
Generators["quest.giver"] = AskFor("giver", { "giver", "ender" }, "names")
Generators["quest.place"] = AskFor("place", { "place", "endPlace" }, "places", "zone")

-- How many an objective asked for. Another objective's number, beside its own name in the book, is always a wrong
-- answer, the mix-up to catch; every other wrong number says which way the book's is.
Generators["quest.count"] = function(state)
    local quest = state.quest
    local whys = Words.quest.count.whys
    local counted = {}

    for _, objective in ipairs(quest.objectives) do
        if objective.required > 1 then
            counted[#counted + 1] = objective
        end
    end

    local objective = Pick(state, counted)
    local n = objective.required
    local candidates = { (n - 1), (n + 1), (n + 2), (n * 2) }
    local hi = max(n * 2, n + 10)

    for _, other in ipairs(quest.objectives) do
        if (other ~= objective) and (other.required > 1) and (other.required ~= n) then
            local why = Fill(whys.other, { objective = objective.name, other = other.name })

            candidates[#candidates + 1] = { other.required, required = true, why = why }
            hi = max(hi, other.required)
        end
    end

    local numbers, numberWhys = WrongNumbers(state, n, candidates, 1, hi)
    local wrongs = {}

    for i, value in ipairs(numbers) do
        local way = (((value < n) and whys.fewer) or whys.more)

        wrongs[i] = { tostring(value), why = (numberWhys[i] or Fill(way, { objective = objective.name })) }
    end

    local vars = { answer = n, objective = objective.name, title = quest.title, v = n }

    return Finish(state, "quest.count", Words.quest.count[objective.kind], vars, tostring(n), wrongs)
end

-- What an objective asked for, by its kind: wrong answers are objectives of that kind too.
local ObjectiveBanks = { foe = "foes", item = "items", task = "tasks" }

Generators["quest.objective"] = function(state)
    local quest = state.quest
    local own = {}

    for _, objective in ipairs(quest.objectives) do
        -- The quest's other objectives are right answers too.
        own[lower(objective.name)] = true
    end

    local objective = Pick(state, quest.objectives)
    local answer = objective.name
    local lists = { OtherObjectives(state, objective.kind), Bank(state)[ObjectiveBanks[objective.kind]] }
    local wrongs, titled = Wrongs(state, answer, lists, own, quest.title)
    local text = Prompted(Words.quest.objective[objective.kind], titled)

    return Finish(state, "quest.objective", text, { answer = answer, title = quest.title }, answer, wrongs)
end

Generators["quest.title"] = function(state)
    local quest = state.quest
    local from = Words.quest.from.title
    local others = {}
    local theirs = {}

    for _, other in ipairs(state.known) do
        if lower(other.giver) == lower(quest.giver) then
            -- The giver's other quests are right answers too.
            theirs[lower(other.title)] = true
        elseif (other.key ~= quest.key) and (other.giver ~= "") then
            -- A quest nobody saw given might be the giver's too, so it isn't offered.
            others[#others + 1] = { other.title, why = Fill(from, { choice = other.title, other = other.giver }) }
        end
    end

    local bank = {}

    for _, entry in ipairs(Bank(state).titles) do
        if lower(entry[2]) == lower(quest.giver) then
            -- The giver really gives that one.
            theirs[lower(entry[1])] = true
        else
            bank[#bank + 1] = { entry[1], why = Fill(from, { choice = entry[1], other = entry[2] }) }
        end
    end

    local wrongs = Wrongs(state, quest.title, { others, bank }, theirs)

    return Finish(state, "quest.title", Words.quest.title, { answer = quest.title, giver = quest.giver }, quest.title, wrongs)
end

Generators["quest.blank"] = function(state)
    local blank = state.blank
    local title = state.quest.title
    local vars = { filled = blank.filled, lead = blank.lead, sentence = blank.sentence, side = blank.side, title = title }
    local text = Prompted(Words.quest.blank, next(TitleHits(blank.word, title)) == nil)

    return Finish(state, "quest.blank", text, vars, blank.word, blank.wrongs)
end

local function Family(kind)
    return (Families[kind] or kind)
end

-- The kinds whose answer the record holds.
local function Kinds(state)
    local quest = state.quest
    local kinds = {}

    local function Add(kind, possible)
        if possible then
            kinds[#kinds + 1] = kind
        end
    end

    local counted = false

    for _, objective in ipairs(quest.objectives) do
        counted = (counted or (objective.required > 1))
    end

    Add("quest.giver", quest.giver ~= "")
    Add("quest.ender", quest.turnedIn and (quest.ender ~= ""))
    Add("quest.place", quest.place ~= "")
    Add("quest.endPlace", quest.turnedIn and (quest.endPlace ~= ""))
    Add("quest.count", counted)
    Add("quest.objective", #quest.objectives > 0)
    -- A giver named in the title ("Galgar's Cactus Apple Surprise") would give it away.
    Add("quest.title", (quest.giver ~= "") and (#quest.title <= MaxLine) and (next(TitleHits(quest.giver, quest.title)) == nil))
    state.blank = (((state.context.locale == "enUS") and BlankCandidate(state)) or nil)
    Add("quest.blank", state.blank ~= nil)

    return kinds
end

-- The kinds in the order to try them (see the header): each group shuffled.
local function Ordered(state, kinds)
    local content = {}
    local other = {}
    local last = {}
    local lastFamily = Family(state.quest.askedKind)

    for _, kind in ipairs(kinds) do
        local group = (((Family(kind) == lastFamily) and last) or ((ContentKinds[kind] and content) or other))

        group[#group + 1] = kind
    end

    local ordered = {}

    for _, group in ipairs({ content, other, last }) do
        for _, kind in ipairs(Shuffle(state, group)) do
            ordered[#ordered + 1] = kind
        end
    end

    return ordered
end

--- A puzzle about quest, or nil when no kind of question fits it. See the file header.
---@param state table ScholarPuzzles' generation state
---@param record table a QuestBook record, with its key
---@param known table[] every QuestBook record, with their keys
---@return table? puzzle with book, the quest book's text
local function AskQuest(state, record, known)
    state.quest = Clean(record)

    if not state.quest then
        return nil
    end

    state.known = {}

    for _, other in ipairs(((type(known) == "table") and known) or {}) do
        state.known[#state.known + 1] = Clean(other)
    end

    for _, kind in ipairs(Ordered(state, Kinds(state))) do
        local puzzle = Generators[kind](state)

        if Fits(puzzle) then
            puzzle.book = Book(state.quest)

            return puzzle
        end
    end

    return nil
end

Kit.AskQuest = AskQuest
