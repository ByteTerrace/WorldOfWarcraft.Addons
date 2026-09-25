local addonName, ns = ...

-- Cards: the toolkit's celebratory pop-ups (journal, Krew, Scholar, Warband), one at a time, at
-- the top of the screen.
--
--   ns.Cards.Show(entry)   queues a card: { icon, title, body, sound, onClick }.
--   ns.Cards.Clear()       drops every queued card and hides the current one.
--
-- The queue holds at most MaxQueued cards; beyond that new cards are dropped, so a chatty group
-- can't bury the screen. Cards never interrupt a fight: during combat they wait in the queue and
-- appear when it ends. Hovering a card holds it; clicking dismisses it (and shows the next);
-- otherwise it hides after CardSeconds. A card with onClick is a question: a left-click runs
-- onClick() in a state batch and dismisses it, a right-click (or the timeout) dismisses it without
-- acting.
--
-- The card frame is the global TheLanKrewToolKitCard, created with the first card; its Icon,
-- Title and Body regions show the current entry.

local CardSeconds = 12
local CardWidth = 440
local MinCardHeight = 88
local MaxQueued = 6

local C_Sound, C_Timer, CreateFrame = C_Sound, C_Timer, CreateFrame
local remove = table.remove

local Addon = ns.Addon
local Card, HideTimer, Current
local Queue = {}
local InCombat = false

local function CreateCard()
    local frame = CreateFrame("Button", addonName .. "Card", UIParent, "BackdropTemplate")
    frame:SetWidth(CardWidth)
    frame:SetHeight(MinCardHeight)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.08, 0.06, 0.03, 0.92)
    frame:SetBackdropBorderColor(1, 0.82, 0)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(52, 52)
    icon:SetPoint("TOPLEFT", 18, -18)
    frame.Icon = icon

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -2)
    title:SetPoint("TOPRIGHT", -16, -20)
    title:SetJustifyH("LEFT")
    frame.Title = title

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    body:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -6)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    frame.Body = body

    return frame
end

local ShowNext

local function StartTimer()
    if HideTimer then
        HideTimer:Cancel()
    end
    HideTimer = C_Timer.NewTimer(CardSeconds, ShowNext)
end

local function HoldTimer()
    if HideTimer then
        HideTimer:Cancel()
        HideTimer = nil
    end
end

-- Shows the next queued card, or hides when there's none (always, in combat).
function ShowNext()
    HoldTimer()
    local entry = not InCombat and remove(Queue, 1)
    Current = entry or nil
    if not entry then
        Card:Hide()
        return
    end
    Card.Icon:SetTexture(entry.icon)
    Card.Title:SetText(entry.title)
    Card.Body:SetText(entry.body)
    -- Fit the text: 20px top, the title, 6px, the body, 18px bottom; never shorter than the icon.
    -- secret: card text is built from plain strings, so its fontstrings hold no secret aspect
    local height = 20 + Card.Title:GetStringHeight() + 6 + Card.Body:GetStringHeight() + 18
    Card:SetHeight(height > MinCardHeight and height or MinCardHeight)
    Card:Show()
    if entry.sound then
        C_Sound.PlaySound(entry.sound)
    end
    StartTimer()
end

ns.Cards = {}

--- Queues a card, showing it now unless another card is up or combat holds it. Dropped when the
--- queue is full.
---@param entry table { icon, title, body, sound, onClick }: sound is a SOUNDKIT id or nil; onClick
---                   makes the card a question
function ns.Cards.Show(entry)
    if not Card then
        Card = CreateCard()
        Card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        Card:SetScript("OnClick", function(_, button)
            local onClick = Current and Current.onClick
            ShowNext()
            if onClick and button == "LeftButton" then
                Addon:Batch(onClick)
            end
        end)
        Card:SetScript("OnEnter", HoldTimer)
        Card:SetScript("OnLeave", StartTimer)
    end
    if #Queue >= MaxQueued then
        return
    end
    Queue[#Queue + 1] = entry
    if not Card:IsShown() then
        ShowNext()
    end
end

--- Drops every queued card and hides the current one.
function ns.Cards.Clear()
    wipe(Queue)
    if Card then
        ShowNext()
    end
end

Addon:Module("Cards", {
    toggle = false,
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        InCombat = module:Get(combat)
        module:Rule({
            reads = { combat }, when = function(state) return state.Values[combat] end,
            changed = function(active)
                InCombat = active
                if not active and Card and not Card:IsShown() and #Queue > 0 then
                    ShowNext()
                end
            end,
        })
    end,
})
