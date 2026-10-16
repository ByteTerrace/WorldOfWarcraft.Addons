local addonName, ns = ...

-- Cards: the toolkit's notices on your screen. Celebratory pop-ups (journal, Krew, Scholar, Warband) show one at a time
-- at the top of the screen. News that can't wait is a raid warning.
--
--   ns.Cards.Show(entry)         queues a card: { icon, title, body, sound, onClick }.
--   ns.Cards.Alert(text, sound)  a raid warning on your own screen, now, in combat too.
--   ns.Cards.Unfocus()           gives up the controller, if a question card holds it. The card stays up.
--
-- The queue holds at most MaxQueued cards. Beyond that, it drops new cards, so a chatty group can't bury the screen.
-- Cards never interrupt a fight: during combat they wait in the queue and appear when it ends, and a card showing when
-- combat starts hides and goes back to the front of the queue. Hovering a card holds it. Clicking dismisses it and
-- shows the next. Otherwise, it hides after CardSeconds. A card with onClick is a question: a left-click runs onClick()
-- in a state batch and dismisses it, and a right-click (or the timeout) dismisses it without acting.
--
-- A question card answers to a controller too. While it shows, Select is summoned to focus it (ByteTerrace_Core's
-- Input:Summon), so every other button stays the player's. Focused, the card holds (no timeout) and its card map has
-- the controller: A answers yes (as a left-click), B answers no (as a right-click), and Select lets go. With a
-- controller connected, the card's Prompt line says which buttons do what. A fight ends the focus and the summon with
-- the card, before combat lockdown, and the card comes back after.
--
-- The card frame is the global TheLanKrewToolKitCard, created with the first card. Its Icon, Title, and Body regions
-- show the current entry.

-- The controller buttons a question card answers to.
local AnswerSources = { focus = "gamepad.back", no = "gamepad.east", yes = "gamepad.south" }
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
-- Whether the question card showing has the controller.
local Focused = false
local HideTimer
local InCombat = false
local Input = ByteTerrace.Input
local Queue = {}

local function CreateCard()
    local frame = CreateFrame("Button", addonName .. "Card", UIParent, "BackdropTemplate")

    -- Never focused by the controller UI's SmartNavigation (it covers every child): focus on an addon's control carries
    -- its taint into what the controller UI remembers, which blocks SetPreferredGamepadInteractTarget and can freeze
    -- the game (docs/ControllerSupport.md). Its controller input is summons (Input:Summon) instead.
    frame.smartNavigationIgnored = true

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
    local prompt = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    prompt:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -8)
    prompt:Hide()
    frame.Prompt = prompt

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

-- A or B on a focused question card: yes runs its answer, and both dismiss it.
local function Answer(yes)
    local onClick = (Current and Current.onClick)

    if not (Focused and onClick) then
        return
    end

    ShowNext()

    if yes then
        Addon:Batch(onClick)
    end
end

local function HoldTimer()
    Cards:Cancel(HideTimer)
    HideTimer = nil
end

-- The card's Prompt line for the controller: how to focus a question card, or, focused, how to answer it. Hidden
-- without a controller, and on a card that isn't a question.
local function SetPrompt()
    local question = (Current and Current.onClick and (Input.LabelStyle() ~= "Generic"))

    if question and Focused then
        Card.Prompt:SetText(("%s yes    %s no"):format(Input.Prompt(AnswerSources.yes, 16), Input.Prompt(AnswerSources.no, 16)))
    elseif question then
        Card.Prompt:SetText(Input.Prompt(AnswerSources.focus, 16) .. " answer")
    end

    Card.Prompt:SetShown((question and true) or false)
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

        -- A focused card holds until it's answered or let go, mouse or no mouse.
        Card:SetScript("OnLeave", function()
            if not Focused then
                StartTimer()
            end
        end)
    end

    if #Queue >= MaxQueued then
        return
    end

    Queue[#Queue + 1] = entry

    if not Card:IsShown() then
        ShowNext()
    end
end

-- Gives the controller back from a focused card, keeping any other feature's map.
local function Unfocus()
    if not Focused then
        return
    end

    Focused = false
    local kept = {}

    for _, name in ipairs(Addon.Input:ActiveMaps()) do
        if name ~= "card" then
            kept[#kept + 1] = name
        end
    end

    Addon.Input:SetActiveMaps(kept)
end

-- Select on a question card: focus it, or let go of it.
local function Focus()
    if not (Current and Current.onClick) then
        return
    end

    if Focused then
        Unfocus()
        StartTimer()
    else
        Focused = true
        HoldTimer()
        local maps = Addon.Input:ActiveMaps()

        maps[#maps + 1] = "card"
        Addon.Input:SetActiveMaps(maps)
    end

    SetPrompt()
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
    Unfocus()
    Addon.Input:Dismiss(Cards, AnswerSources.focus, "Cards.focus")
    local entry = (not InCombat and remove(Queue, 1))

    Current = (entry or nil)

    if not entry then
        Card:Hide()

        return
    end

    Card.Icon:SetTexture(entry.icon)
    Card.Title:SetText(entry.title)
    Card.Body:SetText(entry.body)
    SetPrompt()
    -- Fit the text: 20px top, the title, 6px, the body, the prompt line and 8px above it when it shows, and 18px
    -- bottom, never shorter than the icon.
    -- secret: card text is built from plain strings, so its fontstrings hold no secret aspect
    local height = ((((20 + Card.Title:GetStringHeight()) + 6) + Card.Body:GetStringHeight()) + 18)

    if Card.Prompt:IsShown() then
        -- secret: plain, as above
        height = ((height + 8) + Card.Prompt:GetStringHeight())
    end

    Card:SetHeight(((height > MinCardHeight) and height) or MinCardHeight)
    Card:Show()

    if entry.sound then
        C_Sound.PlaySound(entry.sound)
    end

    StartTimer()

    if entry.onClick then
        Addon.Input:Summon(Cards, AnswerSources.focus, "Cards.focus")
    end
end

Cards = Addon:Module("Cards", {
    bindings = {
        { command = "Cards.focus", map = "card", source = AnswerSources.focus },
        { command = "Cards.no", map = "card", source = AnswerSources.no },
        { command = "Cards.yes", map = "card", source = AnswerSources.yes },
    },
    commands = {
        { label = "Focus or let go of a question card", name = "focus", run = Focus },
        { label = "Answer a question card no", name = "no", run = function() Answer(false) end },
        { label = "Answer a question card yes", name = "yes", run = function() Answer(true) end },
    },
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

ns.Cards = { Alert = Alert, Show = Show, Unfocus = Unfocus }
