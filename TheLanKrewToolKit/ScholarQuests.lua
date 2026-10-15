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
-- missing from its text. A kind runs only when the record holds its answer, and its three wrong
-- answers come from the player's other quests first, then from ScholarWords' banks, never one that
-- is also true (the zone around the place it began, another quest the same giver gave).

local MaxTitle = 60
local MaxLine = 40      -- the longest choice, as ScholarPuzzles allows
local MinSentence, MaxSentence = 30, 140
local MinWord, MaxWord = 5, 12

local ipairs, pairs, select, tostring, type = ipairs, pairs, select, tostring, type
local concat = table.concat
local find, gmatch, gsub, lower = string.find, string.gmatch, string.gsub, string.lower

local Kit = ns.Puzzles.Kit
local Words = Kit.Words
local Generators, Pick, Shuffle, Finish, WrongNumbers, Fits = Kit.Generators, Kit.Pick, Kit.Shuffle, Kit.Finish,
    Kit.WrongNumbers, Kit.Fits
local MaxObjectives = ns.QuestBook.MaxObjectives

-- A one-line text from a record: no control characters, escape or template characters, trimmed,
-- at most length; "" otherwise.
local function Line(text, length)
    if type(text) ~= "string" then
        return ""
    end
    text = gsub(gsub(gsub(text, "[%c|{}\\]", " "), "%s+", " "), "^%s*(.-)%s*$", "%1")
    return #text <= length and text or ""
end

-- A quest's text from a record: line breaks kept, nothing that could be an escape or template.
local function Body(text)
    if type(text) ~= "string" then
        return ""
    end
    return (gsub(gsub(text, "[|{}\\]", ""), "[%z\1-\9\11-\31]", ""))
end

-- A record as the riddles read it: { title, giver, place, zone, ender, endPlace, endZone, turnedIn,
-- goal, text, objectives = { { text, required } } }, every field cleaned; nil without a title.
local function Clean(record)
    local quest = {
        key = record.key, title = Line(record.title, MaxTitle), giver = Line(record.giver, MaxLine),
        place = Line(record.place, MaxLine), zone = Line(record.zone, MaxLine), ender = Line(record.ender, MaxLine),
        endPlace = Line(record.endPlace, MaxLine), endZone = Line(record.endZone, MaxLine),
        turnedIn = record.turnedIn == true,
        goal = Line(record.goal, 200), text = Body(record.text), objectives = {},
    }
    for i = 1, MaxObjectives do
        local text, required = Line(record["objective" .. i], MaxLine), record["required" .. i]
        if text ~= "" and type(required) == "number" and required >= 1 then
            quest.objectives[#quest.objectives + 1] = { text = text, required = required }
        end
    end
    return quest.title ~= "" and quest or nil
end

-- What the quest book shows: the quest as the player saw it, every answer in it.
local function Book(quest)
    local lines = { "\"" .. quest.title .. "\"" }
    if quest.giver ~= "" and quest.place ~= "" then
        lines[#lines + 1] = ("From %s, in %s."):format(quest.giver, quest.place)
    elseif quest.giver ~= "" then
        lines[#lines + 1] = "From " .. quest.giver .. "."
    elseif quest.place ~= "" then
        lines[#lines + 1] = "Taken in " .. quest.place .. "."
    end
    if #quest.objectives > 0 then
        local parts = {}
        for i, objective in ipairs(quest.objectives) do
            parts[i] = objective.required > 1 and (objective.text .. " (" .. objective.required .. ")") or objective.text
        end
        lines[#lines + 1] = "Objectives: " .. concat(parts, "; ")
    end
    if quest.goal ~= "" then
        lines[#lines + 1] = quest.goal
    end
    if quest.text ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = quest.text
    end
    if quest.turnedIn and (quest.ender ~= "" or quest.endPlace ~= "") then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Turned in" .. (quest.ender ~= "" and (" to " .. quest.ender) or "")
            .. (quest.endPlace ~= "" and (" at " .. quest.endPlace) or "") .. "."
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
        if #out < 3 and value ~= "" and #value <= MaxLine and not seen[key] then
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

-- The other known quests' objectives.
local function OtherObjectives(state)
    local values = {}
    for _, other in ipairs(state.known) do
        if other.key ~= state.quest.key then
            for _, objective in ipairs(other.objectives) do
                values[#values + 1] = objective.text
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
        if #word >= MinWord and not Words.stopWords[lower(word)] then
            pool[#pool + 1] = word
        end
    end
    local sentences = {}
    for sentence in gmatch(gsub(text, "\n", " ") .. " ", "%s*([^%.!?]+[%.!?])") do
        if #sentence >= MinSentence and #sentence <= MaxSentence and not find(sentence, "\"", 1, true) then
            sentences[#sentences + 1] = sentence
        end
    end
    for _, sentence in ipairs(Shuffle(state, sentences)) do
        local candidates, inSentence = {}, {}
        for word in gmatch(sentence, "%a+") do
            inSentence[lower(word)] = true
            if #word >= MinWord and #word <= MaxWord and not Words.stopWords[lower(word)] then
                candidates[#candidates + 1] = word
            end
        end
        for _, word in ipairs(Shuffle(state, candidates)) do
            local capital = find(word, "^%u") ~= nil
            local _, uses = gsub(sentence, "%f[%a]" .. word .. "%f[%A]", "")
            -- Wrong answers come from the rest of the text: a word the sentence already has would
            -- read oddly in its own blank.
            local wrongs, seen = {}, {}
            for key in pairs(inSentence) do
                seen[key] = true
            end
            for _, other in ipairs(Shuffle(state, pool)) do
                local key = lower(other)
                if not seen[key] and (find(other, "^%u") ~= nil) == capital and #other >= #word - 3 and #other <= #word + 3 then
                    seen[key] = true
                    wrongs[#wrongs + 1] = other
                end
            end
            if #wrongs >= 3 and uses == 1 then -- a word used twice would show through its blank
                local blanked = gsub(sentence, "%f[%a]" .. word .. "%f[%A]", "___", 1)
                return { sentence = blanked, filled = sentence, word = word, wrongs = wrongs }
            end
        end
    end
    return nil
end

Generators["quest.giver"] = function(state)
    local quest = state.quest
    local wrongs = Wrongs(state, quest.giver, Gather(state, "giver", "ender"), Words.questNames)
    return Finish(state, "quest.giver", Words.quest.giver, { title = quest.title, answer = quest.giver }, quest.giver, wrongs)
end

Generators["quest.ender"] = function(state)
    local quest = state.quest
    local wrongs = Wrongs(state, quest.ender, Gather(state, "giver", "ender"), Words.questNames)
    return Finish(state, "quest.ender", Words.quest.ender, { title = quest.title, answer = quest.ender }, quest.ender, wrongs)
end

Generators["quest.place"] = function(state)
    local quest = state.quest
    local wrongs = Wrongs(state, quest.place, Gather(state, "place", "endPlace"), Words.questPlaces, Lowered(quest.zone))
    return Finish(state, "quest.place", Words.quest.place, { title = quest.title, answer = quest.place }, quest.place, wrongs)
end

Generators["quest.endPlace"] = function(state)
    local quest = state.quest
    local wrongs = Wrongs(state, quest.endPlace, Gather(state, "place", "endPlace"), Words.questPlaces, Lowered(quest.endZone))
    return Finish(state, "quest.endPlace", Words.quest.endPlace, { title = quest.title, answer = quest.endPlace },
        quest.endPlace, wrongs)
end

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
    for i, value in ipairs(WrongNumbers(state, n, { n - 1, n + 1, n + 2, n * 2 })) do
        wrongs[i] = tostring(value)
    end
    local vars = { title = state.quest.title, objective = objective.text, answer = n, v = n }
    return Finish(state, "quest.count", Words.quest.count, vars, tostring(n), wrongs)
end

Generators["quest.objective"] = function(state)
    local quest = state.quest
    local own = {}
    for _, objective in ipairs(quest.objectives) do
        own[lower(objective.text)] = true
    end
    local answer = Pick(state, quest.objectives).text
    local wrongs = Wrongs(state, answer, OtherObjectives(state), Words.questObjectives, own)
    return Finish(state, "quest.objective", Words.quest.objective, { title = quest.title, answer = answer }, answer, wrongs)
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
    local wrongs = Wrongs(state, quest.title, others, Words.questTitles, theirs)
    return Finish(state, "quest.title", Words.quest.title, { giver = quest.giver, answer = quest.title }, quest.title, wrongs)
end

Generators["quest.blank"] = function(state)
    local blank = state.blank
    local vars = { title = state.quest.title, sentence = blank.sentence, filled = blank.filled }
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
        counted = counted or objective.required > 1
    end
    Add("quest.giver", quest.giver ~= "")
    Add("quest.ender", quest.turnedIn and quest.ender ~= "")
    Add("quest.place", quest.place ~= "")
    Add("quest.endPlace", quest.turnedIn and quest.endPlace ~= "")
    Add("quest.count", counted)
    Add("quest.objective", #quest.objectives > 0)
    Add("quest.title", quest.giver ~= "" and #quest.title <= MaxLine)
    state.blank = BlankCandidate(state)
    Add("quest.blank", state.blank ~= nil)
    return kinds
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
    for _, other in ipairs(type(known) == "table" and known or {}) do
        state.known[#state.known + 1] = Clean(other)
    end
    for _, kind in ipairs(Shuffle(state, Kinds(state))) do
        local puzzle = Generators[kind](state)
        if Fits(puzzle) then
            puzzle.book = Book(state.quest)
            return puzzle
        end
    end
    return nil
end

Kit.AskQuest = AskQuest
