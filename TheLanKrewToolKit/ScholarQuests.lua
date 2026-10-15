local addonName, ns = ...

-- Scholar quest riddles: questions about a quest the player was shown, from its QuestBook record
-- (QuestBook.lua). Pure like the other puzzle files: no WoW API, and no randomness but the
-- state's roll. ScholarPuzzles.Generate calls Kit.AskQuest for the "quest" subject.
--
--   Kit.AskQuest(state, quest, known)  a puzzle about quest (a record), with known (every record,
--                                      that one included) for wrong answers; nil when nothing
--                                      fits. The puzzle's book is the quest as the player saw it.
--
-- It's an open-book test: every answer is in the quest's text, its objectives, or who and where,
-- and the book shows them all. Kinds: who gave it, who took it (turned in), where it began, where
-- it ended, how many an objective asked for, what it asked, which quest a giver gave, and a word
-- missing from its text (enUS clients only: the words are split as English letters, and the plain
-- words left out are English ones). A kind runs only when the record holds its answer, and its
-- three wrong answers come from the player's other quests first, then from ScholarWords' banks for
-- the player's faction (state.context.faction), never one that is also true (the zone around the
-- place it began, another quest the same giver gave, a bank quest that giver really gives).
--
-- Which kind: what the quest asked for (how many, what, a missing word) before who and where, and
-- not the kind last asked about this quest (its askedKind; who gave it and which quest a giver gave
-- are one kind) unless no other fits.

local MaxLine = 40      -- the longest choice, as ScholarPuzzles allows
local MaxSentence, MinSentence = 140, 30
local MaxTitle = 60
local MaxWord, MinWord = 12, 5
-- The kinds about what a quest asked for, asked before who and where.
local ContentKinds = { ["quest.count"] = true, ["quest.objective"] = true, ["quest.blank"] = true }
-- Kinds that ask the same thing another way, by the kind they count as.
local Families = { ["quest.title"] = "quest.giver" }

local concat = table.concat
local find, gmatch, gsub, lower = string.find, string.gmatch, string.gsub, string.lower
local ipairs, pairs, select, tostring, type = ipairs, pairs, select, tostring, type

local Kit = ns.Puzzles.Kit
local Generators, Pick, Shuffle, Finish, WrongNumbers, Fits = Kit.Generators, Kit.Pick, Kit.Shuffle, Kit.Finish,
    Kit.WrongNumbers, Kit.Fits
local MaxObjectives = ns.QuestBook.MaxObjectives
local Words = Kit.Words

-- A one-line text from a record: no control characters, escape or template characters, trimmed,
-- at most length; "" otherwise.
local function Line(text, length)
    if type(text) ~= "string" then
        return ""
    end
    text = gsub(gsub(gsub(text, "[%c|{}\\]", " "), "%s+", " "), "^%s*(.-)%s*$", "%1")
    return (((#text <= length) and text) or "")
end

-- A quest's text from a record: line breaks kept, nothing that could be an escape or template.
local function Body(text)
    if type(text) ~= "string" then
        return ""
    end
    return (gsub(gsub(text, "[|{}\\]", ""), "[%z\1-\9\11-\31]", ""))
end

-- An objective's kind as the riddles ask about it, by the log's type: an item to bring, a foe to
-- defeat, anything else a task to do.
local ObjectiveKinds = { item = "item", monster = "foe" }
local ObjectiveVerbs = { { "item", "Bring" }, { "foe", "Defeat" }, { "task", "Do" } }

-- A record's objective i, or nil: what it names, its count and its kind. One without a name, or
-- without the kind the book notes, isn't asked about.
local function RecordObjective(record, i)
    local name, required, logType = Line(record["objective" .. i], MaxLine), record["required" .. i], record["type" .. i]

    if not ((name ~= "") and (type(required) == "number") and (required >= 1) and (type(logType) == "string") and (logType ~= "")) then
        return nil
    end
    return { kind = (ObjectiveKinds[logType] or "task"), name = name, required = required }
end

-- A record as the riddles read it: { title, giver, place, zone, ender, endPlace, endZone, turnedIn,
-- goal, text, askedKind, objectives = { { name, kind, required } } }, every field cleaned; nil
-- without a title.
local function Clean(record)
    local quest = {
        key = record.key, title = Line(record.title, MaxTitle), giver = Line(record.giver, MaxLine),
        place = Line(record.place, MaxLine), zone = Line(record.zone, MaxLine), ender = Line(record.ender, MaxLine),
        endPlace = Line(record.endPlace, MaxLine), endZone = Line(record.endZone, MaxLine),
        turnedIn = (record.turnedIn == true), askedKind = Line(record.askedKind, MaxLine),
        goal = Line(record.goal, 200), text = Body(record.text), objectives = {},
    }

    for i = 1, MaxObjectives do
        quest.objectives[#quest.objectives + 1] = RecordObjective(record, i)
    end
    return (((quest.title ~= "") and quest) or nil)
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

-- Three wrong answers: values from the other known quests first, shuffled, then the bank's,
-- shuffled, each distinct, not the answer and (with excluded, a set of lowercase values that are
-- also true) not excluded. Finish shuffles where they sit among the choices.
local function Wrongs(state, answer, values, bank, excluded)
    local out, seen = {}, { [lower(answer)] = true }

    for key in pairs(excluded or {}) do
        seen[key] = true
    end
    local function Add(value)
        local key = lower(value)

        if (#out < 3) and (value ~= "") and (#value <= MaxLine) and not seen[key] then
            seen[key] = true
            out[#out + 1] = value
        end
    end
    for _, value in ipairs(Shuffle(state, values)) do
        Add(value)
    end
    for _, value in ipairs(Shuffle(state, bank)) do
        Add(value)
    end
    return out
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

-- Every value of the named fields across the other known quests.
local function Gather(state, ...)
    local values = {}

    for _, other in ipairs(state.known) do
        if other.key ~= state.quest.key then
            for i = 1, select("#", ...) do
                values[#values + 1] = other[select(i, ...)]
            end
        end
    end
    return values
end

-- The other known quests' objectives of a kind, by name.
local function OtherObjectives(state, kind)
    local values = {}

    for _, other in ipairs(state.known) do
        if other.key ~= state.quest.key then
            for _, objective in ipairs(other.objectives) do
                if objective.kind == kind then
                    values[#values + 1] = objective.name
                end
            end
        end
    end
    return values
end

-- A sentence of the quest's text with one word to blank out, and three other words from the text
-- like it (as long, capitalized the same) as wrong answers; nil when the text has none.
local function BlankCandidate(state)
    local text = state.quest.text
    local pool = {}

    for word in gmatch(text, "%a+") do
        if (#word >= MinWord) and not Words.stopWords[lower(word)] then
            pool[#pool + 1] = word
        end
    end
    local sentences = {}

    for sentence in gmatch(gsub(text, "\n", " ") .. " ", "%s*([^%.!?]+[%.!?])") do
        if (#sentence >= MinSentence) and (#sentence <= MaxSentence) and not find(sentence, "\"", 1, true) then
            sentences[#sentences + 1] = sentence
        end
    end
    for _, sentence in ipairs(Shuffle(state, sentences)) do
        local candidates, inSentence = {}, {}

        for word in gmatch(sentence, "%a+") do
            inSentence[lower(word)] = true
            if (#word >= MinWord) and (#word <= MaxWord) and not Words.stopWords[lower(word)] then
                candidates[#candidates + 1] = word
            end
        end
        for _, word in ipairs(Shuffle(state, candidates)) do
            local capital = (find(word, "^%u") ~= nil)
            local _, uses = gsub(sentence, "%f[%a]" .. word .. "%f[%A]", "")
            -- Wrong answers come from the rest of the text: a word the sentence already has would
            -- read oddly in its own blank.
            local wrongs, seen = {}, {}

            for key in pairs(inSentence) do
                seen[key] = true
            end
            for _, other in ipairs(Shuffle(state, pool)) do
                local key = lower(other)

                if not seen[key] and ((find(other, "^%u") ~= nil) == capital) and (#other >= (#word - 3)) and (#other <= (#word + 3)) then
                    seen[key] = true
                    wrongs[#wrongs + 1] = other
                end
            end
            if (#wrongs >= 3) and (uses == 1) then -- a word used twice would show through its blank
                local blanked = gsub(sentence, "%f[%a]" .. word .. "%f[%A]", "___", 1)

                return { filled = sentence, sentence = blanked, word = word, wrongs = wrongs }
            end
        end
    end
    return nil
end

-- ScholarWords' wrong answers for the player's faction (Alliance's when it's unknown).
local function Bank(state)
    return (Words.questBanks[state.context.faction] or Words.questBanks.Alliance)
end

-- A generator asking for the quest's field: wrong answers come from the same pair of fields in
-- other quests, then the faction bank's bankKey list, and never name the field's own zone.
local function AskFor(field, pair, bankKey, zoneField)
    local kind = ("quest." .. field)

    return function(state)
        local quest = state.quest
        local answer = quest[field]
        local excluded = (zoneField and Lowered(quest[zoneField]))
        local wrongs = Wrongs(state, answer, Gather(state, pair[1], pair[2]), Bank(state)[bankKey], excluded)

        return Finish(state, kind, Words.quest[field], { answer = answer, title = quest.title }, answer, wrongs)
    end
end

Generators["quest.endPlace"] = AskFor("endPlace", { "place", "endPlace" }, "places", "endZone")
Generators["quest.ender"] = AskFor("ender", { "giver", "ender" }, "names")
Generators["quest.giver"] = AskFor("giver", { "giver", "ender" }, "names")
Generators["quest.place"] = AskFor("place", { "place", "endPlace" }, "places", "zone")

Generators["quest.count"] = function(state)
    local counted = {}

    for _, objective in ipairs(state.quest.objectives) do
        if objective.required > 1 then
            counted[#counted + 1] = objective
        end
    end
    local objective = Pick(state, counted)
    local n = objective.required
    local wrongs = {}

    for i, value in ipairs(WrongNumbers(state, n, { (n - 1), (n + 1), (n + 2), (n * 2) })) do
        wrongs[i] = tostring(value)
    end
    local vars = { answer = n, objective = objective.name, title = state.quest.title, v = n }

    return Finish(state, "quest.count", Words.quest.count[objective.kind], vars, tostring(n), wrongs)
end

-- What an objective asked for, by its kind: wrong answers are objectives of that kind too.
local ObjectiveBanks = { foe = "foes", item = "items", task = "tasks" }

Generators["quest.objective"] = function(state)
    local quest = state.quest
    local own = {}

    for _, objective in ipairs(quest.objectives) do
        own[lower(objective.name)] = true -- the quest's other objectives are right answers too
    end
    local objective = Pick(state, quest.objectives)
    local answer = objective.name
    local wrongs = Wrongs(state, answer, OtherObjectives(state, objective.kind), Bank(state)[ObjectiveBanks[objective.kind]], own)

    return Finish(state, "quest.objective", Words.quest.objective[objective.kind], { answer = answer, title = quest.title },
        answer, wrongs)
end

Generators["quest.title"] = function(state)
    local quest = state.quest
    local others, theirs = {}, {}

    for _, other in ipairs(state.known) do
        if lower(other.giver) == lower(quest.giver) then
            theirs[lower(other.title)] = true -- the giver's other quests are right answers too
        elseif other.key ~= quest.key then
            others[#others + 1] = other.title
        end
    end
    local bank = {}

    for _, entry in ipairs(Bank(state).titles) do
        if lower(entry[2]) == lower(quest.giver) then
            theirs[lower(entry[1])] = true -- the giver really gives that one
        else
            bank[#bank + 1] = entry[1]
        end
    end
    local wrongs = Wrongs(state, quest.title, others, bank, theirs)

    return Finish(state, "quest.title", Words.quest.title, { answer = quest.title, giver = quest.giver }, quest.title, wrongs)
end

Generators["quest.blank"] = function(state)
    local blank = state.blank
    local vars = { filled = blank.filled, sentence = blank.sentence, title = state.quest.title }

    return Finish(state, "quest.blank", Words.quest.blank, vars, blank.word, blank.wrongs)
end

-- The kinds whose answer the record holds.
local function Kinds(state)
    local quest, kinds = state.quest, {}

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
    Add("quest.title", (quest.giver ~= "") and (#quest.title <= MaxLine))
    state.blank = (((state.context.locale == "enUS") and BlankCandidate(state)) or nil)
    Add("quest.blank", state.blank ~= nil)
    return kinds
end

local function Family(kind)
    return (Families[kind] or kind)
end

-- The kinds in the order to try them (see the header): each group shuffled.
local function Ordered(state, kinds)
    local content, other, last = {}, {}, {}
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
