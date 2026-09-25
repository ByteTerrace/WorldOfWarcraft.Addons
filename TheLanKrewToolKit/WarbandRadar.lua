local addonName, ns = ...

-- WarbandRadar: the nearby-enemies window. It lists enemy players seen in the last NearbySeconds,
-- by you (nameplates, target, mouseover, through Warband.OnNearby) or by the Krew (NEARBY
-- messages). Each row shows the player's standing icon, class-colored name, level, how long ago,
-- and who saw them; right-click for the Krew's choices (mark, grudge, glory, war on their guild).
-- Drag it anywhere; it shows itself when there's someone to list, and hides when there isn't.
--
-- The window is the global frame TheLanKrewToolKitRadar: Title, then Rows (MaxRows buttons, each
-- with Icon, Name and Detail). A redraw touches only the rows in use and the ones it clears.
--
-- Sharing: enemies you see for the first time in a while are batched and sent to the Krew at most
-- once per ShareInterval, only while there's something new: no timer runs when nothing is.

local NearbySeconds = 120
local ShareInterval = 10
local MaxRows = 10
local RowHeight = 18
local Width = 240
local MaxMessageFields = 200 -- bytes of entries per NEARBY message (the rest waits its turn)
local Points = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local C_Timer, CreateFrame, GetRealZoneText, GetSubZoneText, GetTime = C_Timer, CreateFrame, GetRealZoneText, GetSubZoneText, GetTime
local MenuUtil, RAID_CLASS_COLORS = MenuUtil, RAID_CLASS_COLORS
local floor, tostring = math.floor, tostring
local concat, sort = table.concat, table.sort

local Addon = ns.Addon
local Krew = ns.Krew
local Warband = ns.Warband

local Nearby = {} -- [key] = { key, class, level, faction, guild, time, by, zone, status }
local Pending = {} -- [key] = true for your own sightings not yet shared
local FlushTimer, Window, Ticker
local Radar

local Render

local function Note(info, by, zone)
    local entry = Nearby[info.key]
    if not entry then
        entry = { key = info.key }
        Nearby[info.key] = entry
        if not by then
            Pending[info.key] = true
        end
    end
    entry.class = info.class ~= "" and info.class or entry.class or ""
    entry.level = info.level > 0 and info.level or entry.level or 0
    entry.faction = info.faction ~= "" and info.faction or entry.faction or ""
    entry.guild = (info.guild and info.guild ~= "") and info.guild or entry.guild or ""
    if not by or not entry.time or entry.by then
        entry.by = by -- your own sighting wins over a Krew report
    end
    entry.time = GetTime()
    entry.zone = zone or ""
    Render()
end

local function Flush()
    FlushTimer = nil
    if not Radar:Get("share") or not Krew.Ready() then
        wipe(Pending)
        return
    end
    local fields = { Warband.CleanText(GetRealZoneText()), Warband.CleanText(GetSubZoneText()) }
    local size = 0
    for key in pairs(Pending) do
        local entry = Nearby[key]
        Pending[key] = nil
        if entry then
            local text = key .. ";" .. entry.class .. ";" .. entry.level
            if size + #text + 1 > MaxMessageFields then
                Pending[key] = true -- next message
                break
            end
            size = size + #text + 1
            fields[#fields + 1] = text
        end
    end
    if #fields > 2 then
        Krew.Send("NEARBY", fields)
    end
    if next(Pending) then
        FlushTimer = C_Timer.NewTimer(ShareInterval, Flush)
    end
end

local function OnNearby(info)
    Note(info)
    if next(Pending) and not FlushTimer then
        FlushTimer = C_Timer.NewTimer(ShareInterval, Flush)
    end
end

local function Ago(seconds)
    seconds = floor(seconds)
    if seconds < 60 then
        return seconds .. "s"
    end
    return floor(seconds / 60) .. "m"
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
        Radar:Set("x", floor(x + 0.5))
        Radar:Set("y", floor(y + 0.5))
    end)
end

local function CreateWindow()
    local frame = CreateFrame("Frame", addonName .. "Radar", UIParent, "BackdropTemplate")
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
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.02, 0.02, 0.85)
    frame:SetBackdropBorderColor(0.7, 0.1, 0.1)
    frame:Hide()

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Title:SetPoint("TOPLEFT", 8, -6)

    frame.Rows = {}
    for i = 1, MaxRows do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(Width - 12, RowHeight)
        row:SetPoint("TOPLEFT", 6, -6 - i * RowHeight)
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

local function StopTicker()
    if Ticker then
        Ticker:Cancel()
        Ticker = nil
    end
end

-- Expires old entries and redraws. Runs on each sighting and once a second while shown.
function Render()
    local now, list = GetTime(), {}
    for key, entry in pairs(Nearby) do
        if now - entry.time > NearbySeconds then
            Nearby[key] = nil
        else
            entry.status = Warband.Status(key, entry.guild)
            list[#list + 1] = entry
        end
    end
    if #list == 0 then
        if Window then
            Window:Hide()
        end
        StopTicker()
        return
    end
    sort(list, function(a, b)
        local rankA, rankB = Warband.Order[a.status] or 9, Warband.Order[b.status] or 9
        if rankA ~= rankB then
            return rankA < rankB
        end
        if a.time ~= b.time then
            return a.time > b.time
        end
        return a.key < b.key
    end)
    Window = Window or CreateWindow()
    Window.Title:SetText("Nearby enemies (" .. #list .. ")")
    local count = #list < MaxRows and #list or MaxRows
    for i = 1, (Window.m_count or 0) > count and Window.m_count or count do -- rows in use, and rows to clear
        local row, entry = Window.Rows[i], list[i]
        if i <= count then
            row.m_entry = entry
            row.Icon:SetTexture(entry.status and Warband.Icons[entry.status] or nil)
            row.Name:SetText(Warband.Short(entry.key))
            local color = RAID_CLASS_COLORS[entry.class]
            if color then
                row.Name:SetTextColor(color.r, color.g, color.b)
            else
                row.Name:SetTextColor(1, 1, 1)
            end
            local detail = {}
            if entry.level > 0 then
                detail[#detail + 1] = tostring(entry.level)
            end
            detail[#detail + 1] = Ago(now - entry.time)
            if entry.by then
                detail[#detail + 1] = entry.by
            end
            row.Detail:SetText(concat(detail, " - "))
            row:Show()
        else
            row.m_entry = nil
            row:Hide()
        end
    end
    if Window.m_count ~= count then
        Window:SetHeight(12 + (count + 1) * RowHeight)
        Window.m_count = count
    end
    Window:Show()
    if not Ticker then
        Ticker = C_Timer.NewTicker(1, Render)
    end
end

Radar = Addon:Module("Radar", {
    label = "Nearby enemies window",
    page = "Warband",
    description = "A list of enemy players you and your Krew have seen in the last two minutes, with their standing. Right-click a name for the Krew's choices; drag the window to move it.",
    active = { reads = { "Warband.enabled" }, when = function(s) return s:Get("Warband.enabled") end },
    state = {
        { name = "share", kind = "boolean", default = true, label = "Share nearby enemies with the Krew",
            description = "Send the enemies you see to your group (batched, at most every " .. ShareInterval .. " seconds)." },
        { name = "point", kind = "string", default = "RIGHT", values = Points },
        { name = "relativePoint", kind = "string", default = "RIGHT", values = Points },
        { name = "x", kind = "number", default = -60, min = -10000, max = 10000 },
        { name = "y", kind = "number", default = 120, min = -10000, max = 10000 },
    },
    OnEnable = function()
        Warband.OnNearby = OnNearby
    end,
    OnDisable = function()
        Warband.OnNearby = nil
        wipe(Nearby)
        wipe(Pending)
        if FlushTimer then
            FlushTimer:Cancel()
            FlushTimer = nil
        end
        StopTicker()
        if Window then
            Window:Hide()
        end
    end,
})

Krew.Listen("NEARBY", function(sender, fields)
    if not Radar.Enabled then
        return
    end
    local zone = Warband.CleanText(fields[2]) ~= "" and Warband.CleanText(fields[2]) or Warband.CleanText(fields[1])
    for i = 3, #fields do
        local key, class, level = fields[i]:match("^([^;]+);([^;]*);([^;]*)$")
        if key and Warband.ValidKey(key) then
            Note({ key = key, class = Warband.CleanClass(class), level = Warband.CleanLevel(level), faction = "", guild = "" }, sender, zone)
        end
    end
end)
