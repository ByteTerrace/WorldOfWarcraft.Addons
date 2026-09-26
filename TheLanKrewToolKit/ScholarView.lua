local addonName, ns = ...

-- The Scholar's challenge screen: one riddle, asked by the Owl Sage, laid out so a child reads it
-- at a glance and wants the next one.
--
--   header    the Owl Sage's portrait and "The Owl Sage asks...", the subject and riddle title;
--             on the right the stars, a bar filling toward the next rank, and the current streak
--   story     the setup; numbers and "quoted words" are highlighted; a Read aloud button beside it
--   picture   for small numbers in the early grades, the riddle drawn as icons: groups in bags,
--             two piles to join, or a pile with some taken away
--   question  the actual question, the largest text, on its own band
--   answers   a 2 x 2 grid of big answers, each with its key (1-4 or a controller face button) on a
--             raised keycap at its edge; hover glows, a wrong answer turns red and shakes, the right
--             one turns green and a "+1" rises from the star counter
--   footer    Need a hint? and how to answer; feedback (the hint, or the working) replaces it in
--             place, so the panel never jumps. Every button names its key: the controller's
--             buttons when one is connected (face buttons answer, shoulders ask for the hint and read
--             aloud, Back skips), the keyboard's otherwise
--
-- The panel is opaque and sized to its content, over a dark shade. The screen only draws;
-- Scholar.lua owns the rules and gives it handlers through ns.ScholarView.Init before the first
-- Show. Its colors, textures and backdrop come from ns.ScholarStyle (ScholarPictures.lua).

local Width = 760
local Pad = 28
local AnswerHeight = 72
local AnswerGap = 14
local ButtonWidth = (Width - 2 * Pad - AnswerGap) / 2
local KeycapSize = 34
local FooterHeight = 44
local PortraitSize = 60
local OwlIcon = "Interface\\Icons\\Ability_Hunter_Pet_Owl"
local CircleMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RightIcon = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local SpeakerIcon = "Interface\\Common\\VoiceChat-Speaker"
local NumberColor = "|cffffd100"
local WordColor = "|cff7fe0ff"

local CreateFrame = CreateFrame
local floor, max = math.floor, math.max
local concat = table.concat

local ScholarStyle = ns.ScholarStyle
local Palette, Solid, StarIcon, WrongIcon = ScholarStyle.Palette, ScholarStyle.Solid, ScholarStyle.StarIcon,
    ScholarStyle.WrongIcon
local Backdrop, TextColor = ScholarStyle.Backdrop, ScholarStyle.TextColor

local ScholarView = {}
ns.ScholarView = ScholarView

local Overlay, Callbacks
local PlaceFooter

--- Highlights numbers (12, 3.5, 25%, 1,000) and "quoted words" with color codes.
---@param text string plain text
---@return string
local function Emphasize(text)
    -- Numbers go first: the color codes added for words contain digits of their own.
    text = text:gsub("(%d[%d,%.]*%%?)", function(number)
        local trailing = number:match("[,%.]+$") or "" -- a sentence's full stop isn't part of the number
        return NumberColor .. number:sub(1, #number - #trailing) .. "|r" .. trailing
    end)
    text = text:gsub('"([^"]+)"', WordColor .. '"%1"|r')
    return text
end

--- Splits a prompt into its story and its question: the question is the last sentence ending in
--- "?" (or the whole prompt when there's none).
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
        if character == "\n" or ((character == "." or character == "!" or character == "?")
            and prompt:sub(i + 1, i + 1):match("%s")) then
            cut = i
            break
        end
    end
    local story = prompt:sub(1, cut):gsub("%s+$", ""):gsub("\n", " ")
    return story, (prompt:sub(cut + 1):gsub("^%s+", ""))
end

--- What a child hears when they press Read aloud: the story, the question, then the choices.
---@param puzzle table
---@return string
local function Spoken(puzzle)
    local choices = puzzle.choices
    return ("%s Is it %s, %s, %s, or %s?"):format(puzzle.prompt:gsub("\n", " "), choices[1], choices[2], choices[3], choices[4])
end

-- The prompt as the screen shows it: a line the screen draws instead (the letters as tiles, a row
-- of symbols as a picture) comes out of the text, and an unscramble's clue moves under its tiles.
-- Read aloud still reads the whole prompt.
---@return string shown
---@return string? clue
local function DisplayPrompt(puzzle)
    local drawn = puzzle.tiles and concat(puzzle.tiles, " ") or (puzzle.picture and puzzle.picture.row)
    if not drawn then
        return puzzle.prompt, nil
    end
    local lines, clue = {}, nil
    for line in (puzzle.prompt .. "\n"):gmatch("([^\n]*)\n") do
        if puzzle.tiles and line:find("^Clue:") then
            clue = line
        elseif line ~= drawn then
            lines[#lines + 1] = line
        end
    end
    return concat(lines, "\n"), clue
end

-- A hint shown after "Hint:" doesn't need its own "Clue:".
local function HintText(hint)
    return (hint:gsub("^Clue:%s*", ""))
end

-- Big answers get the biggest font that fits: short numbers huge, long words smaller.
local function AnswerFont(text)
    if #text <= 10 then
        return "Game30Font"
    elseif #text <= 20 then
        return "Game24Font"
    end
    return "Game18Font"
end

local function Fill(region, color, alpha)
    region:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

local function Hex(color)
    return ("|cff%02x%02x%02x"):format(floor(color[1] * 255), floor(color[2] * 255), floor(color[3] * 255))
end

local function Paint(button, state)
    button.State = state
    local background, edge, text, key = Palette.button, Palette.edge, Palette.question, Palette.story
    local mark
    if state == "hover" then
        edge = Palette.gold
    elseif state == "wrong" then
        background, edge, text, key, mark = { 0.24, 0.07, 0.06 }, Palette.bad, Palette.muted, Palette.muted, WrongIcon
    elseif state == "right" then
        background, edge, mark = { 0.08, 0.26, 0.1 }, Palette.good, RightIcon
    elseif state == "dim" then
        edge, text, key = { 0.28, 0.23, 0.14 }, Palette.muted, Palette.muted
    end
    button:SetBackdropColor(background[1], background[2], background[3], 1)
    button:SetBackdropBorderColor(edge[1], edge[2], edge[3])
    TextColor(button.Text, text)
    TextColor(button.Key, key)
    Fill(button.Keycap, (state == "dim" or state == "wrong") and Palette.keycapDim or Palette.keycap)
    button.Mark:SetTexture(mark)
    button.Mark:SetShown(mark ~= nil)
end

-- A quick side-to-side shake, for a wrong answer.
local function CreateShake(button)
    local group = button:CreateAnimationGroup()
    for order, offset in ipairs({ 8, -16, 12, -4 }) do
        local move = group:CreateAnimation("Translation")
        move:SetOffset(offset, 0)
        move:SetDuration(0.05)
        move:SetOrder(order)
    end
    return group
end

local function CreateAnswer(panel, i)
    local button = CreateFrame("Button", nil, panel, "BackdropTemplate")
    button:SetSize(ButtonWidth, AnswerHeight)
    Backdrop(button, 14)

    -- The keycap: a raised key at the button's edge, so "1" never reads as part of the answer.
    local cap = button:CreateTexture(nil, "ARTWORK")
    cap:SetSize(KeycapSize, KeycapSize)
    cap:SetPoint("LEFT", 12, 0)
    Fill(cap, { 0, 0, 0 }, 0.7)
    local top = button:CreateTexture(nil, "ARTWORK", nil, 1)
    top:SetPoint("TOPLEFT", cap, "TOPLEFT", 1, -1)
    top:SetPoint("BOTTOMRIGHT", cap, "BOTTOMRIGHT", -1, 3)
    Fill(top, Palette.keycap)
    button.Keycap = top
    button.Key = button:CreateFontString(nil, "OVERLAY", "Game18Font")
    button.Key:SetPoint("CENTER", top, "CENTER", 0, 1)

    -- The answer centers on the whole button; the keycap sits at its edge.
    button.Text = button:CreateFontString(nil, "OVERLAY", "Game30Font")
    button.Text:SetPoint("LEFT", KeycapSize + 24, 0)
    button.Text:SetPoint("RIGHT", -(KeycapSize + 24), 0)
    button.Text:SetJustifyH("CENTER")
    button.Text:SetWordWrap(true)

    button.Mark = button:CreateTexture(nil, "OVERLAY")
    button.Mark:SetSize(26, 26)
    button.Mark:SetPoint("RIGHT", -16, 0)
    button.Shake = CreateShake(button)

    button:SetScript("OnClick", function() Callbacks.choose(i) end)
    button:SetScript("OnEnter", function(self)
        if self.State == "normal" then Paint(self, "hover") end
    end)
    button:SetScript("OnLeave", function(self)
        if self.State == "hover" then Paint(self, "normal") end
    end)
    return button
end

-- Small text buttons (Need a hint?, Read aloud, Skip).
local function CreatePill(parent, text, icon)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    Backdrop(button, 10)
    button:SetBackdropColor(0.14, 0.1, 0.05, 1)
    button:SetBackdropBorderColor(Palette.edge[1], Palette.edge[2], Palette.edge[3])
    local left = 12
    if icon then
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetSize(16, 16)
        button.Icon:SetPoint("LEFT", 10, 0)
        button.Icon:SetTexture(icon)
        left = 32
    end
    button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.Label:SetPoint("LEFT", left, 0)
    button.m_left, button.m_text = left, text
    button:SetHeight(28)
    button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(Palette.gold[1], Palette.gold[2], Palette.gold[3]) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(Palette.edge[1], Palette.edge[2], Palette.edge[3]) end)
    return button
end

-- Labels a pill with its key ("LB  Need a hint?") and fits the pill to it.
local function LabelPill(button, key)
    button.Label:SetText(key and (NumberColor .. key .. "|r  " .. button.m_text) or button.m_text)
    -- secret: pill labels are built from fixed strings and key names, so they hold no secret aspect
    button:SetWidth(button.m_left + button.Label:GetStringWidth() + 14)
end

local function CreateHeader(frame, panel)
    local ring = panel:CreateTexture(nil, "ARTWORK")
    ring:SetSize(PortraitSize + 6, PortraitSize + 6)
    ring:SetPoint("TOPLEFT", Pad - 3, -15)
    Fill(ring, Palette.gold)
    local portrait = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    portrait:SetSize(PortraitSize, PortraitSize)
    portrait:SetPoint("CENTER", ring, "CENTER")
    portrait:SetTexture(OwlIcon)
    for _, texture in ipairs({ ring, portrait }) do
        local mask = panel:CreateMaskTexture()
        mask:SetTexture(CircleMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
    end
    frame.Portrait = portrait

    frame.Asks = panel:CreateFontString(nil, "OVERLAY", "Game20Font")
    frame.Asks:SetPoint("TOPLEFT", Pad + PortraitSize + 16, -24)
    frame.Asks:SetText("The Owl Sage asks...")
    TextColor(frame.Asks, Palette.gold)
    frame.Tag = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Tag:SetPoint("TOPLEFT", frame.Asks, "BOTTOMLEFT", 0, -6)

    frame.Stars = panel:CreateFontString(nil, "OVERLAY", "Game24Font")
    frame.Stars:SetPoint("TOPRIGHT", -Pad, -18)
    TextColor(frame.Stars, Palette.gold)
    frame.StarIcon = panel:CreateTexture(nil, "ARTWORK")
    frame.StarIcon:SetSize(22, 22)
    frame.StarIcon:SetTexture(StarIcon)
    frame.StarIcon:SetPoint("RIGHT", frame.Stars, "LEFT", -6, 0)

    local bar = CreateFrame("StatusBar", nil, panel, "BackdropTemplate")
    bar:SetSize(210, 10)
    bar:SetPoint("TOPRIGHT", -Pad, -52)
    bar:SetStatusBarTexture(Solid)
    bar:SetStatusBarColor(Palette.gold[1], Palette.gold[2], Palette.gold[3])
    bar:SetMinMaxValues(0, 1)
    bar.Edge = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bar.Edge:SetPoint("TOPLEFT", -1, 1)
    bar.Edge:SetPoint("BOTTOMRIGHT", 1, -1)
    Fill(bar.Edge, Palette.gold, 0.45)
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    Fill(bar.Background, { 0, 0, 0 }, 1)
    frame.Progress = bar
    frame.Rank = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.Rank:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -5)
    frame.Streak = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.Streak:SetPoint("TOPRIGHT", frame.Rank, "BOTTOMRIGHT", 0, -3)
    TextColor(frame.Streak, Palette.streak)

    -- "+1" rises and fades above the star counter when a star is earned.
    frame.Gain = panel:CreateFontString(nil, "OVERLAY", "Game24Font")
    frame.Gain:SetPoint("BOTTOM", frame.Stars, "TOP", 0, -4)
    TextColor(frame.Gain, Palette.gold)
    frame.Gain:SetAlpha(0)
    local rise = frame.Gain:CreateAnimationGroup()
    local up = rise:CreateAnimation("Translation")
    up:SetOffset(0, 24)
    up:SetDuration(1)
    local fade = rise:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.4)
    fade:SetDuration(0.6)
    frame.Rise = rise

    frame.Rule = panel:CreateTexture(nil, "ARTWORK")
    frame.Rule:SetHeight(1)
    frame.Rule:SetPoint("TOPLEFT", Pad, -98)
    frame.Rule:SetPoint("TOPRIGHT", -Pad, -98)
    Fill(frame.Rule, Palette.gold, 0.3)
end

local function CreateBody(frame, panel)
    frame.Story = panel:CreateFontString(nil, "OVERLAY", "Game20Font")
    frame.Story:SetWidth(Width - 2 * Pad)
    frame.Story:SetJustifyH("LEFT")
    frame.Story:SetWordWrap(true)
    frame.Story:SetSpacing(4)
    TextColor(frame.Story, Palette.story)
    frame.Speak = CreatePill(panel, "Read aloud", SpeakerIcon)
    frame.Speak:SetScript("OnClick", function() Callbacks.speak() end)

    frame.Pictures = ns.ScholarPictures.Create(panel)
    frame.Clue = panel:CreateFontString(nil, "OVERLAY", "Game18Font")
    TextColor(frame.Clue, Palette.muted)

    frame.Band = panel:CreateTexture(nil, "BORDER")
    Fill(frame.Band, Palette.band)
    frame.Stripe = panel:CreateTexture(nil, "ARTWORK")
    frame.Stripe:SetWidth(4)
    Fill(frame.Stripe, Palette.gold)
    frame.Question = panel:CreateFontString(nil, "OVERLAY", "Game30Font")
    frame.Question:SetWidth(Width - 2 * Pad - 48)
    frame.Question:SetJustifyH("LEFT")
    frame.Question:SetWordWrap(true)
    frame.Question:SetSpacing(4)
    TextColor(frame.Question, Palette.question)

    frame.Buttons = {}
    for i = 1, 4 do
        frame.Buttons[i] = CreateAnswer(panel, i)
    end
end

local function CreateFooter(frame, panel)
    frame.Hint = CreatePill(panel, "Need a hint?")
    frame.Hint:SetScript("OnClick", function() Callbacks.hint() end)
    frame.Skip = CreatePill(panel, "Skip")
    frame.Skip:SetScript("OnClick", function() Callbacks.skip() end)

    local banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    Backdrop(banner, 10)
    banner.Text = banner:CreateFontString(nil, "OVERLAY", "Game18Font")
    banner.Text:SetPoint("LEFT", 14, 0)
    banner.Text:SetPoint("RIGHT", -14, 0)
    banner.Text:SetJustifyH("LEFT")
    banner.Text:SetWordWrap(true)
    TextColor(banner.Text, Palette.story)
    frame.Feedback = banner
end

local function Create()
    -- Parentless, so hiding the UI (Alt+Z) doesn't hide the riddle.
    local frame = CreateFrame("Frame", addonName .. "Scholar")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetAllPoints(UIParent)
    frame:EnableMouse(true)
    frame:Hide()

    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.85)

    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetWidth(Width)
    panel:SetPoint("CENTER", 0, 30)
    Backdrop(panel, 16)
    panel:SetBackdropColor(Palette.panel[1], Palette.panel[2], Palette.panel[3], 1)
    panel:SetBackdropBorderColor(Palette.gold[1], Palette.gold[2], Palette.gold[3])
    frame.Panel = panel

    CreateHeader(frame, panel)
    CreateBody(frame, panel)
    CreateFooter(frame, panel)
    frame:SetScript("OnKeyDown", function(_, key) Callbacks.key(key) end)
    return frame
end

-- The footer row: help on the left (Need a hint?, or the feedback banner in its place), Skip and
-- Read aloud on the right. The banner stretches to whichever right-hand button comes first.
function PlaceFooter()
    local y = Overlay.FooterTop
    Overlay.Hint:ClearAllPoints()
    Overlay.Hint:SetPoint("TOPLEFT", Pad, -(y + 8))
    local right = -Pad
    local leftmost
    for _, pill in ipairs({ Overlay.Speak, Overlay.Skip }) do
        if pill:IsShown() then
            pill:ClearAllPoints()
            pill:SetPoint("TOPRIGHT", right, -(y + 8))
            -- secret: pill sizes come from fixed strings and key names
            right = right - pill:GetWidth() - 8
            leftmost = pill
        end
    end
    local banner = Overlay.Feedback
    banner:ClearAllPoints()
    banner:SetPoint("TOPLEFT", Pad, -y)
    if leftmost then
        banner:SetPoint("TOPRIGHT", leftmost, "TOPLEFT", -10, 8)
    else
        banner:SetPoint("TOPRIGHT", -Pad, -y)
    end
    banner:SetHeight(FooterHeight)
end

-- Lays the panel out top to bottom from its content, so it's always exactly as tall as it needs
-- to be.
local function Layout(hasStory, puzzle)
    local panel, y = Overlay.Panel, 116
    if hasStory then
        Overlay.Story:ClearAllPoints()
        Overlay.Story:SetPoint("TOPLEFT", Pad, -y)
        Overlay.Story:Show()
        -- secret: riddle text is built from plain strings, so its fontstrings hold no secret aspect
        y = y + max(Overlay.Story:GetStringHeight(), 24) + 14
    else
        Overlay.Story:Hide()
    end
    local pictureHeight = ns.ScholarPictures.Draw(Overlay.Pictures, puzzle.picture, puzzle.tiles)
    if pictureHeight > 0 then
        local pictures = Overlay.Pictures
        pictures:ClearAllPoints()
        pictures:SetPoint("TOP", panel, "TOP", 0, -y)
        y = y + pictureHeight + 14
    end
    if Overlay.Clue:IsShown() then
        Overlay.Clue:ClearAllPoints()
        Overlay.Clue:SetPoint("TOP", panel, "TOP", 0, -y)
        y = y + 26
    end
    -- secret: as above
    local questionHeight = Overlay.Question:GetStringHeight()
    Overlay.Band:ClearAllPoints()
    Overlay.Band:SetPoint("TOPLEFT", Pad, -y)
    Overlay.Band:SetPoint("TOPRIGHT", -Pad, -y)
    Overlay.Band:SetHeight(questionHeight + 30)
    Overlay.Stripe:ClearAllPoints()
    Overlay.Stripe:SetPoint("TOPLEFT", Overlay.Band, "TOPLEFT")
    Overlay.Stripe:SetPoint("BOTTOMLEFT", Overlay.Band, "BOTTOMLEFT")
    Overlay.Question:ClearAllPoints()
    Overlay.Question:SetPoint("TOPLEFT", Pad + 22, -(y + 15))
    y = y + questionHeight + 30 + 20
    for i, button in ipairs(Overlay.Buttons) do
        local column, row = (i - 1) % 2, i > 2 and 1 or 0
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", Pad + column * (ButtonWidth + AnswerGap), -(y + row * (AnswerHeight + AnswerGap)))
    end
    y = y + 2 * AnswerHeight + AnswerGap + 16
    Overlay.FooterTop = y
    PlaceFooter()
    panel:SetHeight(y + FooterHeight + 18)
end

-- Shows a message in the footer's place: the hint (gold) or the working (green).
local function ShowFeedback(text, good)
    local banner = Overlay.Feedback
    local tint = good and { 0.07, 0.19, 0.09 } or { 0.17, 0.13, 0.05 }
    local edge = good and { 0.2, 0.5, 0.26 } or { 0.48, 0.38, 0.13 }
    banner:SetBackdropColor(tint[1], tint[2], tint[3], 1)
    banner:SetBackdropBorderColor(edge[1], edge[2], edge[3])
    banner.Text:SetText(text)
    banner:Show()
    Overlay.Hint:Hide()
    PlaceFooter()
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
    if info.streak and info.streak >= 2 then
        Overlay.Streak:SetText(info.streak .. " in a row" .. (info.levelUp and "  -  harder riddles!" or ""))
        Overlay.Streak:Show()
    else
        Overlay.Streak:Hide()
    end
end

ScholarView.Emphasize = Emphasize
ScholarView.Split = Split
ScholarView.Spoken = Spoken

--- Sets the handlers the screen calls back: choose(i) for an answer clicked, skip() for Skip,
--- hint() for Need a hint?, speak() for Read aloud, key(key) for every key pressed while the
--- screen has the keyboard.
---@param handlers table { choose, skip, hint, speak, key }
function ScholarView.Init(handlers)
    Callbacks = handlers
end

--- Shows a puzzle, creating the screen on first use. The caller takes the keyboard.
---@param puzzle table a puzzle from ns.Puzzles.Generate
---@param info table { stars, rank, nextRank?, nextAt?, progress (0 to 1), streak, gentle, canSpeak,
---  controller (a controller is connected), keys = { four answer key labels },
---  actions = { hint, speak, skip key labels } }
---@return table frame the full-screen overlay
function ScholarView.Show(puzzle, info)
    Overlay = Overlay or Create()
    local subject = puzzle.subject == "reading" and "reading" or "math"
    Overlay.Tag:SetText(("%s%s|r  %s-  %s|r"):format(Hex(Palette[subject]), subject == "reading" and "READING" or "MATH",
        Hex(Palette.muted), puzzle.title))
    ShowProgress(info)
    local shown, clue = DisplayPrompt(puzzle)
    local story, question = Split(shown)
    Overlay.Clue:SetText(clue and Emphasize(clue) or "")
    Overlay.Clue:SetShown(clue ~= nil)
    Overlay.Story:SetText(Emphasize(story))
    Overlay.Question:SetFontObject(#question <= 44 and "Game30Font" or "Game24Font")
    Overlay.Question:SetText(Emphasize(question))
    for i, button in ipairs(Overlay.Buttons) do
        local choice = puzzle.choices[i]
        button.Key:SetText(info.keys[i])
        button.Text:SetFontObject(AnswerFont(choice))
        button.Text:SetText(choice)
        button:Enable()
        Paint(button, "normal")
    end
    local actions = info.actions or {}
    LabelPill(Overlay.Speak, actions.speak)
    LabelPill(Overlay.Hint, actions.hint)
    LabelPill(Overlay.Skip, actions.skip)
    Overlay.Speak:SetShown(info.canSpeak and true or false)
    Overlay.Feedback:Hide()
    Overlay.Hint:Show()
    Overlay.Skip:Hide()
    Layout(story ~= "", puzzle)
    Overlay:Show()
    return Overlay
end

--- Shows the hint in the footer's place (no penalty; asking for help is part of learning).
---@param hint string
function ScholarView.Hint(hint)
    ShowFeedback(NumberColor .. "Hint:|r  " .. Emphasize(HintText(hint)), false)
end

--- Marks answer i right, dims the others, shows the working and celebrates the new star.
---@param i integer
---@param explanation string
---@param info table the new progress, as for Show
function ScholarView.Correct(i, explanation, info)
    for j, button in ipairs(Overlay.Buttons) do
        button:Disable()
        Paint(button, j == i and "right" or "dim")
    end
    ShowFeedback("|cff59f273Correct!|r  " .. Emphasize(explanation), true)
    Overlay.Gain:SetText("+" .. max(info.earned or 1, 1))
    Overlay.Rise:Stop()
    Overlay.Rise:Play()
    ShowProgress(info)
end

--- Marks answer i wrong (it shakes and can't be picked again), shows the hint, and offers Skip
--- when canSkip.
---@param i integer
---@param hint string
---@param canSkip boolean
function ScholarView.Wrong(i, hint, canSkip)
    local button = Overlay.Buttons[i]
    button:Disable()
    Paint(button, "wrong")
    button.Shake:Stop()
    button.Shake:Play()
    ShowFeedback("|cffff665aNot quite.|r  " .. NumberColor .. "Hint:|r  " .. Emphasize(HintText(hint)), false)
    if canSkip then
        Overlay.Skip:Show()
        PlaceFooter()
    end
end

--- Hides the screen; the caller gives the keyboard back.
function ScholarView.Hide()
    if Overlay then
        Overlay:Hide()
    end
end

--- Whether the screen is showing.
---@return boolean
function ScholarView.IsShown()
    return Overlay ~= nil and Overlay:IsShown()
end

--- The full-screen overlay, or nil before the first Show. Among its children: Buttons[1..4] (each with
--- Key, Keycap, Text, Mark, Shake and State: "normal", "hover", "wrong", "right" or "dim"),
--- Portrait, Asks, Tag, Stars, StarIcon, Progress, Rank, Streak, Gain (raised by Rise), Story,
--- Speak, Pictures (Icons, Cards, Tiles), Clue, Question, Hint, Skip and Feedback (a banner with
--- Text).
---@return table?
function ScholarView.Frame()
    return Overlay
end
