-- Scholar for children still learning to read: riddles said aloud as they appear (readAloud: kindergarten and grade 1
-- by default), each choice said with the key that picks it, heard riddles whose word is only spoken, and heard stories
-- whose story is only spoken, with their choices said after it. With no text-to-speech voice, nothing tries to speak
-- and no heard riddle is asked.

local Kit = use("scholar")
local LoadKid, Watch = Kit.LoadKid, Kit.Watch

local HeardKinds = { ["reading.listen"] = true, ["reading.listenSound"] = true, ["reading.listenStory"] = true }
-- The heard kinds whose word is only spoken, and whose choices are for reading.
local WordKinds = { ["reading.listen"] = true, ["reading.listenSound"] = true }

-- A kindergartner's character asking only reading riddles, with every reading skill but kind resting (mastered and not
-- due), so kind is asked next.
local function OnlyNext(kind, extra)
    local settings = { ["Scholar.grade"] = "0", ["Scholar.math"] = false, ["Scholar.quests"] = false }

    for key, value in pairs(extra or {}) do
        settings[key] = value
    end

    local h, addon, ns = LoadKid(settings)

    for _, other in ipairs(ns.Puzzles.Kinds("reading", 0, true)) do
        if other ~= kind then
            addon.Modules.Scholar.Records.skills:Set(other, { asked = 3, box = 5, due = 99, firstTry = 3, recent = "111" })
        end
    end

    return h, addon, ns
end

-- What was said since from (an index into h.spoken), joined.
local function SaidSince(h, from)
    local texts = {}

    for i = from, #h.spoken do
        texts[#texts + 1] = h.spoken[i].text
    end

    return table.concat(texts, " | ")
end

test("a kindergarten riddle is said aloud as it appears, with each choice and its key; grade 2 waits to be asked", function()
    local h, _, ns = OnlyNext("reading.rhyme")
    local shown = Watch(ns)
    local from = (#h.spoken + 1)

    h:Slash("/tlk puzzle")
    local said = SaidSince(h, from)

    truthy(said:find(("Press 1 for %s."):format(shown[#shown].choices[1]), 1, true), said)
    local h2 = LoadKid({ ["Scholar.grade"] = "2", ["Scholar.quests"] = false })

    from = (#h2.spoken + 1)
    h2:Slash("/tlk puzzle")
    eq(SaidSince(h2, from), "", "grade 2 isn't said aloud unless asked")
    local h3 = LoadKid({ ["Scholar.grade"] = "2", ["Scholar.quests"] = false, ["Scholar.readAloud"] = "always" })

    from = (#h3.spoken + 1)
    h3:Slash("/tlk puzzle")
    truthy(SaidSince(h3, from) ~= "", "always means every grade")
end)

test("hovering a choice says it with its key while riddles are read aloud, and not when they're only read on request", function()
    local h, _, ns = OnlyNext("reading.rhyme")
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")
    local frame = rawget(h.env, "TheLanKrewToolKitScholar")
    local from = (#h.spoken + 1)

    h:Hover(frame.Buttons[2], true)
    eq(SaidSince(h, from), ("Press 2 for %s."):format(shown[#shown].choices[2]))
    local quiet = OnlyNext("reading.rhyme", { ["Scholar.readAloud"] = "off" })

    quiet:Slash("/tlk puzzle")
    from = (#quiet.spoken + 1)
    quiet:Hover(rawget(quiet.env, "TheLanKrewToolKitScholar").Buttons[2], true)
    eq(SaidSince(quiet, from), "", "off: a hover says nothing")
end)

test("a heard riddle says only its word, even with read-aloud off, never shows it, and its button is Hear it again", function()
    for kind in pairs(WordKinds) do
        local h, _, ns = OnlyNext(kind, { ["Scholar.readAloud"] = "off" })
        local shown = Watch(ns)
        local from = (#h.spoken + 1)

        h:Slash("/tlk puzzle")
        local puzzle = shown[#shown]

        eq(puzzle.kind, kind)
        eq(SaidSince(h, from), puzzle.speech, kind .. ": it says the word, not the choices")
        local frame = rawget(h.env, "TheLanKrewToolKitScholar")

        truthy(Harness.State(frame.Speak.Label).text:find("Hear it again", 1, true), kind)
        from = (#h.spoken + 1)
        h:Hover(frame.Buttons[1], true)
        eq(SaidSince(h, from), "", kind .. ": a hover never reads a heard riddle's choices")
        h:Key("R", true)
        eq(SaidSince(h, from), puzzle.speech, kind .. ": Hear it again says the word again")
        h:Key(tostring(puzzle.answer), true)
        truthy(frame.Buttons[puzzle.answer].State == "right", kind .. ": the right choice is right")
    end
end)

test("a heard story says the story, the question and each choice with its key, even with read-aloud off, and never shows the story", function()
    local h, _, ns = OnlyNext("reading.listenStory", { ["Scholar.readAloud"] = "off" })
    local shown = Watch(ns)
    local from = (#h.spoken + 1)

    h:Slash("/tlk puzzle")
    local puzzle = shown[#shown]
    local choices = {}

    for i, choice in ipairs(puzzle.choices) do
        choices[i] = ("Press %d for %s."):format(i, choice)
    end

    local said = ("%s %s"):format(puzzle.speech, table.concat(choices, " "))

    eq(puzzle.kind, "reading.listenStory")
    eq(SaidSince(h, from), said, "the story and question, then the choices")
    local frame = rawget(h.env, "TheLanKrewToolKitScholar")
    local story = puzzle.speech:sub(1, 30)

    falsy((Harness.State(frame.Question).text or ""):find(story, 1, true), "the question band doesn't show the story")
    falsy((Harness.State(frame.Story).text or ""):find(story, 1, true), "the story band doesn't show it")
    truthy(Harness.State(frame.Speak.Label).text:find("Hear it again", 1, true))
    from = (#h.spoken + 1)
    h:Key("R", true)
    eq(SaidSince(h, from), said, "Hear it again says it all again")
    h:Key(tostring(puzzle.answer), true)
    truthy(frame.Buttons[puzzle.answer].State == "right", "the right choice is right")
    local young, _, youngNs = OnlyNext("reading.listenStory")
    local youngShown = Watch(youngNs)

    young:Slash("/tlk puzzle")
    from = (#young.spoken + 1)
    young:Hover(rawget(young.env, "TheLanKrewToolKitScholar").Buttons[2], true)
    eq(SaidSince(young, from), ("Press 2 for %s."):format(youngShown[#youngShown].choices[2]), "a hover says its choice")
end)

test("with no text-to-speech voice, nothing is said, Read aloud hides, and no heard riddle is asked", function()
    local h, _, ns = LoadKid({ ["Scholar.grade"] = "0", ["Scholar.math"] = false, ["Scholar.quests"] = false })
    local shown = Watch(ns)

    h.ttsVoices = {}
    eq(#ns.Puzzles.Kinds("reading", 0, false), #ns.Puzzles.Kinds("reading", 0, true) - 3, "the heard kinds are left out")

    for _ = 1, 12 do
        h:Slash("/tlk puzzle")
        local puzzle = shown[#shown]

        falsy(HeardKinds[puzzle.kind], puzzle.kind)
        h:Key(tostring(puzzle.answer), true)
        h:Advance(2)
    end

    eq(#h.spoken, 0, "nothing tried to speak")
    h:Slash("/tlk puzzle")
    falsy(rawget(h.env, "TheLanKrewToolKitScholar").Speak:IsShown(), "Read aloud hides")
end)
