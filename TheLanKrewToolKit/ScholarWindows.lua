local addonName, ns = ...

-- ScholarWindows: which of Blizzard's windows a riddle waits for. While a quest dialog, gossip, a vendor, the mailbox,
-- a bank, the auction house, a trainer, or the flight map is open, the Scholar module's window row is true, and a
-- riddle that comes due waits for it to close (Scholar.lua's rules read the row). A loading screen closes them all.
--
--   ns.ScholarWindows.Start(module)  follows the windows, from the Scholar module's OnEnable
--   ns.ScholarWindows.Clear(module)  forgets every window, as a loading screen or the module stopping does

-- The events that open (true) and close (false) the quest dialog and gossip, as Blizzard's QuestFrame and gossip frame
-- read them.
local DialogEvents = {
    GOSSIP_CLOSED = { "gossip", false }, GOSSIP_SHOW = { "gossip", true }, QUEST_COMPLETE = { "quest", true },
    QUEST_DETAIL = { "quest", true }, QUEST_FINISHED = { "quest", false }, QUEST_GREETING = { "quest", true },
    QUEST_PROGRESS = { "quest", true },
}

-- The windows Blizzard's interaction manager opens that a riddle waits for (by Enum.PlayerInteractionType name).
local HeldInteractions = {}
-- The taxi node's map also closes with TAXIMAP_CLOSED.
local TaxiNode = Enum.PlayerInteractionType.TaxiNode

for _, name in ipairs({ "Merchant", "MailInfo", "Banker", "CharacterBanker", "AccountBanker", "GuildBanker",
    "Auctioneer", "Trainer", "TaxiNode" }) do
    HeldInteractions[Enum.PlayerInteractionType[name]] = true
end

local next = next
local pairs = pairs
local wipe = wipe

-- Blizzard's windows open now that a riddle waits for: "quest", "gossip", and interaction types.
local Windows = {}

local function Clear(module)
    wipe(Windows)
    module:Set("window", false)
end

local function Start(module)
    -- A window opened (open) or closed. The window row is whether any window a riddle waits for is open.
    local function SetWindow(name, open)
        Windows[name] = (open or nil)
        module:Set("window", next(Windows) ~= nil)
    end

    for event, dialog in pairs(DialogEvents) do
        module:On(event, function() SetWindow(dialog[1], dialog[2]) end)
    end

    module:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(interaction)
        if HeldInteractions[interaction] then
            SetWindow(interaction, true)
        end
    end)

    module:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(interaction) SetWindow(interaction, false) end)
    module:On("TAXIMAP_CLOSED", function() SetWindow(TaxiNode, false) end)
end

ns.ScholarWindows = { Clear = Clear, Start = Start }
