local addonName, ns = ...

-- Cards: the toolkit's notices on your screen. Celebratory pop-ups (journal, Krew, Scholar, Warband) show one at a time
-- at the top of the screen. News that can't wait is a raid warning.
--
--   ns.Cards.Show(entry)         queues a card: { icon, title, body, sound, onClick }.
--   ns.Cards.Alert(text, sound)  a raid warning on your own screen, now, in combat too.
--
-- The queue holds at most MaxQueued cards. Beyond that, it drops new cards, so a chatty group can't bury the screen.
-- Cards never interrupt a fight: during combat they wait in the queue and appear when it ends, and a card showing when
-- combat starts hides and goes back to the front of the queue. Hovering a card holds it. Clicking dismisses it and
-- shows the next. Otherwise, it hides after CardSeconds. A card with onClick is a question: a left-click runs onClick()
-- in a state batch and dismisses it, and a right-click (or the timeout) dismisses it without acting.
--
-- The card frame is the global TheLanKrewToolKitCard, created with the first card. Its Icon, Title, and Body regions
-- show the current entry.

local CardSeconds = 12
local CardWidth = 440
local MaxQueued = 6
local MinCardHeight = 88

local C_Sound = C_Sound
local ChatTypeInfo = ChatTypeInfo
local CreateFrame = CreateFrame
local insert = table.insert
local RaidWarningUtil = RaidWarningUtil
local remove = table.remove

local Addon = ns.Addon
local Card
-- The module is assigned at the end of the file, and it always runs.
local Cards
local Current
local HideTimer
local InCombat = false
local Queue = {}

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
        insets = { bottom = 4, left = 4, right = 4, top = 4 },
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

--- Shows a raid warning on your own screen.
---@param text string
---@param sound integer? a SOUNDKIT id
local function Alert(text, sound)
    RaidWarningUtil.AddMessage(text, ChatTypeInfo.RAID_WARNING)

    if sound then
        C_Sound.PlaySound(sound)
    end
end

local function HoldTimer()
    Cards:Cancel(HideTimer)
    HideTimer = nil
end

local function StartTimer()
    Cards:Cancel(HideTimer)
    HideTimer = Cards:After(CardSeconds, ShowNext)
end

--- Queues a card, showing it now unless another card is up or combat holds it. Drops the card when the queue is full.
---@param entry table { icon, title, body, sound, onClick }: sound is a SOUNDKIT id or nil; onClick
---                   makes the card a question
local function Show(entry)
    if not Card then
        Card = CreateCard()
        Card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        Card:SetScript("OnClick", function(_, button)
            local onClick = (Current and Current.onClick)

            ShowNext()

            if onClick and (button == "LeftButton") then
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

-- Combat started: the card showing goes back to the front of the queue until combat ends.
local function Withdraw()
    if Current then
        insert(Queue, 1, Current)
        ShowNext()
    end
end

-- Shows the next queued card, or hides when there's none (always, in combat).
function ShowNext()
    HoldTimer()
    local entry = (not InCombat and remove(Queue, 1))

    Current = (entry or nil)

    if not entry then
        Card:Hide()

        return
    end

    Card.Icon:SetTexture(entry.icon)
    Card.Title:SetText(entry.title)
    Card.Body:SetText(entry.body)
    -- Fit the text: 20px top, the title, 6px, the body, and 18px bottom, never shorter than the icon.
    -- secret: card text is built from plain strings, so its fontstrings hold no secret aspect
    local height = ((((20 + Card.Title:GetStringHeight()) + 6) + Card.Body:GetStringHeight()) + 18)

    Card:SetHeight(((height > MinCardHeight) and height) or MinCardHeight)
    Card:Show()

    if entry.sound then
        C_Sound.PlaySound(entry.sound)
    end

    StartTimer()
end

Cards = Addon:Module("Cards", {
    OnEnable = function(module)
        local combat = module:Id("combat.active")

        InCombat = module:Get(combat)

        module:Rule({
            changed = function(active)
                InCombat = active

                if active then
                    Withdraw()
                elseif Card and not Card:IsShown() and (#Queue > 0) then
                    ShowNext()
                end
            end,
            reads = { combat }, when = function(state) return state.Values[combat] end,
        })
    end,
    toggle = false,
})

ns.Cards = { Alert = Alert, Show = Show }
