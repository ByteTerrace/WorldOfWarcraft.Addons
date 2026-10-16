local addonName, ns = ...

-- WarbandRadar: the nearby-enemies window. It lists enemy players seen in the last NearbySeconds, by you (nameplates,
-- target, and mouseover, through Warband.OnNearby) or by the Krew (NEARBY messages). Each row shows the player's
-- standing icon, class-colored name, level, how long ago, and who saw them. Right-click a row for the Krew's choices
-- (mark, grudge, glory, and war on their guild). Drag the window anywhere. It shows itself when there's someone to
-- list, and hides when there isn't.
--
-- The window is the global frame TheLanKrewToolKitRadar: Title, then Rows (MaxRows buttons, each with Icon, Name, and
-- Detail). While it shows, a once-a-second tick redraws it. A sighting only updates its entry, and draws at once only
-- when the window is hidden. A redraw sets only what changed: a row keeps what it shows and sets a region only when its
-- entry's value differs, so a tick where nobody came or went touches only the Detail texts whose "ago" moved.
--
-- Sharing: enemies you see for the first time in a while are batched and sent to the Krew at most once per
-- ShareInterval, only while there's something new: no timer runs when nothing is. A NEARBY message is "NEARBY:" then
-- entries "First Last;CLASS;level", as many as fit in Comms' MaxMessage bytes. The rest wait for the next one.

local MaxMessage = ByteTerrace.Comms.MaxMessage
local MaxRows = 10
local NearbySeconds = 120
local Points = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
-- How many bytes of entries and their tab separators fit in one message.
local Room = (MaxMessage - #"NEARBY:")
local RowHeight = 18
local ShareInterval = 10
local Width = 240

local CreateFrame = CreateFrame
local floor = math.floor
local GetTime = GetTime
local MenuUtil = MenuUtil
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local sort = table.sort
local wipe = wipe

local Addon = ns.Addon
local Krew = ns.Krew
local Warband = ns.Warband

local FlushTimer
-- Scratch space for the entries a redraw shows, in order.
local List = {}
-- Maps each key to { key, class, level, faction, guild, time, by, status }.
local Nearby = {}
-- Maps each key of your own sightings not yet shared to true.
local Pending = {}
local Radar
local Ticker
local Window

local Render

-- Standing first (marks, then grudges ...), then the most recently seen, then by name.
local function ByStanding(a, b)
    local rankA = (Warband.Order[a.status] or 9)
    local rankB = (Warband.Order[b.status] or 9)

    if rankA ~= rankB then
        return (rankA < rankB)
    end

    if a.time ~= b.time then
        return (a.time > b.time)
    end

    return (a.key < b.key)
end

local function Clear(row)
    row.m_entry, row.m_key, row.m_class, row.m_status, row.m_detail = nil, nil, nil, nil, nil
    row:Hide()
end

-- "60 - 5s - Mom Doe": level, how long ago, and who saw them.
local function Detail(entry, now)
    local seconds = floor(now - entry.time)
    local detail = (((seconds < 60) and (seconds .. "s")) or (floor(seconds / 60) .. "m"))

    if entry.level > 0 then
        detail = (entry.level .. " - " .. detail)
    end

    if entry.by then
        detail = (detail .. " - " .. entry.by)
    end

    return detail
end

-- Shows entry on row, setting only the regions whose value differs from what the row shows.
local function Draw(row, entry, now)
    if not row.m_entry then
        row:Show()
    end

    row.m_entry = entry

    if row.m_key ~= entry.key then
        row.m_key = entry.key
        row.Name:SetText(entry.key)
    end

    if row.m_class ~= entry.class then
        row.m_class = entry.class
        local color = RAID_CLASS_COLORS[entry.class]

        if color then
            row.Name:SetTextColor(color.r, color.g, color.b)
        else
            row.Name:SetTextColor(1, 1, 1)
        end
    end

    local status = (entry.status or "")

    if row.m_status ~= status then
        row.m_status = status
        row.Icon:SetTexture((entry.status and Warband.Icons[entry.status]) or nil)
    end

    local detail = Detail(entry, now)

    if row.m_detail ~= detail then
        row.m_detail = detail
        row.Detail:SetText(detail)
    end
end

local function Flush()
    FlushTimer = nil

    if not Radar:Get("share") or not Krew:Ready() then
        wipe(Pending)

        return
    end

    local fields = {}
    local room = Room

    for key in pairs(Pending) do
        local entry = Nearby[key]

        if not entry then
            -- An entry gone from the list has nothing to share.
            Pending[key] = nil
        else
            local text = (key .. ";" .. entry.class .. ";" .. entry.level)
            local size = (((#fields > 0) and (#text + 1)) or #text)

            if size > room then
                -- The rest wait for the next message.
                break
            end

            room = (room - size)
            fields[#fields + 1] = text
            Pending[key] = nil
        end
    end

    if #fields > 0 then
        Krew:Send("NEARBY", fields)
    end

    if next(Pending) then
        FlushTimer = Radar:After(ShareInterval, Flush)
    end
end

local function Note(info, by)
    local entry = Nearby[info.key]

    if not entry then
        entry = { class = "", faction = "", guild = "", key = info.key, level = 0 }
        Nearby[info.key] = entry

        if not by then
            Pending[info.key] = true
        end
    end

    if info.class ~= "" then
        entry.class = info.class
    end

    if info.level > 0 then
        entry.level = info.level
    end

    if info.faction ~= "" then
        entry.faction = info.faction
    end

    if info.guild ~= "" then
        entry.guild = info.guild
    end

    if not by or not entry.time or entry.by then
        -- Your own sighting wins over a Krew report.
        entry.by = by
    end

    entry.time = GetTime()

    if not Ticker then
        -- The window is hidden, so show it now. While it shows, the tick draws.
        Render()
    end
end

local function OnMessage(sender, fields)
    for i = 1, #fields do
        local key, class, level = fields[i]:match("^([^;]+);([^;]*);([^;]*)$")

        if key and Warband.ValidKey(key) then
            Note({ class = Warband.CleanClass(class), faction = "", guild = "", key = key, level = Warband.CleanLevel(level) }, sender)
        end
    end
end

local function OnNearby(info)
    Note(info)

    if next(Pending) and not FlushTimer then
        FlushTimer = Radar:After(ShareInterval, Flush)
    end
end

local function OpenMenu(row)
    if row.m_entry then
        MenuUtil.CreateContextMenu(row, function(_, root)
            Warband.MenuEntries(root, row.m_entry)
        end)
    end
end

local function SavePosition()
    Window:StopMovingOrSizing()
    -- secret: the window's anchors and texts are only ever set from plain values
    local point, _, relativePoint, x, y = Window:GetPoint(1)

    Addon:Batch(function()
        Radar:Set("point", point)
        Radar:Set("relativePoint", relativePoint)
        -- secret: plain, as above
        Radar:Set("x", floor(x + 0.5))
        -- secret: plain, as above
        Radar:Set("y", floor(y + 0.5))
    end)
end

local function CreateWindow()
    local frame = CreateFrame("Frame", addonName .. "Radar", UIParent, "BackdropTemplate")

    -- Never focused by the controller UI's SmartNavigation (it covers every child): focus on an addon's control carries
    -- its taint into what the controller UI remembers, which blocks SetPreferredGamepadInteractTarget and can freeze
    -- the game (docs/ControllerSupport.md). Its controller input is summons (Input:Summon) instead.
    frame.smartNavigationIgnored = true

    frame:SetSize(Width, 26)
    frame:SetPoint(Radar:Get("point"), UIParent, Radar:Get("relativePoint"), Radar:Get("x"), Radar:Get("y"))
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", SavePosition)

    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { bottom = 3, left = 3, right = 3, top = 3 } })

    frame:SetBackdropColor(0.05, 0.02, 0.02, 0.85)
    frame:SetBackdropBorderColor(0.7, 0.1, 0.1)
    frame:Hide()

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Title:SetPoint("TOPLEFT", 8, -6)

    frame.Rows = {}

    for i = 1, MaxRows do
        local row = CreateFrame("Button", nil, frame)

        row:SetSize(Width - 12, RowHeight)
        row:SetPoint("TOPLEFT", 6, -6 - (i * RowHeight))
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnClick", OpenMenu)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(14, 14)
        row.Icon:SetPoint("LEFT", 2, 0)
        row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Name:SetPoint("LEFT", 20, 0)
        row.Detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.Detail:SetPoint("RIGHT", -2, 0)
        row:Hide()
        frame.Rows[i] = row
    end

    return frame
end

-- Expires old entries and redraws what changed. It hides the window and stops the tick when nobody is left. The window
-- shows exactly while the tick runs.
function Render()
    local now = GetTime()
    local list = List

    wipe(list)

    for key, entry in pairs(Nearby) do
        if (now - entry.time) > NearbySeconds then
            Nearby[key] = nil
        else
            entry.status = Warband.Status(key, entry.guild)
            list[#list + 1] = entry
        end
    end

    if #list == 0 then
        if Ticker then
            Window:Hide()
            Radar:Cancel(Ticker)
            Ticker = nil
        end

        return
    end

    sort(list, ByStanding)
    Window = (Window or CreateWindow())

    if Window.m_total ~= #list then
        Window.m_total = #list
        Window.Title:SetText("Nearby enemies (" .. #list .. ")")
    end

    local count = (((#list < MaxRows) and #list) or MaxRows)

    -- Walk the rows in use, then the rows to clear.
    for i = 1, (((Window.m_count or 0) > count) and Window.m_count) or count do
        local row = Window.Rows[i]

        if i <= count then
            Draw(row, list[i], now)
        elseif row.m_entry then
            Clear(row)
        end
    end

    if Window.m_count ~= count then
        Window:SetHeight(12 + ((count + 1) * RowHeight))
        Window.m_count = count
    end

    if not Ticker then
        Window:Show()
        Ticker = Radar:Every(1, Render)
    end
end

Radar = Addon:Module("Radar", {
    active = { reads = { "Warband.enabled" }, when = function(state) return state:Get("Warband.enabled") end },
    description = "A list of enemy players you and your Krew have seen in the last two minutes, with their standing. Right-click a name for the Krew's choices; drag the window to move it.",
    label = "Nearby enemies window",
    OnDisable = function()
        Warband.OnNearby = nil
        wipe(Nearby)
        wipe(Pending)
        wipe(List)
        -- The module's timers stop with it, so only the handles are forgotten.
        FlushTimer, Ticker = nil, nil

        if Window then
            Window:Hide()
        end
    end,
    OnEnable = function(module)
        module:Listen(Krew, "NEARBY", OnMessage)
        Warband.OnNearby = OnNearby
    end,
    page = "Warband",
    state = {
        { default = true,
            description = ("Send the enemies you see to your group (batched, at most every " .. ShareInterval .. " seconds)."),
            kind = "boolean", label = "Share nearby enemies with the Krew", name = "share" },
        { default = "RIGHT", kind = "string", name = "point", values = Points },
        { default = "RIGHT", kind = "string", name = "relativePoint", values = Points },
        { default = -60, kind = "number", max = 10000, min = -10000, name = "x" },
        { default = 120, kind = "number", max = 10000, min = -10000, name = "y" },
    },
})
