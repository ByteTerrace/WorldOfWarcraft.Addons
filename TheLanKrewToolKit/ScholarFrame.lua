local addonName, ns = ...

-- ScholarFrame: builds the Scholar's challenge screen's widgets, for ScholarView.lua, which lays them out and runs
-- them. Create(callbacks) makes the full-screen overlay: the shade, the panel, its header (the Owl Sage, the subject
-- and title, the stars, the rank bar, and the streak), its body (the story, the quest book's page, the picture, the
-- clue, the question band, and the four answers), and its footer (the pills and the feedback banner). The widgets call
-- the callbacks ScholarView.Init was given, at the moment they're used. Paint colors an answer by its state, and
-- LabelPill labels a pill with its key and fits it.
--
--   ns.ScholarFrame.Create(callbacks)      the overlay, hidden
--   ns.ScholarFrame.Paint(button, state)   "normal", "hover", "wrong", "right", "dim", or "reveal"
--   ns.ScholarFrame.LabelPill(pill, key)   the pill's text with its key ("LB  Need a hint?"), fitted
--   ns.ScholarFrame.AnswerHeight, BookInset, ButtonWidth, Inset, NumberColor, Pad, Width   the sizes both files share
--
-- One rule aligns the text: the story sits at the panel's padding, like the boxes' edges, and every box's text starts
-- Inset into it, the question's band, the quest book's page, and the feedback banner alike. The band and the banner
-- carry a stripe at their left edge in that room: the band's is gold, and the banner's says how it went
-- (ScholarView.lua colors it). The panel casts a soft shadow, and each answer has a lit top edge and a shaded bottom
-- one.

local AnswerGap = 14
local AnswerHeight = 72
-- The room above and below the quest book's text, and to its right, before the scroll bar.
local BookInset = 14
local CircleMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- How far into a box its text starts: the question's band, the quest book's page, and the feedback banner.
local Inset = 22
local KeycapSize = 34
local NumberColor = "|cffffd100"
local OwlIcon = "Interface\\Icons\\Ability_Hunter_Pet_Owl"
local Pad = 28
local PortraitSize = 60
local RightIcon = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local ScrollBarWidth = 6
local SpeakerIcon = "Interface\\Common\\VoiceChat-Speaker"
local Width = 760
local ButtonWidth = (((Width - (2 * Pad)) - AnswerGap) / 2)

local CreateFrame = CreateFrame
local UIParent = UIParent

local ScholarStyle = ns.ScholarStyle
local Backdrop = ScholarStyle.Backdrop
local BackdropColors = ScholarStyle.BackdropColors
local TextColor = ScholarStyle.TextColor

local Palette, Solid, StarIcon, WrongIcon = ScholarStyle.Palette, ScholarStyle.Solid, ScholarStyle.StarIcon,
    ScholarStyle.WrongIcon

-- The handlers ScholarView.Init gave, for the widgets' scripts.
local Callbacks

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

local function DimPill(pill)
    BackdropColors(pill, nil, Palette.edge)
end

local function Fill(region, color, alpha)
    region:SetColorTexture(color[1], color[2], color[3], alpha or 1)
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
    frame.Asks:SetPoint("TOPLEFT", (Pad + PortraitSize) + 16, -24)
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

-- Labels a pill with its key ("LB  Need a hint?") and fits the pill to it.
local function LabelPill(button, key)
    button.Label:SetText((key and (NumberColor .. key .. "|r  " .. button.m_text)) or button.m_text)
    -- secret: pill labels are built from fixed strings and key names, so they hold no secret aspect
    button:SetWidth((button.m_left + button.Label:GetStringWidth()) + 14)
end

local function LightPill(pill)
    BackdropColors(pill, nil, Palette.gold)
end

-- Small text buttons (Need a hint?, Read aloud, Skip).
local function CreatePill(parent, text, icon)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")

    Backdrop(button, 10)
    BackdropColors(button, Palette.pill, Palette.edge)
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
    button:SetScript("OnEnter", LightPill)
    button:SetScript("OnLeave", DimPill)

    return button
end

local function CreateFooter(frame, panel)
    frame.Hint = CreatePill(panel, "Need a hint?")
    frame.Hint:SetScript("OnClick", function() Callbacks.hint() end)
    frame.Skip = CreatePill(panel, "Skip")
    frame.Skip:SetScript("OnClick", function() Callbacks.skip() end)

    local banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")

    Backdrop(banner, 10)
    banner.Stripe = banner:CreateTexture(nil, "ARTWORK")
    banner.Stripe:SetWidth(4)
    banner.Stripe:SetPoint("TOPLEFT", 3, -3)
    banner.Stripe:SetPoint("BOTTOMLEFT", 3, 3)
    Fill(banner.Stripe, Palette.gold)
    banner.Text = banner:CreateFontString(nil, "OVERLAY", "Game18Font")
    banner.Text:SetPoint("LEFT", Inset, 0)
    banner.Text:SetJustifyH("LEFT")
    banner.Text:SetWordWrap(true)
    TextColor(banner.Text, Palette.story)
    frame.Feedback = banner
end

local function Paint(button, state)
    button.State = state
    local background = Palette.button
    local edge = Palette.edge
    local text = Palette.question
    local key = Palette.story
    local mark

    if state == "hover" then
        edge = Palette.gold
    elseif state == "wrong" then
        background, edge, text, key, mark = Palette.wrongFill, Palette.bad, Palette.muted, Palette.muted, WrongIcon
    elseif state == "right" then
        background, edge, mark = Palette.rightFill, Palette.good, RightIcon
    elseif state == "dim" then
        edge, text, key = Palette.dimEdge, Palette.muted, Palette.muted
    elseif state == "reveal" then
        background, edge = Palette.rightFill, Palette.gold
    end

    BackdropColors(button, background, edge)
    TextColor(button.Text, text)
    TextColor(button.Key, key)
    Fill(button.Keycap, (((state == "dim") or (state == "wrong")) and Palette.keycapDim) or Palette.keycap)
    button.Mark:SetTexture(mark)
    button.Mark:SetShown(mark ~= nil)
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

    -- The answer centers on the whole button. The keycap sits at its edge.
    button.Text = button:CreateFontString(nil, "OVERLAY", "Game30Font")
    button.Text:SetPoint("LEFT", KeycapSize + 24, 0)
    button.Text:SetPoint("RIGHT", -(KeycapSize + 24), 0)
    button.Text:SetJustifyH("CENTER")
    button.Text:SetWordWrap(true)

    -- A bevel: a lit top edge and a shaded bottom one, inside the border.
    button.Shine = button:CreateTexture(nil, "ARTWORK")
    button.Shine:SetHeight(1)
    button.Shine:SetPoint("TOPLEFT", 4, -4)
    button.Shine:SetPoint("TOPRIGHT", -4, -4)
    Fill(button.Shine, { 1, 1, 1 }, 0.1)
    button.Shade = button:CreateTexture(nil, "ARTWORK")
    button.Shade:SetHeight(2)
    button.Shade:SetPoint("BOTTOMLEFT", 4, 4)
    button.Shade:SetPoint("BOTTOMRIGHT", -4, 4)
    Fill(button.Shade, { 0, 0, 0 }, 0.35)
    button.Mark = button:CreateTexture(nil, "OVERLAY")
    button.Mark:SetSize(26, 26)
    button.Mark:SetPoint("RIGHT", -16, 0)
    button.Shake = CreateShake(button)

    button:SetScript("OnClick", function() Callbacks.choose(i) end)

    button:SetScript("OnEnter", function(self)
        if self.State == "normal" then Paint(self, "hover") end

        if Callbacks.hover then Callbacks.hover(i) end
    end)

    button:SetScript("OnLeave", function(self)
        if self.State == "hover" then Paint(self, "normal") end
    end)

    return button
end

local function CreateBody(frame, panel)
    frame.Story = panel:CreateFontString(nil, "OVERLAY", "Game20Font")
    frame.Story:SetWidth(Width - (2 * Pad))
    frame.Story:SetJustifyH("LEFT")
    frame.Story:SetWordWrap(true)
    frame.Story:SetSpacing(4)
    TextColor(frame.Story, Palette.story)
    -- The quest book: a page below the story, holding the quest's text in a scroll frame, the wheel scrolling it, and a
    -- slim bar on its right showing where in the text you are.
    local case = CreateFrame("Frame", nil, panel, "BackdropTemplate")

    Backdrop(case, 10)
    BackdropColors(case, Palette.card, Palette.dimEdge)
    case:Hide()
    local book = CreateFrame("ScrollFrame", nil, case)

    book:EnableMouseWheel(true)
    book:SetScript("OnMouseWheel", function(_, delta) ns.ScholarView.ScrollBook(-delta) end)
    book:SetPoint("TOPLEFT", Inset, -BookInset)
    book:SetPoint("BOTTOMRIGHT", -BookInset, BookInset)
    book:Hide()
    local page = CreateFrame("Frame", nil, book)
    local textWidth = ((((Width - (2 * Pad)) - Inset) - BookInset) - 16)

    page:SetWidth(textWidth)
    book:SetScrollChild(page)
    frame.BookText = page:CreateFontString(nil, "OVERLAY", "Game20Font")
    frame.BookText:SetPoint("TOPLEFT")
    frame.BookText:SetWidth(textWidth)
    frame.BookText:SetJustifyH("LEFT")
    frame.BookText:SetWordWrap(true)
    frame.BookText:SetSpacing(4)
    TextColor(frame.BookText, Palette.story)
    frame.Track = book:CreateTexture(nil, "ARTWORK")
    frame.Track:SetWidth(ScrollBarWidth)
    frame.Track:SetPoint("TOPRIGHT")
    frame.Track:SetPoint("BOTTOMRIGHT")
    Fill(frame.Track, Palette.gold, 0.15)
    frame.Thumb = book:CreateTexture(nil, "OVERLAY")
    frame.Thumb:SetWidth(ScrollBarWidth)
    Fill(frame.Thumb, Palette.gold, 0.7)
    frame.Book, frame.BookCase, frame.BookPage = book, case, page
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
    frame.Question:SetWidth((Width - (2 * Pad)) - 48)
    frame.Question:SetJustifyH("LEFT")
    frame.Question:SetWordWrap(true)
    frame.Question:SetSpacing(4)
    TextColor(frame.Question, Palette.question)

    frame.Buttons = {}

    for i = 1, 4 do
        frame.Buttons[i] = CreateAnswer(panel, i)
    end
end

local function Create(callbacks)
    Callbacks = callbacks
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

    -- A soft shadow behind the panel, so it lifts off the shade.
    frame.Shadow = frame:CreateTexture(nil, "BORDER")
    frame.Shadow:SetPoint("TOPLEFT", panel, "TOPLEFT", -10, 10)
    frame.Shadow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 10, -10)
    Fill(frame.Shadow, { 0, 0, 0 }, 0.6)

    panel:SetWidth(Width)
    panel:SetPoint("CENTER", 0, 30)
    Backdrop(panel, 16)
    BackdropColors(panel, Palette.panel, Palette.gold)
    frame.Panel = panel

    CreateHeader(frame, panel)
    CreateBody(frame, panel)
    CreateFooter(frame, panel)
    frame:SetScript("OnKeyDown", function(_, key) Callbacks.key(key) end)

    return frame
end

ns.ScholarFrame = {
    AnswerHeight = AnswerHeight, BookInset = BookInset, ButtonWidth = ButtonWidth, Create = Create, Inset = Inset,
    LabelPill = LabelPill, NumberColor = NumberColor, Pad = Pad, Paint = Paint, Width = Width,
}
