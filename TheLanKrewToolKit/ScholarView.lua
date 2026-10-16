local addonName, ns = ...

-- The Scholar's challenge screen: one riddle, asked by the Owl Sage, laid out so a child reads it at a glance and wants
-- the next one.
--
--   header    the Owl Sage's portrait and "The Owl Sage asks...", the subject and riddle title;
--             on the right the stars, a bar filling toward the next rank, and the current streak
--   story     the setup; numbers and "quoted words" are highlighted; a Read aloud button beside it,
--             which reads what the screen shows (Speech): the riddle, the open quest book, or the
--             feedback
--   picture   for small numbers in the early grades, the riddle drawn as icons: groups in bags,
--             two piles to join, or a pile with some taken away
--   question  the question itself, the largest text, on its own band
--   answers   a 2 x 2 grid of big answers, each with its key (1-4 or a controller face button) on a
--             raised keycap at its edge; hover glows, a wrong answer turns red and shakes, the right
--             one turns green, and a "+1" rises from the star counter
--   book      on a quest riddle, Need a hint? is the quest book: it puts the quest's whole text, as
--             the player saw it, on a page below the riddle's story, and closes again the same way. The
--             page is at most BookHeight tall (less on a screen without the room), and longer text
--             scrolls, like the quest log: the mouse wheel, the Up and Down arrows, or the D-pad
--             (held, it keeps going), with a slim bar showing where you are
--   footer    Need a hint? and how to answer; feedback (the hint, or the working) replaces it in
--             place, growing down to fit its text, with the buttons centered on it and a stripe that
--             says how it went (red, gold, or green). Every button names its key: the controller's
--             buttons when one is connected (face buttons answer, shoulders ask for the hint and read
--             aloud, Back skips), the keyboard's otherwise
--
-- The panel is opaque and sized to its content, never taller than the screen (less ScreenMargin above and below), over
-- a light shade that lets clicks through to the world. Later, a tab on the panel's top edge, puts the riddle away; it
-- hides while a right answer celebrates. The screen only draws. Scholar.lua owns the rules and gives it handlers
-- through ns.ScholarView.Init before the first Show. ScholarFrame.lua builds its widgets, and their colors, textures,
-- and backdrop come from ns.ScholarStyle (ScholarPictures.lua).

local AnswerGap = 14
-- The least of the open quest book shown, in pixels, however little room the rest of the riddle leaves: about a line.
local BookFloor = 24
-- The most of the open quest book shown at once, in pixels. The rest scrolls.
local BookHeight = 240
local FooterHeight = 44
-- How many pixels the panel sits above the screen's center when it has room.
local LiftUp = 30
-- The least room, in pixels, above and below the panel.
local ScreenMargin = 20
-- Riddles whose wrong choices are misspellings: Read aloud spells their choices.
local SpelledKinds = { ["reading.spelling"] = true, ["reading.sight"] = true }
local SubjectLabels = { math = "MATH", quest = "QUEST", reading = "READING" }
local WordColor = "|cff7fe0ff"

local ceil = math.ceil
local concat = table.concat
local floor = math.floor
local ipairs = ipairs
local max = math.max
local min = math.min
local UIParent = UIParent
local unpack = unpack

local ScholarFrame = ns.ScholarFrame
local AnswerHeight = ScholarFrame.AnswerHeight
local BookInset = ScholarFrame.BookInset
local ButtonWidth = ScholarFrame.ButtonWidth
local Inset = ScholarFrame.Inset
local LabelPill = ScholarFrame.LabelPill
local NumberColor = ScholarFrame.NumberColor
local Pad = ScholarFrame.Pad
local Paint = ScholarFrame.Paint
local Width = ScholarFrame.Width

local ScholarStyle = ns.ScholarStyle
local BackdropColors = ScholarStyle.BackdropColors
local Palette = ScholarStyle.Palette

local ScholarView = {}

ns.ScholarView = ScholarView

local Callbacks
local Overlay
local PlaceFooter

-- Big answers get the biggest font that fits: short numbers huge, long words smaller.
local function AnswerFont(text)
    if #text <= 10 then
        return "Game30Font"
    elseif #text <= 20 then
        return "Game24Font"
    end

    return "Game18Font"
end

-- The prompt as the screen shows it: a line the screen draws instead (the letters as tiles, a row of symbols as a
-- picture) comes out of the text, and an unscramble's clue moves under its tiles. Read aloud still reads the whole
-- prompt.
---@return string shown
---@return string? clue
local function DisplayPrompt(puzzle)
    local drawn = ((puzzle.tiles and concat(puzzle.tiles, " ")) or (puzzle.picture and puzzle.picture.row))

    if not drawn then
        return puzzle.prompt, nil
    end

    local lines = {}
    local clue = nil

    for line in (puzzle.prompt .. "\n"):gmatch("([^\n]*)\n") do
        if puzzle.tiles and line:find("^Clue:") then
            clue = line
        elseif line ~= drawn then
            lines[#lines + 1] = line
        end
    end

    return concat(lines, "\n"), clue
end

--- Highlights numbers (12, 3.5, 25%, 1,000) and "quoted words" with color codes.
---@param text string plain text
---@return string
local function Emphasize(text)
    -- Numbers go first: the color codes added for words contain digits of their own.
    text = text:gsub("(%d[%d,%.]*%%?)", function(number)
        -- A sentence's full stop isn't part of the number.
        local trailing = (number:match("[,%.]+$") or "")

        return (NumberColor .. number:sub(1, #number - #trailing) .. "|r" .. trailing)
    end)

    text = text:gsub('"([^"]+)"', WordColor .. '"%1"|r')

    return text
end

local function Hex(color)
    return ("|cff%02x%02x%02x"):format(floor(color[1] * 255), floor(color[2] * 255), floor(color[3] * 255))
end

-- A hint shown after "Hint:" doesn't need its own "Clue:".
local function HintText(hint)
    return (hint:gsub("^Clue:%s*", ""))
end

-- The quest book's scroll bar: a thumb along the book's right edge, as long as the share of the text in view and as far
-- down as the book is scrolled. It's hidden when the text fits. The view keeps the book's numbers itself (Layout,
-- ScrollBook): m_bookView tall, m_bookRange to scroll, at m_bookOffset.
local function PlaceThumb()
    local thumb = Overlay.Thumb
    local range = Overlay.m_bookRange
    local view = Overlay.m_bookView
    local offset = Overlay.m_bookOffset
    local scrolls = (range > 0)

    Overlay.Track:SetShown(scrolls)
    thumb:SetShown(scrolls)

    if scrolls then
        local size = max((view * view) / (view + range), 24)

        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", Overlay.Book, "TOPRIGHT", 0, (-(view - size) * offset) / range)
    end
end

-- Text as the voice says it: a blank ("___", or a math riddle's "__") is "blank".
local function Sayable(text)
    return (text:gsub("_+", "blank"))
end

-- The screen's height in the overlay's own units. The overlay has no parent (so hiding the UI doesn't hide a riddle),
-- so the UI scale doesn't apply to it, while UIParent's height is in UIParent's units.
local function ScreenHeight()
    -- secret: UIParent is the client's own screen-sized frame, anchored to nothing an addon sets
    return ((UIParent:GetHeight() * UIParent:GetEffectiveScale()) / Overlay:GetEffectiveScale())
end

-- Lays the panel out top to bottom from its content, so it's always exactly as tall as it needs to be, and centers it
-- on screen (LiftUp above center when there's room). Returns its height.
local function Layout(hasStory, puzzle)
    local panel = Overlay.Panel
    local y = 116

    Overlay.Book:SetShown(Overlay.m_bookOpen == true)
    Overlay.BookCase:SetShown(Overlay.m_bookOpen == true)

    if hasStory then
        Overlay.Story:ClearAllPoints()
        Overlay.Story:SetPoint("TOPLEFT", Pad, -y)
        Overlay.Story:Show()
        -- secret: riddle text is built from plain strings, so its fontstrings hold no secret aspect
        y = ((y + max(Overlay.Story:GetStringHeight(), 24)) + 14)
    else
        Overlay.Story:Hide()
    end

    if Overlay.m_bookOpen then
        local case = Overlay.BookCase
        -- secret: the book's text is built from plain strings, as the story's is
        local textHeight = Overlay.BookText:GetStringHeight()
        local view = min(textHeight, BookHeight, Overlay.m_bookRoom)

        -- A book that scrolls shows whole lines, each with its spacing below, so a line's letters that hang below it
        -- (g, p, y) aren't cut at the edge. Its page is as tall as whole lines too, so a scroll always stops on one.
        local pitch = (Overlay.BookText:GetLineHeight() + Overlay.BookText:GetSpacing())
        local page = textHeight

        -- secret: plain, as above
        if view < textHeight then
            view = max(pitch, floor(view / pitch) * pitch)
            -- secret: plain, as above
            page = (view + (ceil((textHeight - view) / pitch) * pitch))
        end

        Overlay.m_bookPitch, Overlay.m_bookView, Overlay.m_bookRange = pitch, view, (page - view)
        Overlay.BookPage:SetHeight(page)
        case:ClearAllPoints()
        case:SetPoint("TOPLEFT", Pad, -y)
        case:SetSize(Width - (2 * Pad), view + (2 * BookInset))
        -- A smaller book can't be scrolled as far.
        Overlay.m_bookOffset = min(Overlay.m_bookOffset, Overlay.m_bookRange)
        Overlay.Book:SetVerticalScroll(Overlay.m_bookOffset)
        PlaceThumb()
        y = (((y + view) + (2 * BookInset)) + 14)
    end

    local pictureHeight = ns.ScholarPictures.Draw(Overlay.Pictures, puzzle.picture, puzzle.tiles)

    if pictureHeight > 0 then
        local pictures = Overlay.Pictures

        pictures:ClearAllPoints()
        pictures:SetPoint("TOP", panel, "TOP", 0, -y)
        y = ((y + pictureHeight) + 14)
    end

    if Overlay.Clue:IsShown() then
        Overlay.Clue:ClearAllPoints()
        Overlay.Clue:SetPoint("TOP", panel, "TOP", 0, -y)
        y = (y + 26)
    end

    -- secret: as above
    local questionHeight = Overlay.Question:GetStringHeight()

    Overlay.Band:ClearAllPoints()
    Overlay.Band:SetPoint("TOPLEFT", Pad, -y)
    Overlay.Band:SetPoint("TOPRIGHT", -Pad, -y)
    -- secret: plain, as above
    Overlay.Band:SetHeight(questionHeight + 30)
    Overlay.Stripe:ClearAllPoints()
    Overlay.Stripe:SetPoint("TOPLEFT", Overlay.Band, "TOPLEFT")
    Overlay.Stripe:SetPoint("BOTTOMLEFT", Overlay.Band, "BOTTOMLEFT")
    Overlay.Question:ClearAllPoints()
    Overlay.Question:SetPoint("TOPLEFT", Pad + Inset, -(y + 15))
    -- secret: plain, as above
    y = (((y + questionHeight) + 30) + 20)

    for i, button in ipairs(Overlay.Buttons) do
        local column = ((i - 1) % 2)
        local row = (((i > 2) and 1) or 0)

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", Pad + (column * (ButtonWidth + AnswerGap)), -(y + (row * (AnswerHeight + AnswerGap))))
    end

    y = (((y + (2 * AnswerHeight)) + AnswerGap) + 16)
    Overlay.FooterTop = y
    local height = ((y + PlaceFooter()) + 18)

    panel:SetHeight(height)
    local room = (((ScreenHeight() - height) / 2) - ScreenMargin)

    panel:ClearAllPoints()
    panel:SetPoint("CENTER", 0, max(0, min(LiftUp, room)))

    return height
end

-- Lays the panel out with the open book in the room the rest of the riddle leaves: the screen, less the margins and the
-- rest. Feedback that grows the footer shrinks the book, so the panel always fits.
local function Refit()
    local puzzle = Overlay.m_puzzle
    local hasStory = (Overlay.m_story ~= "")

    if Overlay.m_bookOpen then
        Overlay.m_bookOpen = false
        local rest = Layout(hasStory, puzzle)

        Overlay.m_bookRoom = max((((ScreenHeight() - (2 * ScreenMargin)) - rest) - 14) - (2 * BookInset), BookFloor)
        Overlay.m_bookOpen = true
    end

    Layout(hasStory, puzzle)
end

-- Shows a message in the footer's place: the hint (gold) or the working (green), and said is the message as plain text,
-- for Read aloud.
local function ShowFeedback(text, tone, said)
    Overlay.m_said = said
    local banner = Overlay.Feedback

    if tone == "right" then
        BackdropColors(banner, Palette.feedbackGood, Palette.feedbackGoodEdge)
    else
        BackdropColors(banner, Palette.feedback, Palette.feedbackEdge)
    end

    -- The stripe says how it went: green when it's right, red for a miss, gold for a hint.
    banner.Stripe:SetColorTexture(unpack((((tone == "right") and Palette.good) or ((tone == "miss") and Palette.bad))
        or Palette.gold))

    banner.Text:SetText(text)
    banner:Show()
    -- On a quest riddle, the hint is the quest book, which stays a click away beside the banner.
    local book = (Overlay.m_puzzle and Overlay.m_puzzle.book)

    Overlay.Hint:SetShown(book ~= nil)
    Refit()
end

local function ShowProgress(info)
    Overlay.Stars:SetText(tostring(info.stars))
    Overlay.Progress:SetValue(info.progress or 1)

    if info.nextRank then
        Overlay.Rank:SetText(("%s%s|r  %s%d more to %s|r"):format(Hex(Palette.story), info.rank, Hex(Palette.muted),
            info.nextAt - info.stars, info.nextRank))
    else
        Overlay.Rank:SetText(Hex(Palette.story) .. info.rank .. "|r")
    end

    if info.streak and (info.streak >= 2) then
        -- A cheer beside a long streak: the riddles getting harder comes first, since it's news.
        local cheer = ((info.levelUp and "harder riddles!") or ((info.streak >= 10) and "the Owl Sage hoots!")
            or ((info.streak >= 5) and "on a roll!") or nil)

        Overlay.Streak:SetText(info.streak .. " in a row" .. ((cheer and ("  -  " .. cheer)) or ""))
        Overlay.Streak:Show()
    else
        Overlay.Streak:Hide()
    end
end

-- A word as its letters, for the voice to spell: "BELIEVE" is "B, E, L, I, E, V, E".
local function Spelled(word)
    local letters = {}

    for letter in word:gmatch("%a") do
        letters[#letters + 1] = letter:upper()
    end

    return concat(letters, ", ")
end

--- Splits a prompt into its story and its question: the question is the last sentence ending in "?" (or the whole
--- prompt when there's none).
---@param prompt string
---@return string story "" when the prompt is only a question
---@return string question
local function Split(prompt)
    prompt = prompt:gsub("%s+$", "")

    if prompt:sub(-1) ~= "?" then
        return "", prompt
    end

    local cut = 0

    for i = #prompt - 1, 1, -1 do
        local character = prompt:sub(i, i)

        if (character == "\n") or (((character == ".") or (character == "!") or (character == "?"))
            and prompt:sub(i + 1, i + 1):match("%s")) then
            cut = i

            break
        end
    end

    local story = prompt:sub(1, cut):gsub("%s+$", ""):gsub("\n", " ")

    return story, (prompt:sub(cut + 1):gsub("^%s+", ""))
end

-- What read-aloud says for choice i: the button that picks it, then the choice (spelled out for a spelling riddle), or
-- nil for a riddle that's heard, whose choices are for reading (unless it speaks its choices, as a heard story does).
local function SpokenChoice(puzzle, i)
    if puzzle.speech and not puzzle.speakChoices then
        return nil
    end

    local choice = puzzle.choices[i]
    local keys = (Overlay and Overlay.m_keys)
    local key = ((keys and keys[i]) or tostring(i))

    if SpelledKinds[puzzle.kind] then
        return ("Press %s: %s."):format(key, Spelled(choice))
    end

    return ("Press %s for %s."):format(key, Sayable(choice))
end

--- Returns what a child hears when they press Read aloud: the story and the question, then each choice with the key
--- that picks it ("Press A for cat."). A spelling riddle's choices are misspelled on purpose, so the voice spells each
--- letter by letter rather than saying a wrong spelling as if it were the word. A heard riddle says only its speech, or
--- its speech and then its choices when it speaks them.
---@param puzzle table
---@return string
local function Spoken(puzzle)
    if puzzle.speech and not puzzle.speakChoices then
        return Sayable(puzzle.speech)
    end

    local spoken = { Sayable(((puzzle.speech or puzzle.prompt):gsub("\n", " "))) }

    for i in ipairs(puzzle.choices) do
        spoken[#spoken + 1] = SpokenChoice(puzzle, i)
    end

    return concat(spoken, " ")
end

-- The footer row: help on the left (Need a hint?, or the feedback banner in its place), and Skip and Read aloud on the
-- right. On a quest riddle, the quest book stays, with the banner beside it. The banner stretches to whichever
-- right-hand button comes first, and grows down to fit its text. Returns the footer's height.
function PlaceFooter()
    local y = Overlay.FooterTop
    local banner = Overlay.Feedback
    local hint = Overlay.Hint
    -- The banner fills the row between the buttons: from the hint's right edge to the right-hand buttons' left.
    local left = Pad
    local right = Pad
    local pills = {}

    if hint:IsShown() then
        -- secret: pill sizes come from fixed strings and key names
        left = ((Pad + hint:GetWidth()) + 10)
    end

    for _, pill in ipairs({ Overlay.Speak, Overlay.Skip }) do
        if pill:IsShown() then
            pills[#pills + 1] = { pill, right }
            -- secret: as above
            right = ((right + pill:GetWidth()) + 8)
        end
    end

    if #pills > 0 then
        right = (right + 2)
    end

    banner.Text:SetWidth(((Width - left) - right) - (Inset + 14))
    -- secret: feedback is built from plain strings, as the riddle's text is
    local height = max(FooterHeight, banner.Text:GetStringHeight() + 20)
    local row = ((banner:IsShown() and height) or FooterHeight)

    banner:ClearAllPoints()
    banner:SetPoint("TOPLEFT", left, -y)
    banner:SetPoint("TOPRIGHT", -right, -y)
    banner:SetHeight(height)
    hint:ClearAllPoints()
    -- secret: as above
    hint:SetPoint("TOPLEFT", Pad, -(y + ((row - hint:GetHeight()) / 2)))

    for _, entry in ipairs(pills) do
        local pill = entry[1]

        pill:ClearAllPoints()
        -- secret: as above
        pill:SetPoint("TOPRIGHT", -entry[2], -(y + ((row - pill:GetHeight()) / 2)))
    end

    return row
end

ScholarView.Emphasize = Emphasize
ScholarView.Split = Split
ScholarView.Spoken = Spoken

--- Returns whether the quest book is open.
---@return boolean
function ScholarView.BookOpen()
    return ((Overlay ~= nil) and (Overlay.m_bookOpen == true))
end

--- Marks answer i right, dims the others, shows the working, and celebrates the new star.
---@param i integer
---@param explanation string
---@param info table the new progress, as for Show
function ScholarView.Correct(i, explanation, info)
    for j, button in ipairs(Overlay.Buttons) do
        button:Disable()
        Paint(button, ((j == i) and "right") or "dim")
    end

    ShowFeedback("|cff59f273Correct!|r  " .. Emphasize(explanation), "right", "Correct! " .. explanation)
    Overlay.Gain:SetText("+" .. max(info.earned or 1, 1))
    Overlay.Rise:Stop()
    Overlay.Rise:Play()
    Overlay.Later:Hide()
    ShowProgress(info)
end

--- Returns the full-screen overlay, or nil before the first Show. Among its children: Buttons[1..4] (each with Key,
--- Keycap, Text, Mark, Shake, and State: "normal", "hover", "wrong", "right", or "dim"), Portrait, Asks, Tag, Stars,
--- StarIcon, Progress, Rank, Streak, Gain (raised by Rise), Story, Speak, Pictures (Icons, Cards, Tiles), Clue,
--- Question, Hint, Skip, and Feedback (a banner with Text).
---@return table?
function ScholarView.Frame()
    return Overlay
end

--- Hides the screen. The caller gives the keyboard back.
function ScholarView.Hide()
    if Overlay then
        Overlay:Hide()
    end
end

--- Shows the hint in the footer's place (no penalty: asking for help is part of learning).
---@param hint string
function ScholarView.Hint(label, hint)
    ShowFeedback(NumberColor .. label .. ":|r  " .. Emphasize(HintText(hint)), "hint", (label .. ": " .. HintText(hint)))
end

--- Sets the handlers the screen calls back: choose(i) for an answer selected, skip() for Skip, hint() for Need a hint?,
--- speak() for Read aloud, later() for Later, wishes() for Wishes, and key(key) for every key pressed while the screen
--- has the keyboard, which returns whether the riddle used the key (any other reaches the game).
---@param handlers table { choose, skip, hint, speak, later, wishes, key }
function ScholarView.Init(handlers)
    Callbacks = handlers
end

--- Returns whether the screen is showing.
---@return boolean
function ScholarView.IsShown()
    return ((Overlay ~= nil) and Overlay:IsShown())
end

--- Shows text in the feedback banner as the Owl's own words, the way a hint shows, and Read aloud says it.
---@param text string
function ScholarView.Note(text)
    ShowFeedback(text, "hint", text)
end

--- Scrolls the open quest book by notches (positive is down, two lines each), never past the top or the end of its
--- text.
---@param notches number
function ScholarView.ScrollBook(notches)
    if not ScholarView.BookOpen() then
        return
    end

    -- Two whole lines a notch, so the page stops on a line.
    local step = (2 * Overlay.m_bookPitch)

    Overlay.m_bookOffset = max(0, min(Overlay.m_bookOffset + (notches * step), Overlay.m_bookRange))
    Overlay.Book:SetVerticalScroll(Overlay.m_bookOffset)
    PlaceThumb()
end

--- Shows a puzzle, creating the screen on first use. The caller takes the keyboard.
---@param puzzle table a puzzle from ns.Puzzles.Generate
---@param info table { stars, rank, nextRank?, nextAt?, progress (0 to 1), streak, gentle, canSpeak,
---                  controller (a controller is connected), keys = { four answer key labels },
---                  actions = { hint, speak, skip key labels }, wrong? ([i] = true for answers already missed, which
---                  stay marked and can't be picked), canSkip? (Skip shows), book? (Need a hint? is the quest book,
---                  puzzle.book's text) }
---@return table frame the full-screen overlay
function ScholarView.Show(puzzle, info)
    Overlay = (Overlay or ScholarFrame.Create(Callbacks))
    local subject = ((SubjectLabels[puzzle.subject] and puzzle.subject) or "math")

    -- A stretch riddle says so: it's meant to be hard, and its help comes sooner.
    local label = (SubjectLabels[subject] .. ((puzzle.stretch and " STRETCH") or ""))

    Overlay.Tag:SetText(("%s%s|r  %s-  %s|r"):format(Hex(Palette[subject]), label, Hex(Palette.muted), puzzle.title))

    ShowProgress(info)
    local shown, clue = DisplayPrompt(puzzle)
    local story, question = Split(shown)

    Overlay.Clue:SetText((clue and Emphasize(clue)) or "")
    Overlay.Clue:SetShown(clue ~= nil)
    Overlay.Story:SetText(Emphasize(story))
    Overlay.m_puzzle, Overlay.m_story, Overlay.m_bookOpen, Overlay.m_said = puzzle, story, false, nil
    Overlay.m_keys = info.keys
    Overlay.Question:SetFontObject(((#question <= 44) and "Game30Font") or "Game24Font")
    Overlay.Question:SetText(Emphasize(question))

    for i, button in ipairs(Overlay.Buttons) do
        local choice = puzzle.choices[i]

        button.Key:SetText(info.keys[i])
        button.Text:SetFontObject(AnswerFont(choice))
        button.Text:SetText(choice)
        local missed = (info.wrong and info.wrong[i])

        button:SetEnabled(not missed)
        Paint(button, (missed and "wrong") or ((info.reveal == i) and "reveal") or "normal")
    end

    local actions = (info.actions or {})

    Overlay.Speak.m_text = ((puzzle.speech and "Hear it again") or "Read aloud")
    LabelPill(Overlay.Speak, actions.speak)
    Overlay.Hint.m_text, Overlay.Hint.m_key = ((info.book and "Quest book") or "Need a hint?"), actions.hint
    LabelPill(Overlay.Hint, actions.hint)
    LabelPill(Overlay.Skip, actions.skip)
    LabelPill(Overlay.Later, actions.later)
    Overlay.Later:Show()
    LabelPill(Overlay.Wishes, actions.wishes)
    Overlay.Speak:SetShown((info.canSpeak and true) or false)
    Overlay.Feedback:Hide()
    Overlay.Hint:Show()
    Overlay.Skip:SetShown((info.canSkip and true) or false)
    Layout(story ~= "", puzzle)
    Overlay:Show()

    return Overlay
end

--- Returns what Read aloud says for what the screen shows now: the open quest book, else the feedback shown (the hint
--- or the working), else the riddle (Spoken). Call it only while a riddle is on screen.
---@return string
function ScholarView.Speech()
    if Overlay.m_bookOpen then
        return Sayable(Overlay.m_puzzle.book)
    end

    return ((Overlay.m_said and Sayable(Overlay.m_said)) or Spoken(Overlay.m_puzzle))
end

--- Returns what read-aloud says for choice i of the riddle on screen ("Press A for cat."), or nil for a riddle that's
--- heard, whose choices are for reading. Call it only while a riddle is on screen.
---@param i integer
---@return string?
function ScholarView.SpokenChoice(i)
    return SpokenChoice(Overlay.m_puzzle, i)
end

--- Opens the quest book below the riddle's story, or closes it again: the quest's text, as the player saw it, holds
--- every answer to a quest riddle. It opens at the top, as tall as its text, BookHeight, or the room the screen leaves,
--- whichever is least, and scrolls the rest (ScrollBook). Call it only while a puzzle with a book is on screen.
function ScholarView.ToggleBook()
    local open = not Overlay.m_bookOpen

    if open then
        Overlay.BookText:SetText(Emphasize(Overlay.m_puzzle.book))
        Overlay.Book:SetVerticalScroll(0)
        Overlay.m_bookOffset = 0
    end

    Overlay.m_bookOpen = open
    Overlay.Hint.m_text = ((open and "Close book") or "Quest book")
    LabelPill(Overlay.Hint, Overlay.Hint.m_key)
    Refit()
end

--- Makes the answers still open wait seconds before they can be picked (the pause after a miss), dimmed, with their
--- keycaps counting it down; 0 wakes them, with their keys back. A revealed answer keeps its glow while it waits.
---@param seconds integer
function ScholarView.Wait(seconds)
    for i, button in ipairs(Overlay.Buttons) do
        if button.State ~= "wrong" then
            button.Key:SetText(((seconds > 0) and tostring(seconds)) or Overlay.m_keys[i])
            button:SetEnabled(seconds <= 0)

            if button.State ~= "reveal" then
                Paint(button, ((seconds > 0) and "dim") or "normal")
            end
        end
    end
end

--- Marks answer i wrong (it shakes and can't be picked again), shows the hint, and offers Skip when canSkip.
---@param i integer
---@param hint string
---@param canSkip boolean
function ScholarView.Wrong(i, why, label, hint, canSkip, reveal)
    local button = Overlay.Buttons[i]

    button:Disable()
    Paint(button, "wrong")
    button.Shake:Stop()
    button.Shake:Play()

    if reveal then
        Paint(Overlay.Buttons[reveal], "reveal")
    end

    local because = ((why and (Emphasize(why) .. "  ")) or "")

    ShowFeedback((((("|cffff665aNot quite.|r  " .. because) .. NumberColor) .. label) .. ":|r  ") .. Emphasize(HintText(hint)),
        "miss", ("Not quite. " .. ((why and (why .. " ")) or "")) .. label .. ": " .. HintText(hint))

    if canSkip then
        Overlay.Skip:Show()
        Refit()
    end
end
