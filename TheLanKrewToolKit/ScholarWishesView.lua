local addonName, ns = ...

-- ScholarWishesView: the wishes window. It only draws: ScholarWishes.lua decides what it lists and what its buttons do,
-- and gives it handlers through Init. A row is a wish with how close the stars are, or for a grown-up, a request
-- waiting for an answer. One row is chosen, and the footer's buttons act on it: the main action (Ask or Grant), Not now
-- for a request, and Close. Each footer button shows its controller glyph when a controller is connected.
--
-- The window is the global TheLanKrewToolKitWishes, at DIALOG strata, over the riddle. Only the panel takes the mouse,
-- and a key reaches the game unless the key handler says the window used it.
--
--   ns.ScholarWishesView.Init(handlers)  { select(i), act(), no(), close(), key(key) -> used }
--   ns.ScholarWishesView.Show(model)     { title, empty, rows = { { label, status, icon, ready } }, selected,
--                                          act (its label, or nil for none), no (whether Not now applies),
--                                          prompts = { act, no, close } (each a glyph, or nil) }
--   ns.ScholarWishesView.Hide()

local MaxRows = 14
local RowHeight = 34
local Width = 480

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent

local ScholarStyle = ns.ScholarStyle
local Backdrop = ScholarStyle.Backdrop
local BackdropColors = ScholarStyle.BackdropColors
local Palette = ScholarStyle.Palette
local TextColor = ScholarStyle.TextColor

-- The handlers Init was given.
local Callbacks = {}
local Window = nil

-- A footer button with its label.
local function FooterButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")

    Backdrop(button, 10)
    BackdropColors(button, Palette.pill, Palette.edge)
    button:SetHeight(30)
    button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.Label:SetPoint("CENTER")
    button:SetScript("OnClick", function() onClick() end)

    return button
end

local function Create()
    local frame = CreateFrame("Frame", addonName .. "Wishes", UIParent, "BackdropTemplate")

    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(Width)
    frame:SetPoint("CENTER", 0, 40)
    frame:EnableMouse(true)
    Backdrop(frame, 16)
    BackdropColors(frame, Palette.panel, Palette.gold)
    frame:Hide()

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "Game20Font")
    frame.Title:SetPoint("TOP", 0, -18)
    TextColor(frame.Title, Palette.gold)
    frame.Empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.Empty:SetPoint("TOP", frame.Title, "BOTTOM", 0, -20)
    frame.Empty:SetWidth(Width - 48)
    frame.Rows = {}

    for i = 1, MaxRows do
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")

        row:SetHeight(RowHeight)
        row:SetPoint("TOPLEFT", 20, -(54 + ((i - 1) * (RowHeight + 4))))
        row:SetPoint("TOPRIGHT", -20, -(54 + ((i - 1) * (RowHeight + 4))))
        Backdrop(row, 8)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(24, 24)
        row.Icon:SetPoint("LEFT", 8, 0)
        row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.Label:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
        row.Label:SetJustifyH("LEFT")
        row.Status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.Status:SetPoint("RIGHT", -10, 0)
        row:SetScript("OnClick", function() Callbacks.select(i) end)
        frame.Rows[i] = row
    end

    frame.Act = FooterButton(frame, function() Callbacks.act() end)
    frame.NotNow = FooterButton(frame, function() Callbacks.no() end)
    frame.Close = FooterButton(frame, function() Callbacks.close() end)
    frame.Close:SetPoint("BOTTOMRIGHT", -20, 16)
    frame.NotNow:SetPoint("RIGHT", frame.Close, "LEFT", -8, 0)
    frame.Act:SetPoint("RIGHT", frame.NotNow, "LEFT", -8, 0)
    frame:EnableKeyboard(true)

    -- The window's own keys stay with it, and every other key reaches the game, out of combat only.
    frame:SetScript("OnKeyDown", function(self, key)
        local used = Callbacks.key(key)

        if not InCombatLockdown() then
            -- protected: only out of combat, and the window closes as a fight starts
            self:SetPropagateKeyboardInput(not used)
        end
    end)

    return frame
end

local function Hide()
    if Window then
        Window:Hide()
    end
end

local function Init(handlers)
    Callbacks = handlers
end

-- Labels a footer button with its glyph and its words, and fits it.
local function Label(button, prompt, text)
    button.Label:SetText(((prompt and (prompt .. "  ")) or "") .. text)
    -- secret: footer labels are built from fixed words and controller glyphs, so they hold no secret aspect
    button:SetWidth(button.Label:GetStringWidth() + 28)
end

local function Show(model)
    Window = (Window or Create())
    local prompts = (model.prompts or {})
    local count = math.min(#model.rows, MaxRows)

    Window.Title:SetText(model.title)
    Window.Empty:SetText(model.empty or "")
    Window.Empty:SetShown(count == 0)
    Window.Selected = model.selected

    for i, row in ipairs(Window.Rows) do
        local entry = model.rows[i]

        row:SetShown(i <= count)

        if entry and (i <= count) then
            row.Label:SetText(entry.label)
            row.Status:SetText(entry.status)
            row.Icon:SetTexture(entry.icon)
            TextColor(row.Status, (entry.ready and Palette.good) or Palette.muted)

            BackdropColors(row, ((i == model.selected) and Palette.band) or Palette.pill,
                ((i == model.selected) and Palette.gold) or Palette.dimEdge)
        end
    end

    Window:SetHeight(((54 + (math.max(count, 1) * (RowHeight + 4))) + 56))
    Window.Act:SetShown(model.act ~= nil)

    if model.act then
        Label(Window.Act, prompts.act, model.act)
    end

    Window.NotNow:SetShown((model.no and true) or false)
    Label(Window.NotNow, prompts.no, "Not now")
    Label(Window.Close, prompts.close, "Close")
    Window:Show()
end

ns.ScholarWishesView = { Hide = Hide, Init = Init, Show = Show }
